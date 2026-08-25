# N1 - Negative control for item 1: a treasury other than the derived one
#      must be refused on a production chain, before anything is broadcast.
. .\script\campaign\lib.ps1
Log-Scenario "N1" "Treasury override on BSC mainnet (chain 56): phase 1 refuses with nothing broadcast"

# A fork of BSC MAINNET: chain id 56, the real production chain id the guard
# protects. (The campaign's usual node forks the testnet, chain 97, where
# the override is a legitimate loudly-logged rehearsal tool.)
Stop-Anvil
$mainnetFork = "https://bsc-rpc.publicnode.com"
Start-Process anvil -ArgumentList "--fork-url",$mainnetFork,"--port","8545","--silent" -WindowStyle Hidden
$up = $false
foreach ($i in 1..60) {
  Start-Sleep -Seconds 1
  try { $cid = cast chain-id --rpc-url $script:RPC 2>$null; if ($cid -eq "56") { $up = $true; break } } catch {}
}
if (-not $up) { throw "mainnet fork did not come up" }

# The exact misuse the guard exists for: a hand-supplied treasury on the
# production chain. Everything else is a plausible mainnet configuration.
$env:TESTNET_TREASURY_OVERRIDE = $script:TREASURY
$env:ROUTER = "0x10ED43C718714eb63d5aA57B78B54704E256024E"   # PancakeSwap V2, BSC mainnet
Remove-Item env:OLD_DAIMON -ErrorAction SilentlyContinue
$env:GUARDIAN_ADDRESS = $script:Addr.guardian
$env:MARKETING_WALLET = $script:MARKETING

$journal = Join-Path $script:ROOT (Join-Path "broadcast" (Join-Path "DeployPhase1.s.sol" "56"))
if (Test-Path $journal) { Remove-Item $journal -Recurse -Force }
$nonceBefore = cast nonce $script:Addr.deployer --rpc-url $script:RPC 2>$null

$prev = $ErrorActionPreference; $ErrorActionPreference = "Continue"
$out = forge script script/DeployPhase1.s.sol --rpc-url $script:RPC --broadcast --private-key $script:Key.deployer 2>&1 | Out-String
$code = $LASTEXITCODE
$ErrorActionPreference = $prev
Get-Process forge -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

$refused = ($code -ne 0 -and $out -match "not available on BSC mainnet")
Log-Step "N1.1" "Phase 1 with TESTNET_TREASURY_OVERRIDE set, on chain 56" "refused in simulation with the guard's own message" "exit=$code, message found=$refused" $(if ($refused) { "PASS" } else { "DEVIATION" })
$nonceAfter = cast nonce $script:Addr.deployer --rpc-url $script:RPC 2>$null
Log-Step "N1.2" "Was anything broadcast?" "nothing: no chain-56 journal written, deployer nonce untouched" "journal exists=$(Test-Path $journal), nonce $nonceBefore -> $nonceAfter" $(if (-not (Test-Path $journal) -and "$nonceBefore" -eq "$nonceAfter") { "PASS" } else { "DEVIATION" })
Log-Line ""
Log-Line "The refusal, verbatim from the forge output:"
Log-Line ""
Log-Line '```'
foreach ($l in (($out -split "`r?`n") | Where-Object { $_ -match "Error|revert|mainnet" } | Select-Object -First 4)) { Log-Line ($l.Trim()) }
Log-Line '```'
Remove-Item env:TESTNET_TREASURY_OVERRIDE -ErrorAction SilentlyContinue
Remove-Item env:ROUTER -ErrorAction SilentlyContinue
Stop-Anvil
Write-Output "N1 COMPLETE"
