# Day 1 -- Chapel: the journal header, the harness table and the account
# safety facts, read from the chain BEFORE any campaign transaction. The
# one funding move of the day happens FIRST, here, before phase 1 so the
# deployer's nonce between the phases stays untouched: -TopUpTbnb sends
# that many tBNB from the deployer to oldowner (the liquidity leg lives
# with the mock owner, as it will on mainnet). Otherwise read-only.
param([string]$TopUpTbnb = "0")
. $PSScriptRoot\lib.ps1
Load-Keystores
$existing = S
if ($existing -and $existing.old) { throw "state.json already carries a mock predecessor ($($existing.old)): Day 1 has started, do not rewrite the header" }
$day = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd")
$topUp = $null
if ($TopUpTbnb -ne "0") {
  $wei = [System.Numerics.BigInteger]([decimal]$TopUpTbnb * 1000000) * ($script:E18 / 1000000)
  $ks = Ks "deployer"; $pf = Pf
  $prev = $ErrorActionPreference; $ErrorActionPreference = "Continue"
  $r = (cast send $script:AddrBook.oldowner --value "$wei" --account $ks --password-file $pf --rpc-url $script:RPC --json 2>&1 | Out-String)
  $c = $LASTEXITCODE; $ErrorActionPreference = $prev
  if ($c -ne 0) { throw "TOP-UP FAILED: $(($r -replace '\s+',' ').Trim())" }
  $j = $r | ConvertFrom-Json
  if ($j.status -ne "0x1") { throw "TOP-UP REVERTED: $($j.transactionHash)" }
  $topUp = @{ wei = $wei; hash = $j.transactionHash }
}
$blk = BlockNumber

Log-Line ""
Log-Line "## Day 1 -- Chapel ($day)"
Log-Line ""
Log-Line "First broadcast on BSC Chapel (chain id 97) of the launch-script changes"
Log-Line "rehearsed on the fork on Day 0. Same method as Level 2: real keystores,"
Log-Line "real blocks, real gas, one second per second; every state-changing step"
Log-Line "records its transaction hash; every value asserted is read from MINED"
Log-Line "state; no assert is ever adapted. One script change landed between Day 0"
Log-Line "and today, committed on its own: the MARKETING_WALLET override is refused"
Log-Line "on chain 56 exactly as the treasury override is (DeployPhase1, re-guarded"
Log-Line "in DeployPhase2). Neither override is set here."
Log-Line ""
Log-Line "### Harness (Day 1)"
Log-Line ""
Log-Line "| piece | choice |"
Log-Line "|---|---|"
Log-Line "| Chain | BSC Chapel (97), RPC ``$($script:RPC)`` -- the harness refuses any other chain id at load |"
Log-Line "| Roles | TWO signing roles mirror mainnet: **deployer** (phases 1 and 2, the verification, and NOTHING between the phases) and **oldowner** (owner of the CampaignOldDaimon mock: the liquidity claim, the liquidity, LP to the Timelock, 11a/11b). Two campaign roles: **holder** (non-owner claimant, staker, proposer) and **stranger** (test sell, poke) |"
Log-Line "| Guardian | the test Safe ``$($script:GUARDIAN)`` (2 of 3), never signs through this harness |"
Log-Line "| Marketing wallet | the Timelock (H0.1): no ``MARKETING_WALLET`` in the environment, no treasury override |"
Log-Line "| Predecessor | ``script/campaign/CampaignOldDaimon.sol`` (11% fee, owner-gated exemptions, the 1.5B cap of H0.5), deployed and owned by **oldowner** |"
Log-Line "| Opening price | a PARAMETER: $($script:PRICE_LABEL) = $($script:PRICE_WEI_PER_TOKEN) wei per whole DMN. Liquidity sizing per decision (c) on the maxTx finding: the largest single addLiquidityETH the token's 5B maxTx allows (mainnet: 5B gross, 4.8B net, 2.2512 BNB), scaled on Chapel to the tBNB oldowner holds; the DMN leg is derived from the BNB at that ratio and sent gross so the pair receives the net (#17) |"
Log-Line "| Invariant | after every signed send: the Timelock holds 0 native and 0 DMN -- with share 1000 nothing reaches it from the token (its predecessor-token balance grows with claims, its LP balance is set at step 6: neither is a token payout) |"
Log-Line "| Signing | ``cast send --account <keystore> --password-file <path>``; names, addresses and the path live in ``script/chapel2b/keystore-map.json`` (gitignored) |"
Log-Line "| Runners | ``script/chapel2b/H1a..H1f``, ``H2``, ``H3a`` -- one per sitting, rows appended here by the runner, state carried in ``script/chapel2b/state.json`` (gitignored) |"
Log-Line ""
Log-Line "### Account safety (read at block $blk, before any campaign transaction)"
Log-Line ""
if ($topUp) {
  Log-Line "Funding, the only value transfer of the day and the FIRST transaction: deployer -> oldowner $(FmtT $topUp.wei) tBNB, tx $($topUp.hash) -- done before phase 1, so the deployer signs nothing between the two phases. The liquidity leg lives with the mock owner, as it will on mainnet with the DMX owner."
  Log-Line ""
}
Log-Line "| role | address | code | balance | nonce |"
Log-Line "|---|---|---|---|---|"
$bad = 0
foreach ($role in @("deployer", "oldowner", "holder", "stranger")) {
  $a = $script:AddrBook[$role]
  $cl = Code-Len $a
  $codeTxt = if ($cl -le 2) { "``0x`` (none)" } else { "PRESENT ($cl chars) -- NOT a plain EOA"; $bad++ }
  Log-Line "| $role | $a | $codeTxt | $(FmtT (Bal $a)) tBNB | $(Nonce $a) |"
}
$gcl = Code-Len $script:GUARDIAN
Log-Line "| guardian (Safe) | $($script:GUARDIAN) | contract ($gcl chars) | $(FmtT (Bal $script:GUARDIAN)) tBNB | -- |"
Log-Line ""
if ($bad -gt 0) { Log-Line "**STOP: a role address carries code (EIP-7702 delegation or contract).**"; throw "a role address carries code" }
Log-Line "Every signing role: no code (no EIP-7702 delegation, no contract). The"
Log-Line "deployer is the Level-2 deployer, its nonce is not virgin: the two-phase"
Log-Line "predictions are computed from the LIVE nonce, as the scripts do."
Log-Line ""
Log-Line "---"
Save-State ([ordered]@{ day = $day; headerBlock = "$blk"; invariantChecks = 0 })
Write-Output "D1 header written (block $blk)"
