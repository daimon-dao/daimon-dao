# The launch day, steps 1-11b of CHECKLIST_MAINNET.md, on the LOCAL fork
# started by start-fork.ps1 -- then the post-11b claims by two real
# third-party holders, then the totals.
#
#   powershell -File script/fork/launch-day.ps1 [-FundOwnerForLiquidity] [-GriefProbe]
#
# Default: faithful. The DMX owner keeps its REAL BNB balance; if that
# cannot fund step 5b the run STOPS there (a finding), finalizes the totals
# and moves the launch artifacts away.
# -FundOwnerForLiquidity: at the 5b gate, if the owner is short, the fork
#   adds EXACTLY the BNB leg of the liquidity to the owner's balance
#   (anvil_setBalance, logged as a setup deviation) -- every gas cost after
#   that is still paid from the owner's real balance -- and the day goes on
#   to 11b. The STOP row is logged all the same.
# -GriefProbe: before 5b, inside evm_snapshot/evm_revert, a stranger
#   donates 1 wei of WBNB to the empty DMN pair and calls sync(); records
#   whether the router's addLiquidityETH is then refused, and whether the
#   direct path (transfer + mint) still opens the pool at the right price.
param([switch]$FundOwnerForLiquidity, [switch]$GriefProbe)
. $PSScriptRoot\lib.ps1
Load-Holders
$st = S
if (-not $st -or -not $st.gasPrice) { throw "run start-fork.ps1 first" }
if ($st.token) { throw "this fork already carries a deployment (token $($st.token)): start a fresh fork" }
Assert-LocalFork
$runLabel = $st.label
$GAS_RESERVE = BI "2000000000000000"   # 0.002 BNB kept by the owner for the rest of the day's gas (5b..11b)
$MILLE = BI "1000000000000000"         # 0.001 BNB
$USDT = "0x55d398326f99059fF775485246999027B3197955"; $BUSD = "0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56"
$ownerTopUp = [System.Numerics.BigInteger]::Zero

function Finalize { param([string]$how)
  $st = S
  $depEnd = Bal $script:DEPLOYER; $ownEnd = Bal $script:OWNER
  $depStart = BI $st.deployerStart; $ownStart = BI $st.ownerStart
  $rows = @($script:Ledger | Where-Object { -not $_.probe })
  Log-Line ""
  Log-Line "### Gas ledger (run $runLabel) -- every mined transaction of the day, probes excluded"
  Log-Line ""
  Log-Line "| step | signer | call | gas used | gas price (wei) | cost (BNB) |"
  Log-Line "|---|---|---|---|---|---|"
  $byStep = [ordered]@{}
  foreach ($r in $rows) {
    $who = if ($r.who -eq "holderA") { "holder A" } elseif ($r.who -eq "holderB") { "holder B" } else { $r.who }
    Log-Line "| $($r.step) | $who | $($r.what) | $($r.gas) | $($r.price) | $(FmtT $r.cost) |"
  }
  $sum = @{}
  foreach ($role in @("deployer", "owner", "holderA", "holderB")) {
    $g = [System.Numerics.BigInteger]::Zero; $c = [System.Numerics.BigInteger]::Zero; $n = 0
    foreach ($r in ($rows | Where-Object { $_.who -eq $role })) { $g += (BI $r.gas); $c += (BI $r.cost); $n++ }
    $sum[$role] = @{ gas = $g; cost = $c; n = $n }
  }
  $gp = BI $st.gasPrice
  Log-Scenario "F14 (run $runLabel)" "Gas and BNB: what the day actually cost ($how)"
  $depSpent = $depStart - $depEnd
  Log-Step "F14.1" "DEPLOYER: total spent, from its balance (start - end) and from the ledger" "the two phases only ($($sum.deployer.n) transactions); start 0.2 BNB exactly; spent == sum of gas x price" "start=$(FmtT $depStart), end=$(FmtT $depEnd), spent=$(FmtT $depSpent) BNB ($depSpent wei); ledger: $($sum.deployer.n) txs, gas $($sum.deployer.gas), cost $(FmtT $sum.deployer.cost); at 1 gwei the same gas would cost $(FmtT ($sum.deployer.gas * 1000000000)), at 3 gwei $(FmtT ($sum.deployer.gas * 3000000000)); headroom left of the 0.2 BNB plan: $(FmtT $depEnd)" "-" $(V ($depSpent -eq $sum.deployer.cost -and $depEnd -ge 0))
  $ownSpent = $ownStart + $ownerTopUp - $ownEnd
  $ownGas = $sum.owner.cost
  $liq = if ($st.liqBnbWei) { BI $st.liqBnbWei } else { [System.Numerics.BigInteger]::Zero }
  $buy = if ($st.testBuyWei) { BI $st.testBuyWei } else { [System.Numerics.BigInteger]::Zero }
  $sellBack = if ($st.testSellProceeds) { BI $st.testSellProceeds } else { [System.Numerics.BigInteger]::Zero }
  $ownOk = ($ownSpent -eq ($ownGas + $liq + $buy - $sellBack))
  Log-Step "F14.2" "DMX OWNER: total spent" "spent == gas + BNB into the pool + test buy - test sell proceeds" "real start=$(FmtT $ownStart), fork top-up=$(FmtT $ownerTopUp), end=$(FmtT $ownEnd), spent=$(FmtT $ownSpent) BNB; of which gas=$(FmtT $ownGas) ($($sum.owner.n) txs, gas $($sum.owner.gas); at 1 gwei $(FmtT ($sum.owner.gas * 1000000000)), at 3 gwei $(FmtT ($sum.owner.gas * 3000000000))), liquidity=$(FmtT $liq), test buy=$(FmtT $buy), test sell back=$(FmtT $sellBack)" "-" $(V $ownOk)
  if ($sum.holderA.n + $sum.holderB.n -gt 0) {
    Log-Step "F14.3" "Third-party holders: gas paid from their own real balances" "their own claims only, never funded by the fork" "holder A: $($sum.holderA.n) txs, $(FmtT $sum.holderA.cost) BNB; holder B: $($sum.holderB.n) txs, $(FmtT $sum.holderB.cost) BNB" "-" "NOTE"
  }
  Log-Line ""
  Log-Line "Run $runLabel verdicts: PASS $($script:Verdicts.PASS), NOTE $($script:Verdicts.NOTE), FINDING $($script:Verdicts.FINDING), STOP $($script:Verdicts.STOP), DEVIATION $($script:Verdicts.DEVIATION); launch invariant asserted after $($script:InvariantChecks) sends; local-fork guard passed $($script:LocalChecks) times."
  # The launch artifacts leave the working tree: nothing stale for launch day.
  $dest = Join-Path $script:OUTDIR "run-$runLabel"
  if (-not (Test-Path $dest)) { New-Item -ItemType Directory -Path $dest | Out-Null }
  $sf = Join-Path $script:ROOT "deployments\two-phase-56.json"
  if (Test-Path $sf) { Move-Item $sf (Join-Path $dest "two-phase-56.json") -Force }
  foreach ($ph in @("DeployPhase1.s.sol", "DeployPhase2.s.sol")) {
    $b = Join-Path $script:ROOT "broadcast\$ph\56"
    if (Test-Path $b) { Move-Item $b (Join-Path $dest "broadcast-$ph") -Force }
  }
  $st | Add-Member -NotePropertyName ledger -NotePropertyValue @($script:Ledger) -Force
  $st | Add-Member -NotePropertyName finished -NotePropertyValue $how -Force
  Save-State $st
  Copy-Item $script:StatePath (Join-Path $dest "state.json") -Force
}

