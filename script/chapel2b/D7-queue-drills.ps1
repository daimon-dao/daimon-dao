# D7 -- Day 7: queue the two drill proposals. Their voting closed at
# 2026-09-21 22:54:30 / 22:54:58 UTC and the clock, not a transaction,
# moved P-A (id 2, hostile) and P-B (id 3, harmless) to Succeeded: each
# proposer's own 1.20 B FOR cleared the 0.64 B quorum alone (Day 5). Today
# queue(2) and queue(3) hand both operations to the Timelock and start the
# 7-day delay on each: readyTimestamp = scheduling-block timestamp + 604800.
# That is the WHOLE purpose of the sitting: the queue-side cancel drills
# (H4.5 via the Governor on P-B, H4.6/H4.7 direct at the Timelock on P-A)
# need scheduled operations, and DRILL_KIT.md 2c says the Timelock row is
# actionable only after CallScheduled(opId) has been seen. The Safe does
# the cancels, separately, with its own signers; this runner cancels
# NOTHING and never touches proposal 0, whose own operation (queued Day 6)
# is read before and after and must not move.
# Two signed transactions from the holder: queue() is permissionless, so the
# caller changes no on-chain value (operation id, readyTimestamp and both
# events are sender-independent); the holder queued proposal 0 on Day 6 and
# queues here for the same reason a monitor or a stranger could. The
# operation ids are asserted three ways: the kit's precomputed value, the
# Timelock's hashOperation() and a local keccak. Every number asserted is
# read from mined state; ProposalQueued and CallScheduled are decoded from
# the receipts, fetched from a data-seed node when publicnode has pruned
# them. Preflight from live state, no loop: an Active drill proposal stops
# the runner with the seconds to voteEnd; any state but Succeeded stops it
# cold; a revert stops it with the full error, nothing is retried.
. $PSScriptRoot\lib.ps1
Load-Keystores
$st = S
if (-not $st.pAVoteTx -or -not $st.pBVoteTx) { throw "state.json carries no drill vote tx: Day 5 (D5-drill-votes.ps1) has not run" }
if (-not $st.queueTx) { throw "state.json carries no queue tx for proposal 0: Day 6 (D6-queue.ps1) has not run" }
if ($st.pAQueueTx -or $st.pBQueueTx) { throw "the drill queues are already recorded (P-A $($st.pAQueueTx), P-B $($st.pBQueueTx))" }
$holder = $script:AddrBook.holder
$epoch = [DateTime]::new(1970, 1, 1, 0, 0, 0, [DateTimeKind]::Utc)
function Utc { param($ts) return $epoch.AddSeconds([double]"$ts").ToString("yyyy-MM-dd HH:mm:ss") }
function HexToBig { param([string]$h) return [System.Numerics.BigInteger]::Parse("0" + ($h -replace "^0x", ""), "AllowHexSpecifier") }
function Dhms { param($s) $t = [TimeSpan]::FromSeconds([double]"$s"); return ("{0}d {1:00}h {2:00}m {3:00}s" -f [int]$t.TotalDays, $t.Hours, $t.Minutes, $t.Seconds) }
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
## blocks AND prunes older history). Evidence comes from STORAGE; this is
## the monitor's view, reported with its range.
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

# The two drill proposals, pinned to the kit (DRILL_KIT.md 4.1 / 4.2 / 2c).
$drills = @(
  @{ tag = "P-A"; id = "2"; proposerRole = "staker3"; kind = "hostile, setMaxTxAmount(type(uint256).max)"
     kitData = "0xec28438affffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
     kitSalt = "0x58a832d2ab8d15f59c6f9093ab4d93ab2d3a6df30f1d19a0efc3b11163972250"
     kitOpId = "0xd895606ccce44f00f6ca3af8a1fa99e6e1dbcf2221fd7b6b3ab50a39d9398e7d"
     kitVoteEnd = "1790031270"; stateVoteEnd = "$($st.pAVoteEnd)"; kitSnap = "131258242"
     drill = "H4.6/H4.7 -- Timelock.cancel(opId) direct by the Safe, then Governor.state(2) must read Canceled on its own"
     stepPre = "D7.2"; stepQ = "D7.4"; stepOp = "D7.5"; stepEv = "D7.6"; stepRe = "D7.10" },
  @{ tag = "P-B"; id = "3"; proposerRole = "staker1"; kind = "harmless, setMaxSwapSlippageBps(500) no-op"
     kitData = "0xe89d59de00000000000000000000000000000000000000000000000000000000000001f4"
     kitSalt = "0xbece6405b58ad27650973b1ef8a096dde74dd496c2574ff41914cb6b0c181213"
     kitOpId = "0x86564200b67e9203c71e7eb160f7e5afdc016d7f632d18daf803800bfd0ccb12"
     kitVoteEnd = "1790031298"; stateVoteEnd = "$($st.pBVoteEnd)"; kitSnap = "131258303"
     drill = "H4.5 -- Governor.cancel(3) by the Safe, the atomic cross-cancel of the Timelock operation"
     stepPre = "D7.3"; stepQ = "D7.7"; stepOp = "D7.8"; stepEv = "D7.9"; stepRe = "D7.11" }
)

