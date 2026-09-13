# H2 -- the maxTx finding on a public chain: a 3B claim from a non-owner
# reverts before 11a; oldowner does 11a (cap raised) then 11b (treasury
# exemption) LAST; the same claim passes 1:1 exactly; a claim below the cap
# behaves as in Level 2.
. $PSScriptRoot\lib.ps1
Load-Keystores
$st = S
if (-not $st.pokeTx) { throw "run H1f-swap-poke.ps1 first (H2 comes after the first poke)" }
if ($st.step11b) { throw "11b already done ($($st.step11b))" }
Log-Scenario "H2" "The 1.5B DMX cap binds claim() on Chapel: 3B refused before 11a, then 11a, then 11b last, then exact 1:1"

$cap = CQ $st.old "maxTxAmount()(uint256)"
$tlEx = CQRaw $st.old "excludedFromFee(address)(bool)" @($st.timelock)
$owner = CQRaw $st.old "owner()(address)"
$hOld = CQ $st.old "balanceOf(address)(uint256)" @($script:AddrBook.holder)
$hEx = CQRaw $st.old "excludedFromFee(address)(bool)" @($script:AddrBook.holder)
Log-Step "H2.1" "Predecessor state: neither 11a nor 11b done" "maxTxAmount == 1.50 B (the real DMX value); treasury NOT exempt; the holder is a plain holder (not the owner, not exempt) with 5.00 B" "maxTxAmount=$(FmtB $cap), excludedFromFee(timelock)=$tlEx, owner=$owner, holder old balance=$(FmtB $hOld), holder exempt=$hEx" "-" $(if ($cap -eq (BW "1.50") -and "$tlEx" -eq "false" -and "$owner".ToLower() -ne "$($script:AddrBook.holder)".ToLower() -and "$hEx" -eq "false" -and $hOld -eq (BW "5.00")) { "PASS" } else { "DEVIATION" })

# ---- A 3B claim: refused by the CAP (checked first), before 11a -----------
$amount = BW "3.00"
$tOld0 = CQ $st.old "balanceOf(address)(uint256)" @($st.timelock)
$hDmn0 = CQ $st.token "balanceOf(address)(uint256)" @($script:AddrBook.holder)
$hA = Send "holder" $st.old "approve(address,uint256)" @($st.migration, "$amount") -NoInvariant
$rev = Expect-Revert "holder" $st.migration "claim(uint256)" @("$amount") -errSig "Transfer amount exceeds the maxTxAmount."
$tOld1 = CQ $st.old "balanceOf(address)(uint256)" @($st.timelock)
$hDmn1 = CQ $st.token "balanceOf(address)(uint256)" @($script:AddrBook.holder)
$migr = CQ $st.migration "migratedAmount(address)(uint256)" @($script:AddrBook.holder)
Log-Step "H2.2" "The holder claims 3.00 B (twice the cap) BEFORE 11a" "REVERTS with the predecessor's own cap message: the cap is checked before the fee, so it is the cap -- not AmountMismatch -- that refuses" "approve ok; claim: $rev" $hA.hash $(if ("$rev" -match "reverted with Transfer amount exceeds the maxTxAmount") { "PASS" } else { "DEVIATION" })
Log-Step "H2.3" "State after the refused claim" "nothing moved, nothing credited: treasury old delta 0, holder DMN delta 0, migratedAmount 0" "treasury old delta=$($tOld1 - $tOld0), holder DMN delta=$($hDmn1 - $hDmn0), migratedAmount=$migr" "-" $(if (($tOld1 - $tOld0) -eq 0 -and ($hDmn1 - $hDmn0) -eq 0 -and $migr -eq 0) { "PASS" } else { "DEVIATION" })

# ---- 11a: a non-owner refused, then the owner raises the cap -------------
$rev2 = Expect-Revert "holder" $st.old "setMaxTxAmount(uint256)" @("$(BW '1000.00')") -errSig "DMX: only owner"
$h11a = Send "oldowner" $st.old "setMaxTxAmount(uint256)" @("$(BW '1000.00')")
$cap2 = CQ $st.old "maxTxAmount()(uint256)"
Log-Step "H2.4" "Step 11a: setMaxTxAmount(1000.00 B) -- the holder first, then the owner" "the holder is refused (onlyOwner); the owner's call is read back from the chain" "holder: $rev2; owner: maxTxAmount $(FmtB $cap) -> $(FmtB $cap2)" $h11a.hash $(if ("$rev2" -match "reverted" -and $cap2 -eq (BW "1000.00")) { "PASS" } else { "DEVIATION" })

# ---- 11b LAST: excludeFromFee(TIMELOCK) -- the window opens ---------------
$h11b = Send "oldowner" $st.old "excludeFromFee(address)" @($st.timelock)
$ex = CQRaw $st.old "excludedFromFee(address)(bool)" @($st.timelock)
$exMig = CQRaw $st.old "excludedFromFee(address)(bool)" @($st.migration)
Log-Step "H2.5" "Step 11b, LAST: excludeFromFee(TIMELOCK) on the predecessor -- the TREASURY, not the Migration" "exemption active on the Timelock, none on the Migration: the migration window OPENS here" "excludedFromFee(timelock)=$ex, excludedFromFee(migration)=$exMig" $h11b.hash $(if ("$ex" -eq "true" -and "$exMig" -eq "false") { "PASS" } else { "DEVIATION" })

