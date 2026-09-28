# D9 -- Day 9: execute proposal 0 (H3.3b) and run the first poke at share
# 600 (H3.4), the last untested "what if" of the campaign. The 7-day delay
# of queue(0) ended at readyTimestamp 1790609699 (2026-09-28 15:34:59 UTC);
# from that instant execute(0) is permissionless. The holder signs it, as it
# signed propose/vote/queue. Then the fee inventory is armed and a 1-wei
# direct transfer to the pair pokes the automation: with
# stakingRewardShareBps == 600 the marketing branch executes toward the
# marketing wallet -- the Timelock -- for the FIRST time on a public chain.
# The split is verified wei-exact from mined state: balances read at the
# block before the poke and at the poke block, against the ethReceived the
# token itself emits in SwapAndLiquify. If the call to the Timelock reverts
# or the automation blocks, the runner STOPS with the full error: that is
# the finding H3.5 exists to catch.
# The 2b invariant flips here (lib.ps1, Assert-Invariants): the poke is sent
# with -NoInvariant, the Timelock's BNB is verified exact, and only then is
# timelockBnbExpected recorded and the invariant re-asserted in its new form.
# Preflight from live state, no loop: proposal 0 not Queued, or the clock
# short of readyTimestamp, stops the runner before anything is signed.
. $PSScriptRoot\lib.ps1
Load-Keystores
$st = S
if ("$($st.proposalId)" -ne "0") { throw "state.json: the campaign proposal must be id 0 (found '$($st.proposalId)')" }
if (-not $st.queueTx -or -not $st.readyTimestamp -or -not $st.operationId) { throw "state.json carries no queue record: Day 6 (D6-queue.ps1) has not run" }
if ($st.executeTx) { throw "the execute is already recorded (tx $($st.executeTx))" }
if ($st.poke600Tx) { throw "the share-600 poke is already recorded (tx $($st.poke600Tx))" }
$propId = 0
$holder = $script:AddrBook.holder
$stranger = $script:AddrBook.stranger
$ARCHIVE = "https://data-seed-prebsc-1-s1.bnbchain.org:8545"
$epoch = [DateTime]::new(1970, 1, 1, 0, 0, 0, [DateTimeKind]::Utc)
function Utc { param($ts) return $epoch.AddSeconds([double]"$ts").ToString("yyyy-MM-dd HH:mm:ss") }
function HexToBig { param([string]$h) return [System.Numerics.BigInteger]::Parse("0" + ($h -replace "^0x", ""), "AllowHexSpecifier") }
function Word { param([string]$data, [int]$i) $d = $data -replace "^0x", ""; return (HexToBig $d.Substring($i * 64, 64)) }
function ReadOperation { param($opId)
  $prev = $ErrorActionPreference; $ErrorActionPreference = "Continue"
  $lines = @(cast call $st.timelock "operations(bytes32)(uint256,bool,bool)" $opId --rpc-url $script:RPC 2>&1)
  $c = $LASTEXITCODE; $ErrorActionPreference = $prev
  if ($c -ne 0 -or $lines.Count -lt 3) { throw "operations($opId) read failed: $(($lines -join ' ') -replace '\s+',' ')" }
  $tok = @(); foreach ($l in $lines) { $tok += ("$l".Trim() -split "\s+")[0] }
  return @{ readyTimestamp = [System.Numerics.BigInteger]::Parse($tok[0]); executed = $tok[1]; canceled = $tok[2] }
}
## One-shot receipt fetch: publicnode first, then the data-seed node.
function Get-ReceiptRaw { param($hash)
  foreach ($ep in @($script:RPC, $ARCHIVE)) {
    $prev = $ErrorActionPreference; $ErrorActionPreference = "Continue"
    $r = (cast rpc eth_getTransactionReceipt $hash --rpc-url $ep 2>&1 | Out-String)
    $c = $LASTEXITCODE; $ErrorActionPreference = $prev
    if ($c -ne 0) { continue }
    $j = $null; try { $j = $r | ConvertFrom-Json } catch { continue }
    if ($j -and $j.logs) { $src = ([uri]$ep).Host; return ,@($j, $src) }
  }
  throw "receipt for $hash not served by publicnode nor data-seed-prebsc-1-s1"
}
## Native balance and DMN balance AT a block (publicnode, then data-seed):
## the wei-exact split is read between two fixed blocks, never "latest".
function BalAt { param($addr, $blk)
  foreach ($ep in @($script:RPC, $ARCHIVE)) {
    $prev = $ErrorActionPreference; $ErrorActionPreference = "Continue"
    $r = (cast balance $addr --block "$blk" --rpc-url $ep 2>&1 | Out-String)
    $c = $LASTEXITCODE; $ErrorActionPreference = $prev
    if ($c -eq 0) { return [System.Numerics.BigInteger]::Parse(($r.Trim() -split "\s+")[0]) }
  }
  throw "balance of $addr at block $blk not served"
}
function DmnAt { param($addr, $blk)
  foreach ($ep in @($script:RPC, $ARCHIVE)) {
    $prev = $ErrorActionPreference; $ErrorActionPreference = "Continue"
    $r = (cast call $st.token "balanceOf(address)(uint256)" $addr --block "$blk" --rpc-url $ep 2>&1 | Out-String)
    $c = $LASTEXITCODE; $ErrorActionPreference = $prev
    if ($c -eq 0) { return [System.Numerics.BigInteger]::Parse(($r.Trim() -split "\s+")[0]) }
  }
  throw "DMN balance of $addr at block $blk not served"
}
function Guardian-Snapshot {
  $gRole = CQRaw $st.token "GUARDIAN_ROLE()(bytes32)"
  $cRole = CQRaw $st.timelock "CANCELLER_ROLE()(bytes32)"
  $govRole = CQRaw $st.token "GOVERNANCE_ROLE()(bytes32)"
  return @{
    tokenGuardian = CQRaw $st.token "hasRole(bytes32,address)(bool)" @($gRole, $script:GUARDIAN)
    tlCanceller = CQRaw $st.timelock "hasRole(bytes32,address)(bool)" @($cRole, $script:GUARDIAN)
    govGuardian = CQRaw $st.governor "guardian()(address)"
    expiry = CQ $st.governor "guardianAuthorityExpiry()(uint256)"
    tlGovernance = CQRaw $st.token "hasRole(bytes32,address)(bool)" @($govRole, $st.timelock)
  }
}
function Guardian-Ok { param($g)
  return ($g.tokenGuardian -eq "true" -and $g.tlCanceller -eq "true" -and "$($g.govGuardian)".ToLower() -eq $script:GUARDIAN.ToLower() -and "$($g.expiry)" -eq "$($st.guardianExpiry)" -and $g.tlGovernance -eq "true")
}
function Guardian-Text { param($g) return "token GUARDIAN_ROLE(Safe)=$($g.tokenGuardian), timelock CANCELLER_ROLE(Safe)=$($g.tlCanceller), governor.guardian()=$($g.govGuardian), guardianAuthorityExpiry=$($g.expiry) ($(Utc $g.expiry) UTC), token GOVERNANCE_ROLE(Timelock)=$($g.tlGovernance)" }

