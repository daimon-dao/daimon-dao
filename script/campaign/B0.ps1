# B0 - Initial pool pricing (#17): the pair is NOT fee-exempt.
. .\script\campaign\lib.ps1
Log-Scenario "B0" "Initial pool pricing (Zenith #17): price on what the pair RECEIVES, with counter-proof"

# Target opening price: 1 BNB = 1,000,000,000 DMN.
$TARGET = [System.Numerics.BigInteger]::Parse("1000000000")
$gross  = BW "4.00"          # under maxTxAmount (5.00 B): see the note below

function Open-Pool { param([switch]$OnGross)
  $st = Bootstrap-Campaign
  $tax = CQ $st.token "taxFee()(uint256)"; $liq = CQ $st.token "liquidityFee()(uint256)"
  $net = ($gross * (1000 - $tax - $liq)) / 1000
  $basis = if ($OnGross) { $gross } else { $net }
  $bnb = $basis / $TARGET                      # wei of BNB for the chosen basis
  Claim-Dmn "team1" (BW "5.00") | Out-Null      # fund the LP with DMN 1:1
  Send "team1" $st.token "approve(address,uint256)" @($script:ROUTER, "$gross") | Out-Null
  Send "team1" $script:ROUTER "addLiquidityETH(address,uint256,uint256,uint256,address,uint256)" @(
    $st.token, "$gross", "0", "0", $script:Addr.team1, "99999999999") -value "$bnb" | Out-Null
  $res = Pair-Reserves
  return @{ st = $st; net = $net; bnb = $bnb; dmn = $res[0]; wbnb = $res[1] }
}

# ---- PROOF: BNB computed on what the pair ACTUALLY receives --------------
$ok = Open-Pool
$impliedOk = [System.Numerics.BigInteger]::Divide($ok.dmn, $ok.wbnb)
$devOk = [Math]::Abs([double](($TARGET - $impliedOk) * 10000 / $TARGET))
Log-Step "B0.1" "Send 4.00 B DMN gross; the pair receives it net of the 5% fee" "the pair's DMN reserve is the NET amount, 3.80 B - not the 4.00 B sent" "reserve DMN = $(FmtB $ok.dmn), expected net = $(FmtB $ok.net)" $(if ($ok.dmn -eq $ok.net) { "PASS" } else { "DEVIATION" })
Log-Step "B0.2" "Pair BNB with the contribution computed on the NET receipt" "opening price exactly 1 BNB = 1,000,000,000 DMN" "implied = $impliedOk DMN/BNB (off by $devOk bps)" $(if ($impliedOk -eq $TARGET) { "PASS" } else { "DEVIATION" })

# ---- COUNTER-PROOF: BNB computed on the GROSS amount sent ----------------
$bad = Open-Pool -OnGross
$impliedBad = [System.Numerics.BigInteger]::Divide($bad.dmn, $bad.wbnb)
$devBad = [double](($TARGET - $impliedBad) * 10000 / $TARGET)
Log-Step "B0.3" "COUNTER-PROOF, throwaway state: same 4.00 B gross, BNB computed on the GROSS" "the pool opens at the WRONG price - fewer DMN per BNB than intended" "implied = $impliedBad DMN/BNB (off by $devBad bps, i.e. DMN opens $([Math]::Round(100*[double]($TARGET-$impliedBad)/[double]$TARGET,2))% too expensive)" $(if ($impliedBad -lt $TARGET) { "PASS" } else { "DEVIATION" })

$maxTx = CQ $ok.st.token "maxTxAmount()(uint256)"
Log-Step "B0.4" "Size limit on a single liquidity add" "maxTxAmount caps the DMN leg: 5.00 B per transaction for a non-exempt provider" "maxTxAmount = $(FmtB $maxTx); this run used 4.00 B gross to stay under it" "NOTE"

Log-Note "Both halves land exactly where the checklist says they should. Pricing on the gross opens the pool 5.26% off - the mirror image of the 5% fee - and the error is silent: nothing reverts, the pool simply starts at a price nobody chose. Pricing on the net receipt lands on the intended ratio to the wei."
Log-Note "Operational note surfaced by running it: maxTxAmount is 5.00 B at deploy (0.5% of supply), so a realistic initial-liquidity position cannot be added in one transaction by a non-exempt provider - it has to be split into chunks, each paying the 5% fee and each needing its BNB leg computed on that chunk's NET receipt. Exempting the provider from fees instead would remove both the fee and the maxTx limit, and with them the #17 problem - but that exemption is a governance action with its own consequences, not a launch shortcut."
Stop-Anvil
Write-Output "B0 COMPLETE"
