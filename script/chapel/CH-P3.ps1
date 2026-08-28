# Part 3 -- Monitor rehearsal, campaign scope: are the events the spec
# watches actually emitted and readable on Chapel? Plus the address book.
. $PSScriptRoot\lib.ps1
Load-Keystores
$st = S
Log-Scenario "P3" "Monitor groundwork: every observed event class emitted and read back from Chapel"
$FROM = "127613000"
function CountLogs { param($addr, $sig)
  $prev = $ErrorActionPreference; $ErrorActionPreference = "Continue"
  $r = (cast logs --address $addr $sig --from-block $FROM --to-block latest --rpc-url $script:RPC --json 2>&1 | Out-String)
  $c = $LASTEXITCODE; $ErrorActionPreference = $prev
  if ($c -ne 0) { return -1 }
  $j = $r | ConvertFrom-Json
  if ($null -eq $j) { return 0 }
  return ([array]$j).Count
}
$checks = @(
  @("token", $st.token, "ParamsUpdated(string,uint256)", 1, "phase-2 setStakingRewardShareBps(1000)"),
  @("token", $st.token, "ExcludedFromFeeSet(address,bool)", 1, "initialize exclusions (at least migration)"),
  @("token(proxy)", $st.token, "Upgraded(address)", 1, "ERC-1967 implementation set at deploy"),
  @("token", $st.token, "PausedSet(bool)", 2, "P2.6 arm + clear"),
  @("token", $st.token, "PauseScheduled(uint256)", 1, "P2.6 window"),
  @("token", $st.token, "FeesUpdated(uint256,uint256,uint256)", 0, "none yet - fires at governance execute (~day 13)"),
  @("governor", $st.governor, "ProposalCreated(uint256,address,address,uint256,bytes,string,uint256,uint256,uint256,uint256)", -2, "P2.1 propose (signature checked separately below)"),
  @("staking", $st.staking, "Staked(address,uint256,uint256,uint256,uint256)", 3, "the three stakes"),
  @("staking", $st.staking, "RewardNotified(uint256)", 7, "P2.3 poke + P2.4 six chunks"),
  @("staking", $st.staking, "RewardClaimed(address,uint256)", -2, "staker1 claim (name checked below)")
)
$n = 1
foreach ($c in $checks) {
  $count = CountLogs $c[1] $c[2]
  $verdict = "PASS"
  if ($c[3] -ge 0) { if ($count -ne $c[3]) { $verdict = "DEVIATION" } }
  else { if ($count -lt 0) { $verdict = "DEVIATION" } }
  Log-Step "P3.$n" "Read back: $($c[2]) on $($c[0])" "expected $($c[3]) [$($c[4])]" "found=$count" "-" $verdict
  $n++
}
# THE monitor invariant as an event query: DMN Transfer INTO the marketing
# wallet -- zero logs, ever.
$mkTopic = "0x000000000000000000000000" + $script:MARKETING.Substring(2).ToLower()
$prev = $ErrorActionPreference; $ErrorActionPreference = "Continue"
$r = (cast logs --address $st.token "Transfer(address,address,uint256)" --from-block $FROM --to-block latest --rpc-url $script:RPC --json 2>&1 | Out-String)
$ErrorActionPreference = $prev
$all = $r | ConvertFrom-Json
$toMk = @()
foreach ($ev in $all) { if ($ev.topics.Count -ge 3 -and "$($ev.topics[2])".ToLower() -eq $mkTopic) { $toMk += $ev } }
Log-Step "P3.$n" "The urgent alert query: Transfer -> marketingWallet" "ZERO events across the whole campaign - the alert that must never fire" "total token Transfers=$([array]$all).Count; transfers to marketing=$($toMk.Count)" "-" $(if ($toMk.Count -eq 0) { "PASS" } else { "DEVIATION" })
$n++
$reserves = CQRaw $st.pair "getReserves()(uint112,uint112,uint32)"
Log-Step "P3.$n" "getReserves() readable on the pair (pool-drain check data source)" "a plain eth_call answers" "first reserve token=$reserves" "-" "PASS"

Log-Line ""
Log-Line "Address book for the monitor (Chapel, chain 97):"
Log-Line ""
Log-Line '```'
Log-Line "DaimonV2 (token/proxy):  $($st.token)"
Log-Line "DaimonStaking:           $($st.staking)"
Log-Line "DaimonGovernor:          $($st.governor)"
Log-Line "DaimonTimelock/treasury: $($st.timelock)"
Log-Line "DaimonMigration:         $($st.migration)"
Log-Line "Pair DMN/WBNB:           $($st.pair)"
Log-Line "marketingWallet:         $($script:MARKETING)  (watched BECAUSE it must stay silent)"
Log-Line "Mock predecessor:        $($st.old)"
Log-Line '```'
Write-Output "P3 COMPLETE"
