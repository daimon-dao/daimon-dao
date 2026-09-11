# P2.5b -- Checkpoints at real past blocks + pro-rata rewards + claim.
. $PSScriptRoot\lib.ps1
Load-Keystores
$st = S
Log-Scenario "P2.5b" "Checkpoint history on real blocks; rewards from real conversions; claim"

# Recover each staker's stake block from the Staked events (also proves the
# event is emitted and readable -- Part 3 material).
$prev = $ErrorActionPreference; $ErrorActionPreference = "Continue"
$logs = (cast logs --address $st.staking "Staked(address,uint256,uint256,uint256,uint256)" --from-block 127613000 --to-block latest --rpc-url $script:RPC --json 2>&1 | Out-String)
$ErrorActionPreference = $prev
$evs = $logs | ConvertFrom-Json
$blk1 = [System.Numerics.BigInteger]::Parse("0" + $evs[0].blockNumber.Substring(2), "AllowHexSpecifier")
Log-Step "P2.5b.1" "Staked events read back from the chain" "3 events, one per staker" "count=$($evs.Count), first stake block=$blk1" $evs[0].transactionHash $(if ($evs.Count -eq 3) { "PASS" } else { "DEVIATION" })

$vpBefore = CQ $st.staking "votingPowerAt(address,uint256)(uint256)" @($script:AddrBook.staker1, "$($blk1 - 1)")
$vpAt = CQ $st.staking "votingPowerAt(address,uint256)(uint256)" @($script:AddrBook.staker1, "$blk1")
$vpNow = CQ $st.staking "votingPower(address)(uint256)" @($script:AddrBook.staker1)
Log-Step "P2.5b.2" "staker1 voting power at three real points in history" "0 before the stake block, 20B at it, 20B now" "at $($blk1 - 1)=$(FmtB $vpBefore), at $blk1=$(FmtB $vpAt), live=$(FmtB $vpNow)" "-" $(if ($vpBefore -eq 0 -and "$vpAt" -eq "20000000000000000000000000000" -and "$vpNow" -eq "20000000000000000000000000000") { "PASS" } else { "DEVIATION" })

$tvpBefore = CQ $st.staking "totalVotingPowerAt(uint256)(uint256)" @("$($blk1 - 1)")
$tvpNow = CQ $st.staking "totalVotingPower()(uint256)"
Log-Step "P2.5b.3" "The aggregate series (the quorum denominator, #12)" "0 before anyone staked; 32.5B live" "at $($blk1 - 1)=$(FmtB $tvpBefore), live=$(FmtB $tvpNow)" "-" $(if ($tvpBefore -eq 0 -and "$tvpNow" -eq "32500000000000000000000000000") { "PASS" } else { "DEVIATION" })

# Rewards accrued from the REAL conversions (P2.3 + P2.4 pokes).
$p1 = CQ $st.staking "pendingReward(address)(uint256)" @($script:AddrBook.staker1)
$p2 = CQ $st.staking "pendingReward(address)(uint256)" @($script:AddrBook.staker2)
$p3 = CQ $st.staking "pendingReward(address)(uint256)" @($script:AddrBook.staker3)
$sum = $p1 + $p2 + $p3
$stakingBal = Bal $st.staking
# pro-rata: staker1 20/32.5, staker2 7.5/32.5, staker3 5/32.5
$ratioOk = $true
if ($p3 -gt 0) {
  $r12 = [System.Numerics.BigInteger]::Divide($p1 * 1000, $p3)
  $r23 = [System.Numerics.BigInteger]::Divide($p2 * 1000, $p3)
  $ratioOk = ([System.Numerics.BigInteger]::Abs($r12 - 4000) -le 20 -and [System.Numerics.BigInteger]::Abs($r23 - 1500) -le 20)
}
Log-Step "P2.5b.4" "Pending rewards, pro-rata by voting power" "ratios 4.0x and 1.5x vs staker3 (20:7.5:5); the sum stays within the pool balance" "p1=$(FmtT $p1), p2=$(FmtT $p2), p3=$(FmtT $p3) BNB; ratios x1000: $r12 / $r23; pool=$(FmtT $stakingBal)" "-" $(if ($p1 -gt 0 -and $ratioOk -and $sum -le $stakingBal) { "PASS" } else { "DEVIATION" })

$bnbBefore = Bal $script:AddrBook.staker1
$hC = Send "staker1" $st.staking "claimReward()"
$bnbAfter = Bal $script:AddrBook.staker1
$gasCost = $hC.gasUsed * 100000000  # approx at 0.1 gwei
$gained = $bnbAfter - $bnbBefore
Log-Step "P2.5b.5" "staker1 claims" "receives the pending amount (minus own gas); pending resets" "balance moved $(FmtT $gained) BNB (pending was $(FmtT $p1)); now pending=$(FmtT (CQ $st.staking 'pendingReward(address)(uint256)' @($script:AddrBook.staker1))); gas=$($hC.gasUsed)" $hC.hash $(if ($gained -gt 0) { "PASS" } else { "DEVIATION" })
Write-Output "P2e COMPLETE"
