# LAUNCH_DAY step 2 environment -- dot-source AFTER session.ps1, in the SAME call as 2.1 / 2.2 / 2.3
$env:ROUTER = $ROUTER; $env:OLD_DAIMON = $DMX; $env:GUARDIAN_ADDRESS = $SAFE
$env:MIGRATION_DURATION = "7776000"     # 90 days -- immutable from the Migration's block
# = the doc's Remove-Item env:... line (the tool's path guard blocks that form)
"MARKETING_WALLET","TESTNET_TREASURY_OVERRIDE","TREASURY_ADDRESS" | ForEach-Object { [Environment]::SetEnvironmentVariable($_, $null, "Process") }
# hard gate: refuse to go on if the guardian is not the mainnet Safe
if ($env:GUARDIAN_ADDRESS -ne "0x37F45839765AD3418E29c97d5D92407Ddbf5c7a8") { throw "STOP: GUARDIAN_ADDRESS is '$env:GUARDIAN_ADDRESS', not the mainnet Safe" }
