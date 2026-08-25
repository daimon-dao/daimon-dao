. .\script\campaign\lib.ps1
$t=[Diagnostics.Stopwatch]::StartNew(); Start-CampaignNode;  Write-Output "node up:        $([int]$t.Elapsed.TotalSeconds)s"
$t=[Diagnostics.Stopwatch]::StartNew(); $old = Deploy-OldToken; Write-Output "old token:      $([int]$t.Elapsed.TotalSeconds)s"
$t=[Diagnostics.Stopwatch]::StartNew(); $st = Run-MainDeploy $old; Write-Output "main deploy:    $([int]$t.Elapsed.TotalSeconds)s"
$t=[Diagnostics.Stopwatch]::StartNew(); Claim-Dmn "team1" (BW "40.00") | Out-Null; Write-Output "claim:          $([int]$t.Elapsed.TotalSeconds)s"
$t=[Diagnostics.Stopwatch]::StartNew(); Setup-Pool "team1" "4.00" | Out-Null; Write-Output "pool:           $([int]$t.Elapsed.TotalSeconds)s"
$t=[Diagnostics.Stopwatch]::StartNew(); Send "team1" $st.token "transfer(address,uint256)" @($script:Addr.bob, "$(BW '5.00')") | Out-Null; Write-Output "one transfer:   $([int]$t.Elapsed.TotalSeconds)s"
$t=[Diagnostics.Stopwatch]::StartNew(); Sell-Dmn "bob" (BW "0.50") | Out-Null; Write-Output "one sell:       $([int]$t.Elapsed.TotalSeconds)s"
$t=[Diagnostics.Stopwatch]::StartNew(); Warp (15*86400); Write-Output "one warp:       $([int]$t.Elapsed.TotalSeconds)s"
$t=[Diagnostics.Stopwatch]::StartNew(); Sell-Dmn "bob" (BW "0.50") | Out-Null; Write-Output "sell after warp:$([int]$t.Elapsed.TotalSeconds)s"
$t=[Diagnostics.Stopwatch]::StartNew(); Warp (15*86400); Sell-Dmn "bob" (BW "0.50") | Out-Null; Write-Output "warp+sell #2:   $([int]$t.Elapsed.TotalSeconds)s"
Stop-Anvil
