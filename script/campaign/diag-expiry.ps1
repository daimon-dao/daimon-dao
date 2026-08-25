# Diagnostic for the A1.8 deviation: why do the three expiries differ?
. .\script\campaign\lib.ps1
$st = Bootstrap-Campaign
$DAYS1095 = [System.Numerics.BigInteger]::Parse("94608000")

$eTok = CQ $st.token "guardianExpiry()(uint256)"
$eTl  = CQ $st.timelock "guardianAuthorityExpiry()(uint256)"
$eGov = CQ $st.governor "guardianAuthorityExpiry()(uint256)"
Write-Output "token   expiry = $eTok  -> implied deploy ts = $($eTok - $DAYS1095)"
Write-Output "timelock expiry= $eTl   -> implied source ts = $($eTl - $DAYS1095)"
Write-Output "governor expiry= $eGov  -> implied source ts = $($eGov - $DAYS1095)"
Write-Output "skew token-timelock = $($eTok - $eTl) s"

# Block timestamps of the actual on-chain creations, from the broadcast journal.
$bc = Get-Content (Join-Path $script:ROOT "broadcast\Deploy.s.sol\97\run-latest.json") -Raw | ConvertFrom-Json
Write-Output "--- on-chain creation blocks ---"
foreach ($tx in $bc.transactions) {
  if ($tx.transactionType -eq "CREATE") {
    $rcpt = cast receipt $tx.hash --rpc-url $script:RPC --json 2>$null | ConvertFrom-Json
    $bn = [System.Numerics.BigInteger]::Parse($rcpt.blockNumber.Substring(2), 'AllowHexSpecifier')
    $blk = cast block $bn --rpc-url $script:RPC --json 2>$null | ConvertFrom-Json
    $ts = [System.Numerics.BigInteger]::Parse("$($blk.timestamp)".Replace("0x",""), 'AllowHexSpecifier')
    Write-Output ("{0,-18} block={1} ts={2}" -f $tx.contractName, $bn, $ts)
  }
}
# The value baked into the Timelock's constructor calldata at SIMULATION time.
foreach ($tx in $bc.transactions) {
  if ($tx.contractName -eq "DaimonTimelock") {
    $data = $tx.transaction.input
    Write-Output "timelock ctor calldata tail: ...$($data.Substring($data.Length-64))"
    Write-Output "  = $([System.Numerics.BigInteger]::Parse($data.Substring($data.Length-64), 'AllowHexSpecifier'))"
  }
}
Write-Output "simulation timestamp recorded by forge: $($bc.timestamp)"
Stop-Anvil
