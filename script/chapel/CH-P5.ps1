# Day 4 -- P2.1c: queue. Voting closed at voteEnd (2026-09-03 00:17:59 UTC)
# and the clock, not a transaction, moved proposal 0 to Succeeded. Today
# queue(0) hands the operation to the Timelock and the 7-day delay starts
# its REAL clock: readyTimestamp = scheduling-block timestamp + 604800,
# and nothing shorter exists in the bytecode (MIN_DELAY is a constant).
# Wallet: staker1, the proposer. The plan says "the designated wallet"
# without naming it in any repository artefact; the July campaign, which
# this level replays (proposal 0 on a real clock), queued from the
# proposer, and queue() is permissionless so the caller changes nothing
# on-chain (operation id, eta and events are sender-independent). Recorded
# as an assumption, not hidden.
# "Pending operations: 0" is proven from STORAGE, not from logs: the public
# RPC prunes eth_getLogs history beyond its most recent ~50000 blocks, so an
# event scan over the campaign is not admissible evidence here. The
# Timelock schedules only through PROPOSER_ROLE (= the Governor, 34/34 on
# day 1), the Governor schedules only from queue(), exactly one proposal
# exists and its queued flag is false, and the expected operation slot is
# empty. The log scan is still run and reported, with its readable range.
# Nothing is retried, nothing is worked around: any preflight mismatch or
# revert stops the runner with the full error.
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

$PROP_SIG = "proposals(uint256)(address,address,uint256,bytes,string,uint256,uint256,uint256,uint256,uint256,uint256,uint256,bool,bool,bool,bytes32,uint256)"
function ReadProposal {
  $lines = @(cast call $st.governor $PROP_SIG $propId --rpc-url $script:RPC)
  if ($LASTEXITCODE -ne 0 -or $lines.Count -lt 17) { throw "proposals($propId) read failed" }
  $tok = @(); foreach ($l in $lines) { $tok += ($l.Trim() -split "\s+")[0] }
  return @{
    proposer = $tok[0]; target = $tok[1]; value = $tok[2]; data = $tok[3]
    description = $lines[4].Trim()
    snapshotBlock = [System.Numerics.BigInteger]::Parse($tok[5])
    snapTotal = [System.Numerics.BigInteger]::Parse($tok[6])
    voteStart = [System.Numerics.BigInteger]::Parse($tok[7])
    voteEnd = [System.Numerics.BigInteger]::Parse($tok[8])
    forVotes = [System.Numerics.BigInteger]::Parse($tok[9])
    againstVotes = [System.Numerics.BigInteger]::Parse($tok[10])
    abstainVotes = [System.Numerics.BigInteger]::Parse($tok[11])
    canceled = $tok[12]; executed = $tok[13]; queued = $tok[14]
    salt = $tok[15]
    quorumBps = [System.Numerics.BigInteger]::Parse($tok[16])
  }
}
function ReadOperation { param($opId)
  $lines = @(cast call $st.timelock "operations(bytes32)(uint256,bool,bool)" $opId --rpc-url $script:RPC)
  if ($LASTEXITCODE -ne 0 -or $lines.Count -lt 3) { throw "operations($opId) read failed" }
  $tok = @(); foreach ($l in $lines) { $tok += ($l.Trim() -split "\s+")[0] }
  return @{ readyTimestamp = [System.Numerics.BigInteger]::Parse($tok[0]); executed = $tok[1]; canceled = $tok[2] }
}
function UtcOf { param($unix) return [DateTimeOffset]::FromUnixTimeSeconds([int64]"$unix").UtcDateTime.ToString("yyyy-MM-dd HH:mm:ss") }
function HexToBig { param([string]$h) return [System.Numerics.BigInteger]::Parse("0" + ($h -replace "^0x", ""), "AllowHexSpecifier") }
# Log scan in 50000-block chunks (the public RPC caps eth_getLogs at 50000
# blocks AND prunes older history): returns the count over the chunks that
# answered, plus the first block of the readable range.
function CountLogsChunked { param($addr, $sig, [int64]$from, [int64]$to)
  $total = 0; $errs = 0; $firstReadable = -1
  $prev = $ErrorActionPreference; $ErrorActionPreference = "Continue"
  while ($from -le $to) {
    $end = [Math]::Min($from + 49999, $to)
    $r = (cast logs --address $addr $sig --from-block $from --to-block $end --rpc-url $script:RPC --json 2>&1 | Out-String)
    if ($LASTEXITCODE -ne 0) { $errs++ }
    else {
      if ($firstReadable -lt 0) { $firstReadable = $from }
      $j = $r | ConvertFrom-Json; if ($null -ne $j) { $total += ([array]$j).Count }
    }
    $from = $end + 1
  }
  $ErrorActionPreference = $prev
  return @{ count = $total; errorChunks = $errs; firstReadable = $firstReadable }
}
$ZERO32 = "0x0000000000000000000000000000000000000000000000000000000000000000"
$CAMPAIGN_FROM = 127613000   # first block of the campaign (before P1.1)

