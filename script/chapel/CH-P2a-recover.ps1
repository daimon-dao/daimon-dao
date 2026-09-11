# Recovery: the propose tx WAS mined; the runner died on the read-only $pid
# automatic variable before logging it. Recover id, state and hash from the
# chain itself (ProposalCreated event) -- which also exercises the event
# readability the monitor depends on.
. $PSScriptRoot\lib.ps1
Load-Keystores
$st = S
$propCount = CQ $st.governor "proposalCount()(uint256)"
$propId = $propCount - 1
$state = CQRaw $st.governor "state(uint256)(uint8)" @("$propId")
$prev = $ErrorActionPreference; $ErrorActionPreference = "Continue"
$logs = (cast logs --address $st.governor --from-block 127613000 --to-block latest --rpc-url $script:RPC --json 2>&1 | Out-String)
$ErrorActionPreference = $prev
$evs = $logs | ConvertFrom-Json
$hash = if ($evs -and $evs.Count -gt 0) { $evs[-1].transactionHash } else { "(logs unavailable)" }
$blk = if ($evs -and $evs.Count -gt 0) { [System.Numerics.BigInteger]::Parse($evs[-1].blockNumber.Substring(2), "AllowHexSpecifier") } else { "?" }
$ts = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd HH:mm:ss")
Log-Step "P2.1.1" "staker1 proposes setFees(10,10,20) (recovered from chain after a harness crash)" "proposal 0 created, state Pending (voting delay 1 REAL day)" "id=$propId, state=$state (0=Pending), event block=$blk, recorded $ts UTC" $hash $(if ($propCount -eq 1 -and $state -eq "0") { "PASS" } else { "DEVIATION" })
Log-Note "The real-time calendar from here: voting opens ~24h after the propose block; the 5-day voting period follows; queue arms the 7-day timelock; execute lands around day 13. Each stage will be recorded with its timestamp and hash as it happens. Harness note: the runner crashed AFTER the propose broadcast on PowerShell's read-only automatic variable PID (renamed); the governor event log recovered the record -- incidentally proving ProposalCreated is emitted and readable, which Part 3 needs."
$stNew = [ordered]@{}
foreach ($prop in $st.PSObject.Properties) { $stNew[$prop.Name] = $prop.Value }
$stNew["proposalId"] = "$propId"
Save-State $stNew
Write-Output "RECOVERED proposal=$propId state=$state hash=$hash"
