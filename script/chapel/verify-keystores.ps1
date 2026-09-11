# One-time mapping check: every keystore NAME must resolve to the expected
# role address. Reads addresses only -- no key ever leaves the keystore.
. $PSScriptRoot\lib.ps1
Load-Keystores
$pf = $script:KsMap.passwordFile
$ok = 0; $bad = 0
foreach ($role in @("deployer","guardian","staker1","staker2","staker3","holder1","holder2","holder3","stranger")) {
  $ks = $script:KsMap.accounts.$role
  $prev = $ErrorActionPreference; $ErrorActionPreference = "Continue"
  $addr = (cast wallet address --account $ks --password-file $pf 2>&1 | Out-String).Trim()
  $ErrorActionPreference = $prev
  $expected = $script:AddrBook[$role]
  if ("$addr".ToLower() -eq "$expected".ToLower()) { Write-Output "$role OK"; $ok++ }
  else { Write-Output "$role MISMATCH: keystore='$addr' atteso='$expected'"; $bad++ }
}
Write-Output "risultato: $ok ok, $bad mismatch"
if ($bad -gt 0) { exit 1 }
