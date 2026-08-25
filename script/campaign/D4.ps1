# D4 - queue -> timelock -> execute, and the ordering guards.
. .\script\campaign\lib.ps1
Log-Scenario "D4" "queue, the 7-day timelock, execute - and what happens out of order"
$st = Bootstrap-Campaign
Claim-Dmn "team1" (BW "12.00") | Out-Null
Stake-Dmn "team1" (BW "4.00") 3 | Out-Null
Mine 1
$taxBefore = CQ $st.token "taxFee()(uint256)"; $liqBefore = CQ $st.token "liquidityFee()(uint256)"
$calldata = (cast calldata "setFees(uint256,uint256,uint256)" 10 10 20)
$id = Propose-Call "team1" $st.token "$calldata" "replay-of-proposal-0"
Warp (86400 + 60)
Vote-Prop "team1" $id 1 | Out-Null
Warp (5 * 86400 + 60)
Log-Step "D4.1" "Proposal approved and out of voting" "Succeeded, not yet queued" "$(Prop-State $id)" $(if ((Prop-State $id) -eq "Succeeded") { "PASS" } else { "DEVIATION" })

$rev1 = Expect-Revert "stranger" $st.governor "execute(uint256)" @("$id") -errSig "ProposalNotQueued()"
Log-Step "D4.2" "execute() without queue()" "refused with its own precise error: the timelock is not optional" "$rev1" $(if ("$rev1" -match "ProposalNotQueued") { "PASS" } else { "DEVIATION" })

Queue-Prop $id | Out-Null
Log-Step "D4.3" "queue() by an address with no role at all" "anyone may queue an approved proposal; state becomes Queued" "$(Prop-State $id)" $(if ((Prop-State $id) -eq "Queued") { "PASS" } else { "DEVIATION" })
$rev2 = Expect-Revert "stranger" $st.governor "execute(uint256)" @("$id")
Log-Step "D4.4" "execute() during the timelock delay" "refused: the public reaction window is enforced by the Timelock itself" "$rev2" $(if ("$rev2" -match "reverted") { "PASS" } else { "DEVIATION" })

Warp (7 * 86400 + 60)
Exec-Prop $id | Out-Null
$tax = CQ $st.token "taxFee()(uint256)"; $buy = CQ $st.token "buybackFee()(uint256)"; $mkt = CQ $st.token "marketingFee()(uint256)"; $liq = CQ $st.token "liquidityFee()(uint256)"
Log-Step "D4.5" "execute() after the seven days" "the parameter actually changes on the token" "taxFee $taxBefore -> $tax, buyback $buy, marketing $mkt, liquidityFee $liqBefore -> $liq (total $(($tax+$liq)/10)%)" $(if ($tax -eq 10 -and $buy -eq 10 -and $mkt -eq 20 -and $liq -eq 30) { "PASS" } else { "DEVIATION" })
Log-Step "D4.6" "Proposal state afterwards" "Executed" "$(Prop-State $id)" $(if ((Prop-State $id) -eq "Executed") { "PASS" } else { "DEVIATION" })
$rev3 = Expect-Revert "stranger" $st.governor "execute(uint256)" @("$id") -errSig "AlreadyExecuted()"
Log-Step "D4.7" "A second execute() of the same proposal" "refused: no replay" "$rev3" $(if ("$rev3" -match "AlreadyExecuted") { "PASS" } else { "DEVIATION" })
Log-Note "This is the historical proposal #0 replayed end to end - fees from 5% to 4% - through the real script's deployment: thirteen days of process compressed into warps, with every ordering guard refusing on its own terms."
Stop-Anvil
Write-Output "D4 COMPLETE"
