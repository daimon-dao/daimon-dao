# F1 - The Timelock as a multi-asset treasury: it receives and it holds.
. .\script\campaign\lib.ps1
Log-Scenario "F1" "The Timelock custodies BNB and BEP-20 tokens"
$st = Bootstrap-Campaign
Claim-Dmn "team1" (BW "12.00") | Out-Null

$bnbBefore = Bal $st.timelock
SendValue "stranger" $st.timelock "5000000000000000000" | Out-Null
$bnbAfter = Bal $st.timelock
Log-Step "F1.1" "Anyone sends 5 BNB to the Timelock" "accepted: it has a receive() and cannot refuse funds" "$(FmtT $bnbBefore) -> $(FmtT $bnbAfter) BNB" $(if (($bnbAfter - $bnbBefore) -eq [System.Numerics.BigInteger]::Parse("5000000000000000000")) { "PASS" } else { "DEVIATION" })

Send "team1" $st.token "transfer(address,uint256)" @($st.timelock, "$(BW '2.00')") | Out-Null
$dmnHeld = CQ $st.token "balanceOf(address)(uint256)" @($st.timelock)
Send "team1" $st.old "transfer(address,uint256)" @($st.timelock, "$(BW '1.00')") | Out-Null
$oldHeld = CQ $st.old "balanceOf(address)(uint256)" @($st.timelock)
Log-Step "F1.2" "Two different BEP-20s sent to the same address" "both held: an ERC20 credit needs nothing from the recipient" "DMN $(FmtB $dmnHeld), predecessor $(FmtB $oldHeld)" $(if ($dmnHeld -gt 0 -and $oldHeld -gt 0) { "PASS" } else { "DEVIATION" })

$revBnb = Expect-Revert "stranger" $st.timelock "execute(address,uint256,bytes,bytes32,bytes32)" @($script:Addr.stranger, "1000000000000000000", "0x", "0x0000000000000000000000000000000000000000000000000000000000000000", "0x0000000000000000000000000000000000000000000000000000000000000000")
Log-Step "F1.3" "A stranger tries to walk funds out of the Timelock" "refused: execute() is role-gated and only the Governor holds it" "$revBnb" $(if ("$revBnb" -match "reverted") { "PASS" } else { "DEVIATION" })
$revGuard = Expect-Revert "guardian" $st.timelock "execute(address,uint256,bytes,bytes32,bytes32)" @($script:Addr.guardian, "1000000000000000000", "0x", "0x0000000000000000000000000000000000000000000000000000000000000000", "0x0000000000000000000000000000000000000000000000000000000000000000")
Log-Step "F1.4" "The guardian tries the same" "refused too - its powers are negative only, never spending" "$revGuard" $(if ("$revGuard" -match "reverted") { "PASS" } else { "DEVIATION" })
Log-Note "Custody needs no new code: the Timelock accepts native BNB through its receive() and any BEP-20 by the ordinary credit, and the only door out is execute(), which the Governor alone can open - and only for an operation that has been through the vote and the delay."
Stop-Anvil
Write-Output "F1 COMPLETE"
