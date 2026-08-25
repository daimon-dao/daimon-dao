. .\script\campaign\lib.ps1
$st = Bootstrap-Campaign
Claim-Dmn "team1" (BW "30.00") | Out-Null
Setup-Pool "team1" "4.00" | Out-Null
Send "team1" $st.token "transfer(address,uint256)" @($script:Addr.alice, "$(BW '5.00')") | Out-Null
Write-Output "alice addr = $($script:Addr.alice)"
Write-Output "raw cast balance BEFORE: $(cast balance $script:Addr.alice --rpc-url $script:RPC)"
Write-Output "Bal() BEFORE           : $(Bal $script:Addr.alice)"
Write-Output "alice DMN before       : $(FmtB (CQ $st.token 'balanceOf(address)(uint256)' @($script:Addr.alice)))"
$res = Pair-Reserves
Write-Output "pair reserves: DMN=$(FmtB $res[0]) WBNB=$(FmtT $res[1])"
Sell-Dmn "alice" (BW "1.00") | Out-Null
Write-Output "raw cast balance AFTER : $(cast balance $script:Addr.alice --rpc-url $script:RPC)"
Write-Output "alice DMN after        : $(FmtB (CQ $st.token 'balanceOf(address)(uint256)' @($script:Addr.alice)))"
$res2 = Pair-Reserves
Write-Output "pair after   : DMN=$(FmtB $res2[0]) WBNB=$(FmtT $res2[1])"
Write-Output "gas price: $(cast gas-price --rpc-url $script:RPC)"
Stop-Anvil
