# Post-broadcast verification -- the authoritative launch gate.
#
# Why this exists (Level 1 campaign, deviation A1.8): every assert inside a
# forge script runs in the SIMULATION context and proves nothing about the
# state that actually got mined. This runner reads only mined state, through
# ordinary eth_call against a normal RPC -- no simulation context anywhere.
#
# Why cast and not a read-only forge script:
#   1. zero EVM simulation: each value below is one eth_call on the live node;
#   2. a require-cascade aborts at the first failure and hides the rest --
#      a verification wants EVERY invariant's status on record;
#   3. same tooling the Level 1 campaign validated across 31 scenarios, and
#      the same tool a human uses to spot-check any single line by hand.
#
# Usage:
#   powershell -File script/verify-deploy.ps1 -Rpc <url> [-StateFile <path>]
# StateFile defaults to deployments/two-phase-<chainid>.json, with the chain
# id read from the RPC itself. Exit code = number of failed checks.
param(
  [Parameter(Mandatory = $true)][string]$Rpc,
  [string]$StateFile = ""
)
$ErrorActionPreference = "Stop"

function CastCall { param([string]$to, [string]$sig, [string[]]$callArgs = @())
  $prev = $ErrorActionPreference; $ErrorActionPreference = "Continue"
  $r = (cast call $to $sig @callArgs --rpc-url $Rpc 2>&1 | Out-String)
  $code = $LASTEXITCODE; $ErrorActionPreference = $prev
  if ($code -ne 0) {
    # A verification must REPORT a broken read, not die on it: a codeless
    # address or a reverting getter becomes a failing row in the table.
    return "READ-ERROR($(($r -replace '\s+',' ').Trim().Substring(0, [Math]::Min(60, $r.Trim().Length)))...)"
  }
  # First whitespace-token of the first non-empty line (cast appends
  # scientific-notation hints like "[1.8e9]" after large numbers).
  foreach ($line in ($r -split "`n")) {
    $t = $line.Trim()
    if ($t -ne "") { return ($t -split "\s+")[0] }
  }
  return "READ-ERROR(empty)"
}

$script:results = @()
$script:failures = 0
function Check { param([string]$name, $got, $expected)
  $ok = ("$got".ToLower() -eq "$expected".ToLower())
  if (-not $ok) { $script:failures++ }
  $script:results += [pscustomobject]@{
    check    = $name
    expected = "$expected"
    observed = "$got"
    verdict  = $(if ($ok) { "PASS" } else { "FAIL" })
  }
}

# ---- Resolve the state file from the chain the RPC actually serves ----
$prevEap = $ErrorActionPreference; $ErrorActionPreference = "Continue"
$chainId = (cast chain-id --rpc-url $Rpc 2>&1 | Out-String).Trim()
$ErrorActionPreference = $prevEap
if (-not ($chainId -match "^\d+$")) { Write-Output "Cannot reach the RPC: $chainId"; exit 1 }
if ($StateFile -eq "") {
  $StateFile = Join-Path (Split-Path $PSScriptRoot -Parent) (Join-Path "deployments" "two-phase-$chainId.json")
}
if (-not (Test-Path $StateFile)) { Write-Output "State file not found: $StateFile"; exit 1 }
$st = Get-Content $StateFile -Raw | ConvertFrom-Json
if ("$($st.chainId)" -ne "$chainId") {
  Write-Output "State file is for chain $($st.chainId), the RPC serves chain $chainId."
  exit 1
}

$token     = $st.token;     $timelock = $st.timelock; $governor = $st.governor
$staking   = $st.staking;   $migration = $st.migration
$deployer  = $st.deployer;  $guardian = $st.guardian
$treasury  = $st.treasury;  $marketingWallet = $st.marketingWallet
$treasuryOverridden = [bool]$st.treasuryOverridden
$oldDaimon = $st.oldDaimon

Write-Output "Post-broadcast verification -- chain $chainId"
Write-Output "State file: $StateFile"
Write-Output ""

# ---- Structural: code where code must be ----
foreach ($pair in @(@("token", $token), @("timelock", $timelock), @("governor", $governor), @("staking", $staking), @("migration", $migration))) {
  $prevEap = $ErrorActionPreference; $ErrorActionPreference = "Continue"
  $code = (cast code $pair[1] --rpc-url $Rpc 2>&1 | Out-String).Trim()
  $ErrorActionPreference = $prevEap
  Check "code at $($pair[0])" $(if ($code.Length -gt 4) { "present" } else { "MISSING" }) "present"
}

# ---- Role hashes, read from the contracts themselves ----
$govRole   = CastCall $token "GOVERNANCE_ROLE()(bytes32)"
$guardRole = CastCall $token "GUARDIAN_ROLE()(bytes32)"
$adminRole = CastCall $timelock "ADMIN_ROLE()(bytes32)"
$propRole  = CastCall $timelock "PROPOSER_ROLE()(bytes32)"
$execRole  = CastCall $timelock "EXECUTOR_ROLE()(bytes32)"
$cancRole  = CastCall $timelock "CANCELLER_ROLE()(bytes32)"
$defaultAdmin = "0x0000000000000000000000000000000000000000000000000000000000000000"

