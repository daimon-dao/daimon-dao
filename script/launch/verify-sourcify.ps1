# Source verification of a two-phase deployment -- on Sourcify (free), plus
# the files BscScan's MANUAL web form needs (the Etherscan API has no free
# tier for BNB Chain).
#
#   powershell -File script/launch/verify-sourcify.ps1 -Chain 56 -Rpc <url> [-Seeder <addr> -SeederTx <hash>] [-OldMock <addr> -OldMockTx <hash>]
#
# Why not `forge verify-contract --verifier sourcify`: with forge 1.5.1 and
# the Sourcify of 2026-09-28 it printed "already verified" / "Contract
# source code already verified" and verified NOTHING (Sourcify kept
# answering 404, match null). forge is used here only to produce the
# standard JSON input; the submission goes to Sourcify's v2 API
# (POST /v2/verify/{chain}/{address}, then poll /v2/verify/{id}), and the
# verdict is read back from GET /v2/contract/{chain}/{address}.
#
# Addresses, constructor arguments and creation transactions come from the
# phase-1/phase-2 broadcast journals (broadcast/DeployPhaseN.s.sol/<chain>/
# run-latest.json), never typed. -Seeder / -OldMock take their constructor
# arguments from their own on-chain getters. For every contract it writes,
# into script/launch/out/verify-<chain>/:
#   <Name>.standard-input.json   -> BscScan "Solidity (Standard-Json-Input)"
#   <Name>.constructor-args.txt  -> BscScan "Constructor Arguments ABI-encoded" (no 0x)
# Read-only on chain; sends no transaction.
param(
  [Parameter(Mandatory = $true)][string]$Chain,
  [Parameter(Mandatory = $true)][string]$Rpc,
  [string]$Seeder = "", [string]$SeederTx = "",
  [string]$OldMock = "", [string]$OldMockTx = "",
  [switch]$NoSubmit
)
$ErrorActionPreference = "Stop"
if (-not (Get-Command forge -ErrorAction SilentlyContinue)) { $env:PATH = (Join-Path $HOME ".foundry\bin") + ";" + $env:PATH }
$ROOT = (git rev-parse --show-toplevel)
Set-Location $ROOT
$served = (cast chain-id --rpc-url $Rpc | Out-String).Trim()
if ($served -ne $Chain) { throw "the RPC serves chain $served, not $Chain" }
$OUT = Join-Path $ROOT (Join-Path "script\launch\out" "verify-$Chain")
New-Item -ItemType Directory -Force $OUT | Out-Null
$SOURCIFY = "https://sourcify.dev/server"
$UTF8 = New-Object System.Text.UTF8Encoding($false)   # no BOM: the API rejects one

$SPEC = @{
  "DaimonV2"        = @{ path = "src/DaimonV2.sol:DaimonV2"; sig = "" }
  "ERC1967Proxy"    = @{ path = "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy"; sig = "constructor(address,bytes)" }
  "DaimonMigration" = @{ path = "src/DaimonMigration.sol:DaimonMigration"; sig = "constructor(address,address,address,address,uint256)" }
  "DaimonTimelock"  = @{ path = "src/DaimonTimelock.sol:DaimonTimelock"; sig = "constructor(uint256,address,address,address,address,uint256)" }
  "DaimonStaking"   = @{ path = "src/DaimonStaking.sol:DaimonStaking"; sig = "constructor(address,address)" }
  "DaimonGovernor"  = @{ path = "src/DaimonGovernor.sol:DaimonGovernor"; sig = "constructor(address,address,address,uint256,uint256,uint256)" }
}
$targets = @()
foreach ($phase in @("DeployPhase1.s.sol", "DeployPhase2.s.sol")) {
  $jf = Join-Path $ROOT "broadcast\$phase\$Chain\run-latest.json"
  if (-not (Test-Path $jf)) { throw "broadcast journal missing: $jf" }
  $j = Get-Content $jf -Raw | ConvertFrom-Json
  foreach ($t in @($j.transactions)) {
    if ("$($t.transactionType)" -ne "CREATE") { continue }
    $s = $SPEC["$($t.contractName)"]
    if (-not $s) { continue }   # e.g. a testnet MockOldDaimon deployed by phase 1
    $targets += [pscustomobject]@{ name = "$($t.contractName)"; address = "$($t.contractAddress)"; path = $s.path; sig = $s.sig; args = @($t.arguments); tx = "$($t.hash)" }
  }
}
function Get1 { param($to, $sig) return ((cast call $to $sig --rpc-url $Rpc | Select-Object -First 1) -split "\s+")[0] }
if ($Seeder -ne "") {
  $targets += [pscustomobject]@{ name = "LiquiditySeeder"; address = $Seeder; path = "script/launch/LiquiditySeeder.sol:LiquiditySeeder"; tx = $SeederTx
    sig = "constructor(address,address,address,address,address)"
    args = @((Get1 $Seeder "owner()(address)"), (Get1 $Seeder "dmn()(address)"), (Get1 $Seeder "pair()(address)"), (Get1 $Seeder "wbnb()(address)"), (Get1 $Seeder "timelock()(address)")) }
}
if ($OldMock -ne "") {
  # CampaignOldDaimon(initialSupply, holder): on Chapel 2b the holder was the
  # deployer, which the mock records as its immutable owner.
  $targets += [pscustomobject]@{ name = "CampaignOldDaimon"; address = $OldMock; path = "script/campaign/CampaignOldDaimon.sol:CampaignOldDaimon"; tx = $OldMockTx
    sig = "constructor(uint256,address)"; args = @((Get1 $OldMock "totalSupply()(uint256)"), (Get1 $OldMock "owner()(address)")) }
}

