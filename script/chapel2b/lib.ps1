# Level-2b Chapel harness -- REAL chain (BSC Chapel, id 97), REAL keystores,
# REAL time. Derived from script/chapel/lib.ps1 (Level 2); what changed:
#   - TWO signing roles mirror mainnet: `deployer` (the two phases, the
#     verification, nothing else between them) and `oldowner` (owner of the
#     CampaignOldDaimon mock: liquidity, LP to the Timelock, 11a/11b). Two
#     campaign roles do the rest: `holder` (the non-owner claimant, the
#     staker, the proposer) and `stranger` (the test sell and the poke).
#     The guardian is the test Safe, which never signs through this harness.
#   - the marketing wallet IS the Timelock (H0.1), so the Level-2 keyless
#     sentinel is gone. The global invariant of this level: the Timelock has
#     received NO BNB and NO DMN from the token -- asserted after every send
#     (share 1000: the marketing branch is never entered). H3 flips it on
#     purpose, in a later sitting, with a config change recorded in the log.
#   - the RPC is checked to serve chain 97 at load: this harness refuses to
#     start against anything else. No mainnet RPC anywhere in this file.
#   - keystore names, the password-file path AND the role addresses live in
#     script/chapel2b/keystore-map.json (gitignored): no key, no password and
#     no password PATH ever enters the repository or the log.
$ErrorActionPreference = "Stop"
$script:RPC  = "https://bsc-testnet.publicnode.com"
$script:ROOT = (git rev-parse --show-toplevel)
$script:LOG  = Join-Path $ROOT (Join-Path "docs" "CHAPEL_2B_RESULTS.md")
# StatePath, not STATE: PowerShell variable names are case-insensitive and a
# runner assigning $state (H3a, 2026-09-14: "$state = Prop-State ...")
# overwrote the library's state-file path with the word "Pending". Same
# lesson as AddrBook at Level 2; the name is deliberately one no scenario
# would use.
$script:StatePath = Join-Path $ROOT (Join-Path "script" (Join-Path "chapel2b" "state.json"))
$script:ROUTER = "0xD99D1c33F9fC3444f8101754aBC46c52416550D1"   # PancakeSwap V2, BSC testnet
$script:GUARDIAN = "0x4253f80666E48a04CAbE4966Aa63035Dbb4f104F" # the test Safe (2 of 3)
$script:DEAD = "0x000000000000000000000000000000000000dEaD"
# The opening price parameter (H1 step 5b): the mainnet DMX price read on
# 2026-09-10 from the DMX pool, 4.69e-10 BNB per token = 469,000,000 wei
# per whole token (1e18 base units). On mainnet the script reads it live.
$script:PRICE_WEI_PER_TOKEN = [System.Numerics.BigInteger]::Parse("469000000")
$script:PRICE_LABEL = "4.69e-10 BNB/token (read 2026-09-10 from the DMX pool)"

# Refuse anything but Chapel, before any other call.
$prevEap = $ErrorActionPreference; $ErrorActionPreference = "Continue"
$script:CHAIN = (cast chain-id --rpc-url $script:RPC 2>&1 | Out-String).Trim()
$ErrorActionPreference = $prevEap
if ($script:CHAIN -ne "97") { throw "REFUSED: the RPC serves chain '$($script:CHAIN)', this harness runs on BSC Chapel (97) only" }

# Role -> address, filled from the keystore map (Load-Keystores). The name
# AddrBook is deliberately unusual: PowerShell variable names are
# case-insensitive and a scenario assigning $addr would overwrite $Addr.
$script:AddrBook = @{}
$script:KsMap = $null
function Load-Keystores {
  $p = Join-Path $script:ROOT (Join-Path "script" (Join-Path "chapel2b" "keystore-map.json"))
  if (-not (Test-Path $p)) { throw "keystore-map.json missing: ask the operator for keystore names and role addresses (never for keys)" }
  $script:KsMap = Get-Content $p -Raw | ConvertFrom-Json
  if (-not (Test-Path $script:KsMap.passwordFile)) { throw "password file not found at the configured path" }
  foreach ($role in @("deployer", "oldowner", "holder", "stranger")) {
    $e = $script:KsMap.accounts.$role
    if (-not $e -or -not $e.keystore -or -not $e.address) { throw "keystore-map.json: role '$role' needs { keystore, address }" }
    $script:AddrBook[$role] = "$($e.address)"
  }
}
function Ks { param($who) if ($null -eq $script:KsMap) { Load-Keystores }; $e = $script:KsMap.accounts.$who; if (-not $e) { throw "no keystore mapped for role '$who'" }; return $e.keystore }
function Pf { if ($null -eq $script:KsMap) { Load-Keystores }; return $script:KsMap.passwordFile }

