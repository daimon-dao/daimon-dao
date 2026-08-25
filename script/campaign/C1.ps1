# C1 - Staking: voting power follows the lock multipliers.
. .\script\campaign\lib.ps1
Log-Scenario "C1" "Stake at 30 days and at 365 days: voting power per the multipliers"
$st = Bootstrap-Campaign
Claim-Dmn "team1" (BW "20.00") | Out-Null
Send "team1" $st.token "transfer(address,uint256)" @($script:Addr.alice, "$(BW '4.00')") | Out-Null
Send "team1" $st.token "transfer(address,uint256)" @($script:Addr.bob, "$(BW '4.00')") | Out-Null

$aliceAmt = CQ $st.token "balanceOf(address)(uint256)" @($script:Addr.alice)
Stake-Dmn "alice" $aliceAmt 0 | Out-Null      # 30 days, 1.0x
$bobAmt = CQ $st.token "balanceOf(address)(uint256)" @($script:Addr.bob)
Stake-Dmn "bob" $bobAmt 3 | Out-Null          # 365 days, 4.0x

$vpA = CQ $st.staking "votingPower(address)(uint256)" @($script:Addr.alice)
$vpB = CQ $st.staking "votingPower(address)(uint256)" @($script:Addr.bob)
$expA = ($aliceAmt * 1000) / 1000
$expB = ($bobAmt * 4000) / 1000
Log-Step "C1.1" "alice stakes her balance on the 30-day option" "voting power = amount x 1.0" "staked $(FmtB $aliceAmt) -> vp $(FmtB $vpA), expected $(FmtB $expA)" $(if ($vpA -eq $expA) { "PASS" } else { "DEVIATION" })
Log-Step "C1.2" "bob stakes his balance on the 365-day option" "voting power = amount x 4.0" "staked $(FmtB $bobAmt) -> vp $(FmtB $vpB), expected $(FmtB $expB)" $(if ($vpB -eq $expB) { "PASS" } else { "DEVIATION" })

# Normalized per unit staked: the two principals are NOT identical (see the
# note below), so the multipliers must be compared per token, not head to head.
$perUnitA = ($vpA * 1000) / $aliceAmt
$perUnitB = ($vpB * 1000) / $bobAmt
Log-Step "C1.3" "Weight per unit staked, normalized" "1000 (1.0x) for the 30-day lock, 4000 (4.0x) for the 365-day one" "alice=$perUnitA, bob=$perUnitB; raw ratio bob/alice = $([Math]::Round([double]$vpB / [double]$vpA, 4))x on unequal principals" $(if ($perUnitA -eq 1000 -and $perUnitB -eq 4000) { "PASS" } else { "DEVIATION" })
$totalVp = CQ $st.staking "totalVotingPower()(uint256)"
$totalStaked = CQ $st.staking "totalStakedAmount()(uint256)"
Log-Step "C1.4" "Aggregates after both stakes" "totals equal the sum of the parts" "totalVotingPower=$(FmtB $totalVp), totalStaked=$(FmtB $totalStaked)" $(if ($totalVp -eq ($vpA + $vpB) -and $totalStaked -eq ($aliceAmt + $bobAmt)) { "PASS" } else { "DEVIATION" })
Log-Note "Worth recording because it caught out the first version of this very test: alice and bob were sent an identical 4.00 B each, yet ended up staking 3.8003 B and 3.8001 B. In a reflection token two nominally identical transfers do not produce identical balances - the second sender's own reflection share has already moved between them. Any test comparing two holders head to head has to normalize per unit staked; the multipliers themselves are exact."
Stop-Anvil
Write-Output "C1 COMPLETE"
