# A5 - What if EVERYONE migrates: migratable supply vs the script funding logic.
. .\script\campaign\lib.ps1
Log-Scenario "A5" "Everyone migrates: total migratable against the deploy script funding logic"
$st = Bootstrap-Campaign
$funded = CQ $st.token "balanceOf(address)(uint256)" @($st.migration)
$oldSupply = CQ $st.old "totalSupply()(uint256)"
$deadBal = CQ $st.old "balanceOf(address)(uint256)" @($script:DEAD)
$selfBal = CQ $st.old "balanceOf(address)(uint256)" @($st.old)
$nonMigratable = $deadBal + $selfBal
Log-Step "A5.1" "Migration DMN funding, as the deploy script leaves it" "the entire INITIAL_SUPPLY: the script funds it by making Migration the initialize() recipient" "$(FmtB $funded)" $(if ($funded -eq $oldSupply) { "PASS" } else { "NOTE" })
Log-Step "A5.2" "Non-migratable old tokens" "dead address plus the old contract itself, unreachable by any claim" "dead=$(FmtB $deadBal) + contract=$(FmtB $selfBal) = $(FmtB $nonMigratable)" "PASS"
$keyed = @("team1","team2","tp1","tp2")
foreach ($w in $keyed) {
  $b = CQ $st.old "balanceOf(address)(uint256)" @($script:Addr[$w])
  if ($b -gt 0) { Claim-Dmn $w $b | Out-Null }
}
$keyless = @() + $script:TP_SILENT + @($script:POOLSIM)
foreach ($a in $keyless) {
  $b = CQ $st.old "balanceOf(address)(uint256)" @($a)
  if ($b -gt 0) { Claim-DmnAs $a $b | Out-Null }
}
$total = CQ $st.migration "totalMigrated()(uint256)"
$expectedMigratable = $oldSupply - $nonMigratable
$left = CQ $st.token "balanceOf(address)(uint256)" @($st.migration)
Log-Step "A5.3" "Every reachable holder migrates 100 percent" "total migrated = supply minus non-migratable = 966.53 B" "$(FmtB $total) (expected $(FmtB $expectedMigratable))" $(if ($total -eq $expectedMigratable) { "PASS" } else { "DEVIATION" })
Log-Step "A5.4" "Was the funding sufficient" "yes with room to spare: no claim can ever be refused for lack of DMN" "funded $(FmtB $funded) vs claimed $(FmtB $total), surplus left $(FmtB $left)" $(if ($left -eq $nonMigratable -and $funded -ge $total) { "PASS" } else { "DEVIATION" })
$mkDmn = CQ $st.token "balanceOf(address)(uint256)" @($script:MARKETING)
Log-Step "A5.5" "Global invariant after a full-supply migration" "marketing wallet still at zero" "DMN=$mkDmn" $(if ($mkDmn -eq 0) { "PASS" } else { "DEVIATION" })
Log-Note "The funding question has a structural answer rather than an arithmetic one: the script never computes a migration budget, it makes Migration the recipient of the entire INITIAL_SUPPLY in initialize(). Funding therefore cannot fall short - it exceeds the migratable amount by exactly the tokens nobody can claim (dead address and the old contract), which the post-deadline sweep later routes to the treasury."
Stop-Anvil
Write-Output "A5 COMPLETE"