# ---- keystore: the holder's must decrypt to the mapped address -------------
$ksH = Ks "holder"; $pf = Pf
$prevEap = $ErrorActionPreference; $ErrorActionPreference = "Continue"
$waddr = (cast wallet address --account $ksH --password-file $pf 2>&1 | Out-String).Trim()
$ErrorActionPreference = $prevEap
if ($waddr.ToLower() -ne "$holder".ToLower()) { throw "keystore '$ksH' decrypts to '$waddr', not the mapped $holder -- nothing signed" }

# ---- preflight, read-only: the chain, the clock, proposal 0 and the duplicate ------------------
$blkNow = BlockNumber
$tsNow = [System.Numerics.BigInteger]::Parse(((cast block $blkNow --field timestamp --rpc-url $script:RPC | Out-String).Trim()))
$propCount = CQ $st.governor "proposalCount()(uint256)"
$pState0 = Prop-State 0
$p0 = ReadProposal 0
$op0 = ReadOperation $st.operationId
$pState1 = Prop-State 1
$minDelay = CQ $st.timelock "getMinDelay()(uint256)"
$PROPOSER_ROLE = CQRaw $st.timelock "PROPOSER_ROLE()(bytes32)"
$CANCELLER_ROLE = CQRaw $st.timelock "CANCELLER_ROLE()(bytes32)"
$govIsProposer = CQRaw $st.timelock "hasRole(bytes32,address)(bool)" @($PROPOSER_ROLE, $st.governor)
$safeIsCanceller = CQRaw $st.timelock "hasRole(bytes32,address)(bool)" @($CANCELLER_ROLE, $script:GUARDIAN)
$govGuardian = CQRaw $st.governor "guardian()(address)"
$okPre0 = ($script:CHAIN -eq "97" -and $propCount -eq 4 -and $pState0 -eq "Queued" -and $p0.queued -eq "true" -and $p0.executed -eq "false" -and $p0.canceled -eq "false" -and "$($op0.readyTimestamp)" -eq "$($st.readyTimestamp)" -and $op0.executed -eq "false" -and $op0.canceled -eq "false" -and $pState1 -eq "Defeated" -and $minDelay -eq 604800 -and $govIsProposer -eq "true" -and $safeIsCanceller -eq "true" -and "$govGuardian".ToLower() -eq "$($script:GUARDIAN)".ToLower())

