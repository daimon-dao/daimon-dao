# H1 - Level 2b, Day 0: the launch order 1-11b end to end on the fork, with
# the H0 script changes: derived marketing wallet, fees set in phase 2, the
# 36-check gate, LP tokens to the Timelock, the 4% test swap, the first
# poke with share 1000 (NO BNB to the Timelock), then 11a/11b last.
. .\script\campaign\lib.ps1
$script:LOG = Join-Path $script:ROOT "docs\CHAPEL_2B_RESULTS.md"
Log-Scenario "H1" "Launch order 1-11b on the fork: new defaults, 36-check gate, LP to the Timelock, 4% fee, first poke, 11a then 11b"
Start-CampaignNode
$old = Deploy-OldToken

# ---- Step 1: the pair must NOT exist before phase 1 (#25) ----------------
# Phase 1 creates impl, proxy, migration: the proxy lands at nonce + 1.
$nonce = [int]((cast nonce $script:Addr.deployer --rpc-url $script:RPC | Out-String).Trim())
$predictedToken = (((cast compute-address $script:Addr.deployer --nonce ($nonce + 1) | Out-String).Trim()) -split "\s+")[-1]
$factory = CQRaw $script:ROUTER "factory()(address)"
$wbnb = CQRaw $script:ROUTER "WETH()(address)"
$prePair = CQRaw $factory "getPair(address,address)(address)" @($predictedToken, $wbnb)
Log-Step "H1.1" "Step 1: DMN/WBNB pair on the factory BEFORE phase 1 (#25)" "none: getPair(predicted proxy, WBNB) == 0x0" "predicted proxy=$predictedToken (deployer nonce $nonce + 1), getPair=$prePair" $(if ("$prePair" -eq "0x0000000000000000000000000000000000000000") { "PASS" } else { "DEVIATION" })

# ---- Step 2: the two-phase deploy, mainnet-faithful: NO override of any kind
# (treasury derived, marketing derived), and NO exemption yet (11b is last).
$st = Run-MainDeploy $old -DerivedTreasury -DerivedMarketing -SkipTreasuryPreflight
$dep = Get-Content (Join-Path $script:ROOT (Join-Path "deployments" "two-phase-97.json")) -Raw | ConvertFrom-Json
Log-Step "H1.2" "Step 2: phase 1 + phase 2 broadcast against the live node, no env override" "five contracts up; state file records treasuryOverridden=false AND marketingWalletOverridden=false" "token=$($st.token), timelock=$($st.timelock), governor=$($st.governor); treasuryOverridden=$($dep.treasuryOverridden), marketingWalletOverridden=$($dep.marketingWalletOverridden), MARKETING_WALLET env present=$(if ($env:MARKETING_WALLET) { 'yes' } else { 'no' })" $(if ($st.governor -and -not $dep.treasuryOverridden -and -not $dep.marketingWalletOverridden -and -not $env:MARKETING_WALLET) { "PASS" } else { "DEVIATION" })

$mk = CQRaw $st.token "marketingWallet()(address)"
$migGov = CQRaw $st.migration "governance()(address)"
$migTreasury = CQRaw $st.migration "treasury()(address)"
Log-Step "H1.3" "H0.1 -- the marketing wallet, read from the live token" "it IS the timelock deployed in phase 2: the same prediction as the migration treasury and governance, all three fulfilled" "token.marketingWallet=$mk, migration.treasury=$migTreasury, migration.governance=$migGov, timelock=$($st.timelock)" $(if ("$mk".ToLower() -eq "$($st.timelock)".ToLower() -and "$migTreasury".ToLower() -eq "$($st.timelock)".ToLower() -and "$migGov".ToLower() -eq "$($st.timelock)".ToLower()) { "PASS" } else { "DEVIATION" })

