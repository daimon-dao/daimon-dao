# READ-ONLY: the step-5b numbers from live state, with the arithmetic the
# fork runs used (launch-day.ps1, row F5a.3). Sends nothing, needs no key.
#   powershell -File script/fork/size-liquidity.ps1 -Rpc <url> [-Token <DMN proxy>]
# Without -Token (before phase 1) the DMN parameters are the deploy values
# phase 2 asserts: maxTxAmount 5B, taxFee 10, liquidityFee 30 (per mille).
param([Parameter(Mandatory = $true)][string]$Rpc, [string]$Token = "")
$ErrorActionPreference = "Stop"
if (-not (Get-Command cast -ErrorAction SilentlyContinue)) { $env:PATH = (Join-Path $HOME ".foundry\bin") + ";" + $env:PATH }
$DMX = "0x36EbA94407B53c631eE822C219e94580fadd67c7"
$POOL = "0xB24916823C61Ee6272448209174F75fAfD297B82"
$OWNER = "0xF8EC459CAEaF1052b64B38BDD67290B0c132B0Ae"
$E18 = [System.Numerics.BigInteger]::Pow(10, 18)
$MILLE = [System.Numerics.BigInteger]::Parse("1000000000000000")
$RESERVE = [System.Numerics.BigInteger]::Parse("2000000000000000")
function N { param($s) return [System.Numerics.BigInteger]::Parse(("$s".Trim() -split "\s+")[0]) }
function C { param($to, $sig, [string[]]$a = @()) return (N ((cast call $to $sig @a --rpc-url $Rpc | Select-Object -First 1))) }
function Net { param($g, $t, $l) return ($g - [System.Numerics.BigInteger]::Divide($g * $t, 1000) - [System.Numerics.BigInteger]::Divide($g * $l, 1000)) }
function T { param($w) $w = [System.Numerics.BigInteger]$w; return "$([System.Numerics.BigInteger]::Divide($w, $E18)).$(([System.Numerics.BigInteger]::Divide([System.Numerics.BigInteger]::Remainder($w, $E18) * 1000000, $E18)).ToString().PadLeft(6,'0'))" }

$chain = (cast chain-id --rpc-url $Rpc | Out-String).Trim()
$block = (cast block-number --rpc-url $Rpc | Out-String).Trim()
$raw = @((cast call $POOL "getReserves()(uint112,uint112,uint32)" --rpc-url $Rpc) | Where-Object { $_.Trim() -ne "" })
$t0 = (cast call $POOL "token0()(address)" --rpc-url $Rpc | Out-String).Trim()
if ($t0.ToLower() -eq $DMX.ToLower()) { $rDmx = N $raw[0]; $rBnb = N $raw[1] } else { $rDmx = N $raw[1]; $rBnb = N $raw[0] }
$price = [System.Numerics.BigInteger]::Divide($rBnb * $E18, $rDmx)
if ($Token -ne "") {
  $maxTx = C $Token "maxTxAmount()(uint256)"; $tax = C $Token "taxFee()(uint256)"; $liq = C $Token "liquidityFee()(uint256)"; $src = "live token $Token"
} else {
  $maxTx = [System.Numerics.BigInteger]::Parse("5000000000000000000000000000"); $tax = 10; $liq = 30; $src = "deploy values (no token yet)"
}
$capNet = Net $maxTx $tax $liq
$bnb = [System.Numerics.BigInteger]::Divide([System.Numerics.BigInteger]::Divide($capNet * $price, $E18), $MILLE) * $MILLE
$netTarget = [System.Numerics.BigInteger]::Divide($bnb * $E18, $price)
$num = $netTarget * 1000; $den = 1000 - $tax - $liq
$gross = [System.Numerics.BigInteger]::Divide($num, $den); if ($gross * $den -ne $num) { $gross += 1 }
$net = Net $gross $tax $liq
if ($gross -gt $maxTx) { throw "gross exceeds maxTxAmount" }
$ownerBal = N ((cast balance $OWNER --rpc-url $Rpc | Out-String))
Write-Output "chain $chain, block $block"
Write-Output "DMX pool reserves: DMX $rDmx, WBNB $rBnb"
Write-Output "DMX price (wei per token): $price"
Write-Output "DMN parameters ($src): maxTxAmount $maxTx, taxFee $tax, liquidityFee $liq"
Write-Output "BNB_LEG  (wei): $bnb   ($(T $bnb) BNB)"
Write-Output "GROSS    (wei): $gross   (the claim of 5a and the amountTokenDesired/Min of 5b)"
Write-Output "NET      (wei): $net   (what the pair will hold; over the target by $($net - $netTarget) wei)"
Write-Output "owner BNB (wei): $ownerBal   ($(T $ownerBal) BNB); needed leg + 0.002 reserve = $(T ($bnb + $RESERVE)) BNB -> $(if ($ownerBal -ge $bnb + $RESERVE) { 'FUNDED' } else { "SHORT by $(T ($bnb + $RESERVE - $ownerBal)) BNB" })"
