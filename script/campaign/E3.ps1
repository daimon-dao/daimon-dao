# E3 - Atomic cancel when the guardian already cancelled at the Timelock (#26).
. .\script\campaign\lib.ps1
Log-Scenario "E3" "Both cancel paths on the same operation: the flags converge, nothing reverts (Zenith #26)"
$st = Bootstrap-Campaign
Claim-Dmn "team1" (BW "12.00") | Out-Null
Stake-Dmn "team1" (BW "4.00") 3 | Out-Null
Mine 1
$calldata = (cast calldata "setFees(uint256,uint256,uint256)" 10 10 20)
$id = Propose-Call "team1" $st.token "$calldata" "race-the-cancels"
Warp (86400 + 60); Vote-Prop "team1" $id 1 | Out-Null; Warp (5 * 86400 + 60)
Queue-Prop $id | Out-Null
$opId = Op-Id $id
$opBefore = cast call $st.timelock "operations(bytes32)(uint256,bool,bool)" $opId --rpc-url $script:RPC 2>&1 | Out-String
Log-Step "E3.1" "A proposal reaches the Timelock" "queued on both sides: the Governor says Queued, the operation is scheduled" "state=$(Prop-State $id), operation=$(($opBefore -replace '\s+',' ').Trim())" $(if ((Prop-State $id) -eq "Queued") { "PASS" } else { "DEVIATION" })

# The guardian uses its INDEPENDENT path first - straight at the Timelock.
Send "guardian" $st.timelock "cancel(bytes32)" @($opId) | Out-Null
$stateAfterTl = Prop-State $id
Log-Step "E3.2" "The guardian cancels directly at the Timelock" "the Governor already reflects it: state reads Canceled, not Queued (#26 pt.4-6)" "$stateAfterTl" $(if ($stateAfterTl -eq "Canceled") { "PASS" } else { "DEVIATION" })

# Now the OTHER path on the same proposal: it must converge, not revert.
Send "guardian" $st.governor "cancel(uint256)" @("$id") | Out-Null
$canceledFlag = Prop-Field $id 12
$opAfter = cast call $st.timelock "operations(bytes32)(uint256,bool,bool)" $opId --rpc-url $script:RPC 2>&1 | Out-String
Log-Step "E3.3" "Governor.cancel() on an operation already cancelled at the Timelock" "succeeds: it sees the operation is cancelled and does NOT call cancel again (which would revert)" "proposal.canceled=$canceledFlag, operation=$(($opAfter -replace '\s+',' ').Trim())" $(if ("$canceledFlag" -eq "true") { "PASS" } else { "DEVIATION" })

$rev = Expect-Revert "stranger" $st.governor "execute(uint256)" @("$id")
Log-Step "E3.4" "Executing it afterwards" "impossible from either side" "$rev" $(if ("$rev" -match "reverted") { "PASS" } else { "DEVIATION" })
$rev2 = Expect-Revert "guardian" $st.timelock "cancel(bytes32)" @($opId) -errSig "OperationAlreadyCanceled()"
Log-Step "E3.5" "Cancelling the operation a second time at the Timelock" "refused - which is exactly why the Governor had to check first" "$rev2" $(if ("$rev2" -match "OperationAlreadyCanceled") { "PASS" } else { "DEVIATION" })
Log-Note "The invariant Poneder asked for holds on a chain: whichever path is used first, the two contracts never disagree about whether the operation can still execute, and the second path converges instead of reverting."
Stop-Anvil
Write-Output "E3 COMPLETE"
