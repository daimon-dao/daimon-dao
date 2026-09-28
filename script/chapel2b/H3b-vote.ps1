# H3.2 -- Day 2: the vote. The holder (the only staker, the proposer) casts
# FOR on proposal 0, the campaign's proposal. Proposal 1 (the duplicate of
# H3.1.4) receives nothing and is only READ. Every number asserted is read
# from mined state; the VoteCast event is decoded from the receipt.
# Preflight from live state, no loop: if proposal 0 is still Pending the
# runner stops and reports the seconds to voteStart.
. $PSScriptRoot\lib.ps1
Load-Keystores
$st = S
if ("$($st.proposalId)" -ne "0") { throw "state.json: the campaign proposal must be id 0 (found '$($st.proposalId)') -- run H3a-finalize.ps1 first" }
if ($st.voteTx) { throw "the vote is already recorded (tx $($st.voteTx))" }
$propId = 0
$dupId = [int]$st.duplicateProposalId
$holder = $script:AddrBook.holder
$epoch = [DateTime]::new(1970, 1, 1, 0, 0, 0, [DateTimeKind]::Utc)
function Utc { param($ts) return $epoch.AddSeconds([double]"$ts").ToString("yyyy-MM-dd HH:mm:ss") }
function Tally { param($id) return ,@([System.Numerics.BigInteger]::Parse((Prop-Field $id 9)), [System.Numerics.BigInteger]::Parse((Prop-Field $id 10)), [System.Numerics.BigInteger]::Parse((Prop-Field $id 11))) }
function HasVoted { param($id) return ((CQRaw $st.governor "hasVoted(uint256,address)(bool)" @("$id", $holder)) -eq "true") }

# ---- preflight, read-only -------------------------------------------------
$blkNow = BlockNumber
$tsNow = [System.Numerics.BigInteger]::Parse(((cast block $blkNow --field timestamp --rpc-url $script:RPC | Out-String).Trim()))
$pState0 = Prop-State $propId
$vStart = [System.Numerics.BigInteger]::Parse((Prop-Field $propId 7))
$vEnd = [System.Numerics.BigInteger]::Parse((Prop-Field $propId 8))
if ($pState0 -eq "Pending") { throw "STOP: proposal 0 is still Pending at block $blkNow (ts $tsNow): voting opens at $vStart ($(Utc $vStart) UTC), $($vStart - $tsNow) s from now. Not looping." }
if ($pState0 -ne "Active") { throw "STOP: proposal 0 is '$pState0', not Active -- nothing to vote on" }
$snap = [System.Numerics.BigInteger]::Parse((Prop-Field $propId 5))
$snapTvp = [System.Numerics.BigInteger]::Parse((Prop-Field $propId 6))
$qbps = [System.Numerics.BigInteger]::Parse((Prop-Field $propId 16))
$quorumNeeded = [System.Numerics.BigInteger]::Divide($snapTvp * $qbps, 10000)
$wSnap = CQ $st.staking "votingPowerAt(address,uint256)(uint256)" @($holder, "$snap")
$tvpSnap = CQ $st.staking "totalVotingPowerAt(uint256)(uint256)" @("$snap")
$t0 = Tally $propId; $t1 = Tally $dupId
$pState1 = Prop-State $dupId
$hv0 = HasVoted $propId; $hv1 = HasVoted $dupId
if ($wSnap -lt $quorumNeeded) { throw "STOP: the holder's weight at the snapshot ($wSnap) is below the quorum ($quorumNeeded): the vote of one staker cannot meet quorum -- a finding about the staking setup, not something to work around" }
if ($hv0) { throw "STOP: the holder has already voted on proposal 0 (hasVoted true) but state.json carries no vote tx" }

