# F3 - The Timelock is not fee-exempt, but its outflows are maxTx-exempt.
. .\script\campaign\lib.ps1
Log-Scenario "F3" "Treasury and the token's own rules: fees apply, maxTx does not"
$st = Bootstrap-Campaign
Claim-Dmn "team1" (BW "30.00") | Out-Null
Stake-Dmn "team1" (BW "4.00") 3 | Out-Null
$exempt0 = CQRaw $st.token "isExcludedFromFee(address)(bool)" @($st.timelock)
$maxTx = CQ $st.token "maxTxAmount()(uint256)"
Log-Step "F3.1" "Is the Timelock fee-exempt out of the box?" "no - the deploy script grants it governance, not a fee exemption" "isExcludedFromFee(timelock) = $exempt0" $(if ("$exempt0" -eq "false") { "PASS" } else { "DEVIATION" })

# Fund it with more than maxTxAmount, in chunks the sender is allowed to move.
$sent = BW "3.00"
Send "team1" $st.token "transfer(address,uint256)" @($st.timelock, "$sent") | Out-Null
$held1 = CQ $st.token "balanceOf(address)(uint256)" @($st.timelock)
Send "team1" $st.token "transfer(address,uint256)" @($st.timelock, "$sent") | Out-Null
$held2 = CQ $st.token "balanceOf(address)(uint256)" @($st.timelock)
Log-Step "F3.2" "Sending 3.00 B into the treasury" "it arrives net of the 5% fee: the treasury pays like anyone else" "sent $(FmtB $sent), credited $(FmtB $held1)" $(if ($held1 -lt $sent) { "PASS" } else { "DEVIATION" })
Log-Step "F3.3" "Treasury balance now exceeds maxTxAmount" "6.00 B in, against a 5.00 B per-transaction cap for ordinary holders" "held $(FmtB $held2), maxTxAmount $(FmtB $maxTx)" $(if ($held2 -gt $maxTx) { "PASS" } else { "DEVIATION" })

Mine 1
$dest = $script:TP_SILENT[3]
$outData = (cast calldata "transfer(address,uint256)" $dest "$held2")
$idA = Propose-Call "team1" $st.token "$outData" "treasury-outflow-above-maxtx"
$exemptData = (cast calldata "setExcludedFromFee(address,bool)" $st.timelock "true")
$idB = Propose-Call "team1" $st.token "$exemptData" "exempt-the-treasury"
Warp (86400 + 60); Vote-Prop "team1" $idA 1 | Out-Null; Vote-Prop "team1" $idB 1 | Out-Null
Warp (5 * 86400 + 60); Queue-Prop $idA | Out-Null; Queue-Prop $idB | Out-Null
Warp (7 * 86400 + 60)
$destBefore = CQ $st.token "balanceOf(address)(uint256)" @($dest)
Exec-Prop $idA | Out-Null
$destAfter = CQ $st.token "balanceOf(address)(uint256)" @($dest)
$received = $destAfter - $destBefore
Log-Step "F3.4" "A governance-voted outflow of 6.00 B, above the per-transaction cap" "it goes through: holding GOVERNANCE_ROLE exempts the sender from maxTxAmount" "moved $(FmtB $held2) in one transaction, recipient credited $(FmtB $received)" $(if ($received -gt 0) { "PASS" } else { "DEVIATION" })
Log-Step "F3.5" "Was that outflow taxed?" "yes - the exemption and the cap are separate things" "sent $(FmtB $held2), received $(FmtB $received), fee $(FmtB ($held2 - $received))" $(if ($received -lt $held2) { "PASS" } else { "DEVIATION" })

Exec-Prop $idB | Out-Null
$exempt1 = CQRaw $st.token "isExcludedFromFee(address)(bool)" @($st.timelock)
Send "team1" $st.token "transfer(address,uint256)" @($st.timelock, "$(BW '2.00')") | Out-Null
$heldNow = CQ $st.token "balanceOf(address)(uint256)" @($st.timelock)
Log-Step "F3.6" "After a proposal exempts the treasury" "transfers involving it stop paying the fee - a governance decision, with its own 13 days" "isExcludedFromFee = $exempt1, 2.00 B sent arrived as $(FmtB $heldNow)" $(if ("$exempt1" -eq "true" -and $heldNow -ge (BW "2.00")) { "PASS" } else { "DEVIATION" })
Log-Note "Two independent properties that are easy to conflate: the Timelock is exempt from maxTxAmount by virtue of GOVERNANCE_ROLE, so a treasury outflow of any size clears in one transaction - but it is NOT fee-exempt, so every DMN movement in or out is taxed until a proposal says otherwise. A treasury holding DMN should decide that deliberately rather than discover it."
Stop-Anvil
Write-Output "F3 COMPLETE"