$tax = CQ $st.token "taxFee()(uint256)"; $buy = CQ $st.token "buybackFee()(uint256)"; $mkt = CQ $st.token "marketingFee()(uint256)"; $liq = CQ $st.token "liquidityFee()(uint256)"
Log-Step "H1.4" "H0.2 -- the fees, read from the live token right after phase 2" "10/10/20, liquidityFee 30: the 4% model live from the first block, no proposal needed" "taxFee=$tax buybackFee=$buy marketingFee=$mkt liquidityFee=$liq (total $(($tax+$liq)/10)%)" $(if ($tax -eq 10 -and $buy -eq 10 -and $mkt -eq 20 -and $liq -eq 30) { "PASS" } else { "DEVIATION" })

$share = CQ $st.token "stakingRewardShareBps()(uint256)"
$eT = CQ $st.token "guardianExpiry()(uint256)"; $eL = CQ $st.timelock "guardianAuthorityExpiry()(uint256)"; $eG = CQ $st.governor "guardianAuthorityExpiry()(uint256)"
$supply = CQ $st.token "totalSupply()(uint256)"; $inMig = CQ $st.token "balanceOf(address)(uint256)" @($st.migration)
Log-Step "H1.5" "The rest of the phase-2 configuration, live" "share 1000; one expiry across the three contracts; the whole supply in the migration" "share=$share; expiry token=$eT timelock=$eL governor=$eG; supply=$(FmtB $supply) in migration=$(FmtB $inMig)" $(if ($share -eq 1000 -and $eT -eq $eL -and $eT -eq $eG -and $supply -eq $inMig) { "PASS" } else { "DEVIATION" })

# ---- Step 3: the post-broadcast verification, 36 checks -------------------
$r1 = Run-Verify
$vExit = $r1[0]; $vOut = $r1[1]
$vTail = (($vOut -split "`r?`n" | Where-Object { $_ -match 'VERIFICATION' }) -join ' ')
Log-Step "H1.6" "Step 3: script/verify-deploy.ps1 against the live node (H0.3: 34 -> 36 checks)" "36/36 green, exit code 0 -- the MANDATORY GATE" "exit=$vExit; $vTail" $(if ($vExit -eq 0 -and $vTail -match "36/36") { "PASS" } else { "DEVIATION" })
Log-Line ""; Log-Line "Full output of the verification, verbatim:"; Log-Line ""; Log-Line '```'
foreach ($l in ($vOut -split "`r?`n")) { Log-Line ($l.TrimEnd()) }
Log-Line '```'
if ($vExit -ne 0) { Stop-Anvil; Write-Output "H1 STOPPED: verification failed"; exit 1 }

# ---- The window is CLOSED until 11b: a claim cannot happen ----------------
Send "team1" $st.old "approve(address,uint256)" @($st.migration, "$(BW '1.00')") -NoInvariant | Out-Null
$rev = Expect-Revert "team1" $st.migration "claim(uint256)" @("$(BW '1.00')") -errSig "AmountMismatch()"
Log-Step "H1.7" "A non-exempt holder tries to claim 1.00 B after the gate, BEFORE 11b" "refused with AmountMismatch (#29): no claim is possible against this deployment yet" "$rev" $(if ("$rev" -match "AmountMismatch") { "PASS" } else { "DEVIATION" })

# ---- Step 4: automation armed by initialize, inert without reserves -------
$sal = CQRaw $st.token "swapAndLiquifyEnabled()(bool)"; $bbe = CQRaw $st.token "buyBackEnabled()(bool)"
$inv0 = Fee-Inventory
Log-Step "H1.8" "Step 4: automation state before liquidity (#27)" "enabled by initialize, inert by construction: no inventory, no reserves, pokes are the only trigger" "swapAndLiquifyEnabled=$sal buyBackEnabled=$bbe, inventory=$(FmtB $inv0), pair reserves=(0,0) by construction" $(if ("$sal" -eq "true" -and $inv0 -eq 0) { "PASS" } else { "DEVIATION" })

