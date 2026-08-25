# A1-2p - The full deploy, now in two phases: expiry identical by construction.
. .\script\campaign\lib.ps1
Log-Scenario "A1-2p" "Two-phase deploy on a live node: the A1.8 skew is gone, exactly"
Start-CampaignNode
$old = Deploy-OldToken
$st = Run-MainDeploy $old -DerivedTreasury

Log-Step "A1-2p.1" "Both phases broadcast against the live node" "five contracts up, addresses recorded by the scripts own state file" "token=$($st.token), timelock=$($st.timelock), governor=$($st.governor)" $(if ($st.token -and $st.timelock -and $st.governor) { "PASS" } else { "DEVIATION" })

# THE check: the three expiry values, read from mined state, must be EXACTLY
# equal now. In Level 1 (A1.8) the same read showed 1882278209 vs 1882278205.
$eT = CQ $st.token    "guardianExpiry()(uint256)"
$eL = CQ $st.timelock "guardianAuthorityExpiry()(uint256)"
$eG = CQ $st.governor "guardianAuthorityExpiry()(uint256)"
Log-Step "A1-2p.2" "Guardian expiry read from the three live contracts" "EXACT equality - phase 2 read the mined value and passed it verbatim" "token=$eT, timelock=$eL, governor=$eG" $(if ($eT -eq $eL -and $eT -eq $eG) { "PASS" } else { "DEVIATION" })

# Counter-proof at the calldata level, the same probe that diagnosed A1.8:
# the expiry embedded in the timelock's constructor arguments in the phase-2
# broadcast journal must equal the token's live value.
$bc = Get-Content (Join-Path $script:ROOT "broadcast\DeployPhase2.s.sol\97\run-latest.json") -Raw | ConvertFrom-Json
$tlTx = $bc.transactions | Where-Object { $_.transactionType -eq "CREATE" -and $_.contractName -eq "DaimonTimelock" }
$argExpiry = $tlTx.arguments[-1]
Log-Step "A1-2p.3" "The expiry actually embedded in the phase-2 calldata" "equals the live token value - in A1.8 this is exactly where the stale simulated value sat" "calldata argument=$argExpiry, live token=$eT" $(if ("$argExpiry" -eq "$eT") { "PASS" } else { "DEVIATION" })

$share = CQ $st.token "stakingRewardShareBps()(uint256)"
Log-Step "A1-2p.4" "Launch compliance configuration" "stakingRewardShareBps == 1000, set in phase 2" "$share" $(if ($share -eq 1000) { "PASS" } else { "DEVIATION" })

$supply = CQ $st.token "totalSupply()(uint256)"
$inMigration = CQ $st.token "balanceOf(address)(uint256)" @($st.migration)
Log-Step "A1-2p.5" "Supply placement across the phase boundary" "the entire supply in the migration, untouched by phase 2" "supply=$(FmtB $supply), in migration=$(FmtB $inMigration)" $(if ($supply -eq $inMigration -and $supply -eq (BW "1000.00")) { "PASS" } else { "DEVIATION" })

$migGov = CQRaw $st.migration "governance()(address)"
Log-Step "A1-2p.6" "The phase-1 prediction came true" "migration.governance (immutable, set in phase 1) IS the timelock deployed in phase 2" "migration.governance=$migGov, timelock=$($st.timelock)" $(if ("$migGov".ToLower() -eq "$($st.timelock)".ToLower()) { "PASS" } else { "DEVIATION" })

# Item 1 follow-up: the treasury is DERIVED (it IS the timelock), never typed.
$migTreasury = CQRaw $st.migration "treasury()(address)"
Log-Step "A1-2p.7" "The migration treasury, read live" "it IS the timelock: derived in phase 1 from the same prediction as the governance, fulfilled in phase 2" "migration.treasury=$migTreasury, timelock=$($st.timelock)" $(if ("$migTreasury".ToLower() -eq "$($st.timelock)".ToLower()) { "PASS" } else { "DEVIATION" })
$depState = Get-Content (Join-Path $script:ROOT (Join-Path "deployments" "two-phase-97.json")) -Raw | ConvertFrom-Json
Log-Step "A1-2p.8" "How the treasury value came to be" "no hand-typed input anywhere: the state file records treasuryOverridden=false" "treasuryOverridden=$($depState.treasuryOverridden), env override present=$(if ($env:TESTNET_TREASURY_OVERRIDE) { 'yes' } else { 'no' })" $(if (-not $depState.treasuryOverridden) { "PASS" } else { "DEVIATION" })
$mk = CQ $st.token "balanceOf(address)(uint256)" @($script:MARKETING)
Log-Step "A1-2p.9" "Marketing wallet after the full two-phase deploy" "zero, as always" "DMN=$mk" $(if ($mk -eq 0) { "PASS" } else { "DEVIATION" })
Stop-Anvil
Write-Output "A1-2p COMPLETE"
