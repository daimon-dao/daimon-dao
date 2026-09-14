# H1 steps 9-10 -- a test sell pays 4%; the inventory is armed by ordinary
# transfers; the FIRST poke: with share 1000 NO BNB reaches the Timelock,
# and the ratio chunk-sold / reserves and the price move are RECORDED --
# the number that says whether 3 BNB is too thin on mainnet.
. $PSScriptRoot\lib.ps1
Load-Keystores
$st = S
if (-not $st.lpTx) { throw "run H1e-liquidity.ps1 first" }
if ($st.pokeTx) { throw "first poke already done ($($st.pokeTx))" }
Log-Scenario "H1 (9-10)" "Step 9: the test sell pays 4%; step 10: the first poke -- zero BNB to the Timelock, the chunk/reserves ratio and the price move recorded"

$tax = CQ $st.token "taxFee()(uint256)"; $liq = CQ $st.token "liquidityFee()(uint256)"; $mkt = CQ $st.token "marketingFee()(uint256)"
$minSwap = CQ $st.token "minimumTokensBeforeSwap()(uint256)"

# ---- The float: before 11b only the owner can obtain DMN ------------------
$float = BW "7.00"
$tOld0 = CQ $st.old "balanceOf(address)(uint256)" @($st.timelock)
$oDmn0 = CQ $st.token "balanceOf(address)(uint256)" @($script:AddrBook.oldowner)
$hF = Claim-Dmn "oldowner" $float
$tOld1 = CQ $st.old "balanceOf(address)(uint256)" @($st.timelock)
$oDmn1 = CQ $st.token "balanceOf(address)(uint256)" @($script:AddrBook.oldowner)
Log-Step "H1.17" "The campaign float: oldowner's SECOND claim, 7.00 B, separate from the liquidity claim of 5a" "exact 1:1 again; harness necessity, recorded as such: steps 9 and 10 need DMN in non-owner hands and before 11b the owner is the only address that can claim -- on mainnet the volume that arms the first conversion is organic" "treasury old +$(FmtB ($tOld1 - $tOld0)), oldowner DMN +$(FmtB ($oDmn1 - $oDmn0)) ($($oDmn1 - $oDmn0) wei)" $hF.hash $(if (($tOld1 - $tOld0) -eq $float -and ($oDmn1 - $oDmn0) -eq $float) { "NOTE" } else { "DEVIATION" })

$inv0 = Fee-Inventory
$amt = BW "0.50"
$hS0 = Send "oldowner" $st.token "transfer(address,uint256)" @($script:AddrBook.stranger, "$amt")
$sDmn = CQ $st.token "balanceOf(address)(uint256)" @($script:AddrBook.stranger)
$inv1 = Fee-Inventory
$exp96 = [System.Numerics.BigInteger]::Divide($amt * 96, 100)
$expInv = [System.Numerics.BigInteger]::Divide($amt * $liq, 1000)
## Inventory expectation, corrected BEFORE this runner ran (H1.16 note): the
## contract's fee inventory is a reflection-participating balance, so every
## taxed transfer credits it the 3% liquidityFee PLUS its pro-rata share of
## the 1% reflection (about 1.7e-5 of the fee at today's balances). The
## assert is therefore "3% exactly floored, plus at most 0.01% of it", the
## form Day 0 used (>=), tightened with an upper bound.
Log-Step "H1.18" "oldowner sends 0.50 B DMN to the stranger (an ordinary, taxed transfer)" "the stranger receives 96% (+ its reflection share, < 0.01%); inventory += 3% (liquidityFee) plus the contract's own reflection share (< 0.01% of it)" "stranger DMN=$sDmn wei (96% = $exp96), inventory +$($inv1 - $inv0) wei (3% = $expInv, extra $($inv1 - $inv0 - $expInv))" $hS0.hash $(if ($sDmn -ge $exp96 -and (($sDmn - $exp96) * 10000) -le $exp96 -and ($inv1 - $inv0) -ge $expInv -and (($inv1 - $inv0 - $expInv) * 10000) -le $expInv) { "PASS" } else { "DEVIATION" })

