# Level-1 campaign harness library. Dot-source from the repo root:
#   . .\script\campaign\lib.ps1
# Every runner call re-sources this file and reloads state.json -- no shell
# state survives between steps by design (crash resilience).

$ErrorActionPreference = "Stop"
$script:RPC  = "http://127.0.0.1:8545"
$script:FORK = "https://bsc-testnet.publicnode.com"
$script:ROUTER_ADDR = "0xD99D1c33F9fC3444f8101754aBC46c52416550D1"   # PancakeSwap V2, BSC testnet
$script:PIN  = 0            # resolved at runtime by Resolve-ForkBlock
$script:ROOT = (git rev-parse --show-toplevel)
$script:STATE = Join-Path $ROOT (Join-Path "script" (Join-Path "campaign" "state-$PID.json"))  # per-process: two runners can never contend
$script:LOG   = Join-Path $ROOT "TESTNET_L1_RESULTS.md"

# -- Anvil dev accounts (public dev mnemonic) -----------------------------
$script:Addr = [ordered]@{
  deployer = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"
  guardian = "0x70997970C51812dc3A010C7d01b50e0d17dc79C8"
  alice    = "0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC"
  bob      = "0x90F79bf6EB2c4f870365E785982E1f101E93b906"
  carol    = "0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65"
  team1    = "0x9965507D1a55bcC2695C58ba16FB37d819B0A4dc"
  team2    = "0x976EA74026E726554dB657fA54763abd0C3a0aa9"
  tp1      = "0x14dC79964da2C08b23698B3D3cc7Ca32193d9955"
  tp2      = "0x23618e81E3f5cdF7f54C3d65f7FBc0aBf5B21E8f"
  stranger = "0xa0Ee7A142d267C1f36714E4a8F75612F20a79720"
}
$script:Key = @{
  deployer = "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
  guardian = "0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d"
  alice    = "0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a"
  bob      = "0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6"
  carol    = "0x47e179ec197488593b187f80a00eb0da91f1b9d0b13f8733639f19c30a34926a"
  team1    = "0x8b3a350cf5c34c9194ca85829a2df0ec3153be0318b5e2d3348e872092edffba"
  team2    = "0x92db14e403b83dfe3df233f83dfa3a0d7096f21ca9b0d6d6b8d88b2b4ec1564e"
  tp1      = "0x4bbbf85ce3377467afe5d46f804f221813b2bb87f24d81f60f1fcdbf7cbf4356"
  tp2      = "0xdbda1821b80551c9d65939329250298aa3472ba22feea921c0cf5d620ea67b97"
  stranger = "0x2a871d0798f97d79848a013d4936a73bf4cc922c825d33c1cf7073dff6d409c6"
}
# Constant, keyless role addresses (never sign, never receive gas):
$script:MARKETING = "0x000000000000000000000000000000000000A001"
$script:TREASURY  = "0x000000000000000000000000000000000000a002"
$script:TP_SILENT = @("0x000000000000000000000000000000000000B003",
                     "0x000000000000000000000000000000000000B004",
                     "0x000000000000000000000000000000000000B005",
                     "0x000000000000000000000000000000000000B006")
$script:POOLSIM   = "0x000000000000000000000000000000000000C001"
$script:DEAD      = "0x000000000000000000000000000000000000dEaD"

# -- Old-token distribution model (wei) -- see the results log header ------
$script:E18 = [System.Numerics.BigInteger]::Pow(10,18)
function BW([string]$billions) {  # "213.56" billions -> wei BigInteger
  $parts = $billions.Split('.')
  $int = [System.Numerics.BigInteger]::Parse($parts[0]) * 1000000000 * $script:E18
  if ($parts.Count -gt 1) {
    $frac = $parts[1].PadRight(2,'0')
    $int += [System.Numerics.BigInteger]::Parse($frac) * 10000000 * $script:E18
  }
  return $int
}

