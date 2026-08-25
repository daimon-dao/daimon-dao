# D3 - Voting and quorum computed on the snapshot.
. .\script\campaign\lib.ps1
Log-Scenario "D3" "Vote and quorum: the bar is the snapshot, and later staking cannot move it"
$st = Bootstrap-Campaign
Claim-Dmn "team1" (BW "12.00") | Out-Null
Send "team1" $st.token "transfer(address,uint256)" @($script:Addr.alice, "$(BW '4.00')") | Out-Null
Stake-Dmn "team1" (BW "4.00") 3 | Out-Null     # 16 B of weight
Stake-Dmn "alice" (BW "3.00") 0 | Out-Null     # 3 B of weight
Mine 1
$calldata = (cast calldata "setFees(uint256,uint256,uint256)" 10 10 20)
$id = Propose-Call "team1" $st.token "$calldata" "quorum-test"
$snapTotal = Prop-Num $id 6
$snapBps = Prop-Num $id 16
$needed = ($snapTotal * $snapBps) / 10000
Log-Step "D3.1" "The bar this proposal must clear" "10% of the voting power that existed at the snapshot" "quorum needed = $(FmtB $needed) of $(FmtB $snapTotal)" $(if ($needed -eq ($snapTotal / 10)) { "PASS" } else { "DEVIATION" })

Warp (86400 + 60)
Log-Step "D3.2" "Proposal state once the voting delay elapses" "Active" "$(Prop-State $id)" $(if ((Prop-State $id) -eq "Active") { "PASS" } else { "DEVIATION" })
Vote-Prop "team1" $id 1 | Out-Null
$forVotes = Prop-Num $id 9
Log-Step "D3.3" "team1 votes in favour with its snapshot weight" "its 16 B of weight is recorded, clearing the bar on its own" "forVotes = $(FmtB $forVotes), needed = $(FmtB $needed)" $(if ($forVotes -ge $needed) { "PASS" } else { "DEVIATION" })

# Somebody stakes a large position AFTER the vote: the bar must not move.
Claim-Dmn "team2" (BW "12.00") | Out-Null
Stake-Dmn "team2" (BW "4.00") 3 | Out-Null
Mine 1
$snapTotal2 = Prop-Num $id 6
$liveTotal = CQ $st.staking "totalVotingPower()(uint256)"
Log-Step "D3.4" "A whale stakes 16 B of fresh weight mid-vote" "the live total jumps, this proposal's denominator does not" "live $(FmtB $liveTotal) vs proposal denominator $(FmtB $snapTotal2)" $(if ($snapTotal2 -eq $snapTotal -and $liveTotal -gt $snapTotal) { "PASS" } else { "DEVIATION" })

Warp (5 * 86400 + 60)
$state = Prop-State $id
Log-Step "D3.5" "State at the end of the voting period" "Succeeded: quorum met on the snapshot, for-votes ahead" "$state" $(if ($state -eq "Succeeded") { "PASS" } else { "DEVIATION" })
Log-Note "The whale that appeared mid-vote is exactly the actor the snapshot exists to neutralize: 16 B of new weight, arriving after the question was asked, changed neither the bar nor the tally."
Stop-Anvil
Write-Output "D3 COMPLETE"
