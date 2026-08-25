# B3 - The poke: a 1-wei direct transfer to the pair fires the conversion.
. .\script\campaign\lib.ps1
Log-Scenario "B3" "The poke: 1 wei to the pair from a stranger converts exactly one chunk (#1 + #28)"
$st = Bootstrap-Campaign
Claim-Dmn "team1" (BW "30.00") | Out-Null
Setup-Pool "team1" "4.00" | Out-Null
Send "team1" $st.token "transfer(address,uint256)" @($script:Addr.alice, "$(BW '5.00')") | Out-Null
Send "team1" $st.token "transfer(address,uint256)" @($script:Addr.stranger, "$(BW '1.00')") | Out-Null

$minSwap = CQ $st.token "minimumTokensBeforeSwap()(uint256)"
$invBefore = Fee-Inventory
$ethBefore = Bal $st.token
$stakingBefore = Bal $st.staking
Log-Step "B3.1" "State before the poke" "inventory armed, no BNB anywhere yet" "inventory=$(FmtB $invBefore), contract BNB=$(FmtT $ethBefore), staking BNB=$(FmtT $stakingBefore)" $(if ($invBefore -ge $minSwap) { "PASS" } else { "DEVIATION" })

Poke "stranger" | Out-Null
$invAfter = Fee-Inventory
$ethAfter = Bal $st.token
$stakingAfter = Bal $st.staking
$consumed = $invBefore - $invAfter
Log-Step "B3.2" "The stranger - no role, no permission - sends 1 wei of DMN to the pair" "the conversion fires: exactly ONE threshold-sized chunk is sold" "inventory consumed = $(FmtB $consumed), threshold = $(FmtB $minSwap)" $(if ($consumed -eq $minSwap) { "PASS" } else { "DEVIATION" })
Log-Step "B3.3" "Where the proceeds went" "the whole marketing share to the staking pool (share = 1000), the buyback share retained" "staking +$(FmtT ($stakingAfter - $stakingBefore)) BNB, contract +$(FmtT ($ethAfter - $ethBefore)) BNB" $(if ($stakingAfter -gt $stakingBefore -and $ethAfter -gt $ethBefore) { "PASS" } else { "DEVIATION" })
$mk = CQ $st.token "balanceOf(address)(uint256)" @($script:MARKETING)
$mkNat = Bal $script:MARKETING
Log-Step "B3.4" "The marketing wallet during a real conversion" "nothing: with the share at 1000 the transfer branch is never even entered" "DMN=$mk, native=$(FmtT $mkNat)" $(if ($mk -eq 0 -and $mkNat -eq 0) { "PASS" } else { "DEVIATION" })
Log-Note "This is the launch configuration doing its job on a live conversion: the BNB the marketing wallet would have received is instead notified to the staking pool in the same transaction, and the wallet is not even called."
Stop-Anvil
Write-Output "B3 COMPLETE"