# ---- Step 9: the test sell through the real router ------------------------
$sellAmt = BW "0.05"
$resB = Pair-Reserves
$wbnb = CQRaw $script:ROUTER "WETH()(address)"
$hA = Send "stranger" $st.token "approve(address,uint256)" @($script:ROUTER, "$sellAmt")
$sBnb0 = Bal $script:AddrBook.stranger
$hS = Send "stranger" $script:ROUTER "swapExactTokensForETHSupportingFeeOnTransferTokens(uint256,uint256,address[],address,uint256)" @("$sellAmt", "0", "[$($st.token),$wbnb]", $script:AddrBook.stranger, "99999999999")
$sBnb1 = Bal $script:AddrBook.stranger
$resA = Pair-Reserves
$inv2 = Fee-Inventory
$pairGot = $resA[0] - $resB[0]
$exp96s = [System.Numerics.BigInteger]::Divide($sellAmt * 96, 100)
$exp95s = [System.Numerics.BigInteger]::Divide($sellAmt * 95, 100)
$expInvS = [System.Numerics.BigInteger]::Divide($sellAmt * $liq, 1000)
Log-Step "H1.19" "Step 9: the stranger sells 0.05 B through the real router" "the pair (reward-excluded) receives EXACTLY 96% of the amount sent (fee 4%), NOT 95%; inventory += 3% plus the contract's reflection share (< 0.01% of it); the seller receives BNB" "pair DMN reserve +$pairGot wei = $(FmtB $pairGot) (96% would be $exp96s, 95% would be $exp95s); inventory +$($inv2 - $inv1) wei (3% = $expInvS, extra $($inv2 - $inv1 - $expInvS)); stranger BNB delta (gas included)=$(FmtT ($sBnb1 - $sBnb0)), BNB out of the pool=$(FmtT ($resB[1] - $resA[1])); sell gas=$($hS.gasUsed)" "$($hA.hash) / $($hS.hash)" $(if ($pairGot -eq $exp96s -and ($inv2 - $inv1) -ge $expInvS -and (($inv2 - $inv1 - $expInvS) * 10000) -le $expInvS -and ($resB[1] - $resA[1]) -gt 0) { "PASS" } else { "DEVIATION" })
Log-Step "H1.20" "Did the router sell trigger any conversion? (#1)" "no: router-initiated transfers skip the automation, inventory only grew, contract BNB zero, Timelock BNB zero" "inventory $(FmtB $inv1) -> $(FmtB $inv2), contract BNB=$(FmtT (Bal $st.token)), timelock BNB=$(FmtT (Bal $st.timelock))" "-" $(if ($inv2 -gt $inv1 -and (Bal $st.token) -eq 0 -and (Bal $st.timelock) -eq 0) { "PASS" } else { "DEVIATION" })

# ---- Arm the inventory above the threshold with ordinary transfers --------
$h1 = Send "oldowner" $st.token "transfer(address,uint256)" @($script:AddrBook.holder, "$(BW '3.50')")
$h2 = Send "oldowner" $st.token "transfer(address,uint256)" @($script:AddrBook.holder, "$(BW '3.00')")
$inv3 = Fee-Inventory
$resP = Pair-Reserves
$priceP = Price-WeiPerToken $resP[0] $resP[1]
$tl0 = Bal $st.timelock; $stk0 = Bal $st.staking; $ct0 = Bal $st.token
Log-Step "H1.21" "Inventory armed by ordinary transfers (3.50 B + 3.00 B oldowner -> holder, each under the token's maxTx)" "inventory >= minimumTokensBeforeSwap; Timelock, staking and contract BNB all zero before the poke; reserves and price recorded before the poke" "inventory=$inv3 wei ($(FmtB $inv3)) vs threshold $minSwap ($(FmtB $minSwap)); timelock BNB=$(FmtT $tl0), staking BNB=$(FmtT $stk0), contract BNB=$(FmtT $ct0); reserves before poke DMN=$($resP[0]) BNB=$($resP[1]), price=$priceP wei/token" "$($h1.hash) / $($h2.hash)" $(if ($inv3 -ge $minSwap -and $tl0 -eq 0 -and $stk0 -eq 0 -and $ct0 -eq 0) { "PASS" } else { "DEVIATION" })

