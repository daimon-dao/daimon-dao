. .\script\campaign\lib.ps1
Start-CampaignNode
Write-Output "alice before: $(cast balance $script:Addr.alice --rpc-url $script:RPC)"
$h = cast send 0x000000000000000000000000000000000000dEaD --value 1 --private-key $script:Key.alice --rpc-url $script:RPC --json 2>&1 | ConvertFrom-Json
Write-Output "alice after : $(cast balance $script:Addr.alice --rpc-url $script:RPC)"
Write-Output "gasUsed=$($h.gasUsed) effectiveGasPrice=$($h.effectiveGasPrice)"
$gu = [System.Numerics.BigInteger]::Parse($h.gasUsed.Substring(2),'AllowHexSpecifier')
$gp = [System.Numerics.BigInteger]::Parse($h.effectiveGasPrice.Substring(2),'AllowHexSpecifier')
Write-Output "gasUsed=$gu  effectiveGasPrice=$gp  cost=$($gu*$gp) wei = $(FmtT ($gu*$gp)) BNB"
Stop-Anvil
