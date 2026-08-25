# A3 - The same holder migrates the remainder: no double counting.
. .\script\campaign\lib.ps1
Log-Scenario "A3" "Second claim by the same holder: the remainder, with no double counting"
$st = Bootstrap-Campaign
$part = BW "30.00"; $rest = BW "46.90"; $all = BW "76.90"
Claim-Dmn "tp1" $part | Out-Null
Claim-Dmn "tp1" $rest | Out-Null
$oldLeft  = CQ $st.old "balanceOf(address)(uint256)" @($script:Addr.tp1)
$dmn      = CQ $st.token "balanceOf(address)(uint256)" @($script:Addr.tp1)
$recorded = CQ $st.migration "migratedAmount(address)(uint256)" @($script:Addr.tp1)
$total    = CQ $st.migration "totalMigrated()(uint256)"
$trBal    = CQ $st.old "balanceOf(address)(uint256)" @($script:TREASURY)
Log-Step "A3.1" "tp1 claims the remaining 46.90 B after the earlier 30.00 B" "holds 76.90 B DMN in total, 1:1 across two claims" "$(FmtB $dmn)" $(if ($dmn -eq $all) { "PASS" } else { "DEVIATION" })
Log-Step "A3.2" "tp1 old balance" "zero: fully migrated" "$(FmtB $oldLeft)" $(if ($oldLeft -eq 0) { "PASS" } else { "DEVIATION" })
Log-Step "A3.3" "Per-account accounting after two claims" "migratedAmount[tp1] = 76.90 B, counted once, not twice" "$(FmtB $recorded)" $(if ($recorded -eq $all) { "PASS" } else { "DEVIATION" })
Log-Step "A3.4" "Protocol-wide total" "totalMigrated = 76.90 B, matching the treasury old-token holding" "total=$(FmtB $total), treasury=$(FmtB $trBal)" $(if ($total -eq $all -and $trBal -eq $all) { "PASS" } else { "DEVIATION" })
$rev = Expect-Revert "tp1" $st.migration "claim(uint256)" @("$part")
Log-Step "A3.5" "tp1 tries a third claim with nothing left" "fails: allowance and balance are both exhausted, nothing is credited twice" "$rev" $(if ("$rev" -match "reverted") { "PASS" } else { "DEVIATION" })
Stop-Anvil
Write-Output "A3 COMPLETE"
