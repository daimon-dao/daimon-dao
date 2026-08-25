# E1 - The pause blocks transfers; the unpause restores them.
. .\script\campaign\lib.ps1
Log-Scenario "E1" "Guardian pause and unpause"
$st = Bootstrap-Campaign
Claim-Dmn "team1" (BW "12.00") | Out-Null
Send "team1" $st.token "transfer(address,uint256)" @($script:Addr.alice, "$(BW '4.00')") | Out-Null

Send "guardian" $st.token "setPaused(bool)" @("true") | Out-Null
$isP = CQRaw $st.token "isPaused()(bool)"
$rawP = CQRaw $st.token "paused()(bool)"
$until = CQ $st.token "pauseUntil()(uint256)"
$now = [System.Numerics.BigInteger]::Parse((cast block latest --rpc-url $script:RPC --json 2>$null | ConvertFrom-Json).timestamp.ToString().Replace("0x",""), 'AllowHexSpecifier')
$maxDur = CQ $st.token "MAX_PAUSE_DURATION()(uint256)"
Log-Step "E1.1" "The guardian pauses the token" "paused, with a window that ends at most MAX_PAUSE_DURATION out" "isPaused=$isP, pauseUntil-now = $(($until - $now)/86400) days, MAX_PAUSE_DURATION = $($maxDur/86400) days" $(if ("$isP" -eq "true" -and ($until - $now) -le $maxDur) { "PASS" } else { "DEVIATION" })

$rev = Expect-Revert "alice" $st.token "transfer(address,uint256)" @($script:Addr.bob, "$(BW '1.00')") -errSig "ContractIsPaused()"
Log-Step "E1.2" "An ordinary transfer while paused" "refused" "$rev" $(if ("$rev" -match "ContractIsPaused") { "PASS" } else { "DEVIATION" })
$rev2 = Expect-Revert "stranger" $st.token "burnDeadBalanceToFloor()" @()
Log-Step "E1.3" "The permissionless burn while paused" "also refused - the pause covers the supply accounting too (#5)" "$rev2" $(if ("$rev2" -match "reverted") { "PASS" } else { "DEVIATION" })

Send "guardian" $st.token "setPaused(bool)" @("false") | Out-Null
$isP2 = CQRaw $st.token "isPaused()(bool)"
$until2 = CQ $st.token "pauseUntil()(uint256)"
Send "alice" $st.token "transfer(address,uint256)" @($script:Addr.bob, "$(BW '1.00')") | Out-Null
$bobBal = CQ $st.token "balanceOf(address)(uint256)" @($script:Addr.bob)
Log-Step "E1.4" "The guardian unpauses" "transfers work again, and the window is cleared" "isPaused=$isP2, pauseUntil=$until2, bob now holds $(FmtB $bobBal)" $(if ("$isP2" -eq "false" -and $until2 -eq 0 -and $bobBal -gt 0) { "PASS" } else { "DEVIATION" })
$onlyGuardian = Expect-Revert "alice" $st.token "setPaused(bool)" @("true")
Log-Step "E1.5" "Anyone else trying to pause" "refused: the role is the guardian's alone" "$onlyGuardian" $(if ("$onlyGuardian" -match "reverted") { "PASS" } else { "DEVIATION" })
Stop-Anvil
Write-Output "E1 COMPLETE"
