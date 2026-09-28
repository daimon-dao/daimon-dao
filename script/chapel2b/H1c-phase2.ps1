# H1 step 2 (phase 2) -- DeployPhase2: the Timelock lands on the prediction,
# setFees(10,10,20) through the TEMPORARY role BEFORE the grant to the
# Timelock, then grant/revoke; expiry read from the live token. The order
# of the three calls is asserted from the broadcast journal AND from the
# receipts on chain.
. $PSScriptRoot\lib.ps1
Load-Keystores
$st = S
if (-not $st.token) { throw "run H1b-phase1.ps1 first" }
if ($st.timelock) { throw "phase 2 already broadcast: timelock=$($st.timelock)" }
Log-Scenario "H1 (2, phase 2)" "Phase 2: the Timelock on the prediction, fees 10/10/20 set by the temporary role before the hand-over, one expiry on three contracts"

$stateFile = Join-Path $script:ROOT (Join-Path "deployments" "two-phase-97.json")
$nonceNow = Nonce $script:AddrBook.deployer
Log-Step "H1.4.0" "The deployer's live nonce right before phase 2" "== expectedPhase2Nonce: nothing was signed between the phases" "nonce=$nonceNow, expected=$($st.expectedPhase2Nonce)" "-" $(if ("$nonceNow" -eq "$($st.expectedPhase2Nonce)") { "PASS" } else { "DEVIATION" })
if ("$nonceNow" -ne "$($st.expectedPhase2Nonce)") { throw "STOP: the deployer nonce moved between the phases -- abandon and redeploy phase 1 (the script's own rule)" }

$r2 = Run-ForgeScript "script/DeployPhase2.s.sol" "deployer" -Broadcast
if ($r2[0] -ne 0) { Log-Block "Phase 2 output (FAILED), verbatim:" $r2[1]; throw "PHASE 2 FAILED:`n$($r2[1])" }
$dep = Get-Content $stateFile -Raw | ConvertFrom-Json
if (-not $dep.governor) { throw "phase 2 did not complete the state file" }

$pt = "$($st.predictedTimelock)".ToLower()
Log-Step "H1.4" "Phase 2 broadcast: timelock + staking + governor + wiring + renounce" "the Timelock lands EXACTLY on the phase-1 prediction (the fourth fulfilment of one address: governance, treasury, marketing wallet, and now the contract itself)" "timelock=$($dep.timelock), predicted=$($st.predictedTimelock), match=$("$($dep.timelock)".ToLower() -eq $pt); staking=$($dep.staking), governor=$($dep.governor)" "journal broadcast/DeployPhase2.s.sol/97" $(if ("$($dep.timelock)".ToLower() -eq $pt) { "PASS" } else { "DEVIATION" })
if ("$($dep.timelock)".ToLower() -ne $pt) { throw "STOP: the Timelock missed the prediction" }

# ---- H0.2: the fees, from mined state, and the ORDER of the three calls ---
$tax = CQ $dep.token "taxFee()(uint256)"; $buy = CQ $dep.token "buybackFee()(uint256)"; $mkt = CQ $dep.token "marketingFee()(uint256)"; $liq = CQ $dep.token "liquidityFee()(uint256)"
$govRole = CQRaw $dep.token "GOVERNANCE_ROLE()(bytes32)"
$tlHas = CQRaw $dep.token "hasRole(bytes32,address)(bool)" @($govRole, $dep.timelock)
$depHas = CQRaw $dep.token "hasRole(bytes32,address)(bool)" @($govRole, $script:AddrBook.deployer)
Log-Step "H1.5" "H0.2 on a public chain: the fees read from the live token right after phase 2, and who holds GOVERNANCE_ROLE now" "10/10/20, liquidityFee 30 (4% total from the first block); the Timelock holds the role, the deployer does not" "taxFee=$tax buybackFee=$buy marketingFee=$mkt liquidityFee=$liq; hasRole(timelock)=$tlHas, hasRole(deployer)=$depHas" "-" $(if ($tax -eq 10 -and $buy -eq 10 -and $mkt -eq 20 -and $liq -eq 30 -and "$tlHas" -eq "true" -and "$depHas" -eq "false") { "PASS" } else { "DEVIATION" })

