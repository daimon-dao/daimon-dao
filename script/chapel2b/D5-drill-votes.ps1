# D5 -- Day 5: the drill proposals get their proposers' own FOR votes, so
# the cancel drills (H4.5-H4.7) have queueable targets. staker3 casts FOR on
# P-A (id 2, hostile) and staker1 casts FOR on P-B (id 3, harmless): each
# proposer votes on its OWN proposal and on nothing else. The holder does
# NOT vote on either: it is the campaign's voter on proposal 0, and
# Scenario W requires the hostile proposal to pass WITHOUT the team voting
# (DRILL_KIT.md 4.3: "nobody votes" means nobody ELSE votes). Every number
# asserted is read from mined state; the VoteCast events are decoded from
# the receipts, fetched from a data-seed node when publicnode has pruned
# them. Preflight from live state, no loop: a Pending proposal stops the
# runner with the seconds to voteStart; any state but Active stops it cold.
. $PSScriptRoot\lib.ps1
Load-Keystores
$st = S
if ($st.pAVoteTx -or $st.pBVoteTx) { throw "the drill votes are already recorded (P-A $($st.pAVoteTx), P-B $($st.pBVoteTx))" }
$holder = $script:AddrBook.holder
$epoch = [DateTime]::new(1970, 1, 1, 0, 0, 0, [DateTimeKind]::Utc)
function Utc { param($ts) return $epoch.AddSeconds([double]"$ts").ToString("yyyy-MM-dd HH:mm:ss") }
function Tally { param($id) return ,@([System.Numerics.BigInteger]::Parse((Prop-Field $id 9)), [System.Numerics.BigInteger]::Parse((Prop-Field $id 10)), [System.Numerics.BigInteger]::Parse((Prop-Field $id 11))) }
function HV { param($id, $addr) return ((CQRaw $st.governor "hasVoted(uint256,address)(bool)" @("$id", "$addr")) -eq "true") }
## One-shot receipt fetch: publicnode first, then the data-seed node it
## prunes to (DRILL_KIT preparation; Level-2b note: publicnode serves blocks
## but drops receipts). cast rpc is a single query -- no polling.
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

# The two drill proposals, pinned to the kit (DRILL_KIT.md 4.1 / 4.2).
$drills = @(
  @{ tag = "P-A"; id = "2"; role = "staker3"; kind = "hostile, setMaxTxAmount(type(uint256).max)"; kitSnap = "131258242"; step = "D5.2" },
  @{ tag = "P-B"; id = "3"; role = "staker1"; kind = "harmless, setMaxSwapSlippageBps(500) no-op"; kitSnap = "131258303"; step = "D5.3" }
)

# ---- keystores: each must decrypt to the kit's proposer address -----------
# A castVote signed by the wrong key would burn nothing but gas, yet a
# mismatched map is exactly the kind of mistake this stops before signing.
$pf = Pf
foreach ($d in $drills) {
  $ks = Ks $d.role
  $prev = $ErrorActionPreference; $ErrorActionPreference = "Continue"
  $waddr = (cast wallet address --account $ks --password-file $pf 2>&1 | Out-String).Trim()
  $ErrorActionPreference = $prev
  $mapAddr = "$($script:KsMap.accounts.($d.role).address)"
  if ($waddr.ToLower() -ne $mapAddr.ToLower()) { throw "keystore '$ks' decrypts to '$waddr', not the mapped $mapAddr -- nothing signed" }
  $d.addr = $mapAddr
}