# ---- preflight, read-only: the two drill proposals -----------------------------------------------
foreach ($d in $drills) {
  $d.state = Prop-State $d.id
  $d.p = ReadProposal $d.id
  if ($d.state -eq "Active") { throw "STOP: proposal $($d.id) ($($d.tag)) is still Active at block $blkNow (ts $tsNow): voting closes at $($d.p.voteEnd) ($(Utc $d.p.voteEnd) UTC), $($d.p.voteEnd - $tsNow) s from now. Not looping." }
  if ($d.state -ne "Succeeded") { throw "STOP: proposal $($d.id) ($($d.tag)) is '$($d.state)', not Succeeded -- nothing to queue. Report to the operator." }
  $d.addr = "$($script:KsMap.accounts.($d.proposerRole).address)"
  $d.quorumNeeded = [System.Numerics.BigInteger]::Divide($d.p.snapTotal * $d.p.quorumBps, 10000)
  $d.quorumVotes = $d.p.forVotes + $d.p.abstainVotes
  $d.hvSelf = ((CQRaw $st.governor "hasVoted(uint256,address)(bool)" @("$($d.id)", $d.addr)) -eq "true")
  $d.hvHolder = ((CQRaw $st.governor "hasVoted(uint256,address)(bool)" @("$($d.id)", $holder)) -eq "true")
  $d.opIdChain = (CQRaw $st.timelock "hashOperation(address,uint256,bytes,bytes32,bytes32)(bytes32)" @($d.p.target, "$($d.p.value)", $d.p.data, $ZERO32, $d.p.salt)).ToLower()
  $d.opIdLocal = (cast keccak (cast abi-encode "f(address,uint256,bytes,bytes32,bytes32)" $d.p.target "$($d.p.value)" $d.p.data $ZERO32 $d.p.salt)).ToLower()
  $d.opBefore = ReadOperation $d.kitOpId
  $d.ok = ($d.state -eq "Succeeded" -and $tsNow -gt $d.p.voteEnd -and "$($d.p.voteEnd)" -eq $d.kitVoteEnd -and "$($d.p.voteEnd)" -eq $d.stateVoteEnd -and "$($d.p.snapshotBlock)" -eq $d.kitSnap -and $d.p.proposer.ToLower() -eq $d.addr.ToLower() -and $d.p.target.ToLower() -eq "$($st.token)".ToLower() -and "$($d.p.value)" -eq "0" -and $d.p.data.ToLower() -eq $d.kitData.ToLower() -and $d.p.salt.ToLower() -eq $d.kitSalt.ToLower() -and $d.p.forVotes -eq (BW "1.20") -and $d.p.againstVotes -eq 0 -and $d.p.abstainVotes -eq 0 -and $d.quorumNeeded -eq (BW "0.64") -and $d.quorumVotes -ge $d.quorumNeeded -and $d.p.forVotes -gt $d.p.againstVotes -and $d.hvSelf -and (-not $d.hvHolder) -and $d.p.queued -eq "false" -and $d.p.executed -eq "false" -and $d.p.canceled -eq "false" -and $d.opIdChain -eq $d.kitOpId.ToLower() -and $d.opIdLocal -eq $d.kitOpId.ToLower() -and $d.opBefore.readyTimestamp -eq 0 -and $d.opBefore.executed -eq "false" -and $d.opBefore.canceled -eq "false")
}
$okPre = $okPre0
foreach ($d in $drills) { $okPre = ($okPre -and $d.ok) }