# ---- The same 3B claim now passes, exact on both legs ---------------------
$tOld3 = CQ $st.old "balanceOf(address)(uint256)" @($st.timelock)
$hOld3 = CQ $st.old "balanceOf(address)(uint256)" @($script:AddrBook.holder)
$hDmn3 = CQ $st.token "balanceOf(address)(uint256)" @($script:AddrBook.holder)
$hC = Send "holder" $st.migration "claim(uint256)" @("$amount")
$tOld4 = CQ $st.old "balanceOf(address)(uint256)" @($st.timelock)
$hOld4 = CQ $st.old "balanceOf(address)(uint256)" @($script:AddrBook.holder)
$hDmn4 = CQ $st.token "balanceOf(address)(uint256)" @($script:AddrBook.holder)
$migr4 = CQ $st.migration "migratedAmount(address)(uint256)" @($script:AddrBook.holder)
Log-Step "H2.6" "The holder repeats the SAME 3.00 B claim after 11a + 11b (the approve of H2.2 still stands)" "passes: 1:1, no fee on either leg -- the treasury receives EXACTLY 3.00 B of mock DMX, the holder EXACTLY 3.00 B DMN, the holder's old balance down by exactly 3.00 B, migratedAmount 3.00 B" "treasury old +$($tOld4 - $tOld3) wei ($(FmtB ($tOld4 - $tOld3))), holder old -$(FmtB ($hOld3 - $hOld4)), holder DMN +$($hDmn4 - $hDmn3) wei ($(FmtB ($hDmn4 - $hDmn3))), migratedAmount=$(FmtB $migr4); gas=$($hC.gasUsed)" $hC.hash $(if (($tOld4 - $tOld3) -eq $amount -and ($hOld3 - $hOld4) -eq $amount -and ($hDmn4 - $hDmn3) -eq $amount -and $migr4 -eq $amount) { "PASS" } else { "DEVIATION" })

# ---- A claim below the cap: as in Level 2 --------------------------------
$small = BW "1.00"
$tOld5 = CQ $st.old "balanceOf(address)(uint256)" @($st.timelock)
$hDmn5 = CQ $st.token "balanceOf(address)(uint256)" @($script:AddrBook.holder)
$hC2 = Claim-Dmn "holder" $small
$tOld6 = CQ $st.old "balanceOf(address)(uint256)" @($st.timelock)
$hDmn6 = CQ $st.token "balanceOf(address)(uint256)" @($script:AddrBook.holder)
$migr6 = CQ $st.migration "migratedAmount(address)(uint256)" @($script:AddrBook.holder)
Log-Step "H2.7" "The holder claims 1.00 B, below the (old) cap" "identical to Level 2 P1.5.3: exact 1:1, migratedAmount accumulates to 4.00 B" "treasury old +$(FmtB ($tOld6 - $tOld5)), holder DMN +$(FmtB ($hDmn6 - $hDmn5)) ($($hDmn6 - $hDmn5) wei), migratedAmount=$(FmtB $migr6); gas=$($hC2.gasUsed)" $hC2.hash $(if (($tOld6 - $tOld5) -eq $small -and ($hDmn6 - $hDmn5) -eq $small -and $migr6 -eq ($amount + $small)) { "PASS" } else { "DEVIATION" })

$treOld = CQ $st.old "balanceOf(address)(uint256)" @($st.timelock)
$total = CQ $st.migration "totalMigrated()(uint256)"
$tlDmn = CQ $st.token "balanceOf(address)(uint256)" @($st.timelock)
Log-Step "H2.8" "The treasury (= the Timelock) through the day" "old balance == totalMigrated (every claim of the day: the two owner claims and the holder's two); zero DMN, zero BNB" "treasury old=$(FmtB $treOld) ($treOld wei), totalMigrated=$(FmtB $total) ($total wei); DMN=$tlDmn, BNB=$(FmtT (Bal $st.timelock))" "-" $(if ($treOld -eq $total -and $tlDmn -eq 0 -and (Bal $st.timelock) -eq 0) { "PASS" } else { "DEVIATION" })
Log-Note "Launch order step 11a earning its place on a public chain: with the cap at its real value, a 3B claim is refused by the predecessor before any fee logic runs -- and with 11b deliberately done LAST, the window opened only after the cap was raised. Once raised, the same claim clears to the wei on both legs."
$st | Add-Member -NotePropertyName step11a -NotePropertyValue $h11a.hash -Force
$st | Add-Member -NotePropertyName step11b -NotePropertyValue $h11b.hash -Force
Save-State $st
Write-Output "H2 COMPLETE"