# =============================================================================
# Steps 1-2: the pair does not exist; phase 1, then phase 2, nothing between
# =============================================================================
Log-Scenario "F1-F2 (run $runLabel)" "Step 1: no DMN/WBNB pair for the predicted proxy; step 2: phase 1 then phase 2 against the real router and the real DMX"
$nonce = Nonce $script:DEPLOYER
$pred = @{}
foreach ($k in 0..3) { $pred[$k] = ((cast compute-address $script:DEPLOYER --nonce ($nonce + $k) | Out-String).Trim() -split "\s+")[-1] }
$prePair = CQRaw $script:FACTORY "getPair(address,address)(address)" @($pred[1], $script:WBNB)
$preCode = (Code-Len $pred[1]) + (Code-Len $pred[2]) + (Code-Len $pred[3])
Log-Step "F1.1" "Step 1 (#25): the REAL PancakeSwap factory, getPair(predicted proxy, WBNB), before phase 1" "0x0; and no code at the predicted proxy, migration and Timelock" "deployer nonce=$nonce; predicted impl=$($pred[0]), proxy=$($pred[1]), migration=$($pred[2]), timelock=$($pred[3]); getPair=$prePair; code chars at the three=$preCode (6 = three empty '0x')" "-" $(V ("$prePair" -eq $script:ZERO -and $preCode -eq 6))
if ("$prePair" -ne $script:ZERO) { throw "STOP: a pair pre-exists for the predicted proxy" }

$env:ROUTER = $script:ROUTER
$env:OLD_DAIMON = $script:DMX
$env:GUARDIAN_ADDRESS = $script:GUARDIAN
foreach ($v in @("MARKETING_WALLET", "TESTNET_TREASURY_OVERRIDE", "TREASURY_ADDRESS", "MIGRATION_DURATION", "OLD_SUPPLY")) { Remove-Item "env:$v" -ErrorAction SilentlyContinue }
$sim = Run-Forge "script/DeployPhase1.s.sol"
$derived = @(($sim[1] -split "`r?`n") | Where-Object { $_ -match "\(= predicted timelock\)" })
$overr = @(($sim[1] -split "`r?`n") | Where-Object { $_ -match "override active|WARNING:" })
$durLine = (($sim[1] -split "`r?`n") | Where-Object { $_ -match "Migration duration \(days\)" } | Select-Object -First 1)
$simOk = ($sim[0] -eq 0 -and $derived.Count -eq 2 -and $overr.Count -eq 0)
Log-Step "F2.1" "Phase 1 SIMULATED on chain 56 with the launch environment: ROUTER, OLD_DAIMON (real DMX), GUARDIAN_ADDRESS (real Safe); no MARKETING_WALLET, no TESTNET_TREASURY_OVERRIDE; MIGRATION_DURATION unset" "exit 0; treasury AND marketing wallet logged '(= predicted timelock)'; no override or warning line" "exit=$($sim[0]); derived lines=$($derived.Count); override/warning lines=$($overr.Count); '$(("$durLine").Trim())'" "-" $(V $simOk)
if (-not $simOk) { Log-Block "Simulation output, verbatim:" $sim[1]; throw "STOP: phase 1 simulation" }
Log-Note "MIGRATION_DURATION was left unset, so phase 1 used its default: 30 days. No document in the repository fixes the mainnet value; the deadline is immutable from phase 1. It is a launch-day input to decide before phase 1 (LAUNCH_DAY.md, inputs)."

$r1 = Run-Forge "script/DeployPhase1.s.sol" -Broadcast
if ($r1[0] -ne 0) { Log-Block "Phase 1 output (FAILED), verbatim:" $r1[1]; throw "PHASE 1 FAILED" }
$l1 = Ledger-FromBroadcast "DeployPhase1.s.sol" "2 phase 1"
$sf = Join-Path $script:ROOT "deployments\two-phase-56.json"
$dep = Get-Content $sf -Raw | ConvertFrom-Json
$nAfter1 = Nonce $script:DEPLOYER
$mk = CQRaw $dep.token "marketingWallet()(address)"; $mt = CQRaw $dep.migration "treasury()(address)"; $mg = CQRaw $dep.migration "governance()(address)"
$mOld = CQRaw $dep.migration "oldDaimon()(address)"; $tRouter = CQRaw $dep.token "uniswapV2Router()(address)"; $tPair = CQRaw $dep.token "uniswapV2Pair()(address)"
$pt = "$($dep.predictedTimelock)".ToLower()
$p1ok = ("$($dep.token)".ToLower() -eq $pred[1].ToLower() -and "$($dep.migration)".ToLower() -eq $pred[2].ToLower() -and $pt -eq $pred[3].ToLower() -and "$mk".ToLower() -eq $pt -and "$mt".ToLower() -eq $pt -and "$mg".ToLower() -eq $pt -and "$mOld".ToLower() -eq $script:DMX.ToLower() -and "$tRouter".ToLower() -eq $script:ROUTER.ToLower() -and $nAfter1 -eq [int]$dep.expectedPhase2Nonce -and -not $dep.treasuryOverridden -and -not $dep.marketingWalletOverridden)
Log-Step "F2.2" "Phase 1 BROADCAST (impersonated deployer, mainnet gas price)" "impl/proxy/migration on the predicted nonces 0/1/2; marketingWallet, migration.treasury, migration.governance == the predicted Timelock (nonce 3); migration.oldDaimon == the REAL DMX; token router == the real router; deployer nonce == expectedPhase2Nonce; no override" "$($l1.count) txs, gas $($l1.gas), cost $(FmtT $l1.cost) BNB; token=$($dep.token), migration=$($dep.migration), predictedTimelock=$($dep.predictedTimelock); marketingWallet=$mk, treasury=$mt, governance=$mg, oldDaimon=$mOld, router=$tRouter, pair created=$tPair; nonce=$nAfter1 (expected $($dep.expectedPhase2Nonce))" "journal broadcast/DeployPhase1.s.sol/56" $(V $p1ok)
if (-not $p1ok) { throw "STOP: phase 1 checks" }
Log-Block "Phase 1 console, completion block verbatim:" ((($r1[1] -split "`r?`n") | Where-Object { $_ -match "PHASE 1 complete|DaimonV2 \(proxy\)|DaimonMigration:|Timelock \(predicted\)|Migration treasury:|Marketing wallet:|Migration duration" }) -join "`n")

