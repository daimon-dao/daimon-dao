. .\script\campaign\lib.ps1
$st = Bootstrap-Campaign
$tax = CQ $st.token "taxFee()(uint256)"; $liq = CQ $st.token "liquidityFee()(uint256)"
$maxTx = CQ $st.token "maxTxAmount()(uint256)"; $minSwap = CQ $st.token "minimumTokensBeforeSwap()(uint256)"
Write-Output "taxFee=$tax liquidityFee=$liq (per mille) -> total fee $(($tax+$liq)/10)%"
Write-Output "maxTxAmount=$(FmtB $maxTx)  minimumTokensBeforeSwap=$(FmtB $minSwap)"
Write-Output "pair=$($st.pair)"
$r = cast call $st.pair "getReserves()(uint112,uint112,uint32)" --rpc-url $script:RPC 2>&1
Write-Output "raw getReserves: $(($r -join ' | '))"
$t0 = CQRaw $st.pair "token0()(address)"
Write-Output "token0=$t0  token=$($st.token)"
Stop-Anvil
