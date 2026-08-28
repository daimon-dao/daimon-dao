# P2.2 -- Migration under real conditions: one full, one partial, one late.
. $PSScriptRoot\lib.ps1
Load-Keystores
$st = S
Log-Scenario "P2.2" "Migration: full-balance, partial, and a holder who waits"

# holder1: FULL remaining balance (169B old left after the 1B claim of P1.5.3).
$oldBal = CQ $st.old "balanceOf(address)(uint256)" @($script:AddrBook.holder1)
$h1 = Send "holder1" $st.old "approve(address,uint256)" @($st.migration, "$oldBal")
$h2 = Send "holder1" $st.migration "claim(uint256)" @("$oldBal")
$dmn1 = CQ $st.token "balanceOf(address)(uint256)" @($script:AddrBook.holder1)
$oldAfter = CQ $st.old "balanceOf(address)(uint256)" @($script:AddrBook.holder1)
Log-Step "P2.2.1" "holder1 migrates the FULL remaining balance ($(FmtB $oldBal))" "old balance to zero, DMN 1:1 on top of what it already held" "old=$(FmtB $oldAfter), DMN=$(FmtB $dmn1); claim gas=$($h2.gasUsed)" $h2.hash $(if ($oldAfter -eq 0) { "PASS" } else { "DEVIATION" })

# holder2: PARTIAL -- 25B of 60B.
$h3 = Send "holder2" $st.old "approve(address,uint256)" @($st.migration, "25000000000000000000000000000")
$h4 = Send "holder2" $st.migration "claim(uint256)" @("25000000000000000000000000000")
$dmn2 = CQ $st.token "balanceOf(address)(uint256)" @($script:AddrBook.holder2)
$old2 = CQ $st.old "balanceOf(address)(uint256)" @($script:AddrBook.holder2)
Log-Step "P2.2.2" "holder2 migrates 25B of 60B (partial)" "35B old kept, 25B DMN exact" "old=$(FmtB $old2), DMN=$(FmtB $dmn2); gas=$($h4.gasUsed)" $h4.hash $(if ("$dmn2" -eq "25000000000000000000000000000" -and "$old2" -eq "35000000000000000000000000000") { "PASS" } else { "DEVIATION" })

# holder3: deliberately does NOT migrate yet -- the late holder the window exists for.
$old3 = CQ $st.old "balanceOf(address)(uint256)" @($script:AddrBook.holder3)
$dmn3 = CQ $st.token "balanceOf(address)(uint256)" @($script:AddrBook.holder3)
Log-Step "P2.2.3" "holder3 waits (models the late migrator)" "40B old untouched, zero DMN" "old=$(FmtB $old3), DMN=$(FmtB $dmn3)" "-" $(if ("$old3" -eq "40000000000000000000000000000" -and $dmn3 -eq 0) { "PASS" } else { "DEVIATION" })

# The old tokens collected so far sit at the TREASURY (= the Timelock).
$treOld = CQ $st.old "balanceOf(address)(uint256)" @($st.timelock)
$claimed = CQ $st.migration "totalMigrated()(uint256)"
Log-Step "P2.2.4" "Collected predecessor tokens sit at the treasury (the Timelock)" "treasury old balance == totalMigrated (claimant -> treasury path, #29 design)" "treasury old=$(FmtB $treOld), totalMigrated=$(FmtB $claimed)" "-" $(if ($treOld -eq $claimed) { "PASS" } else { "DEVIATION" })
Write-Output "P2b COMPLETE"