# ---- Phase 2, immediately: the deployer signs nothing in between ------------
# Captured BEFORE phase 2: phase 2 rewrites the state file as the complete
# deployment record, which no longer carries expectedPhase2Nonce (run B,
# F2.3: the check compared against the rewritten file and read empty).
$expected2 = [int]$dep.expectedPhase2Nonce
$nBefore2 = Nonce $script:DEPLOYER
$r2 = Run-Forge "script/DeployPhase2.s.sol" -Broadcast
if ($r2[0] -ne 0) { Log-Block "Phase 2 output (FAILED), verbatim:" $r2[1]; throw "PHASE 2 FAILED" }
$l2 = Ledger-FromBroadcast "DeployPhase2.s.sol" "2 phase 2"
$dep = Get-Content $sf -Raw | ConvertFrom-Json
$tl = "$($dep.timelock)"
$tax = CQ $dep.token "taxFee()(uint256)"; $buyF = CQ $dep.token "buybackFee()(uint256)"; $mktF = CQ $dep.token "marketingFee()(uint256)"; $liqF = CQ $dep.token "liquidityFee()(uint256)"
$share = CQ $dep.token "stakingRewardShareBps()(uint256)"
$eT = CQ $dep.token "guardianExpiry()(uint256)"; $eL = CQ $dep.timelock "guardianAuthorityExpiry()(uint256)"; $eG = CQ $dep.governor "guardianAuthorityExpiry()(uint256)"
$gG = CQRaw $dep.governor "guardian()(address)"
$p2ok = ($nBefore2 -eq $expected2 -and $tl.ToLower() -eq $pt -and $tax -eq 10 -and $buyF -eq 10 -and $mktF -eq 20 -and $liqF -eq 30 -and $share -eq 1000 -and $eT -eq $eL -and $eT -eq $eG -and "$gG".ToLower() -eq $script:GUARDIAN.ToLower())
Log-Step "F2.3" "Phase 2 BROADCAST right after phase 1 (deployer nonce untouched in between)" "Timelock lands on the prediction; fees 10/10/20 (liquidityFee 30); share 1000; ONE guardian expiry on three contracts; governor.guardian == the real Safe" "nonce before=$nBefore2 (expected $expected2); $($l2.count) txs, gas $($l2.gas), cost $(FmtT $l2.cost) BNB; timelock=$tl, staking=$($dep.staking), governor=$($dep.governor); fees=$tax/$buyF/$mktF liq=$liqF; share=$share; expiry token/timelock/governor=$eT/$eL/$eG; governor.guardian=$gG" "journal broadcast/DeployPhase2.s.sol/56" $(V $p2ok)
if (-not $p2ok) { throw "STOP: phase 2 checks" }
Log-Step "F2.4" "Deployer after both phases" "it signs nothing else for the rest of the day" "nonce=$(Nonce $script:DEPLOYER), balance=$(FmtT (Bal $script:DEPLOYER)) BNB; phases 1+2: $($l1.count + $l2.count) txs, gas $($l1.gas + $l2.gas), cost $(FmtT ($l1.cost + $l2.cost)) BNB" "-" "NOTE"
$st = S
foreach ($kv in @(@("token", $dep.token), @("migration", $dep.migration), @("timelock", $tl), @("staking", $dep.staking), @("governor", $dep.governor), @("pair", (CQRaw $dep.token "uniswapV2Pair()(address)")))) {
  $st | Add-Member -NotePropertyName $kv[0] -NotePropertyValue "$($kv[1])" -Force
}
Save-State $st
Assert-Invariants "post-phase2"

# =============================================================================
# Step 3: the gate -- 36/36 from mined state
# =============================================================================
Log-Scenario "F3-F4 (run $runLabel)" "Step 3: the mandatory gate; step 4: automation inert without reserves"
$vr = Run-Verify
$vTail = (($vr[1] -split "`r?`n" | Where-Object { $_ -match 'VERIFICATION' }) -join ' ')
Log-Step "F3.1" "Step 3: script/verify-deploy.ps1 -Rpc <the local fork>" "36/36 green, exit code 0 -- MANDATORY GATE" "exit=$($vr[0]); $vTail" "-" $(V ($vr[0] -eq 0 -and $vTail -match "36/36"))
Log-Block "Full output of the verification, verbatim:" $vr[1]
if ($vr[0] -ne 0 -or -not ($vTail -match "36/36")) { Finalize "stopped at the gate"; exit 1 }

$st = S
$sal = CQRaw $st.token "swapAndLiquifyEnabled()(bool)"; $bbe = CQRaw $st.token "buyBackEnabled()(bool)"
$inv0 = Fee-Inventory; $res0 = Pair-Reserves; $cb0 = Bal $st.token
Log-Step "F4.1" "Step 4 (#27): automation before liquidity" "enabled by initialize, inert by construction: inventory 0, reserves (0,0), contract BNB 0" "swapAndLiquifyEnabled=$sal, buyBackEnabled=$bbe, inventory=$inv0, reserves=($($res0[0]),$($res0[1])), contract BNB=$cb0" "-" $(V ("$sal" -eq "true" -and $inv0 -eq 0 -and $res0[0] -eq 0 -and $res0[1] -eq 0 -and $cb0 -eq 0))

# =============================================================================
# Step 5a: a non-owner claim still reverts; the owner claims ONLY the gross
# =============================================================================
Log-Scenario "F5a (run $runLabel)" "Step 5a on the REAL DMX: a non-owner is refused, the owner claims only the liquidity quota"
$hB = $script:AddrBook.holderB
$hBA = Send "holderB" $script:DMX "approve(address,uint256)" @($st.migration, "$(BW '1.00')") -step "5a check"
$revB = Expect-Revert "holderB" $st.migration "claim(uint256)" @("$(BW '1.00')") -match "AmountMismatch()"
$bDmn = CQ $st.token "balanceOf(address)(uint256)" @($hB)
Log-Step "F5a.1" "A REAL non-owner (holder B, below the cap, not fee-exempt) approves then claims 1.00 B, BEFORE 11b" "refused with AmountMismatch (#29): the real DMX takes its 11% on the claimant -> treasury leg; nothing credited" "approve mined (holder B's own gas); claim: $revB; holder B DMN=$bDmn" $hBA.hash $(V ("$revB" -match "reverted with AmountMismatch" -and $bDmn -eq 0))

# The launch-day form of the same check: nobody can ask a real holder to
# sign an approve on launch day, so the proof is a pure eth_call from a real
# holder that never approved, with the DMX allowance supplied by a state
# override (DMX `_allowances` is storage slot 7: Ownable's _owner,
# _previousOwner, _lockTime, then marketingAddress2, marketingAddress1,
# _rOwned, _tOwned; confirmed on mainnet 2026-09-28 by overriding it and
# reading allowance() back).
$hAx = $script:AddrBook.holderA
$aAllow = CQ $script:DMX "allowance(address,address)(uint256)" @($hAx, $st.migration)
$slot = ((cast index address $st.migration (cast index address $hAx 7) | Out-String).Trim())
$ovr = "$($script:DMX):$($slot):$(ToHex (BW '1.00'))"
$revO1 = Expect-Revert "holderA" $st.migration "claim(uint256)" @("$(BW '1.00')") -match "AmountMismatch()" -overrideState $ovr
$aDmnX = CQ $st.token "balanceOf(address)(uint256)" @($hAx)
Log-Step "F5a.1b" "The LAUNCH-DAY form of the check: eth_call claim(1.00 B) from a real holder that never approved (holder A), the DMX allowance supplied by --override-state-diff on slot keccak(migration . keccak(holder . 7))" "reverts with AmountMismatch exactly like the mined approve + claim above; nothing mined, the real allowance untouched" "real allowance before=$aAllow; claim: $revO1; holder A DMN=$aDmnX; real allowance after=$(CQ $script:DMX 'allowance(address,address)(uint256)' @($hAx, $st.migration))" "-" $(V ("$revO1" -match "reverted with AmountMismatch" -and $aAllow -eq 0 -and $aDmnX -eq 0))

