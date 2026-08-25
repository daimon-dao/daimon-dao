# E5 - The expiry: all three authorities die together, and the system self-heals.
. .\script\campaign\lib.ps1
Log-Scenario "E5" "guardianExpiry: three authorities end at one instant (Zenith #36)"
$st = Bootstrap-Campaign
Claim-Dmn "team1" (BW "12.00") | Out-Null
Stake-Dmn "team1" (BW "4.00") 3 | Out-Null
Mine 1
$expiry = CQ $st.token "guardianExpiry()(uint256)"

# A recovery proposal - replacing the guardian itself - queued before expiry.
$newGuardian = $script:TP_SILENT[1]
$calldata = (cast calldata "setGuardian(address)" $newGuardian)
$id = Propose-Call "team1" $st.governor "$calldata" "replace-the-guardian"
Warp (86400 + 60); Vote-Prop "team1" $id 1 | Out-Null; Warp (5 * 86400 + 60)
Queue-Prop $id | Out-Null
Log-Step "E5.1" "A proposal to replace the guardian is queued" "Queued, waiting out the timelock" "$(Prop-State $id)" $(if ((Prop-State $id) -eq "Queued") { "PASS" } else { "DEVIATION" })

# Move to one day before the mandate ends, then pause.
$now = CQ $st.migration "effectiveMigrationDeadline()(uint256)"   # any read, to keep the node warm
$blkTs = [System.Numerics.BigInteger]::Parse(((cast block latest --rpc-url $script:RPC --json | ConvertFrom-Json).timestamp -replace "0x",""), 'AllowHexSpecifier')
Warp ([int]($expiry - $blkTs - 86400))
Send "guardian" $st.token "setPaused(bool)" @("true") | Out-Null
$until = CQ $st.token "pauseUntil()(uint256)"
Log-Step "E5.2" "The guardian pauses one day before its mandate ends" "the window is clamped to the expiry, not 14 days past it" "pauseUntil=$until, guardianExpiry=$expiry" $(if ($until -eq $expiry) { "PASS" } else { "DEVIATION" })

Warp (86400 + 120)
$isP = CQRaw $st.token "isPaused()(bool)"
Log-Step "E5.3" "Past the expiry, with nobody doing anything" "the pause has lapsed by itself - decentralization completes without cooperation" "isPaused=$isP" $(if ("$isP" -eq "false") { "PASS" } else { "DEVIATION" })

$rev1 = Expect-Revert "guardian" $st.token "setPaused(bool)" @("true") -errSig "GuardianExpired()"
Log-Step "E5.4" "The guardian tries to pause again" "refused forever" "$rev1" $(if ("$rev1" -match "GuardianExpired") { "PASS" } else { "DEVIATION" })

$id2 = Propose-Call "team1" $st.token (cast calldata "setFees(uint256,uint256,uint256)" 10 10 20) "post-expiry-proposal"
$rev2 = Expect-Revert "guardian" $st.governor "cancel(uint256)" @("$id2") -errSig "GuardianAuthorityExpired()"
Log-Step "E5.5" "The guardian tries to cancel a proposal" "refused: the Governor path is dead too" "$rev2" $(if ("$rev2" -match "GuardianAuthorityExpired") { "PASS" } else { "DEVIATION" })

$opId = Op-Id $id
$rev3 = Expect-Revert "guardian" $st.timelock "cancel(bytes32)" @($opId) -errSig "GuardianAuthorityExpired()"
Log-Step "E5.6" "The guardian tries to cancel the queued operation at the Timelock" "refused: the third authority is gone at the same instant" "$rev3" $(if ("$rev3" -match "GuardianAuthorityExpired") { "PASS" } else { "DEVIATION" })

Exec-Prop $id | Out-Null
$newG = CQRaw $st.governor "guardian()(address)"
Log-Step "E5.7" "The recovery proposal executes" "uncancellable by anyone: whatever passed the vote and the timelock, executes" "governor.guardian = $newG (was $($script:Addr.guardian))" $(if ("$newG".ToLower() -eq "$newGuardian".ToLower()) { "PASS" } else { "DEVIATION" })
Log-Note "One instant, three authorities. After it the pause is gone without anyone lifting it, both cancellation paths refuse, and a proposal already through the public process cannot be stopped by any single actor - which is exactly what makes the post-expiry recovery path credible."
Stop-Anvil
Write-Output "E5 COMPLETE"
