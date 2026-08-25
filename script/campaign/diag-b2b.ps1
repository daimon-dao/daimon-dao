. .\script\campaign\lib.ps1
$st = Bootstrap-Campaign
Claim-Dmn "team1" (BW "30.00") | Out-Null
Setup-Pool "team1" "4.00" | Out-Null
Send "team1" $st.token "transfer(address,uint256)" @($script:Addr.alice, "$(BW '5.00')") | Out-Null
Write-Output "alice BEFORE swap: $(cast balance $script:Addr.alice --rpc-url $script:RPC)"
$amount = BW "1.00"
Send "alice" $st.token "approve(address,uint256)" @($script:ROUTER, "$amount") | Out-Null
Write-Output "alice after approve: $(cast balance $script:Addr.alice --rpc-url $script:RPC)"
$weth = CQRaw $script:ROUTER "WETH()(address)"
Write-Output "WETH = $weth"
$path = "[$($st.token),$weth]"
Write-Output "path = $path"
$h = Send "alice" $script:ROUTER "swapExactTokensForETHSupportingFeeOnTransferTokens(uint256,uint256,address[],address,uint256)" @("$amount", "0", $path, $script:Addr.alice, "99999999999")
Write-Output "swap tx = $h"
Write-Output "alice AFTER swap: $(cast balance $script:Addr.alice --rpc-url $script:RPC)"
$tx = cast tx $h --rpc-url $script:RPC --json 2>&1 | ConvertFrom-Json
Write-Output "tx.value = $($tx.value)   tx.gasPrice = $($tx.gasPrice)  tx.gas = $($tx.gas)"
$rc = cast receipt $h --rpc-url $script:RPC --json 2>&1 | ConvertFrom-Json
Write-Output "receipt gasUsed = $($rc.gasUsed)  effGasPrice = $($rc.effectiveGasPrice)"
Stop-Anvil