# -- Anvil lifecycle ------------------------------------------------------
function Stop-Anvil {
  Get-Process anvil -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
  # A forge script left hanging from an earlier run keeps a stale nonce view
  # and blocks the next broadcast: clear it with the node.
  Get-Process forge -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
  Start-Sleep -Milliseconds 800
}
## Public endpoints prune state: a block that forks cleanly in the morning
## returns "state at block #N is pruned" a few hours later. The pin is
## therefore resolved once per sitting, cached in forkpin.txt, and refreshed
## automatically when the endpoint no longer serves it. Only the PancakeSwap
## periphery is inherited from the fork - every Daimon contract is deployed
## fresh in each run - so which recent block we pin to does not affect any
## result.
function Resolve-ForkBlock { param([switch]$Force)
  $pinFile = Join-Path $script:ROOT (Join-Path "script" (Join-Path "campaign" "forkpin.txt"))
  $prev = $ErrorActionPreference
  $ErrorActionPreference = "Continue"   # a pruned pin makes cast write to stderr
  try {
    if (-not $Force -and (Test-Path $pinFile)) {
      $cached = (Get-Content $pinFile -Raw).Trim()
      if ($cached -match "^\d+$") {
        $probe = (cast code $script:ROUTER_ADDR --block $cached --rpc-url $script:FORK 2>&1 | Out-String)
        if ($LASTEXITCODE -eq 0 -and $probe -match "^\s*0x[0-9a-fA-F]{20,}") { $script:PIN = [int]$cached; return $script:PIN }
      }
    }
    $latest = (cast block-number --rpc-url $script:FORK 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or -not ($latest -match "^\d+$")) { throw "cannot reach the fork endpoint: $latest" }
    $pin = [int]$latest - 20
    Set-Content -Path $pinFile -Value "$pin" -Encoding ascii
    $script:PIN = $pin
    return $pin
  } finally { $ErrorActionPreference = $prev }
}

function Start-CampaignNode {
  Stop-Anvil
  $nodeLog = Join-Path $script:ROOT "script\campaign\anvil.log"
  foreach ($attempt in 1..3) {
    $pin = Resolve-ForkBlock -Force:([bool]($attempt -gt 1))
    if (Test-Path $nodeLog) { Remove-Item $nodeLog -Force -ErrorAction SilentlyContinue }
    Start-Process anvil -ArgumentList "--fork-url",$script:FORK,"--fork-block-number","$pin","--port","8545","--silent" -WindowStyle Hidden -RedirectStandardError $nodeLog
    foreach ($i in 1..60) {
      Start-Sleep -Seconds 1
      try { $cid = cast chain-id --rpc-url $script:RPC 2>$null; if ($cid -eq "97") { Sanitize-Accounts; return } } catch {}
      if ((Test-Path $nodeLog) -and ((Get-Content $nodeLog -Raw) -match "pruned|error")) { break }
    }
    Write-Output "  .. anvil attempt $attempt failed (pin $pin), re-resolving"
    Stop-Anvil
  }
  $err = if (Test-Path $nodeLog) { (Get-Content $nodeLog -Raw) } else { "(no stderr captured)" }
  throw "anvil did not come up after 3 attempts. stderr: $err"
}

