# F2 - Two governance calls in one window: approve, then deposit.
. .\script\campaign\lib.ps1
Log-Scenario "F2" "Treasury deploying capital: approve and deposit as two proposals in one window"
$st = Bootstrap-Campaign
Claim-Dmn "team1" (BW "20.00") | Out-Null
Setup-Pool "team1" "4.00" | Out-Null
Stake-Dmn "team1" (BW "4.00") 3 | Out-Null
# Fund the treasury: DMN and BNB.
Send "team1" $st.token "transfer(address,uint256)" @($st.timelock, "$(BW '4.00')") | Out-Null
SendValue "stranger" $st.timelock "4000000000000000000" | Out-Null
$tlDmn = CQ $st.token "balanceOf(address)(uint256)" @($st.timelock)
$tlBnb = Bal $st.timelock
Mine 1
Log-Step "F2.1" "The treasury holds both legs" "DMN and BNB in the Timelock, ready to be deployed by vote" "DMN $(FmtB $tlDmn), BNB $(FmtT $tlBnb)" $(if ($tlDmn -gt 0 -and $tlBnb -gt 0) { "PASS" } else { "DEVIATION" })

# Two proposals raised together: the Governor takes ONE call each.
$approveData = (cast calldata "approve(address,uint256)" $script:ROUTER "$tlDmn")
$idA = Propose-Call "team1" $st.token "$approveData" "treasury-approve-router"
$addData = (cast calldata "addLiquidityETH(address,uint256,uint256,uint256,address,uint256)" $st.token "$tlDmn" "0" "0" $st.timelock "99999999999")
$idB = Propose-Call "team1" $script:ROUTER "$addData" "treasury-add-liquidity" -value "2000000000000000000"
Log-Step "F2.2" "Both raised in the same window" "one call per proposal, so a two-step operation is two proposals running in parallel" "ids $idA and $idB, both $(Prop-State $idA)/$(Prop-State $idB)" $(if ((Prop-State $idA) -eq "Pending" -and (Prop-State $idB) -eq "Pending") { "PASS" } else { "DEVIATION" })

Warp (86400 + 60)
Vote-Prop "team1" $idA 1 | Out-Null
Vote-Prop "team1" $idB 1 | Out-Null
Warp (5 * 86400 + 60)
Queue-Prop $idA | Out-Null
Queue-Prop $idB | Out-Null
Warp (7 * 86400 + 60)
$resBefore = Pair-Reserves
Exec-Prop $idA | Out-Null
$allowance = CQ $st.token "allowance(address,address)(uint256)" @($st.timelock, $script:ROUTER)
Log-Step "F2.3" "First proposal executes: the treasury approves the router" "an allowance now exists, set by vote and not by any individual" "allowance = $(FmtB $allowance)" $(if ($allowance -gt 0) { "PASS" } else { "DEVIATION" })

Exec-Prop $idB | Out-Null
$resAfter = Pair-Reserves
$lp = CQ $st.pair "balanceOf(address)(uint256)" @($st.timelock)
Log-Step "F2.4" "Second proposal executes: the treasury deposits into the pool" "reserves grow on both sides and the LP position is held by the Timelock itself" "DMN reserve $(FmtB $resBefore[0]) -> $(FmtB $resAfter[0]), BNB $(FmtT $resBefore[1]) -> $(FmtT $resAfter[1]), LP held = $(FmtT $lp)" $(if ($resAfter[0] -gt $resBefore[0] -and $lp -gt 0) { "PASS" } else { "DEVIATION" })
$mk = CQ $st.token "balanceOf(address)(uint256)" @($script:MARKETING)
Log-Step "F2.5" "Marketing wallet through a treasury operation" "zero" "DMN=$mk" $(if ($mk -eq 0) { "PASS" } else { "DEVIATION" })
Log-Note "A two-call DeFi interaction is two proposals, not one transaction - but they can run side by side and land in the same window, so the cost is one 13-day cycle rather than two. The LP tokens come back to the Timelock, which means the position itself stays under the same governance that opened it."
Stop-Anvil
Write-Output "F2 COMPLETE"