$own = CQRaw $script:DMX "owner()(address)"; $oEx = CQRaw $script:DMX "isExcludedFromFee(address)(bool)" @($script:OWNER)
$tEx = CQRaw $script:DMX "isExcludedFromFee(address)(bool)" @($st.timelock); $cap = CQ $script:DMX "_maxTxAmount()(uint256)"
Log-Step "F5a.2" "Why the owner can claim now: its status on the REAL DMX" "owner() == the DMX owner (cap-exempt as sender), isExcludedFromFee(owner) true; the Timelock NOT exempt (11b not done); cap 1.5B (11a not done)" "owner=$own, isExcludedFromFee(owner)=$oEx, isExcludedFromFee(timelock)=$tEx, _maxTxAmount=$(FmtB $cap)" "-" $(V ("$own".ToLower() -eq $script:OWNER.ToLower() -and "$oEx" -eq "true" -and "$tEx" -eq "false" -and $cap -eq (BW "1.50")))

# ---- Sizing, from the REAL DMX pool read live on the fork -------------------
$pr = Reserves-Of $script:DMX_POOL $script:DMX
$price = Price-WeiPerToken $pr[0] $pr[1]
$maxTx = CQ $st.token "maxTxAmount()(uint256)"
$capNet = NetOfGross $maxTx $tax $liqF
$bnbWei = [System.Numerics.BigInteger]::Divide([System.Numerics.BigInteger]::Divide($capNet * $price, $script:E18), $MILLE) * $MILLE
$netTarget = [System.Numerics.BigInteger]::Divide($bnbWei * $script:E18, $price)
$gross = CeilDiv ($netTarget * 1000) (1000 - $tax - $liqF)
$net = NetOfGross $gross $tax $liqF
$sizeOk = ($net -ge $netTarget -and ($net - $netTarget) -lt 1000 -and $gross -le $maxTx -and $bnbWei -gt 0)
Log-Step "F5a.3" "Sizing from live values: the REAL DMX pool on the fork; the largest single addLiquidityETH under the DMN maxTx (decision (c))" "price = DMX pool WBNB reserve x 1e18 / DMX reserve; BNB leg = net(maxTx) x price, floored to 0.001 BNB; net target = BNB x 1e18 / price; gross = ceil(net x 1000 / 960); pair receives >= net target by < 1000 wei; gross <= maxTx" "DMX pool reserves DMX=$($pr[0]) ($(FmtB $pr[0])), WBNB=$($pr[1]) ($(FmtT $pr[1]) BNB) -> DMX price=$price wei/token ($([decimal]$price / 1000000000000000000) BNB); DMN maxTx=$(FmtB $maxTx) -> net $(FmtB $capNet); BNB leg=$(FmtT $bnbWei) BNB ($bnbWei wei); net target=$netTarget; gross=$gross ($(FmtB $gross)); net of gross=$net (+$($net - $netTarget) wei)" "-" $(V $sizeOk)
if (-not $sizeOk) { throw "STOP: sizing" }
$ob = Bal $script:OWNER
$need = $bnbWei + $GAS_RESERVE
Log-Step "F5a.4" "Funding preview, BEFORE the owner claims: can the owner's REAL balance fund 5b?" "owner BNB >= BNB leg + 0.002 BNB gas reserve" "owner=$(FmtT $ob) BNB; needed=$(FmtT $need) (leg $(FmtT $bnbWei) + reserve $(FmtT $GAS_RESERVE)); $(if ($ob -ge $need) { 'covered' } else { "SHORT by $(FmtT ($need - $ob)) BNB" })" "-" $(if ($ob -ge $need) { "PASS" } else { "FINDING" })

$tOld0 = CQ $script:DMX "balanceOf(address)(uint256)" @($st.timelock)
$oOld0 = CQ $script:DMX "balanceOf(address)(uint256)" @($script:OWNER)
$oDmn0 = CQ $st.token "balanceOf(address)(uint256)" @($script:OWNER)
$hOA = Send "owner" $script:DMX "approve(address,uint256)" @($st.migration, "$gross") -step "5a"
$hOC = Send "owner" $st.migration "claim(uint256)" @("$gross") -step "5a"
$tOld1 = CQ $script:DMX "balanceOf(address)(uint256)" @($st.timelock)
$oOld1 = CQ $script:DMX "balanceOf(address)(uint256)" @($script:OWNER)
$oDmn1 = CQ $st.token "balanceOf(address)(uint256)" @($script:OWNER)
$mig = CQ $st.migration "migratedAmount(address)(uint256)" @($script:OWNER)
Log-Step "F5a.5" "Step 5a: the owner approves and claims EXACTLY the gross, on the REAL DMX" "exact 1:1 on every leg: Timelock DMX +gross, owner DMX -gross, owner DMN +gross, migratedAmount == gross" "Timelock DMX +$($tOld1 - $tOld0), owner DMX -$($oOld0 - $oOld1), owner DMN +$($oDmn1 - $oDmn0), migratedAmount=$mig (gross $gross); claim gas=$($hOC.gasUsed)" "$($hOA.hash) / $($hOC.hash)" $(V (($tOld1 - $tOld0) -eq $gross -and ($oOld0 - $oOld1) -eq $gross -and ($oDmn1 - $oDmn0) -eq $gross -and $mig -eq $gross))

# =============================================================================
# Step 5b gate: the owner's REAL balance
# =============================================================================
Log-Scenario "F5b (run $runLabel)" "Step 5b: initial liquidity on the REAL router at the REAL DMX price"
$ob = Bal $script:OWNER
if ($ob -lt $need) {
  $short = $need - $ob
  Log-Step "F5b.0" "GATE: the owner's REAL BNB against the 5b requirement" "owner BNB >= BNB leg + gas reserve, or STOP" "owner=$(FmtT $ob) BNB ($ob wei); leg=$(FmtT $bnbWei), reserve=$(FmtT $GAS_RESERVE), needed=$(FmtT $need); SHORTFALL=$(FmtT $short) BNB ($short wei)" "-" "STOP"
  if (-not $FundOwnerForLiquidity) {
    Log-Note "STOPPED at 5b on the owner's real balance, as the rehearsal plan requires. On launch day the owner would now hold the claimed DMN with no pool to put it in. The owner must be funded with at least the shortfall BEFORE phase 1 (LAUNCH_DAY.md, preflight)."
    Finalize "stopped at 5b: owner shortfall"
    Write-Output "STOPPED at 5b: owner short by $(FmtT $short) BNB"
    exit 2
  }
  $ownerTopUp = $bnbWei
  Rpc "anvil_setBalance" @($script:OWNER, (ToHex ($ob + $bnbWei))) | Out-Null
  $ob2 = Bal $script:OWNER
  Log-Step "F5b.0b" "SETUP DEVIATION, by the operator's switch -FundOwnerForLiquidity: the fork adds EXACTLY the BNB leg to the owner (anvil_setBalance); every gas cost from here is still paid out of the owner's real balance" "owner = real balance + leg; the continuation measures what the owner really needs" "owner $(FmtT $ob) -> $(FmtT $ob2) BNB (+$(FmtT $bnbWei))" "-" "NOTE"
} else {
  Log-Step "F5b.0" "GATE: the owner's REAL BNB against the 5b requirement" "owner BNB >= BNB leg + gas reserve" "owner=$(FmtT $ob) BNB, needed=$(FmtT $need)" "-" "PASS"
}

