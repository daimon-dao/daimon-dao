# A2 - A holder migrates a partial amount.
. .\script\campaign\lib.ps1
Log-Scenario "A2" "Partial migration: 1:1 credit, old tokens out of circulation"
$st = Bootstrap-Campaign
$part = BW "30.00"
$oldBefore = CQ $st.old "balanceOf(address)(uint256)" @($script:Addr.tp1)
$trBefore  = CQ $st.old "balanceOf(address)(uint256)" @($script:TREASURY)
$migBefore = CQ $st.token "balanceOf(address)(uint256)" @($st.migration)
Claim-Dmn "tp1" $part | Out-Null
$oldAfter = CQ $st.old "balanceOf(address)(uint256)" @($script:Addr.tp1)
$dmn      = CQ $st.token "balanceOf(address)(uint256)" @($script:Addr.tp1)
$trAfter  = CQ $st.old "balanceOf(address)(uint256)" @($script:TREASURY)
$migAfter = CQ $st.token "balanceOf(address)(uint256)" @($st.migration)
$recorded = CQ $st.migration "migratedAmount(address)(uint256)" @($script:Addr.tp1)
$total    = CQ $st.migration "totalMigrated()(uint256)"
Log-Step "A2.1" "tp1 (76.90 B of old) migrates 30.00 B" "receives exactly 30.00 B DMN" "$(FmtB $dmn)" $(if ($dmn -eq $part) { "PASS" } else { "DEVIATION" })
Log-Step "A2.2" "tp1 old-token balance after the partial claim" "76.90 - 30.00 = 46.90 B left" "$(FmtB $oldAfter) (was $(FmtB $oldBefore))" $(if ($oldAfter -eq ($oldBefore - $part)) { "PASS" } else { "DEVIATION" })
Log-Step "A2.3" "Where the old tokens went" "the treasury holds them: out of circulation, not burned" "treasury +$(FmtB ($trAfter - $trBefore))" $(if (($trAfter - $trBefore) -eq $part) { "PASS" } else { "DEVIATION" })
Log-Step "A2.4" "Migration DMN reserve" "down by exactly what it credited" "-$(FmtB ($migBefore - $migAfter))" $(if (($migBefore - $migAfter) -eq $part) { "PASS" } else { "DEVIATION" })
Log-Step "A2.5" "Migration internal accounting" "migratedAmount[tp1] = totalMigrated = 30.00 B" "per-account=$(FmtB $recorded), total=$(FmtB $total)" $(if ($recorded -eq $part -and $total -eq $part) { "PASS" } else { "DEVIATION" })
Stop-Anvil
Write-Output "A2 COMPLETE"
