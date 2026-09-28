# Mainnet-fork rehearsal harness -- a LOCAL Anvil fork of BSC mainnet
# (chain 56), the REAL predecessor DMX, the REAL DMX pool, the REAL
# PancakeSwap v2 router. Derived from script/chapel2b/lib.ps1; what changed:
#   - NOTHING here can reach the real network with a transaction. Every
#     send goes through Send / Run-Forge, and both call Assert-LocalFork
#     first: the RPC must be a loopback URL, the node must answer
#     web3_clientVersion as Anvil, the chain id must be 56 and the node
#     must report a fork (anvil_nodeInfo). The only non-local URL in this
#     file is the UPSTREAM the fork reads state from, and it is used for
#     read-only calls (Up-*) exclusively.
#   - NO private key exists anywhere: every signer is an account the fork
#     impersonates (anvil_impersonateAccount); cast signs nothing, it asks
#     the node to (`--unlocked`), and forge runs with `--unlocked --sender`.
#   - roles are the REAL mainnet addresses: `deployer` (the planned mainnet
#     deployer, funded on the fork to exactly the planned 0.2 BNB) and
#     `owner` (the real DMX owner, its real BNB balance untouched). Two real
#     third-party DMX holders (`holderA` above the 1.5B cap, `holderB`
#     below it) come from script/fork/holders.local.json, gitignored: their
#     addresses never enter the repository or the journal.
#   - every transaction pays the MAINNET gas price read at fork start, so
#     the BNB each signer spends is the real funding number.
$ErrorActionPreference = "Stop"
$script:ROOT = (git rev-parse --show-toplevel)
$script:PORT = 8555
$script:RPC  = "http://127.0.0.1:$($script:PORT)"
$script:FORKDIR = Join-Path $script:ROOT (Join-Path "script" "fork")
$script:OUTDIR  = Join-Path $script:FORKDIR "out"
$script:StatePath = Join-Path $script:FORKDIR "state.json"
$script:LOG = Join-Path $script:ROOT (Join-Path "docs" "MAINNET_FORK_RESULTS.md")

# Foundry lives in the user profile on this machine, not in the system PATH.
if (-not (Get-Command cast -ErrorAction SilentlyContinue)) { $env:PATH = (Join-Path $HOME ".foundry\bin") + ";" + $env:PATH }
# Nothing ambient may steer a tool towards another node or a key.
foreach ($v in @("ETH_RPC_URL", "ETH_FROM", "PRIVATE_KEY", "ETH_PRIVATE_KEY", "ETH_KEYSTORE", "ETH_PASSWORD", "MNEMONIC")) {
  Remove-Item "env:$v" -ErrorAction SilentlyContinue
}

# ---- Real mainnet addresses ------------------------------------------------
$script:DEPLOYER = "0x4D38C9FE5250235dc99D3e098cd515B008aCa26e"  # planned mainnet deployer
$script:OWNER    = "0xF8EC459CAEaF1052b64B38BDD67290B0c132B0Ae"  # DMX owner (EOA)
$script:GUARDIAN = "0x37F45839765AD3418E29c97d5D92407Ddbf5c7a8"  # the mainnet 2-of-3 Safe
$script:DMX      = "0x36EbA94407B53c631eE822C219e94580fadd67c7"  # the predecessor
$script:DMX_POOL = "0xB24916823C61Ee6272448209174F75fAfD297B82"  # DMX/WBNB on PancakeSwap v2
# PancakeSwap v2 on BSC, verified three ways before the first run
# (2026-09-28): developer.pancakeswap.finance/contracts/v2/addresses lists
# this router and the factory below; DMX's own uniswapV2Router() returns
# it; router.factory()/WETH() return the factory/WBNB below and
# factory.getPair(DMX, WBNB) returns the DMX pool. Re-checked live by
# start-fork.ps1 (row F0.4).
$script:ROUTER   = "0x10ED43C718714eb63d5aA57B78B54704E256024E"
$script:FACTORY  = "0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73"
$script:WBNB     = "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c"
$script:DEAD     = "0x000000000000000000000000000000000000dEaD"
$script:ZERO     = "0x0000000000000000000000000000000000000000"

