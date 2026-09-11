# H2 - Level 2b, Day 0: the predecessor's transfer cap against claim().
# The mock now carries the real DMX _maxTxAmount (1.5B, H0.5). 11b is
# performed WITHOUT 11a on purpose: a 3B claim must be refused by the cap
# even with the fee exemption in place, and pass once the owner raises it.
. .\script\campaign\lib.ps1
$script:LOG = Join-Path $script:ROOT "docs\CHAPEL_2B_RESULTS.md"
Log-Scenario "H2" "The 1.5B DMX cap binds claim(): a 3B claim reverts before setMaxTxAmount, passes after (exact 1:1)"
Start-CampaignNode
$old = Deploy-OldToken
$st = Run-MainDeploy $old -DerivedTreasury -DerivedMarketing -SkipTreasuryPreflight

# 11b alone: the treasury (= the Timelock) is fee-exempt, the cap untouched.
Send "deployer" $st.old "excludeFromFee(address)" @($st.timelock) -NoInvariant | Out-Null
$cap = CQ $st.old "maxTxAmount()(uint256)"
$ex = CQRaw $st.old "excludedFromFee(address)(bool)" @($st.timelock)
$owner = CQRaw $st.old "owner()(address)"
$tp1Old = CQ $st.old "balanceOf(address)(uint256)" @($script:Addr.tp1)
Log-Step "H2.1" "Predecessor state: 11b done, 11a deliberately NOT done" "maxTxAmount == 1.50 B (the real DMX value); treasury exempt; tp1 is a plain holder (not the owner, not exempt) with 76.90 B" "maxTxAmount=$(FmtB $cap), excludedFromFee(timelock)=$ex, owner=$owner, tp1 old balance=$(FmtB $tp1Old), tp1 exempt=$(CQRaw $st.old 'excludedFromFee(address)(bool)' @($script:Addr.tp1))" $(if ($cap -eq (BW "1.50") -and "$ex" -eq "true" -and "$owner".ToLower() -ne "$($script:Addr.tp1)".ToLower()) { "PASS" } else { "DEVIATION" })

# ---- A 3B claim: refused by the cap, NOT by the fee -----------------------
$amount = BW "3.00"
$tOld0 = CQ $st.old "balanceOf(address)(uint256)" @($st.timelock)
Send "tp1" $st.old "approve(address,uint256)" @($st.migration, "$amount") -NoInvariant | Out-Null
$rev = Expect-Revert "tp1" $st.migration "claim(uint256)" @("$amount") -errSig "Transfer amount exceeds the maxTxAmount."
$tOld1 = CQ $st.old "balanceOf(address)(uint256)" @($st.timelock)
$tp1Dmn = CQ $st.token "balanceOf(address)(uint256)" @($script:Addr.tp1)
$migr = CQ $st.migration "migratedAmount(address)(uint256)" @($script:Addr.tp1)
Log-Step "H2.2" "tp1 claims 3.00 B (twice the cap) with the exemption in place" "REVERTS with the predecessor's own cap message: the fee exemption does NOT lift the cap" "$rev" $(if ("$rev" -match "reverted with Transfer amount exceeds the maxTxAmount") { "PASS" } else { "DEVIATION" })
Log-Step "H2.3" "State after the refused claim" "nothing moved, nothing credited: treasury old delta 0, tp1 DMN 0, migratedAmount 0" "treasury old delta=$(FmtB ($tOld1 - $tOld0)), tp1 DMN=$(FmtB $tp1Dmn), migratedAmount=$(FmtB $migr)" $(if (($tOld1 - $tOld0) -eq 0 -and $tp1Dmn -eq 0 -and $migr -eq 0) { "PASS" } else { "DEVIATION" })

