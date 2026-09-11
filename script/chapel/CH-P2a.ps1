# P2.1 (start) + P2.5 (stakes) -- the 13-day clock starts NOW.
. $PSScriptRoot\lib.ps1
Load-Keystores
$st = S
Log-Scenario "P2.5a" "Stakers migrate and lock: three real accounts, three lock tiers"
$stakes = @(
  @("staker1", "3", "4.0x/365d", "20000000000000000000000000000"),
  @("staker2", "1", "1.5x/90d",  "7500000000000000000000000000"),
  @("staker3", "0", "1.0x/30d",  "5000000000000000000000000000")
)
$n = 1
foreach ($sk in $stakes) {
  $who = $sk[0]
  $h1 = Send $who $st.old "approve(address,uint256)" @($st.migration, "15000000000000000000000000000")
  $h2 = Send $who $st.migration "claim(uint256)" @("15000000000000000000000000000")
  $h3 = Send $who $st.token "approve(address,uint256)" @($st.staking, "5000000000000000000000000000")
  $h4 = Send $who $st.staking "stake(uint256,uint256)" @("5000000000000000000000000000", $sk[1])
  $vp = CQ $st.staking "votingPower(address)(uint256)" @($script:AddrBook.$who)
  Log-Step "P2.5a.$n" "$who migrates 15B, stakes 5B on option $($sk[1]) ($($sk[2]))" "voting power = $($sk[3]) wei" "vp=$(FmtB $vp) ($vp wei); claim gas=$($h2.gasUsed), stake gas=$($h4.gasUsed)" "$($h2.hash) / $($h4.hash)" $(if ("$vp" -eq $sk[3]) { "PASS" } else { "DEVIATION" })
  $n++
}
$tvp = CQ $st.staking "totalVotingPower()(uint256)"
Log-Step "P2.5a.4" "Aggregate voting power" "32.5B = 20 + 7.5 + 5" "$(FmtB $tvp) ($tvp wei)" "-" $(if ("$tvp" -eq "32500000000000000000000000000") { "PASS" } else { "DEVIATION" })

Log-Scenario "P2.1" "Governance cycle, day 1: propose (the 7-day timelock starts its real clock later at queue)"
$calldata = (cast calldata "setFees(uint256,uint256,uint256)" 10 10 20)
$hP = Send "staker1" $st.governor "propose(address,uint256,bytes,string)" @($st.token, "0", "$calldata", "Chapel L2: fees 5 percent to 4 percent (historical proposal 0 replayed on a real clock)")
$pid = (CQ $st.governor "proposalCount()(uint256)") - 1
$snapBlock = ""
$state = CQRaw $st.governor "state(uint256)(uint8)" @("$pid")
$ts = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd HH:mm:ss")
Log-Step "P2.1.1" "staker1 proposes setFees(10,10,20)" "proposal 0 created, state Pending (voting delay 1 REAL day)" "id=$pid, state=$state (0=Pending), proposed at $ts UTC; gas=$($hP.gasUsed)" $hP.hash $(if ($state -eq "0") { "PASS" } else { "DEVIATION" })
Log-Note "The real-time calendar from here: voting opens ~24h after the propose block; the 5-day voting period follows; queue arms the 7-day timelock; execute lands around day 13. Each stage will be recorded with its timestamp and hash as it happens."
$stNew = S
$stNew | Add-Member -NotePropertyName proposalId -NotePropertyValue "$pid" -Force
Save-State $stNew
Write-Output "P2a COMPLETE proposal=$pid"
