# C3 - Checkpoints across several epochs: the history stays coherent.
. .\script\campaign\lib.ps1
Log-Scenario "C3" "Checkpoints across epochs: historical voting power at past blocks holds"
$st = Bootstrap-Campaign
Claim-Dmn "team1" (BW "30.00") | Out-Null
Send "team1" $st.token "transfer(address,uint256)" @($script:Addr.alice, "$(BW '4.00')") | Out-Null
Send "team1" $st.token "transfer(address,uint256)" @($script:Addr.bob, "$(BW '4.00')") | Out-Null
Send "team1" $st.token "transfer(address,uint256)" @($script:Addr.carol, "$(BW '4.00')") | Out-Null

$b0 = CQ $st.token "totalSupply()(uint256)"   # placeholder read to keep the block moving
$blk0 = [System.Numerics.BigInteger]::Parse((cast block-number --rpc-url $script:RPC))
Stake-Dmn "alice" (BW "2.00") 0 | Out-Null
$blkA = [System.Numerics.BigInteger]::Parse((cast block-number --rpc-url $script:RPC))
$vpA1 = CQ $st.staking "votingPower(address)(uint256)" @($script:Addr.alice)
Mine 3
Stake-Dmn "bob" (BW "2.00") 3 | Out-Null
$blkB = [System.Numerics.BigInteger]::Parse((cast block-number --rpc-url $script:RPC))
$vpB1 = CQ $st.staking "votingPower(address)(uint256)" @($script:Addr.bob)
Mine 3
Stake-Dmn "alice" (BW "1.00") 3 | Out-Null
$blkC = [System.Numerics.BigInteger]::Parse((cast block-number --rpc-url $script:RPC))
$vpA2 = CQ $st.staking "votingPower(address)(uint256)" @($script:Addr.alice)
Mine 2

$hA0 = CQ $st.staking "votingPowerAt(address,uint256)(uint256)" @($script:Addr.alice, "$blk0")
$hAa = CQ $st.staking "votingPowerAt(address,uint256)(uint256)" @($script:Addr.alice, "$blkA")
$hAb = CQ $st.staking "votingPowerAt(address,uint256)(uint256)" @($script:Addr.alice, "$blkB")
$hAc = CQ $st.staking "votingPowerAt(address,uint256)(uint256)" @($script:Addr.alice, "$blkC")
Log-Step "C3.1" "alice's voting power at a block BEFORE she ever staked" "zero - the history knows she had none" "at block $blk0 = $(FmtB $hA0)" $(if ($hA0 -eq 0) { "PASS" } else { "DEVIATION" })
Log-Step "C3.2" "At the block of her first stake" "her first position, and nothing more" "at block $blkA = $(FmtB $hAa), live then = $(FmtB $vpA1)" $(if ($hAa -eq $vpA1) { "PASS" } else { "DEVIATION" })
Log-Step "C3.3" "At a later block, while only bob acted" "unchanged: nobody else's action moves her history" "at block $blkB = $(FmtB $hAb)" $(if ($hAb -eq $vpA1) { "PASS" } else { "DEVIATION" })
Log-Step "C3.4" "At the block of her second stake" "both positions counted" "at block $blkC = $(FmtB $hAc), live = $(FmtB $vpA2)" $(if ($hAc -eq $vpA2) { "PASS" } else { "DEVIATION" })

$tA = CQ $st.staking "totalVotingPowerAt(uint256)(uint256)" @("$blkA")
$tB = CQ $st.staking "totalVotingPowerAt(uint256)(uint256)" @("$blkB")
$tC = CQ $st.staking "totalVotingPowerAt(uint256)(uint256)" @("$blkC")
$tNow = CQ $st.staking "totalVotingPower()(uint256)"
Log-Step "C3.5" "The aggregate history - the quorum denominator (#12)" "the total tracks the same epochs: alice alone, then alice+bob, then both of alice's" "at A=$(FmtB $tA), at B=$(FmtB $tB), at C=$(FmtB $tC), live=$(FmtB $tNow)" $(if ($tA -eq $vpA1 -and $tB -eq ($vpA1 + $vpB1) -and $tC -eq $tNow) { "PASS" } else { "DEVIATION" })
$cpA = CQ $st.staking "checkpointCount(address)(uint256)" @($script:Addr.alice)
$cpT = CQ $st.staking "totalCheckpointCount()(uint256)"
Log-Step "C3.6" "Checkpoints actually written" "one per position change for alice, and a global series alongside" "alice=$cpA, global=$cpT" $(if ($cpA -eq 2 -and $cpT -ge 3) { "PASS" } else { "DEVIATION" })
Log-Note "This is the machinery the #12 fix rests on, exercised on a chain for the first time: both the per-account series and the aggregate are keyed by block number, and a query about a past block returns what was true then - not what is true now."
Stop-Anvil
Write-Output "C3 COMPLETE"
