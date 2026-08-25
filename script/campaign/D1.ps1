# D1 - propose(): the snapshot is frozen at creation.
. .\script\campaign\lib.ps1
Log-Scenario "D1" "propose(): voting power and the quorum bar are frozen at creation"
Write-Output "  .. bootstrap"
$st = Bootstrap-Campaign
Write-Output "  .. claim"
Claim-Dmn "team1" (BW "12.00") | Out-Null
Write-Output "  .. transfer"
Send "team1" $st.token "transfer(address,uint256)" @($script:Addr.alice, "$(BW '4.00')") | Out-Null
Write-Output "  .. stake team1 (under maxTx 5.00 B)"
Stake-Dmn "team1" (BW "4.00") 3 | Out-Null
Write-Output "  .. stake alice"
Stake-Dmn "alice" (BW "2.00") 0 | Out-Null
Mine 1

$totalBefore = CQ $st.staking "totalVotingPower()(uint256)"
$quorumBps = CQ $st.governor "quorumBps()(uint256)"
Write-Output "  .. propose"
$calldata = (cast calldata "setFees(uint256,uint256,uint256)" 10 10 20)
$id = Propose-Call "team1" $st.token "$calldata" "fees-to-4pct"
Write-Output "  .. proposed id=$id"
$snapBlock = Prop-Num $id 5
$snapTotal = Prop-Num $id 6
$snapQuorum = Prop-Num $id 16
$proposeBlock = [System.Numerics.BigInteger]::Parse((cast block-number --rpc-url $script:RPC))
Log-Step "D1.1" "A proposal is created" "its snapshot block is the block BEFORE its own - already sealed (#12)" "created in block $proposeBlock, snapshotBlock = $snapBlock" $(if ($snapBlock -eq ($proposeBlock - 1)) { "PASS" } else { "DEVIATION" })
Log-Step "D1.2" "The quorum denominator recorded with it" "the aggregate voting power at that same sealed block" "snapshotTotalVotingPower = $(FmtB $snapTotal), live total = $(FmtB $totalBefore)" $(if ($snapTotal -eq $totalBefore) { "PASS" } else { "DEVIATION" })
Log-Step "D1.3" "The quorum bps captured per proposal (#37)" "the bps in force at creation, stored on the proposal itself" "quorumBpsSnapshot = $snapQuorum, live quorumBps = $quorumBps" $(if ($snapQuorum -eq $quorumBps) { "PASS" } else { "DEVIATION" })

Write-Output "  .. late stake"
Stake-Dmn "alice" (BW "1.00") 3 | Out-Null
Mine 1
$totalAfter = CQ $st.staking "totalVotingPower()(uint256)"
$snapTotal2 = Prop-Num $id 6
Log-Step "D1.4" "Someone stakes more AFTER the proposal exists" "the live total moves, the proposal's denominator does not" "live total $(FmtB $totalBefore) -> $(FmtB $totalAfter), proposal still $(FmtB $snapTotal2)" $(if ($snapTotal2 -eq $snapTotal -and $totalAfter -gt $totalBefore) { "PASS" } else { "DEVIATION" })
Log-Step "D1.5" "Proposal state right after creation" "Pending: the one-day voting delay has not elapsed" "$(Prop-State $id)" $(if ((Prop-State $id) -eq "Pending") { "PASS" } else { "DEVIATION" })
Stop-Anvil
Write-Output "D1 COMPLETE"
