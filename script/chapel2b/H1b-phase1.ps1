# H1 steps 1-2 (phase 1) -- pair not pre-existing, then DeployPhase1 with
# NO override of any kind: marketing wallet AND treasury derived from the
# same predicted Timelock. Every assert reads MINED state.
. $PSScriptRoot\lib.ps1
Load-Keystores
$st = S
if (-not $st.old) { throw "run H1a-mock.ps1 first" }
if ($st.token) { throw "phase 1 already broadcast: token=$($st.token)" }
Log-Scenario "H1 (1-2)" "Step 1: no pair pre-exists; step 2 phase 1: marketingWallet == predicted Timelock, read from mined state"

# ---- Step 1: the pair must NOT exist for the PREDICTED proxy (#25) -------
# Phase 1 creates impl (n), proxy (n+1), migration (n+2); the Timelock is
# the first create of phase 2 (n+3). All from the deployer's LIVE nonce.
$nonce = Nonce $script:AddrBook.deployer
$predictedProxy = ((cast compute-address $script:AddrBook.deployer --nonce ($nonce + 1) | Out-String).Trim() -split "\s+")[-1]
$predictedTimelockLocal = ((cast compute-address $script:AddrBook.deployer --nonce ($nonce + 3) | Out-String).Trim() -split "\s+")[-1]
$factory = CQRaw $script:ROUTER "factory()(address)"
$wbnb = CQRaw $script:ROUTER "WETH()(address)"
$prePair = CQRaw $factory "getPair(address,address)(address)" @($predictedProxy, $wbnb)
Log-Step "H1.1" "Step 1: DMN/WBNB pair on the factory for the PREDICTED proxy, BEFORE phase 1 (#25)" "getPair(predicted proxy, WBNB) == 0x0: nobody pre-created it" "deployer nonce=$nonce, predicted proxy=$predictedProxy (nonce+1), predicted timelock=$predictedTimelockLocal (nonce+3), getPair=$prePair" "-" $(if ("$prePair" -eq "0x0000000000000000000000000000000000000000") { "PASS" } else { "DEVIATION" })
if ("$prePair" -ne "0x0000000000000000000000000000000000000000") { throw "STOP: a pair pre-exists for the predicted proxy" }

# ---- Environment: the mainnet-faithful path, no override ------------------
$env:OLD_DAIMON = $st.old
$env:GUARDIAN_ADDRESS = $script:GUARDIAN
Remove-Item env:MARKETING_WALLET -ErrorAction SilentlyContinue
Remove-Item env:TESTNET_TREASURY_OVERRIDE -ErrorAction SilentlyContinue
Remove-Item env:TREASURY_ADDRESS -ErrorAction SilentlyContinue
$stateFile = Join-Path $script:ROOT (Join-Path "deployments" "two-phase-97.json")
if (Test-Path $stateFile) { Remove-Item $stateFile -Force }

# Simulation first (no broadcast): the script's own log must say both the
# treasury and the marketing wallet are "(= predicted timelock)" and no
# override is active. Only then the broadcast.
$sim = Run-ForgeScript "script/DeployPhase1.s.sol" "deployer"
$simOut = $sim[1]
$derivedLines = @(($simOut -split "`r?`n") | Where-Object { $_ -match "\(= predicted timelock\)" })
$overrideLines = @(($simOut -split "`r?`n") | Where-Object { $_ -match "override active|WARNING: marketing" })
Log-Step "H1.2a" "Phase 1 SIMULATED (no broadcast) with the environment as it will be broadcast" "exit 0; the script logs 'Migration treasury' AND 'Marketing wallet' as '(= predicted timelock)'; no override line, no marketing warning" "exit=$($sim[0]); derived lines=$($derivedLines.Count); override/warning lines=$($overrideLines.Count); MARKETING_WALLET in env=$(if ($env:MARKETING_WALLET) { 'yes' } else { 'no' }); TESTNET_TREASURY_OVERRIDE in env=$(if ($env:TESTNET_TREASURY_OVERRIDE) { 'yes' } else { 'no' })" "-" $(if ($sim[0] -eq 0 -and $derivedLines.Count -eq 2 -and $overrideLines.Count -eq 0) { "PASS" } else { "DEVIATION" })
if (-not ($sim[0] -eq 0 -and $derivedLines.Count -eq 2 -and $overrideLines.Count -eq 0)) { Log-Block "Simulation output, verbatim:" $simOut; throw "STOP: the simulation did not show the derived path" }

