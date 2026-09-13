# H1 steps 3-4 -- the MANDATORY GATE (36/36 from mined state, output
# verbatim), automation inert while the pair has no reserves, and the
# window still closed: a non-owner claim reverts before 11b.
. $PSScriptRoot\lib.ps1
Load-Keystores
$st = S
if (-not $st.timelock) { throw "run H1c-phase2.ps1 first" }
Log-Scenario "H1 (3-4)" "Step 3: the 36-check gate on Chapel; step 4: automation inert without reserves; the window closed to non-owners"

$r = Run-Verify
$vExit = $r[0]; $vOut = $r[1]
$vTail = (($vOut -split "`r?`n" | Where-Object { $_ -match 'VERIFICATION' }) -join ' ')
Log-Step "H1.7" "Step 3: script/verify-deploy.ps1 -Rpc <chapel> (H0.3: 34 -> 36 checks)" "36/36 green, exit code 0 -- the MANDATORY GATE" "exit=$vExit; $vTail" "-" $(if ($vExit -eq 0 -and $vTail -match "36/36") { "PASS" } else { "DEVIATION" })
Log-Block "Full output of the verification, verbatim:" $vOut
if ($vExit -ne 0 -or -not ($vTail -match "36/36")) { Write-Output "H1d STOPPED: verification failed -- CAMPAIGN STOPS"; exit 1 }

$sal = CQRaw $st.token "swapAndLiquifyEnabled()(bool)"; $bbe = CQRaw $st.token "buyBackEnabled()(bool)"
$inv0 = Fee-Inventory
$res = Pair-Reserves
Log-Step "H1.8" "Step 4: automation state before liquidity (#27)" "enabled by initialize, inert by construction: no inventory, reserves (0,0), pokes are the only trigger" "swapAndLiquifyEnabled=$sal buyBackEnabled=$bbe, inventory=$(FmtB $inv0), pair=$($st.pair) reserves=($($res[0]),$($res[1]))" "-" $(if ("$sal" -eq "true" -and $inv0 -eq 0 -and $res[0] -eq 0 -and $res[1] -eq 0) { "PASS" } else { "DEVIATION" })

$hA = Send "holder" $st.old "approve(address,uint256)" @($st.migration, "$(BW '1.00')") -NoInvariant
$rev = Expect-Revert "holder" $st.migration "claim(uint256)" @("$(BW '1.00')") -errSig "AmountMismatch()"
$hDmn = CQ $st.token "balanceOf(address)(uint256)" @($script:AddrBook.holder)
Log-Step "H1.9" "A NON-owner (the holder, 5B DMX, not exempt) claims 1.00 B after the gate, BEFORE 11b" "refused with AmountMismatch (#29): the treasury is not fee-exempt on the predecessor, the 11% fee breaks the 1:1 -- no claim is possible against this deployment yet; the approve itself is not gated" "approve tx ok; claim: $rev; holder DMN=$hDmn" $hA.hash $(if ("$rev" -match "reverted with AmountMismatch" -and $hDmn -eq 0) { "PASS" } else { "DEVIATION" })
Assert-Invariants "post-gate"
Write-Output "H1d COMPLETE (gate 36/36)"