$deadline = "$((Now-Ts) + 1200)"
if ($GriefProbe) {
  # ---- Probe, discarded afterwards: a 1-wei WBNB donation + sync() --------
  $snap = Rpc "evm_snapshot"
  $script:ProbeMode = $true
  $PROBE = "0x00000000000000000000000000000000000Fa11E"
  $script:AddrBook["probe"] = $PROBE
  Rpc "anvil_impersonateAccount" @($PROBE) | Out-Null
  Rpc "anvil_setBalance" @($PROBE, (ToHex (BI "10000000000000000"))) | Out-Null
  Send "probe" $script:WBNB "deposit()" -value "1" -step "probe" | Out-Null
  Send "probe" $script:WBNB "transfer(address,uint256)" @($st.pair, "1") -step "probe" | Out-Null
  $hs = Send "probe" $st.pair "sync()" -step "probe"
  $rp = Pair-Reserves
  Send "owner" $st.token "approve(address,uint256)" @($script:ROUTER, "$gross") -step "probe" | Out-Null
  $revL = Expect-Revert "owner" $script:ROUTER "addLiquidityETH(address,uint256,uint256,uint256,address,uint256)" @($st.token, "$gross", "$gross", "$bnbWei", $script:OWNER, $deadline) -match "INSUFFICIENT_LIQUIDITY" -value "$bnbWei"
  Log-Step "F5b.P1" "PROBE (inside evm_snapshot, discarded): a stranger, funded 0.01 BNB by the fork for this probe only, wraps 1 wei, sends it to the EMPTY DMN pair and calls sync(); then the owner's planned addLiquidityETH is simulated" "recorded: does a 1-wei donation block the router path?" "reserves after sync: DMN=$($rp[0]) WBNB=$($rp[1]); addLiquidityETH: $revL" $hs.hash $(if ("$revL" -match "INSUFFICIENT_LIQUIDITY") { "FINDING" } else { "NOTE" })
  $h1 = Send "owner" $st.token "transfer(address,uint256)" @($st.pair, "$gross") -step "probe"
  Send "owner" $script:WBNB "deposit()" -value "$bnbWei" -step "probe" | Out-Null
  Send "owner" $script:WBNB "transfer(address,uint256)" @($st.pair, "$bnbWei") -step "probe" | Out-Null
  $hm = Send "owner" $st.pair "mint(address)" @($script:OWNER) -step "probe"
  $rq = Pair-Reserves
  $pq = Price-WeiPerToken $rq[0] $rq[1]
  $lpq = CQ $st.pair "balanceOf(address)(uint256)" @($script:OWNER)
  Log-Step "F5b.P2" "PROBE, recovery path on the same griefed pair: owner transfers the gross DMN to the pair (taxed, automation idle), wraps the BNB leg, sends WBNB, calls pair.mint(owner)" "the pool opens anyway: reserve DMN == net, WBNB == leg + the 1 donated wei, price within 1 ppm of the DMX price; LP minted to the owner" "reserves DMN=$($rq[0]) (net $net), WBNB=$($rq[1]) (leg+1 = $($bnbWei + 1)); price=$pq vs DMX $price; LP=$lpq" $hm.hash $(V ($rq[0] -eq $net -and $rq[1] -eq ($bnbWei + 1) -and ($price - $pq) * 1000000 -le $price))
  Rpc "evm_revert" @($snap) | Out-Null
  $script:ProbeMode = $false
  $rb = Pair-Reserves
  Log-Step "F5b.P3" "PROBE discarded: evm_revert to the snapshot" "pair back to (0,0); owner DMN back to the gross; the probe's transactions excluded from every total" "reserves=($($rb[0]),$($rb[1])), owner DMN=$(CQ $st.token 'balanceOf(address)(uint256)' @($script:OWNER))" "-" $(V ($rb[0] -eq 0 -and $rb[1] -eq 0))
}

# ---- 5b: the liquidity --------------------------------------------------------
$hA = Send "owner" $st.token "approve(address,uint256)" @($script:ROUTER, "$gross") -step "5b"
$hL = Send "owner" $script:ROUTER "addLiquidityETH(address,uint256,uint256,uint256,address,uint256)" @($st.token, "$gross", "$gross", "$bnbWei", $script:OWNER, $deadline) -value "$bnbWei" -step "5b"
$res = Pair-Reserves
$pairBal = CQ $st.token "balanceOf(address)(uint256)" @($st.pair)
$oDmn2 = CQ $st.token "balanceOf(address)(uint256)" @($script:OWNER)
$open = Price-WeiPerToken $res[0] $res[1]
$lpMinted = CQ $st.pair "balanceOf(address)(uint256)" @($script:OWNER)
$pd = $price - $open
Log-Step "F5b.1" "Step 5b: approve + addLiquidityETH(token, gross, amountTokenMin = gross, amountETHMin = leg, owner) on the REAL router" "reserve DMN == net of gross (exact), reserve WBNB == the leg (no refund); owner DMN back to 0; opening price == the DMX price within 1 ppm (never above: the net is rounded up)" "BNB=$bnbWei wei ($(FmtT $bnbWei)); DMN gross=$gross ($(FmtB $gross)); DMN received by the pair: reserve=$($res[0]), balanceOf=$pairBal ($(FmtB $res[0])), expected $net; reserve WBNB=$($res[1]); OPENING PRICE=$open wei/token vs DMX $price (diff $pd wei, $(Pct $pd $price 6) %); owner DMN after=$oDmn2; LP minted=$lpMinted; gas approve=$($hA.gasUsed), add=$($hL.gasUsed)" "$($hA.hash) / $($hL.hash)" $(V ($res[0] -eq $net -and $res[1] -eq $bnbWei -and $oDmn2 -eq 0 -and $pd -ge 0 -and ($pd * 1000000) -le $price))