# ---- Step 10: the first poke ----------------------------------------------
$hP = Send "stranger" $st.token "transfer(address,uint256)" @($st.pair, "1")
$inv4 = Fee-Inventory
$resQ = Pair-Reserves
$priceQ = Price-WeiPerToken $resQ[0] $resQ[1]
$tl1 = Bal $st.timelock; $stk1 = Bal $st.staking; $ct1 = Bal $st.token
$consumed = $inv3 - $inv4
$ethReceived = ($stk1 - $stk0) + ($ct1 - $ct0) + ($tl1 - $tl0)
$marketingEth = [System.Numerics.BigInteger]::Divide($ethReceived * $mkt, $liq)
Log-Step "H1.22" "Step 10: the stranger pokes (1 wei of DMN straight to the pair)" "the call succeeds; exactly ONE threshold-sized chunk converts (#28 budget)" "consumed=$consumed wei ($(FmtB $consumed)) vs threshold $minSwap; poke gas=$($hP.gasUsed), block $($hP.block)" $hP.hash $(if ($consumed -eq $minSwap) { "PASS" } else { "DEVIATION" })
Log-Step "H1.23" "Where the BNB went, with stakingRewardShareBps == 1000" "the WHOLE marketing share (20/30 of the proceeds) to the staking pool, the buyback share retained by the token, and NO BNB from the token to the Timelock: the marketing-wallet branch is not entered (launch invariant)" "received=$ethReceived wei ($(FmtT $ethReceived) BNB): staking +$(FmtT ($stk1 - $stk0)) (expected $(FmtT $marketingEth)), contract +$(FmtT ($ct1 - $ct0)) (expected $(FmtT ($ethReceived - $marketingEth))), TIMELOCK +$($tl1 - $tl0) wei" "-" $(if (($tl1 - $tl0) -eq 0 -and ($stk1 - $stk0) -eq $marketingEth -and ($ct1 - $ct0) -eq ($ethReceived - $marketingEth) -and $ethReceived -gt 0) { "PASS" } else { "DEVIATION" })

# ---- THE RATIO: chunk sold vs reserves, and the price move ----------------
$chunkBps = [System.Numerics.BigInteger]::Divide($consumed * 10000, $resP[0])
$bnbOut = $resP[1] - $resQ[1]
$bnbOutBps = [System.Numerics.BigInteger]::Divide($bnbOut * 10000, $resP[1])
$moveBps = MoveBps $priceP $priceQ
$pctChunk = "$([System.Numerics.BigInteger]::Divide($chunkBps, 100)).$(([System.Numerics.BigInteger]::Remainder($chunkBps, 100)).ToString().PadLeft(2,'0'))"
$pctMove = "$([System.Numerics.BigInteger]::Divide($moveBps, 100)).$(([System.Numerics.BigInteger]::Remainder($moveBps, 100)).ToString().PadLeft(2,'0'))"
Log-Step "H1.24" "THE NUMBER: the fee-swap chunk sold by the poke against the pool it was sold into" "recorded, not judged here: chunk / DMN reserve before the poke; BNB drawn / BNB reserve; price before -> after and the move. This is what says whether 3 BNB is too thin on mainnet (the chunk is fixed: minimumTokensBeforeSwap = 0.02% of supply = 0.2 B)" "chunk sold=$(FmtB $consumed) against DMN reserve $(FmtB $resP[0]) = $chunkBps bps ($pctChunk %); BNB drawn=$(FmtT $bnbOut) of $(FmtT $resP[1]) = $bnbOutBps bps; price $priceP -> $priceQ wei/token, move -$moveBps bps (-$pctMove %); reserves after DMN=$($resQ[0]) BNB=$($resQ[1]); pool size: $(FmtT $st.liqBnbWei) tBNB opened at $($st.liqPriceWeiPerToken) wei/token" $hP.hash "PASS"
$tlDmn = CQ $st.token "balanceOf(address)(uint256)" @($st.timelock)
Log-Step "H1.25" "The marketing wallet (= the Timelock) after the first conversion on a public chain" "zero DMN, zero BNB: it received nothing (the invariant, asserted after every send so far: $($st.invariantChecks) checks)" "timelock DMN=$tlDmn, timelock BNB=$tl1" "-" $(if ($tlDmn -eq 0 -and $tl1 -eq 0) { "PASS" } else { "DEVIATION" })

$st | Add-Member -NotePropertyName pokeTx -NotePropertyValue $hP.hash -Force
$st | Add-Member -NotePropertyName pokeChunkBps -NotePropertyValue "$chunkBps" -Force
$st | Add-Member -NotePropertyName pokeMoveBps -NotePropertyValue "$moveBps" -Force
Save-State $st
Write-Output "H1f COMPLETE chunk/reserves=$chunkBps bps, price move=-$moveBps bps"