# -- cast wrappers --------------------------------------------------------
function CQ { param($to, $sig, [string[]]$callArgs = @())
  $r = cast call $to $sig @callArgs --rpc-url $script:RPC 2>&1
  if ($LASTEXITCODE -ne 0) { throw "cast call failed: $to $sig -> $r" }
  $v = ("$r" -split "\s+")[0]
  if ($v -match '^0x[0-9a-fA-F]+$' -and $v.Length -gt 42) { return [System.Numerics.BigInteger]::Parse($v.Substring(2), 'AllowHexSpecifier') }
  if ($v -match '^-?\d+$') { return [System.Numerics.BigInteger]::Parse($v) }
  return $v   # address / bool / string as text
}
function Send { param($who, $to, $sig, [string[]]$sendArgs = @(), [string]$value = "0", [switch]$NoInvariant)
  $extra = @(); if ($value -ne "0") { $extra += @("--value", $value) }
  # An UNEXPECTED revert must fail fast and loudly. Under
  # ErrorActionPreference=Stop, cast's stderr becomes a terminating native
  # error that can leave the runner wedged instead of throwing - so the call
  # is made with the preference relaxed and the outcome judged explicitly.
  $prev = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  $r = (cast send $to $sig @sendArgs --private-key $script:Key[$who] --rpc-url $script:RPC --json @extra 2>&1 | Out-String)
  $code = $LASTEXITCODE
  $ErrorActionPreference = $prev
  if ($code -ne 0) { throw "SEND FAILED [$who -> $to $sig]: $(($r -replace '\s+',' ').Trim())" }
  $j = $null
  try { $j = ($r | ConvertFrom-Json) } catch { throw "SEND: unparseable output [$who -> $to $sig]: $(($r -replace '\s+',' ').Trim())" }
  if ($j.status -ne "0x1") { throw "TX REVERTED [$who -> $to $sig]: $($j.transactionHash)" }
  if (-not $NoInvariant) { Assert-Invariants "$who -> $sig" }
  return $j.transactionHash
}
function SendRaw { param($who, $to, [string]$data, [string]$value = "0")
  $extra = @(); if ($value -ne "0") { $extra += @("--value", $value) }
  $r = cast send $to $data --private-key $script:Key[$who] --rpc-url $script:RPC --json @extra 2>&1
  if ($LASTEXITCODE -ne 0) { throw "SENDRAW FAILED: $r" }
  $j = ($r | Out-String | ConvertFrom-Json)
  if ($j.status -ne "0x1") { throw "TX REVERTED (raw): $($j.transactionHash)" }
  Assert-Invariants "raw send"
  return $j.transactionHash
}
function Expect-Revert { param($who, $to, $sig, [string[]]$revArgs = @(), [string]$errSig = "", [string]$value = "0")
  $extra = @(); if ($value -ne "0") { $extra += @("--value", $value) }
  # cast prints the revert reason on stderr and exits non-zero. With
  # $ErrorActionPreference = Stop that native stderr becomes a terminating
  # error, so an EXPECTED revert would kill the runner: relax it here only.
  $prev = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  $r = (cast send $to $sig @revArgs --private-key $script:Key[$who] --rpc-url $script:RPC --json @extra 2>&1 | Out-String)
  $code = $LASTEXITCODE
  $ErrorActionPreference = $prev
  if ($code -eq 0 -and $r -match '"status"\s*:\s*"0x1"') { throw "EXPECTED REVERT but tx succeeded: $to $sig" }
  $flat = ($r -replace "\s+", " ").Trim()
  if ($errSig -ne "") {
    $name = $errSig.Split("(")[0]
    if ($flat -match [regex]::Escape($name)) { return "reverted with $name" }
    $sel = (cast sig $errSig 2>$null)
    if ($sel -and ($flat -match [regex]::Escape("$sel".Substring(2)))) { return "reverted with $errSig" }
    $tail = $flat.Substring(0, [Math]::Min(140, $flat.Length))
    return "reverted, but NOT with $errSig (raw: $tail)"
  }
  return "reverted"
}
function RpcCall { param($method, [string[]]$rpcArgs = @())
  return cast rpc $method @rpcArgs --rpc-url $script:RPC 2>&1
}
function Warp { param([int]$seconds) RpcCall "evm_increaseTime" @("$seconds") | Out-Null; RpcCall "anvil_mine" @("1") | Out-Null }
function Mine { param([int]$n = 1) RpcCall "anvil_mine" @("$n") | Out-Null }
function Bal { param($addr) return [System.Numerics.BigInteger]::Parse(((cast balance $addr --rpc-url $script:RPC) -split "\s+")[0]) }

# -- state ----------------------------------------------------------------
function Save-State { param($obj) $obj | ConvertTo-Json -Depth 5 | Set-Content $script:STATE -Encoding utf8 }
function Load-State { if (Test-Path $script:STATE) { return Get-Content $script:STATE -Raw | ConvertFrom-Json } else { return $null } }