$day = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd")
Log-Line ""
Log-Line "## Day 7 -- Drill proposals queued ($day)"
Log-Line ""
Log-Line "The last prerequisite of the queue-side cancel drills (H4.5-H4.7): the"
Log-Line "two throwaway proposals go into the Timelock. Their voting closed at"
Log-Line "22:54:30 / 22:54:58 UTC on the 21st and the clock alone moved P-A (id 2,"
Log-Line "hostile) and P-B (id 3, harmless) to Succeeded, each on its proposer's"
Log-Line "own 1.20 B FOR. Today queue(2) and queue(3) schedule the two operations"
Log-Line "and start a 7-day delay on each; the Safe's signers then cancel inside"
Log-Line "that window, separately, with their own keys (P-B through the Governor,"
Log-Line "P-A direct at the Timelock). Nothing is canceled here and proposal 0 is"
Log-Line "not touched: its operation from Day 6 is read before and after and must"
Log-Line "not move. Two signed transactions from the holder (queue() is"
Log-Line "permissionless; every value below is sender-independent), the same"
Log-Line "harness and invariant as every day before. Preflight is read from live"
Log-Line "state and refuses to loop: any state but Succeeded on either drill"
Log-Line "proposal stops the runner before anything is signed."
Log-Line ""
Log-Scenario "D7" "The drill queues: the holder queues P-A (id 2) and P-B (id 3); the Timelock takes both operations with the 7-day floor; the ids match the kit; proposal 0 untouched"
Log-Step "D7.1" "Preflight from live state: the chain, proposal 0, the duplicate, the Timelock roles" "chain 97; proposalCount 4; proposal 0 Queued (queued=true, executed=canceled=false) with its operation's readyTimestamp == Day 6's 1790609699 and executed=canceled=false; proposal 1 Defeated; getMinDelay 604800; governor holds PROPOSER_ROLE; the Safe holds CANCELLER_ROLE and is the Governor's guardian (the two cancel paths the drills will use)" "chain=$($script:CHAIN), block=$blkNow ts=$tsNow ($(Utc $tsNow) UTC), proposalCount=$propCount; state0=$pState0 queued0=$($p0.queued) executed0=$($p0.executed) canceled0=$($p0.canceled), op0 readyTimestamp=$($op0.readyTimestamp) ($(Utc $op0.readyTimestamp) UTC) executed=$($op0.executed) canceled=$($op0.canceled); state1=$pState1; getMinDelay=$minDelay, governorIsProposer=$govIsProposer, safeIsCanceller=$safeIsCanceller, governor.guardian=$govGuardian" "-" $(if ($okPre0) { "PASS" } else { "DEVIATION" })
foreach ($d in $drills) {
  Log-Step $d.stepPre "Preflight from live state: $($d.tag) (id $($d.id), $($d.kind)), before the queue" "state Succeeded (now > voteEnd == kit == Day 5's record); snapshot == kit; proposer == $($d.proposerRole); target == token, value 0, data == kit calldata, timelockSalt == kit; tally 1.20 B / 0 / 0 == Day 5's VoteCast weight; quorum For+Abstain >= 0.64 B and For > Against; proposer has voted, the holder has not; queued=executed=canceled=false; opId: Timelock.hashOperation == local keccak == the kit's precomputed value; its slot empty (readyTimestamp 0)" "state=$($d.state), voteEnd=$($d.p.voteEnd) ($(Utc $d.p.voteEnd) UTC), closed since $($tsNow - $d.p.voteEnd) s; snapshot=$($d.p.snapshotBlock), proposer=$($d.p.proposer), target=$($d.p.target), value=$($d.p.value), dataMatch=$($d.p.data.ToLower() -eq $d.kitData.ToLower()), saltMatch=$($d.p.salt.ToLower() -eq $d.kitSalt.ToLower()); for/against/abstain=$(FmtB $d.p.forVotes)/$($d.p.againstVotes)/$($d.p.abstainVotes), quorumNeeded=$(FmtB $d.quorumNeeded), quorum $([System.Numerics.BigInteger]::Divide($d.quorumVotes * 100, $d.quorumNeeded)) % of the bar, proposerVoted=$($d.hvSelf) holderVoted=$($d.hvHolder); queued=$($d.p.queued) executed=$($d.p.executed) canceled=$($d.p.canceled); opId chain=$($d.opIdChain) local=$($d.opIdLocal) kit=$($d.kitOpId) allMatch=$($d.opIdChain -eq $d.kitOpId.ToLower() -and $d.opIdLocal -eq $d.kitOpId.ToLower()); slot readyTimestamp=$($d.opBefore.readyTimestamp) executed=$($d.opBefore.executed) canceled=$($d.opBefore.canceled)" "-" $(if ($d.ok) { "PASS" } else { "DEVIATION" })
}
if (-not $okPre) { throw "STOP: preflight deviation, nothing signed" }