$bc = Get-Content (Join-Path $script:ROOT "broadcast\DeployPhase2.s.sol\97\run-latest.json") -Raw | ConvertFrom-Json
$txs = @($bc.transactions)
$tokenL = "$($dep.token)".ToLower(); $tlL = "$($dep.timelock)".ToLower(); $depL = "$($script:AddrBook.deployer)".ToLower()
$iFees = -1; $iGrant = -1; $iRevoke = -1
for ($i = 0; $i -lt $txs.Count; $i++) {
  $t = $txs[$i]
  $to = "$($t.contractAddress)".ToLower()
  if ($to -ne $tokenL) { continue }
  if ("$($t.function)" -like "setFees(*") { $iFees = $i }
  if ("$($t.function)" -like "grantRole(*" -and "$($t.arguments[1])".ToLower() -eq $tlL) { $iGrant = $i }
  if ("$($t.function)" -like "revokeRole(*" -and "$($t.arguments[1])".ToLower() -eq $depL) { $iRevoke = $i }
}
if ($iFees -lt 0 -or $iGrant -lt 0 -or $iRevoke -lt 0) { throw "could not locate setFees/grantRole/revokeRole in the broadcast journal ($iFees/$iGrant/$iRevoke)" }
function RcptPos { param($hash)
  $j = (cast receipt $hash --json --rpc-url $script:RPC | Out-String) | ConvertFrom-Json
  $b = [System.Numerics.BigInteger]::Parse("0" + "$($j.blockNumber)".Substring(2), "AllowHexSpecifier")
  $x = [System.Numerics.BigInteger]::Parse("0" + "$($j.transactionIndex)".Substring(2), "AllowHexSpecifier")
  return @{ block = $b; index = $x; status = "$($j.status)" }
}
$pF = RcptPos $txs[$iFees].hash; $pG = RcptPos $txs[$iGrant].hash; $pR = RcptPos $txs[$iRevoke].hash
$chainOrder = (($pF.block -lt $pG.block) -or ($pF.block -eq $pG.block -and $pF.index -lt $pG.index)) -and (($pG.block -lt $pR.block) -or ($pG.block -eq $pR.block -and $pG.index -lt $pR.index))
Log-Step "H1.5b" "The ORDER of setFees, grantRole(GOVERNANCE_ROLE, timelock), revokeRole(GOVERNANCE_ROLE, deployer) on the token" "setFees BEFORE the grant BEFORE the revoke -- in the broadcast journal and on chain (block, index); all three status 0x1" "journal indices fees=$iFees grant=$iGrant revoke=$iRevoke; chain fees=(block $($pF.block), idx $($pF.index), $($pF.status)) grant=(block $($pG.block), idx $($pG.index), $($pG.status)) revoke=(block $($pR.block), idx $($pR.index), $($pR.status)); setFees args=$($txs[$iFees].arguments -join ',')" "$($txs[$iFees].hash) / $($txs[$iGrant].hash) / $($txs[$iRevoke].hash)" $(if ($iFees -lt $iGrant -and $iGrant -lt $iRevoke -and $chainOrder -and $pF.status -eq "0x1" -and $pG.status -eq "0x1" -and $pR.status -eq "0x1") { "PASS" } else { "DEVIATION" })

# ---- The rest of the phase-2 configuration, live --------------------------
$share = CQ $dep.token "stakingRewardShareBps()(uint256)"
$eT = CQ $dep.token "guardianExpiry()(uint256)"; $eL = CQ $dep.timelock "guardianAuthorityExpiry()(uint256)"; $eG = CQ $dep.governor "guardianAuthorityExpiry()(uint256)"
$supply = CQ $dep.token "totalSupply()(uint256)"; $inMig = CQ $dep.token "balanceOf(address)(uint256)" @($dep.migration)
$mk = CQRaw $dep.token "marketingWallet()(address)"
$migTre = CQRaw $dep.migration "treasury()(address)"
Log-Step "H1.6" "The rest of the phase-2 configuration, live" "share 1000; ONE expiry across the three contracts (exact); the whole supply in the migration; marketingWallet AND migration.treasury == the DEPLOYED timelock" "share=$share; expiry token=$eT timelock=$eL governor=$eG; supply=$(FmtB $supply) in migration=$(FmtB $inMig); marketingWallet=$mk, migration.treasury=$migTre, timelock=$($dep.timelock)" "-" $(if ($share -eq 1000 -and $eT -eq $eL -and $eT -eq $eG -and $supply -eq $inMig -and "$mk".ToLower() -eq $tlL -and "$migTre".ToLower() -eq $tlL) { "PASS" } else { "DEVIATION" })

$guardRole = CQRaw $dep.token "GUARDIAN_ROLE()(bytes32)"
$cancRole = CQRaw $dep.timelock "CANCELLER_ROLE()(bytes32)"
$gT = CQRaw $dep.token "hasRole(bytes32,address)(bool)" @($guardRole, $script:GUARDIAN)
$gL = CQRaw $dep.timelock "hasRole(bytes32,address)(bool)" @($cancRole, $script:GUARDIAN)
$gG = CQRaw $dep.governor "guardian()(address)"
Log-Step "H1.6b" "H1.3 of the plan: the guardian is the test Safe on all three contracts" "GUARDIAN_ROLE on the token, CANCELLER_ROLE on the Timelock, governor.guardian() == the Safe" "token hasRole=$gT, timelock canceller=$gL, governor.guardian=$gG (Safe=$($script:GUARDIAN))" "-" $(if ("$gT" -eq "true" -and "$gL" -eq "true" -and "$gG".ToLower() -eq "$($script:GUARDIAN)".ToLower()) { "PASS" } else { "DEVIATION" })

Log-Block "State file after phase 2 (the complete deployment record), verbatim:" (Get-Content $stateFile -Raw) "json"
$st | Add-Member -NotePropertyName timelock -NotePropertyValue $dep.timelock -Force
$st | Add-Member -NotePropertyName governor -NotePropertyValue $dep.governor -Force
$st | Add-Member -NotePropertyName staking -NotePropertyValue $dep.staking -Force
$st | Add-Member -NotePropertyName pair -NotePropertyValue (CQRaw $dep.token "uniswapV2Pair()(address)") -Force
$st | Add-Member -NotePropertyName guardianExpiry -NotePropertyValue "$eT" -Force
Save-State $st
Assert-Invariants "post-phase2"
Write-Output "H1c COMPLETE timelock=$($dep.timelock)"