# -- the global invariant, checked after every step -----------------------
$script:InvariantCount = 0
function Assert-Invariants { param([string]$label = "")
  $st = Load-State
  if (-not $st -or -not $st.token) { return }   # pre-deploy steps
  $mkDmn = CQ $st.token "balanceOf(address)(uint256)" @($script:MARKETING)
  $mkNat = Bal $script:MARKETING
  $supply = CQ $st.token "totalSupply()(uint256)"
  $floor = [System.Numerics.BigInteger]::Parse("21000000000") * $script:E18
  if ($mkDmn -ne [System.Numerics.BigInteger]::Zero) { throw "GLOBAL INVARIANT VIOLATED at [$label]: marketing wallet DMN = $mkDmn" }
  if ("$mkNat" -ne "$($st.marketingNativeGenesis)") { throw "GLOBAL INVARIANT VIOLATED at [$label]: marketing native moved ($mkNat vs genesis $($st.marketingNativeGenesis))" }
  if ($supply -lt $floor) { throw "GLOBAL INVARIANT VIOLATED at [$label]: totalSupply $supply below floor" }
  $script:InvariantCount++
  $st.invariantChecks = [int]$st.invariantChecks + 1
  Save-State $st
}

# -- results log ----------------------------------------------------------
function Log-Line { param([string]$text)
  # A stalled runner from an earlier attempt can still hold the file open;
  # retry rather than dying on a transient lock.
  foreach ($try in 1..10) {
    try { Add-Content -Path $script:LOG -Value $text -Encoding utf8 -ErrorAction Stop; return } catch { Start-Sleep -Milliseconds 300 }
  }
  throw "could not write to the results log after 10 attempts"
}
function Log-Scenario { param([string]$id, [string]$title)
  Log-Line ""; Log-Line "### $id -- $title"; Log-Line ""
  Log-Line "| step | action | expected | observed | verdict |"
  Log-Line "|---|---|---|---|---|"
}
function Log-Step { param([string]$n, [string]$action, [string]$expected, [string]$observed, [string]$verdict = "PASS")
  Log-Line "| $n | $action | $expected | $observed | $verdict |"
}
function Log-Note { param([string]$text) Log-Line ""; Log-Line $text }

# -- old-token deploy + realistic distribution ----------------------------
function Deploy-OldToken {
  $supply = BW "1000.00"
  $r = forge create script/campaign/CampaignOldDaimon.sol:CampaignOldDaimon --private-key $script:Key.deployer --rpc-url $script:RPC --broadcast --json --constructor-args "$supply" $script:Addr.deployer 2>&1
  if ($LASTEXITCODE -ne 0) { throw "old-token deploy failed: $r" }
  # Same nonce hazard as the deploy script: a lingering forge process keeps a
  # stale nonce view and every cast send after it ends up queued behind a gap.
  Get-Process forge -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
  Start-Sleep -Milliseconds 300
  $old = (($r | Out-String) | ConvertFrom-Json).deployedTo
  # Owner exempts the distributor so the model lands EXACT balances.
  Send "deployer" $old "excludeFromFee(address)" @($script:Addr.deployer) -NoInvariant | Out-Null
  # Distribution (billions): team 213.56 x2 | tp1 76.90, tp2 75.418... x5 | pool 85.42 | dead 20.00 + contract 13.47
  Send "deployer" $old "transfer(address,uint256)" @($script:Addr.team1, (BW "213.56")) -NoInvariant | Out-Null
  Send "deployer" $old "transfer(address,uint256)" @($script:Addr.team2, (BW "213.56")) -NoInvariant | Out-Null
  Send "deployer" $old "transfer(address,uint256)" @($script:Addr.tp1,   (BW "76.90"))  -NoInvariant | Out-Null
  $tpShare = [System.Numerics.BigInteger]::Parse("75418") * [System.Numerics.BigInteger]::Pow(10,6) * $script:E18  # 75.418 B
  Send "deployer" $old "transfer(address,uint256)" @($script:Addr.tp2, "$tpShare") -NoInvariant | Out-Null
  foreach ($silent in $script:TP_SILENT) { Send "deployer" $old "transfer(address,uint256)" @($silent, "$tpShare") -NoInvariant | Out-Null }
  Send "deployer" $old "transfer(address,uint256)" @($script:POOLSIM, (BW "85.42")) -NoInvariant | Out-Null
  Send "deployer" $old "transfer(address,uint256)" @($script:DEAD,    (BW "20.00")) -NoInvariant | Out-Null
  Send "deployer" $old "transfer(address,uint256)" @($old,            (BW "13.47")) -NoInvariant | Out-Null
  return $old
}