# ---- preflight, read-only -------------------------------------------------
$blkNow = BlockNumber
$tsNow = [System.Numerics.BigInteger]::Parse(((cast block $blkNow --field timestamp --rpc-url $script:RPC | Out-String).Trim()))
foreach ($d in $drills) {
  $d.state = Prop-State $d.id
  if ($d.state -eq "Pending") { throw "STOP: proposal $($d.id) ($($d.tag)) is still Pending at block $blkNow (ts $tsNow): voting opens at $(Utc (Prop-Field $d.id 7)) UTC, $([System.Numerics.BigInteger]::Parse((Prop-Field $d.id 7)) - $tsNow) s from now. Not looping." }
  if ($d.state -ne "Active") { throw "STOP: proposal $($d.id) ($($d.tag)) is '$($d.state)', not Active -- nothing to vote on. Report to the operator." }
  $d.proposer = (Prop-Field $d.id 0)
  $d.snap = (Prop-Field $d.id 5)
  $d.snapTvp = [System.Numerics.BigInteger]::Parse((Prop-Field $d.id 6))
  $d.vStart = [System.Numerics.BigInteger]::Parse((Prop-Field $d.id 7))
  $d.vEnd = [System.Numerics.BigInteger]::Parse((Prop-Field $d.id 8))
  $d.qbps = [System.Numerics.BigInteger]::Parse((Prop-Field $d.id 16))
  $d.quorumNeeded = [System.Numerics.BigInteger]::Divide($d.snapTvp * $d.qbps, 10000)
  $d.weight = CQ $st.staking "votingPowerAt(address,uint256)(uint256)" @($d.addr, $d.snap)
  $d.tally = Tally $d.id
  $d.hvSelf = HV $d.id $d.addr
  $d.hvHolder = HV $d.id $holder
}
# The cross votes that must NOT exist: staker3 on 3, staker1 on 2.
$hvCrossA = HV $drills[1].id $drills[0].addr
$hvCrossB = HV $drills[0].id $drills[1].addr
# Proposal 0 baseline: the campaign proposal, voted FOR by the holder on
# Day 2, must sit exactly where Day 2 left it.
$p0State = Prop-State 0
$p0Tally = Tally 0
$p0HvHolder = HV 0 $holder

$okPre = ($tsNow -ge $drills[0].vStart -and $tsNow -le $drills[0].vEnd -and $tsNow -ge $drills[1].vStart -and $tsNow -le $drills[1].vEnd -and $p0State -eq "Active" -and $p0Tally[0] -eq (BW "4.00") -and $p0Tally[1] -eq 0 -and $p0Tally[2] -eq 0 -and $p0HvHolder -and (-not $hvCrossA) -and (-not $hvCrossB))
foreach ($d in $drills) {
  $okPre = ($okPre -and $d.state -eq "Active" -and "$($d.proposer)".ToLower() -eq "$($d.addr)".ToLower() -and "$($d.snap)" -eq "$($d.kitSnap)" -and $d.snapTvp -eq (BW "6.40") -and $d.qbps -eq 1000 -and $d.quorumNeeded -eq (BW "0.64") -and $d.weight -eq (BW "1.20") -and $d.weight -ge $d.quorumNeeded -and (-not $d.hvSelf) -and (-not $d.hvHolder) -and $d.tally[0] -eq 0 -and $d.tally[1] -eq 0 -and $d.tally[2] -eq 0)
}

$day = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd")
Log-Line ""
Log-Line "## Day 5 -- Drill proposals voted ($day)"
Log-Line ""
Log-Line "The prerequisite of the queue-side cancel drills (H4.5-H4.7), run inside"
Log-Line "the P-A/P-B voting window: each proposer casts its own FOR on its OWN"
Log-Line "proposal and on nothing else -- staker3 on id 2 (P-A, hostile), staker1"
Log-Line "on id 3 (P-B, harmless). The holder votes on NEITHER: it is the"
Log-Line "campaign's voter on proposal 0, and Scenario W requires the hostile"
Log-Line "proposal to pass without the team voting. Two signed transactions, the"
Log-Line "same harness and invariant as every day before; keystores were checked"
Log-Line "against the kit's proposer addresses before anything was signed."
Log-Line ""
Log-Scenario "D5" "The proposers' own FOR votes on P-A (id 2) and P-B (id 3); quorum from one voter each; the holder abstains by design"
Log-Step "D5.1" "Preflight from live state, before the votes" "both proposals Active (voteStart <= now <= voteEnd); proposer fields == the kit's staker3/staker1; snapshots == kit (131258242 / 131258303); snapshotTotalVotingPower == 6.40 B, quorumBps 1000, quorum needed == 0.64 B; votingPowerAt(proposer, snapshot) == 1.20 B >= quorum; hasVoted false everywhere it must be (each proposer on both ids, the holder on 2 and 3); tallies 0/0/0 on both; proposal 0 exactly as Day 2 left it (Active, 4.00 B / 0 / 0, holder hasVoted true)" "block=$blkNow ts=$tsNow ($(Utc $tsNow) UTC); P-A: state=$($drills[0].state), proposer=$($drills[0].proposer), snap=$($drills[0].snap), window $(Utc $drills[0].vStart)..$(Utc $drills[0].vEnd), weight=$(FmtB $drills[0].weight), tally=$($drills[0].tally[0])/$($drills[0].tally[1])/$($drills[0].tally[2]), hvSelf=$($drills[0].hvSelf) hvHolder=$($drills[0].hvHolder); P-B: state=$($drills[1].state), proposer=$($drills[1].proposer), snap=$($drills[1].snap), window $(Utc $drills[1].vStart)..$(Utc $drills[1].vEnd), weight=$(FmtB $drills[1].weight), tally=$($drills[1].tally[0])/$($drills[1].tally[1])/$($drills[1].tally[2]), hvSelf=$($drills[1].hvSelf) hvHolder=$($drills[1].hvHolder); cross staker3-on-3=$hvCrossA staker1-on-2=$hvCrossB; snapTvp=$(FmtB $drills[0].snapTvp)/$(FmtB $drills[1].snapTvp), quorumNeeded=$(FmtB $drills[0].quorumNeeded); proposal 0: state=$p0State, tally=$(FmtB $p0Tally[0])/$($p0Tally[1])/$($p0Tally[2]), holderVoted=$p0HvHolder" "-" $(if ($okPre) { "PASS" } else { "DEVIATION" })
if (-not $okPre) { throw "STOP: preflight deviation, nothing signed" }

