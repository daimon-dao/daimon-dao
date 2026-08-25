# V1 - The post-broadcast verification: the real gate, on a real deploy.
. .\script\campaign\lib.ps1
Log-Scenario "V1" "script/verify-deploy.ps1 against the live node: every invariant from mined state"
Start-CampaignNode
$old = Deploy-OldToken
$st = Run-MainDeploy $old

# Nested powershell through Start-Process with redirected files: piping the
# child's stderr through Out-String can deadlock PS 5.1 when the child throws.
function Run-Verify { param([string[]]$extra = @())
  $so = Join-Path $env:TEMP "verify-out-$PID.txt"
  $vf = '"' + (Join-Path $script:ROOT "script\verify-deploy.ps1") + '"'
  $ex = @()
  foreach ($e in $extra) { if ($e -match "\s") { $ex += ('"' + $e + '"') } else { $ex += $e } }
  $verifyArgs = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $vf, "-Rpc", $script:RPC) + $ex
  $p = Start-Process powershell -ArgumentList $verifyArgs -NoNewWindow -Wait -PassThru -RedirectStandardOutput $so
  $text = if (Test-Path $so) { Get-Content $so -Raw } else { "" }
  Remove-Item $so -Force -ErrorAction SilentlyContinue
  return @($p.ExitCode, $text)
}
$r1 = Run-Verify
$vExit = $r1[0]; $vOut = $r1[1]
Log-Step "V1.1" "Full verification run" "every check green, exit code 0" "exit=$vExit, tail: $((($vOut -split "`r?`n" | Where-Object { $_ -match 'VERIFICATION' }) -join ' '))" $(if ($vExit -eq 0) { "PASS" } else { "DEVIATION" })
Log-Line ""
Log-Line "Full output of the verification, verbatim:"
Log-Line ""
Log-Line '```'
foreach ($l in ($vOut -split "`r?`n")) { Log-Line ($l.TrimEnd()) }
Log-Line '```'

# Negative control: the tool must FAIL when the world is wrong. Point it at a
# state file whose governor address is a random EOA and count the failures.
$stateFile = Join-Path $script:ROOT (Join-Path "deployments" "two-phase-97.json")
$bad = Get-Content $stateFile -Raw | ConvertFrom-Json
$bad.governor = "0x00000000000000000000000000000000000000AA"
$badPath = Join-Path $script:ROOT (Join-Path "deployments" "two-phase-97-bad.json")
$bad | ConvertTo-Json | Set-Content $badPath -Encoding ascii
$r2 = Run-Verify @("-StateFile", $badPath)
$v2Exit = $r2[0]
Remove-Item $badPath -Force
Log-Step "V1.2" "Counter-proof: a state file with a wrong governor address" "the verification fails loudly with a non-zero exit code" "exit=$v2Exit" $(if ($v2Exit -gt 0) { "PASS" } else { "DEVIATION" })
Stop-Anvil
Write-Output "V1 COMPLETE"