# =============================================================================
# Steps 6-8
# =============================================================================
Log-Scenario "F6-F8 (run $runLabel)" "Step 6: every LP token to the Timelock; step 7: one pool; step 8: reserves non-zero"
$hT = Send "owner" $st.pair "transfer(address,uint256)" @($st.timelock, "$lpMinted") -step "6"
$lpO = CQ $st.pair "balanceOf(address)(uint256)" @($script:OWNER); $lpD = CQ $st.pair "balanceOf(address)(uint256)" @($script:DEPLOYER)
$lpT = CQ $st.pair "balanceOf(address)(uint256)" @($st.timelock); $lpS = CQ $st.pair "totalSupply()(uint256)"; $minL = CQ $st.pair "MINIMUM_LIQUIDITY()(uint256)"
Log-Step "F6.1" "Step 6: ALL the LP tokens, owner -> Timelock" "owner LP 0, deployer LP 0, Timelock LP == totalSupply - MINIMUM_LIQUIDITY (1000)" "moved=$lpMinted; owner=$lpO, deployer=$lpD, timelock=$lpT, totalSupply=$lpS, MINIMUM_LIQUIDITY=$minL; gas=$($hT.gasUsed)" $hT.hash $(V ($lpO -eq 0 -and $lpD -eq 0 -and $lpT -eq ($lpS - $minL) -and $minL -eq 1000))
$fp = CQRaw $script:FACTORY "getPair(address,address)(address)" @($st.token, $script:WBNB)
$fu = CQRaw $script:FACTORY "getPair(address,address)(address)" @($st.token, $USDT)
$fb2 = CQRaw $script:FACTORY "getPair(address,address)(address)" @($st.token, $BUSD)
Log-Step "F7.1" "Step 7: one pool only; stored pair == factory pair" "factory.getPair(DMN, WBNB) == token.uniswapV2Pair; no DMN/USDT or DMN/BUSD pair" "stored=$($st.pair), factory=$fp; USDT pair=$fu, BUSD pair=$fb2" "-" $(V ("$fp".ToLower() -eq "$($st.pair)".ToLower() -and "$fu" -eq $script:ZERO -and "$fb2" -eq $script:ZERO))
$inv8 = Fee-Inventory
$expInv = [System.Numerics.BigInteger]::Divide($gross * $liqF, 1000)
Log-Step "F8.1" "Step 8: reserves non-zero -> automation live" "both reserves > 0; the liquidity transfer was taxed: inventory == gross x 3% (plus at most 0.01% reflection)" "DMN=$(FmtB $res[0]), WBNB=$(FmtT $res[1]); inventory=$inv8 ($(FmtB $inv8)), 3% of gross=$expInv; threshold minimumTokensBeforeSwap=$(FmtB (CQ $st.token 'minimumTokensBeforeSwap()(uint256)'))" "-" $(V ($res[0] -gt 0 -and $res[1] -gt 0 -and $inv8 -ge $expInv -and (($inv8 - $expInv) * 10000) -le $expInv))
$st = S
$st | Add-Member -NotePropertyName liqBnbWei -NotePropertyValue "$bnbWei" -Force
$st | Add-Member -NotePropertyName liqGross -NotePropertyValue "$gross" -Force
$st | Add-Member -NotePropertyName liqNet -NotePropertyValue "$($res[0])" -Force
$st | Add-Member -NotePropertyName openPrice -NotePropertyValue "$open" -Force
$st | Add-Member -NotePropertyName dmxPrice -NotePropertyValue "$price" -Force
Save-State $st

# =============================================================================
# Step 9: a small test buy, then a test sell -- fee exactly 4%
# =============================================================================
Log-Scenario "F9-F10 (run $runLabel)" "Step 9: the test swap pays exactly 4%; step 10: the first poke"
$minSwap = CQ $st.token "minimumTokensBeforeSwap()(uint256)"
$buyWei = $MILLE
$pb0 = CQ $st.token "balanceOf(address)(uint256)" @($st.pair); $ob0 = CQ $st.token "balanceOf(address)(uint256)" @($script:OWNER)
$hBy = Send "owner" $script:ROUTER "swapExactETHForTokensSupportingFeeOnTransferTokens(uint256,address[],address,uint256)" @("0", "[$($script:WBNB),$($st.token)]", $script:OWNER, $deadline) -value "$buyWei" -step "9 buy"
$pb1 = CQ $st.token "balanceOf(address)(uint256)" @($st.pair); $ob1 = CQ $st.token "balanceOf(address)(uint256)" @($script:OWNER)
$out = $pb0 - $pb1; $got = $ob1 - $ob0
$e96 = NetOfGross $out $tax $liqF   # the token floors the 1% and the 3% separately
Log-Step "F9.1" "The owner buys with 0.001 BNB through the real router (it holds no DMN after 5b: the test sell needs a buy first)" "the owner receives the net of what left the pair -- amount - floor(1%) - floor(3%) -- plus its own reflection share (< 0.01%)" "left the pair=$out ($(FmtB $out)); owner received=$got; net (96%, floors per fee)=$e96 (+$($got - $e96) wei); gas=$($hBy.gasUsed)" $hBy.hash $(V ($got -ge $e96 -and (($got - $e96) * 10000) -le $e96))
$sell = [System.Numerics.BigInteger]::Divide($got, 2)
$inv9a = Fee-Inventory
$hAp = Send "owner" $st.token "approve(address,uint256)" @($script:ROUTER, "$sell") -step "9 sell"
$ob2 = Bal $script:OWNER; $pb2 = CQ $st.token "balanceOf(address)(uint256)" @($st.pair)
$hSl = Send "owner" $script:ROUTER "swapExactTokensForETHSupportingFeeOnTransferTokens(uint256,uint256,address[],address,uint256)" @("$sell", "0", "[$($st.token),$($script:WBNB)]", $script:OWNER, $deadline) -step "9 sell"
$ob3 = Bal $script:OWNER; $pb3 = CQ $st.token "balanceOf(address)(uint256)" @($st.pair)
$inv9b = Fee-Inventory
$pairGot = $pb3 - $pb2
$s96 = NetOfGross $sell $tax $liqF; $s95 = [System.Numerics.BigInteger]::Divide($sell * 95, 100)
$proceeds = $ob3 - $ob2 + $hSl.cost
Log-Step "F9.2" "Step 9: the owner sells half of it through the real router" "the pair (balanceOf delta, reward-excluded) receives EXACTLY the net: amount - floor(1%) - floor(3%), i.e. 96% up to the two floors -- fee 4%, not the historical 5%; inventory grows by 3% (+ reflection); no conversion on a router sell (#1): contract BNB 0, Timelock BNB 0" "sold=$sell; pair received=$pairGot (net=$s96, floor(96%)=$([System.Numerics.BigInteger]::Divide($sell * 96, 100)), 95% would be $s95); inventory +$($inv9b - $inv9a); BNB back to the owner=$(FmtT $proceeds) ($proceeds wei); contract BNB=$(Bal $st.token), Timelock BNB=$(Bal $st.timelock); gas=$($hSl.gasUsed)" "$($hAp.hash) / $($hSl.hash)" $(V ($pairGot -eq $s96 -and $inv9b -gt $inv9a -and (Bal $st.token) -eq 0 -and (Bal $st.timelock) -eq 0))
$st = S
$st | Add-Member -NotePropertyName testBuyWei -NotePropertyValue "$buyWei" -Force
$st | Add-Member -NotePropertyName testSellProceeds -NotePropertyValue "$proceeds" -Force
Save-State $st

