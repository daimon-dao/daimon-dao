# Chapel Level-2 harness -- REAL chain, REAL keys, REAL time.
# Differences from the Level-1 (anvil) harness, all deliberate:
#   - no impersonation, no warps, no automine: every action is a signed tx
#     from an encrypted keystore, and time passes at one second per second;
#   - signing goes through `cast --account <keystore> --password-file <pf>`.
#     The keystore names and the password-file path live in
#     script/chapel/keystore-map.json, which is GITIGNORED: no key, no
#     password and no password PATH ever enters the repository or the log;
#   - every state-changing step records its tx hash in the results log;
#   - the global invariant (marketing wallet received nothing, ever) is
#     asserted programmatically after every send, as at Level 1.
$ErrorActionPreference = "Stop"
$script:RPC  = "https://bsc-testnet.publicnode.com"
$script:ROOT = (git rev-parse --show-toplevel)
$script:LOG  = Join-Path $ROOT "CHAPEL_L2_RESULTS.md"
$script:STATE = Join-Path $ROOT (Join-Path "script" (Join-Path "chapel" "state.json"))

# Role -> address (generated fresh by the operator, code==0x verified and
# recorded in the log before any funding was used).
$script:Addr = @{
  deployer = "0x052bB2834d292d078cf686F5f4BB2bb55E424943"
  guardian = "0x74D6140C874E0C9142b8312eDA8175B3c447a0F2"
  staker1  = "0xfbcE9e13C309549c82B0775C8587E3470f2837b0"
  staker2  = "0x36E3A9f60AD6e89835Ee0f3a4b8BC9283cFA83d1"
  staker3  = "0xbb843DFe3dec6D7dFc4Ef194A1a9BDc7A07eac84"
  holder1  = "0x583982463dA108879566868506Cba32E7b023576"
  holder2  = "0x66332d032b4F9583A4D85FB2b97B93F8311A39F2"
  holder3  = "0xD7ca3011eB7Caae4A76c245c93FaAc56A7F58DaE"
  stranger = "0x05Eb589Cba778FdFeE6bf2Dc0C1EFd32b48006e2"
}
$script:MARKETING = "0x000000000000000000000000000000000000A001"  # keyless, code-free, zero forever
$script:DEAD = "0x000000000000000000000000000000000000dEaD"

# Keystore names + password file: OUTSIDE the repo's history.
# script/chapel/keystore-map.json format:
#   { "passwordFile": "C:\\...\\pf.txt",
#     "accounts": { "deployer": "chapel-deployer", ... } }
$script:KS = $null
function Load-Keystores {
  $p = Join-Path $script:ROOT (Join-Path "script" (Join-Path "chapel" "keystore-map.json"))
  if (-not (Test-Path $p)) { throw "keystore-map.json missing: ask the operator for keystore names (never for keys)" }
  $script:KS = Get-Content $p -Raw | ConvertFrom-Json
  if (-not (Test-Path $script:KS.passwordFile)) { throw "password file not found at the configured path" }
}

$script:E18 = [System.Numerics.BigInteger]::Pow(10, 18)
function BW { param([string]$b) return ([System.Numerics.BigInteger]([decimal]$b * 10000) * ($script:E18 / 10000)) }
function FmtB { param($wei)
  $b = [System.Numerics.BigInteger]$wei
  $bn = $script:E18 * 1000000000
  $w = [System.Numerics.BigInteger]::Divide($b, $bn)
  $r = [System.Numerics.BigInteger]::Divide(($b - ($w * $bn)) * 10000, $bn)
  return "$w.$($r.ToString().PadLeft(4,'0')) B"
}
function FmtT { param($wei)
  $b = [System.Numerics.BigInteger]$wei
  $neg = ($b -lt [System.Numerics.BigInteger]::Zero)
  if ($neg) { $b = -$b }
  $w = [System.Numerics.BigInteger]::Divide($b, $script:E18)
  $r = [System.Numerics.BigInteger]::Divide(($b - ($w * $script:E18)) * 10000, $script:E18)
  $s = "$w.$($r.ToString().PadLeft(4,'0'))"
  if ($neg) { return "-$s" } else { return $s }
}

function CQRaw { param($to, $sig, [string[]]$callArgs = @())
  $prev = $ErrorActionPreference; $ErrorActionPreference = "Continue"
  $r = (cast call $to $sig @callArgs --rpc-url $script:RPC 2>&1 | Out-String)
  $c = $LASTEXITCODE; $ErrorActionPreference = $prev
  if ($c -ne 0) { throw "CALL FAILED [$to $sig]: $(($r -replace '\s+',' ').Trim())" }
  foreach ($l in ($r -split "`n")) { $t = $l.Trim(); if ($t -ne "") { return ($t -split "\s+")[0] } }
  throw "CALL empty [$to $sig]"
}
function CQ { param($to, $sig, [string[]]$callArgs = @()) return [System.Numerics.BigInteger]::Parse((CQRaw $to $sig $callArgs)) }
function Bal { param($addr) return [System.Numerics.BigInteger]::Parse((cast balance $addr --rpc-url $script:RPC)) }

