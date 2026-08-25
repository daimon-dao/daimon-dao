# E2 - The pause self-terminates with nobody doing anything.
. .\script\campaign\lib.ps1
Log-Scenario "E2" "The pause window lapses on its own (Zenith #36)"
$st = Bootstrap-Campaign
Claim-Dmn "team1" (BW "12.00") | Out-Null
Send "team1" $st.token "transfer(address,uint256)" @($script:Addr.alice, "$(BW '4.00')") | Out-Null
Send "guardian" $st.token "setPaused(bool)" @("true") | Out-Null
$until = CQ $st.token "pauseUntil()(uint256)"
$credit0 = CQ $st.token "cumulativePauseSeconds()(uint256)"
Log-Step "E2.1" "Pause armed" "a 14-day window, and the same 14 days credited to the migration clock" "pauseUntil=$until, cumulativePauseSeconds=$($credit0/86400) days" $(if ($credit0 -eq (14*86400)) { "PASS" } else { "DEVIATION" })

Warp (13 * 86400)
$mid = CQRaw $st.token "isPaused()(bool)"
Log-Step "E2.2" "Thirteen days later, nobody has touched anything" "still paused: the window has not run out" "isPaused=$mid" $(if ("$mid" -eq "true") { "PASS" } else { "DEVIATION" })

Warp (86400 + 120)
$after = CQRaw $st.token "isPaused()(bool)"
$rawFlag = CQRaw $st.token "paused()(bool)"
Send "alice" $st.token "transfer(address,uint256)" @($script:Addr.bob, "$(BW '1.00')") | Out-Null
Log-Step "E2.3" "Past the fourteenth day, still with NO transaction from anyone" "the pause has lapsed by itself and transfers work" "isPaused=$after, and a transfer went through" $(if ("$after" -eq "false") { "PASS" } else { "DEVIATION" })
Log-Step "E2.4" "The raw flag afterwards" "still true - which is why interfaces must read isPaused(), not paused()" "paused()=$rawFlag vs isPaused()=$after" $(if ("$rawFlag" -eq "true" -and "$after" -eq "false") { "PASS" } else { "DEVIATION" })

Send "guardian" $st.token "setPaused(bool)" @("true") | Out-Null
$credit1 = CQ $st.token "cumulativePauseSeconds()(uint256)"
Log-Step "E2.5" "The guardian renews the pause" "a fresh window, and the credit grows again - every renewal is a visible transaction" "credit $($credit0/86400) -> $($credit1/86400) days" $(if ($credit1 -gt $credit0) { "PASS" } else { "DEVIATION" })
Log-Note "A pause cannot persist through inaction: keeping the token frozen takes a renewal every fortnight, each one an on-chain event. A lost guardian key stops mattering fourteen days later."
Stop-Anvil
Write-Output "E2 COMPLETE"
