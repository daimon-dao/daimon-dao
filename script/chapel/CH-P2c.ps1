# P2.3 -- The poke model on a public chain: sell does not fire, 1 wei does.
. $PSScriptRoot\lib.ps1
Load-Keystores
$st = S
$router = "0xD99D1c33F9fC3444f8101754aBC46c52416550D1"
Log-Scenario "P2.3" "Poke model, real conditions: gas measured on both sides"

$minSwap = CQ $st.token "minimumTokensBeforeSwap()(uint256)"
$h1 = Send "holder1" $st.token "transfer(address,uint256)" @($script:AddrBook.holder2, "3000000000000000000000000000")
$h2 = Send "holder1" $st.token "transfer(address,uint256)" @($script:AddrBook.holder3, "2000000000000000000000000000")
$inv0 = CQ $st.token "balanceOf(address)(uint256)" @($st.token)
Log-Step "P2.3.1" "Ordinary volume: holder1 sends 3B + 2B (taxed)" "inventory crosses minimumTokensBeforeSwap ($(FmtB $minSwap))" "inventory=$(FmtB $inv0), armed=$($inv0 -ge $minSwap)" "$($h1.hash) / $($h2.hash)" $(if ($inv0 -ge $minSwap) { "PASS" } else { "DEVIATION" })

$wbnb = CQRaw $router "WETH()(address)"
$hAp = Send "staker2" $st.token "approve(address,uint256)" @($router, "500000000000000000000000000")
$hS = Send "staker2" $router "swapExactTokensForETHSupportingFeeOnTransferTokens(uint256,uint256,address[],address,uint256)" @("500000000000000000000000000", "0", "[$($st.token),$wbnb]", $script:AddrBook.staker2, "99999999999")
$inv1 = CQ $st.token "balanceOf(address)(uint256)" @($st.token)
$ethC0 = Bal $st.token
Log-Step "P2.3.2" "A REAL router sell (0.5B) with the inventory armed" "no conversion: inventory only grows by the sell fee (#1)" "inventory $(FmtB $inv0) -> $(FmtB $inv1), contract BNB=$(FmtT $ethC0); sell gas=$($hS.gasUsed)" $hS.hash $(if ($inv1 -gt $inv0) { "PASS" } else { "DEVIATION" })

$hD = Send "deployer" $st.token "transfer(address,uint256)" @($script:AddrBook.stranger, "10000000000000000000000000")
$stakingBnb0 = Bal $st.staking
$hP = Send "stranger" $st.token "transfer(address,uint256)" @($st.pair, "1")
$inv2 = CQ $st.token "balanceOf(address)(uint256)" @($st.token)
$ethC1 = Bal $st.token
$stakingBnb1 = Bal $st.staking
Log-Step "P2.3.3" "The stranger pokes: 1 wei of DMN to the pair" "conversion fires, ~one chunk consumed; staking receives BNB; poke gas vs sell gas" "inventory $(FmtB $inv1) -> $(FmtB $inv2), contract BNB $(FmtT $ethC0) -> $(FmtT $ethC1), staking BNB $(FmtT $stakingBnb0) -> $(FmtT $stakingBnb1); POKE gas=$($hP.gasUsed) vs SELL gas=$($hS.gasUsed)" $hP.hash $(if ($inv2 -lt $inv1 -and $stakingBnb1 -gt $stakingBnb0) { "PASS" } else { "DEVIATION" })
$mkDmn = CQ $st.token "balanceOf(address)(uint256)" @($script:MARKETING)
$mkNat = Bal $script:MARKETING
Log-Step "P2.3.4" "Marketing wallet during a REAL conversion on a public chain" "untouched: share=1000 means the transfer branch never runs" "DMN=$mkDmn, native=$mkNat" "-" $(if ($mkDmn -eq 0 -and $mkNat -eq 0) { "PASS" } else { "DEVIATION" })
Write-Output "P2c COMPLETE"
