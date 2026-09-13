# H1 steps 5a-8 -- oldowner claims EXACTLY the liquidity leg (gross of the
# 4% the pair takes), adds liquidity at the DMX price parameter with the
# tBNB actually available, moves ALL LP to the Timelock; one pool; reserves
# non-zero. Sizing values are read from the chain, not typed.
. $PSScriptRoot\lib.ps1
Load-Keystores
$st = S
if (-not $st.timelock) { throw "run H1c-phase2.ps1 first" }
if ($st.lpTx) { throw "liquidity already added (lp tx $($st.lpTx))" }
Log-Scenario "H1 (5-8)" "Step 5a: the owner's exact claim; 5b: liquidity at the DMX price on the NET; 6: LP to the Timelock; 7: one pool; 8: reserves non-zero"

# ---- 5a preconditions on the mock: the two properties the step relies on --
$owner = CQRaw $st.old "owner()(address)"
$ex = CQRaw $st.old "excludedFromFee(address)(bool)" @($script:AddrBook.oldowner)
$cap = CQ $st.old "maxTxAmount()(uint256)"
$tlEx = CQRaw $st.old "excludedFromFee(address)(bool)" @($st.timelock)
Log-Step "H1.10" "Why the owner can claim before 11b: its status on the predecessor, read live" "owner() == oldowner (cap-exempt as sender/recipient), excludedFromFee(oldowner) == true (no 11% on the claimant -> treasury leg); the treasury itself NOT exempt (11b not done), cap still 1.5B (11a not done)" "owner=$owner, excludedFromFee(oldowner)=$ex, excludedFromFee(timelock)=$tlEx, maxTxAmount=$(FmtB $cap)" "-" $(if ("$owner".ToLower() -eq "$($script:AddrBook.oldowner)".ToLower() -and "$ex" -eq "true" -and "$tlEx" -eq "false" -and $cap -eq (BW "1.50")) { "PASS" } else { "DEVIATION" })

# ---- Sizing: the tBNB actually available, the price parameter -------------
$avail = Bal $script:AddrBook.oldowner
$gasReserve = [System.Numerics.BigInteger]::Parse("30000000000000000")      # 0.03 tBNB kept for the day's gas
$target = [System.Numerics.BigInteger]::Parse("3000000000000000000")        # 3 tBNB
$bnbWei = $avail - $gasReserve
if ($bnbWei -gt $target) { $bnbWei = $target }
$mille = [System.Numerics.BigInteger]::Parse("1000000000000000")
$bnbWei = [System.Numerics.BigInteger]::Divide($bnbWei, $mille) * $mille       # whole 0.001 tBNB
if ($bnbWei -lt [System.Numerics.BigInteger]::Parse("50000000000000000")) { throw "STOP: oldowner holds $(FmtT $avail) tBNB -- less than 0.05 usable for liquidity" }
$tax = CQ $st.token "taxFee()(uint256)"; $liq = CQ $st.token "liquidityFee()(uint256)"
$netTarget = [System.Numerics.BigInteger]::Divide($bnbWei * $script:E18, $script:PRICE_WEI_PER_TOKEN)
$gross = CeilDiv ($netTarget * 1000) (1000 - $tax - $liq)
$net = NetOfGross $gross $tax $liq
$maxTx = CQ $st.token "maxTxAmount()(uint256)"
$sizingOk = ($net -ge $netTarget -and ($net - $netTarget) -lt 1000 -and $gross -le $maxTx -and $tax -eq 10 -and $liq -eq 30)
Log-Step "H1.11" "Sizing from live values: tBNB available to oldowner vs the 3 tBNB target; DMN leg derived from the price parameter $($script:PRICE_LABEL)" "BNB = min(3, available - 0.03) rounded to 0.001; net DMN = BNB * 1e18 / $($script:PRICE_WEI_PER_TOKEN); gross = ceil(net * 1000 / (1000 - taxFee - liquidityFee)) so that the pair receives >= the net target by < 1000 wei; gross <= token maxTxAmount (a single addLiquidityETH)" "available=$(FmtT $avail) tBNB, used=$(FmtT $bnbWei) tBNB$(if ($bnbWei -lt $target) { ' (LESS than the 3 tBNB target: the faucet allowed less)' } else { ' (the full target)' }); fees=$tax/$liq per mille; net target=$(FmtB $netTarget) ($netTarget wei); gross=$(FmtB $gross) ($gross wei); net of gross=$net wei (over target by $($net - $netTarget) wei); token maxTxAmount=$(FmtB $maxTx)" "-" $(if ($sizingOk) { "PASS" } else { "DEVIATION" })
if ($gross -gt $maxTx) { Log-Note "STOP: at this price the DMN leg ($(FmtB $gross) gross) exceeds the token's maxTxAmount ($(FmtB $maxTx)): the provider is not exempt, a single addLiquidityETH would revert with TransferAmountExceedsMaxTx, and a second router add re-prices on the gross (#17). Not worked around; decision for the operator (the finding stands for mainnet at 3 BNB: 3 / 4.69e-10 = 6.40 B net, 6.66 B gross, cap 5 B)."; throw "STOP: gross exceeds maxTxAmount" }
if (-not $sizingOk) { throw "STOP: sizing assert failed" }