$day = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd")
Log-Line ""
Log-Line "## Day 2 -- Vote ($day)"
Log-Line ""
Log-Line "The governance cycle on the real clock, second sitting: the vote on"
Log-Line "proposal 0. One signed transaction today (castVote by the holder), the"
Log-Line "same harness and roles as Day 1, the same invariant asserted after the"
Log-Line "send. Preflight is read from live state and refuses to loop: a Pending"
Log-Line "proposal stops the runner with the seconds to voteStart. Proposal 1, the"
Log-Line "duplicate, is read and left untouched."
Log-Line ""
Log-Scenario "H3.2" "The vote: the holder casts FOR on proposal 0; quorum from one staker; the duplicate receives nothing"
$okPre = ($pState0 -eq "Active" -and $tsNow -ge $vStart -and $tsNow -le $vEnd -and $wSnap -eq $snapTvp -and $tvpSnap -eq $snapTvp -and $snapTvp -eq (BW "4.00") -and $quorumNeeded -eq (BW "0.40") -and (-not $hv0) -and (-not $hv1) -and $t0[0] -eq 0 -and $t0[1] -eq 0 -and $t0[2] -eq 0 -and $t1[0] -eq 0 -and $t1[1] -eq 0 -and $t1[2] -eq 0 -and $pState1 -eq "Active")
Log-Step "H3.2.1" "Preflight from live state, before the vote" "proposal 0 Active (voteStart <= now <= voteEnd); the holder's votingPowerAt(snapshot $snap) == snapshotTotalVotingPower == totalVotingPowerAt(snapshot) == 4.00 B; quorum needed == 1000 bps of 4.00 B == 0.40 B; hasVoted false on 0 and 1; tallies 0/0/0 on both; proposal 1 Active too" "block=$blkNow ts=$tsNow ($(Utc $tsNow) UTC), voting open since $($tsNow - $vStart) s, closes in $($vEnd - $tsNow) s; state0=$pState0, state1=$pState1; votingPowerAt(holder,$snap)=$(FmtB $wSnap), totalVotingPowerAt($snap)=$(FmtB $tvpSnap), snapshotTotalVotingPower=$(FmtB $snapTvp), quorumBpsSnapshot=$qbps, quorumNeeded=$(FmtB $quorumNeeded) ($quorumNeeded wei); hasVoted0=$hv0 hasVoted1=$hv1; tally0 for/against/abstain=$($t0[0])/$($t0[1])/$($t0[2]), tally1=$($t1[0])/$($t1[1])/$($t1[2])" "-" $(if ($okPre) { "PASS" } else { "DEVIATION" })
if (-not $okPre) { throw "STOP: preflight deviation, nothing signed" }

