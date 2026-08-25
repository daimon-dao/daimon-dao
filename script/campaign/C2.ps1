# C2 - Withdrawing before the lock expires must revert.
. .\script\campaign\lib.ps1
Log-Scenario "C2" "Withdraw before expiry: refused, and the position is untouched"
$st = Bootstrap-Campaign
Claim-Dmn "team1" (BW "20.00") | Out-Null
Send "team1" $st.token "transfer(address,uint256)" @($script:Addr.alice, "$(BW '4.00')") | Out-Null
$amt = CQ $st.token "balanceOf(address)(uint256)" @($script:Addr.alice)
$lockId = CQ $st.staking "nextLockId()(uint256)"
Stake-Dmn "alice" $amt 0 | Out-Null

$rev = Expect-Revert "alice" $st.staking "withdraw(uint256)" @("$lockId") -errSig "LockStillActive()"
$vpAfter = CQ $st.staking "votingPower(address)(uint256)" @($script:Addr.alice)
Log-Step "C2.1" "alice tries to withdraw immediately after staking" "refused: the lock has not expired" "$rev" $(if ("$rev" -match "LockStillActive") { "PASS" } else { "DEVIATION" })
Log-Step "C2.2" "Her position after the refused withdrawal" "untouched - voting power and stake intact" "vp = $(FmtB $vpAfter)" $(if ($vpAfter -gt 0) { "PASS" } else { "DEVIATION" })

Warp (29 * 86400)
$rev2 = Expect-Revert "alice" $st.staking "withdraw(uint256)" @("$lockId") -errSig "LockStillActive()"
Log-Step "C2.3" "One day before expiry (29 of 30 days elapsed)" "still refused - the boundary is respected to the second" "$rev2" $(if ("$rev2" -match "LockStillActive") { "PASS" } else { "DEVIATION" })

Warp (86400 + 60)
Send "alice" $st.staking "withdraw(uint256)" @("$lockId") | Out-Null
$vpEnd = CQ $st.staking "votingPower(address)(uint256)" @($script:Addr.alice)
$balEnd = CQ $st.token "balanceOf(address)(uint256)" @($script:Addr.alice)
Log-Step "C2.4" "Just past 30 days" "the withdrawal goes through, voting power returns to zero, principal comes back" "vp=$(FmtB $vpEnd), balance=$(FmtB $balEnd)" $(if ($vpEnd -eq 0 -and $balEnd -gt 0) { "PASS" } else { "DEVIATION" })
Stop-Anvil
Write-Output "C2 COMPLETE"