# ---- Step 5 prerequisite: the deployer needs DMN, and only a claim makes DMN
# The Level-1 model hands the WHOLE 1000 B to the modelled holders, so the
# deployer owns no DMX: a team wallet funds it first. On the fork the
# deployer is BOTH the mock's owner (cap-exempt: to == owner) AND fee-exempt
# on it (Deploy-OldToken exempts the distributor, so the funding transfer
# and the claim leg both run fee-free), so its claim passes before 11b. On
# mainnet neither holds: see the note at the end.
Send "team1" $st.old "transfer(address,uint256)" @($script:Addr.deployer, "$(BW '12.00')") -NoInvariant | Out-Null
$depOld = CQ $st.old "balanceOf(address)(uint256)" @($script:Addr.deployer)
Claim-Dmn "deployer" (BW "10.00") | Out-Null
$depDmn = CQ $st.token "balanceOf(address)(uint256)" @($script:Addr.deployer)
Log-Step "H1.9" "Step 5 prerequisite: team1 sends the deployer 12.00 B DMX, the deployer migrates 10.00 B for the pool and the later steps" "exact on both transfers -- on the fork the deployer is fee-exempt on the mock (as recipient and as sender) AND its owner (cap-exempt)" "deployer DMX after funding=$(FmtB $depOld), deployer DMN=$(FmtB $depDmn); mock: excludedFromFee(deployer)=$(CQRaw $st.old 'excludedFromFee(address)(bool)' @($script:Addr.deployer)), owner=$(CQRaw $st.old 'owner()(address)')" "NOTE"

# ---- Step 5: initial liquidity, BNB leg on the NET (#17) ------------------
$gross = Setup-Pool "deployer" "4.00"
$net = ($gross * (1000 - $tax - $liq)) / 1000
$res = Pair-Reserves
$ratio = [System.Numerics.BigInteger]::Divide($res[0], $res[1])
Log-Step "H1.10" "Step 5: deployer adds 4.00 B gross + BNB computed on the NET receipt" "reserve DMN == 4.00 B x 0.96 = 3.84 B (the 4% fee, not 5%); opening price exactly 1e9 DMN/BNB" "reserve DMN=$(FmtB $res[0]) (net expected $(FmtB $net)), BNB=$(FmtT $res[1]), implied=$ratio DMN/BNB" $(if ($res[0] -eq $net -and $ratio -eq 1000000000) { "PASS" } else { "DEVIATION" })

# ---- Step 6: LP tokens deployer -> Timelock (H0.4) -----------------------
$lp = Move-LpToTimelock "deployer"
Log-Step "H1.11" "Step 6: ALL the LP tokens, deployer -> Timelock, one published transaction (H0.4)" "from mined state: pair.balanceOf(deployer) == 0 and pair.balanceOf(timelock) == pair.totalSupply() - MINIMUM_LIQUIDITY (1000 wei)" "moved=$($lp.moved) wei LP; deployer LP=$($lp.provider), timelock LP=$($lp.timelock), totalSupply=$($lp.supply), MINIMUM_LIQUIDITY=$($lp.minLiq); tx=$($lp.tx)" $(if ($lp.ok) { "PASS" } else { "DEVIATION" })

# ---- Step 7: one pool only ------------------------------------------------
$factPair = CQRaw $factory "getPair(address,address)(address)" @($st.token, $wbnb)
Log-Step "H1.12" "Step 7: the pair the token stores vs the pair the factory created" "identical" "token.uniswapV2Pair=$($st.pair), factory.getPair=$factPair" $(if ("$factPair".ToLower() -eq "$($st.pair)".ToLower()) { "PASS" } else { "DEVIATION" })

# ---- Step 8: reserves non-zero -> automation live -------------------------
Log-Step "H1.13" "Step 8: both reserves non-zero" "automation can now run on a real pool" "DMN=$(FmtB $res[0]), BNB=$(FmtT $res[1])" $(if ($res[0] -gt 0 -and $res[1] -gt 0) { "PASS" } else { "DEVIATION" })