# ---- Step 10: the first poke --------------------------------------------------
$inv10 = Fee-Inventory
$stk0 = Bal $st.staking; $ct0 = Bal $st.token; $tl0 = Bal $st.timelock; $r10 = Pair-Reserves
$hP = Send "owner" $st.token "transfer(address,uint256)" @($st.pair, "1") -step "10 poke"
$inv10b = Fee-Inventory; $stk1 = Bal $st.staking; $ct1 = Bal $st.token; $tl1 = Bal $st.timelock
if ($inv10 -lt $minSwap) {
  $missing = $minSwap - $inv10
  $vol = CeilDiv ($missing * 1000) $liqF
  Log-Step "F10.1" "Step 10: the first poke (1 wei DMN owner -> pair), share 1000" "zero BNB to the Timelock. Recorded: is the inventory above the threshold yet?" "inventory=$(FmtB $inv10) < threshold $(FmtB $minSwap): NOTHING converts (inventory after=$(FmtB $inv10b)); staking +$($stk1 - $stk0), contract +$($ct1 - $ct0), TIMELOCK +$($tl1 - $tl0) wei; the first conversion needs $(FmtB $missing) more inventory = about $(FmtB $vol) of further taxed volume; gas=$($hP.gasUsed)" $hP.hash $(if (($tl1 - $tl0) -eq 0 -and $inv10b -ge $inv10) { "FINDING" } else { "DEVIATION" })
  Log-Note "On launch day the first poke is a no-op: the 5b liquidity transfer arms only 3% of ~5B = ~0.15B of inventory, under the 0.2B threshold. The Timelock-receives-nothing property is proven again at the first REAL conversion, which happens later (F10.2 below, after the window opens)."
} else {
  $ethR = ($stk1 - $stk0) + ($ct1 - $ct0) + ($tl1 - $tl0)
  $mEth = [System.Numerics.BigInteger]::Divide($ethR * $mktF, $liqF)
  Log-Step "F10.1" "Step 10: the first poke, share 1000" "one threshold chunk converts; the marketing share to staking, the buyback share kept, ZERO to the Timelock" "consumed=$(FmtB ($inv10 - $inv10b)); received=$(FmtT $ethR): staking +$(FmtT ($stk1 - $stk0)) (exp $(FmtT $mEth)), contract +$(FmtT ($ct1 - $ct0)), TIMELOCK +$($tl1 - $tl0)" $hP.hash $(V (($tl1 - $tl0) -eq 0 -and ($stk1 - $stk0) -eq $mEth))
}

# =============================================================================
# Steps 11a and 11b on the REAL DMX
# =============================================================================
Log-Scenario "F11 (run $runLabel)" "11a setMaxTxAmount(full supply), then 11b excludeFromFee(TIMELOCK) -- on the REAL DMX, same session, nothing between"
$hA_ = $script:AddrBook.holderA
$big = BW "10.00"
$hAA = Send "holderA" $script:DMX "approve(address,uint256)" @($st.migration, "$big") -step "11 check"
$revA = Expect-Revert "holderA" $st.migration "claim(uint256)" @("$big") -match "Transfer amount exceeds the maxTxAmount."
Log-Step "F11.0" "BEFORE 11a: holder A (real, > 10 B) approves and claims 10.00 B" "REVERTS with the real DMX cap message (the cap is checked before any fee logic)" "approve mined (holder A's own gas); claim: $revA" $hAA.hash $(V ("$revA" -match "reverted with Transfer amount exceeds the maxTxAmount"))
$FULL = BI "1000000000000000000000000000000"
$revO = Expect-Revert "holderA" $script:DMX "setMaxTxAmount(uint256)" @("$FULL") -match "Ownable: caller is not the owner"
$h11a = Send "owner" $script:DMX "setMaxTxAmount(uint256)" @("$FULL") -step "11a"
$cap2 = CQ $script:DMX "_maxTxAmount()(uint256)"
Log-Step "F11a" "Step 11a: setMaxTxAmount(1000000000000 x 1e18) -- a non-owner first (eth_call), then the owner" "non-owner refused by Ownable; the owner's call mined; _maxTxAmount == the full supply == totalSupply()" "non-owner: $revO; _maxTxAmount $(FmtB $cap) -> $(FmtB $cap2) (totalSupply $(FmtB (CQ $script:DMX 'totalSupply()(uint256)'))); logs emitted by the call=$($h11a.logs); gas=$($h11a.gasUsed); block $($h11a.block)" $h11a.hash $(V ("$revO" -match "reverted with Ownable" -and $cap2 -eq $FULL))
$h11b = Send "owner" $script:DMX "excludeFromFee(address)" @($st.timelock) -step "11b"
$exT = CQRaw $script:DMX "isExcludedFromFee(address)(bool)" @($st.timelock); $exM = CQRaw $script:DMX "isExcludedFromFee(address)(bool)" @($st.migration)
Log-Step "F11b" "Step 11b, LAST: excludeFromFee(TIMELOCK) -- the treasury, not the Migration; the window opens" "isExcludedFromFee(timelock) true, (migration) false; mined right after 11a with nothing in between" "timelock=$exT, migration=$exM; logs emitted=$($h11b.logs); 11a block $($h11a.block) -> 11b block $($h11b.block); gas=$($h11b.gasUsed)" $h11b.hash $(V ("$exT" -eq "true" -and "$exM" -eq "false" -and ($h11b.block - $h11a.block) -eq 1))
if ($h11a.logs -eq 0 -or $h11b.logs -eq 0) {
  Log-Step "F11.x" "Events: what an observer sees of 11a and 11b" "recorded against the mock (CampaignOldDaimon emits MaxTxAmountUpdated on setMaxTxAmount)" "the REAL DMX emitted $($h11a.logs) log(s) on setMaxTxAmount and $($h11b.logs) on excludeFromFee: both are silent -- only the calldata and a storage read show them" "-" "FINDING"
}

