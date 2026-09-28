# H3.1 finalize -- READ-ONLY. The propose of H3.1 was signed twice on
# 2026-09-14 (see the journal note under H3.1.2): the first runner run
# signed proposal 0 and then crashed before logging it; the -Resume run,
# written on the wrong diagnosis that nothing had been signed, signed
# proposal 1. This runner records both from chain state, designates
# proposal 0 as THE campaign proposal (H3.2 votes on it) and proposal 1 as
# the duplicate that is left to lapse, and saves the calendar. No signing.
. $PSScriptRoot\lib.ps1
Load-Keystores
$st = S
if ($st.proposalId) { throw "already finalized (proposal $($st.proposalId))" }
$count = CQ $st.governor "proposalCount()(uint256)"
if ($count -ne 2) { throw "expected exactly 2 proposals on the governor, found $count" }
$calldata = (cast calldata "setStakingRewardShareBps(uint256)" 600)
$vp = CQ $st.staking "votingPower(address)(uint256)" @($script:AddrBook.holder)
$evTopic = (cast keccak "ProposalCreated(uint256,address,address,string)")
$epoch = [DateTime]::new(1970, 1, 1, 0, 0, 0, [DateTimeKind]::Utc)
function Utc { param($ts) return $epoch.AddSeconds([double]"$ts").ToString("yyyy-MM-dd HH:mm:ss") }

# The two ProposalCreated events, from the logs of the governor.
$prev = $ErrorActionPreference; $ErrorActionPreference = "Continue"
$logs = (cast logs --address $st.governor "ProposalCreated(uint256,address,address,string)" --from-block $st.headerBlock --to-block latest --rpc-url $script:RPC --json 2>&1 | Out-String) | ConvertFrom-Json
$ErrorActionPreference = $prev
$byId = @{}
foreach ($l in $logs) { $byId["$([System.Numerics.BigInteger]::Parse('0' + "$($l.topics[1])".Substring(2), 'AllowHexSpecifier'))"] = @{ tx = $l.transactionHash; block = [System.Numerics.BigInteger]::Parse("0" + "$($l.blockNumber)".Substring(2), "AllowHexSpecifier") } }