$script:AddrBook = @{ deployer = $script:DEPLOYER; owner = $script:OWNER }
function Load-Holders {
  $p = Join-Path $script:FORKDIR "holders.local.json"
  if (-not (Test-Path $p)) { throw "holders.local.json missing (copy holders.example.json and fill two real DMX holders from the live holder list)" }
  $h = Get-Content $p -Raw | ConvertFrom-Json
  foreach ($k in @("holderA", "holderB")) {
    if (-not ("$($h.$k)" -match "^0x[0-9a-fA-F]{40}$")) { throw "holders.local.json: '$k' must be an address" }
    $script:AddrBook[$k] = "$($h.$k)"
  }
}

$script:E18 = [System.Numerics.BigInteger]::Pow(10, 18)
function BI { param($x) return [System.Numerics.BigInteger]::Parse("$x") }
function HexBI { param([string]$h) return [System.Numerics.BigInteger]::Parse("0" + $h.Substring(2), "AllowHexSpecifier") }
function ToHex { param($n) return "0x" + ([System.Numerics.BigInteger]$n).ToString("x").TrimStart("0").PadLeft(1, "0") }
function BW { param([string]$b) return ([System.Numerics.BigInteger]([decimal]$b * 10000) * ($script:E18 / 10000) * 1000000000) }  # BILLIONS -> wei
function FmtB { param($wei)
  $b = [System.Numerics.BigInteger]$wei
  $neg = ($b -lt [System.Numerics.BigInteger]::Zero); if ($neg) { $b = -$b }
  $bn = $script:E18 * 1000000000
  $w = [System.Numerics.BigInteger]::Divide($b, $bn)
  $r = [System.Numerics.BigInteger]::Divide(($b - ($w * $bn)) * 10000, $bn)
  $s = "$w.$($r.ToString().PadLeft(4,'0')) B"
  if ($neg) { return "-$s" } else { return $s }
}
## BNB (or whole tokens) with 6 decimals.
function FmtT { param($wei)
  $b = [System.Numerics.BigInteger]$wei
  $neg = ($b -lt [System.Numerics.BigInteger]::Zero); if ($neg) { $b = -$b }
  $w = [System.Numerics.BigInteger]::Divide($b, $script:E18)
  $r = [System.Numerics.BigInteger]::Divide(($b - ($w * $script:E18)) * 1000000, $script:E18)
  $s = "$w.$($r.ToString().PadLeft(6,'0'))"
  if ($neg) { return "-$s" } else { return $s }
}
function CeilDiv { param($n, $d)
  $q = [System.Numerics.BigInteger]::Divide($n, $d)
  if (($q * $d) -ne $n) { $q = $q + [System.Numerics.BigInteger]::One }
  return $q
}
## The DMN amount the pair receives from a taxed transfer of `gross`, as the
## token computes it (_getValues: two floor divisions out of 1000).
function NetOfGross { param($gross, $taxFee, $liquidityFee)
  $g = [System.Numerics.BigInteger]$gross
  $tFee = [System.Numerics.BigInteger]::Divide($g * $taxFee, 1000)
  $tLiq = [System.Numerics.BigInteger]::Divide($g * $liquidityFee, 1000)
  return ($g - $tFee - $tLiq)
}
function Pct { param($num, $den, [int]$dec = 2)
  if ($den -eq 0) { return "n/a" }
  $scale = [System.Numerics.BigInteger]::Pow(10, $dec)
  $v = [System.Numerics.BigInteger]::Divide(([System.Numerics.BigInteger]$num) * 100 * $scale, [System.Numerics.BigInteger]$den)
  $neg = $v -lt 0; if ($neg) { $v = -$v }
  $s = "$([System.Numerics.BigInteger]::Divide($v, $scale)).$(([System.Numerics.BigInteger]::Remainder($v, $scale)).ToString().PadLeft($dec,'0'))"
  if ($neg) { return "-$s" } else { return $s }
}