# ---- keystores: the two signers must decrypt to their mapped addresses -----------
$pf = Pf
foreach ($role in @("holder", "stranger")) {
  $ks = Ks $role
  $prevEap = $ErrorActionPreference; $ErrorActionPreference = "Continue"
  $waddr = (cast wallet address --account $ks --password-file $pf 2>&1 | Out-String).Trim()
  $ErrorActionPreference = $prevEap
  if ($waddr.ToLower() -ne "$($script:AddrBook[$role])".ToLower()) { throw "keystore '$ks' decrypts to '$waddr', not the mapped $role address -- nothing signed" }
}

# ---- preflight, read-only ------------------------------------------------------------
$blkNow = BlockNumber
$tsNow = [System.Numerics.BigInteger]::Parse(((cast block $blkNow --field timestamp --rpc-url $script:RPC | Out-String).Trim()))
$ready = [System.Numerics.BigInteger]::Parse("$($st.readyTimestamp)")
$pState0 = Prop-State $propId
if ($tsNow -lt $ready) { throw "STOP: block $blkNow ts $tsNow is $($ready - $tsNow) s short of readyTimestamp $ready ($(Utc $ready) UTC). Not looping." }
if ($pState0 -ne "Queued") { throw "STOP: proposal 0 is '$pState0', not Queued -- nothing to execute" }
$pState1 = Prop-State 1; $pState2 = Prop-State 2; $pState3 = Prop-State 3
$op0 = ReadOperation $st.operationId
$opIdLive = CQRaw $st.timelock "hashOperation(address,uint256,bytes,bytes32,bytes32)(bytes32)" @($st.token, "0", (cast calldata "setStakingRewardShareBps(uint256)" 600), "0x0000000000000000000000000000000000000000000000000000000000000000", $st.timelockSalt)
$fExecuted0 = Prop-Field $propId 13; $fQueued0 = Prop-Field $propId 14; $fCanceled0 = Prop-Field $propId 12
$share0 = CQ $st.token "stakingRewardShareBps()(uint256)"
$mw = CQRaw $st.token "marketingWallet()(address)"
$stkAddr = CQRaw $st.token "stakingContract()(address)"
$g0 = Guardian-Snapshot
$tlBnb0 = Bal $st.timelock
$tlDmn0 = CQ $st.token "balanceOf(address)(uint256)" @($st.timelock)
$lpTl0 = CQ $st.pair "balanceOf(address)(uint256)" @($st.timelock)
$lpTot0 = CQ $st.pair "totalSupply()(uint256)"
$okPre = ($script:CHAIN -eq "97" -and $pState0 -eq "Queued" -and $tsNow -ge $ready -and "$($op0.readyTimestamp)" -eq "$ready" -and $op0.executed -eq "false" -and $op0.canceled -eq "false" -and $opIdLive.ToLower() -eq "$($st.operationId)".ToLower() -and $fQueued0 -eq "true" -and $fExecuted0 -eq "false" -and $fCanceled0 -eq "false" -and $pState1 -eq "Defeated" -and $pState2 -eq "Canceled" -and $pState3 -eq "Canceled" -and $share0 -eq 1000 -and $mw.ToLower() -eq "$($st.timelock)".ToLower() -and $stkAddr.ToLower() -eq "$($st.staking)".ToLower() -and (Guardian-Ok $g0) -and $tlBnb0 -eq 0 -and $tlDmn0 -eq 0 -and ($lpTot0 - $lpTl0) -eq 1000)