# ---- 5a: the claim, exactly gross ----------------------------------------
$tOld0 = CQ $st.old "balanceOf(address)(uint256)" @($st.timelock)
$oDmn0 = CQ $st.token "balanceOf(address)(uint256)" @($script:AddrBook.oldowner)
$hC = Claim-Dmn "oldowner" $gross
$tOld1 = CQ $st.old "balanceOf(address)(uint256)" @($st.timelock)
$oDmn1 = CQ $st.token "balanceOf(address)(uint256)" @($script:AddrBook.oldowner)
$migr = CQ $st.migration "migratedAmount(address)(uint256)" @($script:AddrBook.oldowner)
Log-Step "H1.12" "Step 5a: oldowner claims EXACTLY the gross liquidity leg from the mock, before 11b" "exact 1:1 on both legs: treasury (the Timelock) old +gross, oldowner DMN +gross, migratedAmount == gross -- possible only because the owner is fee-exempt and cap-exempt on the predecessor (H1.10)" "treasury old +$($tOld1 - $tOld0) wei ($(FmtB ($tOld1 - $tOld0))), oldowner DMN +$($oDmn1 - $oDmn0) wei ($(FmtB ($oDmn1 - $oDmn0))), migratedAmount=$migr; gas=$($hC.gasUsed)" $hC.hash $(if (($tOld1 - $tOld0) -eq $gross -and ($oDmn1 - $oDmn0) -eq $gross -and $migr -eq $gross) { "PASS" } else { "DEVIATION" })

# ---- 5b: the liquidity ---------------------------------------------------
$hA = Send "oldowner" $st.token "approve(address,uint256)" @($script:ROUTER, "$gross")
$bnb0 = Bal $script:AddrBook.oldowner
$hL = Send "oldowner" $script:ROUTER "addLiquidityETH(address,uint256,uint256,uint256,address,uint256)" @($st.token, "$gross", "0", "0", $script:AddrBook.oldowner, "99999999999") -value "$bnbWei"
$res = Pair-Reserves
$oDmn2 = CQ $st.token "balanceOf(address)(uint256)" @($script:AddrBook.oldowner)
$price = Price-WeiPerToken $res[0] $res[1]
$priceDiff = $script:PRICE_WEI_PER_TOKEN - $price
$lpMinted = CQ $st.pair "balanceOf(address)(uint256)" @($script:AddrBook.oldowner)
$priceOk = ($priceDiff -ge 0 -and ($priceDiff * 1000000) -le $script:PRICE_WEI_PER_TOKEN)
Log-Step "H1.13" "Step 5b: addLiquidityETH(gross DMN, $(FmtT $bnbWei) tBNB) by oldowner -- BNB leg on the NET (#17)" "reserve DMN == net of gross (exact), reserve BNB == the tBNB sent (no refund); oldowner DMN back to 0 (all of the claim went in); resulting price == the parameter within 1 ppm" "BNB sent=$bnbWei wei ($(FmtT $bnbWei)); DMN gross=$gross wei ($(FmtB $gross)); DMN received by the pair=$($res[0]) wei ($(FmtB $res[0])), expected net=$net; reserve BNB=$($res[1]); price=$price wei/token vs parameter $($script:PRICE_WEI_PER_TOKEN) (diff $priceDiff); oldowner DMN after=$oDmn2; LP minted=$lpMinted; gas=$($hL.gasUsed)" "$($hA.hash) / $($hL.hash)" $(if ($res[0] -eq $net -and $res[1] -eq $bnbWei -and $oDmn2 -eq 0 -and $priceOk) { "PASS" } else { "DEVIATION" })