## GET /v2/contract: Sourcify answers 404 (with a JSON body) when unverified.
function Sourcify-Status { param($addr)
  try { $r = Invoke-WebRequest -Uri "$SOURCIFY/v2/contract/$Chain/$addr" -UseBasicParsing -TimeoutSec 30; return ($r.Content | ConvertFrom-Json) }
  catch { return [pscustomobject]@{ match = $null; runtimeMatch = $null; creationMatch = $null } }
}

$rows = @()
foreach ($t in $targets) {
  $enc = ""
  if ($t.sig -ne "") { $enc = ((cast abi-encode $t.sig @($t.args) | Out-String).Trim()) }
  $vargs = @($t.address, $t.path, "--chain", $Chain, "--rpc-url", $Rpc)
  if ($enc -ne "") { $vargs += @("--constructor-args", $enc) }
  $prev = $ErrorActionPreference; $ErrorActionPreference = "Continue"
  $sj = (forge verify-contract @vargs --show-standard-json-input 2>&1 | Out-String)
  $ErrorActionPreference = $prev
  $sjStart = $sj.IndexOf("{"); $sjEnd = $sj.LastIndexOf("}")
  if ($sjStart -lt 0) { throw "no standard JSON input for $($t.name): $sj" }
  $stdJson = $sj.Substring($sjStart, $sjEnd - $sjStart + 1)
  [System.IO.File]::WriteAllText((Join-Path $OUT "$($t.name).standard-input.json"), $stdJson, $UTF8)
  [System.IO.File]::WriteAllText((Join-Path $OUT "$($t.name).constructor-args.txt"), ($enc -replace "^0x", ""), $UTF8)
  $compiler = ((Get-Content (Join-Path $ROOT "out\$(Split-Path ($t.path -split ':')[0] -Leaf)\$($t.name).json") -Raw | ConvertFrom-Json).metadata.compiler.version)

  $job = "not submitted"
  $st = Sourcify-Status $t.address
  if (-not $NoSubmit -and -not $st.match) {
    $body = '{"stdJsonInput":' + $stdJson + ',"compilerVersion":"' + $compiler + '","contractIdentifier":"' + $t.path + '"'
    if ($t.tx -ne "") { $body += ',"creationTransactionHash":"' + $t.tx + '"' }
    $body += '}'
    $resp = Invoke-WebRequest -Uri "$SOURCIFY/v2/verify/$Chain/$($t.address)" -Method Post -ContentType "application/json" -Body $UTF8.GetBytes($body) -UseBasicParsing -TimeoutSec 120
    $vid = ($resp.Content | ConvertFrom-Json).verificationId
    $job = "submitted $vid"
    foreach ($i in 1..40) {
      Start-Sleep -Seconds 4
      $p = (Invoke-WebRequest -Uri "$SOURCIFY/v2/verify/$vid" -UseBasicParsing -TimeoutSec 30).Content | ConvertFrom-Json
      if ($p.isJobCompleted) {
        $job = if ($p.error) { "FAILED: $($p.error.customCode) $($p.error.message)" } else { "job $vid completed" }
        break
      }
    }
    $st = Sourcify-Status $t.address
  } elseif ($st.match) { $job = "already on Sourcify" }
  $rows += [pscustomobject]@{ contract = $t.name; address = $t.address; match = "$($st.match)"; creation = "$($st.creationMatch)"; runtime = "$($st.runtimeMatch)"; compiler = $compiler; job = $job }
}
$rows | Format-Table -AutoSize | Out-String -Width 260 | Write-Output
$bad = @($rows | Where-Object { $_.match -ne "exact_match" -and $_.match -ne "match" }).Count
Write-Output "Sourcify: $($rows.Count - $bad)/$($rows.Count) verified on chain $Chain. BscScan manual-form files: $OUT"
exit $bad
