# H3 - Level 2b, Day 0 (compressed with RPC time travel): governance moves
# stakingRewardShareBps from 1000 to 600, then a poke with inventory in the
# token makes the marketing branch execute for the FIRST time -- toward the
# Timelock, which is the marketing wallet since H0.1.
. .\script\campaign\lib.ps1
$script:LOG = Join-Path $script:ROOT "docs\CHAPEL_2B_RESULTS.md"
Log-Scenario "H3" "setStakingRewardShareBps(600) by governance (warped), then the first poke that pays the marketing branch: 40% to the Timelock, call succeeds"
Start-CampaignNode
$old = Deploy-OldToken
$st = Run-MainDeploy $old -DerivedTreasury -DerivedMarketing   # 11b applied by the harness
Send "deployer" $st.old "setMaxTxAmount(uint256)" @("$(BW '1000.00')") -NoInvariant | Out-Null   # 11a

# Launch state: pool by the deployer, LP in the Timelock, a staker with weight.
# (The model gives the deployer no DMX: team1 funds it first, as in H1 --
# fee-free, the deployer being exempt on the mock.)
Send "team1" $st.old "transfer(address,uint256)" @($script:Addr.deployer, "$(BW '12.00')") -NoInvariant | Out-Null
Claim-Dmn "deployer" (BW "10.00") | Out-Null
Setup-Pool "deployer" "4.00" | Out-Null
Move-LpToTimelock "deployer" | Out-Null
Claim-Dmn "team1" (BW "20.00") | Out-Null
Stake-Dmn "team1" (BW "4.00") 3 | Out-Null
# Fee inventory from ordinary transfers, well above one threshold.
Send "team1" $st.token "transfer(address,uint256)" @($script:Addr.alice, "$(BW '4.00')") | Out-Null
Send "team1" $st.token "transfer(address,uint256)" @($script:Addr.bob, "$(BW '4.00')") | Out-Null
Send "team1" $st.token "transfer(address,uint256)" @($script:Addr.stranger, "$(BW '0.50')") | Out-Null
$minSwap = CQ $st.token "minimumTokensBeforeSwap()(uint256)"
$share0 = CQ $st.token "stakingRewardShareBps()(uint256)"
$mk = CQRaw $st.token "marketingWallet()(address)"
$tlBnbStart = Bal $st.timelock
Log-Step "H3.1" "Launch state before the vote" "share 1000, marketing wallet == Timelock, inventory armed, Timelock BNB zero" "share=$share0, marketingWallet=$mk (timelock=$($st.timelock)), inventory=$(FmtB (Fee-Inventory)) vs threshold $(FmtB $minSwap), timelock BNB=$(FmtT $tlBnbStart), LP in timelock=$(CQ $st.pair 'balanceOf(address)(uint256)' @($st.timelock))" $(if ($share0 -eq 1000 -and "$mk".ToLower() -eq "$($st.timelock)".ToLower() -and (Fee-Inventory) -ge $minSwap -and $tlBnbStart -eq 0) { "PASS" } else { "DEVIATION" })

# ---- The governance cycle, compressed by evm_increaseTime -----------------
$calldata = (cast calldata "setStakingRewardShareBps(uint256)" 600)
$id = Propose-Call "team1" $st.token "$calldata" "operational-share-600"
$s1 = Prop-State $id
Warp (86400 + 60)
Vote-Prop "team1" $id 1 | Out-Null
$s2 = Prop-State $id
Warp (5 * 86400 + 60)
$s3 = Prop-State $id
Queue-Prop $id | Out-Null
$s4 = Prop-State $id
$revEarly = Expect-Revert "stranger" $st.governor "execute(uint256)" @("$id")
Log-Step "H3.2" "propose -> (1 day) vote -> (5 days) queue; execute attempted at once" "Pending, Active, Succeeded, Queued; the early execute is refused by the 7-day timelock" "after propose=$s1, after vote=$s2, after voting=$s3, after queue=$s4; early execute: $revEarly" $(if ($s1 -eq "Pending" -and $s2 -eq "Active" -and $s3 -eq "Succeeded" -and $s4 -eq "Queued" -and "$revEarly" -match "reverted") { "PASS" } else { "DEVIATION" })