Log-Scenario "P2.1c" "Governance cycle, day 4: queue -- the 7-day timelock starts its real clock"

# --- P2.1c.1: preflight from live state -- the proposal
$p = ReadProposal
$now = [System.Numerics.BigInteger]::Parse((cast block latest -f timestamp --rpc-url $script:RPC))
$state0 = CQRaw $st.governor "state(uint256)(uint8)" @($propId)
$expectedCalldata = (cast calldata "setFees(uint256,uint256,uint256)" 10 10 20)
$calldataOk = ($p.data.ToLower() -eq $expectedCalldata.ToLower())
$tallyOk = ("$($p.forVotes)" -eq "20000000000000000000000000000" -and "$($p.againstVotes)" -eq "7500000000000000000000000000" -and "$($p.abstainVotes)" -eq "5000000000000000000000000000")
$flagsOk = ($p.queued -eq "false" -and $p.executed -eq "false" -and $p.canceled -eq "false")
$ok1 = ($chainId -eq "97" -and $state0 -eq "3" -and ($now -gt $p.voteEnd) -and $tallyOk -and $flagsOk -and $calldataOk -and $p.target.ToLower() -eq "$($st.token)".ToLower() -and "$($p.value)" -eq "0")
Log-Step "P2.1c.1" "Preflight from live state: chain, proposal $propId, outcome, flags, calldata" "chain 97; state Succeeded (3); now > voteEnd; tally 20B/7.5B/5B exact; queued=executed=canceled=false; data == setFees(10,10,20); target == token; value 0" "chain=$chainId, state=$state0 (3=Succeeded), voteEnd=$(UtcOf $p.voteEnd) UTC (now $(UtcOf $now)), for/against/abstain=$($p.forVotes)/$($p.againstVotes)/$($p.abstainVotes), queued=$($p.queued) executed=$($p.executed) canceled=$($p.canceled), calldataMatch=$calldataOk, target=$($p.target), value=$($p.value), salt=$($p.salt)" "-" $(if ($ok1) { "PASS" } else { "DEVIATION" })
if (-not $ok1) { throw "preflight (proposal) failed -- stopping before queue" }

# --- P2.1c.2: preflight -- the Timelock: delay is the 7-day floor, nothing pending
$minDelay = CQ $st.timelock "getMinDelay()(uint256)"
$MIN_DELAY = CQ $st.timelock "MIN_DELAY()(uint256)"
$PROPOSER_ROLE = CQRaw $st.timelock "PROPOSER_ROLE()(bytes32)"
$govIsProposer = CQRaw $st.timelock "hasRole(bytes32,address)(bool)" @($PROPOSER_ROLE, $st.governor)
$opId = CQRaw $st.timelock "hashOperation(address,uint256,bytes,bytes32,bytes32)(bytes32)" @($p.target, "$($p.value)", $p.data, $ZERO32, $p.salt)
$opIdLocal = (cast keccak (cast abi-encode "f(address,uint256,bytes,bytes32,bytes32)" $p.target "$($p.value)" $p.data $ZERO32 $p.salt))
$op0 = ReadOperation $opId
$latestBlock = [int64](cast block latest -f number --rpc-url $script:RPC)
$sched = CountLogsChunked $st.timelock "CallScheduled(bytes32,address,uint256,bytes,uint256)" $CAMPAIGN_FROM $latestBlock
$ok2 = ($minDelay -eq 604800 -and $MIN_DELAY -eq 604800 -and $govIsProposer -eq "true" -and $opId.ToLower() -eq $opIdLocal.ToLower() -and $op0.readyTimestamp -eq 0 -and $op0.executed -eq "false" -and $op0.canceled -eq "false" -and $sched.count -eq 0)
Log-Step "P2.1c.2" "Preflight from live state: the Timelock before queue (pending operations: 0, proven from storage)" "getMinDelay == MIN_DELAY == 604800; governor holds PROPOSER_ROLE (the only scheduling path, and it schedules only from queue: one proposal, queued=false); operation id (target, 0, data, predecessor 0x0, salt) computed on-chain == local keccak; its slot empty (readyTimestamp 0); CallScheduled events over the RPC's readable range: 0" "getMinDelay=$minDelay, MIN_DELAY=$MIN_DELAY, governorIsProposer=$govIsProposer, opId=$opId, localMatch=$($opId.ToLower() -eq $opIdLocal.ToLower()), slot readyTimestamp=$($op0.readyTimestamp) executed=$($op0.executed) canceled=$($op0.canceled), CallScheduled count=$($sched.count) (readable from block $($sched.firstReadable) to $latestBlock; $($sched.errorChunks) pruned chunks below it)" "-" $(if ($ok2) { "PASS" } else { "DEVIATION" })
if (-not $ok2) { throw "preflight (timelock) failed -- stopping before queue" }