# ---- the two votes --------------------------------------------------------
$evTopic = (cast keccak "VoteCast(uint256,address,uint8,uint256)")
foreach ($d in $drills) {
  $hV = Send $d.role $st.governor "castVote(uint256,uint8)" @($d.id, "1")
  $rr = Get-ReceiptRaw $hV.hash
  $rcpt = $rr[0]; $rcptSrc = $rr[1]
  $ev = $null; $nLogs = 0
  foreach ($lg in $rcpt.logs) {
    $nLogs++
    if ("$($lg.topics[0])".ToLower() -ne "$evTopic".ToLower()) { continue }
    $dta = "$($lg.data)".Substring(2)
    $ev = @{ emitter = "$($lg.address)"
             id = [System.Numerics.BigInteger]::Parse("0" + "$($lg.topics[1])".Substring(2), "AllowHexSpecifier")
             voter = "0x" + "$($lg.topics[2])".Substring(26)
             support = [System.Numerics.BigInteger]::Parse("0" + $dta.Substring(0, 64), "AllowHexSpecifier")
             weight = [System.Numerics.BigInteger]::Parse("0" + $dta.Substring(64, 64), "AllowHexSpecifier") }
  }
  if ($null -eq $ev) { throw "no VoteCast event in the receipt of $($hV.hash) (served by $rcptSrc)" }
  $voteTs = [System.Numerics.BigInteger]::Parse(((cast block $hV.block --field timestamp --rpc-url $script:RPC | Out-String).Trim()))
  $a = Tally $d.id
  $hvA = HV $d.id $d.addr
  $stateA = Prop-State $d.id
  $quorumVotes = $a[0] + $a[2]
  $okVote = ($stateA -eq "Active" -and $hvA -and $a[0] -eq $d.weight -and $a[1] -eq 0 -and $a[2] -eq 0 -and "$($ev.emitter)".ToLower() -eq "$($st.governor)".ToLower() -and $ev.id -eq [System.Numerics.BigInteger]::Parse($d.id) -and "$($ev.voter)".ToLower() -eq "$($d.addr)".ToLower() -and $ev.support -eq 1 -and $ev.weight -eq $a[0] -and $nLogs -eq 1 -and $quorumVotes -ge $d.quorumNeeded -and $a[0] -gt $a[1])
  Log-Step $d.step "$($d.role) casts FOR (support 1) on proposal $($d.id) ($($d.tag): $($d.kind))" "tx mined; hasVoted true; forVotes == votingPowerAt(proposer, snapshot $($d.snap)) == 1.20 B, against 0, abstain 0; state still Active (the window is open); ONE log: VoteCast(id $($d.id), proposer, 1, weight == forVotes) from the governor; quorum For+Abstain >= 0.64 B; For > Against" "block=$($hV.block) ts=$voteTs ($(Utc $voteTs) UTC), gas=$($hV.gasUsed); state=$stateA, hasVoted=$hvA; for/against/abstain=$(FmtB $a[0])/$($a[1])/$($a[2]) (for=$($a[0]) wei); VoteCast decoded (receipt from $rcptSrc): emitter=$($ev.emitter), id=$($ev.id), voter=$($ev.voter), support=$($ev.support), weight=$(FmtB $ev.weight) ($($ev.weight) wei); logs in receipt=$nLogs; quorum: For+Abstain=$(FmtB $quorumVotes) vs needed $(FmtB $d.quorumNeeded) = $([System.Numerics.BigInteger]::Divide($quorumVotes * 100, $d.quorumNeeded)) % of the bar" $hV.hash $(if ($okVote) { "PASS" } else { "DEVIATION" })
  $d.tx = $hV; $d.ok = $okVote
}

