# B5 - What if nobody ever pokes: fees accumulate, nothing breaks.
. .\script\campaign\lib.ps1
Log-Scenario "B5" "Nobody ever pokes: fees accumulate, nothing is lost, only cadence degrades"
$st = Bootstrap-Campaign
Claim-Dmn "team1" (BW "40.00") | Out-Null
Setup-Pool "team1" "4.00" | Out-Null
Send "team1" $st.token "transfer(address,uint256)" @($script:Addr.alice, "$(BW '5.00')") | Out-Null
Send "team1" $st.token "transfer(address,uint256)" @($script:Addr.bob, "$(BW '5.00')") | Out-Null
$minSwap = CQ $st.token "minimumTokensBeforeSwap()(uint256)"
$inv0 = Fee-Inventory
$eth0 = Bal $st.token

# Two months of ordinary trading, nobody ever touching the pair directly.
foreach ($i in 1..4) {
  Write-Output "  .. round $i transfer"
  Send "alice" $st.token "transfer(address,uint256)" @($script:Addr.bob, "$(BW '1.00')") | Out-Null
  Write-Output "  .. round $i sell"
  Sell-Dmn "bob" (BW "0.50") | Out-Null
  Write-Output "  .. round $i warp"
  Warp (15 * 86400)
}
Write-Output "  .. loop done"
$inv1 = Fee-Inventory
$eth1 = Bal $st.token
$supply = CQ $st.token "totalSupply()(uint256)"
Log-Step "B5.1" "Four rounds of transfers and router sells across 60 days, never a poke" "the fee inventory only grows - nothing converts on its own" "$(FmtB $inv0) -> $(FmtB $inv1), i.e. $([Math]::Floor([double]($inv1 / $minSwap))) chunks waiting" $(if ($inv1 -gt $inv0) { "PASS" } else { "DEVIATION" })
Log-Step "B5.2" "Buyback BNB during those 60 days" "none accrues, because nothing was ever converted" "contract BNB $(FmtT $eth0) -> $(FmtT $eth1)" $(if ($eth1 -eq $eth0) { "PASS" } else { "DEVIATION" })
Log-Step "B5.3" "Does anything break?" "no: transfers and sells keep working throughout, supply intact" "totalSupply=$(FmtB $supply), every transfer and sell in the loop succeeded" $(if ($supply -eq (BW "1000.00")) { "PASS" } else { "DEVIATION" })

Send "team1" $st.token "transfer(address,uint256)" @($script:Addr.stranger, "$(BW '1.00')") | Out-Null
$invPre = Fee-Inventory
Poke "stranger" | Out-Null
$invPost = Fee-Inventory
Log-Step "B5.4" "The first poke after 60 days of silence" "the accumulated inventory is intact and converts one chunk at a time" "consumed $(FmtB ($invPre - $invPost)), still waiting $(FmtB $invPost)" $(if (($invPre - $invPost) -eq $minSwap) { "PASS" } else { "DEVIATION" })
$mk = CQ $st.token "balanceOf(address)(uint256)" @($script:MARKETING)
Log-Step "B5.5" "Marketing wallet across the whole idle period" "zero, as everywhere else" "DMN=$mk" $(if ($mk -eq 0) { "PASS" } else { "DEVIATION" })
Log-Note "Nothing is lost by not poking: the fees sit in the contract as DMN and convert whenever somebody eventually sends a wei to the pair. What degrades is only the cadence of staking rewards and buyback pressure - the liveness dependency THREAT_MODEL par.8 describes, and it is a dependency on ANY address in the world bothering, not on a keeper."
Stop-Anvil
Write-Output "B5 COMPLETE"
