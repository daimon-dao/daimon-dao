# D6 -- Day 6: queue proposal 0. Voting closed at voteEnd (2026-09-20
# 10:11:31 UTC) and the clock, not a transaction, moved proposal 0 to
# Succeeded. Today queue(0) hands the operation to the Timelock and the
# 7-day delay starts its REAL clock: readyTimestamp = scheduling-block
# timestamp + 604800, and nothing shorter exists in the bytecode (MIN_DELAY
# is a constant). One signed transaction, from the holder (the proposer, as
# the July campaign and Level 2 queued from the proposer); queue() is
# permissionless, so the caller changes no on-chain value: operation id,
# readyTimestamp and both events are sender-independent.
# Proposal 1, the duplicate of H3.1.4, received no vote: with quorum 0 it
# lapsed to Defeated at its own voteEnd. It is READ and recorded, never
# acted on. P-A/P-B (ids 2 and 3) are read too: still Active until 22:54
# UTC tonight, they belong to the H4.5-H4.7 drills, not to this sitting.
# Every number asserted is read from mined state; ProposalQueued and
# CallScheduled are decoded from the receipt, fetched from a data-seed node
# when publicnode has pruned it. Preflight from live state, no loop: any
# state but Succeeded on proposal 0 stops the runner before anything is
# signed; a revert stops it with the full error, nothing is retried.
. $PSScriptRoot\lib.ps1
Load-Keystores
$st = S
if ("$($st.proposalId)" -ne "0") { throw "state.json: the campaign proposal must be id 0 (found '$($st.proposalId)')" }
if (-not $st.voteTx) { throw "state.json carries no vote tx: Day 2 (H3b-vote.ps1) has not run" }
if ($st.queueTx) { throw "the queue is already recorded (tx $($st.queueTx))" }
$propId = 0
$dupId = [int]$st.duplicateProposalId
$holder = $script:AddrBook.holder
$epoch = [DateTime]::new(1970, 1, 1, 0, 0, 0, [DateTimeKind]::Utc)
function Utc { param($ts) return $epoch.AddSeconds([double]"$ts").ToString("yyyy-MM-dd HH:mm:ss") }
function HexToBig { param([string]$h) return [System.Numerics.BigInteger]::Parse("0" + ($h -replace "^0x", ""), "AllowHexSpecifier") }
$PROP_SIG = "proposals(uint256)(address,address,uint256,bytes,string,uint256,uint256,uint256,uint256,uint256,uint256,uint256,bool,bool,bool,bytes32,uint256)"
function ReadProposal { param($id)
  $prev = $ErrorActionPreference; $ErrorActionPreference = "Continue"
  $lines = @(cast call $st.governor $PROP_SIG "$id" --rpc-url $script:RPC 2>&1)
  $c = $LASTEXITCODE; $ErrorActionPreference = $prev
  if ($c -ne 0 -or $lines.Count -lt 17) { throw "proposals($id) read failed: $(($lines -join ' ') -replace '\s+',' ')" }
  $tok = @(); foreach ($l in $lines) { $tok += ("$l".Trim() -split "\s+")[0] }
  return @{
    proposer = $tok[0]; target = $tok[1]; value = $tok[2]; data = $tok[3]
    description = "$($lines[4])".Trim()
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
  $prev = $ErrorActionPreference; $ErrorActionPreference = "Continue"
  $lines = @(cast call $st.timelock "operations(bytes32)(uint256,bool,bool)" $opId --rpc-url $script:RPC 2>&1)
  $c = $LASTEXITCODE; $ErrorActionPreference = $prev
  if ($c -ne 0 -or $lines.Count -lt 3) { throw "operations($opId) read failed: $(($lines -join ' ') -replace '\s+',' ')" }
  $tok = @(); foreach ($l in $lines) { $tok += ("$l".Trim() -split "\s+")[0] }
  return @{ readyTimestamp = [System.Numerics.BigInteger]::Parse($tok[0]); executed = $tok[1]; canceled = $tok[2] }
}
## One-shot receipt fetch: publicnode first, then the data-seed node it
## falls back to when the public RPC has already pruned the receipt.
function Get-ReceiptRaw { param($hash)
  foreach ($ep in @($script:RPC, "https://data-seed-prebsc-1-s1.bnbchain.org:8545")) {
    $prev = $ErrorActionPreference; $ErrorActionPreference = "Continue"
    $r = (cast rpc eth_getTransactionReceipt $hash --rpc-url $ep 2>&1 | Out-String)
    $c = $LASTEXITCODE; $ErrorActionPreference = $prev
    if ($c -ne 0) { continue }
    $j = $null; try { $j = $r | ConvertFrom-Json } catch { continue }
    if ($j -and $j.logs) { $src = ([uri]$ep).Host; return ,@($j, $src) }
  }
  throw "receipt for $hash not served by publicnode nor data-seed-prebsc-1-s1"
}
## Log scan in 50000-block chunks (the public RPC caps eth_getLogs at 50000
## blocks AND prunes older history): the count over the chunks that
## answered, plus the first block of the readable range. Evidence of the
## "pending operations: 0" claim comes from STORAGE below; this is the
## monitor's view, reported with its range.
function CountLogsChunked { param($addr, $sig, [int64]$from, [int64]$to)
  $total = 0; $errs = 0; $firstReadable = -1
  $prev = $ErrorActionPreference; $ErrorActionPreference = "Continue"
  while ($from -le $to) {
    $end = [Math]::Min($from + 49999, $to)
    $r = (cast logs --address $addr $sig --from-block $from --to-block $end --rpc-url $script:RPC --json 2>&1 | Out-String)
    if ($LASTEXITCODE -ne 0) { $errs++ }
    else {
      if ($firstReadable -lt 0) { $firstReadable = $from }
      $j = $null; try { $j = $r | ConvertFrom-Json } catch {}
      if ($null -ne $j) { $total += ([array]$j).Count }
    }
    $from = $end + 1
  }
  $ErrorActionPreference = $prev
  return @{ count = $total; errorChunks = $errs; firstReadable = $firstReadable }
}
$ZERO32 = "0x0000000000000000000000000000000000000000000000000000000000000000"

# ---- keystore: the holder's must decrypt to the mapped address -------------
$ksH = Ks "holder"; $pf = Pf
$prevEap = $ErrorActionPreference; $ErrorActionPreference = "Continue"
$waddr = (cast wallet address --account $ksH --password-file $pf 2>&1 | Out-String).Trim()
$ErrorActionPreference = $prevEap
if ($waddr.ToLower() -ne "$holder".ToLower()) { throw "keystore '$ksH' decrypts to '$waddr', not the mapped $holder -- nothing signed" }

# ---- preflight, read-only: proposal 0 ------------------------------------------
$blkNow = BlockNumber
$tsNow = [System.Numerics.BigInteger]::Parse(((cast block $blkNow --field timestamp --rpc-url $script:RPC | Out-String).Trim()))
$propCount = CQ $st.governor "proposalCount()(uint256)"
$pState0 = Prop-State $propId
$p = ReadProposal $propId
if ($pState0 -eq "Active") { throw "STOP: proposal 0 is still Active at block $blkNow (ts $tsNow): voting closes at $($p.voteEnd) ($(Utc $p.voteEnd) UTC), $($p.voteEnd - $tsNow) s from now. Not looping." }
if ($pState0 -ne "Succeeded") { throw "STOP: proposal 0 is '$pState0', not Succeeded -- nothing to queue" }
$expectedCalldata = (cast calldata "setStakingRewardShareBps(uint256)" 600)
$calldataOk = ($p.data.ToLower() -eq $expectedCalldata.ToLower())
$quorumNeeded = [System.Numerics.BigInteger]::Divide($p.snapTotal * $p.quorumBps, 10000)
$quorumVotes = $p.forVotes + $p.abstainVotes
$tallyOk = ($p.forVotes -eq (BW "4.00") -and $p.againstVotes -eq 0 -and $p.abstainVotes -eq 0 -and "$($p.forVotes)" -eq "$($st.voteWeight)")
$flagsOk = ($p.queued -eq "false" -and $p.executed -eq "false" -and $p.canceled -eq "false")
$hvHolder = ((CQRaw $st.governor "hasVoted(uint256,address)(bool)" @("$propId", $holder)) -eq "true")
$okPre0 = ($script:CHAIN -eq "97" -and $propCount -eq 4 -and $pState0 -eq "Succeeded" -and $tsNow -gt $p.voteEnd -and "$($p.voteEnd)" -eq "$($st.voteEnd)" -and $tallyOk -and $flagsOk -and $calldataOk -and $p.target.ToLower() -eq "$($st.token)".ToLower() -and "$($p.value)" -eq "0" -and $p.proposer.ToLower() -eq "$holder".ToLower() -and $quorumVotes -ge $quorumNeeded -and $p.forVotes -gt $p.againstVotes -and $hvHolder)
# ---- preflight, read-only: proposal 1, the duplicate, lapsed ----------------------
$pState1 = Prop-State $dupId
$p1 = ReadProposal $dupId
$quorumNeeded1 = [System.Numerics.BigInteger]::Divide($p1.snapTotal * $p1.quorumBps, 10000)
$hv1 = ((CQRaw $st.governor "hasVoted(uint256,address)(bool)" @("$dupId", $holder)) -eq "true")
$okPre1 = ($pState1 -eq "Defeated" -and $tsNow -gt $p1.voteEnd -and "$($p1.voteEnd)" -eq "$($st.duplicateVoteEnd)" -and $p1.forVotes -eq 0 -and $p1.againstVotes -eq 0 -and $p1.abstainVotes -eq 0 -and $p1.queued -eq "false" -and $p1.executed -eq "false" -and $p1.canceled -eq "false" -and (-not $hv1) -and $p1.data.ToLower() -eq $p.data.ToLower() -and $p1.target.ToLower() -eq $p.target.ToLower() -and $quorumNeeded1 -eq $quorumNeeded)
# ---- preflight, read-only: the drills, untouched today ------------------------------
$pState2 = Prop-State 2; $pState3 = Prop-State 3
$p2 = ReadProposal 2; $p3 = ReadProposal 3
# ---- preflight, read-only: the Timelock before queue ---------------------------------
$minDelay = CQ $st.timelock "getMinDelay()(uint256)"
$MIN_DELAY = CQ $st.timelock "MIN_DELAY()(uint256)"
$PROPOSER_ROLE = CQRaw $st.timelock "PROPOSER_ROLE()(bytes32)"
$govIsProposer = CQRaw $st.timelock "hasRole(bytes32,address)(bool)" @($PROPOSER_ROLE, $st.governor)
$opId = CQRaw $st.timelock "hashOperation(address,uint256,bytes,bytes32,bytes32)(bytes32)" @($p.target, "$($p.value)", $p.data, $ZERO32, $p.salt)
$opIdLocal = (cast keccak (cast abi-encode "f(address,uint256,bytes,bytes32,bytes32)" $p.target "$($p.value)" $p.data $ZERO32 $p.salt))
$op0 = ReadOperation $opId
$sched = CountLogsChunked $st.timelock "CallScheduled(bytes32,address,uint256,bytes,uint256)" ([int64]"$($st.headerBlock)") ([int64]$blkNow)
$okTl = ($minDelay -eq 604800 -and $MIN_DELAY -eq 604800 -and $govIsProposer -eq "true" -and $opId.ToLower() -eq $opIdLocal.ToLower() -and $op0.readyTimestamp -eq 0 -and $op0.executed -eq "false" -and $op0.canceled -eq "false" -and $sched.count -eq 0 -and $p2.queued -eq "false" -and $p3.queued -eq "false" -and $pState2 -eq "Active" -and $pState3 -eq "Active")

$day = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd")
Log-Line ""
Log-Line "## Day 6 -- Queue ($day)"
Log-Line ""
Log-Line "The governance cycle on the real clock, third sitting: the queue of"
Log-Line "proposal 0. Voting closed at voteEnd and the clock, not a transaction,"
Log-Line "moved the proposal to Succeeded; today queue(0) hands the operation to"
Log-Line "the Timelock and the 7-day delay starts its real clock. One signed"
Log-Line "transaction (queue by the holder, the proposer), the same harness and"
Log-Line "roles as Day 1, the same invariant asserted after the send. Preflight is"
Log-Line "read from live state and refuses to loop: any state but Succeeded stops"
Log-Line "the runner before anything is signed. Proposal 1, the duplicate that"
Log-Line "received no vote, is read as Defeated and left untouched; P-A/P-B are"
Log-Line "read and left to their own calendar."
Log-Line ""
Log-Scenario "H3.3a" "The queue: the holder queues proposal 0; the Timelock takes the operation with the 7-day floor; the duplicate lapsed to Defeated on its own"
Log-Step "H3.3a.1" "Preflight from live state: proposal 0, before the queue" "chain 97; proposalCount 4; state Succeeded (now > voteEnd == Day 1's voteEnd); tally 4.00 B / 0 / 0 == Day 2's VoteCast weight; quorum For+Abstain >= 0.40 B and For > Against; queued=executed=canceled=false; data == setStakingRewardShareBps(600); target == token; value 0; proposer == holder, who has voted" "chain=$($script:CHAIN), block=$blkNow ts=$tsNow ($(Utc $tsNow) UTC), proposalCount=$propCount; state0=$pState0, voteEnd=$($p.voteEnd) ($(Utc $p.voteEnd) UTC), closed since $($tsNow - $p.voteEnd) s; for/against/abstain=$(FmtB $p.forVotes)/$($p.againstVotes)/$($p.abstainVotes) (for=$($p.forVotes) wei), quorumNeeded=$(FmtB $quorumNeeded), quorum $([System.Numerics.BigInteger]::Divide($quorumVotes * 100, $quorumNeeded)) % of the bar; queued=$($p.queued) executed=$($p.executed) canceled=$($p.canceled); calldataMatch=$calldataOk, target=$($p.target), value=$($p.value), proposer=$($p.proposer), holderVoted=$hvHolder, snapshot=$($p.snapshotBlock), salt=$($p.salt)" "-" $(if ($okPre0) { "PASS" } else { "DEVIATION" })
if (-not $okPre0) { throw "STOP: preflight deviation on proposal 0, nothing signed" }
Log-Step "H3.3a.2" "Proposal 1 (the duplicate) after its voteEnd, read only -- recorded, not acted on" "Defeated by the clock alone: no vote ever cast (hasVoted false, tally 0/0/0, quorum 0 < 0.40 B); same calldata, target and quorum bar as proposal 0; queued=executed=canceled=false; now > its voteEnd $(Utc $st.duplicateVoteEnd) UTC" "state1=$pState1, voteEnd=$($p1.voteEnd) ($(Utc $p1.voteEnd) UTC), lapsed since $($tsNow - $p1.voteEnd) s; for/against/abstain=$($p1.forVotes)/$($p1.againstVotes)/$($p1.abstainVotes), quorumNeeded=$(FmtB $quorumNeeded1), holderVoted=$hv1; queued=$($p1.queued) executed=$($p1.executed) canceled=$($p1.canceled); sameCalldata=$($p1.data.ToLower() -eq $p.data.ToLower()), snapshot=$($p1.snapshotBlock)" "-" $(if ($okPre1) { "PASS" } else { "DEVIATION" })
if (-not $okPre1) { throw "STOP: preflight deviation on proposal 1, nothing signed" }
Log-Step "H3.3a.3" "Preflight from live state: the Timelock before queue (pending operations: 0, proven from storage)" "getMinDelay == MIN_DELAY == 604800; governor holds PROPOSER_ROLE (the only scheduling path, and it schedules only from queue: no proposal has queued=true); operation id (target, 0, data, predecessor 0x0, salt) computed on-chain == local keccak; its slot empty (readyTimestamp 0); CallScheduled events over the RPC's readable range: 0; P-A/P-B still Active, not queued" "getMinDelay=$minDelay, MIN_DELAY=$MIN_DELAY, governorIsProposer=$govIsProposer, opId=$opId, localMatch=$($opId.ToLower() -eq $opIdLocal.ToLower()), slot readyTimestamp=$($op0.readyTimestamp) executed=$($op0.executed) canceled=$($op0.canceled); CallScheduled count=$($sched.count) (readable from block $($sched.firstReadable) to $blkNow; $($sched.errorChunks) pruned chunks below it); state2=$pState2 queued2=$($p2.queued), state3=$pState3 queued3=$($p3.queued)" "-" $(if ($okTl) { "PASS" } else { "DEVIATION" })
if (-not $okTl) { throw "STOP: preflight deviation on the Timelock, nothing signed" }

# ---- the queue: the one signed send of the day ----------------------------------------
$fromBlock = [int64]$blkNow
$hQ = Send "holder" $st.governor "queue(uint256)" @("$propId")
$rr = Get-ReceiptRaw $hQ.hash
$rcpt = $rr[0]; $rcptSrc = $rr[1]
$qBlock = HexToBig "$($rcpt.blockNumber)"
$qTs = [System.Numerics.BigInteger]::Parse(((cast block "$qBlock" --field timestamp --rpc-url $script:RPC | Out-String).Trim()))
$pq = ReadProposal $propId
$stateQ = Prop-State $propId
$stateQn = CQ $st.governor "state(uint256)(uint8)" @("$propId")
$okQ = ("$($rcpt.status)" -eq "0x1" -and "$qBlock" -eq "$($hQ.block)" -and $pq.queued -eq "true" -and $pq.executed -eq "false" -and $pq.canceled -eq "false" -and $stateQ -eq "Queued" -and $stateQn -eq 4 -and "$($rcpt.from)".ToLower() -eq "$holder".ToLower() -and "$($rcpt.to)".ToLower() -eq "$($st.governor)".ToLower() -and $pq.forVotes -eq $p.forVotes -and $pq.againstVotes -eq 0 -and $pq.abstainVotes -eq 0)
Log-Step "H3.3a.4" "The holder (the proposer) calls queue($propId)" "receipt status 1, from == holder, to == governor; proposal queued flag true; state() == Queued (4); executed/canceled untouched; tally unchanged" "status=$($rcpt.status), from=$($rcpt.from), to=$($rcpt.to), block=$qBlock (ts=$qTs = $(Utc $qTs) UTC), gas=$($hQ.gasUsed); queued=$($pq.queued) executed=$($pq.executed) canceled=$($pq.canceled), state=$stateQ ($stateQn); tally=$(FmtB $pq.forVotes)/$($pq.againstVotes)/$($pq.abstainVotes); receipt served by $rcptSrc" $hQ.hash $(if ($okQ) { "PASS" } else { "DEVIATION" })

# ---- the operation, read from storage: delta exact to the second ----------------------------
$op1 = ReadOperation $opId
$delta = $op1.readyTimestamp - $qTs
$okOp = ($op1.readyTimestamp -gt 0 -and $delta -eq 604800 -and $op1.executed -eq "false" -and $op1.canceled -eq "false")
Log-Step "H3.3a.5" "operations(opId) read back from the Timelock" "readyTimestamp == queue-block timestamp + 604800 EXACTLY (7 real days); executed=false; canceled=false" "readyTimestamp=$($op1.readyTimestamp) ($(Utc $op1.readyTimestamp) UTC), queue block ts=$qTs, delta=$delta s, executed=$($op1.executed), canceled=$($op1.canceled)" "-" $(if ($okOp) { "PASS" } else { "DEVIATION" })

# ---- the two events, decoded from the receipt itself ------------------------------------------
$topicPQ = (cast keccak "ProposalQueued(uint256,uint256)")
$topicCS = (cast keccak "CallScheduled(bytes32,address,uint256,bytes,uint256)")
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
  $pqEtaUtc = Utc $pqEta
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
$okEv = ($nLogs -eq 2 -and $evPQ -and $evCS -and "$pqId" -eq "$propId" -and "$pqEta" -eq "$($op1.readyTimestamp)" -and $csId -eq $opId.ToLower() -and $csTarget.ToLower() -eq "$($st.token)".ToLower() -and "$csValue" -eq "0" -and "$csDelay" -eq "604800" -and $csData.ToLower() -eq $p.data.ToLower())
Log-Step "H3.3a.6" "The two events decoded from the receipt" "exactly 2 logs: CallScheduled(id == opId, target == token, value 0, data == setStakingRewardShareBps(600), delay 604800) from the timelock; ProposalQueued(id=$propId, eta == readyTimestamp) from the governor" "logs=$nLogs (receipt from $rcptSrc); CallScheduled id=$csId target=$csTarget value=$csValue delay=$csDelay dataMatch=$($csData.ToLower() -eq $p.data.ToLower()); ProposalQueued id=$pqId eta=$pqEta ($pqEtaUtc UTC)" $hQ.hash $(if ($okEv) { "PASS" } else { "DEVIATION" })

# ---- a second queue is refused at the Governor's own level; execute is refused inside the delay ---
$rv = Expect-Revert "stranger" $st.governor "queue(uint256)" @("$propId") "ProposalAlreadyQueued()"
Log-Step "H3.3a.7" "The stranger tries queue($propId) again" "refused: ProposalAlreadyQueued -- the Governor rejects it itself, before the Timelock's OperationAlreadyScheduled; no transaction mined" "$rv" "-" $(if ($rv -match "ProposalAlreadyQueued") { "PASS" } else { "DEVIATION" })
$rv2 = Expect-Revert "holder" $st.governor "execute(uint256)" @("$propId") "TooEarly()"
Log-Step "H3.3a.8" "The holder tries execute($propId) inside the delay" "refused: TooEarly from the Timelock (state is Queued, so the Governor lets the call reach the Timelock, which holds the clock); no transaction mined" "$rv2" "-" $(if ($rv2 -match "TooEarly") { "PASS" } else { "DEVIATION" })

# ---- the two events read back the way the monitor reads them -------------------------------------
$latest2 = BlockNumber
$rbPQ = CountLogsChunked $st.governor "ProposalQueued(uint256,uint256)" $fromBlock ([int64]$latest2)
$rbCS = CountLogsChunked $st.timelock "CallScheduled(bytes32,address,uint256,bytes,uint256)" $fromBlock ([int64]$latest2)
Log-Step "H3.3a.9" "Read back over eth_getLogs: ProposalQueued on the governor, CallScheduled on the timelock" "exactly 1 each -- today's queue, the first operation this Timelock has ever scheduled" "ProposalQueued found=$($rbPQ.count), CallScheduled found=$($rbCS.count) (blocks $fromBlock-$latest2, unreadable chunks=$($rbPQ.errorChunks)/$($rbCS.errorChunks))" "-" $(if ($rbPQ.count -eq 1 -and $rbCS.count -eq 1 -and $rbPQ.errorChunks -eq 0 -and $rbCS.errorChunks -eq 0) { "PASS" } else { "DEVIATION" })

Log-Note "Earliest execute, read from the Timelock's storage: readyTimestamp $($op1.readyTimestamp) = $(Utc $op1.readyTimestamp) UTC (queue block $qBlock at $qTs + 604800 s). execute(0) before that instant reverts TooEarly (H3.3a.8); from that instant anyone may call it, and the H3.3b/H3.4 sitting (execute, then the first poke that pays the marketing branch on a public chain) is planned for day 13/14, not before $(Utc $op1.readyTimestamp) UTC. The Safe (CANCELLER) can cancel the operation at any point inside the delay -- it will not: proposal 0 is the campaign's own. Wallet choice, recorded as an assumption: the holder (the proposer) signed, as the July campaign and Level 2 queued from the proposer; queue() is permissionless and every value verified above is sender-independent. Proposal 1 stays Defeated forever (no path out of that state); nothing is ever signed for it. P-A (id 2) and P-B (id 3) close at $(Utc $p2.voteEnd) / $(Utc $p3.voteEnd) UTC and belong to the H4.5-H4.7 drills. Nothing else is signed today."

# ---- state: what the execute day will need ------------------------------------------------------------
$stFix = S
$stFix | Add-Member -NotePropertyName queueTx -NotePropertyValue $hQ.hash -Force
$stFix | Add-Member -NotePropertyName queueBlock -NotePropertyValue "$qBlock" -Force
$stFix | Add-Member -NotePropertyName queueTimestamp -NotePropertyValue "$qTs" -Force
$stFix | Add-Member -NotePropertyName operationId -NotePropertyValue $opId.ToLower() -Force
$stFix | Add-Member -NotePropertyName timelockSalt -NotePropertyValue $p.salt.ToLower() -Force
$stFix | Add-Member -NotePropertyName readyTimestamp -NotePropertyValue "$($op1.readyTimestamp)" -Force
$stFix | Add-Member -NotePropertyName duplicateFinalState -NotePropertyValue "$pState1 (read $(Utc $tsNow) UTC, block $blkNow)" -Force
Save-State $stFix

Write-Output "D6 COMPLETE proposal=$propId tx=$($hQ.hash) block=$qBlock ts=$qTs ($(Utc $qTs) UTC)"
Write-Output "opId=$opId readyTimestamp=$($op1.readyTimestamp) ($(Utc $op1.readyTimestamp) UTC) delta=$delta"
Write-Output "events: ProposalQueued id=$pqId eta=$pqEta | CallScheduled id=$csId delay=$csDelay"
Write-Output "proposal 1: $pState1 (recorded, not acted on)"