# -- the real deploy under test -------------------------------------------
function Run-MainDeploy { param($oldToken, [switch]$SkipTreasuryPreflight)
  if (-not $SkipTreasuryPreflight) {
    Send "deployer" $oldToken "excludeFromFee(address)" @($script:TREASURY) -NoInvariant | Out-Null
  }
  $env:OLD_DAIMON = $oldToken
  $env:GUARDIAN_ADDRESS = $script:Addr.guardian
  $env:MARKETING_WALLET = $script:MARKETING
  $env:TREASURY_ADDRESS = $script:TREASURY
  $out = forge script script/Deploy.s.sol --rpc-url $script:RPC --broadcast --private-key $script:Key.deployer 2>&1 | Out-String
  if ($LASTEXITCODE -ne 0) { throw "DEPLOY FAILED:`n$out" }
  # Robust address extraction: the broadcast journal, by contract name.
  $bc = Get-Content (Join-Path $script:ROOT "broadcast\Deploy.s.sol\97\run-latest.json") -Raw | ConvertFrom-Json
  $by = @{}
  foreach ($tx in $bc.transactions) { if ($tx.transactionType -eq "CREATE") { $by[$tx.contractName] = $tx.contractAddress } }
  $token = $by["ERC1967Proxy"]
  $st = [ordered]@{
    old = $oldToken; token = $token; impl = $by["DaimonV2"]
    staking = $by["DaimonStaking"]; timelock = $by["DaimonTimelock"]
    governor = $by["DaimonGovernor"]; migration = $by["DaimonMigration"]
    pair = (CQ $token "uniswapV2Pair()(address)")
    marketingNativeGenesis = "$(Bal $script:MARKETING)"
    invariantChecks = 0
    deployOutTail = (($out -split "`r?`n" | Select-Object -Last 6) -join " | ")
  }
  Save-State $st
  # forge script can outlive its own broadcast; while it lingers it keeps a
  # nonce view of the deployer, and the cast sends that follow then open a
  # nonce gap which leaves every later transaction queued forever. Clear it.
  Get-Process forge -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
  Start-Sleep -Milliseconds 400
  Assert-Invariants "post-deploy"
  return (Load-State)
}

# -- shared post-deploy helpers -------------------------------------------
function S { return (Load-State) }

## Format wei as billions, 4 decimals -- for the results log.
function FmtB { param($wei)
  $b = [System.Numerics.BigInteger]$wei
  $den = [System.Numerics.BigInteger]::Parse("100000000000000") * 10000   # 1e18 * 1e... -> billions
  $den = $script:E18 * [System.Numerics.BigInteger]::Parse("1000000000")
  $whole = [System.Numerics.BigInteger]::Divide($b, $den)
  $rem = $b - ($whole * $den)
  $frac = [System.Numerics.BigInteger]::Divide($rem * 10000, $den)
  return "$whole.$($frac.ToString().PadLeft(4,'0')) B"
}
## Format wei as plain token units, 4 decimals.
function FmtT { param($wei)
  $b = [System.Numerics.BigInteger]$wei
  $neg = ($b -lt [System.Numerics.BigInteger]::Zero)
  if ($neg) { $b = -$b }
  $whole = [System.Numerics.BigInteger]::Divide($b, $script:E18)
  $rem = $b - ($whole * $script:E18)
  $frac = [System.Numerics.BigInteger]::Divide($rem * 10000, $script:E18)
  $s = "$whole.$($frac.ToString().PadLeft(4,'0'))"
  if ($neg) { return "-$s" } else { return $s }
}

## Migrate: approve the old token to Migration, then claim 1:1.
function Claim-Dmn { param($who, $amount)
  $st = S
  Send $who $st.old "approve(address,uint256)" @($st.migration, "$amount") -NoInvariant | Out-Null
  return (Send $who $st.migration "claim(uint256)" @("$amount"))
}

