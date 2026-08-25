# C5 - An awkward reward amount is split strictly pro-rata.
. .\script\campaign\lib.ps1
Log-Scenario "C5" "notifyRewardAmount with an awkward amount: strict pro-rata, no dust leaks"
$st = Bootstrap-Campaign
Claim-Dmn "team1" (BW "30.00") | Out-Null
Send "team1" $st.token "transfer(address,uint256)" @($script:Addr.alice, "$(BW '4.00')") | Out-Null
Send "team1" $st.token "transfer(address,uint256)" @($script:Addr.bob, "$(BW '4.00')") | Out-Null
Stake-Dmn "alice" (BW "2.00") 0 | Out-Null     # 1.0x
Stake-Dmn "bob"   (BW "2.00") 3 | Out-Null     # 4.0x -> four times the weight
$vpA = CQ $st.staking "votingPower(address)(uint256)" @($script:Addr.alice)
$vpB = CQ $st.staking "votingPower(address)(uint256)" @($script:Addr.bob)
$totalVp = CQ $st.staking "totalVotingPower()(uint256)"

# Deliberately not a round number, and not divisible by the weights.
$odd = "3141592653589793238"    # 3.141592653589793238 BNB
Send "stranger" $st.staking "notifyRewardAmount(uint256)" @($odd) -value $odd | Out-Null
$pA = CQ $st.staking "pendingReward(address)(uint256)" @($script:Addr.alice)
$pB = CQ $st.staking "pendingReward(address)(uint256)" @($script:Addr.bob)
$oddBI = [System.Numerics.BigInteger]::Parse($odd)
$expA = ($oddBI * $vpA) / $totalVp
$expB = ($oddBI * $vpB) / $totalVp
Log-Step "C5.1" "Weights before the distribution" "bob carries 4x alice's weight for the same principal" "alice vp=$(FmtB $vpA), bob vp=$(FmtB $vpB), total=$(FmtB $totalVp)" $(if ($vpB -eq ($vpA * 4)) { "PASS" } else { "DEVIATION" })
$dA = [System.Numerics.BigInteger]::Abs($pA - $expA); $dB = [System.Numerics.BigInteger]::Abs($pB - $expB)
Log-Step "C5.2" "3.141592653589793238 BNB notified" "alice gets one fifth of it" "alice $(FmtT $pA) vs ideal $(FmtT $expA), difference $dA wei" $(if ($dA -le 16) { "PASS" } else { "DEVIATION" })
Log-Step "C5.3" "bob share of the same notification" "four fifths, i.e. four times alice" "bob $(FmtT $pB) vs ideal $(FmtT $expB), difference $dB wei; bob/alice = $([Math]::Round([double]$pB / [double]$pA, 6))x" $(if ($dB -le 16) { "PASS" } else { "DEVIATION" })
$sum = $pA + $pB
$dust = $oddBI - $sum
Log-Step "C5.4" "Everything accounted for" "the shares sum to the notification bar a few wei of integer-division dust, which stays in the contract - never leaks out" "sum=$sum wei vs notified=$oddBI wei, dust retained = $dust wei" $(if ($dust -ge 0 -and $dust -lt 32) { "PASS" } else { "DEVIATION" })

# And the claims actually pay out what was pending.
$aBefore = Bal $script:Addr.alice
Send "alice" $st.staking "claimReward()" | Out-Null
$aGain = (Bal $script:Addr.alice) - $aBefore
Log-Step "C5.5" "alice claims" "she receives what was pending, minus her own gas" "pending was $(FmtT $pA), balance moved $(FmtT $aGain)" $(if ($aGain -gt 0 -and $aGain -le $pA) { "PASS" } else { "DEVIATION" })
$reserve = CQ $st.staking "zeroStakerReserve()(uint256)"
Log-Step "C5.6" "The zero-staker reserve during a normal distribution" "stays at zero: this path never touches it" "$(FmtT $reserve) BNB" $(if ($reserve -eq 0) { "PASS" } else { "DEVIATION" })
Stop-Anvil
Write-Output "C5 COMPLETE"