# =============================================================================
# After 11b: two real third-party claims
# =============================================================================
Log-Scenario "F12 (run $runLabel)" "After 11b: real third-party holders claim through the open window"
$tO0 = CQ $script:DMX "balanceOf(address)(uint256)" @($st.timelock); $aO0 = CQ $script:DMX "balanceOf(address)(uint256)" @($hA_); $aN0 = CQ $st.token "balanceOf(address)(uint256)" @($hA_)
$hCA = Send "holderA" $st.migration "claim(uint256)" @("$big") -step "12 claim A"
$tO1 = CQ $script:DMX "balanceOf(address)(uint256)" @($st.timelock); $aO1 = CQ $script:DMX "balanceOf(address)(uint256)" @($hA_); $aN1 = CQ $st.token "balanceOf(address)(uint256)" @($hA_)
$migA = CQ $st.migration "migratedAmount(address)(uint256)" @($hA_)
Log-Step "F12.1" "Holder A (real, > 10 B, not the owner, not exempt) repeats the SAME 10.00 B claim (the F11.0 approve still stands)" "passes 1:1, no fee: Timelock DMX +10.00 B exactly, holder A DMX -10.00 B exactly, holder A DMN +10.00 B exactly, migratedAmount 10.00 B" "Timelock DMX +$($tO1 - $tO0), holder A DMX -$($aO0 - $aO1), holder A DMN +$($aN1 - $aN0), migratedAmount=$migA (10.00 B = $big); gas=$($hCA.gasUsed)" $hCA.hash $(V (($tO1 - $tO0) -eq $big -and ($aO0 - $aO1) -eq $big -and ($aN1 - $aN0) -eq $big -and $migA -eq $big))
$small = BW "1.00"
$tO2 = CQ $script:DMX "balanceOf(address)(uint256)" @($st.timelock); $bO2 = CQ $script:DMX "balanceOf(address)(uint256)" @($hB); $bN2 = CQ $st.token "balanceOf(address)(uint256)" @($hB)
$hCB = Send "holderB" $st.migration "claim(uint256)" @("$small") -step "12 claim B"
$tO3 = CQ $script:DMX "balanceOf(address)(uint256)" @($st.timelock); $bO3 = CQ $script:DMX "balanceOf(address)(uint256)" @($hB); $bN3 = CQ $st.token "balanceOf(address)(uint256)" @($hB)
Log-Step "F12.2" "Holder B (real, below the old cap) claims 1.00 B with the approve of F5a.1" "exact 1:1 on every leg" "Timelock DMX +$($tO3 - $tO2), holder B DMX -$($bO2 - $bO3), holder B DMN +$($bN3 - $bN2); gas=$($hCB.gasUsed)" $hCB.hash $(V (($tO3 - $tO2) -eq $small -and ($bO2 - $bO3) -eq $small -and ($bN3 - $bN2) -eq $small))
$tot = CQ $st.migration "totalMigrated()(uint256)"
Log-Step "F12.3" "The treasury (= the Timelock) after the day's claims" "DMX held == totalMigrated (owner 5a + holder A + holder B)" "Timelock DMX=$tO3 ($(FmtB $tO3)); totalMigrated=$tot ($(FmtB $tot)); owner $(FmtB $gross) + A $(FmtB $big) + B $(FmtB $small)" "-" $(V ($tO3 -eq $tot -and $tot -eq ($gross + $big + $small)))
# The real DMX is a reflection token and the Timelock is not reward-excluded
# on it: any TAXED DMX transfer anywhere now credits the treasury a share.
$tRw = CQRaw $script:DMX "isExcludedFromReward(address)(bool)" @($st.timelock)
$hX = Send "holderA" $script:DMX "transfer(address,uint256)" @($hB, "$(BW '0.01')") -step "12 reflection"
$tO4 = CQ $script:DMX "balanceOf(address)(uint256)" @($st.timelock)
Log-Step "F12.4" "Behaviour the mock does not have: a taxed DMX transfer between two other holders (holder A -> holder B, 0.01 B) after the claims" "recorded: does the treasury's DMX move without any claim?" "Timelock isExcludedFromReward on DMX=$tRw; Timelock DMX $tO3 -> $tO4 (+$($tO4 - $tO3) wei) while totalMigrated stays $tot" $hX.hash $(if ($tO4 -gt $tO3) { "FINDING" } else { "NOTE" })

# ---- Step 10 again, now meaningful: the first REAL conversion ---------------
$invC = Fee-Inventory
if ($invC -lt $minSwap) {
  $needVol = CeilDiv (($minSwap - $invC) * 1000) $liqF
  $cent = BW "0.01"
  $armAmt = [System.Numerics.BigInteger]::Divide($needVol + $cent, $cent) * $cent
  $hArm = Send "holderA" $st.token "transfer(address,uint256)" @($hB, "$armAmt") -step "10 again arm"
  $invC = Fee-Inventory
  Log-Step "F10.2a" "Arming the first conversion with ordinary volume: holder A sends DMN to holder B (a taxed transfer, under the 5B maxTx)" "inventory >= threshold afterwards" "sent=$(FmtB $armAmt); inventory=$(FmtB $invC) vs threshold $(FmtB $minSwap)" $hArm.hash $(V ($invC -ge $minSwap))
}
$rP = Pair-Reserves; $pP = Price-WeiPerToken $rP[0] $rP[1]
$stk0 = Bal $st.staking; $ct0 = Bal $st.token; $tl0 = Bal $st.timelock
$hP2 = Send "holderB" $st.token "transfer(address,uint256)" @($st.pair, "1") -step "10 again poke"
$invD = Fee-Inventory; $rQ = Pair-Reserves; $pQ = Price-WeiPerToken $rQ[0] $rQ[1]
$stk1 = Bal $st.staking; $ct1 = Bal $st.token; $tl1 = Bal $st.timelock
$consumed = $invC - $invD
$ethR = ($stk1 - $stk0) + ($ct1 - $ct0) + ($tl1 - $tl0)
$mEth = [System.Numerics.BigInteger]::Divide($ethR * $mktF, $liqF)
Log-Step "F10.2" "The first REAL conversion on the REAL router: holder B pokes (1 wei to the pair), share 1000" "one threshold chunk sold; 20/30 of the BNB to staking, 10/30 kept for buyback, ZERO to the Timelock" "consumed=$(FmtB $consumed) (threshold $(FmtB $minSwap)); received=$(FmtT $ethR) BNB: staking +$(FmtT ($stk1 - $stk0)) (exp $(FmtT $mEth)), contract +$(FmtT ($ct1 - $ct0)), TIMELOCK +$($tl1 - $tl0) wei; gas=$($hP2.gasUsed)" $hP2.hash $(V ($consumed -eq $minSwap -and ($tl1 - $tl0) -eq 0 -and ($stk1 - $stk0) -eq $mEth -and ($ct1 - $ct0) -eq ($ethR - $mEth) -and $ethR -gt 0))
Log-Step "F10.3" "THE NUMBER on the real pool: the chunk against the DMN reserve, and the price move" "recorded" "chunk $(FmtB $consumed) vs DMN reserve $(FmtB $rP[0]) = $(Pct $consumed $rP[0]) %; BNB drawn $(FmtT ($rP[1] - $rQ[1])) of $(FmtT $rP[1]) = $(Pct ($rP[1] - $rQ[1]) $rP[1]) %; price $pP -> $pQ wei/token, move -$(Pct ($pP - $pQ) $pP) %" "-" "NOTE"

# ---- The end state -------------------------------------------------------------
$tlB = Bal $st.timelock; $tlD = CQ $st.token "balanceOf(address)(uint256)" @($st.timelock); $tlLp = CQ $st.pair "balanceOf(address)(uint256)" @($st.timelock); $lpS2 = CQ $st.pair "totalSupply()(uint256)"
Log-Step "F13.1" "The Timelock at the end of the day" "BNB 0 and DMN 0 (share 1000: nothing from the token), every LP token, the claimed DMX" "BNB=$tlB, DMN=$tlD, LP=$tlLp of $lpS2, DMX=$(FmtB (CQ $script:DMX 'balanceOf(address)(uint256)' @($st.timelock)))" "-" $(V ($tlB -eq 0 -and $tlD -eq 0 -and $tlLp -eq ($lpS2 - 1000)))
Finalize "complete through 11b and the post-window claims"
Write-Output "LAUNCH DAY COMPLETE run=$runLabel"