$day = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd")
Log-Line ""
Log-Line "## Day 9 -- Execute and the first poke at 600 ($day)"
Log-Line ""
Log-Line "The last sitting of the governance cycle on the real clock, and the last"
Log-Line "untested what-if of the campaign. The 7-day delay of queue(0) ended at"
Log-Line "readyTimestamp; execute(0), signed by the holder, applies"
Log-Line "setStakingRewardShareBps(600) through the Timelock (H3.3b). Then the fee"
Log-Line "inventory is armed and a 1-wei direct transfer to the pair pokes the"
Log-Line "automation (H3.4): with share 600 the marketing branch pays the"
Log-Line "marketing wallet -- the Timelock -- for the first time on a public chain,"
Log-Line "through its receive(). The split is verified wei-exact between the block"
Log-Line "before the poke and the poke block, against the ethReceived the token"
Log-Line "emits. The 2b invariant flips in this sitting: the Timelock's BNB is"
Log-Line "verified, then recorded as the expected balance (lib.ps1)."
Log-Line ""
Log-Scenario "H3.3b" "The execute: proposal 0 applies setStakingRewardShareBps(600) through the Timelock; a second execute is refused"
Log-Step "H3.3b.1" "Preflight from live state, before execute" "chain 97; now >= readyTimestamp $ready; proposal 0 Queued (queued=true, executed=canceled=false); operation slot readyTimestamp == state file, not executed, not canceled; opId recomputed on-chain == Day 6's; proposal 1 Defeated, 2 and 3 Canceled; share 1000; marketingWallet == Timelock; stakingContract == staking; guardian roles as deployed; Timelock BNB 0, DMN 0; Timelock holds all LP but the 1000 burned" "chain=$($script:CHAIN), block=$blkNow ts=$tsNow ($(Utc $tsNow) UTC), ready since $($tsNow - $ready) s; state0=$pState0 queued=$fQueued0 executed=$fExecuted0 canceled=$fCanceled0; op readyTimestamp=$($op0.readyTimestamp) executed=$($op0.executed) canceled=$($op0.canceled), opIdMatch=$($opIdLive.ToLower() -eq "$($st.operationId)".ToLower()); state1=$pState1 state2=$pState2 state3=$pState3; share=$share0; marketingWallet=$mw; stakingContract=$stkAddr; $(Guardian-Text $g0); Timelock BNB=$tlBnb0 DMN=$tlDmn0; LP Timelock=$lpTl0 of totalSupply $lpTot0" "-" $(if ($okPre) { "PASS" } else { "DEVIATION" })
if (-not $okPre) { throw "STOP: preflight deviation, nothing signed" }

