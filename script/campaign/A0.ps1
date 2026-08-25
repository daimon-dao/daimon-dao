# A0 - Predecessor configuration (#29, BLOCKING) + counter-proof.
. .\script\campaign\lib.ps1

Log-Scenario "A0" "Predecessor configuration (Zenith #29) - BLOCKING, with counter-proof"

# ---- main case: the CORRECT configuration --------------------------------
$st = Bootstrap-Campaign          # does excludeFromFee(TREASURY) before deploying
Log-Step "A0.1" "Deploy the predecessor, distribute the 1000 B model, exempt the TREASURY (not Migration), then run the real Deploy.s.sol" "preflight applied before Migration exists; deploy completes" "old=$($st.old) migration=$($st.migration)" "PASS"

$exTreasury = CQ $st.old "excludedFromFee(address)(bool)" @($script:TREASURY)
$exMigr     = CQ $st.old "excludedFromFee(address)(bool)" @($st.migration)
Log-Step "A0.2" "Read the exemption flags on the predecessor" "treasury exempt = true, Migration exempt = false" "treasury=$exTreasury, migration=$exMigr" $(if ("$exTreasury" -eq "true" -and "$exMigr" -eq "false") { "PASS" } else { "DEVIATION" })

# A NON-exempt holder claims: the treasury must receive the EXACT amount.
$amount = BW "10.00"
$tBefore = CQ $st.old "balanceOf(address)(uint256)" @($script:TREASURY)
$hBefore = CQ $st.token "balanceOf(address)(uint256)" @($script:Addr.team1)
Claim-Dmn "team1" $amount | Out-Null
$tAfter = CQ $st.old "balanceOf(address)(uint256)" @($script:TREASURY)
$hAfter = CQ $st.token "balanceOf(address)(uint256)" @($script:Addr.team1)
$delta  = $tAfter - $tBefore
$got    = $hAfter - $hBefore
Log-Step "A0.3" "team1 (NOT exempt) claims 10.00 B" "treasury receives EXACTLY 10.00 B, no fee deducted" "treasury delta = $(FmtB $delta)" $(if ($delta -eq $amount) { "PASS" } else { "DEVIATION" })
Log-Step "A0.4" "Check the new-token leg of the same claim" "claimant receives exactly 10.00 B DMN, 1:1" "received = $(FmtB $got)" $(if ($got -eq $amount) { "PASS" } else { "DEVIATION" })

# ---- counter-proof: the WRONG configuration, throwaway state --------------
$st2 = Bootstrap-Campaign -SkipTreasuryPreflight
Send "deployer" $st2.old "excludeFromFee(address)" @($st2.migration) -NoInvariant | Out-Null
$exT2 = CQ $st2.old "excludedFromFee(address)(bool)" @($script:TREASURY)
$exM2 = CQ $st2.old "excludedFromFee(address)(bool)" @($st2.migration)
Log-Step "A0.5" "COUNTER-PROOF, throwaway state: exempt the Migration contract INSTEAD of the treasury" "treasury exempt = false, Migration exempt = true" "treasury=$exT2, migration=$exM2" $(if ("$exT2" -eq "false" -and "$exM2" -eq "true") { "PASS" } else { "DEVIATION" })

Send "team1" $st2.old "approve(address,uint256)" @($st2.migration, "$amount") -NoInvariant | Out-Null
$t2Before = CQ $st2.old "balanceOf(address)(uint256)" @($script:TREASURY)
$rev = Expect-Revert "team1" $st2.migration "claim(uint256)" @("$amount") -errSig "AmountMismatch()"
$t2After = CQ $st2.old "balanceOf(address)(uint256)" @($script:TREASURY)
Log-Step "A0.6" "team1 claims under the WRONG configuration" "the fee IS deducted, the claim fails visibly (AmountMismatch), nothing is credited" "$rev; treasury delta = $(FmtB ($t2After - $t2Before))" $(if ($t2After -eq $t2Before) { "PASS" } else { "DEVIATION" })

$fee = ($amount * 110) / 1000
Log-Note "The counter-proof is the point: with the wrong exemption the predecessor deducts its 11% fee on the claimant->treasury leg ($(FmtB $fee) on a $(FmtB $amount) claim), the treasury receives less than declared, and DaimonMigration's exact-delta check refuses to credit anything. The wrong configuration cannot pass silently - it stops the migration until it is fixed, which is why the checklist marks it BLOCKING."
Stop-Anvil
Write-Output "A0 COMPLETE"
