# H3.1 -- the governance cycle opens: ONE proposal, setStakingRewardShareBps
# (600) on the token; the marketing wallet is already the Timelock. Records
# the id, the snapshot block and the real-clock voting window (5 days).
. $PSScriptRoot\lib.ps1
Load-Keystores
$st = S
if (-not $st.step11b) { throw "run H2-cap.ps1 first" }
if ($st.proposalId) { throw "proposal already created (id $($st.proposalId))" }
Log-Scenario "H3.1" "The first mainnet proposal, rehearsed: propose setStakingRewardShareBps(600) -- one proposal, real clock"

$share0 = CQ $st.token "stakingRewardShareBps()(uint256)"
$mk = CQRaw $st.token "marketingWallet()(address)"
$lpTl = CQ $st.pair "balanceOf(address)(uint256)" @($st.timelock)
$thr = CQ $st.governor "proposalThreshold()(uint256)"
Log-Step "H3.1.1" "Launch state before the proposal" "share 1000, marketing wallet == the Timelock (nothing to rotate: ONE proposal suffices), LP in the Timelock, Timelock BNB zero" "share=$share0, marketingWallet=$mk (timelock=$($st.timelock)), LP in timelock=$lpTl, timelock BNB=$(FmtT (Bal $st.timelock)), proposalThreshold=$(FmtT $thr) DMN of voting power" "-" $(if ($share0 -eq 1000 -and "$mk".ToLower() -eq "$($st.timelock)".ToLower() -and $lpTl -gt 0 -and (Bal $st.timelock) -eq 0) { "PASS" } else { "DEVIATION" })

# ---- The proposer needs voting power: the holder stakes 1B on option 3 ---
$stakeAmt = BW "1.00"
$hA = Send "holder" $st.token "approve(address,uint256)" @($st.staking, "$stakeAmt")
$hS = Send "holder" $st.staking "stake(uint256,uint256)" @("$stakeAmt", "3")
$vp = CQ $st.staking "votingPower(address)(uint256)" @($script:AddrBook.holder)
$tvp = CQ $st.staking "totalVotingPower()(uint256)"
Log-Step "H3.1.2" "The holder stakes 1.00 B DMN on lock option 3 (365 days, 4.0x)" "voting power == 4.00 B exactly (>= the threshold); totalVotingPower == the same (first and only staker)" "votingPower=$(FmtB $vp) ($vp wei), totalVotingPower=$(FmtB $tvp); stake block $($hS.block), gas=$($hS.gasUsed)" "$($hA.hash) / $($hS.hash)" $(if ($vp -eq ($stakeAmt * 4) -and $tvp -eq $vp -and $vp -ge $thr) { "PASS" } else { "DEVIATION" })
Start-Sleep -Seconds 6   # the stake checkpoint must sit in a block BEFORE the proposal's snapshot (#12)

# ---- propose ---------------------------------------------------------------
$calldata = (cast calldata "setStakingRewardShareBps(uint256)" 600)
$desc = "Chapel 2b H3.1: setStakingRewardShareBps(600) -- the operational share restored by governance; the marketing wallet is the Timelock"
$hP = Send "holder" $st.governor "propose(address,uint256,bytes,string)" @($st.token, "0", "$calldata", $desc)
$pid = (CQ $st.governor "proposalCount()(uint256)") - 1
$rcpt = (cast receipt $hP.hash --json --rpc-url $script:RPC | Out-String) | ConvertFrom-Json
$evTopic = (cast keccak "ProposalCreated(uint256,address,address,string)")
$evId = ""
foreach ($lg in $rcpt.logs) { if ("$($lg.topics[0])".ToLower() -eq "$evTopic".ToLower()) { $evId = [System.Numerics.BigInteger]::Parse("0" + "$($lg.topics[1])".Substring(2), "AllowHexSpecifier") } }
$state = Prop-State $pid
$target = Prop-Field $pid 1
$data = Prop-Field $pid 3
$snap = [System.Numerics.BigInteger]::Parse((Prop-Field $pid 5))
$snapTvp = [System.Numerics.BigInteger]::Parse((Prop-Field $pid 6))
$vStart = [System.Numerics.BigInteger]::Parse((Prop-Field $pid 7))
$vEnd = [System.Numerics.BigInteger]::Parse((Prop-Field $pid 8))
$qbps = [System.Numerics.BigInteger]::Parse((Prop-Field $pid 16))
$blkTs = [System.Numerics.BigInteger]::Parse(((cast block $hP.block --field timestamp --rpc-url $script:RPC | Out-String).Trim()))
$epoch = [DateTime]::new(1970, 1, 1, 0, 0, 0, [DateTimeKind]::Utc)
$vStartUtc = $epoch.AddSeconds([double]"$vStart").ToString("yyyy-MM-dd HH:mm:ss")
$vEndUtc = $epoch.AddSeconds([double]"$vEnd").ToString("yyyy-MM-dd HH:mm:ss")
$execUtc = $epoch.AddSeconds([double]"$vEnd" + 7 * 86400).ToString("yyyy-MM-dd HH:mm:ss")
$ok = ($state -eq "Pending" -and "$evId" -eq "$pid" -and "$target".ToLower() -eq "$($st.token)".ToLower() -and "$data".ToLower() -eq "$calldata".ToLower() -and $snap -eq ($hP.block - 1) -and $snapTvp -eq $vp -and $vStart -eq ($blkTs + 86400) -and ($vEnd - $vStart) -eq 432000 -and $qbps -eq 1000)
Log-Step "H3.1.3" "The holder proposes setStakingRewardShareBps(600) on the token" "state Pending; ProposalCreated id == proposalCount-1; target == token, data == the calldata; snapshotBlock == propose block - 1; snapshotTotalVotingPower == 4.00 B; voteStart == block timestamp + 1 day; voteEnd - voteStart == 432000 s (5 days); quorum snapshot 1000 bps" "id=$pid (event id=$evId), state=$state, target=$target, data=$data; propose block=$($hP.block) ts=$blkTs, snapshotBlock=$snap, snapshotTotalVotingPower=$(FmtB $snapTvp); voteStart=$vStart ($vStartUtc UTC), voteEnd=$vEnd ($vEndUtc UTC), window=$($vEnd - $vStart) s; quorumBpsSnapshot=$qbps; gas=$($hP.gasUsed)" $hP.hash $(if ($ok) { "PASS" } else { "DEVIATION" })
Log-Note "Real-clock calendar from here: voting opens at $vStartUtc UTC (24 h after the propose block), closes at $vEndUtc UTC (5 days later); queue any time after that arms the 7-day Timelock; the earliest execute, if queued at once, is $execUtc UTC. H3.2-H3.5 and the H4 drill follow on that calendar. The monitor's expected URGENT on ProposalCreated (it touches stakingRewardShareBps) is to be confirmed by hand."
$st | Add-Member -NotePropertyName proposalId -NotePropertyValue "$pid" -Force
$st | Add-Member -NotePropertyName proposeTx -NotePropertyValue $hP.hash -Force
$st | Add-Member -NotePropertyName proposeBlock -NotePropertyValue "$($hP.block)" -Force
$st | Add-Member -NotePropertyName snapshotBlock -NotePropertyValue "$snap" -Force
$st | Add-Member -NotePropertyName voteStart -NotePropertyValue "$vStart" -Force
$st | Add-Member -NotePropertyName voteEnd -NotePropertyValue "$vEnd" -Force
Save-State $st
Write-Output "H3a COMPLETE proposal=$pid voting $vStartUtc -> $vEndUtc UTC"