# ---- H3.3b: execute(0) -------------------------------------------------------------------
$hE = Send "holder" $st.governor "execute(uint256)" @("$propId")
$rr = Get-ReceiptRaw $hE.hash
$rcpt = $rr[0]; $rcptSrc = $rr[1]
$eBlock = HexToBig "$($rcpt.blockNumber)"
$eTs = [System.Numerics.BigInteger]::Parse(((cast block "$eBlock" --field timestamp --rpc-url $script:RPC | Out-String).Trim()))
$op1 = ReadOperation $st.operationId
$fExecuted1 = Prop-Field $propId 13
$pStateE = Prop-State $propId
$pStateEn = CQ $st.governor "state(uint256)(uint8)" @("$propId")
$share1 = CQ $st.token "stakingRewardShareBps()(uint256)"
$okE = ("$($rcpt.status)" -eq "0x1" -and "$($rcpt.from)".ToLower() -eq "$holder".ToLower() -and "$($rcpt.to)".ToLower() -eq "$($st.governor)".ToLower() -and $fExecuted1 -eq "true" -and $pStateE -eq "Executed" -and $pStateEn -eq 5 -and $op1.executed -eq "true" -and $op1.canceled -eq "false" -and $share1 -eq 600 -and $eTs -ge $ready)
Log-Step "H3.3b.2" "The holder calls execute($propId)" "receipt status 1, from == holder, to == governor, mined at ts >= readyTimestamp; proposals(0).executed true; state() == Executed (5); operations(opId).executed true; token.stakingRewardShareBps() == 600" "status=$($rcpt.status), from=$($rcpt.from), to=$($rcpt.to), block=$eBlock (ts=$eTs = $(Utc $eTs) UTC, $($eTs - $ready) s after ready), gas=$($hE.gasUsed); executed=$fExecuted1, state=$pStateE ($pStateEn); op executed=$($op1.executed) canceled=$($op1.canceled); share=$share1; receipt served by $rcptSrc" $hE.hash $(if ($okE) { "PASS" } else { "DEVIATION" })

$topicPU = (cast keccak "ParamsUpdated(string,uint256)").ToLower()
$topicCE = (cast keccak "CallExecuted(bytes32,address,uint256,bytes)").ToLower()
$topicPE = (cast keccak "ProposalExecuted(uint256)").ToLower()
$evPU = $null; $evCE = $null; $evPE = $null; $nLogs = 0
foreach ($lg in [array]$rcpt.logs) {
  $nLogs++
  $t0 = "$($lg.topics[0])".ToLower(); $a = "$($lg.address)".ToLower()
  if ($t0 -eq $topicPU -and $a -eq "$($st.token)".ToLower()) { $evPU = $lg }
  if ($t0 -eq $topicCE -and $a -eq "$($st.timelock)".ToLower()) { $evCE = $lg }
  if ($t0 -eq $topicPE -and $a -eq "$($st.governor)".ToLower()) { $evPE = $lg }
}
$puName = "?"; $puValue = "?"; $ceId = "?"; $ceTarget = "?"; $peId = "?"
if ($evPU) {
  $dec = @(cast abi-decode "f()(string,uint256)" "$($evPU.data)")
  $puName = ("$($dec[0])".Trim()).Trim('"')
  $puValue = (("$($dec[1])".Trim()) -split "\s+")[0]
}
if ($evCE) { $ceId = "$($evCE.topics[1])".ToLower(); $ceTarget = "0x" + ("$($evCE.data)" -replace "^0x", "").Substring(24, 40) }
if ($evPE) { $peId = HexToBig "$($evPE.topics[1])" }
$okEv = ($nLogs -eq 3 -and $evPU -and $evCE -and $evPE -and $puName -eq "stakingRewardShareBps" -and "$puValue" -eq "600" -and $ceId -eq "$($st.operationId)".ToLower() -and $ceTarget.ToLower() -eq "$($st.token)".ToLower() -and "$peId" -eq "$propId")
Log-Step "H3.3b.3" "The events decoded from the execute receipt" "exactly 3 logs: ParamsUpdated(`"stakingRewardShareBps`", 600) from the token; CallExecuted(id == opId, target == token) from the timelock; ProposalExecuted(0) from the governor" "logs=$nLogs; ParamsUpdated param=`"$puName`" value=$puValue; CallExecuted id=$ceId target=$ceTarget; ProposalExecuted id=$peId" $hE.hash $(if ($okEv) { "PASS" } else { "DEVIATION" })

