# A4 - A holder migrates 100% in a single call.
. .\script\campaign\lib.ps1
Log-Scenario "A4" "Full migration in one call: exact 1:1"
$st = Bootstrap-Campaign
$bal = CQ $st.old "balanceOf(address)(uint256)" @($script:Addr.tp2)
Claim-Dmn "tp2" $bal | Out-Null
$dmn = CQ $st.token "balanceOf(address)(uint256)" @($script:Addr.tp2)
$oldLeft = CQ $st.old "balanceOf(address)(uint256)" @($script:Addr.tp2)
$tr = CQ $st.old "balanceOf(address)(uint256)" @($script:TREASURY)
Log-Step "A4.1" "tp2 migrates its entire holding in one transaction" "DMN received equals the old balance exactly, to the wei" "old was $(FmtB $bal), DMN now $(FmtB $dmn)" $(if ($dmn -eq $bal) { "PASS" } else { "DEVIATION" })
Log-Step "A4.2" "tp2 old balance afterwards" "zero" "$(FmtB $oldLeft)" $(if ($oldLeft -eq 0) { "PASS" } else { "DEVIATION" })
Log-Step "A4.3" "Treasury custody" "holds exactly the migrated amount" "$(FmtB $tr)" $(if ($tr -eq $bal) { "PASS" } else { "DEVIATION" })
Stop-Anvil
Write-Output "A4 COMPLETE"