$script:E18 = [System.Numerics.BigInteger]::Pow(10, 18)
$script:E9  = [System.Numerics.BigInteger]::Parse("1000000000")
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
function FmtT { param($wei)
  $b = [System.Numerics.BigInteger]$wei
  $neg = ($b -lt [System.Numerics.BigInteger]::Zero); if ($neg) { $b = -$b }
  $w = [System.Numerics.BigInteger]::Divide($b, $script:E18)
  $r = [System.Numerics.BigInteger]::Divide(($b - ($w * $script:E18)) * 10000, $script:E18)
  $s = "$w.$($r.ToString().PadLeft(4,'0'))"
  if ($neg) { return "-$s" } else { return $s }
}
## Ceiling division on BigIntegers.
function CeilDiv { param($n, $d)
  $q = [System.Numerics.BigInteger]::Divide($n, $d)
  if (($q * $d) -ne $n) { $q = $q + [System.Numerics.BigInteger]::One }
  return $q
}
## The DMN amount the pair actually receives from a taxed transfer of
## `gross`, computed exactly as the token computes it (_getValues: two
## floor divisions out of 1000).
function NetOfGross { param($gross, $taxFee, $liquidityFee)
  $g = [System.Numerics.BigInteger]$gross
  $tFee = [System.Numerics.BigInteger]::Divide($g * $taxFee, 1000)
  $tLiq = [System.Numerics.BigInteger]::Divide($g * $liquidityFee, 1000)
  return ($g - $tFee - $tLiq)
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
function Bal { param($addr) return [System.Numerics.BigInteger]::Parse(((cast balance $addr --rpc-url $script:RPC) -split "\s+")[0]) }
function Nonce { param($addr) return [int]((cast nonce $addr --rpc-url $script:RPC | Out-String).Trim()) }
function BlockNumber { return [long]((cast block-number --rpc-url $script:RPC | Out-String).Trim()) }
function Code-Len { param($addr) $prev = $ErrorActionPreference; $ErrorActionPreference = "Continue"; $c = (cast code $addr --rpc-url $script:RPC 2>&1 | Out-String).Trim(); $ErrorActionPreference = $prev; return $c.Length }

## Signed send from a role. Returns @{ hash; gasUsed; block }. A transport
## failure throws; an on-chain revert throws; nothing is ever retried
## silently. The 2b invariant is asserted after every send unless the
## caller says -NoInvariant (pre-deploy steps).
function Send { param($who, $to, $sig, [string[]]$sendArgs = @(), [string]$value = "0", [switch]$NoInvariant)
  $ks = Ks $who; $pf = Pf
  $extra = @(); if ($value -ne "0") { $extra += @("--value", $value) }
  $prev = $ErrorActionPreference; $ErrorActionPreference = "Continue"
  $r = (cast send $to $sig @sendArgs --account $ks --password-file $pf --rpc-url $script:RPC --json @extra 2>&1 | Out-String)
  $c = $LASTEXITCODE; $ErrorActionPreference = $prev
  if ($c -ne 0) { throw "SEND FAILED [$who -> $to $sig]: $(($r -replace '\s+',' ').Trim())" }
  $j = $r | ConvertFrom-Json
  if ($j.status -ne "0x1") { throw "TX REVERTED [$who -> $to $sig]: $($j.transactionHash)" }
  if (-not $NoInvariant) { Assert-Invariants "$who -> $sig" }
  return @{ hash = $j.transactionHash
            gasUsed = [System.Numerics.BigInteger]::Parse("0" + $j.gasUsed.Substring(2), "AllowHexSpecifier")
            block = [System.Numerics.BigInteger]::Parse("0" + $j.blockNumber.Substring(2), "AllowHexSpecifier") }
}
## A send that is EXPECTED to be refused. cast estimates gas first, so a
## refused call never reaches the chain: no transaction, no nonce moved.
function Expect-Revert { param($who, $to, $sig, [string[]]$sendArgs = @(), [string]$errSig = "")
  $ks = Ks $who; $pf = Pf
  $prev = $ErrorActionPreference; $ErrorActionPreference = "Continue"
  $r = (cast send $to $sig @sendArgs --account $ks --password-file $pf --rpc-url $script:RPC --json 2>&1 | Out-String)
  $c = $LASTEXITCODE; $ErrorActionPreference = $prev
  if ($c -eq 0) {
    $j = $r | ConvertFrom-Json
    if ($j.status -eq "0x1") { return "DID-NOT-REVERT ($($j.transactionHash))" }
  }
  # cast's stderr arrives as ErrorRecords that Out-String wraps at the
  # console width, so a revert string can be split across lines anywhere
  # (H2.2, 2026-09-14: "Transfer amount exceeds the maxTxAmount." was
  # returned by the chain and missed by the matcher). Match on the
  # whitespace-flattened text.
  $flat = ($r -replace '\s+', ' ').Trim()
  if ($errSig -ne "") {
    $name = $errSig -replace "\(\)$", ""
    $sel = ""
    if ($errSig -match "^\w+\(.*\)$") { $sel = (cast sig $errSig 2>$null) }
    if ($flat -match [regex]::Escape($name)) { return "reverted with $name" }
    if ($sel -and $flat -match [regex]::Escape($sel.Substring(0, 10))) { return "reverted with $name" }
    return "reverted (different reason): $($flat.Substring(0, [Math]::Min(160, $flat.Length)))"
  }
  return "reverted"
}

## The 2b global invariant: the Timelock -- marketing wallet AND treasury
## -- has received nothing from the token: zero native, zero DMN. Its
## predecessor-token balance grows with every claim (that is the treasury
## working) and its LP balance is set by step 6: neither is a token
## payout. Counted in the state file; reported at closing.
function Assert-Invariants { param([string]$context)
  $st = Load-State
  if (-not $st -or -not $st.timelock) { return }
  $nat = Bal $st.timelock
  if ($nat -ne 0) { throw "INVARIANT VIOLATED [$context]: the Timelock holds $nat wei of native -- BNB reached the treasury from the token with share 1000" }
  $dmn = CQ $st.token "balanceOf(address)(uint256)" @($st.timelock)
  if ($dmn -ne 0) { throw "INVARIANT VIOLATED [$context]: the Timelock holds $dmn wei of DMN" }
  $st.invariantChecks = [int]$st.invariantChecks + 1
  Save-State $st
}
## The invariant counter lives in the file, not in any runner's copy: a
## runner saves the object it loaded at its start, so without this merge
## its final Save-State would clobber the count Assert-Invariants advanced
## meanwhile (Day 1, 2026-09-14: the file said 6 where 21 checks had run;
## reconstructed from the runners' code and recorded in the journal).
function Save-State { param($obj)
  if (Test-Path $script:StatePath) {
    try {
      $onDisk = Get-Content $script:StatePath -Raw | ConvertFrom-Json
      if ($onDisk -and [int]$onDisk.invariantChecks -gt [int]$obj.invariantChecks) {
        $obj | Add-Member -NotePropertyName invariantChecks -NotePropertyValue ([int]$onDisk.invariantChecks) -Force
      }
    } catch {}
  }
  $obj | ConvertTo-Json -Depth 5 | Set-Content $script:StatePath -Encoding utf8
}
function Load-State { if (Test-Path $script:StatePath) { return (Get-Content $script:StatePath -Raw | ConvertFrom-Json) } else { return $null } }
function S { return Load-State }
function Set-StateField { param($name, $value)
  $st = Load-State
  if ($null -eq $st) { $st = [pscustomobject]@{} }
  $st | Add-Member -NotePropertyName $name -NotePropertyValue $value -Force
  Save-State $st
}

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
function Log-Block { param([string]$title, [string]$text, [string]$fence = "")
  Log-Line ""; Log-Line $title; Log-Line ""; Log-Line ('```' + $fence)
  foreach ($l in ($text -split "`r?`n")) { Log-Line ($l.TrimEnd()) }
  Log-Line '```'
}

## Reserves of the DMN/WBNB pair as [dmn, wbnb], whatever order the pair uses.
function Pair-Reserves {
  $st = S
  $raw = (cast call $st.pair "getReserves()(uint112,uint112,uint32)" --rpc-url $script:RPC 2>&1 | Out-String)
  $nums = @()
  foreach ($line in ($raw -split "`n")) {
    $t = $line.Trim(); if ($t -eq "") { continue }
    $first = ($t -split "\s+")[0]
    if ($first -match "^\d+$") { $nums += [System.Numerics.BigInteger]::Parse($first) }
  }
  $a = [System.Numerics.BigInteger]$nums[0]; $b = [System.Numerics.BigInteger]$nums[1]
  $t0 = CQRaw $st.pair "token0()(address)"
  if ("$t0".ToLower() -eq "$($st.token)".ToLower()) { return ,@($a, $b) } else { return ,@($b, $a) }
}
## Price of one whole DMN in wei of BNB, from reserves: bnb * 1e18 / dmn.
function Price-WeiPerToken { param($dmnRes, $bnbRes)
  if ($dmnRes -eq 0) { return [System.Numerics.BigInteger]::Zero }
  return [System.Numerics.BigInteger]::Divide(([System.Numerics.BigInteger]$bnbRes) * $script:E18, [System.Numerics.BigInteger]$dmnRes)
}
## Basis points of (a - b) / a, signed, for a price move.
function MoveBps { param($before, $after)
  if ($before -eq 0) { return 0 }
  return [System.Numerics.BigInteger]::Divide((([System.Numerics.BigInteger]$before) - ([System.Numerics.BigInteger]$after)) * 10000, [System.Numerics.BigInteger]$before)
}
function Fee-Inventory { $st = S; return (CQ $st.token "balanceOf(address)(uint256)" @($st.token)) }
## Migrate: approve the predecessor to the Migration, then claim 1:1.
function Claim-Dmn { param($who, $amount, [switch]$NoInvariant)
  $st = S
  Send $who $st.old "approve(address,uint256)" @($st.migration, "$amount") -NoInvariant | Out-Null
  return (Send $who $st.migration "claim(uint256)" @("$amount") -NoInvariant:$NoInvariant)
}
## The post-broadcast verification, run as the operator runs it (a nested
## powershell, as at Level 2). Returns @(exitCode, fullOutput).
function Run-Verify {
  $so = Join-Path $env:TEMP "chapel2b-verify-$PID.txt"
  $vf = '"' + (Join-Path $script:ROOT "script\verify-deploy.ps1") + '"'
  $verifyArgs = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $vf, "-Rpc", $script:RPC)
  $p = Start-Process powershell -ArgumentList $verifyArgs -NoNewWindow -Wait -PassThru -RedirectStandardOutput $so
  $text = if (Test-Path $so) { Get-Content $so -Raw } else { "" }
  Remove-Item $so -Force -ErrorAction SilentlyContinue
  return @($p.ExitCode, $text)
}
## forge script wrapper: returns @(exitCode, output). Kills the forge
## process afterwards (a lingering one keeps a stale nonce view).
function Run-ForgeScript { param([string]$path, [string]$who, [switch]$Broadcast)
  $ks = Ks $who; $pf = Pf
  $bc = @(); if ($Broadcast) { $bc = @("--broadcast", "--slow") }
  $prev = $ErrorActionPreference; $ErrorActionPreference = "Continue"
  $out = forge script $path --rpc-url $script:RPC @bc --account $ks --password-file $pf 2>&1 | Out-String
  $c = $LASTEXITCODE; $ErrorActionPreference = $prev
  Get-Process forge -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
  Start-Sleep -Milliseconds 400
  return @($c, $out)
}
## Read one field of the Governor's Proposal struct by index.
## 0 proposer, 1 target, 2 value, 3 data, 4 description, 5 snapshotBlock,
## 6 snapshotTotalVotingPower, 7 voteStart, 8 voteEnd, 9 for, 10 against,
## 11 abstain, 12 canceled, 13 executed, 14 queued, 15 salt, 16 quorumBps.
function Prop-Field { param($id, [int]$idx)
  $st = S
  $to = "$($st.governor)"
  if (-not ($to -match "^0x[0-9a-fA-F]{40}$")) { throw "Prop-Field: no governor in the state file ('$to')" }
  $sig = "proposals(uint256)(address,address,uint256,bytes,string,uint256,uint256,uint256,uint256,uint256,uint256,uint256,bool,bool,bool,bytes32,uint256)"
  $prev = $ErrorActionPreference; $ErrorActionPreference = "Continue"
  $r = (cast call $to $sig "$id" --rpc-url $script:RPC 2>&1 | Out-String)
  $c = $LASTEXITCODE; $ErrorActionPreference = $prev
  if ($c -ne 0) { throw "Prop-Field FAILED [$to id=$id]: $(($r -replace '\s+',' ').Trim())" }
  $lines = @()
  foreach ($l in ($r -split "`n")) { $t = $l.Trim(); if ($t -ne "") { $lines += $t } }
  return (($lines[$idx] -split "\s+")[0]).Trim()
}
function Prop-State { param($id)
  $st = S
  $n = CQ $st.governor "state(uint256)(uint8)" @("$id")
  $names = @("Pending","Active","Defeated","Succeeded","Queued","Executed","Canceled")
  return $names[[int]$n]
}