Warp (7 * 86400 + 60)
Exec-Prop $id | Out-Null
$s5 = Prop-State $id
$share1 = CQ $st.token "stakingRewardShareBps()(uint256)"
Log-Step "H3.3" "execute after 7 warped days" "Executed; stakingRewardShareBps == 600 on the live token" "state=$s5, share $share0 -> $share1" $(if ($s5 -eq "Executed" -and $share1 -eq 600) { "PASS" } else { "DEVIATION" })

# ---- The poke: the marketing branch runs for the first time ---------------
$mkt = CQ $st.token "marketingFee()(uint256)"; $liq = CQ $st.token "liquidityFee()(uint256)"
$inv1 = Fee-Inventory
$tl0 = Bal $st.timelock; $stk0 = Bal $st.staking; $ct0 = Bal $st.token
$pokeTx = Poke "stranger"
$inv2 = Fee-Inventory
$tl1 = Bal $st.timelock; $stk1 = Bal $st.staking; $ct1 = Bal $st.token
$consumed = $inv1 - $inv2
$ethReceived = ($stk1 - $stk0) + ($ct1 - $ct0) + ($tl1 - $tl0)
$marketingEth = ($ethReceived * $mkt) / $liq
$toStaking = ($marketingEth * $share1) / 1000
$toMarketing = $marketingEth - $toStaking
$pct = if ($marketingEth -gt 0) { [System.Numerics.BigInteger]::Divide(($tl1 - $tl0) * 1000, $marketingEth) } else { -1 }
Log-Step "H3.4" "The stranger pokes with $(FmtB $inv1) of inventory" "the call succeeds (status 0x1, no revert on the Timelock leg) and exactly one chunk converts" "tx=$pokeTx, consumed=$(FmtB $consumed) vs threshold $(FmtB $minSwap)" $(if ($consumed -eq $minSwap -and $pokeTx) { "PASS" } else { "DEVIATION" })
Log-Step "H3.5" "Where the BNB went, with share 600" "marketing share = received x 20/30; 60% of it to staking, 40% to the TIMELOCK (marketing wallet), the buyback share retained -- every leg exact to the wei" "received=$(FmtT $ethReceived): staking +$(FmtT ($stk1 - $stk0)) (expected $(FmtT $toStaking)), TIMELOCK +$(FmtT ($tl1 - $tl0)) (expected $(FmtT $toMarketing)), contract +$(FmtT ($ct1 - $ct0)) (expected $(FmtT ($ethReceived - $marketingEth))); timelock share of marketing = $pct per mille" $(if (($tl1 - $tl0) -eq $toMarketing -and ($tl1 - $tl0) -gt 0 -and ($stk1 - $stk0) -eq $toStaking -and ($ct1 - $ct0) -eq ($ethReceived - $marketingEth)) { "PASS" } else { "DEVIATION" })
Log-Step "H3.6" "The Timelock's BNB balance across the whole scenario" "zero from deploy until this poke, then up by exactly the 40% share -- the first BNB the treasury ever receives from the token" "$(FmtT $tlBnbStart) -> $(FmtT $tl0) (before the poke) -> $(FmtT $tl1)" $(if ($tlBnbStart -eq 0 -and $tl0 -eq 0 -and $tl1 -gt 0) { "PASS" } else { "DEVIATION" })
$sentinel = CQ $st.token "balanceOf(address)(uint256)" @($script:MARKETING)
Log-Step "H3.7" "The Level-1 keyless sentinel (0x...A001), no longer the marketing wallet" "untouched: it is not wired anywhere on this deploy" "DMN=$sentinel, native=$(FmtT (Bal $script:MARKETING))" $(if ($sentinel -eq 0 -and (Bal $script:MARKETING) -eq 0) { "PASS" } else { "DEVIATION" })
Log-Note "The branch that never ran in Level 1 or on Chapel -- marketingWallet.call{value}(...) -- ran here for the first time, against the Timelock, and did not revert: the Timelock's receive() takes the BNB and the split lands to the wei on all three legs. Restoring an operational share is therefore a one-proposal change with no wiring to touch, exactly as the deploy comment says."
Stop-Anvil
Write-Output "H3 COMPLETE"