# ---- Step 2, phase 1: the broadcast ---------------------------------------
$r1 = Run-ForgeScript "script/DeployPhase1.s.sol" "deployer" -Broadcast
if ($r1[0] -ne 0) { Log-Block "Phase 1 output (FAILED), verbatim:" $r1[1]; throw "PHASE 1 FAILED:`n$($r1[1])" }
if (-not (Test-Path $stateFile)) { throw "phase 1 wrote no state file" }
$dep = Get-Content $stateFile -Raw | ConvertFrom-Json
$tokenCode = Code-Len $dep.token
$migCode = Code-Len $dep.migration
$nonceAfter = Nonce $script:AddrBook.deployer
Log-Step "H1.2" "Step 2, phase 1 broadcast: impl + proxy + migration, no env override" "code at both; proxy == the predicted proxy; state file: treasuryOverridden=false AND marketingWalletOverridden=false; deployer nonce == expectedPhase2Nonce" "token=$($dep.token) (code $tokenCode ch), migration=$($dep.migration) (code $migCode ch), proxy-as-predicted=$("$($dep.token)".ToLower() -eq "$predictedProxy".ToLower()); treasuryOverridden=$($dep.treasuryOverridden), marketingWalletOverridden=$($dep.marketingWalletOverridden); nonce now=$nonceAfter, expectedPhase2Nonce=$($dep.expectedPhase2Nonce)" "journal broadcast/DeployPhase1.s.sol/97" $(if ($tokenCode -gt 100 -and $migCode -gt 100 -and "$($dep.token)".ToLower() -eq "$predictedProxy".ToLower() -and (-not $dep.treasuryOverridden) -and (-not $dep.marketingWalletOverridden) -and "$nonceAfter" -eq "$($dep.expectedPhase2Nonce)") { "PASS" } else { "DEVIATION" })

# ---- The three predictions, from MINED state -----------------------------
$mk = CQRaw $dep.token "marketingWallet()(address)"
$migGov = CQRaw $dep.migration "governance()(address)"
$migTre = CQRaw $dep.migration "treasury()(address)"
$pt = "$($dep.predictedTimelock)".ToLower()
$okPred = ("$mk".ToLower() -eq $pt -and "$migGov".ToLower() -eq $pt -and "$migTre".ToLower() -eq $pt -and "$predictedTimelockLocal".ToLower() -eq $pt)
Log-Step "H1.3" "H0.1 on a public chain: token.marketingWallet(), migration.treasury(), migration.governance() from MINED state" "all three == the predicted Timelock, which also == this runner's own nonce+3 computation (never typed anywhere)" "token.marketingWallet=$mk, migration.treasury=$migTre, migration.governance=$migGov, state predictedTimelock=$($dep.predictedTimelock), local nonce+3=$predictedTimelockLocal" "-" $(if ($okPred) { "PASS" } else { "DEVIATION" })

$supplyInMig = CQ $dep.token "balanceOf(address)(uint256)" @($dep.migration)
$migEx = CQRaw $dep.token "isExcludedFromFee(address)(bool)" @($dep.migration)
$fees0 = "$(CQ $dep.token 'taxFee()(uint256)')/$(CQ $dep.token 'buybackFee()(uint256)')/$(CQ $dep.token 'marketingFee()(uint256)')"
Log-Step "H1.3b" "Supply placement and the fee model BETWEEN the phases" "the full 1e30 in the Migration (fee-exempt); fees still the initialize() historical 10/20/20 -- phase 2 sets 10/10/20" "in migration=$(FmtB $supplyInMig) ($supplyInMig wei), migration fee-exempt=$migEx, fees now=$fees0" "-" $(if ("$supplyInMig" -eq "1000000000000000000000000000000" -and "$migEx" -eq "true" -and $fees0 -eq "10/20/20") { "PASS" } else { "DEVIATION" })

$tail = (($r1[1] -split "`r?`n") | Where-Object { $_ -match "PHASE 1 complete|DaimonV2 \(proxy\)|DaimonMigration:|Timelock \(predicted\)|Migration treasury:|Marketing wallet:|State file:" }) -join "`n"
Log-Block "Phase 1 console, the completion block verbatim:" $tail
Log-Block "State file after phase 1, verbatim:" (Get-Content $stateFile -Raw) "json"
$st | Add-Member -NotePropertyName token -NotePropertyValue $dep.token -Force
$st | Add-Member -NotePropertyName impl -NotePropertyValue $dep.tokenImplementation -Force
$st | Add-Member -NotePropertyName migration -NotePropertyValue $dep.migration -Force
$st | Add-Member -NotePropertyName predictedTimelock -NotePropertyValue $dep.predictedTimelock -Force
$st | Add-Member -NotePropertyName expectedPhase2Nonce -NotePropertyValue "$($dep.expectedPhase2Nonce)" -Force
Save-State $st
if (-not $okPred) { throw "STOP: the predicted Timelock does not match on mined state" }
Log-Note "From this row until phase 2 the deployer signs NOTHING: the Timelock must land at nonce $($dep.expectedPhase2Nonce)."
Write-Output "H1b COMPLETE token=$($dep.token) -- run H1c-phase2.ps1 NOW, nothing from the deployer in between"