$rv = Expect-Revert "stranger" $st.governor "execute(uint256)" @("$propId") "AlreadyExecuted()"
$selAE = (cast sig "AlreadyExecuted()")
$prevEap = $ErrorActionPreference; $ErrorActionPreference = "Continue"
$raw = (cast call $st.governor "execute(uint256)" "$propId" --from $stranger --rpc-url $script:RPC 2>&1 | Out-String)
$ErrorActionPreference = $prevEap
$rawFlat = ($raw -replace '\s+', ' ').Trim()
Log-Step "H3.3b.4" "The stranger tries execute($propId) a second time" "refused by the Governor itself: AlreadyExecuted() (selector $selAE), the first check in execute(), before state() or the Timelock; no transaction mined" "$rv; eth_call: $($rawFlat.Substring(0, [Math]::Min(220, $rawFlat.Length)))" "-" $(if ($rv -match "AlreadyExecuted" -and $rawFlat.ToLower().Contains($selAE.ToLower())) { "PASS" } else { "DEVIATION" })

$g1 = Guardian-Snapshot
Log-Step "H3.3b.5" "After execute: nothing but the share moved" "guardian roles unchanged; Timelock BNB 0 and DMN 0 (share 600 is live but no conversion has run yet); LP unchanged" "$(Guardian-Text $g1); Timelock BNB=$(Bal $st.timelock) DMN=$(CQ $st.token 'balanceOf(address)(uint256)' @($st.timelock)); LP Timelock=$(CQ $st.pair 'balanceOf(address)(uint256)' @($st.timelock)) totalSupply=$(CQ $st.pair 'totalSupply()(uint256)')" "-" $(if ((Guardian-Ok $g1) -and (Bal $st.timelock) -eq 0 -and (CQ $st.token 'balanceOf(address)(uint256)' @($st.timelock)) -eq 0 -and (CQ $st.pair 'totalSupply()(uint256)') -eq $lpTot0 -and (CQ $st.pair 'balanceOf(address)(uint256)' @($st.timelock)) -eq $lpTl0) { "PASS" } else { "DEVIATION" })
Set-StateField "executeTx" $hE.hash
Set-StateField "executeBlock" "$eBlock"
Set-StateField "executeTimestamp" "$eTs"

# ---- H3.4: the inventory -----------------------------------------------------------------
Log-Scenario "H3.4" "The first poke at share 600: the marketing branch pays the Timelock for the first time -- 60/40 of the marketing share, wei-exact"
$tax = CQ $st.token "taxFee()(uint256)"; $liq = CQ $st.token "liquidityFee()(uint256)"; $mkt = CQ $st.token "marketingFee()(uint256)"
$minSwap = CQ $st.token "minimumTokensBeforeSwap()(uint256)"
$inv0 = Fee-Inventory
Log-Step "H3.4.1" "The fee inventory vs the threshold, read before arming" "recorded: the token's own DMN balance against minimumTokensBeforeSwap; fees 10/10/20 (tax 1%, liquidity 3% of which marketing 2%)" "inventory=$inv0 wei ($(FmtB $inv0)) vs threshold $minSwap ($(FmtB $minSwap)), short by $(FmtB ($minSwap - $inv0)); taxFee=$tax liquidityFee=$liq marketingFee=$mkt" "-" $(if ($tax -eq 10 -and $liq -eq 30 -and $mkt -eq 20) { "PASS" } else { "DEVIATION" })

# The test sell from the stranger, through the real router (router-initiated:
# the automation is skipped, the inventory only grows).
$sellAmt = BW "0.02"
$wbnb = CQRaw $script:ROUTER "WETH()(address)"
$resB = Pair-Reserves
$hA = Send "stranger" $st.token "approve(address,uint256)" @($script:ROUTER, "$sellAmt")
$hS = Send "stranger" $script:ROUTER "swapExactTokensForETHSupportingFeeOnTransferTokens(uint256,uint256,address[],address,uint256)" @("$sellAmt", "0", "[$($st.token),$wbnb]", $stranger, "99999999999")
$resA = Pair-Reserves
$inv1 = Fee-Inventory
$pairGot = $resA[0] - $resB[0]
$exp96s = [System.Numerics.BigInteger]::Divide($sellAmt * 96, 100)
$expInvS = [System.Numerics.BigInteger]::Divide($sellAmt * $liq, 1000)
$tlB = Bal $st.timelock
Log-Step "H3.4.2" "Test sell: the stranger sells 0.02 B through the real router" "the pair receives EXACTLY 96%; inventory += 3% plus the contract's reflection share (< 0.01% of it); router-initiated, so NO conversion: the Timelock still at 0 BNB" "pair DMN +$pairGot wei (96% = $exp96s); inventory +$($inv1 - $inv0) wei (3% = $expInvS, extra $($inv1 - $inv0 - $expInvS)); BNB out of the pool=$(FmtT ($resB[1] - $resA[1])); Timelock BNB=$tlB; sell gas=$($hS.gasUsed)" "$($hA.hash) / $($hS.hash)" $(if ($pairGot -eq $exp96s -and ($inv1 - $inv0) -ge $expInvS -and (($inv1 - $inv0 - $expInvS) * 10000) -le $expInvS -and $tlB -eq 0) { "PASS" } else { "DEVIATION" })