# ---- the vote ----------------------------------------------------------------
$hV = Send "holder" $st.governor "castVote(uint256,uint8)" @("$propId", "1")
$rcpt = (cast receipt $hV.hash --json --rpc-url $script:RPC | Out-String) | ConvertFrom-Json
$evTopic = (cast keccak "VoteCast(uint256,address,uint8,uint256)")
$ev = $null; $nLogs = 0
foreach ($lg in $rcpt.logs) {
  $nLogs++
  if ("$($lg.topics[0])".ToLower() -ne "$evTopic".ToLower()) { continue }
  $d = "$($lg.data)".Substring(2)
  $ev = @{ emitter = "$($lg.address)"
           id = [System.Numerics.BigInteger]::Parse("0" + "$($lg.topics[1])".Substring(2), "AllowHexSpecifier")
           voter = "0x" + "$($lg.topics[2])".Substring(26)
           support = [System.Numerics.BigInteger]::Parse("0" + $d.Substring(0, 64), "AllowHexSpecifier")
           weight = [System.Numerics.BigInteger]::Parse("0" + $d.Substring(64, 64), "AllowHexSpecifier") }
}
if ($null -eq $ev) { throw "no VoteCast event in the receipt of $($hV.hash)" }
$voteTs = [System.Numerics.BigInteger]::Parse(((cast block $hV.block --field timestamp --rpc-url $script:RPC | Out-String).Trim()))
$a0 = Tally $propId
$hvA = HasVoted $propId
$stateA = Prop-State $propId
$quorumVotes = $a0[0] + $a0[2]
$okVote = ($stateA -eq "Active" -and $hvA -and $a0[0] -eq $wSnap -and $a0[1] -eq 0 -and $a0[2] -eq 0 -and "$($ev.emitter)".ToLower() -eq "$($st.governor)".ToLower() -and $ev.id -eq $propId -and "$($ev.voter)".ToLower() -eq "$holder".ToLower() -and $ev.support -eq 1 -and $ev.weight -eq $a0[0] -and $nLogs -eq 1 -and $quorumVotes -ge $quorumNeeded -and $a0[0] -gt $a0[1])
Log-Step "H3.2.2" "The holder casts FOR (support 1) on proposal 0" "tx mined; hasVoted true; forVotes == votingPowerAt(holder, snapshot) == 4.00 B, against 0, abstain 0; state still Active (the window is open); ONE log: VoteCast(id 0, holder, 1, weight == forVotes) from the governor; quorum For+Abstain >= 0.40 B; For > Against" "block=$($hV.block) ts=$voteTs ($(Utc $voteTs) UTC), gas=$($hV.gasUsed); state=$stateA, hasVoted=$hvA; for/against/abstain=$(FmtB $a0[0])/$($a0[1])/$($a0[2]) (for=$($a0[0]) wei); VoteCast decoded: emitter=$($ev.emitter), id=$($ev.id), voter=$($ev.voter), support=$($ev.support), weight=$(FmtB $ev.weight) ($($ev.weight) wei); logs in receipt=$nLogs; quorum: For+Abstain=$(FmtB $quorumVotes) vs needed $(FmtB $quorumNeeded) = $([System.Numerics.BigInteger]::Divide($quorumVotes * 100, $quorumNeeded)) % of the bar" $hV.hash $(if ($okVote) { "PASS" } else { "DEVIATION" })

# ---- the duplicate, read only --------------------------------------------------
$b1 = Tally $dupId
$hv1A = HasVoted $dupId
$state1A = Prop-State $dupId
$okDup = ($state1A -eq "Active" -and (-not $hv1A) -and $b1[0] -eq 0 -and $b1[1] -eq 0 -and $b1[2] -eq 0)
Log-Step "H3.2.3" "Proposal 1 (the duplicate) after the vote, read only" "untouched: hasVoted false, tallies 0/0/0, still Active; it lapses to Defeated after $(Utc $st.duplicateVoteEnd) UTC (quorum 0 < 0.40 B)" "state1=$state1A, hasVoted1=$hv1A, for/against/abstain=$($b1[0])/$($b1[1])/$($b1[2])" "-" $(if ($okDup) { "PASS" } else { "DEVIATION" })
Log-Note "Calendar: proposal 0 stays Active until voteEnd $vEnd ($(Utc $vEnd) UTC); from then state() reads Succeeded (quorum $(FmtB $quorumVotes) >= $(FmtB $quorumNeeded), For $(FmtB $a0[0]) > Against 0) and queue() arms the 7-day Timelock; earliest execute if queued at once $(Utc ($vEnd + 7 * 86400)) UTC. Proposal 1 lapses to Defeated after $(Utc $st.duplicateVoteEnd) UTC and is read then. Nothing else is signed today."
$st | Add-Member -NotePropertyName voteTx -NotePropertyValue $hV.hash -Force
$st | Add-Member -NotePropertyName voteBlock -NotePropertyValue "$($hV.block)" -Force
$st | Add-Member -NotePropertyName voteWeight -NotePropertyValue "$($ev.weight)" -Force
$st | Add-Member -NotePropertyName quorumNeeded -NotePropertyValue "$quorumNeeded" -Force
Save-State $st
Write-Output "H3b COMPLETE vote tx=$($hV.hash) block=$($hV.block) weight=$(FmtB $ev.weight) quorum $(FmtB $quorumVotes)/$(FmtB $quorumNeeded)"
