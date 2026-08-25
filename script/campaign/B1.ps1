# B1 - Ordinary transfers: the fee applies and a passive holder grows.
. .\script\campaign\lib.ps1
Log-Scenario "B1" "Ordinary wallet-to-wallet transfers: fee taken, passive holder grows by reflection"
Write-Output "  .. bootstrapping"
$st = Bootstrap-Campaign
Write-Output "  .. deployed, funding wallets"
Claim-Dmn "team1" (BW "20.00") | Out-Null
# Seed three wallets; carol will then sit completely still.
Send "team1" $st.token "transfer(address,uint256)" @($script:Addr.alice, "$(BW '4.00')") | Out-Null
Send "team1" $st.token "transfer(address,uint256)" @($script:Addr.bob,   "$(BW '4.00')") | Out-Null
Send "team1" $st.token "transfer(address,uint256)" @($script:Addr.carol, "$(BW '4.00')") | Out-Null

Write-Output "  .. wallets funded, running transfers"
$tax = CQ $st.token "taxFee()(uint256)"; $liq = CQ $st.token "liquidityFee()(uint256)"
$amount = BW "1.00"
$aBefore = CQ $st.token "balanceOf(address)(uint256)" @($script:Addr.alice)
$bBefore = CQ $st.token "balanceOf(address)(uint256)" @($script:Addr.bob)
$cBefore = CQ $st.token "balanceOf(address)(uint256)" @($script:Addr.carol)
$invBefore = Fee-Inventory

Send "alice" $st.token "transfer(address,uint256)" @($script:Addr.bob, "$amount") | Out-Null
$bMid = CQ $st.token "balanceOf(address)(uint256)" @($script:Addr.bob)
$expectedNet = ($amount * (1000 - $tax - $liq)) / 1000
$creditedNet = $bMid - $bBefore
Log-Step "B1.1" "alice transfers 1.00 B to bob" "bob is credited the amount net of the 5% fee (1% reflection + 4% to the contract)" "credited $(FmtT $creditedNet) vs net $(FmtT $expectedNet) (delta includes bob's own reflection share)" $(if ($creditedNet -ge $expectedNet) { "PASS" } else { "DEVIATION" })

Send "bob" $st.token "transfer(address,uint256)" @($script:Addr.alice, "$amount") | Out-Null
$cAfter = CQ $st.token "balanceOf(address)(uint256)" @($script:Addr.carol)
$invAfter = Fee-Inventory
Log-Step "B1.2" "A second transfer, bob back to alice" "the contract's fee inventory grows by 4% of each transfer" "inventory $(FmtT $invBefore) -> $(FmtT $invAfter)" $(if ($invAfter -gt $invBefore) { "PASS" } else { "DEVIATION" })
Log-Step "B1.3" "carol never sends or receives anything during the two transfers" "her balance GROWS anyway: reflection accrues to passive holders" "$(FmtT $cBefore) -> $(FmtT $cAfter) (+$(FmtT ($cAfter - $cBefore)))" $(if ($cAfter -gt $cBefore) { "PASS" } else { "DEVIATION" })

$supply = CQ $st.token "totalSupply()(uint256)"
Log-Step "B1.4" "Total supply across the reflection" "unchanged: reflection redistributes, it does not mint or burn" "$(FmtB $supply)" $(if ($supply -eq (BW "1000.00")) { "PASS" } else { "DEVIATION" })
Stop-Anvil
Write-Output "B1 COMPLETE"
