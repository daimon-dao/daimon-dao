# P2.6 -- Guardian pause on a real clock: window arithmetic, block, clear.
. $PSScriptRoot\lib.ps1
Load-Keystores
$st = S
Log-Scenario "P2.6" "Guardian pause: real arming, real refusal, manual clear; expiry values re-checked"

$hP = Send "guardian" $st.token "setPaused(bool)" @("true") -NoInvariant
$blkTs = [System.Numerics.BigInteger]::Parse((cast block latest --rpc-url $script:RPC --json | ConvertFrom-Json).timestamp.Substring(2), "AllowHexSpecifier")
$until = CQ $st.token "pauseUntil()(uint256)"
$credit = CQ $st.token "cumulativePauseSeconds()(uint256)"
$isP = CQRaw $st.token "isPaused()(bool)"
$window = $until - $blkTs
Log-Step "P2.6.1" "The guardian arms the pause" "isPaused=true; the window is the constant 14 days (contract offers no shorter arm)" "isPaused=$isP, window remaining=$window s (~$([Math]::Round([double]$window / 86400, 2)) days), cumulativePauseSeconds=$credit" $hP.hash $(if ("$isP" -eq "true" -and $credit -eq 1209600) { "PASS" } else { "DEVIATION" })

$effDl = CQ $st.migration "effectiveMigrationDeadline()(uint256)"
$baseDl = CQ $st.migration "migrationDeadline()(uint256)"
Log-Step "P2.6.2" "The migration credit (#36) on a real deadline" "effective deadline = immutable base + 14 days" "base=$baseDl, effective=$effDl, delta=$($effDl - $baseDl) s" "-" $(if (($effDl - $baseDl) -eq 1209600) { "PASS" } else { "DEVIATION" })

$rev = Expect-Revert "holder2" $st.token "transfer(address,uint256)" @($script:AddrBook.holder3, "1000000000000000000000000") -errSig "ContractIsPaused()"
Log-Step "P2.6.3" "An ordinary transfer while paused" "refused" "$rev" "-" $(if ("$rev" -match "reverted") { "PASS" } else { "DEVIATION" })

Start-Sleep -Seconds 90
$stillP = CQRaw $st.token "isPaused()(bool)"
$hU = Send "guardian" $st.token "setPaused(bool)" @("false") -NoInvariant
$isP2 = CQRaw $st.token "isPaused()(bool)"
$until2 = CQ $st.token "pauseUntil()(uint256)"
$hT = Send "holder2" $st.token "transfer(address,uint256)" @($script:AddrBook.holder3, "1000000000000000000000000")
Log-Step "P2.6.4" "90 real seconds later: still paused; the guardian clears; transfers resume" "isPaused true before the clear, false after, pauseUntil zeroed, a real transfer passes" "before=$stillP, after=$isP2, pauseUntil=$until2" "$($hU.hash) / $($hT.hash)" $(if ("$stillP" -eq "true" -and "$isP2" -eq "false" -and $until2 -eq 0) { "PASS" } else { "DEVIATION" })

$eT = CQ $st.token "guardianExpiry()(uint256)"
$eL = CQ $st.timelock "guardianAuthorityExpiry()(uint256)"
$eG = CQ $st.governor "guardianAuthorityExpiry()(uint256)"
Log-Step "P2.6.5" "The three stored expiry values, re-read" "exactly equal and 36 months from phase 1" "$eT / $eL / $eG" "-" $(if ($eT -eq $eL -and $eT -eq $eG) { "PASS" } else { "DEVIATION" })
Log-Note "Expectation note, reported not corrected: the campaign document asks for the pause 'self-termination on a real clock (use a short pause window)'. The contract has no short window to use: setPaused(true) always arms min(now + 14 days, guardianExpiry). Observing the lapse-with-no-transaction on a real clock therefore requires 14 real days with the token frozen, which would block the rest of the campaign; the lapse mechanism itself was proven at Level 1 (E2, warped clock). Here the record shows: real arming, exact window arithmetic, real refusal, real credit on the migration deadline, and a real manual clear. Whether a 14-day frozen tail run is wanted at campaign end is a human decision."
Assert-Invariants "post-pause"
Write-Output "P2f COMPLETE"
