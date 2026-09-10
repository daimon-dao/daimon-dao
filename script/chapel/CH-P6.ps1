# Day 5 -- P2.1d: execute. The 7-day timelock ran on a real clock from the
# queue block (ts 1788477722, 2026-09-03 23:22:02 UTC) to readyTimestamp
# 1789082522 (2026-09-10 23:22:02 UTC), and nothing shorter exists in the
# bytecode. Today execute(0) lets the Timelock call setFees(10,10,20) on
# the token: the 5% model (1/2/2) becomes the 4% model (1/1/2).
# Wallet: staker1, the same wallet that queued on day 4 (execute() is
# permissionless; the Timelock checks EXECUTOR_ROLE on the Governor, not
# on the EOA, so the signer changes nothing on-chain).
# Every claim is read back from STORAGE after the send, not just from the
# receipt: proposal.executed, Governor.state, operations(opId).executed
# and the four fee slots. The three events are decoded from the receipt
# itself and then read back the way the monitor will read them.
# Readiness is checked from the chain's own clock: if block.timestamp is
# still below readyTimestamp the runner reports the remaining seconds and
# STOPS -- it never waits in a loop. Any preflight mismatch or unexpected
# revert stops the runner with the full error; nothing is worked around.
. $PSScriptRoot\lib.ps1
Load-Keystores
$st = S

# Chain guard: this script must never speak to anything but Chapel.
$chainId = (cast chain-id --rpc-url $script:RPC)
if ("$chainId" -ne "97") { throw "WRONG CHAIN: chain-id=$chainId (expected 97) -- refusing to continue" }

$propId = "$($st.proposalId)"
if ($propId -ne "0") { throw "state.json proposalId=$propId (plan says 0)" }
$propCount = CQ $st.governor "proposalCount()(uint256)"
if ($propCount -ne 1) { throw "UNEXPECTED proposalCount=$propCount (plan says exactly 1)" }

# The day-4 record, as literal anchors (independent of state.json):
$OP_ID     = "0x0ff0f7d28022bd2a5baa7bfa9be60d682d044b945b50aca7a2b2ff9b1e77c6a2"
$READY_TS  = [System.Numerics.BigInteger]::Parse("1789082522")
$QUEUE_TS  = [System.Numerics.BigInteger]::Parse("1788477722")
if ("$($st.operationId)".ToLower() -ne $OP_ID) { throw "state.json operationId differs from the day-4 record" }
if ("$($st.readyTimestamp)" -ne "$READY_TS") { throw "state.json readyTimestamp differs from the day-4 record" }
if ("$($st.queueTimestamp)" -ne "$QUEUE_TS") { throw "state.json queueTimestamp differs from the day-4 record" }