# --- P2.1c.3: queue(0) from staker1 (the proposer) -- the one signed send of the day
$fromBlock = $latestBlock
$h = Send "staker1" $st.governor "queue(uint256)" @($propId)
$rcpt = (cast receipt $h.hash --rpc-url $script:RPC --json | Out-String) | ConvertFrom-Json
$qBlock = HexToBig "$($rcpt.blockNumber)"
$qTs = [System.Numerics.BigInteger]::Parse((cast block "$qBlock" -f timestamp --rpc-url $script:RPC))
$pq = ReadProposal
$stateQ = CQRaw $st.governor "state(uint256)(uint8)" @($propId)
$ok3 = ($rcpt.status -eq "0x1" -and $pq.queued -eq "true" -and $pq.executed -eq "false" -and $pq.canceled -eq "false" -and $stateQ -eq "4" -and "$($rcpt.from)".ToLower() -eq $script:AddrBook.staker1.ToLower())
Log-Step "P2.1c.3" "staker1 (the proposer) calls queue($propId)" "receipt status 1; proposal queued flag true; state Queued (4); executed/canceled untouched" "status=$($rcpt.status), from=$($rcpt.from), block=$qBlock (ts=$qTs = $(UtcOf $qTs) UTC), queued=$($pq.queued) executed=$($pq.executed) canceled=$($pq.canceled), state=$stateQ (4=Queued); gas=$($h.gasUsed)" $h.hash $(if ($ok3) { "PASS" } else { "DEVIATION" })

# --- P2.1c.4: the Timelock operation, read from storage, delta exact to the second
$op1 = ReadOperation $opId
$delta = $op1.readyTimestamp - $qTs
$ok4 = ($op1.readyTimestamp -gt 0 -and $delta -eq 604800 -and $op1.executed -eq "false" -and $op1.canceled -eq "false")
Log-Step "P2.1c.4" "operations(opId) read back from the Timelock" "readyTimestamp == scheduling-block timestamp + 604800 EXACTLY (7 real days); executed=false; canceled=false" "readyTimestamp=$($op1.readyTimestamp) ($(UtcOf $op1.readyTimestamp) UTC), block ts=$qTs, delta=$delta s, executed=$($op1.executed), canceled=$($op1.canceled)" "-" $(if ($ok4) { "PASS" } else { "DEVIATION" })

# --- P2.1c.5: the two events, decoded from the receipt itself
$topicPQ = (cast sig-event "ProposalQueued(uint256,uint256)")
$topicCS = (cast sig-event "CallScheduled(bytes32,address,uint256,bytes,uint256)")
$evPQ = $null; $evCS = $null; $nLogs = 0
foreach ($lg in [array]$rcpt.logs) {
  $nLogs++
  $t0 = "$($lg.topics[0])".ToLower()
  if ($t0 -eq $topicPQ.ToLower() -and "$($lg.address)".ToLower() -eq "$($st.governor)".ToLower()) { $evPQ = $lg }
  if ($t0 -eq $topicCS.ToLower() -and "$($lg.address)".ToLower() -eq "$($st.timelock)".ToLower()) { $evCS = $lg }
}
$pqId = "?"; $pqEta = "?"; $pqEtaUtc = "?"; $csId = "?"; $csTarget = "?"; $csValue = "?"; $csDelay = "?"; $csData = "?"
if ($evPQ) {
  $pqId = HexToBig "$($evPQ.topics[1])"
  $pqEta = HexToBig "$($evPQ.data)"
  $pqEtaUtc = UtcOf $pqEta
}
if ($evCS) {
  $csId = "$($evCS.topics[1])".ToLower()
  $d = "$($evCS.data)" -replace "^0x", ""
  $csTarget = "0x" + $d.Substring(24, 40)
  $csValue = HexToBig $d.Substring(64, 64)
  $off = [int]"$(HexToBig $d.Substring(128, 64))"
  $csDelay = HexToBig $d.Substring(192, 64)
  $len = [int]"$(HexToBig $d.Substring($off * 2, 64))"
  $csData = "0x" + $d.Substring($off * 2 + 64, $len * 2)
}
$ok5 = ($nLogs -eq 2 -and $evPQ -and $evCS -and "$pqId" -eq $propId -and "$pqEta" -eq "$($op1.readyTimestamp)" -and $csId -eq $opId.ToLower() -and $csTarget.ToLower() -eq "$($st.token)".ToLower() -and "$csValue" -eq "0" -and "$csDelay" -eq "604800" -and $csData.ToLower() -eq $p.data.ToLower())
Log-Step "P2.1c.5" "The two events decoded from the receipt" "exactly 2 logs: ProposalQueued(id=$propId, eta == readyTimestamp) from the governor; CallScheduled(id == opId, target == token, value 0, data == setFees(10,10,20), delay 604800) from the timelock" "logs=$nLogs; ProposalQueued id=$pqId eta=$pqEta ($pqEtaUtc UTC); CallScheduled id=$csId target=$csTarget value=$csValue delay=$csDelay dataMatch=$($csData.ToLower() -eq $p.data.ToLower())" $h.hash $(if ($ok5) { "PASS" } else { "DEVIATION" })

