# LAUNCH_DAY session setup (docs/LAUNCH_DAY.md, master 9c4af2a) -- dot-source at the start of every command
Set-Location "C:\Users\Utente\Desktop\Daimon dao"
$env:PATH = "$HOME\.foundry\bin;" + $env:PATH
$RPC      = "https://bsc-dataseed.bnbchain.org"
$DEPLOYER = "0x4D38C9FE5250235dc99D3e098cd515B008aCa26e"   # dedicated Ledger
$DPATH    = "m/44'/60'/9'/0/0"   # the deployer on the Ledger: Ledger Live scheme, account index 9 (index 0 is ANOTHER account)
$OWNER    = "0xF8EC459CAEaF1052b64B38BDD67290B0c132B0Ae"   # DMX owner
$SAFE     = "0x37F45839765AD3418E29c97d5D92407Ddbf5c7a8"   # guardian, 2-of-3
$DMX      = "0x36EbA94407B53c631eE822C219e94580fadd67c7"
$DMX_POOL = "0xB24916823C61Ee6272448209174F75fAfD297B82"
$ROUTER   = "0x10ED43C718714eb63d5aA57B78B54704E256024E"   # PancakeSwap v2, verified (journal F0.4)
$FACTORY  = "0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73"
$WBNB     = "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c"
$GP       = (cast gas-price --rpc-url $RPC).Trim()          # rehearsed at 50000000

# P3 as a hard gate: the Ledger must return $DEPLOYER at $DPATH, or nothing is sent.
function Assert-Deployer {
  $a = ((cast wallet address --ledger --mnemonic-derivation-path $DPATH 2>&1 | Select-Object -Last 1) | Out-String).Trim()
  if ($a -ne $DEPLOYER) { throw "STOP (P3): the Ledger returns '$a' at $DPATH, not $DEPLOYER -- nothing was sent" }
  Write-Output "P3 OK: $a at $DPATH"
}
$SEEDER    = "0x21ab79825b86137CF1b04884FCFC4e4b717ce062"
$SEEDER_TX = "0x14548b14cd96323d518d85db43da15b2ae3524e152b0a858c180af38145b35ee"
# fixed at 5a (block 124637790) -- used unchanged through 5b
$TOKEN   = "0x160864F9945C52063A7c9f5dcd57C0C89eacbE6a"
$MIG     = "0x76368b60514b145617385847aCFF7b7EA9764725"
$TL      = "0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891"
$STAKING = "0xBb596e7308D6C5AED55cEC597D372840Cbe575b1"
$PAIR    = "0x40A97Ae210a44057603186B4BE92BAe719342AFA"
$GROSS   = "4999548574361503910682398180"
$BNB     = "1994000000000000000"
$NET     = "4799566631387043754255102254"