$PROP_SIG = "proposals(uint256)(address,address,uint256,bytes,string,uint256,uint256,uint256,uint256,uint256,uint256,uint256,bool,bool,bool,bytes32,uint256)"
function ReadProposal {
  $lines = @(cast call $st.governor $PROP_SIG $propId --rpc-url $script:RPC)
  if ($LASTEXITCODE -ne 0 -or $lines.Count -lt 17) { throw "proposals($propId) read failed" }
  $tok = @(); foreach ($l in $lines) { $tok += ($l.Trim() -split "\s+")[0] }
  return @{
    proposer = $tok[0]; target = $tok[1]; value = $tok[2]; data = $tok[3]
    description = $lines[4].Trim()
    forVotes = [System.Numerics.BigInteger]::Parse($tok[9])
    againstVotes = [System.Numerics.BigInteger]::Parse($tok[10])
    abstainVotes = [System.Numerics.BigInteger]::Parse($tok[11])
    canceled = $tok[12]; executed = $tok[13]; queued = $tok[14]
    salt = $tok[15]
  }
}
function ReadOperation { param($opId)
  $lines = @(cast call $st.timelock "operations(bytes32)(uint256,bool,bool)" $opId --rpc-url $script:RPC)
  if ($LASTEXITCODE -ne 0 -or $lines.Count -lt 3) { throw "operations($opId) read failed" }
  $tok = @(); foreach ($l in $lines) { $tok += ($l.Trim() -split "\s+")[0] }
  return @{ readyTimestamp = [System.Numerics.BigInteger]::Parse($tok[0]); executed = $tok[1]; canceled = $tok[2] }
}
function ReadFees {
  return @{
    taxFee = CQ $st.token "taxFee()(uint256)"
    buybackFee = CQ $st.token "buybackFee()(uint256)"
    marketingFee = CQ $st.token "marketingFee()(uint256)"
    liquidityFee = CQ $st.token "liquidityFee()(uint256)"
  }
}
function FeesStr { param($f) return "taxFee=$($f.taxFee) buybackFee=$($f.buybackFee) marketingFee=$($f.marketingFee) liquidityFee=$($f.liquidityFee)" }
function UtcOf { param($unix) return [DateTimeOffset]::FromUnixTimeSeconds([int64]"$unix").UtcDateTime.ToString("yyyy-MM-dd HH:mm:ss") }
function HexToBig { param([string]$h) return [System.Numerics.BigInteger]::Parse("0" + ($h -replace "^0x", ""), "AllowHexSpecifier") }
# Log scan in 50000-block chunks (the public RPC caps eth_getLogs at 50000
# blocks AND prunes older history): returns the logs over the chunks that
# answered, plus the first block of the readable range.
function ScanLogsChunked { param($addr, $sig, [int64]$from, [int64]$to)
  $logs = @(); $errs = 0; $firstReadable = -1
  $prev = $ErrorActionPreference; $ErrorActionPreference = "Continue"
  while ($from -le $to) {
    $end = [Math]::Min($from + 49999, $to)
    $r = (cast logs --address $addr $sig --from-block $from --to-block $end --rpc-url $script:RPC --json 2>&1 | Out-String)
    if ($LASTEXITCODE -ne 0) { $errs++ }
    else {
      if ($firstReadable -lt 0) { $firstReadable = $from }
      $j = $r | ConvertFrom-Json; if ($null -ne $j) { $logs += [array]$j }
    }
    $from = $end + 1
  }
  $ErrorActionPreference = $prev
  return @{ logs = $logs; count = $logs.Count; errorChunks = $errs; firstReadable = $firstReadable }
}
# A send that is EXPECTED to revert, returning the raw cast error (path and
# keystore name scrubbed) next to the classification, so the exact error
# lands in the journal verbatim.
function Expect-Revert-Raw { param($who, $to, $sig, [string[]]$sendArgs = @())
  $ks = $script:KsMap.accounts.$who
  $pf = $script:KsMap.passwordFile
  $prev = $ErrorActionPreference; $ErrorActionPreference = "Continue"
  $r = (cast send $to $sig @sendArgs --account $ks --password-file $pf --rpc-url $script:RPC --json 2>&1 | Out-String)
  $c = $LASTEXITCODE; $ErrorActionPreference = $prev
  $raw = ($r -replace '\s+', ' ').Trim()
  $raw = $raw.Replace($pf, "<password-file>").Replace($ks, "<keystore>").Replace("|", "/")
  if ($c -eq 0) {
    $j = $r | ConvertFrom-Json
    if ($j.status -eq "0x1") { return @{ reverted = $false; raw = "DID-NOT-REVERT ($($j.transactionHash))" } }
  }
  return @{ reverted = $true; raw = $raw }
}
$ZERO32 = "0x0000000000000000000000000000000000000000000000000000000000000000"
$CAMPAIGN_FROM = 127613000   # first block of the campaign (before P1.1)

Log-Scenario "P2.1d" "Governance cycle, day 5: execute -- the 7-day timelock has elapsed on a real clock"

