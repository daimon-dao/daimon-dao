# E4 - An operation executed directly at the Timelock cannot be "cancelled" after the fact.
. .\script\campaign\lib.ps1
Log-Scenario "E4" "Already executed at the Timelock: Governor.cancel refuses (Zenith #26)"
$st = Bootstrap-Campaign
Claim-Dmn "team1" (BW "12.00") | Out-Null
Stake-Dmn "team1" (BW "4.00") 3 | Out-Null
Mine 1
$calldata = (cast calldata "setFees(uint256,uint256,uint256)" 10 10 20)
$id = Propose-Call "team1" $st.token "$calldata" "extra-executor"
Warp (86400 + 60); Vote-Prop "team1" $id 1 | Out-Null; Warp (5 * 86400 + 60)
Queue-Prop $id | Out-Null
$opId = Op-Id $id

# The configuration the finding warned about: governance grants a SECOND
# executor, which can then execute straight at the Timelock.
$execRole = CQRaw $st.timelock "EXECUTOR_ROLE()(bytes32)"
SendAs $st.timelock $st.timelock "grantRole(bytes32,address)" @($execRole, $script:Addr.stranger) | Out-Null
$hasRole = CQRaw $st.timelock "hasRole(bytes32,address)(bool)" @($execRole, $script:Addr.stranger)
Log-Step "E4.1" "Governance adds a second executor" "a legitimate configuration - and the one that made this edge reachable" "stranger holds EXECUTOR_ROLE = $hasRole" $(if ("$hasRole" -eq "true") { "PASS" } else { "DEVIATION" })

Warp (7 * 86400 + 60)
$target = Prop-Field $id 1; $value = Prop-Field $id 2; $data = Prop-Field $id 3; $salt = Prop-Field $id 15
$zero = "0x0000000000000000000000000000000000000000000000000000000000000000"
Send "stranger" $st.timelock "execute(address,uint256,bytes,bytes32,bytes32)" @($target, $value, $data, $zero, $salt) | Out-Null
$tax = CQ $st.token "taxFee()(uint256)"; $liq = CQ $st.token "liquidityFee()(uint256)"
$propExecutedFlag = Prop-Field $id 13
Log-Step "E4.2" "The second executor runs the operation straight at the Timelock" "it takes effect on the token, while the Governor's own executed flag stays false" "fees now $(($tax+$liq)/10)%, proposal.executed flag = $propExecutedFlag" $(if ($liq -eq 30 -and "$propExecutedFlag" -eq "false") { "PASS" } else { "DEVIATION" })

$rev = Expect-Revert "guardian" $st.governor "cancel(uint256)" @("$id") -errSig "AlreadyExecuted()"
$canceledFlag = Prop-Field $id 12
Log-Step "E4.3" "The guardian tries to cancel it afterwards" "refused with AlreadyExecuted: the Governor reads the Timelock and will not call something cancelled that already happened" "$rev" $(if ("$rev" -match "AlreadyExecuted") { "PASS" } else { "DEVIATION" })
Log-Step "E4.4" "The proposal's canceled flag" "still false - no divergence was created" "canceled=$canceledFlag" $(if ("$canceledFlag" -eq "false") { "PASS" } else { "DEVIATION" })
Log-Note "This is the exact configuration the finding described - an additional executor acting outside the Governor - and the fix holds where it counts: the Governor refuses to record as cancelled an action that already took effect on chain. The two contracts still agree."
Stop-Anvil
Write-Output "E4 COMPLETE"
