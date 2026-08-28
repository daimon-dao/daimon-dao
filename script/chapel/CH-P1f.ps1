# P1.7 -- Initial liquidity: the BNB leg computed on the DMN the pair
#         ACTUALLY receives (#17/B0). P1.9 -- automation armed + test swap.
. $PSScriptRoot\lib.ps1
Load-Keystores
$st = S
$router = "0xD99D1c33F9fC3444f8101754aBC46c52416550D1"
Log-Scenario "P1.7" "Initial liquidity: BNB leg on the NET, opening price verified"

$sal = CQRaw $st.token "swapAndLiquifyEnabled()(bool)"
Log-Step "P1.7.1" "Automation state before liquidity (#27)" "armed by initialize, and inert by construction: no inventory exists, pokes are the only trigger (#1), and the fail-open fix is in the audited bytecode (BuyBackSkipped paths)" "swapAndLiquifyEnabled=$sal, fee inventory=$(FmtB (CQ $st.token 'balanceOf(address)(uint256)' @($st.token)))" "-" $(if ("$sal" -eq "true") { "PASS" } else { "DEVIATION" })

$hOldApp = Send "deployer" $st.old "approve(address,uint256)" @($st.migration, "4500000000000000000000000000")
$hC = Send "deployer" $st.migration "claim(uint256)" @("4500000000000000000000000000")
$depDmn = CQ $st.token "balanceOf(address)(uint256)" @($script:AddrBook.deployer)
Log-Step "P1.7.2" "Deployer migrates 4.5B for the pool and later steps" "exact 1:1 (both legs fee-exempt for this path)" "DMN=$(FmtB $depDmn), gas=$($hC.gasUsed)" $hC.hash $(if ("$depDmn" -eq "4500000000000000000000000000") { "PASS" } else { "DEVIATION" })

# The #17 arithmetic: target NET = 0.1B = 1e26. The pair is not fee-exempt,
# so it receives 95% of what is sent: gross G = 1e26 / 0.95.
$gross = "105263157894736842105263157"
$hA = Send "deployer" $st.token "approve(address,uint256)" @($router, $gross)
$hL = Send "deployer" $router "addLiquidityETH(address,uint256,uint256,uint256,address,uint256)" @($st.token, $gross, "0", "0", $script:AddrBook.deployer, "99999999999") -value "100000000000000000"
$r0 = CQRaw $st.pair "getReserves()(uint112,uint112,uint32)"
$t0 = CQRaw $st.pair "token0()(address)"
# order reserves as (DMN, BNB)
$res = (cast call $st.pair "getReserves()(uint112,uint112,uint32)" --rpc-url $script:RPC | Out-String) -split "`n"
$lines = @(); foreach ($l in $res) { $t = $l.Trim(); if ($t -ne "") { $lines += ($t -split "\s+")[0] } }
if ("$t0".ToLower() -eq "$($st.token)".ToLower()) { $dmnRes = [System.Numerics.BigInteger]::Parse($lines[0]); $bnbRes = [System.Numerics.BigInteger]::Parse($lines[1]) }
else { $dmnRes = [System.Numerics.BigInteger]::Parse($lines[1]); $bnbRes = [System.Numerics.BigInteger]::Parse($lines[0]) }
$netTarget = [System.Numerics.BigInteger]::Parse("100000000000000000000000000")
$delta = [System.Numerics.BigInteger]::Abs($dmnRes - $netTarget)
Log-Step "P1.7.3" "addLiquidityETH: gross $gross wei DMN + 0.1 tBNB" "the pair holds ~1e26 DMN NET (gross minus the 5% fee) and 1e17 BNB" "reserves DMN=$dmnRes (delta from target: $delta wei), BNB=$bnbRes; gas=$($hL.gasUsed)" $hL.hash $(if ($delta -le 10 -and "$bnbRes" -eq "100000000000000000") { "PASS" } else { "DEVIATION" })

# Opening price: 1B DMN per 1 tBNB intended -> DMN/BNB ratio == 1e9.
$ratio = [System.Numerics.BigInteger]::Divide($dmnRes, $bnbRes)
Log-Step "P1.7.4" "Opening price from ACTUAL reserves" "1e9 DMN per BNB - the intended price, computed on the net (#17)" "ratio=$ratio DMN/BNB" "-" $(if ("$ratio" -eq "1000000000") { "PASS" } else { "DEVIATION" })

Log-Scenario "P1.9" "Reserves non-zero, automation armed: a small test swap pays the fee"
$invBefore = CQ $st.token "balanceOf(address)(uint256)" @($st.token)
$sellAmt = "50000000000000000000000000"   # 0.05B
$hAp = Send "holder1" $st.token "approve(address,uint256)" @($router, $sellAmt)
$wbnb = CQRaw $router "WETH()(address)"
$bnbBefore = Bal $script:AddrBook.holder1
$hS = Send "holder1" $router "swapExactTokensForETHSupportingFeeOnTransferTokens(uint256,uint256,address[],address,uint256)" @($sellAmt, "0", "[$($st.token),$wbnb]", $script:AddrBook.holder1, "99999999999")
$invAfter = CQ $st.token "balanceOf(address)(uint256)" @($st.token)
$bnbAfter = Bal $script:AddrBook.holder1
$feeTaken = $invAfter - $invBefore
$expFee = [System.Numerics.BigInteger]::Parse($sellAmt) / 20
Log-Step "P1.9.1" "holder1 sells 0.05B through the real router" "the 5% fee lands in the token contract as inventory; the seller receives BNB" "fee inventory +$(FmtB $feeTaken) (expected ~$(FmtB $expFee)), holder1 BNB +$(FmtT ($bnbAfter - $bnbBefore + ($hS.gasUsed * 100000000))) (net of est. gas); gas=$($hS.gasUsed)" $hS.hash $(if ($feeTaken -gt 0) { "PASS" } else { "DEVIATION" })
Log-Step "P1.9.2" "Did the sell trigger any conversion? (#1)" "no: router-initiated transfers skip the automation - inventory only grew" "inventory $(FmtB $invBefore) -> $(FmtB $invAfter)" "-" $(if ($invAfter -gt $invBefore) { "PASS" } else { "DEVIATION" })
Write-Output "P1f COMPLETE"