# --- P2.1d.1: preflight from live state -- the proposal
$p = ReadProposal
$latestBlock = [int64](cast block latest -f number --rpc-url $script:RPC)
$now = [System.Numerics.BigInteger]::Parse((cast block $latestBlock -f timestamp --rpc-url $script:RPC))
$state0 = CQRaw $st.governor "state(uint256)(uint8)" @($propId)
$expectedCalldata = (cast calldata "setFees(uint256,uint256,uint256)" 10 10 20)
$calldataOk = ($p.data.ToLower() -eq $expectedCalldata.ToLower())
$tallyOk = ("$($p.forVotes)" -eq "20000000000000000000000000000" -and "$($p.againstVotes)" -eq "7500000000000000000000000000" -and "$($p.abstainVotes)" -eq "5000000000000000000000000000")
$flagsOk = ($p.queued -eq "true" -and $p.executed -eq "false" -and $p.canceled -eq "false")
$ok1 = ($chainId -eq "97" -and $state0 -eq "4" -and $tallyOk -and $flagsOk -and $calldataOk -and $p.target.ToLower() -eq "$($st.token)".ToLower() -and "$($p.value)" -eq "0" -and $p.salt.ToLower() -eq "$($st.timelockSalt)".ToLower())
Log-Step "P2.1d.1" "Preflight from live state: chain, proposal $propId, flags, calldata" "chain 97; state Queued (4); tally 20B/7.5B/5B exact; queued=true executed=false canceled=false; data == setFees(10,10,20); target == token; value 0; salt == day-4 timelockSalt" "chain=$chainId, state=$state0 (4=Queued), for/against/abstain=$($p.forVotes)/$($p.againstVotes)/$($p.abstainVotes), queued=$($p.queued) executed=$($p.executed) canceled=$($p.canceled), calldataMatch=$calldataOk, target=$($p.target), value=$($p.value), salt=$($p.salt)" "-" $(if ($ok1) { "PASS" } else { "DEVIATION" })
if (-not $ok1) { throw "preflight (proposal) failed -- stopping before execute" }

# --- P2.1d.2: preflight -- the Timelock: the operation is the day-4 one and its clock has elapsed
$EXECUTOR_ROLE = CQRaw $st.timelock "EXECUTOR_ROLE()(bytes32)"
$govIsExecutor = CQRaw $st.timelock "hasRole(bytes32,address)(bool)" @($EXECUTOR_ROLE, $st.governor)
$opId = CQRaw $st.timelock "hashOperation(address,uint256,bytes,bytes32,bytes32)(bytes32)" @($p.target, "$($p.value)", $p.data, $ZERO32, $p.salt)
$op0 = ReadOperation $opId
$remaining = $op0.readyTimestamp - $now
$ready = ($now -ge $op0.readyTimestamp)
$ok2 = ($opId.ToLower() -eq $OP_ID -and $op0.readyTimestamp -eq $READY_TS -and $op0.executed -eq "false" -and $op0.canceled -eq "false" -and $govIsExecutor -eq "true" -and $ready)
Log-Step "P2.1d.2" "Preflight from live state: the Timelock operation and the chain's own clock" "opId == 0x0ff0...c6a2 (day 4); readyTimestamp == 1789082522 (2026-09-10 23:22:02 UTC); executed=false; canceled=false; governor holds EXECUTOR_ROLE; latest block.timestamp >= readyTimestamp" "opId=$opId, readyTimestamp=$($op0.readyTimestamp) ($(UtcOf $op0.readyTimestamp) UTC), executed=$($op0.executed), canceled=$($op0.canceled), governorIsExecutor=$govIsExecutor, latest block $latestBlock ts=$now ($(UtcOf $now) UTC), ready=$ready, readyTimestamp-now=$remaining s" "-" $(if ($ok2) { "PASS" } else { "DEVIATION" })
if (-not $ready) { throw "NOT READY: the Timelock clock has $remaining s to run (ready at $(UtcOf $op0.readyTimestamp) UTC, chain now $(UtcOf $now) UTC) -- stopping, no retry" }
if (-not $ok2) { throw "preflight (timelock) failed -- stopping before execute" }

# --- P2.1d.3: preflight -- fees before, the 5% model
$fees0 = ReadFees
$ok3 = ($fees0.taxFee -eq 10 -and $fees0.buybackFee -eq 20 -and $fees0.marketingFee -eq 20 -and $fees0.liquidityFee -eq 40)
Log-Step "P2.1d.3" "Fees read from the token BEFORE execute" "taxFee 10, buybackFee 20, marketingFee 20 (per mille) -- the 5% model; liquidityFee == buybackFee + marketingFee == 40" "$(FeesStr $fees0)" "-" $(if ($ok3) { "PASS" } else { "DEVIATION" })
if (-not $ok3) { throw "preflight (fees) failed -- stopping before execute" }