## Signed send from a role. Returns @{ hash; gasUsed }. A transport failure
## throws; an on-chain revert throws; nothing is ever retried silently.
function Send { param($who, $to, $sig, [string[]]$sendArgs = @(), [string]$value = "0", [switch]$NoInvariant)
  if ($null -eq $script:KS) { Load-Keystores }
  $ks = $script:KS.accounts.$who
  if (-not $ks) { throw "no keystore mapped for role '$who'" }
  $extra = @(); if ($value -ne "0") { $extra += @("--value", $value) }
  $prev = $ErrorActionPreference; $ErrorActionPreference = "Continue"
  $r = (cast send $to $sig @sendArgs --account $ks --password-file $script:KS.passwordFile --rpc-url $script:RPC --json @extra 2>&1 | Out-String)
  $c = $LASTEXITCODE; $ErrorActionPreference = $prev
  if ($c -ne 0) { throw "SEND FAILED [$who -> $to $sig]: $(($r -replace '\s+',' ').Trim())" }
  $j = $r | ConvertFrom-Json
  if ($j.status -ne "0x1") { throw "TX REVERTED [$who -> $to $sig]: $($j.transactionHash)" }
  if (-not $NoInvariant) { Assert-Invariants "$who -> $sig" }
  return @{ hash = $j.transactionHash; gasUsed = [System.Numerics.BigInteger]::Parse($j.gasUsed.Substring(2), 'AllowHexSpecifier') }
}
function SendValue { param($who, $to, [string]$value)
  if ($null -eq $script:KS) { Load-Keystores }
  $ks = $script:KS.accounts.$who
  $prev = $ErrorActionPreference; $ErrorActionPreference = "Continue"
  $r = (cast send $to --value $value --account $ks --password-file $script:KS.passwordFile --rpc-url $script:RPC --json 2>&1 | Out-String)
  $c = $LASTEXITCODE; $ErrorActionPreference = $prev
  if ($c -ne 0) { throw "SENDVALUE FAILED [$who -> $to]: $(($r -replace '\s+',' ').Trim())" }
  $j = $r | ConvertFrom-Json
  if ($j.status -ne "0x1") { throw "TX REVERTED [$who value]: $($j.transactionHash)" }
  Assert-Invariants "$who -> value"
  return @{ hash = $j.transactionHash; gasUsed = [System.Numerics.BigInteger]::Parse($j.gasUsed.Substring(2), 'AllowHexSpecifier') }
}
function Expect-Revert { param($who, $to, $sig, [string[]]$sendArgs = @(), [string]$errSig = "")
  if ($null -eq $script:KS) { Load-Keystores }
  $ks = $script:KS.accounts.$who
  $prev = $ErrorActionPreference; $ErrorActionPreference = "Continue"
  $r = (cast send $to $sig @sendArgs --account $ks --password-file $script:KS.passwordFile --rpc-url $script:RPC --json 2>&1 | Out-String)
  $c = $LASTEXITCODE; $ErrorActionPreference = $prev
  if ($c -eq 0) {
    $j = $r | ConvertFrom-Json
    if ($j.status -eq "0x1") { return "DID-NOT-REVERT ($($j.transactionHash))" }
  }
  if ($errSig -ne "") {
    $name = $errSig -replace "\(\)$", ""
    $sel = (cast sig $errSig 2>$null)
    if ($r -match [regex]::Escape($name)) { return "reverted with $name" }
    if ($sel -and $r -match [regex]::Escape($sel.Substring(0, 10))) { return "reverted with $name" }
    return "reverted (different reason): $(($r -replace '\s+',' ').Trim().Substring(0, [Math]::Min(120, $r.Trim().Length)))"
  }
  return "reverted"
}

## Global invariant, as at Level 1: the marketing wallet has received
## NOTHING, ever -- DMN zero, native zero (it started at zero and is keyless).
function Assert-Invariants { param([string]$context)
  $st = Load-State
  if ($st -and $st.token) {
    $mk = CQ $st.token "balanceOf(address)(uint256)" @($script:MARKETING)
    if ($mk -ne 0) { throw "INVARIANT VIOLATED [$context]: marketing wallet holds $mk DMN" }
  }
  $nat = Bal $script:MARKETING
  if ($nat -ne 0) { throw "INVARIANT VIOLATED [$context]: marketing wallet native balance $nat" }
  if ($st) {
    $st.invariantChecks = [int]$st.invariantChecks + 1
    Save-State $st
  }
}
function Save-State { param($obj) $obj | ConvertTo-Json -Depth 5 | Set-Content $script:STATE -Encoding utf8 }
function Load-State { if (Test-Path $script:STATE) { return (Get-Content $script:STATE -Raw | ConvertFrom-Json) } else { return $null } }
function S { return Load-State }

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
function Log-Step { param($id, $action, $expected, $observed, $tx, $verdict)
  $utc = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd HH:mm")
  Log-Line "| $id | $action | $expected | $observed ($utc UTC) | $tx | $verdict |"
  if ($verdict -eq "DEVIATION") { Write-Output "!! DEVIATION at $id" }
}
function Log-Note { param($text) Log-Line ""; Log-Line "> $text" }
