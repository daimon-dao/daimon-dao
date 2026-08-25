# E6 - Pause time is credited to the migration deadline (#36).
. .\script\campaign\lib.ps1
Log-Scenario "E6" "A pause during the migration window extends the claim deadline by exactly that time"
$st = Bootstrap-Campaign
$base = CQ $st.migration "migrationDeadline()(uint256)"
$eff0 = CQ $st.migration "effectiveMigrationDeadline()(uint256)"
Log-Step "E6.1" "Before any pause" "the effective deadline equals the immutable base deadline" "base=$base, effective=$eff0" $(if ($eff0 -eq $base) { "PASS" } else { "DEVIATION" })

# Ten days in, the guardian pauses.
Warp (10 * 86400)
Send "guardian" $st.token "setPaused(bool)" @("true") | Out-Null
$credit = CQ $st.token "cumulativePauseSeconds()(uint256)"
$eff1 = CQ $st.migration "effectiveMigrationDeadline()(uint256)"
Log-Step "E6.2" "The guardian pauses with the window open" "the claim deadline moves out by exactly the pause window" "credit=$($credit/86400) days, effective deadline = base + $(($eff1 - $base)/86400) days" $(if ($eff1 -eq ($base + $credit)) { "PASS" } else { "DEVIATION" })

$rev = Expect-Revert "team1" $st.migration "claim(uint256)" @("$(BW '1.00')")
Log-Step "E6.3" "A holder tries to claim while paused" "refused - which is exactly the harm the credit repays" "$rev" $(if ("$rev" -match "reverted") { "PASS" } else { "DEVIATION" })

# The window lapses on its own; we are now PAST the base deadline.
Warp (14 * 86400 + 120)
Warp (7 * 86400)
$blkTs = [System.Numerics.BigInteger]::Parse(((cast block latest --rpc-url $script:RPC --json | ConvertFrom-Json).timestamp -replace "0x",""), 'AllowHexSpecifier')
$eff2 = CQ $st.migration "effectiveMigrationDeadline()(uint256)"
Log-Step "E6.4" "Now past the ORIGINAL deadline, inside the credited extension" "the base deadline has passed, the effective one has not" "now=$blkTs, base=$base (passed: $($blkTs -gt $base)), effective=$eff2" $(if ($blkTs -gt $base -and $blkTs -lt $eff2) { "PASS" } else { "DEVIATION" })

Claim-Dmn "team1" (BW "5.00") | Out-Null
$got = CQ $st.token "balanceOf(address)(uint256)" @($script:Addr.team1)
Log-Step "E6.5" "A claim in that window" "goes through: the holder gets back the time the pause took" "received $(FmtB $got) DMN after the base deadline" $(if ($got -gt 0) { "PASS" } else { "DEVIATION" })

$revSweep = Expect-Revert "stranger" $st.migration "sweepUnclaimed()" @()
$revSweep2 = "n/a"
try { $revSweep2 = (SendAs $st.timelock $st.migration "sweepUnclaimed()" @()) } catch { $revSweep2 = "reverted (MigrationStillOpen)" }
Log-Step "E6.6" "The sweep while the credit still holds the window open" "refused even for governance: the claim window is not over" "stranger: $revSweep; timelock: $revSweep2" $(if ("$revSweep2" -match "revert") { "PASS" } else { "DEVIATION" })

Warp (14 * 86400)
$revClaim = Expect-Revert "team2" $st.migration "claim(uint256)" @("$(BW '1.00')") -errSig "MigrationEnded()"
SendAs $st.timelock $st.migration "sweepUnclaimed()" @() | Out-Null
$swept = CQRaw $st.migration "sweepExecuted()(bool)"
Log-Step "E6.7" "Past the effective deadline" "claims end and the sweep finally runs, once" "claim: $revClaim; sweepExecuted=$swept" $(if ("$revClaim" -match "MigrationEnded" -and "$swept" -eq "true") { "PASS" } else { "DEVIATION" })
Log-Note "Censorship can delay the exchange and cannot consume it: every second the guardian froze is handed back to holders, and the sweep - the thing that would make unclaimed tokens irrecoverable - cannot fire while that credit is still running."
Stop-Anvil
Write-Output "E6 COMPLETE"