# ---- proposal 0 and the non-voters, read only -----------------------------
$p0StateA = Prop-State 0
$p0TallyA = Tally 0
$p0HvS3 = HV 0 $drills[0].addr
$p0HvS1 = HV 0 $drills[1].addr
$hvHolder2A = HV $drills[0].id $holder
$hvHolder3A = HV $drills[1].id $holder
$okP0 = ($p0StateA -eq "Active" -and $p0TallyA[0] -eq (BW "4.00") -and $p0TallyA[1] -eq 0 -and $p0TallyA[2] -eq 0 -and (-not $p0HvS3) -and (-not $p0HvS1) -and (-not $hvHolder2A) -and (-not $hvHolder3A))
Log-Step "D5.4" "Proposal 0 and the deliberate non-votes, after both sends, read only" "proposal 0 untouched: still Active, tally 4.00 B / 0 / 0, neither staker has voted on it; the holder has voted on NEITHER drill proposal (Scenario W discipline)" "state0=$p0StateA, tally0=$(FmtB $p0TallyA[0])/$($p0TallyA[1])/$($p0TallyA[2]); hasVoted(0, staker3)=$p0HvS3, hasVoted(0, staker1)=$p0HvS1; hasVoted(2, holder)=$hvHolder2A, hasVoted(3, holder)=$hvHolder3A" "-" $(if ($okP0) { "PASS" } else { "DEVIATION" })

Log-Note "Queueable-from timestamps, read from mined state: P-A (id 2) voteEnd $($drills[0].vEnd) = $(Utc $drills[0].vEnd) UTC, P-B (id 3) voteEnd $($drills[1].vEnd) = $(Utc $drills[1].vEnd) UTC. From those instants state() reads Succeeded (each 1.20 B FOR clears the 0.64 B quorum alone) and anyone may call queue(id); the 7-day Timelock then puts earliest execute at $(Utc ($drills[0].vEnd + 7 * 86400)) UTC / $(Utc ($drills[1].vEnd + 7 * 86400)) UTC, and the Safe cancels inside that window (H4.5 on P-B via the Governor, H4.6/H4.7 on P-A direct at the Timelock), stopwatch from CallScheduled to Cancelled. Proposal 0 runs its own calendar: Succeeded expected $(Utc $st.voteEnd) UTC. Nothing else is signed today."

$st | Add-Member -NotePropertyName pAVoteTx -NotePropertyValue $drills[0].tx.hash -Force
$st | Add-Member -NotePropertyName pAVoteBlock -NotePropertyValue "$($drills[0].tx.block)" -Force
$st | Add-Member -NotePropertyName pAVoteEnd -NotePropertyValue "$($drills[0].vEnd)" -Force
$st | Add-Member -NotePropertyName pBVoteTx -NotePropertyValue $drills[1].tx.hash -Force
$st | Add-Member -NotePropertyName pBVoteBlock -NotePropertyValue "$($drills[1].tx.block)" -Force
$st | Add-Member -NotePropertyName pBVoteEnd -NotePropertyValue "$($drills[1].vEnd)" -Force
$st | Add-Member -NotePropertyName drillQuorumNeeded -NotePropertyValue "$($drills[0].quorumNeeded)" -Force
Save-State $st
Write-Output "D5 COMPLETE P-A vote tx=$($drills[0].tx.hash) block=$($drills[0].tx.block) queueable from $(Utc $drills[0].vEnd) UTC; P-B vote tx=$($drills[1].tx.hash) block=$($drills[1].tx.block) queueable from $(Utc $drills[1].vEnd) UTC"
