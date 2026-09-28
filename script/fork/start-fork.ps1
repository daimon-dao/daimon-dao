# F0 -- the real mainnet reads, then a LOCAL Anvil fork of BSC mainnet at
# the freshest block the upstream serves. Read-only against the real
# network; every write below goes to the local node (anvil_* methods).
#   powershell -File script/fork/start-fork.ps1 -Label A [-Upstream <url>]
param(
  [Parameter(Mandatory = $true)][string]$Label,
  [string]$Upstream = "https://bsc-rpc.publicnode.com"
)
. $PSScriptRoot\lib.ps1
Load-Holders
if (-not (Test-Path $script:OUTDIR)) { New-Item -ItemType Directory -Path $script:OUTDIR | Out-Null }

# Stale launch artifacts from a previous fork run must never be picked up:
# phase 2 and the verification read deployments/two-phase-56.json, and a
# chain-56 broadcast journal is what `--resume` would resume. launch-day.ps1
# moves them into script/fork/out/ at the end of every run; if one is here
# now, a human decides -- nothing is deleted silently.
$stale = @(
  (Join-Path $script:ROOT "deployments\two-phase-56.json"),
  (Join-Path $script:ROOT "broadcast\DeployPhase1.s.sol\56"),
  (Join-Path $script:ROOT "broadcast\DeployPhase2.s.sol\56")
) | Where-Object { Test-Path $_ }
if ($stale.Count -gt 0) { throw "REFUSED: chain-56 launch artifacts already exist: $($stale -join ', ') -- move them away by hand first" }

# ---- The real mainnet reads (read-only, upstream) ---------------------------
function Up { param($to, $sig, [string[]]$a = @()) return (CQRawAt $Upstream $to $sig $a) }
$upChain = (cast chain-id --rpc-url $Upstream | Out-String).Trim()
if ($upChain -ne "56") { throw "the upstream serves chain $upChain, not BSC mainnet" }
$mDepNonce = (cast nonce $script:DEPLOYER --rpc-url $Upstream | Out-String).Trim()
$mDepBal = BI (((cast balance $script:DEPLOYER --rpc-url $Upstream) -split "\s+")[0])
$mDepCode = (cast code $script:DEPLOYER --rpc-url $Upstream | Out-String).Trim()
$mOwnBal = BI (((cast balance $script:OWNER --rpc-url $Upstream) -split "\s+")[0])
$mOwnNonce = (cast nonce $script:OWNER --rpc-url $Upstream | Out-String).Trim()
$mOwnCode = (cast code $script:OWNER --rpc-url $Upstream | Out-String).Trim()
$mGas = BI ((cast gas-price --rpc-url $Upstream | Out-String).Trim())
$mOwner = Up $script:DMX "owner()(address)"
$mCap = BI (Up $script:DMX "_maxTxAmount()(uint256)")
$mOwnEx = Up $script:DMX "isExcludedFromFee(address)(bool)" @($script:OWNER)
$mUnlock = Up $script:DMX "getUnlockTime()(uint256)"
$mOwnDmx = BI (Up $script:DMX "balanceOf(address)(uint256)" @($script:OWNER))
$rFactory = Up $script:ROUTER "factory()(address)"
$rWeth = Up $script:ROUTER "WETH()(address)"
$dmxRouter = Up $script:DMX "uniswapV2Router()(address)"
$dmxPair = Up $script:DMX "uniswapV2Pair()(address)"
$fPair = Up $script:FACTORY "getPair(address,address)(address)" @($script:DMX, $script:WBNB)
$initHash = Up $script:FACTORY "INIT_CODE_PAIR_HASH()(bytes32)"
$pin = [long]((cast block-number --rpc-url $Upstream | Out-String).Trim())