# Arming: ordinary taxed transfers holder -> stranger (no pair involved, so no
# automation), each <= 3.00 B, sized from the live shortfall + 0.5% margin and
# rounded up to 0.01 B. At most 4 sends; re-read after each.
$armTx = @(); $armTotal = [System.Numerics.BigInteger]::Zero
$cent = BW "0.01"; $cap = BW "3.00"
foreach ($i in 1..4) {
  $invI = Fee-Inventory
  if ($invI -ge $minSwap) { break }
  $vol = CeilDiv (($minSwap - $invI) * 1000 * 1005) ($liq * 1000)
  $vol = (CeilDiv $vol $cent) * $cent
  if ($vol -gt $cap) { $vol = $cap }
  $hT = Send "holder" $st.token "transfer(address,uint256)" @($stranger, "$vol")
  $armTx += $hT.hash; $armTotal += $vol
}
$inv2 = Fee-Inventory
Log-Step "H3.4.3" "Inventory armed by ordinary taxed transfers holder -> stranger ($(FmtB $armTotal) in $($armTx.Count) sends, each <= 3.00 B)" "inventory >= minimumTokensBeforeSwap; harness necessity, recorded as such (as Day 1, H1.21): the stranger's 0.43 B and a 0.78 B-DMN pool cannot carry the ~5.7 B of taxed volume that 0.17 B of inventory needs as sells without moving the price by multiples -- on mainnet the volume is organic" "inventory=$inv2 wei ($(FmtB $inv2)) vs threshold $minSwap; +$(FmtB ($inv2 - $inv1)) from $(FmtB $armTotal) of volume" ($armTx -join " / ") $(if ($inv2 -ge $minSwap) { "NOTE" } else { "DEVIATION" })
if ($inv2 -lt $minSwap) { throw "STOP: inventory $inv2 still below threshold $minSwap after arming" }

# ---- H3.4: the poke ------------------------------------------------------------------------
$resP = Pair-Reserves
$priceP = Price-WeiPerToken $resP[0] $resP[1]
$hP = $null
try {
  $hP = Send "stranger" $st.token "transfer(address,uint256)" @($st.pair, "1") -NoInvariant
} catch {
  $err = "$($_.Exception.Message)"
  Log-Step "H3.4.4" "The stranger pokes (1 wei of DMN straight to the pair) at share 600" "the call succeeds; exactly ONE threshold-sized chunk converts; the call to the Timelock succeeds" "FAILED: $(($err -replace '\|', '/').Substring(0, [Math]::Min(600, $err.Length)))" "-" "DEVIATION"
  Log-Note "H3.5 TRIGGERED: the share-600 poke did not go through. Full error: $($err -replace '\|', '/'). The runner stopped here; nothing else was signed."
  throw "STOP (H3.5): the share-600 poke failed: $err"
}
$pBlock = [System.Numerics.BigInteger]$hP.block
$pPrev = $pBlock - 1
$rrP = Get-ReceiptRaw $hP.hash
$rcptP = $rrP[0]; $rcptPSrc = $rrP[1]

# Balances between the block before the poke and the poke block.
$tlBefore = BalAt $st.timelock $pPrev;  $tlAfter = BalAt $st.timelock $pBlock
$stkBefore = BalAt $st.staking $pPrev;  $stkAfter = BalAt $st.staking $pBlock
$tkBefore = BalAt $st.token $pPrev;     $tkAfter = BalAt $st.token $pBlock
$invBefore = DmnAt $st.token $pPrev;    $invAfter = DmnAt $st.token $pBlock
$tlDmnAfter = DmnAt $st.timelock $pBlock

