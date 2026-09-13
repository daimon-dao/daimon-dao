# H1 (0) -- The predecessor mock on Chapel, deployed and OWNED by oldowner:
# the DMX-faithful CampaignOldDaimon with the 1.5B cap (H0.5). The owner
# self-exempts (exact distribution) and hands the holder 5B. NO treasury
# exemption, NO cap change: 11a/11b are the last steps of the day (H2).
. $PSScriptRoot\lib.ps1
Load-Keystores
$st = S
if (-not $st) { throw "run D1-header.ps1 first" }
if ($st.old) { throw "mock already deployed at $($st.old)" }
Log-Scenario "H1 (0)" "The predecessor mock: deployed and owned by oldowner, the real 1.5B cap, no exemption for the treasury yet"

$supply = BW "1000.00"
if ("$supply" -ne "1000000000000000000000000000000") { throw "BW sanity failed" }
$prev = $ErrorActionPreference; $ErrorActionPreference = "Continue"
$r = forge create script/campaign/CampaignOldDaimon.sol:CampaignOldDaimon --broadcast --account (Ks "oldowner") --password-file (Pf) --rpc-url $script:RPC --json --constructor-args "$supply" $script:AddrBook.oldowner 2>&1 | Out-String
$c = $LASTEXITCODE; $ErrorActionPreference = $prev
Get-Process forge -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
if ($c -ne 0) { throw "mock deploy failed: $r" }
$j = ($r | ConvertFrom-Json)
$old = $j.deployedTo
$st | Add-Member -NotePropertyName old -NotePropertyValue $old -Force
Save-State $st
$ts = CQ $old "totalSupply()(uint256)"
$owner = CQRaw $old "owner()(address)"
$cap = CQ $old "maxTxAmount()(uint256)"
Log-Step "H1.0.1" "CampaignOldDaimon deployed by oldowner, supply minted to oldowner" "totalSupply == 1e30; owner() == oldowner; maxTxAmount == 1.5B (the real DMX value, read 2026-09-11)" "old=$old, totalSupply=$ts, owner=$owner, maxTxAmount=$(FmtB $cap) ($cap wei)" $j.transactionHash $(if ("$ts" -eq "1000000000000000000000000000000" -and "$owner".ToLower() -eq "$($script:AddrBook.oldowner)".ToLower() -and "$cap" -eq "1500000000000000000000000000") { "PASS" } else { "DEVIATION" })

$h = Send "oldowner" $old "excludeFromFee(address)" @($script:AddrBook.oldowner) -NoInvariant
$ex = CQRaw $old "excludedFromFee(address)(bool)" @($script:AddrBook.oldowner)
Log-Step "H1.0.2" "Owner self-exemption on the mock (exact distribution; and the property step 5a relies on)" "excludedFromFee(oldowner) == true; the owner is cap-exempt by construction (from/to owner)" "excludedFromFee(oldowner)=$ex, owner=$owner" $h.hash $(if ("$ex" -eq "true") { "PASS" } else { "DEVIATION" })

$h2 = Send "oldowner" $old "transfer(address,uint256)" @($script:AddrBook.holder, "$(BW '5.00')") -NoInvariant
$hb = CQ $old "balanceOf(address)(uint256)" @($script:AddrBook.holder)
Log-Step "H1.0.3" "Distribute 5.00 B of mock DMX to the holder (the non-owner claimant of H1 and H2)" "exact credit: 5000000000000000000000000000 wei (sender exempt, no fee; sender is the owner, no cap)" "holder old balance=$(FmtB $hb) ($hb wei)" $h2.hash $(if ("$hb" -eq "5000000000000000000000000000") { "PASS" } else { "DEVIATION" })

$hex = CQRaw $old "excludedFromFee(address)(bool)" @($script:AddrBook.holder)
$dex = CQRaw $old "excludedFromFee(address)(bool)" @($script:AddrBook.deployer)
Log-Step "H1.0.4" "The holder and the deployer on the mock" "neither is the owner, neither is fee-exempt: on this predecessor only oldowner can move DMX without fee or cap" "excludedFromFee(holder)=$hex, excludedFromFee(deployer)=$dex, owner=$owner" "-" $(if ("$hex" -eq "false" -and "$dex" -eq "false" -and "$owner".ToLower() -ne "$($script:AddrBook.deployer)".ToLower()) { "PASS" } else { "DEVIATION" })
Log-Step "H1.0.5" "Treasury exemption and cap on the mock" "NOT set, NOT raised: 11a/11b come last (H2), after the gate, the liquidity and the first poke" "excludedFromFee(<timelock>) cannot exist yet (no timelock); maxTxAmount=$(FmtB $cap)" "-" "PASS"
Write-Output "H1a COMPLETE old=$old"