Log-Line ""
Log-Line "## Run $Label"
Log-Scenario "F0 (run $Label)" "Real mainnet reads, then the local fork of chain 56 at block $pin"
Log-Step "F0.1" "Planned mainnet deployer, read on MAINNET" "nonce 0 (never used: phase 1 must predict from nonce 0); no code" "nonce=$mDepNonce, balance=$(FmtT $mDepBal) BNB ($mDepBal wei), code=$mDepCode" "-" $(if ($mDepNonce -eq "0" -and $mDepCode -eq "0x") { "PASS" } else { "DEVIATION" })
Log-Step "F0.2" "DMX owner, read on MAINNET" "an EOA; its real BNB balance is what funds 5a-11b" "balance=$(FmtT $mOwnBal) BNB ($mOwnBal wei), nonce=$mOwnNonce, code=$mOwnCode, DMX held=$(FmtB $mOwnDmx)" "-" $(if ($mOwnCode -eq "0x") { "PASS" } else { "DEVIATION" })
Log-Step "F0.3" "The predecessor's authority and cap, read on MAINNET (checklist: 'confirm the DMX owner still has authority')" "owner() == the DMX owner; _maxTxAmount == 1.5B; owner fee-exempt; not in a lock() window (getUnlockTime 0)" "owner=$mOwner, _maxTxAmount=$(FmtB $mCap), isExcludedFromFee(owner)=$mOwnEx, getUnlockTime=$mUnlock" "-" $(if ("$mOwner".ToLower() -eq $script:OWNER.ToLower() -and $mCap -eq (BW "1.50") -and "$mOwnEx" -eq "true" -and "$mUnlock" -eq "0") { "PASS" } else { "DEVIATION" })
$routerOk = ("$rFactory".ToLower() -eq $script:FACTORY.ToLower() -and "$rWeth".ToLower() -eq $script:WBNB.ToLower() -and "$dmxRouter".ToLower() -eq $script:ROUTER.ToLower() -and "$fPair".ToLower() -eq $script:DMX_POOL.ToLower() -and "$dmxPair".ToLower() -eq $script:DMX_POOL.ToLower())
Log-Step "F0.4" "ROUTER identity, from source and chain (not guessed)" "developer.pancakeswap.finance/contracts/v2/addresses lists router $($script:ROUTER) and factory $($script:FACTORY) for BSC; on chain: router.factory() and router.WETH() match, DMX.uniswapV2Router() is the same router, factory.getPair(DMX, WBNB) == DMX.uniswapV2Pair()" "router.factory=$rFactory, router.WETH=$rWeth, DMX.uniswapV2Router=$dmxRouter, factory.getPair(DMX,WBNB)=$fPair, DMX.uniswapV2Pair=$dmxPair, INIT_CODE_PAIR_HASH=$initHash" "-" $(V $routerOk)
if (-not $routerOk) { throw "STOP: router identity" }
Log-Step "F0.5" "Mainnet gas price at fork time" "every fork transaction pays exactly this, so the BNB totals are the real funding numbers" "eth_gasPrice=$mGas wei ($([decimal]$mGas / 1000000000) gwei)" "-" "NOTE"

# ---- The fork ---------------------------------------------------------------
Get-Process anvil -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 500
$alog = Join-Path $script:OUTDIR "anvil-$Label.log"
$aerr = Join-Path $script:OUTDIR "anvil-$Label.err.log"
$anvilArgs = @("--fork-url", $Upstream, "--fork-block-number", "$pin", "--port", "$($script:PORT)", "--host", "127.0.0.1",
  "--gas-price", "$mGas", "--block-base-fee-per-gas", "0", "--retries", "10", "--timeout", "60000", "--fork-retry-backoff", "2000")