# --- P2.1d.4: execute(0) from staker1 (the day-4 wallet) -- the one signed send of the day
$fromBlock = $latestBlock
$h = Send "staker1" $st.governor "execute(uint256)" @($propId)
$rcpt = (cast receipt $h.hash --rpc-url $script:RPC --json | Out-String) | ConvertFrom-Json
$xBlock = HexToBig "$($rcpt.blockNumber)"
$xTs = [System.Numerics.BigInteger]::Parse((cast block "$xBlock" -f timestamp --rpc-url $script:RPC))
$px = ReadProposal
$stateX = CQRaw $st.governor "state(uint256)(uint8)" @($propId)
$opX = ReadOperation $opId
$ok4 = ($rcpt.status -eq "0x1" -and $px.executed -eq "true" -and $px.queued -eq "true" -and $px.canceled -eq "false" -and $stateX -eq "5" -and $opX.executed -eq "true" -and $opX.canceled -eq "false" -and $opX.readyTimestamp -eq $READY_TS -and "$($rcpt.from)".ToLower() -eq $script:AddrBook.staker1.ToLower())
Log-Step "P2.1d.4" "staker1 (the day-4 wallet) calls execute($propId)" "receipt status 1; from storage: proposal executed=true (queued stays true, canceled false); Governor.state == Executed (5); operations(opId).executed == true, canceled false, readyTimestamp unchanged" "status=$($rcpt.status), from=$($rcpt.from), block=$xBlock (ts=$xTs = $(UtcOf $xTs) UTC), proposal executed=$($px.executed) queued=$($px.queued) canceled=$($px.canceled), state=$stateX (5=Executed), operation executed=$($opX.executed) canceled=$($opX.canceled) readyTimestamp=$($opX.readyTimestamp); gas=$($h.gasUsed)" $h.hash $(if ($ok4) { "PASS" } else { "DEVIATION" })

# --- P2.1d.5: fees after, the 4% model
$fees1 = ReadFees
$ok5 = ($fees1.taxFee -eq 10 -and $fees1.buybackFee -eq 10 -and $fees1.marketingFee -eq 20 -and $fees1.liquidityFee -eq 30)
Log-Step "P2.1d.5" "Fees read from the token AFTER execute" "taxFee 10, buybackFee 10, marketingFee 20 -- the 4% model; liquidityFee recomputed to 30" "$(FeesStr $fees1)" "-" $(if ($ok5) { "PASS" } else { "DEVIATION" })

# --- P2.1d.6: the real delay, exact to the second
$sinceQueue = $xTs - $QUEUE_TS
$pastReady = $xTs - $READY_TS
$ok6 = ($sinceQueue -ge 604800 -and $pastReady -ge 0)
Log-Step "P2.1d.6" "The delay actually elapsed on the chain's clock" "execution ts - scheduling ts (1788477722) >= 604800 s; execution ts >= readyTimestamp (1789082522)" "execution ts=$xTs, scheduling ts=$QUEUE_TS, elapsed=$sinceQueue s (= 604800 + $pastReady); execution ts - readyTimestamp=$pastReady s" "-" $(if ($ok6) { "PASS" } else { "DEVIATION" })

