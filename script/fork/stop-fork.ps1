# Stops the local fork. The fork's state is discarded: every run starts
# from a fresh fork of mainnet (start-fork.ps1).
Get-Process anvil -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Write-Output "fork stopped"