# Detached through WMI: a child started with Start-Process inherits this
# shell's handles and keeps any caller waiting until the fork is stopped.
$anvilExe = (Get-Command anvil).Source
$cmdLine = "cmd.exe /c `"`"$anvilExe`" $($anvilArgs -join ' ') > `"$alog`" 2> `"$aerr`"`""
$cr = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{ CommandLine = $cmdLine; CurrentDirectory = $script:ROOT }
if ($cr.ReturnValue -ne 0) { throw "could not start anvil (Win32_Process.Create returned $($cr.ReturnValue))" }
$up = $false
foreach ($i in 1..90) {
  Start-Sleep -Seconds 1
  $prev = $ErrorActionPreference; $ErrorActionPreference = "Continue"
  $cid = (cast chain-id --rpc-url $script:RPC 2>&1 | Out-String).Trim()
  $ErrorActionPreference = $prev
  if ($cid -eq "56") { $up = $true; break }
}
if (-not $up) { throw "the fork did not come up: $(Get-Content $aerr -Raw)" }
Assert-LocalFork
$ni = Rpc "anvil_nodeInfo" | ConvertFrom-Json
$cv = Rpc "web3_clientVersion"
$fb = [long]((cast block-number --rpc-url $script:RPC | Out-String).Trim())
Log-Step "F0.6" "Local fork up" "Anvil on 127.0.0.1:$($script:PORT), chain 56, forked from the upstream at the pinned block" "clientVersion=$cv, chainId=56, forkUrl=$($ni.forkConfig.forkUrl), forkBlockNumber=$($ni.forkConfig.forkBlockNumber), local head=$fb" "-" $(V ("$($ni.forkConfig.forkBlockNumber)" -eq "$pin"))

# ---- Roles: impersonated, the deployer funded to exactly the plan -----------
foreach ($r in @("deployer", "owner", "holderA", "holderB")) { Rpc "anvil_impersonateAccount" @($script:AddrBook[$r]) | Out-Null }
$PLAN = BI "200000000000000000"   # 0.2 BNB -- the planned deployer funding
Rpc "anvil_setBalance" @($script:DEPLOYER, (ToHex $PLAN)) | Out-Null
$fDepNonce = Nonce $script:DEPLOYER; $fDepBal = Bal $script:DEPLOYER
$fOwnBal = Bal $script:OWNER
Log-Step "F0.7" "Roles on the fork: deployer and owner impersonated (no key anywhere); deployer set to exactly 0.2 BNB (anvil_setBalance, the only balance ever set); the owner left at its real balance" "deployer nonce 0, balance 0.200000 BNB; owner balance on the fork == the mainnet read" "deployer nonce=$fDepNonce, balance=$(FmtT $fDepBal) ($fDepBal wei); owner fork balance=$(FmtT $fOwnBal) vs mainnet $(FmtT $mOwnBal)" "-" $(V ($fDepNonce -eq 0 -and $fDepBal -eq $PLAN -and $fOwnBal -eq $mOwnBal))

# The two real third-party holders: checked, never named.
$hA = $script:AddrBook.holderA; $hB = $script:AddrBook.holderB
$aBal = CQ $script:DMX "balanceOf(address)(uint256)" @($hA); $bBal = CQ $script:DMX "balanceOf(address)(uint256)" @($hB)
$aEx = CQRaw $script:DMX "isExcludedFromFee(address)(bool)" @($hA); $bEx = CQRaw $script:DMX "isExcludedFromFee(address)(bool)" @($hB)
$aRw = CQRaw $script:DMX "isExcludedFromReward(address)(bool)" @($hA); $bRw = CQRaw $script:DMX "isExcludedFromReward(address)(bool)" @($hB)
$aCode = (cast code $hA --rpc-url $script:RPC | Out-String).Trim(); $bCode = (cast code $hB --rpc-url $script:RPC | Out-String).Trim()
$a7702 = $aCode.StartsWith("0xef0100"); $b7702 = $bCode.StartsWith("0xef0100")
$aKind = if ($aCode -eq "0x") { "plain EOA" } elseif ($a7702) { "EOA with an EIP-7702 delegation" } else { "CONTRACT" }
$bKind = if ($bCode -eq "0x") { "plain EOA" } elseif ($b7702) { "EOA with an EIP-7702 delegation" } else { "CONTRACT" }
$aBand = if ($aBal -gt (BW "10.00")) { "> 10 B" } else { "<= 10 B" }
$bBand = if ($bBal -ge (BW "1.00") -and $bBal -lt (BW "1.50")) { "1.00-1.50 B" } else { "outside 1.00-1.50 B" }
Log-Step "F0.8" "Two REAL third-party DMX holders from the live holder list (BSCTrace, 2026-09-28), impersonated, their real BNB untouched; addresses in a gitignored file, never in this journal" "holder A: > 10 B DMX (claims 10.00 B after 11b, 6.7x the old cap); holder B: 1.00-1.50 B (claims 1.00 B, below the cap); neither fee- nor reward-excluded on DMX; neither is a contract" "A: $aBand, $aKind, feeExcluded=$aEx, rewardExcluded=$aRw; B: $bBand, $bKind, feeExcluded=$bEx, rewardExcluded=$bRw" "-" $(V ($aBal -gt (BW "10.00") -and $bBand -eq "1.00-1.50 B" -and "$aEx" -eq "false" -and "$bEx" -eq "false" -and $aKind -ne "CONTRACT" -and $bKind -ne "CONTRACT"))

Save-State ([pscustomobject]@{
  label = $Label; upstream = $Upstream; forkBlock = "$pin"; gasPrice = "$mGas"
  mainnetDeployerNonce = $mDepNonce; mainnetDeployerBalance = "$mDepBal"; mainnetOwnerBalance = "$mOwnBal"
  deployerStart = "$fDepBal"; ownerStart = "$fOwnBal"
  holderAStartBnb = "$(Bal $hA)"; holderBStartBnb = "$(Bal $hB)"
})
Write-Output "F0 COMPLETE run=$Label fork block=$pin gasPrice=$mGas deployer nonce(mainnet)=$mDepNonce owner=$(FmtT $mOwnBal) BNB"
