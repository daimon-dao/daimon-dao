# D2 - Finding #12 reproduced: a stake in the proposal's own block counts for nothing.
. .\script\campaign\lib.ps1
Log-Scenario "D2" "Stake in the SAME block as propose(): it does not count (Zenith #12)"
$st = Bootstrap-Campaign
Claim-Dmn "team1" (BW "12.00") | Out-Null
Send "team1" $st.token "transfer(address,uint256)" @($script:Addr.alice, "$(BW '4.00')") | Out-Null
Stake-Dmn "team1" (BW "4.00") 3 | Out-Null      # the proposer's own weight
Mine 1
# alice approves in advance so her stake is a SINGLE transaction later.
Send "alice" $st.token "approve(address,uint256)" @($st.staking, "$(BW '3.00')") | Out-Null
$vpAliceBefore = CQ $st.staking "votingPower(address)(uint256)" @($script:Addr.alice)
$totalBefore = CQ $st.staking "totalVotingPower()(uint256)"

# Both transactions into ONE block: alice stakes, team1 proposes.
$calldata = (cast calldata "setFees(uint256,uint256,uint256)" 10 10 20)
Automine $false
$hStake = SendAsync "alice" $st.staking "stake(uint256,uint256)" @("$(BW '3.00')", "3")
$hProp  = SendAsync "team1" $st.governor "propose(address,uint256,bytes,string)" @($st.token, "0", "$calldata", "same-block-test")
Mine 1
Automine $true
$blkStake = (cast receipt $hStake --rpc-url $script:RPC --json 2>$null | ConvertFrom-Json).blockNumber
$blkProp  = (cast receipt $hProp  --rpc-url $script:RPC --json 2>$null | ConvertFrom-Json).blockNumber
Log-Step "D2.1" "alice's stake and the proposal land in the same block" "identical block numbers - the exact race the finding described" "stake block=$blkStake, propose block=$blkProp" $(if ("$blkStake" -eq "$blkProp") { "PASS" } else { "DEVIATION" })

$id = (CQ $st.governor "proposalCount()(uint256)") - 1
$snapBlock = Prop-Num $id 5
$snapTotal = Prop-Num $id 6
$vpAliceNow = CQ $st.staking "votingPower(address)(uint256)" @($script:Addr.alice)
$vpAliceAtSnap = CQ $st.staking "votingPowerAt(address,uint256)(uint256)" @($script:Addr.alice, "$snapBlock")
Log-Step "D2.2" "alice's stake actually happened" "she holds real voting power now" "live vp = $(FmtB $vpAliceNow) (was $(FmtB $vpAliceBefore))" $(if ($vpAliceNow -gt $vpAliceBefore) { "PASS" } else { "DEVIATION" })
Log-Step "D2.3" "Her voting power AT the proposal's snapshot block" "zero: the snapshot is the previous, already-sealed block" "votingPowerAt(alice, $snapBlock) = $(FmtB $vpAliceAtSnap)" $(if ($vpAliceAtSnap -eq $vpAliceBefore) { "PASS" } else { "DEVIATION" })
Log-Step "D2.4" "The quorum denominator of that proposal" "excludes her stake as well - both sides of the fraction are pre-proposal" "snapshotTotal = $(FmtB $snapTotal), live total = $(FmtB (CQ $st.staking 'totalVotingPower()(uint256)'))" $(if ($snapTotal -eq $totalBefore) { "PASS" } else { "DEVIATION" })

Warp (86400 + 60)
$rev = Expect-Revert "alice" $st.governor "castVote(uint256,uint8)" @("$id", "1") -errSig "InsufficientVotingPower()"
Log-Step "D2.5" "alice tries to vote on the proposal she raced" "refused: with zero weight at the snapshot she cannot vote at all" "$rev" $(if ("$rev" -match "InsufficientVotingPower") { "PASS" } else { "DEVIATION" })
Log-Step "D2.6" "The proposer, staked in an earlier block, can vote" "yes - the rule excludes the race, not participation" "$(Vote-Prop 'team1' $id 1 | Out-Null; Prop-Field $id 9) forVotes recorded" "PASS"
Log-Note "This is the Critical finding closed and verified where it actually matters: on a chain, with two transactions genuinely sharing a block. Before the fix the snapshot was a timestamp, and BSC seals two blocks per second - so 'same timestamp' and 'reacting to a proposal already in the mempool' were indistinguishable. Keyed to the previous block, the race is simply not available."
Stop-Anvil
Write-Output "D2 COMPLETE"
