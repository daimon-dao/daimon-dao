# One-time mapping check: every keystore NAME must decrypt to the role
# address the map declares. Reads addresses only -- no key ever leaves the
# keystore. Also prints the account-safety facts (code, balance, nonce).
. $PSScriptRoot\lib.ps1
Load-Keystores
$pf = Pf
$ok = 0; $bad = 0
foreach ($role in @("deployer", "oldowner", "holder", "stranger")) {
  $ks = Ks $role
  $prev = $ErrorActionPreference; $ErrorActionPreference = "Continue"
  $addr = (cast wallet address --account $ks --password-file $pf 2>&1 | Out-String).Trim()
  $ErrorActionPreference = $prev
  $expected = $script:AddrBook[$role]
  $codeLen = Code-Len $expected
  $line = "{0,-9} keystore->{1}  map={2}  code={3}  balance={4} tBNB  nonce={5}" -f $role, $addr, $expected, $(if ($codeLen -le 2) { "none" } else { "PRESENT" }), (FmtT (Bal $expected)), (Nonce $expected)
  if ("$addr".ToLower() -eq "$expected".ToLower()) { Write-Output "OK  $line"; $ok++ } else { Write-Output "BAD $line"; $bad++ }
}
Write-Output "result: $ok ok, $bad mismatch (chain $($script:CHAIN))"
if ($bad -gt 0) { exit 1 }