## Stake: approve DMN to staking, then stake with the given lock option.
function Stake-Dmn { param($who, $amount, [int]$optIdx)
  $st = S
  Send $who $st.token "approve(address,uint256)" @($st.staking, "$amount") | Out-Null
  return (Send $who $st.staking "stake(uint256,uint256)" @("$amount", "$optIdx"))
}

## Full campaign bootstrap: fresh forked node, old token + distribution,
## then the REAL Deploy.s.sol against that node.
function Bootstrap-Campaign { param([switch]$SkipTreasuryPreflight)
  Start-CampaignNode
  $old = Deploy-OldToken
  return (Run-MainDeploy $old -SkipTreasuryPreflight:$SkipTreasuryPreflight)
}

# -- governance helpers ---------------------------------------------------
## Create a proposal; returns its id. Mines a block first so the staker's
## checkpoint sits in a SEALED block before the proposal (#12 snapshot).
function Propose-Call { param($who, $target, [string]$data, [string]$desc, [string]$value = "0", [switch]$NoMine)
  $st = S
  if (-not $NoMine) { Mine 1 }
  Send $who $st.governor "propose(address,uint256,bytes,string)" @($target, $value, $data, $desc) | Out-Null
  $count = CQ $st.governor "proposalCount()(uint256)"
  return ($count - 1)
}
function Vote-Prop { param($who, $id, [int]$support = 1)
  $st = S
  return (Send $who $st.governor "castVote(uint256,uint8)" @("$id", "$support"))
}
function Queue-Prop { param($id)
  $st = S
  return (Send "stranger" $st.governor "queue(uint256)" @("$id"))
}
function Exec-Prop { param($id)
  $st = S
  return (Send "stranger" $st.governor "execute(uint256)" @("$id"))
}
function Prop-State { param($id)
  $st = S
  $n = CQ $st.governor "state(uint256)(uint8)" @("$id")
  $names = @("Pending","Active","Defeated","Succeeded","Queued","Executed","Canceled")
  return $names[[int]$n]
}
## Full happy-path governance cycle for a call, executed end to end.
function Govern { param($voter, $target, [string]$data, [string]$desc)
  $id = Propose-Call $voter $target $data $desc
  Warp (86400 + 60)                 # past VOTING_DELAY
  Vote-Prop $voter $id 1 | Out-Null
  Warp (5 * 86400 + 60)             # past VOTING_PERIOD
  Queue-Prop $id | Out-Null
  Warp (7 * 86400 + 60)             # past the timelock
  Exec-Prop $id | Out-Null
  return $id
}

# -- the operation id the Governor derives for a queued proposal ----------
## The Timelock operation id behind a queued proposal, derived exactly as the
## Governor derives it (the Timelock's own hashOperation is the authority).
function Op-Id { param($id)
  $st = S
  $target = Prop-Field $id 1
  $value  = Prop-Field $id 2
  $data   = Prop-Field $id 3
  $salt   = Prop-Field $id 15
  $zero = "0x0000000000000000000000000000000000000000000000000000000000000000"
  return (CQRaw $st.timelock "hashOperation(address,uint256,bytes,bytes32,bytes32)(bytes32)" @($target, $value, $data, $zero, $salt))
}