$rows = @()
foreach ($propId in 0, 1) {
  $state = Prop-State $propId
  $proposer = Prop-Field $propId 0
  $target = Prop-Field $propId 1
  $data = Prop-Field $propId 3
  $snap = [System.Numerics.BigInteger]::Parse((Prop-Field $propId 5))
  $snapTvp = [System.Numerics.BigInteger]::Parse((Prop-Field $propId 6))
  $vStart = [System.Numerics.BigInteger]::Parse((Prop-Field $propId 7))
  $vEnd = [System.Numerics.BigInteger]::Parse((Prop-Field $propId 8))
  $qbps = [System.Numerics.BigInteger]::Parse((Prop-Field $propId 16))
  $ev = $byId["$propId"]
  $blkTs = [System.Numerics.BigInteger]::Parse(((cast block $ev.block --field timestamp --rpc-url $script:RPC | Out-String).Trim()))
  $ok = ($state -eq "Pending" -and "$proposer".ToLower() -eq "$($script:AddrBook.holder)".ToLower() -and "$target".ToLower() -eq "$($st.token)".ToLower() -and "$data".ToLower() -eq "$calldata".ToLower() -and $snap -eq ($ev.block - 1) -and $snapTvp -eq $vp -and $vStart -eq ($blkTs + 86400) -and ($vEnd - $vStart) -eq 432000 -and $qbps -eq 1000)
  $rows += @{ id = $propId; ok = $ok; state = $state; proposer = $proposer; target = $target; data = $data; snap = $snap; snapTvp = $snapTvp; vStart = $vStart; vEnd = $vEnd; qbps = $qbps; tx = $ev.tx; block = $ev.block; ts = $blkTs }
}
$p0 = $rows[0]; $p1 = $rows[1]
Log-Step "H3.1.3" "The proposal of the campaign: id 0, setStakingRewardShareBps(600) on the token, read back from chain state (the first runner run signed it, then crashed before this row)" "state Pending; proposer == the holder; target == token, data == the calldata; snapshotBlock == propose block - 1; snapshotTotalVotingPower == 4.00 B; voteStart == block timestamp + 1 day; voteEnd - voteStart == 432000 s (5 days); quorum snapshot 1000 bps" "id=0, state=$($p0.state), proposer=$($p0.proposer), target=$($p0.target), data=$($p0.data); propose block=$($p0.block) ts=$($p0.ts), snapshotBlock=$($p0.snap), snapshotTotalVotingPower=$(FmtB $p0.snapTvp); voteStart=$($p0.vStart) ($(Utc $p0.vStart) UTC), voteEnd=$($p0.vEnd) ($(Utc $p0.vEnd) UTC), window=$($p0.vEnd - $p0.vStart) s; quorumBpsSnapshot=$($p0.qbps)" $p0.tx $(if ($p0.ok) { "PASS" } else { "DEVIATION" })
Log-Step "H3.1.4" "The DUPLICATE: id 1, the same call signed by the -Resume run on a wrong diagnosis (harness error, recorded not hidden)" "structurally identical to id 0 and valid; it is NOT the campaign's proposal: nobody votes on it and it lapses to Defeated after its voteEnd -- a free extra observation (a proposal with no votes) on the real clock" "id=1, state=$($p1.state), proposer=$($p1.proposer), data==id0 data=$("$($p1.data)".ToLower() -eq "$($p0.data)".ToLower()); propose block=$($p1.block), snapshotBlock=$($p1.snap), snapshotTotalVotingPower=$(FmtB $p1.snapTvp); voteStart=$(Utc $p1.vStart) UTC, voteEnd=$(Utc $p1.vEnd) UTC" $p1.tx $(if ($p1.ok) { "NOTE" } else { "DEVIATION" })
Log-Note "Real-clock calendar for proposal 0 from here: voting opens at $(Utc $p0.vStart) UTC (24 h after the propose block), closes at $(Utc $p0.vEnd) UTC (5 days later); queue any time after that arms the 7-day Timelock; the earliest execute, if queued at once, is $(Utc ($p0.vEnd + 7 * 86400)) UTC. H3.2-H3.5 and the H4 drill follow on that calendar. Proposal 1 is left untouched: its lapse to Defeated after $(Utc $p1.vEnd) UTC will be read and recorded. The monitor's expected URGENT on ProposalCreated (it touches stakingRewardShareBps) is to be confirmed by hand -- twice."
$st | Add-Member -NotePropertyName proposalId -NotePropertyValue "0" -Force
$st | Add-Member -NotePropertyName proposeTx -NotePropertyValue $p0.tx -Force
$st | Add-Member -NotePropertyName proposeBlock -NotePropertyValue "$($p0.block)" -Force
$st | Add-Member -NotePropertyName snapshotBlock -NotePropertyValue "$($p0.snap)" -Force
$st | Add-Member -NotePropertyName voteStart -NotePropertyValue "$($p0.vStart)" -Force
$st | Add-Member -NotePropertyName voteEnd -NotePropertyValue "$($p0.vEnd)" -Force
$st | Add-Member -NotePropertyName duplicateProposalId -NotePropertyValue "1" -Force
$st | Add-Member -NotePropertyName duplicateProposeTx -NotePropertyValue $p1.tx -Force
$st | Add-Member -NotePropertyName duplicateVoteEnd -NotePropertyValue "$($p1.vEnd)" -Force
Save-State $st
Write-Output "H3a-finalize COMPLETE: proposal 0 (campaign) voting $(Utc $p0.vStart) -> $(Utc $p0.vEnd) UTC; proposal 1 duplicate"