# --- P2.1c.6: a second queue is refused at the Governor's own level (#7)
$rv = Expect-Revert "stranger" $st.governor "queue(uint256)" @($propId) "ProposalAlreadyQueued()"
Log-Step "P2.1c.6" "The stranger tries queue($propId) again" "refused: ProposalAlreadyQueued -- the Governor rejects it itself, before the Timelock's OperationAlreadyScheduled" "$rv" "-" $(if ($rv -match "ProposalAlreadyQueued") { "PASS" } else { "DEVIATION" })

# --- P2.1c.7: execute is refused during the delay -- the 7 days are real
$rv2 = Expect-Revert "staker1" $st.governor "execute(uint256)" @($propId) "TooEarly()"
Log-Step "P2.1c.7" "staker1 tries execute($propId) inside the delay" "refused: TooEarly from the Timelock (state is Queued, so the Governor lets the call reach the Timelock, which holds the clock)" "$rv2" "-" $(if ($rv2 -match "TooEarly") { "PASS" } else { "DEVIATION" })

Log-Note "Wallet choice, recorded as an assumption: the plan says queue(0) comes from 'the designated wallet' without naming it in any repository artefact. The July campaign, which this level replays (proposal 0 on a real clock), queued from the proposer; queue() is permissionless (Level 1 D4.3, July proposal 2), and the operation id, readyTimestamp and both events are sender-independent, so the caller cannot change any on-chain value verified above. staker1, the proposer, signed. If the plan names another wallet, the deviation is the signer of one transaction and nothing else."

# --- P3.15 / P3.16: the two events read back the way the monitor will read them
$latest2 = [int64](cast block latest -f number --rpc-url $script:RPC)
$rbPQ = CountLogsChunked $st.governor "ProposalQueued(uint256,uint256)" $fromBlock $latest2
$rbCS = CountLogsChunked $st.timelock "CallScheduled(bytes32,address,uint256,bytes,uint256)" $fromBlock $latest2
Log-Step "P3.15" "Read back: ProposalQueued(uint256,uint256) on governor" "exactly 1 -- today's queue" "found=$($rbPQ.count) (blocks $fromBlock-$latest2, unreadable chunks=$($rbPQ.errorChunks))" "-" $(if ($rbPQ.count -eq 1 -and $rbPQ.errorChunks -eq 0) { "PASS" } else { "DEVIATION" })
Log-Step "P3.16" "Read back: CallScheduled(bytes32,address,uint256,bytes,uint256) on timelock" "exactly 1 -- the first operation the Timelock has ever scheduled" "found=$($rbCS.count) (blocks $fromBlock-$latest2, unreadable chunks=$($rbCS.errorChunks))" "-" $(if ($rbCS.count -eq 1 -and $rbCS.errorChunks -eq 0) { "PASS" } else { "DEVIATION" })

# State: the operation the execute day will need
$stFix = S
$stFix | Add-Member -NotePropertyName queueTx -NotePropertyValue $h.hash -Force
$stFix | Add-Member -NotePropertyName queueBlock -NotePropertyValue "$qBlock" -Force
$stFix | Add-Member -NotePropertyName queueTimestamp -NotePropertyValue "$qTs" -Force
$stFix | Add-Member -NotePropertyName operationId -NotePropertyValue $opId.ToLower() -Force
$stFix | Add-Member -NotePropertyName timelockSalt -NotePropertyValue $p.salt.ToLower() -Force
$stFix | Add-Member -NotePropertyName readyTimestamp -NotePropertyValue "$($op1.readyTimestamp)" -Force
Save-State $stFix

Write-Output "P5 COMPLETE proposal=$propId tx=$($h.hash) block=$qBlock ts=$qTs"
Write-Output "opId=$opId readyTimestamp=$($op1.readyTimestamp) ($(UtcOf $op1.readyTimestamp) UTC) delta=$delta"
Write-Output "events: ProposalQueued id=$pqId eta=$pqEta | CallScheduled id=$csId delay=$csDelay"