# -- liquidity (real PancakeSwap router on the fork) ----------------------
$script:ROUTER = "0xD99D1c33F9fC3444f8101754aBC46c52416550D1"
## Adds initial liquidity. -OnGross reproduces the WRONG pricing of #17
## (BNB computed on the amount SENT); default computes on what the pair
## ACTUALLY receives, net of the transfer fee.
function Add-InitialLiquidity { param($who, $dmnGross, $bnbForNet, [switch]$OnGross)
  $st = S
  Send $who $st.token "approve(address,uint256)" @($script:ROUTER, "$dmnGross") | Out-Null
  $deadline = "99999999999"
  $bnb = if ($OnGross) { $bnbForNet } else { $bnbForNet }
  Send $who $script:ROUTER "addLiquidityETH(address,uint256,uint256,uint256,address,uint256)" @(
    $st.token, "$dmnGross", "0", "0", $script:Addr[$who], $deadline) -value "$bnb" | Out-Null
  return (CQ $st.pair "getReserves()(uint112,uint112,uint32)")
}
## Reserves of the DMN/WBNB pair as [dmn, wbnb], whatever order the pair uses.
function Pair-Reserves {
  $st = S
  # cast appends a scientific-notation hint ("3800000000000000000 [3.8e18]"),
  # so only the FIRST token of each line is the actual number.
  $raw = (cast call $st.pair "getReserves()(uint112,uint112,uint32)" --rpc-url $script:RPC 2>&1 | Out-String)
  $nums = @()
  foreach ($line in ($raw -split "`n")) {
    $t = $line.Trim()
    if ($t -eq "") { continue }
    $first = ($t -split "\s+")[0]
    if ($first -match "^\d+$") { $nums += [System.Numerics.BigInteger]::Parse($first) }
  }
  $a = [System.Numerics.BigInteger]$nums[0]; $b = [System.Numerics.BigInteger]$nums[1]
  $t0 = CQRaw $st.pair "token0()(address)"
  if ("$t0".ToLower() -eq "$($st.token)".ToLower()) { return ,@($a, $b) } else { return ,@($b, $a) }
}
## The poke: 1 wei of DMN straight to the pair, from any address.
function Poke { param($who = "stranger")
  $st = S
  return (Send $who $st.token "transfer(address,uint256)" @($st.pair, "1"))
}

## Raw call: returns the first returned token as TEXT (bytes32, address, bool).
function CQRaw { param($to, $sig, [string[]]$callArgs = @())
  $r = cast call $to $sig @callArgs --rpc-url $script:RPC 2>&1
  if ($LASTEXITCODE -ne 0) { throw "cast call failed: $to $sig -> $r" }
  return (("$r" -split "\s+")[0]).Trim()
}

## Send from a keyless address by impersonating it (Anvil). Used for the
## modelled holders that exist only as constants - the campaign needs them
## to act without ever handing them a key.
function SendAs { param($from, $to, $sig, [string[]]$sendArgs = @(), [switch]$NoInvariant)
  RpcCall "anvil_impersonateAccount" @($from) | Out-Null
  RpcCall "anvil_setBalance" @($from, "0x56BC75E2D63100000") | Out-Null   # 100 ether of gas money
  $r = cast send $to $sig @sendArgs --from $from --unlocked --rpc-url $script:RPC --json 2>&1
  if ($LASTEXITCODE -ne 0) { throw "SENDAS FAILED [$from -> $to $sig]: $r" }
  $j = ($r | Out-String | ConvertFrom-Json)
  if ($j.status -ne "0x1") { throw "TX REVERTED [$from -> $to $sig]: $($j.transactionHash)" }
  RpcCall "anvil_stopImpersonatingAccount" @($from) | Out-Null
  if (-not $NoInvariant) { Assert-Invariants "impersonated $from -> $sig" }
  return $j.transactionHash
}
## Migrate everything a keyless modelled holder owns.
function Claim-DmnAs { param($from, $amount)
  $st = S
  SendAs $from $st.old "approve(address,uint256)" @($st.migration, "$amount") -NoInvariant | Out-Null
  return (SendAs $from $st.migration "claim(uint256)" @("$amount"))
}

## Opens the DMN/WBNB pool at 1 BNB = 1e9 DMN, pricing the BNB leg on what
## the pair ACTUALLY receives (the correct way, proved in B0). Returns the
## gross DMN sent.
function Setup-Pool { param($who = "team1", $grossBillions = "4.00")
  $st = S
  $gross = BW $grossBillions
  $tax = CQ $st.token "taxFee()(uint256)"; $liq = CQ $st.token "liquidityFee()(uint256)"
  $net = ($gross * (1000 - $tax - $liq)) / 1000
  $bnb = $net / [System.Numerics.BigInteger]::Parse("1000000000")
  Send $who $st.token "approve(address,uint256)" @($script:ROUTER, "$gross") | Out-Null
  Send $who $script:ROUTER "addLiquidityETH(address,uint256,uint256,uint256,address,uint256)" @(
    $st.token, "$gross", "0", "0", $script:Addr[$who], "99999999999") -value "$bnb" | Out-Null
  return $gross
}