# Events of the poke receipt.
$topicSL = (cast keccak "SwapAndLiquify(uint256,uint256)").ToLower()
$topicRN = (cast keccak "RewardNotified(uint256)").ToLower()
$topicRR = (cast keccak "RewardReserved(uint256)").ToLower()
$evSL = $null; $evRN = $null; $evRR = $null; $nLogsP = 0
foreach ($lg in [array]$rcptP.logs) {
  $nLogsP++
  $t0 = "$($lg.topics[0])".ToLower(); $a = "$($lg.address)".ToLower()
  if ($t0 -eq $topicSL -and $a -eq "$($st.token)".ToLower()) { $evSL = $lg }
  if ($t0 -eq $topicRN -and $a -eq "$($st.staking)".ToLower()) { $evRN = $lg }
  if ($t0 -eq $topicRR -and $a -eq "$($st.staking)".ToLower()) { $evRR = $lg }
}
$slTokens = [System.Numerics.BigInteger]::Zero; $slEth = [System.Numerics.BigInteger]::Zero; $rnAmt = "?"
if ($evSL) { $slTokens = Word "$($evSL.data)" 0; $slEth = Word "$($evSL.data)" 1 }
if ($evRN) { $rnAmt = Word "$($evRN.data)" 0 }
$consumed = $invBefore - $invAfter
$okPoke = ("$($rcptP.status)" -eq "0x1" -and $evSL -and $slTokens -eq $minSwap -and $consumed -eq $minSwap -and $slEth -gt 0)
Log-Step "H3.4.4" "The stranger pokes (1 wei of DMN straight to the pair) at share 600" "receipt status 1; exactly ONE threshold-sized chunk converts (#28 budget): SwapAndLiquify(tokensSwapped == minimumTokensBeforeSwap, ethReceived > 0) emitted -- it is emitted AFTER require(ok1), so its presence proves the call to the Timelock returned true; the token's DMN falls by exactly the chunk between block N-1 and N" "status=$($rcptP.status), block=$pBlock, gas=$($hP.gasUsed), logs=$nLogsP (receipt from $rcptPSrc); SwapAndLiquify tokensSwapped=$slTokens ethReceived=$slEth wei ($(FmtT $slEth) BNB); inventory $invBefore -> $invAfter, consumed=$consumed" $hP.hash $(if ($okPoke) { "PASS" } else { "DEVIATION" })
if (-not $okPoke) {
  Log-Note "H3.5 TRIGGERED: the poke mined but the automation did not convert as designed (see H3.4.4). The runner stopped here; the invariant was NOT flipped."
  throw "STOP (H3.5): the poke mined without the expected conversion"
}

# The split, exactly as the token computes it (_swapAccumulatedFees).
$marketingEth = [System.Numerics.BigInteger]::Divide($slEth * $mkt, $liq)
$expStk = [System.Numerics.BigInteger]::Divide($marketingEth * 600, 1000)
$expTl = $marketingEth - $expStk
$expTk = $slEth - $marketingEth
$dTl = $tlAfter - $tlBefore; $dStk = $stkAfter - $stkBefore; $dTk = $tkAfter - $tkBefore
$okSplit = ($dTl -eq $expTl -and $dStk -eq $expStk -and $dTk -eq $expTk -and $expTl -gt 0 -and $evRN -and "$rnAmt" -eq "$expStk" -and -not $evRR -and ($dTl + $dStk + $dTk) -eq $slEth)
Log-Step "H3.4.5" "Where the BNB went, with stakingRewardShareBps == 600 -- wei-exact, block N-1 -> N" "marketingEth = floor(ethReceived x 20 / 30); staking += floor(marketingEth x 600 / 1000) and RewardNotified(that amount) (not RewardReserved: stakers exist); TIMELOCK += marketingEth - toStaking via call{value} to its receive(); the token retains ethReceived - marketingEth (buyback); the three deltas sum to ethReceived" "ethReceived=$slEth; marketingEth=$marketingEth; staking +$dStk (expected $expStk, RewardNotified=$rnAmt); TIMELOCK +$dTl (expected $expTl); token +$dTk (expected $expTk); sum=$($dTl + $dStk + $dTk)" $hP.hash $(if ($okSplit) { "PASS" } else { "DEVIATION" })
Log-Step "H3.4.6" "The Timelock's BNB balance, before and after the first payment it ever received from the token" "0 before (the invariant held through $($st.invariantChecks) checks); after == the marketing-wallet share of this one conversion; zero DMN before and after" "BNB at block $pPrev = $tlBefore wei; at block $pBlock = $tlAfter wei ($(FmtT $tlAfter) BNB); DMN after = $tlDmnAfter" $hP.hash $(if ($tlBefore -eq 0 -and $tlAfter -eq $expTl -and $tlDmnAfter -eq 0) { "PASS" } else { "DEVIATION" })

