# P1.2 -- Phase 1 on Chapel: Migration + token, launch order, derived treasury.
. $PSScriptRoot\lib.ps1
Load-Keystores
$pf = $script:KsMap.passwordFile
$st = S
Log-Scenario "P1.2" "Phase 1: Migration + token (predicted Timelock recorded; treasury derived)"

# #25 pre-check: the DMN/WBNB pair must not exist before the deploy. The
# proxy address is predictable from the deployer's live nonce.
$nonce = [int](cast nonce $script:AddrBook.deployer --rpc-url $script:RPC)
$predictedProxy = (cast compute-address $script:AddrBook.deployer --nonce ($nonce + 1) --rpc-url $script:RPC 2>$null | Out-String).Trim() -replace "^Computed Address: ",""
$router = "0xD99D1c33F9fC3444f8101754aBC46c52416550D1"
$factory = CQRaw $router "factory()(address)"
$wbnb = CQRaw $router "WETH()(address)"
$pairPre = CQRaw $factory "getPair(address,address)(address)" @($predictedProxy, $wbnb)
Log-Step "P1.2.1" "#25 preflight: pair for the PREDICTED proxy on the factory" "zero address - nobody pre-created it" "predictedProxy=$predictedProxy (nonce $($nonce+1)), getPair=$pairPre" "-" $(if ($pairPre -eq "0x0000000000000000000000000000000000000000") { "PASS" } else { "DEVIATION" })

# Phase 1, the real script, derived treasury (NO override), real roles.
$env:OLD_DAIMON = $st.old
$env:GUARDIAN_ADDRESS = $script:AddrBook.guardian
$env:MARKETING_WALLET = $script:MARKETING
Remove-Item env:TESTNET_TREASURY_OVERRIDE -ErrorAction SilentlyContinue
Remove-Item env:TREASURY_ADDRESS -ErrorAction SilentlyContinue
$stateFile = Join-Path $script:ROOT (Join-Path "deployments" "two-phase-97.json")
if (Test-Path $stateFile) { Remove-Item $stateFile -Force }

$prev = $ErrorActionPreference; $ErrorActionPreference = "Continue"
$out1 = forge script script/DeployPhase1.s.sol --rpc-url $script:RPC --broadcast --slow --account $script:KsMap.accounts.deployer --password-file $pf 2>&1 | Out-String
$c = $LASTEXITCODE; $ErrorActionPreference = $prev
Get-Process forge -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
if ($c -ne 0) { throw "PHASE 1 FAILED:`n$out1" }
if (-not (Test-Path $stateFile)) { throw "phase 1 wrote no state file" }
$dep = Get-Content $stateFile -Raw | ConvertFrom-Json

$tokenCode = (cast code $dep.token --rpc-url $script:RPC | Out-String).Trim().Length
$migCode = (cast code $dep.migration --rpc-url $script:RPC | Out-String).Trim().Length
Log-Step "P1.2.2" "Phase 1 broadcast: impl + proxy + migration" "code at both addresses, proxy at the predicted address" "token=$($dep.token) (code $tokenCode ch), migration=$($dep.migration) (code $migCode ch), proxy-as-predicted=$("$($dep.token)".ToLower() -eq "$predictedProxy".ToLower())" "journal broadcast/DeployPhase1.s.sol/97" $(if ($tokenCode -gt 100 -and $migCode -gt 100) { "PASS" } else { "DEVIATION" })

$supplyInMig = CQ $dep.token "balanceOf(address)(uint256)" @($dep.migration)
Log-Step "P1.2.3" "Supply placement" "the full 1e30 in the Migration, never through an EOA" "$(FmtB $supplyInMig) ($supplyInMig wei)" "-" $(if ("$supplyInMig" -eq "1000000000000000000000000000000") { "PASS" } else { "DEVIATION" })

$migGov = CQRaw $dep.migration "governance()(address)"
$migTre = CQRaw $dep.migration "treasury()(address)"
Log-Step "P1.2.4" "The two predictions, from live chain state" "governance AND treasury both = the predicted timelock (derived, never typed)" "predictedTimelock=$($dep.predictedTimelock), migration.governance=$migGov, migration.treasury=$migTre, overridden=$($dep.treasuryOverridden)" "-" $(if ("$migGov".ToLower() -eq "$($dep.predictedTimelock)".ToLower() -and "$migTre".ToLower() -eq "$($dep.predictedTimelock)".ToLower() -and (-not $dep.treasuryOverridden)) { "PASS" } else { "DEVIATION" })

# Preserve the state file contents verbatim in the log (the file itself is
# gitignored) and carry the addresses into the harness state.
Log-Line ""
Log-Line "State file after phase 1, verbatim:"
Log-Line ""
Log-Line '```json'
foreach ($l in ((Get-Content $stateFile -Raw) -split "`r?`n")) { Log-Line $l }
Log-Line '```'
$stNew = [ordered]@{
  old = $st.old; token = $dep.token; impl = $dep.tokenImplementation
  migration = $dep.migration; predictedTimelock = $dep.predictedTimelock
  invariantChecks = [int]$st.invariantChecks
}
Save-State $stNew
Assert-Invariants "post-phase1"
Write-Output "P1b COMPLETE token=$($dep.token)"