# ---- 6: ALL LP tokens oldowner -> Timelock --------------------------------
$lp = CQ $st.pair "balanceOf(address)(uint256)" @($script:AddrBook.oldowner)
$hT = Send "oldowner" $st.pair "transfer(address,uint256)" @($st.timelock, "$lp")
$lpOwner = CQ $st.pair "balanceOf(address)(uint256)" @($script:AddrBook.oldowner)
$lpDep = CQ $st.pair "balanceOf(address)(uint256)" @($script:AddrBook.deployer)
$lpTl = CQ $st.pair "balanceOf(address)(uint256)" @($st.timelock)
$lpSupply = CQ $st.pair "totalSupply()(uint256)"
$minLiq = CQ $st.pair "MINIMUM_LIQUIDITY()(uint256)"
Log-Step "H1.14" "Step 6: ALL the LP tokens, oldowner -> Timelock, one published transaction (H0.4)" "from mined state: pair.balanceOf(oldowner) == 0, pair.balanceOf(deployer) == 0, pair.balanceOf(timelock) == totalSupply - MINIMUM_LIQUIDITY (1000 wei)" "moved=$lp wei LP; oldowner LP=$lpOwner, deployer LP=$lpDep, timelock LP=$lpTl, totalSupply=$lpSupply, MINIMUM_LIQUIDITY=$minLiq; gas=$($hT.gasUsed)" $hT.hash $(if ($lpOwner -eq 0 -and $lpDep -eq 0 -and $lpTl -eq ($lpSupply - $minLiq) -and $minLiq -eq 1000 -and $lp -gt 0) { "PASS" } else { "DEVIATION" })

# ---- 7: one pool only -----------------------------------------------------
$factory = CQRaw $script:ROUTER "factory()(address)"
$wbnb = CQRaw $script:ROUTER "WETH()(address)"
$factPair = CQRaw $factory "getPair(address,address)(address)" @($st.token, $wbnb)
Log-Step "H1.15" "Step 7: the pair the token stores vs the pair the factory created" "identical -- one pool" "token.uniswapV2Pair=$($st.pair), factory.getPair=$factPair" "-" $(if ("$factPair".ToLower() -eq "$($st.pair)".ToLower()) { "PASS" } else { "DEVIATION" })

# ---- 8: reserves non-zero -> automation active ---------------------------
$inv = Fee-Inventory
$expInv = [System.Numerics.BigInteger]::Divide($gross * $liq, 1000)
Log-Step "H1.16" "Step 8: both reserves non-zero" "automation can now run on a real pool; the liquidity transfer itself was taxed: inventory == gross * liquidityFee / 1000" "DMN=$(FmtB $res[0]), BNB=$(FmtT $res[1]); inventory=$inv wei ($(FmtB $inv)), expected $expInv" "-" $(if ($res[0] -gt 0 -and $res[1] -gt 0 -and $inv -eq $expInv) { "PASS" } else { "DEVIATION" })

$st | Add-Member -NotePropertyName liqBnbWei -NotePropertyValue "$bnbWei" -Force
$st | Add-Member -NotePropertyName liqGross -NotePropertyValue "$gross" -Force
$st | Add-Member -NotePropertyName liqNet -NotePropertyValue "$($res[0])" -Force
$st | Add-Member -NotePropertyName liqPriceWeiPerToken -NotePropertyValue "$price" -Force
$st | Add-Member -NotePropertyName lpTx -NotePropertyValue $hT.hash -Force
Save-State $st
Write-Output "H1e COMPLETE bnb=$(FmtT $bnbWei) gross=$(FmtB $gross) price=$price wei/token"