$resQ = Pair-Reserves
$priceQ = Price-WeiPerToken $resQ[0] $resQ[1]
$chunkBps = [System.Numerics.BigInteger]::Divide($consumed * 10000, $resP[0])
$moveBps = MoveBps $priceP $priceQ
Log-Step "H3.4.7" "The chunk against the pool it was sold into (as H1.24, recorded not judged)" "recorded" "chunk $(FmtB $consumed) against DMN reserve $(FmtB $resP[0]) = $chunkBps bps; BNB drawn $(FmtT ($resP[1] - $resQ[1])) of $(FmtT $resP[1]); price $priceP -> $priceQ wei/token, move -$moveBps bps" $hP.hash "PASS"

# ---- after: guardian, DMN, LP -----------------------------------------------------------------
$g2 = Guardian-Snapshot
$lpTl2 = CQ $st.pair "balanceOf(address)(uint256)" @($st.timelock)
$lpTot2 = CQ $st.pair "totalSupply()(uint256)"
$tlDmn2 = CQ $st.token "balanceOf(address)(uint256)" @($st.timelock)
$share2 = CQ $st.token "stakingRewardShareBps()(uint256)"
Log-Step "H3.4.8" "Closing reads: guardian, Timelock DMN, LP" "guardian roles unchanged from preflight; Timelock DMN still 0; LP totalSupply and the Timelock's LP balance unchanged (the fee swap sells, it adds no liquidity); share still 600" "$(Guardian-Text $g2); Timelock DMN=$tlDmn2; LP Timelock=$lpTl2 (was $lpTl0), totalSupply=$lpTot2 (was $lpTot0); share=$share2" "-" $(if ((Guardian-Ok $g2) -and $tlDmn2 -eq 0 -and $lpTl2 -eq $lpTl0 -and $lpTot2 -eq $lpTot0 -and $share2 -eq 600) { "PASS" } else { "DEVIATION" })

# ---- the invariant flips, only now that the amount is verified ---------------------------------
$tlNow = Bal $st.timelock
if ($okSplit -and $tlNow -eq $tlAfter) {
  Set-StateField "timelockBnbExpected" "$tlAfter"
  Assert-Invariants "D9 flip: Timelock BNB == verified conversions"
  Log-Step "H3.4.9" "The 2b invariant flips (lib.ps1): the Timelock's native must now EQUAL the sum of verified conversions; its DMN must stay 0" "state file timelockBnbExpected = $tlAfter; Assert-Invariants passes in its new form" "timelockBnbExpected=$tlAfter, Timelock BNB now=$tlNow, invariant checks=$((S).invariantChecks)" "-" "PASS"
} else {
  Log-Step "H3.4.9" "The 2b invariant flip" "only after a wei-exact split" "NOT flipped: split ok=$okSplit, Timelock BNB now=$tlNow vs at poke block $tlAfter" "-" "DEVIATION"
}

$stFix = S
$stFix | Add-Member -NotePropertyName poke600Tx -NotePropertyValue $hP.hash -Force
$stFix | Add-Member -NotePropertyName poke600Block -NotePropertyValue "$pBlock" -Force
$stFix | Add-Member -NotePropertyName poke600EthReceived -NotePropertyValue "$slEth" -Force
$stFix | Add-Member -NotePropertyName poke600ToStaking -NotePropertyValue "$dStk" -Force
$stFix | Add-Member -NotePropertyName poke600ToTimelock -NotePropertyValue "$dTl" -Force
$stFix | Add-Member -NotePropertyName testSell600Tx -NotePropertyValue $hS.hash -Force
$stFix | Add-Member -NotePropertyName armTx600 -NotePropertyValue ($armTx -join ",") -Force
Save-State $stFix

Write-Output "D9 COMPLETE execute=$($hE.hash) block=$eBlock ts=$eTs"
Write-Output "second execute: $rv"
Write-Output "sell=$($hS.hash) arm=$($armTx -join ',')"
Write-Output "poke=$($hP.hash) block=$pBlock ethReceived=$slEth marketingEth=$marketingEth staking+$dStk timelock+$dTl token+$dTk"
Write-Output "timelock BNB $tlBefore -> $tlAfter ; split ok=$okSplit"