# ---- Step 9: a small test swap pays the 4% fee ----------------------------
$sellAmt = BW "0.05"
$invBefore = Fee-Inventory
$resBefore = Pair-Reserves
Sell-Dmn "deployer" $sellAmt | Out-Null
$invAfter = Fee-Inventory
$resAfter = Pair-Reserves
$pairGot = $resAfter[0] - $resBefore[0]
$expect96 = ($sellAmt * 96) / 100
$expect95 = ($sellAmt * 95) / 100
Log-Step "H1.14" "Step 9: deployer sells 0.05 B through the real router" "the pair receives EXACTLY 96% of the amount sent (fee 4%), NOT 95%" "pair DMN reserve +$pairGot wei = $(FmtB $pairGot) (96% would be $expect96, 95% would be $expect95); inventory +$(FmtB ($invAfter - $invBefore)) (>= the 3% liquidityFee share: $(FmtB (($sellAmt * 3) / 100)))" $(if ($pairGot -eq $expect96 -and ($invAfter - $invBefore) -ge (($sellAmt * 3) / 100)) { "PASS" } else { "DEVIATION" })
Log-Step "H1.15" "Did the router sell trigger any conversion? (#1)" "no: router-initiated transfers skip the automation, inventory only grew" "inventory $(FmtB $invBefore) -> $(FmtB $invAfter), contract BNB=$(FmtT (Bal $st.token))" $(if ($invAfter -gt $invBefore -and (Bal $st.token) -eq 0) { "PASS" } else { "DEVIATION" })

# ---- Step 10: the first poke -- share 1000, NOTHING to the Timelock -------
# Arm the inventory above minimumTokensBeforeSwap with ordinary transfers.
Send "deployer" $st.token "transfer(address,uint256)" @($script:Addr.alice, "$(BW '4.00')") | Out-Null
Send "deployer" $st.token "transfer(address,uint256)" @($script:Addr.stranger, "$(BW '0.50')") | Out-Null
$minSwap = CQ $st.token "minimumTokensBeforeSwap()(uint256)"
$inv1 = Fee-Inventory
$tlBnb0 = Bal $st.timelock; $stk0 = Bal $st.staking; $ct0 = Bal $st.token
Log-Step "H1.16" "Inventory armed by ordinary transfers (4.00 B to alice, 0.50 B to the stranger)" "inventory >= minimumTokensBeforeSwap; Timelock BNB still zero" "inventory=$(FmtB $inv1) vs threshold $(FmtB $minSwap); timelock BNB=$(FmtT $tlBnb0), staking BNB=$(FmtT $stk0), contract BNB=$(FmtT $ct0)" $(if ($inv1 -ge $minSwap -and $tlBnb0 -eq 0) { "PASS" } else { "DEVIATION" })

$pokeTx = Poke "stranger"
$inv2 = Fee-Inventory
$tlBnb1 = Bal $st.timelock; $stk1 = Bal $st.staking; $ct1 = Bal $st.token
$consumed = $inv1 - $inv2
$ethReceived = ($stk1 - $stk0) + ($ct1 - $ct0) + ($tlBnb1 - $tlBnb0)
$marketingEth = ($ethReceived * $mkt) / $liq
Log-Step "H1.17" "Step 10: the stranger pokes (1 wei of DMN to the pair)" "exactly ONE threshold-sized chunk converts (#28 budget); the call succeeds" "consumed=$(FmtB $consumed) vs threshold $(FmtB $minSwap); tx=$pokeTx" $(if ($consumed -eq $minSwap) { "PASS" } else { "DEVIATION" })
Log-Step "H1.18" "Where the BNB went, with stakingRewardShareBps == 1000" "the WHOLE marketing share (20/30 of the proceeds) to the staking pool, the buyback share retained by the token, and NO BNB from the token to the Timelock -- the marketing-wallet branch is not entered" "received=$(FmtT $ethReceived) BNB: staking +$(FmtT ($stk1 - $stk0)), contract +$(FmtT ($ct1 - $ct0)), TIMELOCK +$(FmtT ($tlBnb1 - $tlBnb0)); marketing share computed=$(FmtT $marketingEth)" $(if (($tlBnb1 - $tlBnb0) -eq 0 -and ($stk1 - $stk0) -eq $marketingEth -and ($ct1 - $ct0) -eq ($ethReceived - $marketingEth) -and $ethReceived -gt 0) { "PASS" } else { "DEVIATION" })
$tlDmn = CQ $st.token "balanceOf(address)(uint256)" @($st.timelock)
Log-Step "H1.19" "The marketing wallet (= the Timelock) after the first conversion" "zero DMN, zero BNB delta: it received nothing" "timelock DMN=$tlDmn, timelock BNB delta=$($tlBnb1 - $tlBnb0)" $(if ($tlDmn -eq 0 -and ($tlBnb1 - $tlBnb0) -eq 0) { "PASS" } else { "DEVIATION" })

