# P2.4 -- The per-block budget with pokes from different senders, real blocks.
. $PSScriptRoot\lib.ps1
Load-Keystores
$st = S
Log-Scenario "P2.4" "Per-block budget: two pokes from two senders aimed at one real block"
$minSwap = CQ $st.token "minimumTokensBeforeSwap()(uint256)"
$h1 = Send "holder1" $st.token "transfer(address,uint256)" @($script:AddrBook.holder2, "5000000000000000000000000000")
$h2 = Send "holder1" $st.token "transfer(address,uint256)" @($script:AddrBook.holder3, "5000000000000000000000000000")
$inv0 = CQ $st.token "balanceOf(address)(uint256)" @($st.token)
Log-Step "P2.4.1" "Refill: 10B taxed volume" "inventory >= 2 chunks ($(FmtB ($minSwap * 2)))" "inventory=$(FmtB $inv0)" "$($h1.hash) / $($h2.hash)" $(if ($inv0 -ge ($minSwap * 2)) { "PASS" } else { "DEVIATION" })

# Two async pokes, back to back, different senders. On a public chain the
# block placement is the miner's choice: we RECORD what actually happened.
$attempt = 0; $sameBlock = $false; $b1 = ""; $b2 = ""; $hp1 = ""; $hp2 = ""
while ($attempt -lt 3 -and -not $sameBlock) {
  $attempt++
  $invPre = CQ $st.token "balanceOf(address)(uint256)" @($st.token)
  $hp1 = SendAsync "stranger" $st.token "transfer(address,uint256)" @($st.pair, "1")
  $hp2 = SendAsync "staker3"  $st.token "transfer(address,uint256)" @($st.pair, "1")
  Start-Sleep -Seconds 8
  $r1 = (cast receipt $hp1 --rpc-url $script:RPC --json 2>$null | Out-String | ConvertFrom-Json)
  $r2 = (cast receipt $hp2 --rpc-url $script:RPC --json 2>$null | Out-String | ConvertFrom-Json)
  if ($null -eq $r1 -or $null -eq $r2) { Start-Sleep -Seconds 6; $r1 = (cast receipt $hp1 --rpc-url $script:RPC --json | Out-String | ConvertFrom-Json); $r2 = (cast receipt $hp2 --rpc-url $script:RPC --json | Out-String | ConvertFrom-Json) }
  $b1 = [System.Numerics.BigInteger]::Parse("0" + $r1.blockNumber.Substring(2), "AllowHexSpecifier")
  $b2 = [System.Numerics.BigInteger]::Parse("0" + $r2.blockNumber.Substring(2), "AllowHexSpecifier")
  $sameBlock = ($b1 -eq $b2)
  $invPost = CQ $st.token "balanceOf(address)(uint256)" @($st.token)
  $consumed = $invPre - $invPost
  $chunks = [System.Numerics.BigInteger]::Divide($consumed + ($minSwap / 2), $minSwap)
  Log-Step "P2.4.$($attempt + 1)" "Attempt ${attempt}: stranger + staker3 poke back to back" "same block -> ONE chunk total (budget is per block, not per sender); adjacent blocks -> the budget rolls and up to two chunks convert" "blocks $b1 / $b2 (same=$sameBlock), consumed ~$chunks chunk(s) ($(FmtB $consumed))" "$hp1 / $hp2" $(if (($sameBlock -and $chunks -le 1) -or ((-not $sameBlock) -and $chunks -le 2)) { "PASS" } else { "DEVIATION" })
  if (-not $sameBlock -and $attempt -lt 3) {
    $inv = CQ $st.token "balanceOf(address)(uint256)" @($st.token)
    if ($inv -lt ($minSwap * 2)) {
      Send "holder1" $st.token "transfer(address,uint256)" @($script:AddrBook.holder2, "5000000000000000000000000000") | Out-Null
      Send "holder1" $st.token "transfer(address,uint256)" @($script:AddrBook.holder3, "5000000000000000000000000000") | Out-Null
    }
  }
}
Log-Note "On a public chain block placement belongs to the validators: the harness aims for colocation and records what actually landed. The Level-1 result (budget is per block and sender-independent, proven with forced same-block mining) is the mechanism; here the record shows real-network behaviour."
Write-Output "P2d COMPLETE sameBlock=$sameBlock attempts=$attempt"