# ---- Read-only calls against a given RPC ------------------------------------
function CQRawAt { param($rpc, $to, $sig, [string[]]$callArgs = @())
  $prev = $ErrorActionPreference; $ErrorActionPreference = "Continue"
  $r = (cast call $to $sig @callArgs --rpc-url $rpc 2>&1 | Out-String)
  $c = $LASTEXITCODE; $ErrorActionPreference = $prev
  if ($c -ne 0) { throw "CALL FAILED [$to $sig]: $(($r -replace '\s+',' ').Trim())" }
  foreach ($l in ($r -split "`n")) { $t = $l.Trim(); if ($t -ne "") { return ($t -split "\s+")[0] } }
  throw "CALL empty [$to $sig]"
}
function CQRaw { param($to, $sig, [string[]]$callArgs = @()) return (CQRawAt $script:RPC $to $sig $callArgs) }
function CQ { param($to, $sig, [string[]]$callArgs = @()) return (BI (CQRaw $to $sig $callArgs)) }
function Bal { param($addr) return (BI (((cast balance $addr --rpc-url $script:RPC) -split "\s+")[0])) }
function Nonce { param($addr) return [int]((cast nonce $addr --rpc-url $script:RPC | Out-String).Trim()) }
function Code-Len { param($addr) $prev = $ErrorActionPreference; $ErrorActionPreference = "Continue"; $c = (cast code $addr --rpc-url $script:RPC 2>&1 | Out-String).Trim(); $ErrorActionPreference = $prev; return $c.Length }
function Rpc { param([string]$method, [string[]]$params = @())
  $prev = $ErrorActionPreference; $ErrorActionPreference = "Continue"
  $r = (cast rpc $method @params --rpc-url $script:RPC 2>&1 | Out-String)
  $c = $LASTEXITCODE; $ErrorActionPreference = $prev
  if ($c -ne 0) { throw "RPC FAILED [$method]: $(($r -replace '\s+',' ').Trim())" }
  return $r.Trim()
}
function Now-Ts { return [long](HexBI ((Rpc "eth_getBlockByNumber" @("latest", "false") | ConvertFrom-Json).timestamp)) }

# ---- THE guard: nothing is sent unless the node is the local Anvil fork -----
$script:LocalChecks = 0
function Assert-LocalFork {
  if ($script:RPC -notmatch '^http://127\.0\.0\.1:\d+$') { throw "REFUSED: the RPC '$($script:RPC)' is not a loopback URL" }
  $cv = Rpc "web3_clientVersion"
  if ($cv -notmatch '(?i)anvil') { throw "REFUSED: the node at $($script:RPC) is not Anvil ($cv)" }
  $cid = (cast chain-id --rpc-url $script:RPC | Out-String).Trim()
  if ($cid -ne "56") { throw "REFUSED: the local node serves chain '$cid', this harness rehearses BSC mainnet (56) on a fork" }
  $ni = Rpc "anvil_nodeInfo" | ConvertFrom-Json
  if (-not $ni.forkConfig -or -not $ni.forkConfig.forkUrl) { throw "REFUSED: the local Anvil is not a fork" }
  $script:LocalChecks++
}

# ---- State ------------------------------------------------------------------
function Load-State { if (Test-Path $script:StatePath) { return (Get-Content $script:StatePath -Raw | ConvertFrom-Json) } else { return $null } }
function S { return Load-State }
function Save-State { param($obj) $obj | ConvertTo-Json -Depth 6 | Set-Content $script:StatePath -Encoding utf8 }
function Set-StateField { param($name, $value)
  $st = Load-State
  if ($null -eq $st) { $st = [pscustomobject]@{} }
  $st | Add-Member -NotePropertyName $name -NotePropertyValue $value -Force
  Save-State $st
}

# ---- The gas ledger: every mined transaction, who paid, what it cost --------
# Kept in memory by the runner and flushed to state.json; `probe` rows are
# transactions later discarded by evm_revert and never counted in totals.
$script:Ledger = New-Object System.Collections.ArrayList
$script:ProbeMode = $false
function Add-Ledger { param($step, $who, $what, $gas, $price, $hash)
  $g = [System.Numerics.BigInteger]$gas; $p = [System.Numerics.BigInteger]$price
  [void]$script:Ledger.Add([pscustomobject]@{ step = $step; who = $who; what = $what; gas = "$g"; price = "$p"; cost = "$($g * $p)"; tx = $hash; probe = $script:ProbeMode })
}