# ---- Step 11a: DMX setMaxTxAmount raised (owner call) --------------------
$cap0 = CQ $st.old "maxTxAmount()(uint256)"
$newCap = BW "1000.00"
Send "deployer" $st.old "setMaxTxAmount(uint256)" @("$newCap") -NoInvariant | Out-Null
$cap1 = CQ $st.old "maxTxAmount()(uint256)"
Log-Step "H1.20" "Step 11a: the DMX owner raises _maxTxAmount (H0.5 model)" "1.50 B before (the real value); the new value read back from the chain" "maxTxAmount $(FmtB $cap0) -> $(FmtB $cap1)" $(if ($cap0 -eq (BW "1.50") -and $cap1 -eq $newCap) { "PASS" } else { "DEVIATION" })

# ---- Step 11b: excludeFromFee(TIMELOCK): the window opens -----------------
Send "deployer" $st.old "excludeFromFee(address)" @($st.timelock) -NoInvariant | Out-Null
$ex = CQRaw $st.old "excludedFromFee(address)(bool)" @($st.timelock)
$exMig = CQRaw $st.old "excludedFromFee(address)(bool)" @($st.migration)
Log-Step "H1.21" "Step 11b: excludeFromFee(TIMELOCK) on the predecessor -- the TREASURY, not the Migration" "exemption active on the timelock, none on the migration" "excludedFromFee(timelock)=$ex, excludedFromFee(migration)=$exMig" $(if ("$ex" -eq "true" -and "$exMig" -eq "false") { "PASS" } else { "DEVIATION" })

$tOld0 = CQ $st.old "balanceOf(address)(uint256)" @($st.timelock)
$t1Dmn0 = CQ $st.token "balanceOf(address)(uint256)" @($script:Addr.team1)
Claim-Dmn "team1" (BW "1.00") | Out-Null
$tOld1 = CQ $st.old "balanceOf(address)(uint256)" @($st.timelock)
$t1Dmn1 = CQ $st.token "balanceOf(address)(uint256)" @($script:Addr.team1)
Log-Step "H1.22" "The same holder refused in H1.7 claims 1.00 B now" "exact 1:1: the Timelock (treasury) receives exactly 1.00 B of the predecessor, team1 exactly 1.00 B DMN" "treasury old +$(FmtB ($tOld1 - $tOld0)), team1 DMN +$(FmtB ($t1Dmn1 - $t1Dmn0))" $(if (($tOld1 - $tOld0) -eq (BW "1.00") -and ($t1Dmn1 - $t1Dmn0) -eq (BW "1.00")) { "PASS" } else { "DEVIATION" })

Log-Note "Launch-order finding surfaced by H1.9, recorded and NOT worked around: step 5 (initial liquidity) needs DMN in the deployer's hands, and the only source of DMN is claim() -- which the checklist opens at step 11b, six steps later. On this fork the deployer's claim passes only because the harness makes the deployer the mock's fee-exempt distributor AND its owner. On mainnet the deployer is a dedicated Ledger, not the DMX owner and not exempt: the DMX it receives arrives net of the 11% fee, and its pre-11b claim would revert with AmountMismatch (the 11% DMX fee on the deployer -> Timelock leg) and, above 1.5B, with the cap. The order needs an explicit extra owner call BEFORE step 5 -- DMX excludeFromFee(deployer) (from-side exemption; the cap still binds at 1.5B per claim unless 11a moves earlier too) -- or the liquidity must be provided by an address that already holds DMN. Decision is the operator's; the checklist does not list this call today."
Stop-Anvil
Write-Output "H1 COMPLETE"
