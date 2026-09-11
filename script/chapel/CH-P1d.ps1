# P1.4 -- Post-broadcast verification: the launch gate, against Chapel.
. $PSScriptRoot\lib.ps1
Log-Scenario "P1.4" "Post-broadcast verification: 34 checks from mined state (any failure stops the campaign)"
$so = Join-Path $env:TEMP "chapel-verify-$PID.txt"
$vf = '"' + (Join-Path $script:ROOT "script\verify-deploy.ps1") + '"'
$args2 = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $vf, "-Rpc", $script:RPC)
$p = Start-Process powershell -ArgumentList $args2 -NoNewWindow -Wait -PassThru -RedirectStandardOutput $so
$vOut = if (Test-Path $so) { Get-Content $so -Raw } else { "" }
Remove-Item $so -Force -ErrorAction SilentlyContinue
$tail = (($vOut -split "`r?`n") | Where-Object { $_ -match "VERIFICATION" }) -join " "
Log-Step "P1.4.1" "script/verify-deploy.ps1 -Rpc <chapel>" "every check green, exit 0" "exit=$($p.ExitCode); $tail" "-" $(if ($p.ExitCode -eq 0) { "PASS" } else { "DEVIATION" })
Log-Line ""
Log-Line "Full output, verbatim:"
Log-Line ""
Log-Line '```'
foreach ($l in ($vOut -split "`r?`n")) { Log-Line ($l.TrimEnd()) }
Log-Line '```'
if ($p.ExitCode -ne 0) { Write-Output "P1d FAILED - CAMPAIGN STOPS"; exit 1 }
Assert-Invariants "post-verification"
Write-Output "P1d COMPLETE"
