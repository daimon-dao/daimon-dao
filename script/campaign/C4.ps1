# C4 - Finding #35 reproduced on a chain: the dust stake cannot take the backlog.
. .\script\campaign\lib.ps1
Log-Scenario "C4" "Zero-staker backlog vs an atomic dust stake + claim (Zenith #35)"
$st = Bootstrap-Campaign
Claim-Dmn "team1" (BW "20.00") | Out-Null

# A reward arrives while NOBODY is staking - the backlog the finding was about.
$backlog = "4000000000000000000"   # 4 BNB
Send "stranger" $st.staking "notifyRewardAmount(uint256)" @($backlog) -value $backlog | Out-Null
$reserve0 = CQ $st.staking "zeroStakerReserve()(uint256)"
$totalVp0 = CQ $st.staking "totalVotingPower()(uint256)"
Log-Step "C4.1" "4 BNB notified while totalVotingPower is zero" "set aside in the dedicated reserve, NOT added to the distribution accumulator" "zeroStakerReserve = $(FmtT $reserve0) BNB, totalVotingPower = $totalVp0" $(if ($reserve0 -eq [System.Numerics.BigInteger]::Parse($backlog)) { "PASS" } else { "DEVIATION" })

# The attack, atomically: stake 1 wei and claim in ONE transaction.
$r = forge create script/campaign/CampaignAttacker.sol:CampaignAttacker --private-key $script:Key.stranger --rpc-url $script:RPC --broadcast --json 2>&1
if ($LASTEXITCODE -ne 0) { throw "attacker deploy failed: $r" }
$atk = (($r | Out-String) | ConvertFrom-Json).deployedTo
Send "team1" $st.token "transfer(address,uint256)" @($atk, "1000000") | Out-Null
$atkEthBefore = Bal $atk
Send "stranger" $atk "dustStakeAndClaim(address,address,uint256)" @($st.token, $st.staking, "1") | Out-Null
$gain = CQ $atk "lastGain()(uint256)"
$seen = CQ $atk "pendingSeen()(uint256)"
$reserve1 = CQ $st.staking "zeroStakerReserve()(uint256)"
Log-Step "C4.2" "Attacker stakes 1 wei and claims in the SAME transaction" "it sees nothing pending and gains nothing: the backlog was never distributable" "pendingReward seen = $seen wei, BNB gained = $gain wei" $(if ($gain -eq 0 -and $seen -eq 0) { "PASS" } else { "DEVIATION" })
Log-Step "C4.3" "The reserve after the attempt" "untouched - 4 BNB still set aside" "$(FmtT $reserve1) BNB" $(if ($reserve1 -eq $reserve0) { "PASS" } else { "DEVIATION" })

$rev = Expect-Revert "stranger" $st.staking "transferZeroStakerReserve(address,uint256)" @($script:Addr.stranger, "1000000000000000000")
Log-Step "C4.4" "A stranger tries to move the reserve" "refused: recovery is governance-only" "$rev" $(if ("$rev" -match "reverted") { "PASS" } else { "DEVIATION" })

# Governance CAN recover it - shown by acting as the Timelock itself.
$dest = $script:TP_SILENT[0]
$destBefore = Bal $dest
SendAs $st.timelock $st.staking "transferZeroStakerReserve(address,uint256)" @($dest, "$reserve1") | Out-Null
$reserve2 = CQ $st.staking "zeroStakerReserve()(uint256)"
Log-Step "C4.5" "The Timelock recovers the reserve" "it moves only through governance, and only where governance points it" "reserve $(FmtT $reserve1) -> $(FmtT $reserve2), recipient +$(FmtT ((Bal $dest) - $destBefore)) BNB" $(if ($reserve2 -eq 0) { "PASS" } else { "DEVIATION" })
Log-Note "The finding is dead in the way the fix intended: rewards that arrive with nobody staking never enter the distribution accumulator at all, so there is no backlog for a dust stake to capture - the first staker to arrive sees zero pending, atomically or not. The money is not lost either: it waits in a named reserve that only a governance decision can move."
Stop-Anvil
Write-Output "C4 COMPLETE"