# ---- the two queues: the signed sends of the day ------------------------------------------------
$fromBlock = [int64]$blkNow
$topicPQ = (cast keccak "ProposalQueued(uint256,uint256)").ToLower()
$topicCS = (cast keccak "CallScheduled(bytes32,address,uint256,bytes,uint256)").ToLower()
foreach ($d in $drills) {
  $hQ = Send "holder" $st.governor "queue(uint256)" @("$($d.id)")
  $rr = Get-ReceiptRaw $hQ.hash
  $rcpt = $rr[0]; $rcptSrc = $rr[1]
  $qBlock = HexToBig "$($rcpt.blockNumber)"
  $qTs = [System.Numerics.BigInteger]::Parse(((cast block "$qBlock" --field timestamp --rpc-url $script:RPC | Out-String).Trim()))
  $pq = ReadProposal $d.id
  $stateQ = Prop-State $d.id
  $stateQn = CQ $st.governor "state(uint256)(uint8)" @("$($d.id)")
  $okQ = ("$($rcpt.status)" -eq "0x1" -and "$qBlock" -eq "$($hQ.block)" -and $pq.queued -eq "true" -and $pq.executed -eq "false" -and $pq.canceled -eq "false" -and $stateQ -eq "Queued" -and $stateQn -eq 4 -and "$($rcpt.from)".ToLower() -eq "$holder".ToLower() -and "$($rcpt.to)".ToLower() -eq "$($st.governor)".ToLower() -and $pq.forVotes -eq $d.p.forVotes -and $pq.againstVotes -eq 0 -and $pq.abstainVotes -eq 0)
  Log-Step $d.stepQ "The holder calls queue($($d.id)) -- $($d.tag)" "receipt status 1, from == holder, to == governor; proposal queued flag true; state() == Queued (4); executed/canceled untouched; tally unchanged" "status=$($rcpt.status), from=$($rcpt.from), to=$($rcpt.to), block=$qBlock (ts=$qTs = $(Utc $qTs) UTC), gas=$($hQ.gasUsed); queued=$($pq.queued) executed=$($pq.executed) canceled=$($pq.canceled), state=$stateQ ($stateQn); tally=$(FmtB $pq.forVotes)/$($pq.againstVotes)/$($pq.abstainVotes); receipt served by $rcptSrc" $hQ.hash $(if ($okQ) { "PASS" } else { "DEVIATION" })

  # the operation, read from storage: delta exact to the second
  $op1 = ReadOperation $d.kitOpId
  $delta = $op1.readyTimestamp - $qTs
  $okOp = ($op1.readyTimestamp -gt 0 -and $delta -eq 604800 -and $op1.executed -eq "false" -and $op1.canceled -eq "false")
  Log-Step $d.stepOp "operations(opId) read back from the Timelock -- $($d.tag), opId == the kit's" "readyTimestamp == queue-block timestamp + 604800 EXACTLY (7 real days); executed=false; canceled=false" "opId=$($d.kitOpId); readyTimestamp=$($op1.readyTimestamp) ($(Utc $op1.readyTimestamp) UTC), queue block ts=$qTs, delta=$delta s, executed=$($op1.executed), canceled=$($op1.canceled)" "-" $(if ($okOp) { "PASS" } else { "DEVIATION" })

  # the two events, decoded from the receipt itself
  $evPQ = $null; $evCS = $null; $nLogs = 0
  foreach ($lg in [array]$rcpt.logs) {
    $nLogs++
    $t0 = "$($lg.topics[0])".ToLower()
    if ($t0 -eq $topicPQ -and "$($lg.address)".ToLower() -eq "$($st.governor)".ToLower()) { $evPQ = $lg }
    if ($t0 -eq $topicCS -and "$($lg.address)".ToLower() -eq "$($st.timelock)".ToLower()) { $evCS = $lg }
  }
  $pqId = "?"; $pqEta = "?"; $pqEtaUtc = "?"; $csId = "?"; $csTarget = "?"; $csValue = "?"; $csDelay = "?"; $csData = "?"
  if ($evPQ) {
    $pqId = HexToBig "$($evPQ.topics[1])"
    $pqEta = HexToBig "$($evPQ.data)"
    $pqEtaUtc = Utc $pqEta
  }
  if ($evCS) {
    $csId = "$($evCS.topics[1])".ToLower()
    $dd = "$($evCS.data)" -replace "^0x", ""
    $csTarget = "0x" + $dd.Substring(24, 40)
    $csValue = HexToBig $dd.Substring(64, 64)
    $off = [int]"$(HexToBig $dd.Substring(128, 64))"
    $csDelay = HexToBig $dd.Substring(192, 64)
    $len = [int]"$(HexToBig $dd.Substring($off * 2, 64))"
    $csData = "0x" + $dd.Substring($off * 2 + 64, $len * 2)
  }
  $okEv = ($nLogs -eq 2 -and $evPQ -and $evCS -and "$pqId" -eq "$($d.id)" -and "$pqEta" -eq "$($op1.readyTimestamp)" -and $csId -eq $d.kitOpId.ToLower() -and $csTarget.ToLower() -eq "$($st.token)".ToLower() -and "$csValue" -eq "0" -and "$csDelay" -eq "604800" -and $csData.ToLower() -eq $d.kitData.ToLower())
  Log-Step $d.stepEv "The two events decoded from the receipt -- $($d.tag)" "exactly 2 logs: CallScheduled(id == the kit's opId, target == token, value 0, data == the kit's calldata, delay 604800) from the timelock; ProposalQueued(id=$($d.id), eta == readyTimestamp) from the governor. This is the CallScheduled the kit (2c) waits for before the Timelock cancel row may be signed" "logs=$nLogs (receipt from $rcptSrc); CallScheduled id=$csId target=$csTarget value=$csValue delay=$csDelay dataMatch=$($csData.ToLower() -eq $d.kitData.ToLower()); ProposalQueued id=$pqId eta=$pqEta ($pqEtaUtc UTC)" $hQ.hash $(if ($okEv) { "PASS" } else { "DEVIATION" })

  $d.tx = $hQ; $d.qBlock = $qBlock; $d.qTs = $qTs; $d.op = $op1; $d.okAll = ($okQ -and $okOp -and $okEv)
}

