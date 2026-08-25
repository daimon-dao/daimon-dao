# B4 - Repeated pokes inside ONE block must not exceed the per-block budget (#28).
. .\script\campaign\lib.ps1
Log-Scenario "B4" "Three pokes in the same block: the #28 per-block budget holds"
$st = Bootstrap-Campaign
Claim-Dmn "team1" (BW "40.00") | Out-Null
Setup-Pool "team1" "4.00" | Out-Null
Send "team1" $st.token "transfer(address,uint256)" @($script:Addr.alice, "$(BW '5.00')") | Out-Null
Send "team1" $st.token "transfer(address,uint256)" @($script:Addr.bob, "$(BW '5.00')") | Out-Null
Send "team1" $st.token "transfer(address,uint256)" @($script:Addr.stranger, "$(BW '1.00')") | Out-Null
$minSwap = CQ $st.token "minimumTokensBeforeSwap()(uint256)"
$invBefore = Fee-Inventory
Log-Step "B4.1" "Inventory before, with several chunks available" "well above one threshold, so a budget-free implementation could convert repeatedly" "inventory=$(FmtB $invBefore) = $([Math]::Floor([double]($invBefore / $minSwap))) chunks" $(if ($invBefore -ge ($minSwap * 3)) { "PASS" } else { "DEVIATION" })

Automine $false
# Three DIFFERENT senders: same block, and it also proves the budget is
# caller-independent rather than a per-account cooldown.
$h1 = SendAsync "stranger" $st.token "transfer(address,uint256)" @($st.pair, "1")
$h2 = SendAsync "alice"    $st.token "transfer(address,uint256)" @($st.pair, "1")
$h3 = SendAsync "bob"      $st.token "transfer(address,uint256)" @($st.pair, "1")
Mine 1
Automine $true
$bn = CQ $st.token "balanceOf(address)(uint256)" @($st.token)
$consumed = $invBefore - $bn
$b1 = (cast receipt $h1 --rpc-url $script:RPC --json 2>$null | ConvertFrom-Json).blockNumber
$b3 = (cast receipt $h3 --rpc-url $script:RPC --json 2>$null | ConvertFrom-Json).blockNumber
Log-Step "B4.2" "Three pokes from THREE DIFFERENT accounts, mined in one block" "all three land in the same block" "first poke block=$b1, third poke block=$b3" $(if ("$b1" -eq "$b3") { "PASS" } else { "DEVIATION" })
Log-Step "B4.3" "How much was converted by three pokes in that block" "ONE chunk, not three: the budget caps the aggregate per block, whoever calls" "consumed = $(FmtB $consumed), one chunk = $(FmtB $minSwap)" $(if ($consumed -eq $minSwap) { "PASS" } else { "DEVIATION" })
Warp 5
Poke "stranger" | Out-Null
$after = Fee-Inventory
Log-Step "B4.4" "A poke in the NEXT block" "the budget rolls: another chunk converts, so this is pacing and not prohibition" "consumed now = $(FmtB ($invBefore - $after))" $(if (($invBefore - $after) -eq ($minSwap * 2)) { "PASS" } else { "DEVIATION" })
Stop-Anvil
Write-Output "B4 COMPLETE"