# --- P2.1d.7: the three events, decoded from the receipt itself
$topicFU = (cast sig-event "FeesUpdated(uint256,uint256,uint256)")
$topicCE = (cast sig-event "CallExecuted(bytes32,address,uint256,bytes)")
$topicPE = (cast sig-event "ProposalExecuted(uint256)")
$evFU = $null; $evCE = $null; $evPE = $null; $nLogs = 0; $order = @()
foreach ($lg in [array]$rcpt.logs) {
  $nLogs++
  $t0 = "$($lg.topics[0])".ToLower()
  $a = "$($lg.address)".ToLower()
  if ($t0 -eq $topicFU.ToLower() -and $a -eq "$($st.token)".ToLower()) { $evFU = $lg; $order += "FeesUpdated" }
  elseif ($t0 -eq $topicCE.ToLower() -and $a -eq "$($st.timelock)".ToLower()) { $evCE = $lg; $order += "CallExecuted" }
  elseif ($t0 -eq $topicPE.ToLower() -and $a -eq "$($st.governor)".ToLower()) { $evPE = $lg; $order += "ProposalExecuted" }
  else { $order += "UNEXPECTED($a $t0)" }
}
$fuTax = "?"; $fuBuy = "?"; $fuMk = "?"; $ceId = "?"; $ceTarget = "?"; $ceValue = "?"; $ceData = "?"; $peId = "?"
if ($evFU) {
  $d = "$($evFU.data)" -replace "^0x", ""
  $fuTax = HexToBig $d.Substring(0, 64); $fuBuy = HexToBig $d.Substring(64, 64); $fuMk = HexToBig $d.Substring(128, 64)
}
if ($evCE) {
  $ceId = "$($evCE.topics[1])".ToLower()
  $d = "$($evCE.data)" -replace "^0x", ""
  $ceTarget = "0x" + $d.Substring(24, 40)
  $ceValue = HexToBig $d.Substring(64, 64)
  $off = [int]"$(HexToBig $d.Substring(128, 64))"
  $len = [int]"$(HexToBig $d.Substring($off * 2, 64))"
  $ceData = "0x" + $d.Substring($off * 2 + 64, $len * 2)
}
if ($evPE) { $peId = HexToBig "$($evPE.topics[1])" }
$orderStr = ($order -join " > ")
$ok7 = ($nLogs -eq 3 -and $evFU -and $evCE -and $evPE -and "$fuTax" -eq "10" -and "$fuBuy" -eq "10" -and "$fuMk" -eq "20" -and $ceId -eq $OP_ID -and $ceTarget.ToLower() -eq "$($st.token)".ToLower() -and "$ceValue" -eq "0" -and $ceData.ToLower() -eq $p.data.ToLower() -and "$peId" -eq $propId -and $orderStr -eq "FeesUpdated > CallExecuted > ProposalExecuted")
Log-Step "P2.1d.7" "The three events decoded from the receipt" "exactly 3 logs, innermost first: FeesUpdated(10,10,20) from the token; CallExecuted(id == opId, target == token, value 0, data == setFees(10,10,20)) from the timelock; ProposalExecuted(id=$propId) from the governor" "logs=$nLogs, order: $orderStr; FeesUpdated taxFee=$fuTax buybackFee=$fuBuy marketingFee=$fuMk; CallExecuted id=$ceId target=$ceTarget value=$ceValue dataMatch=$($ceData.ToLower() -eq $p.data.ToLower()); ProposalExecuted id=$peId" $h.hash $(if ($ok7) { "PASS" } else { "DEVIATION" })

# --- P2.1d.8: the global invariant, one more time, from balances AND from the event query
$mkDmn = CQ $st.token "balanceOf(address)(uint256)" @($script:MARKETING)
$mkNat = Bal $script:MARKETING
$mkTopic = "0x000000000000000000000000" + $script:MARKETING.Substring(2).ToLower()
$latestA = [int64](cast block latest -f number --rpc-url $script:RPC)
$xfers = ScanLogsChunked $st.token "Transfer(address,address,uint256)" $CAMPAIGN_FROM $latestA
$toMk = @(); foreach ($ev in $xfers.logs) { if ($ev.topics.Count -ge 3 -and "$($ev.topics[2])".ToLower() -eq $mkTopic) { $toMk += $ev } }
$ok8 = ($mkDmn -eq 0 -and $mkNat -eq 0 -and $toMk.Count -eq 0)
Log-Step "P2.1d.8" "Marketing wallet after the fee change: balances and inbound Transfer events" "DMN 0, native 0; zero Transfer events into the wallet over the RPC's readable range (the alert that must never fire)" "DMN=$mkDmn, native=$mkNat; token Transfers scanned=$($xfers.count) (readable from block $($xfers.firstReadable) to $latestA; $($xfers.errorChunks) pruned chunks below it), transfers to marketing=$($toMk.Count); programmatic invariant checks so far=$((S).invariantChecks)" "-" $(if ($ok8) { "PASS" } else { "DEVIATION" })

