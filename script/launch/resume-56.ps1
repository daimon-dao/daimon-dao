# Resume the BSC mainnet launch (docs/LAUNCH_DAY.md, master 9c4af2a) -- dot-source it:
#   . .\script\launch\resume-56.ps1
# State at the pause (2026-09-29 17:32 UTC, block 124757113): steps 1-8 DONE, 9 and 10 SKIPPED (see the journal's Incident).
# NEXT: the operator publishes the dApp, then 11a + 11b (owner, back to back).
# The deployer signs NOTHING more. Every remaining transaction is the DMX owner's, in MetaMask via BscScan.
# The journal is docs/MAINNET_LAUNCH_RECORD.md. No secrets in this file.

Set-Location "C:\Users\Utente\Desktop\Daimon dao"
$env:PATH = "$HOME\.foundry\bin;" + $env:PATH

# --- session setup, as in LAUNCH_DAY.md ---
$RPC      = "https://bsc-dataseed.bnbchain.org"      # the RPC of the day; it prunes old state (reads pinned to old blocks fail: use receipts)
$DEPLOYER = "0x4D38C9FE5250235dc99D3e098cd515B008aCa26e"   # dedicated Ledger -- DONE, nonce 20, signs nothing more
$DPATH    = "m/44'/60'/9'/0/0"
$OWNER    = "0xF8EC459CAEaF1052b64B38BDD67290B0c132B0Ae"   # DMX owner (MetaMask via BscScan)
$SAFE     = "0x37F45839765AD3418E29c97d5D92407Ddbf5c7a8"   # guardian, 2-of-3
$DMX      = "0x36EbA94407B53c631eE822C219e94580fadd67c7"
$DMX_POOL = "0xB24916823C61Ee6272448209174F75fAfD297B82"
$ROUTER   = "0x10ED43C718714eb63d5aA57B78B54704E256024E"
$FACTORY  = "0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73"
$WBNB     = "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c"
$GP       = (cast gas-price --rpc-url $RPC).Trim()

# --- deployed (all == the LAUNCH_DAY.md table) ---
$IMPL      = "0xA7bC2D4D35e49bdfC8329e3673d7De520832941c"
$TOKEN     = "0x160864F9945C52063A7c9f5dcd57C0C89eacbE6a"   # DMN proxy
$MIG       = "0x76368b60514b145617385847aCFF7b7EA9764725"
$TL        = "0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891"
$STAKING   = "0xBb596e7308D6C5AED55cEC597D372840Cbe575b1"
$GOVERNOR  = "0x1397a7d25595B718BE6FEEDd42ed5E60F66E16De"
$PAIR      = "0x40A97Ae210a44057603186B4BE92BAe719342AFA"
$SEEDER    = "0x21ab79825b86137CF1b04884FCFC4e4b717ce062"   # used() == true
$SEEDER_TX = "0x14548b14cd96323d518d85db43da15b2ae3524e152b0a858c180af38145b35ee"

# --- fixed at 5a (block 124637790), used through 5b -- DONE ---
$GROSS = "4999548574361503910682398180"
$BNB   = "1994000000000000000"
$NET   = "4799566631387043754255102254"

# --- expected at resume -- baseline of step 8 (block 124757113, 17:31:57 UTC), AFTER the 05:04 bot incident ---
#   (the 04:48 pause baseline -- reserves NET | BNB, inventory ~0.15 B -- was superseded by tx 0xa1238092...d048)
#   getReserves(PAIR) == 4948969529051442709553456167 | 1934053593848810506 until someone trades
#   fee inventory DMN.balanceOf(TOKEN) == 51553630463798540020259; staking totalVotingPower == 1, 0 BNB
#   DMX: owner() == OWNER, getUnlockTime() == 0, _maxTxAmount() == 1.5e27, isExcludedFromFee(TL) == false (11a/11b NOT done)
#   owner: nonce 1011, 0.390959 BNB, 0 DMN; deployer: nonce 20
#   steps 9 and 10 SKIPPED by decision; next: dApp publication, then 11a + 11b
#   11a expected data 0xec28438a000000000000000000000000000000000000000c9f2c9cd04674edea40000000
#   11b expected data 0x437823ec000000000000000000000000cdaa1cfe783a4de642ca3ed98a38bfdc16f30891
#   The DMX owner must NEVER call lock(), renounceOwnership or transferOwnership until 11b is done.

# P3 gate (not needed any more: no deployer step is left), kept for completeness.
function Assert-Deployer {
  $a = ((cast wallet address --ledger --mnemonic-derivation-path $DPATH 2>&1 | Select-Object -Last 1) | Out-String).Trim()
  if ($a -ne $DEPLOYER) { throw "STOP (P3): the Ledger returns '$a' at $DPATH, not $DEPLOYER -- nothing was sent" }
  Write-Output "P3 OK: $a at $DPATH"
}