# ---- a second queue is refused at the Governor's own level (no transaction mined) -----------------
foreach ($d in $drills) {
  $rv = Expect-Revert "stranger" $st.governor "queue(uint256)" @("$($d.id)") "ProposalAlreadyQueued()"
  Log-Step $d.stepRe "The stranger tries queue($($d.id)) again -- $($d.tag)" "refused: ProposalAlreadyQueued -- the Governor rejects it itself, before the Timelock's OperationAlreadyScheduled; no transaction mined" "$rv" "-" $(if ($rv -match "ProposalAlreadyQueued") { "PASS" } else { "DEVIATION" })
}

# ---- proposal 0 after both sends, read only: nothing moved --------------------------------------------
$pState0A = Prop-State 0
$p0A = ReadProposal 0
$op0A = ReadOperation $st.operationId
$okP0 = ($pState0A -eq "Queued" -and $p0A.queued -eq "true" -and $p0A.executed -eq "false" -and $p0A.canceled -eq "false" -and "$($op0A.readyTimestamp)" -eq "$($st.readyTimestamp)" -and $op0A.executed -eq "false" -and $op0A.canceled -eq "false" -and $p0A.forVotes -eq (BW "4.00"))
Log-Step "D7.12" "Proposal 0 after both sends, read only" "untouched: still Queued, queued=true, executed=canceled=false, tally 4.00 B / 0 / 0; its operation's readyTimestamp still 1790609699 (2026-09-28 15:34:59 UTC), executed=canceled=false" "state0=$pState0A queued=$($p0A.queued) executed=$($p0A.executed) canceled=$($p0A.canceled), tally=$(FmtB $p0A.forVotes)/$($p0A.againstVotes)/$($p0A.abstainVotes); op0 readyTimestamp=$($op0A.readyTimestamp) ($(Utc $op0A.readyTimestamp) UTC) executed=$($op0A.executed) canceled=$($op0A.canceled)" "-" $(if ($okP0) { "PASS" } else { "DEVIATION" })

# ---- the events read back the way the monitor reads them ---------------------------------------------
$latest2 = BlockNumber
$rbPQ = CountLogsChunked $st.governor "ProposalQueued(uint256,uint256)" $fromBlock ([int64]$latest2)
$rbCS = CountLogsChunked $st.timelock "CallScheduled(bytes32,address,uint256,bytes,uint256)" $fromBlock ([int64]$latest2)
Log-Step "D7.13" "Read back over eth_getLogs: ProposalQueued on the governor, CallScheduled on the timelock, since the preflight block" "exactly 2 each -- today's two queues; with Day 6's this Timelock now carries three scheduled operations, all pending" "ProposalQueued found=$($rbPQ.count), CallScheduled found=$($rbCS.count) (blocks $fromBlock-$latest2, unreadable chunks=$($rbPQ.errorChunks)/$($rbCS.errorChunks))" "-" $(if ($rbPQ.count -eq 2 -and $rbCS.count -eq 2 -and $rbPQ.errorChunks -eq 0 -and $rbCS.errorChunks -eq 0) { "PASS" } else { "DEVIATION" })