# --- P2.1d.9: a second execute is refused at the Governor's own level
$rv = Expect-Revert-Raw "staker1" $st.governor "execute(uint256)" @($propId)
$selAE = (cast sig "AlreadyExecuted()")
$isAE = ($rv.reverted -and ($rv.raw -match "AlreadyExecuted" -or $rv.raw -match [regex]::Escape($selAE)))
Log-Step "P2.1d.9" "staker1 tries execute($propId) a second time" "refused: AlreadyExecuted (selector $selAE) -- p.executed is the first check in Governor.execute, before state() and before the Timelock's OperationAlreadyExecuted" "reverted=$($rv.reverted); raw: $($rv.raw)" "-" $(if ($isAE) { "PASS" } else { "DEVIATION" })

# --- P3.17 / P3.18 / P3.19: the three events read back the way the monitor will read them
$latest2 = [int64](cast block latest -f number --rpc-url $script:RPC)
$rbFU = ScanLogsChunked $st.token "FeesUpdated(uint256,uint256,uint256)" $fromBlock $latest2
$rbCE = ScanLogsChunked $st.timelock "CallExecuted(bytes32,address,uint256,bytes)" $fromBlock $latest2
$rbPE = ScanLogsChunked $st.governor "ProposalExecuted(uint256)" $fromBlock $latest2
Log-Step "P3.17" "Read back: FeesUpdated(uint256,uint256,uint256) on token (the P3.6 follow-up)" "exactly 1 -- today's execute; P3.6 expected 0 on day 1 for exactly this reason" "found=$($rbFU.count) (blocks $fromBlock-$latest2, unreadable chunks=$($rbFU.errorChunks))" "-" $(if ($rbFU.count -eq 1 -and $rbFU.errorChunks -eq 0) { "PASS" } else { "DEVIATION" })
Log-Step "P3.18" "Read back: CallExecuted(bytes32,address,uint256,bytes) on timelock" "exactly 1 -- the first operation the Timelock has ever executed" "found=$($rbCE.count) (blocks $fromBlock-$latest2, unreadable chunks=$($rbCE.errorChunks))" "-" $(if ($rbCE.count -eq 1 -and $rbCE.errorChunks -eq 0) { "PASS" } else { "DEVIATION" })
Log-Step "P3.19" "Read back: ProposalExecuted(uint256) on governor" "exactly 1 -- proposal $propId" "found=$($rbPE.count) (blocks $fromBlock-$latest2, unreadable chunks=$($rbPE.errorChunks))" "-" $(if ($rbPE.count -eq 1 -and $rbPE.errorChunks -eq 0) { "PASS" } else { "DEVIATION" })

# State: the execution record
$stFix = S
$stFix | Add-Member -NotePropertyName executeTx -NotePropertyValue $h.hash -Force
$stFix | Add-Member -NotePropertyName executeBlock -NotePropertyValue "$xBlock" -Force
$stFix | Add-Member -NotePropertyName executeTimestamp -NotePropertyValue "$xTs" -Force
$stFix | Add-Member -NotePropertyName executeDelaySeconds -NotePropertyValue "$sinceQueue" -Force
$stFix | Add-Member -NotePropertyName feesAfter -NotePropertyValue "$($fees1.taxFee)/$($fees1.buybackFee)/$($fees1.marketingFee)" -Force
Save-State $stFix

Write-Output "P6 COMPLETE proposal=$propId tx=$($h.hash) block=$xBlock ts=$xTs ($(UtcOf $xTs) UTC)"
Write-Output "elapsed since queue=$sinceQueue s (readyTimestamp slack $pastReady s); state=$stateX; op executed=$($opX.executed)"
Write-Output "fees before: $(FeesStr $fees0)"
Write-Output "fees after:  $(FeesStr $fees1)"
Write-Output "events: $orderStr | FeesUpdated($fuTax,$fuBuy,$fuMk) | CallExecuted id=$ceId | ProposalExecuted id=$peId"
Write-Output "second execute: $($rv.raw)"