## Signed send, impersonated. Returns @{ hash; gasUsed; block; cost }.
function Send { param($who, $to, $sig, [string[]]$sendArgs = @(), [string]$value = "0", [string]$step = "", [switch]$NoInvariant)
  Assert-LocalFork
  $from = $script:AddrBook[$who]; if (-not $from) { throw "unknown role '$who'" }
  $gp = "$((S).gasPrice)"
  $extra = @(); if ($value -ne "0") { $extra += @("--value", $value) }
  $prev = $ErrorActionPreference; $ErrorActionPreference = "Continue"
  $r = (cast send $to $sig @sendArgs --from $from --unlocked --legacy --gas-price $gp --rpc-url $script:RPC --json @extra 2>&1 | Out-String)
  $c = $LASTEXITCODE; $ErrorActionPreference = $prev
  if ($c -ne 0) { throw "SEND FAILED [$who -> $to $sig]: $(($r -replace '\s+',' ').Trim())" }
  $j = $r | ConvertFrom-Json
  if ($j.status -ne "0x1") { throw "TX REVERTED [$who -> $to $sig]: $($j.transactionHash)" }
  $gas = HexBI $j.gasUsed; $price = HexBI $j.effectiveGasPrice
  Add-Ledger $step $who $sig $gas $price $j.transactionHash
  if (-not $NoInvariant) { Assert-Invariants "$who -> $sig" }
  return @{ hash = $j.transactionHash; gasUsed = $gas; block = (HexBI $j.blockNumber); cost = ($gas * $price); logs = @($j.logs).Count }
}
## A call EXPECTED to revert, as the given role -- a pure eth_call on the
## fork (`cast call --from`): nothing is mined, no nonce moves.
function Expect-Revert { param($who, $to, $sig, [string[]]$callArgs = @(), [string]$match = "", [string]$value = "0", [string]$overrideState = "")
  Assert-LocalFork
  $from = $script:AddrBook[$who]
  $extra = @(); if ($value -ne "0") { $extra += @("--value", $value) }
  if ($overrideState -ne "") { $extra += @("--override-state-diff", $overrideState) }   # -diff: patch ONE slot; plain --override-state replaces the whole storage (run F)
  $prev = $ErrorActionPreference; $ErrorActionPreference = "Continue"
  $r = (cast call $to $sig @callArgs --from $from --rpc-url $script:RPC @extra 2>&1 | Out-String)
  $c = $LASTEXITCODE; $ErrorActionPreference = $prev
  if ($c -eq 0) { return "DID-NOT-REVERT" }
  $flat = ($r -replace '\s+', ' ').Trim()
  if ($match -ne "") {
    $name = $match -replace "\(\)$", ""
    if ($flat -match [regex]::Escape($name)) { return "reverted with $name" }
    if ($match -match "^\w+\(.*\)$") {
      $sel = (cast sig $match 2>$null)
      if ($sel -and $flat -match [regex]::Escape($sel.Substring(0, 10))) { return "reverted with $name" }
    }
    return "reverted (different reason): $($flat.Substring(0, [Math]::Min(200, $flat.Length)))"
  }
  return "reverted: $($flat.Substring(0, [Math]::Min(200, $flat.Length)))"
}

## The launch invariant (share 1000): the Timelock -- marketing wallet AND
## treasury -- receives NO BNB and NO DMN from the token. Its DMX balance
## grows with every claim (the treasury working) and its LP balance is set
## by step 6: neither is a token payout. Asserted after every send.
$script:InvariantChecks = 0
function Assert-Invariants { param([string]$context)
  $st = S
  if (-not $st -or -not $st.timelock) { return }
  $nat = Bal $st.timelock
  if ($nat -ne 0) { throw "INVARIANT VIOLATED [$context]: the Timelock holds $nat wei of BNB" }
  $dmn = CQ $st.token "balanceOf(address)(uint256)" @($st.timelock)
  if ($dmn -ne 0) { throw "INVARIANT VIOLATED [$context]: the Timelock holds $dmn wei of DMN" }
  $script:InvariantChecks++
}

# ---- Journal ----------------------------------------------------------------
function Log-Line { param([string]$text)
  foreach ($try in 1..10) {
    try { Add-Content -Path $script:LOG -Value $text -Encoding utf8 -ErrorAction Stop; return } catch { Start-Sleep -Milliseconds 300 }
  }
  throw "could not write the results log"
}
function Log-Scenario { param($id, $title)
  Log-Line ""
  Log-Line "### $id -- $title"
  Log-Line ""
  Log-Line "| step | action | expected | observed | tx | verdict |"
  Log-Line "|---|---|---|---|---|---|"
}
$script:Verdicts = @{ PASS = 0; NOTE = 0; DEVIATION = 0; FINDING = 0; STOP = 0 }
function Log-Step { param($id, $action, $expected, $observed, $tx, $verdict)
  $script:Verdicts[$verdict] = [int]$script:Verdicts[$verdict] + 1
  Log-Line "| $id | $action | $expected | $observed | $tx | $verdict |"
  if ($verdict -eq "DEVIATION" -or $verdict -eq "STOP") { Write-Output "!! $verdict at $id" }
}
function Log-Note { param($text) Log-Line ""; Log-Line "> $text" }
function Log-Block { param([string]$title, [string]$text, [string]$fence = "")
  Log-Line ""; Log-Line $title; Log-Line ""; Log-Line ('```' + $fence)
  foreach ($l in ($text -split "`r?`n")) { Log-Line ($l.TrimEnd()) }
  Log-Line '```'
}
function V { param([bool]$ok) if ($ok) { return "PASS" } else { return "DEVIATION" } }

