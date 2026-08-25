# B2 - A router sell above the swap threshold must NOT fire the automation (#1).
. .\script\campaign\lib.ps1
Log-Scenario "B2" "Router sell above minimumTokensBeforeSwap: the sell passes, the automation stays put (Zenith #1)"
$st = Bootstrap-Campaign
Claim-Dmn "team1" (BW "30.00") | Out-Null
Setup-Pool "team1" "4.00" | Out-Null
Send "team1" $st.token "transfer(address,uint256)" @($script:Addr.alice, "$(BW '5.00')") | Out-Null
Send "team1" $st.token "transfer(address,uint256)" @($script:Addr.bob, "$(BW '5.00')") | Out-Null

$minSwap = CQ $st.token "minimumTokensBeforeSwap()(uint256)"
$invBefore = Fee-Inventory
$ethBefore = Bal $st.token
$stakingBefore = Bal $st.staking
Log-Step "B2.1" "Fee inventory before the sell" "at or above minimumTokensBeforeSwap, so the automation is armed" "inventory $(FmtB $invBefore) vs threshold $(FmtB $minSwap)" $(if ($invBefore -ge $minSwap) { "PASS" } else { "DEVIATION" })

$aliceEthBefore = Bal $script:Addr.alice
Sell-Dmn "alice" (BW "1.00") | Out-Null
$invAfter = Fee-Inventory
$ethAfter = Bal $st.token
$aliceEthAfter = Bal $script:Addr.alice
Log-Step "B2.2" "alice sells 1.00 B through the real PancakeSwap router" "the sell goes through: she receives BNB" "alice BNB +$(FmtT ($aliceEthAfter - $aliceEthBefore))" $(if ($aliceEthAfter -gt $aliceEthBefore) { "PASS" } else { "DEVIATION" })
Log-Step "B2.3" "Did the fee swap fire during the sell?" "NO - a router-initiated transfer skips the automation, so no DMN was converted" "inventory $(FmtB $invBefore) -> $(FmtB $invAfter) (only grew, by the sell's own fee)" $(if ($invAfter -ge $invBefore) { "PASS" } else { "DEVIATION" })
Log-Step "B2.4" "Did any BNB reach the token contract?" "none: no conversion happened at all" "contract BNB $(FmtT $ethBefore) -> $(FmtT $ethAfter)" $(if ($ethAfter -eq $ethBefore) { "PASS" } else { "DEVIATION" })
Log-Step "B2.5" "Did the staking pool receive anything?" "no: with nothing converted there is nothing to distribute" "staking BNB $(FmtT $stakingBefore) -> $(FmtT (Bal $st.staking))" $(if ((Bal $st.staking) -eq $stakingBefore) { "PASS" } else { "DEVIATION" })
Log-Note "This is the #1 fix behaving exactly as designed, and it is the behaviour the whitepaper now describes: ordinary sales through the router no longer convert fees, because doing so inside the router's own reserve window is what let a liquidity deposit be mispriced. The inventory simply accumulates until somebody pokes."
Stop-Anvil
Write-Output "B2 COMPLETE"
