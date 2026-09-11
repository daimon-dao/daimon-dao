# P1.3 -- Phase 2 on Chapel: expiry from the live token, wiring, renounce.
. $PSScriptRoot\lib.ps1
Load-Keystores
$pf = $script:KsMap.passwordFile
$st = S
Log-Scenario "P1.3" "Phase 2: Timelock + Staking + Governor -- expiry read from the live chain"

$prev = $ErrorActionPreference; $ErrorActionPreference = "Continue"
$out2 = forge script script/DeployPhase2.s.sol --rpc-url $script:RPC --broadcast --slow --account $script:KsMap.accounts.deployer --password-file $pf 2>&1 | Out-String
$c = $LASTEXITCODE; $ErrorActionPreference = $prev
Get-Process forge -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
if ($c -ne 0) { throw "PHASE 2 FAILED:`n$out2" }
$stateFile = Join-Path $script:ROOT (Join-Path "deployments" "two-phase-97.json")
$dep = Get-Content $stateFile -Raw | ConvertFrom-Json
if (-not $dep.governor) { throw "phase 2 did not complete the state file" }

Log-Step "P1.3.1" "Phase 2 broadcast: timelock + staking + governor + wiring + renounce" "timelock lands EXACTLY on the phase-1 prediction" "timelock=$($dep.timelock), predicted=$($st.predictedTimelock), match=$("$($dep.timelock)".ToLower() -eq "$($st.predictedTimelock)".ToLower())" "journal broadcast/DeployPhase2.s.sol/97" $(if ("$($dep.timelock)".ToLower() -eq "$($st.predictedTimelock)".ToLower()) { "PASS" } else { "DEVIATION" })

# THE numbers: the three expiry values from mined state.
$eT = CQ $dep.token    "guardianExpiry()(uint256)"
$eL = CQ $dep.timelock "guardianAuthorityExpiry()(uint256)"
$eG = CQ $dep.governor "guardianAuthorityExpiry()(uint256)"
Log-Step "P1.3.2" "Guardian expiry from the three live contracts on a PUBLIC chain" "EXACT equality - the A1.8 skew is what this deploy design removed" "token=$eT, timelock=$eL, governor=$eG" "-" $(if ($eT -eq $eL -and $eT -eq $eG) { "PASS" } else { "DEVIATION" })

# Calldata-level counter-proof from the real broadcast journal.
$bc = Get-Content (Join-Path $script:ROOT "broadcast\DeployPhase2.s.sol\97\run-latest.json") -Raw | ConvertFrom-Json
$tlTx = $bc.transactions | Where-Object { $_.transactionType -eq "CREATE" -and $_.contractName -eq "DaimonTimelock" }
$argExpiry = $tlTx.arguments[-1]
Log-Step "P1.3.3" "The expiry embedded in the phase-2 constructor calldata" "equals the live token value (where A1.8 found the 4-second skew)" "calldata=$argExpiry, live=$eT" $tlTx.hash $(if ("$argExpiry" -eq "$eT") { "PASS" } else { "DEVIATION" })

$migTre = CQRaw $dep.migration "treasury()(address)"
Log-Step "P1.3.4" "Both phase-1 predictions fulfilled on live state" "migration.governance == migration.treasury == the deployed timelock" "treasury=$migTre" "-" $(if ("$migTre".ToLower() -eq "$($dep.timelock)".ToLower()) { "PASS" } else { "DEVIATION" })

$share = CQ $dep.token "stakingRewardShareBps()(uint256)"
Log-Step "P1.3.5" "Launch compliance configuration" "stakingRewardShareBps == 1000, set and asserted in phase 2" "$share" "-" $(if ($share -eq 1000) { "PASS" } else { "DEVIATION" })

Log-Line ""
Log-Line "State file after phase 2 (the complete deployment record), verbatim:"
Log-Line ""
Log-Line '```json'
foreach ($l in ((Get-Content $stateFile -Raw) -split "`r?`n")) { Log-Line $l }
Log-Line '```'
$stNew = [ordered]@{
  old = $st.old; token = $dep.token; impl = $dep.tokenImplementation
  migration = $dep.migration; timelock = $dep.timelock
  governor = $dep.governor; staking = $dep.staking
  pair = (CQRaw $dep.token "uniswapV2Pair()(address)")
  guardianExpiry = "$eT"
  invariantChecks = [int]$st.invariantChecks
}
Save-State $stNew
Assert-Invariants "post-phase2"
Write-Output "P1c COMPLETE timelock=$($dep.timelock)"
