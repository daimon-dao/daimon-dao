# P1.5 -- The migration window opens LAST: no-claim proof, then the exemption.
# P1.8 -- One pool only, stored pair == factory pair.
. $PSScriptRoot\lib.ps1
Load-Keystores
$st = S
Log-Scenario "P1.5" "The exemption goes last: claims impossible during the window, then opened"

$rev = Expect-Revert "holder1" $st.old "approve(address,uint256)" @($st.migration, "170000000000000000000000000000")
# approve succeeds (it is not gated); the CLAIM is what must revert.
$hApp = $rev
if ($rev -match "DID-NOT-REVERT") { $hApp = "approved (as expected - approvals are not gated)" }
$rev2 = Expect-Revert "holder1" $st.migration "claim(uint256)" @("10000000000000000000000000000") -errSig "AmountMismatch()"
Log-Step "P1.5.1" "holder1 attempts a 10B claim BEFORE the exemption exists" "REVERTS with AmountMismatch (#29): the treasury is not fee-exempt on the predecessor, so no claim was possible at any point between the phases" "$hApp; claim: $rev2" "-" $(if ("$rev2" -match "AmountMismatch") { "PASS" } else { "DEVIATION" })

$h = Send "deployer" $st.old "excludeFromFee(address)" @($st.timelock)
$ex = CQRaw $st.old "excludedFromFee(address)(bool)" @($st.timelock)
Log-Step "P1.5.2" "excludeFromFee(TIMELOCK) on the mock predecessor - launch order step 4" "exemption active: the migration window effectively OPENS here" "excludedFromFee(timelock)=$ex" $h.hash $(if ("$ex" -eq "true") { "PASS" } else { "DEVIATION" })

$hC = Send "holder1" $st.migration "claim(uint256)" @("1000000000000000000000000000")
$got = CQ $st.token "balanceOf(address)(uint256)" @($script:AddrBook.holder1)
Log-Step "P1.5.3" "The same holder claims 1B immediately after" "exact 1:1 receipt - the window is open and clean" "DMN=$(FmtB $got) ($got wei), gas=$($hC.gasUsed)" $hC.hash $(if ("$got" -eq "1000000000000000000000000000") { "PASS" } else { "DEVIATION" })

Log-Scenario "P1.8" "One pool only: stored pair == factory pair"
$router = "0xD99D1c33F9fC3444f8101754aBC46c52416550D1"
$factory = CQRaw $router "factory()(address)"
$wbnb = CQRaw $router "WETH()(address)"
$factPair = CQRaw $factory "getPair(address,address)(address)" @($st.token, $wbnb)
Log-Step "P1.8.1" "The pair the contracts store vs the pair the factory created" "identical - a wrong address breaks fee-swap and buyback silently" "token.uniswapV2Pair=$($st.pair), factory.getPair=$factPair" "-" $(if ("$factPair".ToLower() -eq "$($st.pair)".ToLower()) { "PASS" } else { "DEVIATION" })
Write-Output "P1e COMPLETE"