# ---- Token: governed only by the timelock ----
Check "token: timelock holds GOVERNANCE_ROLE"   (CastCall $token "hasRole(bytes32,address)(bool)" @($govRole, $timelock))   "true"
Check "token: deployer lacks GOVERNANCE_ROLE"   (CastCall $token "hasRole(bytes32,address)(bool)" @($govRole, $deployer))   "false"
Check "token: deployer lacks DEFAULT_ADMIN"     (CastCall $token "hasRole(bytes32,address)(bool)" @($defaultAdmin, $deployer)) "false"
Check "token: guardian holds GUARDIAN_ROLE"     (CastCall $token "hasRole(bytes32,address)(bool)" @($guardRole, $guardian)) "true"
Check "token: stakingRewardShareBps == 1000"    (CastCall $token "stakingRewardShareBps()(uint256)") "1000"
Check "token: stakingContract is the staking"   (CastCall $token "stakingContract()(address)") $staking
Check "token: marketingWallet as configured"    (CastCall $token "marketingWallet()(address)") $marketingWallet
Check "token: migration is fee-exempt"          (CastCall $token "isExcludedFromFee(address)(bool)" @($migration)) "true"

# ---- Timelock: self-administers, deployer has nothing ----
Check "timelock: self-administers"              (CastCall $timelock "hasRole(bytes32,address)(bool)" @($adminRole, $timelock)) "true"
Check "timelock: deployer lacks ADMIN_ROLE"     (CastCall $timelock "hasRole(bytes32,address)(bool)" @($adminRole, $deployer)) "false"
Check "timelock: deployer lacks PROPOSER_ROLE"  (CastCall $timelock "hasRole(bytes32,address)(bool)" @($propRole, $deployer))  "false"
Check "timelock: deployer lacks EXECUTOR_ROLE"  (CastCall $timelock "hasRole(bytes32,address)(bool)" @($execRole, $deployer))  "false"
Check "timelock: governor is proposer"          (CastCall $timelock "hasRole(bytes32,address)(bool)" @($propRole, $governor))  "true"
Check "timelock: governor is executor"          (CastCall $timelock "hasRole(bytes32,address)(bool)" @($execRole, $governor))  "true"

# ---- Cancellations (#26/#36) ----
Check "timelock: guardian is canceller"         (CastCall $timelock "hasRole(bytes32,address)(bool)" @($cancRole, $guardian)) "true"
Check "timelock: governor is canceller"         (CastCall $timelock "hasRole(bytes32,address)(bool)" @($cancRole, $governor)) "true"
Check "timelock: self-cancel role present"      (CastCall $timelock "hasRole(bytes32,address)(bool)" @($cancRole, $timelock)) "true"

# ---- Guardian expiry: EXACT equality across the three contracts ----
# The two-phase deploy removes the reason for any tolerance window: phase 2
# read the token's mined value and passed it verbatim. Any difference at all
# is a failure.
$expiryToken    = CastCall $token    "guardianExpiry()(uint256)"
$expiryTimelock = CastCall $timelock "guardianAuthorityExpiry()(uint256)"
$expiryGovernor = CastCall $governor "guardianAuthorityExpiry()(uint256)"
Check "expiry: timelock == token (exact)"       $expiryTimelock $expiryToken
Check "expiry: governor == token (exact)"       $expiryGovernor $expiryToken

# ---- Staking: governed only by the timelock ----
Check "staking: timelock is governance"         (CastCall $staking "isGovernance(address)(bool)" @($timelock)) "true"
Check "staking: deployer is not governance"     (CastCall $staking "isGovernance(address)(bool)" @($deployer)) "false"

# ---- Supply: entirely in the migration ----
$initialSupply = CastCall $token "INITIAL_SUPPLY()(uint256)"
Check "supply: totalSupply == INITIAL_SUPPLY"   (CastCall $token "totalSupply()(uint256)") $initialSupply
Check "supply: all of it in the migration"      (CastCall $token "balanceOf(address)(uint256)" @($migration)) $initialSupply

# ---- Migration: immutable wiring ----
Check "migration: governance is the timelock"   (CastCall $migration "governance()(address)") $timelock
Check "migration: newDaimon is the token"       (CastCall $migration "newDaimon()(address)") $token
Check "migration: oldDaimon as configured"      (CastCall $migration "oldDaimon()(address)") $oldDaimon
Check "migration: treasury as configured"       (CastCall $migration "treasury()(address)") $treasury
# The treasury IS the Timelock (derived in phase 1, fulfilled in phase 2).
# A testnet rehearsal may have opted into a separate treasury: that is NOT a
# mainnet-valid configuration and the row says so out loud.
if ($treasuryOverridden) {
  Write-Output "!!! TESTNET-ONLY treasury override was active on this deploy - NOT a mainnet-valid configuration."
  Check "migration: treasury override (TESTNET ONLY)" (CastCall $migration "treasury()(address)") $treasury
} else {
  Check "migration: treasury is the timelock"  (CastCall $migration "treasury()(address)") $timelock
}

# ---- Pair exists ----
$pairAddr = CastCall $token "uniswapV2Pair()(address)"
Check "token: pancake pair created"             $(if ($pairAddr -ne "0x0000000000000000000000000000000000000000") { "present" } else { "MISSING" }) "present"

# ---- Report ----
$script:results | Format-Table -AutoSize | Out-String -Width 200 | Write-Output
$total = $script:results.Count
Write-Output "Guardian expiry raw values: token=$expiryToken timelock=$expiryTimelock governor=$expiryGovernor"
if ($script:failures -eq 0) {
  Write-Output "VERIFICATION PASSED: $total/$total checks green against live chain state."
} else {
  Write-Output "VERIFICATION FAILED: $($script:failures) of $total checks failed. DO NOT PROCEED."
}
exit $script:failures