## Sell DMN into the pool through the real router (fee-supporting variant).
function Sell-Dmn { param($who, $amount)
  $st = S
  Send $who $st.token "approve(address,uint256)" @($script:ROUTER, "$amount") | Out-Null
  $path = "[$($st.token),$(CQRaw $script:ROUTER 'WETH()(address)')]"
  return (Send $who $script:ROUTER "swapExactTokensForETHSupportingFeeOnTransferTokens(uint256,uint256,address[],address,uint256)" @(
    "$amount", "0", $path, $script:Addr[$who], "99999999999"))
}

## Fire a transaction without waiting for its receipt - needed to put
## several transactions into ONE block (automine off).
function SendAsync { param($who, $to, $sig, [string[]]$sendArgs = @())
  $r = cast send $to $sig @sendArgs --private-key $script:Key[$who] --rpc-url $script:RPC --async 2>&1
  if ($LASTEXITCODE -ne 0) { throw "ASYNC SEND FAILED [$who -> $to $sig]: $r" }
  return ("$r" -split "\s+")[0]
}
function Automine { param([bool]$on) RpcCall "evm_setAutomine" @("$($on.ToString().ToLower())") | Out-Null }
## The DMN fee inventory sitting in the token contract, not yet converted.
function Fee-Inventory { $st = S; return (CQ $st.token "balanceOf(address)(uint256)" @($st.token)) }

## The public dev-mnemonic accounts are NOT clean on a public testnet: on the
## forked chain every one of them carries an EIP-7702 delegation (0xef0100 +
## address, 23 bytes) to a sweeper that forwards any native balance it
## receives. Left in place it silently drains a role account the moment the
## router pays it - the campaign needs plain EOAs, so the delegation is
## cleared and the balance restored on the local fork only.
function Sanitize-Accounts {
  $all = @()
  foreach ($k in $script:Addr.Keys) { $all += $script:Addr[$k] }
  $all += $script:MARKETING; $all += $script:TREASURY; $all += $script:POOLSIM
  foreach ($s in $script:TP_SILENT) { $all += $s }
  foreach ($a in $all) {
    RpcCall "anvil_setCode" @($a, "0x") | Out-Null
  }
  # Role signers get gas money; the keyless constants (marketing, treasury)
  # are deliberately left at zero so the global invariant stays meaningful.
  foreach ($k in $script:Addr.Keys) {
    RpcCall "anvil_setBalance" @($script:Addr[$k], "0x21E19E0C9BAB2400000") | Out-Null  # 10000 ether
  }
}

## Read one field of the Proposal struct by index.
## 0 proposer, 1 target, 2 value, 3 data, 4 description, 5 snapshotBlock,
## 6 snapshotTotalVotingPower, 7 voteStart, 8 voteEnd, 9 for, 10 against,
## 11 abstain, 12 canceled, 13 executed, 14 queued, 15 salt, 16 quorumBps.
function Prop-Field { param($id, [int]$idx)
  $st = S
  $sig = "proposals(uint256)(address,address,uint256,bytes,string,uint256,uint256,uint256,uint256,uint256,uint256,uint256,bool,bool,bool,bytes32,uint256)"
  $r = (cast call $st.governor $sig "$id" --rpc-url $script:RPC 2>&1 | Out-String)
  $lines = @()
  foreach ($l in ($r -split "`n")) { $t = $l.Trim(); if ($t -ne "") { $lines += $t } }
  return (($lines[$idx] -split "\s+")[0]).Trim()
}
function Prop-Num { param($id, [int]$idx) return [System.Numerics.BigInteger]::Parse((Prop-Field $id $idx)) }

## Plain native transfer: cast wants no function signature at all here.
function SendValue { param($who, $to, [string]$value)
  $r = cast send $to --value $value --private-key $script:Key[$who] --rpc-url $script:RPC --json 2>&1
  if ($LASTEXITCODE -ne 0) { throw "SENDVALUE FAILED [$who -> $to]: $r" }
  $j = ($r | Out-String | ConvertFrom-Json)
  if ($j.status -ne "0x1") { throw "TX REVERTED [$who -> $to value]: $($j.transactionHash)" }
  Assert-Invariants "$who -> value"
  return $j.transactionHash
}