# ---- Pools ------------------------------------------------------------------
## Reserves of a V2 pair as [token, wbnb], whatever order the pair uses.
function Reserves-Of { param($pair, $token)
  $raw = (cast call $pair "getReserves()(uint112,uint112,uint32)" --rpc-url $script:RPC 2>&1 | Out-String)
  $nums = @()
  foreach ($line in ($raw -split "`n")) {
    $t = $line.Trim(); if ($t -eq "") { continue }
    $first = ($t -split "\s+")[0]
    if ($first -match "^\d+$") { $nums += (BI $first) }
  }
  $t0 = CQRaw $pair "token0()(address)"
  if ("$t0".ToLower() -eq "$token".ToLower()) { return ,@($nums[0], $nums[1]) } else { return ,@($nums[1], $nums[0]) }
}
function Pair-Reserves { $st = S; return (Reserves-Of $st.pair $st.token) }
## Price of one whole token in wei of BNB, from reserves: bnb * 1e18 / tokens.
function Price-WeiPerToken { param($tokRes, $bnbRes)
  if ($tokRes -eq 0) { return [System.Numerics.BigInteger]::Zero }
  return [System.Numerics.BigInteger]::Divide(([System.Numerics.BigInteger]$bnbRes) * $script:E18, [System.Numerics.BigInteger]$tokRes)
}
function Fee-Inventory { $st = S; return (CQ $st.token "balanceOf(address)(uint256)" @($st.token)) }

# ---- forge / verification ---------------------------------------------------
## forge script against the fork, impersonated deployer, mainnet gas price.
## Returns @(exitCode, output).
function Run-Forge { param([string]$path, [switch]$Broadcast)
  Assert-LocalFork
  $gp = "$((S).gasPrice)"
  $bc = @(); if ($Broadcast) { $bc = @("--broadcast", "--slow") }
  $prev = $ErrorActionPreference; $ErrorActionPreference = "Continue"
  $out = forge script $path --rpc-url $script:RPC --unlocked --sender $script:DEPLOYER --legacy --with-gas-price $gp @bc 2>&1 | Out-String
  $c = $LASTEXITCODE; $ErrorActionPreference = $prev
  Get-Process forge -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
  Start-Sleep -Milliseconds 400
  return @($c, $out)
}
## Ledger rows for a forge broadcast, from its journal's receipts.
function Ledger-FromBroadcast { param([string]$scriptFile, [string]$step)
  $p = Join-Path $script:ROOT (Join-Path "broadcast" (Join-Path $scriptFile (Join-Path "56" "run-latest.json")))
  $j = Get-Content $p -Raw | ConvertFrom-Json
  $gasSum = [System.Numerics.BigInteger]::Zero; $costSum = [System.Numerics.BigInteger]::Zero; $n = 0
  foreach ($rc in @($j.receipts)) {
    if ("$($rc.status)" -ne "0x1") { throw "a $scriptFile receipt has status $($rc.status)" }
    $g = HexBI "$($rc.gasUsed)"; $pr = HexBI "$($rc.effectiveGasPrice)"
    Add-Ledger $step "deployer" "$scriptFile tx $n" $g $pr "$($rc.transactionHash)"
    $gasSum += $g; $costSum += ($g * $pr); $n++
  }
  return @{ count = $n; gas = $gasSum; cost = $costSum }
}
## The post-broadcast verification, exactly as the operator runs it.
function Run-Verify {
  Assert-LocalFork
  $so = Join-Path $env:TEMP "fork-verify-$PID.txt"
  $vf = '"' + (Join-Path $script:ROOT "script\verify-deploy.ps1") + '"'
  $verifyArgs = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $vf, "-Rpc", $script:RPC)
  $p = Start-Process powershell -ArgumentList $verifyArgs -NoNewWindow -Wait -PassThru -RedirectStandardOutput $so
  $text = if (Test-Path $so) { Get-Content $so -Raw } else { "" }
  Remove-Item $so -Force -ErrorAction SilentlyContinue
  return @($p.ExitCode, $text)
}