# ---- Exactly at the cap: passes (the boundary is inclusive) ---------------
$atCap = BW "1.50"
Claim-Dmn "tp1" $atCap | Out-Null
$tOld2 = CQ $st.old "balanceOf(address)(uint256)" @($st.timelock)
$tp1Dmn2 = CQ $st.token "balanceOf(address)(uint256)" @($script:Addr.tp1)
Log-Step "H2.4" "tp1 claims exactly 1.50 B" "passes: the cap is inclusive; exact 1:1" "treasury old +$(FmtB ($tOld2 - $tOld1)), tp1 DMN=$(FmtB $tp1Dmn2)" $(if (($tOld2 - $tOld1) -eq $atCap -and $tp1Dmn2 -eq $atCap) { "PASS" } else { "DEVIATION" })

# ---- 11a: the owner raises the cap ----------------------------------------
$rev2 = Expect-Revert "tp1" $st.old "setMaxTxAmount(uint256)" @("$(BW '1000.00')") -errSig "DMX: only owner"
Send "deployer" $st.old "setMaxTxAmount(uint256)" @("$(BW '1000.00')") -NoInvariant | Out-Null
$cap2 = CQ $st.old "maxTxAmount()(uint256)"
Log-Step "H2.5" "Step 11a: setMaxTxAmount(1000.00 B) -- a holder first, then the owner" "the holder is refused (onlyOwner); the owner's call is read back from the chain" "tp1: $rev2; owner: maxTxAmount $(FmtB $cap) -> $(FmtB $cap2)" $(if ("$rev2" -match "reverted" -and $cap2 -eq (BW "1000.00")) { "PASS" } else { "DEVIATION" })

# ---- The same 3B claim now passes, exact on both legs ---------------------
$tOld3 = CQ $st.old "balanceOf(address)(uint256)" @($st.timelock)
$tp1Old3 = CQ $st.old "balanceOf(address)(uint256)" @($script:Addr.tp1)
$tp1Dmn3 = CQ $st.token "balanceOf(address)(uint256)" @($script:Addr.tp1)
Claim-Dmn "tp1" $amount | Out-Null
$tOld4 = CQ $st.old "balanceOf(address)(uint256)" @($st.timelock)
$tp1Old4 = CQ $st.old "balanceOf(address)(uint256)" @($script:Addr.tp1)
$tp1Dmn4 = CQ $st.token "balanceOf(address)(uint256)" @($script:Addr.tp1)
$migr4 = CQ $st.migration "migratedAmount(address)(uint256)" @($script:Addr.tp1)
Log-Step "H2.6" "tp1 claims the same 3.00 B after 11a" "passes: 1:1, no fee on either leg -- the treasury receives EXACTLY 3.00 B of mock DMX, tp1 EXACTLY 3.00 B DMN, tp1's old balance down by exactly 3.00 B" "treasury old +$(FmtB ($tOld4 - $tOld3)) ($($tOld4 - $tOld3) wei), tp1 old -$(FmtB ($tp1Old3 - $tp1Old4)), tp1 DMN +$(FmtB ($tp1Dmn4 - $tp1Dmn3)) ($($tp1Dmn4 - $tp1Dmn3) wei), migratedAmount=$(FmtB $migr4)" $(if (($tOld4 - $tOld3) -eq $amount -and ($tp1Old3 - $tp1Old4) -eq $amount -and ($tp1Dmn4 - $tp1Dmn3) -eq $amount -and $migr4 -eq ($amount + $atCap)) { "PASS" } else { "DEVIATION" })

$tlDmn = CQ $st.token "balanceOf(address)(uint256)" @($st.timelock)
Log-Step "H2.7" "The marketing wallet (= the Timelock) through the scenario" "zero DMN, zero BNB" "DMN=$tlDmn, BNB=$(FmtT (Bal $st.timelock))" $(if ($tlDmn -eq 0 -and (Bal $st.timelock) -eq 0) { "PASS" } else { "DEVIATION" })
Log-Note "This is launch order step 11a earning its place: with the exemption alone, every holder above 1.5B is locked out by a revert that comes from the predecessor, not from the migration -- the 76.9B top holder included. The cap is a plain owner setting, and once raised the same claim clears exactly, to the wei, on both legs."
Stop-Anvil
Write-Output "H2 COMPLETE"
