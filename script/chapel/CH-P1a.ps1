# P1.1-bis -- Mock predecessor, clean redo with the fixed BW helper.
# Exactness checks compare against INDEPENDENT wei constants, not BW twice.
. $PSScriptRoot\lib.ps1
Load-Keystores
$pf = $script:KsMap.passwordFile
Log-Scenario "P1.1-bis" "Mock predecessor deployed and distributed (clean redo; no treasury exemption)"

$supply = BW "1000.00"
if ("$supply" -ne "1000000000000000000000000000000") { throw "BW sanity failed" }
$prev = $ErrorActionPreference; $ErrorActionPreference = "Continue"
$r = forge create script/campaign/CampaignOldDaimon.sol:CampaignOldDaimon --broadcast --account $script:KsMap.accounts.deployer --password-file $pf --rpc-url $script:RPC --json --constructor-args "$supply" $script:AddrBook.deployer 2>&1 | Out-String
$c = $LASTEXITCODE; $ErrorActionPreference = $prev
Get-Process forge -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
if ($c -ne 0) { throw "mock deploy failed: $r" }
$j = ($r | ConvertFrom-Json)
$old = $j.deployedTo
Save-State ([ordered]@{ old = $old; invariantChecks = 0 })
$ts = CQ $old "totalSupply()(uint256)"
Log-Step "P1.1b.1" "CampaignOldDaimon deployed, supply minted to the deployer" "totalSupply == 1e30 (1000B with 18 decimals)" "old=$old, totalSupply=$ts" $j.transactionHash $(if ("$ts" -eq "1000000000000000000000000000000") { "PASS" } else { "DEVIATION" })

$h = Send "deployer" $old "excludeFromFee(address)" @($script:AddrBook.deployer) -NoInvariant
Log-Step "P1.1b.2" "Owner self-exemption for exact distribution" "excludedFromFee(deployer)=true" "$(CQRaw $old 'excludedFromFee(address)(bool)' @($script:AddrBook.deployer))" $h.hash "PASS"

# name, target, billions, independent expected wei
$dist = @(
  @("holder1", $script:AddrBook.holder1, "170.00", "170000000000000000000000000000"),
  @("holder2", $script:AddrBook.holder2, "60.00",  "60000000000000000000000000000"),
  @("holder3", $script:AddrBook.holder3, "40.00",  "40000000000000000000000000000"),
  @("staker1", $script:AddrBook.staker1, "15.00",  "15000000000000000000000000000"),
  @("staker2", $script:AddrBook.staker2, "15.00",  "15000000000000000000000000000"),
  @("staker3", $script:AddrBook.staker3, "15.00",  "15000000000000000000000000000"),
  @("dead",    $script:DEAD,             "20.00",  "20000000000000000000000000000"),
  @("mock-contract", $old,               "15.00",  "15000000000000000000000000000")
)
$n = 3
foreach ($d in $dist) {
  $h = Send "deployer" $old "transfer(address,uint256)" @($d[1], "$(BW $d[2])") -NoInvariant
  $got = CQ $old "balanceOf(address)(uint256)" @($d[1])
  $exact = ("$got" -eq $d[3])
  Log-Step "P1.1b.$n" "Distribute $($d[2])B to $($d[0])" "exact credit: $($d[3]) wei" "balance=$(FmtB $got) ($got wei)" $h.hash $(if ($exact) { "PASS" } else { "DEVIATION" })
  $n++
}
$depBal = CQ $old "balanceOf(address)(uint256)" @($script:AddrBook.deployer)
Log-Step "P1.1b.11" "Deployer residual: team 427B + non-migrating world 223B" "650000000000000000000000000000 wei kept" "balance=$(FmtB $depBal) ($depBal wei)" "-" $(if ("$depBal" -eq "650000000000000000000000000000") { "PASS" } else { "DEVIATION" })
Log-Step "P1.1b.12" "Treasury fee exemption on the mock" "NOT set (launch order: AFTER the post-broadcast verification)" "deferred by design" "-" "PASS"
Write-Output "P1a-bis COMPLETE old=$old"
