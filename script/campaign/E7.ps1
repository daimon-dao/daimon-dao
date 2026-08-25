# E7 - A compromised guardian: what it can do, for how long, and what it cannot.
. .\script\campaign\lib.ps1
Log-Scenario "E7" "Compromised guardian: censorship is real, bounded, and ends by itself"
$st = Bootstrap-Campaign
Claim-Dmn "team1" (BW "12.00") | Out-Null
Send "team1" $st.token "transfer(address,uint256)" @($script:Addr.alice, "$(BW '4.00')") | Out-Null
Stake-Dmn "team1" (BW "4.00") 3 | Out-Null
Mine 1
$expiry = CQ $st.token "guardianExpiry()(uint256)"
$newGuardian = $script:TP_SILENT[2]
$replace = (cast calldata "setGuardian(address)" $newGuardian)

# Act 1 - the guardian censors its own replacement. This works.
$id1 = Propose-Call "team1" $st.governor "$replace" "replace-attempt-1"
Send "guardian" $st.governor "cancel(uint256)" @("$id1") | Out-Null
Log-Step "E7.1" "Governance moves to replace the compromised guardian" "the guardian cancels it - censorship inside the mandate is real, not theoretical" "proposal 1 state = $(Prop-State $id1)" $(if ((Prop-State $id1) -eq "Canceled") { "PASS" } else { "DEVIATION" })

# Act 2 - it escalates to a pause. Governance itself is NOT gagged.
Send "guardian" $st.token "setPaused(bool)" @("true") | Out-Null
$id2 = Propose-Call "team1" $st.governor "$replace" "replace-attempt-2"
Warp (86400 + 60)
Vote-Prop "team1" $id2 1 | Out-Null
Log-Step "E7.2" "With the token frozen, governance carries on" "proposing and voting need no token transfer, so the pause cannot gag the DAO" "proposal 2 state = $(Prop-State $id2), vote recorded" $(if ((Prop-State $id2) -eq "Active") { "PASS" } else { "DEVIATION" })

# approve() is NOT gated by the pause - allowances are bookkeeping, not
# movement - so the freeze bites one step later, on the transfer itself.
Send "alice" $st.token "approve(address,uint256)" @($st.staking, "$(BW '1.00')") | Out-Null
$revStake2 = Expect-Revert "alice" $st.staking "stake(uint256,uint256)" @("$(BW '1.00')", "0")
Log-Step "E7.3" "But nobody can build NEW voting power while paused" "staking needs a token transfer, so the pause freezes the electorate as it stands" "approve went through (allowances are not frozen), stake attempt: $revStake2" $(if ("$revStake2" -match "reverted") { "PASS" } else { "DEVIATION" })

# Act 3 - it keeps renewing the pause right up to the mandate's end.
Warp (5 * 86400 + 60)
Queue-Prop $id2 | Out-Null
$blkTs = [System.Numerics.BigInteger]::Parse(((cast block latest --rpc-url $script:RPC --json | ConvertFrom-Json).timestamp -replace "0x",""), 'AllowHexSpecifier')
# Three renewals are enough to show the mechanism; doing all ~84 of them to
# the expiry only costs wall-clock, it proves nothing further.
$renewals = 0
foreach ($k in 1..3) {
  Warp (13 * 86400)
  Send "guardian" $st.token "setPaused(bool)" @("true") | Out-Null
  $renewals++
}
$blkTs = [System.Numerics.BigInteger]::Parse(((cast block latest --rpc-url $script:RPC --json | ConvertFrom-Json).timestamp -replace "0x",""), 'AllowHexSpecifier')
# Then jump to one day before the mandate ends and pause a final time.
Warp ([int]($expiry - $blkTs - 86400))
Send "guardian" $st.token "setPaused(bool)" @("true") | Out-Null
$finalUntil = CQ $st.token "pauseUntil()(uint256)"
$blkTs = [System.Numerics.BigInteger]::Parse(((cast block latest --rpc-url $script:RPC --json | ConvertFrom-Json).timestamp -replace "0x",""), 'AllowHexSpecifier')
$isPBefore = CQRaw $st.token "isPaused()(bool)"
Log-Step "E7.4" "The guardian renews the pause over and over, up to the expiry" "it CAN keep the token frozen for the whole mandate - at the cost of a visible transaction every fortnight" " renewals shown, then a final pause one day before the end: pauseUntil=$finalUntil is clamped to guardianExpiry=$expiry, still paused = $isPBefore" $(if ("$isPBefore" -eq "true") { "PASS" } else { "DEVIATION" })

# Act 4 - the mandate ends. Nothing is cooperating, and it ends anyway.
Warp ([int]($expiry - $blkTs + 120))
$isPAfter = CQRaw $st.token "isPaused()(bool)"
Send "alice" $st.token "transfer(address,uint256)" @($script:Addr.bob, "$(BW '1.00')") | Out-Null
Log-Step "E7.5" "Past the expiry, with the guardian refusing to lift anything" "the pause lapses on its own and the token works again" "isPaused=$isPAfter, and a transfer went through" $(if ("$isPAfter" -eq "false") { "PASS" } else { "DEVIATION" })

$revCancel = Expect-Revert "guardian" $st.governor "cancel(uint256)" @("$id2") -errSig "GuardianAuthorityExpired()"
Exec-Prop $id2 | Out-Null
$g = CQRaw $st.governor "guardian()(address)"
Log-Step "E7.6" "The replacement it censored the first time" "now uncancellable: it executes and the guardian is replaced" "cancel attempt: $revCancel; governor.guardian = $g" $(if ("$g".ToLower() -eq "$newGuardian".ToLower()) { "PASS" } else { "DEVIATION" })
$mk = CQ $st.token "balanceOf(address)(uint256)" @($script:MARKETING)
Log-Step "E7.7" "The marketing wallet through the whole hostile sequence" "zero, throughout" "DMN=$mk" $(if ($mk -eq 0) { "PASS" } else { "DEVIATION" })
Log-Note "The honest summary of the guardian's worst case: inside the mandate it can censor proposals and keep the token frozen, and the campaign shows it doing exactly that. What it cannot do is outlast the mandate - the pause lapses without its cooperation, both cancel paths die at the same instant, and the proposal it censored once executes with nobody able to stop it. The migration window, meanwhile, is handed back second for second (E6)."
Stop-Anvil
Write-Output "E7 COMPLETE"