$dA = $drills[0]; $dB = $drills[1]
$tsEnd = [System.Numerics.BigInteger]::Parse(((cast block $latest2 --field timestamp --rpc-url $script:RPC | Out-String).Trim()))
Log-Note "Cancel windows, read from the Timelock's storage. P-A (id 2, hostile): opId $($dA.kitOpId), CallScheduled in block $($dA.qBlock) at $($dA.qTs) ($(Utc $dA.qTs) UTC), readyTimestamp $($dA.op.readyTimestamp) = $(Utc $dA.op.readyTimestamp) UTC; the guardian may cancel from now until that instant, $(Dhms ($dA.op.readyTimestamp - $tsEnd)) at the time of this note ($(Utc $tsEnd) UTC); planned path $($dA.drill). P-B (id 3, harmless): opId $($dB.kitOpId), CallScheduled in block $($dB.qBlock) at $($dB.qTs) ($(Utc $dB.qTs) UTC), readyTimestamp $($dB.op.readyTimestamp) = $(Utc $dB.op.readyTimestamp) UTC; the guardian may cancel from now until that instant, $(Dhms ($dB.op.readyTimestamp - $tsEnd)) at the time of this note; planned path $($dB.drill). Both opIds equal the values precomputed in DRILL_KIT.md 2c, so the Safe rows written on 2026-09-15 are valid as printed: target the Timelock $($st.timelock) with calldata 0xc4d252f5 + opId for P-A, target the Governor $($st.governor) with 0x40e58ee5 + id for P-B; the kit's condition for signing the Timelock row (CallScheduled seen) is met by $($dA.stepEv)/$($dB.stepEv). The stopwatch of each drill runs from the CallScheduled timestamp above to the Cancelled block. If the Safe does NOT cancel before readyTimestamp, execute(id) becomes possible for anyone: for P-B a no-op, for P-A the removal of the per-transfer cap on the drill deployment -- the whole point of the drill is that it never gets there. Nothing is canceled by this harness; the cancellations are the signers' work, in the Safe, with the H4.8 read-aloud. Proposal 0 (the campaign's own) is untouched, earliest execute unchanged at $(Utc $st.readyTimestamp) UTC. Wallet choice, recorded as an assumption: the holder signed both queues, as on Day 6; queue() is permissionless and every value verified above is sender-independent. Nothing else is signed today."

# ---- state: what the drill days will need ----------------------------------------------------------------
$stFix = S
$stFix | Add-Member -NotePropertyName pAQueueTx -NotePropertyValue $dA.tx.hash -Force
$stFix | Add-Member -NotePropertyName pAQueueBlock -NotePropertyValue "$($dA.qBlock)" -Force
$stFix | Add-Member -NotePropertyName pAQueueTimestamp -NotePropertyValue "$($dA.qTs)" -Force
$stFix | Add-Member -NotePropertyName pAOperationId -NotePropertyValue $dA.kitOpId.ToLower() -Force
$stFix | Add-Member -NotePropertyName pAReadyTimestamp -NotePropertyValue "$($dA.op.readyTimestamp)" -Force
$stFix | Add-Member -NotePropertyName pBQueueTx -NotePropertyValue $dB.tx.hash -Force
$stFix | Add-Member -NotePropertyName pBQueueBlock -NotePropertyValue "$($dB.qBlock)" -Force
$stFix | Add-Member -NotePropertyName pBQueueTimestamp -NotePropertyValue "$($dB.qTs)" -Force
$stFix | Add-Member -NotePropertyName pBOperationId -NotePropertyValue $dB.kitOpId.ToLower() -Force
$stFix | Add-Member -NotePropertyName pBReadyTimestamp -NotePropertyValue "$($dB.op.readyTimestamp)" -Force
Save-State $stFix

Write-Output "D7 COMPLETE"
Write-Output "P-A id=2 tx=$($dA.tx.hash) block=$($dA.qBlock) ts=$($dA.qTs) ($(Utc $dA.qTs) UTC) opId=$($dA.kitOpId) readyTimestamp=$($dA.op.readyTimestamp) ($(Utc $dA.op.readyTimestamp) UTC) verdicts=$($dA.okAll)"
Write-Output "P-B id=3 tx=$($dB.tx.hash) block=$($dB.qBlock) ts=$($dB.qTs) ($(Utc $dB.qTs) UTC) opId=$($dB.kitOpId) readyTimestamp=$($dB.op.readyTimestamp) ($(Utc $dB.op.readyTimestamp) UTC) verdicts=$($dB.okAll)"
Write-Output "cancel windows: P-A until $(Utc $dA.op.readyTimestamp) UTC, P-B until $(Utc $dB.op.readyTimestamp) UTC; proposal 0 untouched ($pState0A, ready $(Utc $st.readyTimestamp) UTC)"
