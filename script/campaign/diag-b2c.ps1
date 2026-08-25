. .\script\campaign\lib.ps1
$st = Bootstrap-Campaign
Claim-Dmn "team1" (BW "30.00") | Out-Null
Setup-Pool "team1" "4.00" | Out-Null
Send "team1" $st.token "transfer(address,uint256)" @($script:Addr.alice, "$(BW '5.00')") | Out-Null
$amount = BW "1.00"
Send "alice" $st.token "approve(address,uint256)" @($script:ROUTER, "$amount") | Out-Null
$bn = [System.Numerics.BigInteger]::Parse((cast block-number --rpc-url $script:RPC))
Write-Output "block prima dello swap = $bn ; alice = $(cast balance $script:Addr.alice --rpc-url $script:RPC --block $bn)"
$weth = CQRaw $script:ROUTER "WETH()(address)"
$h = Send "alice" $script:ROUTER "swapExactTokensForETHSupportingFeeOnTransferTokens(uint256,uint256,address[],address,uint256)" @("$amount", "0", "[$($st.token),$weth]", $script:Addr.alice, "99999999999")
$bn2 = [System.Numerics.BigInteger]::Parse((cast block-number --rpc-url $script:RPC))
Write-Output "block dopo swap = $bn2"
foreach ($b in @($bn, $bn+1, $bn2)) {
  Write-Output "  alice @block $b = $(cast balance $script:Addr.alice --rpc-url $script:RPC --block $b)"
}
Write-Output "--- trace dello swap (righe con Transfer/ETH) ---"
$trace = cast run $h --rpc-url $script:RPC 2>&1 | Out-String
($trace -split "`n") | Where-Object { $_ -match "withdraw|Withdrawal|Transfer|value:" } | Select-Object -First 12 | ForEach-Object { Write-Output "   $($_.Trim())" }
Stop-Anvil
