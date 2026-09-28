# Mainnet-fork rehearsal -- journal

The launch day, steps 1-11b of CHECKLIST_MAINNET.md, run on a LOCAL Anvil
fork of BNB Smart Chain mainnet (chain 56) against the REAL predecessor DMX
(`0x36EbA94407B53c631eE822C219e94580fadd67c7`), the REAL DMX/WBNB pool
(`0xB24916823C61Ee6272448209174F75fAfD297B82`) and the REAL PancakeSwap v2
router (`0x10ED43C718714eb63d5aA57B78B54704E256024E`). Every earlier
rehearsal (fork campaign, Chapel L2, Chapel 2b) used a mock of DMX; this
one does not.

- Code: tag `launch-config-rc1` (src/ and the launch scripts untouched).
- Harness: `script/fork/` on branch `rehearsal/mainnet-fork`.
- Safety: nothing is broadcast to the real network. Every send goes through
  a guard (`Assert-LocalFork`: loopback URL, Anvil client, chain 56, a fork)
  and every signer is impersonated on the fork: no private key exists in
  the harness, cast and forge run `--unlocked`.
- Funding: the deployer is set on the fork to exactly the planned 0.2 BNB;
  the DMX owner keeps its REAL balance (unless a run says otherwise, in a
  row marked SETUP DEVIATION).
- Third-party holders: two real DMX holders from the live holder list,
  impersonated with their real BNB; their addresses are kept in a
  gitignored file and never appear here. Their claim sizes are round
  numbers (10.00 B and 1.00 B) so that no row identifies them.
- Gas: every transaction pays the mainnet gas price read at fork time, so
  the BNB totals are the real funding numbers.

Rows are written by the runners as they run and are never rewritten.
Verdicts: PASS (as expected), NOTE (recorded, no expectation), FINDING (a
real-world fact the plan must absorb), STOP (a planned halt), DEVIATION
(the expectation failed).

The launch-day script derived from these runs: [LAUNCH_DAY.md](LAUNCH_DAY.md).

## Run A

### F0 (run A) -- Real mainnet reads, then the local fork of chain 56 at block 124563923

| step | action | expected | observed | tx | verdict |
|---|---|---|---|---|---|
| F0.1 | Planned mainnet deployer, read on MAINNET | nonce 0 (never used: phase 1 must predict from nonce 0); no code | nonce=0, balance=0.000000 BNB (0 wei), code=0x | - | PASS |
| F0.2 | DMX owner, read on MAINNET | an EOA; its real BNB balance is what funds 5a-11b | balance=0.096153 BNB (96153397983002775 wei), nonce=1005, code=0x, DMX held=103.8537 B | - | PASS |
| F0.3 | The predecessor's authority and cap, read on MAINNET (checklist: 'confirm the DMX owner still has authority') | owner() == the DMX owner; _maxTxAmount == 1.5B; owner fee-exempt; not in a lock() window (getUnlockTime 0) | owner=0xF8EC459CAEaF1052b64B38BDD67290B0c132B0Ae, _maxTxAmount=1.5000 B, isExcludedFromFee(owner)=true, getUnlockTime=0 | - | PASS |
| F0.4 | ROUTER identity, from source and chain (not guessed) | developer.pancakeswap.finance/contracts/v2/addresses lists router 0x10ED43C718714eb63d5aA57B78B54704E256024E and factory 0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73 for BSC; on chain: router.factory() and router.WETH() match, DMX.uniswapV2Router() is the same router, factory.getPair(DMX, WBNB) == DMX.uniswapV2Pair() | router.factory=0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73, router.WETH=0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c, DMX.uniswapV2Router=0x10ED43C718714eb63d5aA57B78B54704E256024E, factory.getPair(DMX,WBNB)=0xB24916823C61Ee6272448209174F75fAfD297B82, DMX.uniswapV2Pair=0xB24916823C61Ee6272448209174F75fAfD297B82, INIT_CODE_PAIR_HASH=0x00fb7f630766e6a796048ea87d01acd3068e8ff67d078148a3fa3f4a84f69bd5 | - | PASS |
| F0.5 | Mainnet gas price at fork time | every fork transaction pays exactly this, so the BNB totals are the real funding numbers | eth_gasPrice=50000000 wei (0.05 gwei) | - | NOTE |
| F0.6 | Local fork up | Anvil on 127.0.0.1:8555, chain 56, forked from the upstream at the pinned block | clientVersion="anvil/v1.5.1", chainId=56, forkUrl=https://bsc-rpc.publicnode.com, forkBlockNumber=124563923, local head=124563923 | - | PASS |
| F0.7 | Roles on the fork: deployer and owner impersonated (no key anywhere); deployer set to exactly 0.2 BNB (anvil_setBalance, the only balance ever set); the owner left at its real balance | deployer nonce 0, balance 0.200000 BNB; owner balance on the fork == the mainnet read | deployer nonce=0, balance=0.200000 (200000000000000000 wei); owner fork balance=0.096153 vs mainnet 0.096153 | - | PASS |
| F0.8 | Two REAL third-party DMX holders from the live holder list (BSCTrace, 2026-09-28), impersonated, their real BNB untouched; addresses in a gitignored file, never in this journal | holder A: > 10 B DMX (claims 10.00 B after 11b, 6.7x the old cap); holder B: 1.00-1.50 B (claims 1.00 B, below the cap); neither fee- nor reward-excluded on DMX; neither is a contract | A: > 10 B, EOA with an EIP-7702 delegation, feeExcluded=false, rewardExcluded=false; B: 1.00-1.50 B, plain EOA, feeExcluded=false, rewardExcluded=false | - | PASS |

### F1-F2 (run A) -- Step 1: no DMN/WBNB pair for the predicted proxy; step 2: phase 1 then phase 2 against the real router and the real DMX

| step | action | expected | observed | tx | verdict |
|---|---|---|---|---|---|
| F1.0 | The fork against the pinned block, first uncached read (factory.getPair storage), about 12 minutes after pinning | the upstream serves the pinned block's state for the whole run | FAILED on pruned state: 'failed to get storage for 0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73 ... HTTP 403: Archive requests require a personal token' -- publicnode (like every public full node probed on 2026-09-28: the Binance/defibit/ninicoin dataseeds, NodeReal, 1rpc, blockrazor, bloXroute) serves only about 60-128 blocks of state, i.e. about 1-1.5 minutes at BSC's 0.75 s blocks; a launch-day rehearsal takes far longer | - | STOP |

> Run A stopped here, as the rehearsal plan requires on pruned state: no deploy was attempted, nothing was mined on the fork beyond the setup of F0. The runs below use a public endpoint that DOES serve historical state (bsc-mainnet.public.blastapi.io, no key; probed the same day at 10, 60, 200, 1000 and 20000 blocks back).

## Run B

### F0 (run B) -- Real mainnet reads, then the local fork of chain 56 at block 124565466

| step | action | expected | observed | tx | verdict |
|---|---|---|---|---|---|
| F0.1 | Planned mainnet deployer, read on MAINNET | nonce 0 (never used: phase 1 must predict from nonce 0); no code | nonce=0, balance=0.000000 BNB (0 wei), code=0x | - | PASS |
| F0.2 | DMX owner, read on MAINNET | an EOA; its real BNB balance is what funds 5a-11b | balance=0.096153 BNB (96153397983002775 wei), nonce=1005, code=0x, DMX held=103.8537 B | - | PASS |
| F0.3 | The predecessor's authority and cap, read on MAINNET (checklist: 'confirm the DMX owner still has authority') | owner() == the DMX owner; _maxTxAmount == 1.5B; owner fee-exempt; not in a lock() window (getUnlockTime 0) | owner=0xF8EC459CAEaF1052b64B38BDD67290B0c132B0Ae, _maxTxAmount=1.5000 B, isExcludedFromFee(owner)=true, getUnlockTime=0 | - | PASS |
| F0.4 | ROUTER identity, from source and chain (not guessed) | developer.pancakeswap.finance/contracts/v2/addresses lists router 0x10ED43C718714eb63d5aA57B78B54704E256024E and factory 0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73 for BSC; on chain: router.factory() and router.WETH() match, DMX.uniswapV2Router() is the same router, factory.getPair(DMX, WBNB) == DMX.uniswapV2Pair() | router.factory=0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73, router.WETH=0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c, DMX.uniswapV2Router=0x10ED43C718714eb63d5aA57B78B54704E256024E, factory.getPair(DMX,WBNB)=0xB24916823C61Ee6272448209174F75fAfD297B82, DMX.uniswapV2Pair=0xB24916823C61Ee6272448209174F75fAfD297B82, INIT_CODE_PAIR_HASH=0x00fb7f630766e6a796048ea87d01acd3068e8ff67d078148a3fa3f4a84f69bd5 | - | PASS |
| F0.5 | Mainnet gas price at fork time | every fork transaction pays exactly this, so the BNB totals are the real funding numbers | eth_gasPrice=50000000 wei (0.05 gwei) | - | NOTE |
| F0.6 | Local fork up | Anvil on 127.0.0.1:8555, chain 56, forked from the upstream at the pinned block | clientVersion="anvil/v1.5.1", chainId=56, forkUrl=https://bsc-mainnet.public.blastapi.io, forkBlockNumber=124565466, local head=124565466 | - | PASS |
| F0.7 | Roles on the fork: deployer and owner impersonated (no key anywhere); deployer set to exactly 0.2 BNB (anvil_setBalance, the only balance ever set); the owner left at its real balance | deployer nonce 0, balance 0.200000 BNB; owner balance on the fork == the mainnet read | deployer nonce=0, balance=0.200000 (200000000000000000 wei); owner fork balance=0.096153 vs mainnet 0.096153 | - | PASS |
| F0.8 | Two REAL third-party DMX holders from the live holder list (BSCTrace, 2026-09-28), impersonated, their real BNB untouched; addresses in a gitignored file, never in this journal | holder A: > 10 B DMX (claims 10.00 B after 11b, 6.7x the old cap); holder B: 1.00-1.50 B (claims 1.00 B, below the cap); neither fee- nor reward-excluded on DMX; neither is a contract | A: > 10 B, EOA with an EIP-7702 delegation, feeExcluded=false, rewardExcluded=false; B: 1.00-1.50 B, plain EOA, feeExcluded=false, rewardExcluded=false | - | PASS |

### F1-F2 (run B) -- Step 1: no DMN/WBNB pair for the predicted proxy; step 2: phase 1 then phase 2 against the real router and the real DMX

| step | action | expected | observed | tx | verdict |
|---|---|---|---|---|---|
| F1.1 | Step 1 (#25): the REAL PancakeSwap factory, getPair(predicted proxy, WBNB), before phase 1 | 0x0; and no code at the predicted proxy, migration and Timelock | deployer nonce=0; predicted impl=0xA7bC2D4D35e49bdfC8329e3673d7De520832941c, proxy=0x160864F9945C52063A7c9f5dcd57C0C89eacbE6a, migration=0x76368b60514b145617385847aCFF7b7EA9764725, timelock=0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891; getPair=0x0000000000000000000000000000000000000000; code chars at the three=6 (6 = three empty '0x') | - | PASS |
| F2.1 | Phase 1 SIMULATED on chain 56 with the launch environment: ROUTER, OLD_DAIMON (real DMX), GUARDIAN_ADDRESS (real Safe); no MARKETING_WALLET, no TESTNET_TREASURY_OVERRIDE; MIGRATION_DURATION unset | exit 0; treasury AND marketing wallet logged '(= predicted timelock)'; no override or warning line | exit=0; derived lines=2; override/warning lines=0; 'Migration duration (days): 30' | - | PASS |

> MIGRATION_DURATION was left unset, so phase 1 used its default: 30 days. No document in the repository fixes the mainnet value; the deadline is immutable from phase 1. It is a launch-day input to decide before phase 1 (LAUNCH_DAY.md, inputs).
| F2.2 | Phase 1 BROADCAST (impersonated deployer, mainnet gas price) | impl/proxy/migration on the predicted nonces 0/1/2; marketingWallet, migration.treasury, migration.governance == the predicted Timelock (nonce 3); migration.oldDaimon == the REAL DMX; token router == the real router; deployer nonce == expectedPhase2Nonce; no override | 3 txs, gas 8503675, cost 0.000425 BNB; token=0x160864F9945C52063A7c9f5dcd57C0C89eacbE6a, migration=0x76368b60514b145617385847aCFF7b7EA9764725, predictedTimelock=0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891; marketingWallet=0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891, treasury=0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891, governance=0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891, oldDaimon=0x36EbA94407B53c631eE822C219e94580fadd67c7, router=0x10ED43C718714eb63d5aA57B78B54704E256024E, pair created=0x40A97Ae210a44057603186B4BE92BAe719342AFA; nonce=3 (expected 3) | journal broadcast/DeployPhase1.s.sol/56 | PASS |

Phase 1 console, completion block verbatim:

```
  Migration duration (days): 30
  === PHASE 1 complete ===
  DaimonV2 (proxy):      0x160864F9945C52063A7c9f5dcd57C0C89eacbE6a
  DaimonMigration:       0x76368b60514b145617385847aCFF7b7EA9764725
  Timelock (predicted):  0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891
  Migration treasury:    0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891 (= predicted timelock)
  Marketing wallet:      0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891 (= predicted timelock)
```
| F2.3 | Phase 2 BROADCAST right after phase 1 (deployer nonce untouched in between) | Timelock lands on the prediction; fees 10/10/20 (liquidityFee 30); share 1000; ONE guardian expiry on three contracts; governor.guardian == the real Safe | nonce before=3 (expected ); 16 txs, gas 4928945, cost 0.000246 BNB; timelock=0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891, staking=0xBb596e7308D6C5AED55cEC597D372840Cbe575b1, governor=0x1397a7d25595B718BE6FEEDd42ed5E60F66E16De; fees=10/10/20 liq=30; share=1000; expiry token/timelock/governor=1885224851/1885224851/1885224851; governor.guardian=0x37F45839765AD3418E29c97d5D92407Ddbf5c7a8 | journal broadcast/DeployPhase2.s.sol/56 | DEVIATION |

> Annotation to F2.3 (harness-side DEVIATION, not a launch finding): the check compared the live nonce against expectedPhase2Nonce re-read from deployments/two-phase-56.json AFTER phase 2 had rewritten it as the complete record, which no longer carries that field -- hence 'expected' printed empty. Every value in the row is the launch value: nonce 3 before phase 2 (phase 1 left expectedPhase2Nonce = 3, F2.2), Timelock on the prediction, fees 10/10/20, share 1000, one expiry, governor.guardian = the Safe. Run B ends here; the runner now captures the expected nonce before phase 2. Artifacts moved to script/fork/out/run-B.

## Run C

### F0 (run C) -- Real mainnet reads, then the local fork of chain 56 at block 124565662

| step | action | expected | observed | tx | verdict |
|---|---|---|---|---|---|
| F0.1 | Planned mainnet deployer, read on MAINNET | nonce 0 (never used: phase 1 must predict from nonce 0); no code | nonce=0, balance=0.000000 BNB (0 wei), code=0x | - | PASS |
| F0.2 | DMX owner, read on MAINNET | an EOA; its real BNB balance is what funds 5a-11b | balance=0.096153 BNB (96153397983002775 wei), nonce=1005, code=0x, DMX held=103.8537 B | - | PASS |
| F0.3 | The predecessor's authority and cap, read on MAINNET (checklist: 'confirm the DMX owner still has authority') | owner() == the DMX owner; _maxTxAmount == 1.5B; owner fee-exempt; not in a lock() window (getUnlockTime 0) | owner=0xF8EC459CAEaF1052b64B38BDD67290B0c132B0Ae, _maxTxAmount=1.5000 B, isExcludedFromFee(owner)=true, getUnlockTime=0 | - | PASS |
| F0.4 | ROUTER identity, from source and chain (not guessed) | developer.pancakeswap.finance/contracts/v2/addresses lists router 0x10ED43C718714eb63d5aA57B78B54704E256024E and factory 0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73 for BSC; on chain: router.factory() and router.WETH() match, DMX.uniswapV2Router() is the same router, factory.getPair(DMX, WBNB) == DMX.uniswapV2Pair() | router.factory=0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73, router.WETH=0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c, DMX.uniswapV2Router=0x10ED43C718714eb63d5aA57B78B54704E256024E, factory.getPair(DMX,WBNB)=0xB24916823C61Ee6272448209174F75fAfD297B82, DMX.uniswapV2Pair=0xB24916823C61Ee6272448209174F75fAfD297B82, INIT_CODE_PAIR_HASH=0x00fb7f630766e6a796048ea87d01acd3068e8ff67d078148a3fa3f4a84f69bd5 | - | PASS |
| F0.5 | Mainnet gas price at fork time | every fork transaction pays exactly this, so the BNB totals are the real funding numbers | eth_gasPrice=50000000 wei (0.05 gwei) | - | NOTE |
| F0.6 | Local fork up | Anvil on 127.0.0.1:8555, chain 56, forked from the upstream at the pinned block | clientVersion="anvil/v1.5.1", chainId=56, forkUrl=https://bsc-mainnet.public.blastapi.io, forkBlockNumber=124565662, local head=124565662 | - | PASS |
| F0.7 | Roles on the fork: deployer and owner impersonated (no key anywhere); deployer set to exactly 0.2 BNB (anvil_setBalance, the only balance ever set); the owner left at its real balance | deployer nonce 0, balance 0.200000 BNB; owner balance on the fork == the mainnet read | deployer nonce=0, balance=0.200000 (200000000000000000 wei); owner fork balance=0.096153 vs mainnet 0.096153 | - | PASS |
| F0.8 | Two REAL third-party DMX holders from the live holder list (BSCTrace, 2026-09-28), impersonated, their real BNB untouched; addresses in a gitignored file, never in this journal | holder A: > 10 B DMX (claims 10.00 B after 11b, 6.7x the old cap); holder B: 1.00-1.50 B (claims 1.00 B, below the cap); neither fee- nor reward-excluded on DMX; neither is a contract | A: > 10 B, EOA with an EIP-7702 delegation, feeExcluded=false, rewardExcluded=false; B: 1.00-1.50 B, plain EOA, feeExcluded=false, rewardExcluded=false | - | PASS |

### F1-F2 (run C) -- Step 1: no DMN/WBNB pair for the predicted proxy; step 2: phase 1 then phase 2 against the real router and the real DMX

| step | action | expected | observed | tx | verdict |
|---|---|---|---|---|---|
| F1.1 | Step 1 (#25): the REAL PancakeSwap factory, getPair(predicted proxy, WBNB), before phase 1 | 0x0; and no code at the predicted proxy, migration and Timelock | deployer nonce=0; predicted impl=0xA7bC2D4D35e49bdfC8329e3673d7De520832941c, proxy=0x160864F9945C52063A7c9f5dcd57C0C89eacbE6a, migration=0x76368b60514b145617385847aCFF7b7EA9764725, timelock=0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891; getPair=0x0000000000000000000000000000000000000000; code chars at the three=6 (6 = three empty '0x') | - | PASS |
| F2.1 | Phase 1 SIMULATED on chain 56 with the launch environment: ROUTER, OLD_DAIMON (real DMX), GUARDIAN_ADDRESS (real Safe); no MARKETING_WALLET, no TESTNET_TREASURY_OVERRIDE; MIGRATION_DURATION unset | exit 0; treasury AND marketing wallet logged '(= predicted timelock)'; no override or warning line | exit=0; derived lines=2; override/warning lines=0; 'Migration duration (days): 30' | - | PASS |

> MIGRATION_DURATION was left unset, so phase 1 used its default: 30 days. No document in the repository fixes the mainnet value; the deadline is immutable from phase 1. It is a launch-day input to decide before phase 1 (LAUNCH_DAY.md, inputs).
| F2.2 | Phase 1 BROADCAST (impersonated deployer, mainnet gas price) | impl/proxy/migration on the predicted nonces 0/1/2; marketingWallet, migration.treasury, migration.governance == the predicted Timelock (nonce 3); migration.oldDaimon == the REAL DMX; token router == the real router; deployer nonce == expectedPhase2Nonce; no override | 3 txs, gas 8503675, cost 0.000425 BNB; token=0x160864F9945C52063A7c9f5dcd57C0C89eacbE6a, migration=0x76368b60514b145617385847aCFF7b7EA9764725, predictedTimelock=0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891; marketingWallet=0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891, treasury=0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891, governance=0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891, oldDaimon=0x36EbA94407B53c631eE822C219e94580fadd67c7, router=0x10ED43C718714eb63d5aA57B78B54704E256024E, pair created=0x40A97Ae210a44057603186B4BE92BAe719342AFA; nonce=3 (expected 3) | journal broadcast/DeployPhase1.s.sol/56 | PASS |

Phase 1 console, completion block verbatim:

```
  Migration duration (days): 30
  === PHASE 1 complete ===
  DaimonV2 (proxy):      0x160864F9945C52063A7c9f5dcd57C0C89eacbE6a
  DaimonMigration:       0x76368b60514b145617385847aCFF7b7EA9764725
  Timelock (predicted):  0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891
  Migration treasury:    0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891 (= predicted timelock)
  Marketing wallet:      0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891 (= predicted timelock)
```
| F2.3 | Phase 2 BROADCAST right after phase 1 (deployer nonce untouched in between) | Timelock lands on the prediction; fees 10/10/20 (liquidityFee 30); share 1000; ONE guardian expiry on three contracts; governor.guardian == the real Safe | nonce before=3 (expected 3); 16 txs, gas 4928945, cost 0.000246 BNB; timelock=0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891, staking=0xBb596e7308D6C5AED55cEC597D372840Cbe575b1, governor=0x1397a7d25595B718BE6FEEDd42ed5E60F66E16De; fees=10/10/20 liq=30; share=1000; expiry token/timelock/governor=1885224935/1885224935/1885224935; governor.guardian=0x37F45839765AD3418E29c97d5D92407Ddbf5c7a8 | journal broadcast/DeployPhase2.s.sol/56 | PASS |
| F2.4 | Deployer after both phases | it signs nothing else for the rest of the day | nonce=19, balance=0.199328 BNB; phases 1+2: 19 txs, gas 13432620, cost 0.000671 BNB | - | NOTE |

### F3-F4 (run C) -- Step 3: the mandatory gate; step 4: automation inert without reserves

| step | action | expected | observed | tx | verdict |
|---|---|---|---|---|---|
| F3.1 | Step 3: script/verify-deploy.ps1 -Rpc <the local fork> | 36/36 green, exit code 0 -- MANDATORY GATE | exit=0; Post-broadcast verification -- chain 56 VERIFICATION PASSED: 36/36 checks green against live chain state. | - | PASS |

Full output of the verification, verbatim:

```
Post-broadcast verification -- chain 56
State file: C:\Users\Utente\Desktop\Daimon dao\deployments\two-phase-56.json


check                                                  expected                                   observed                                   verdict
-----                                                  --------                                   --------                                   -------
code at token                                          present                                    present                                    PASS
code at timelock                                       present                                    present                                    PASS
code at governor                                       present                                    present                                    PASS
code at staking                                        present                                    present                                    PASS
code at migration                                      present                                    present                                    PASS
token: timelock holds GOVERNANCE_ROLE                  true                                       true                                       PASS
token: deployer lacks GOVERNANCE_ROLE                  false                                      false                                      PASS
token: deployer lacks DEFAULT_ADMIN                    false                                      false                                      PASS
token: guardian holds GUARDIAN_ROLE                    true                                       true                                       PASS
token: stakingRewardShareBps == 1000                   1000                                       1000                                       PASS
token: stakingContract is the staking                  0xBb596e7308D6C5AED55cEC597D372840Cbe575b1 0xBb596e7308D6C5AED55cEC597D372840Cbe575b1 PASS
token: marketingWallet as configured                   0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891 0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891 PASS
token: migration is fee-exempt                         true                                       true                                       PASS
token: fees == (10,10,20)                              10,10,20                                   10,10,20                                   PASS
timelock: self-administers                             true                                       true                                       PASS
timelock: deployer lacks ADMIN_ROLE                    false                                      false                                      PASS
timelock: deployer lacks PROPOSER_ROLE                 false                                      false                                      PASS
timelock: deployer lacks EXECUTOR_ROLE                 false                                      false                                      PASS
timelock: governor is proposer                         true                                       true                                       PASS
timelock: governor is executor                         true                                       true                                       PASS
timelock: guardian is canceller                        true                                       true                                       PASS
timelock: governor is canceller                        true                                       true                                       PASS
timelock: self-cancel role present                     true                                       true                                       PASS
expiry: timelock == token (exact)                      1885224935                                 1885224935                                 PASS
expiry: governor == token (exact)                      1885224935                                 1885224935                                 PASS
staking: timelock is governance                        true                                       true                                       PASS
staking: deployer is not governance                    false                                      false                                      PASS
supply: totalSupply == INITIAL_SUPPLY                  1000000000000000000000000000000            1000000000000000000000000000000            PASS
supply: all of it in the migration                     1000000000000000000000000000000            1000000000000000000000000000000            PASS
migration: governance is the timelock                  0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891 0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891 PASS
migration: newDaimon is the token                      0x160864F9945C52063A7c9f5dcd57C0C89eacbE6a 0x160864F9945C52063A7c9f5dcd57C0C89eacbE6a PASS
migration: oldDaimon as configured                     0x36EbA94407B53c631eE822C219e94580fadd67c7 0x36EbA94407B53c631eE822C219e94580fadd67c7 PASS
migration: treasury as configured                      0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891 0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891 PASS
migration: treasury is the timelock                    0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891 0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891 PASS
token: marketingWallet is the deployed timelock (live) 0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891 0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891 PASS
token: pancake pair created                            present                                    present                                    PASS



Guardian expiry raw values: token=1885224935 timelock=1885224935 governor=1885224935
VERIFICATION PASSED: 36/36 checks green against live chain state.

```
| F4.1 | Step 4 (#27): automation before liquidity | enabled by initialize, inert by construction: inventory 0, reserves (0,0), contract BNB 0 | swapAndLiquifyEnabled=true, buyBackEnabled=true, inventory=0, reserves=(0,0), contract BNB=0 | - | PASS |

### F5a (run C) -- Step 5a on the REAL DMX: a non-owner is refused, the owner claims only the liquidity quota

| step | action | expected | observed | tx | verdict |
|---|---|---|---|---|---|
| F5a.1 | A REAL non-owner (holder B, below the cap, not fee-exempt) approves then claims 1.00 B, BEFORE 11b | refused with AmountMismatch (#29): the real DMX takes its 11% on the claimant -> treasury leg; nothing credited | approve mined (holder B's own gas); claim: reverted with AmountMismatch; holder B DMN=0 | 0x07647f4a4cf803214ea60948a9b4207147cf9a495be531ee4b93ac560d557255 | PASS |
| F5a.2 | Why the owner can claim now: its status on the REAL DMX | owner() == the DMX owner (cap-exempt as sender), isExcludedFromFee(owner) true; the Timelock NOT exempt (11b not done); cap 1.5B (11a not done) | owner=0xF8EC459CAEaF1052b64B38BDD67290B0c132B0Ae, isExcludedFromFee(owner)=true, isExcludedFromFee(timelock)=false, _maxTxAmount=1.5000 B | - | PASS |
| F5a.3 | Sizing from live values: the REAL DMX pool on the fork; the largest single addLiquidityETH under the DMN maxTx (decision (c)) | price = DMX pool WBNB reserve x 1e18 / DMX reserve; BNB leg = net(maxTx) x price, floored to 0.001 BNB; net target = BNB x 1e18 / price; gross = ceil(net x 1000 / 960); pair receives >= net target by < 1000 wei; gross <= maxTx | DMX pool reserves DMX=76394917263158812489516157516 (76.3949 B), WBNB=35996660568812417183 (35.996660 BNB) -> DMX price=471191826 wei/token (0.000000000471191826 BNB); DMN maxTx=5.0000 B -> net 4.8000 B; BNB leg=2.261000 BNB (2261000000000000000 wei); net target=4798470336792302504840141263; gross=4998406600825315109208480483 (4.9984 B); net of gross=4798470336792302504840141265 (+2 wei) | - | PASS |
| F5a.4 | Funding preview, BEFORE the owner claims: can the owner's REAL balance fund 5b? | owner BNB >= BNB leg + 0.002 BNB gas reserve | owner=0.096153 BNB; needed=2.263000 (leg 2.261000 + reserve 0.002000); SHORT by 2.166846 BNB | - | FINDING |
| F5a.5 | Step 5a: the owner approves and claims EXACTLY the gross, on the REAL DMX | exact 1:1 on every leg: Timelock DMX +gross, owner DMX -gross, owner DMN +gross, migratedAmount == gross | Timelock DMX +4998406600825315109208480483, owner DMX -4998406600825315109208480483, owner DMN +4998406600825315109208480483, migratedAmount=4998406600825315109208480483 (gross 4998406600825315109208480483); claim gas=284476 | 0x6e476e17231f721f278c4166590764afb9c461459c46b9742ec0030dff8aea49 / 0xb9cf5ea584bc5ff0d45311e2679f900df763cd070bd1ea509e2d65fd682b227c | PASS |

### F5b (run C) -- Step 5b: initial liquidity on the REAL router at the REAL DMX price

| step | action | expected | observed | tx | verdict |
|---|---|---|---|---|---|
| F5b.0 | GATE: the owner's REAL BNB against the 5b requirement | owner BNB >= BNB leg + gas reserve, or STOP | owner=0.096136 BNB (96136855983002775 wei); leg=2.261000, reserve=0.002000, needed=2.263000; SHORTFALL=2.166863 BNB (2166863144016997225 wei) | - | STOP |

> STOPPED at 5b on the owner's real balance, as the rehearsal plan requires. On launch day the owner would now hold the claimed DMN with no pool to put it in. The owner must be funded with at least the shortfall BEFORE phase 1 (LAUNCH_DAY.md, preflight).

### F14 (run C) -- Gas and BNB: what the day actually cost (stopped at 5b: owner shortfall)

| step | action | expected | observed | tx | verdict |
|---|---|---|---|---|---|

| step | signer | call | gas used | gas price (wei) | cost (BNB) |
|---|---|---|---|---|---|
| 2 phase 1 | deployer | DeployPhase1.s.sol tx 0 | 3569417 | 50000000 | 0.000178 |
| 2 phase 1 | deployer | DeployPhase1.s.sol tx 1 | 4192820 | 50000000 | 0.000209 |
| 2 phase 1 | deployer | DeployPhase1.s.sol tx 2 | 741438 | 50000000 | 0.000037 |
| 2 phase 2 | deployer | DeployPhase2.s.sol tx 0 | 1013596 | 50000000 | 0.000050 |
| 2 phase 2 | deployer | DeployPhase2.s.sol tx 1 | 1825591 | 50000000 | 0.000091 |
| 2 phase 2 | deployer | DeployPhase2.s.sol tx 2 | 1510972 | 50000000 | 0.000075 |
| 2 phase 2 | deployer | DeployPhase2.s.sol tx 3 | 51213 | 50000000 | 0.000002 |
| 2 phase 2 | deployer | DeployPhase2.s.sol tx 4 | 51213 | 50000000 | 0.000002 |
| 2 phase 2 | deployer | DeployPhase2.s.sol tx 5 | 51213 | 50000000 | 0.000002 |
| 2 phase 2 | deployer | DeployPhase2.s.sol tx 6 | 29640 | 50000000 | 0.000001 |
| 2 phase 2 | deployer | DeployPhase2.s.sol tx 7 | 29640 | 50000000 | 0.000001 |
| 2 phase 2 | deployer | DeployPhase2.s.sol tx 8 | 47896 | 50000000 | 0.000002 |
| 2 phase 2 | deployer | DeployPhase2.s.sol tx 9 | 23984 | 50000000 | 0.000001 |
| 2 phase 2 | deployer | DeployPhase2.s.sol tx 10 | 97349 | 50000000 | 0.000004 |
| 2 phase 2 | deployer | DeployPhase2.s.sol tx 11 | 36062 | 50000000 | 0.000001 |
| 2 phase 2 | deployer | DeployPhase2.s.sol tx 12 | 46173 | 50000000 | 0.000002 |
| 2 phase 2 | deployer | DeployPhase2.s.sol tx 13 | 56384 | 50000000 | 0.000002 |
| 2 phase 2 | deployer | DeployPhase2.s.sol tx 14 | 33478 | 50000000 | 0.000001 |
| 2 phase 2 | deployer | DeployPhase2.s.sol tx 15 | 24541 | 50000000 | 0.000001 |
| 5a check | holder B | approve(address,uint256) | 46328 | 50000000 | 0.000002 |
| 5a | owner | approve(address,uint256) | 46364 | 50000000 | 0.000002 |
| 5a | owner | claim(uint256) | 284476 | 50000000 | 0.000014 |
| F14.1 | DEPLOYER: total spent, from its balance (start - end) and from the ledger | the two phases only (19 transactions); start 0.2 BNB exactly; spent == sum of gas x price | start=0.200000, end=0.199328, spent=0.000671 BNB (671631000000000 wei); ledger: 19 txs, gas 13432620, cost 0.000671; at 1 gwei the same gas would cost 0.013432, at 3 gwei 0.040297; headroom left of the 0.2 BNB plan: 0.199328 | - | PASS |
| F14.2 | DMX OWNER: total spent | spent == gas + BNB into the pool + test buy - test sell proceeds | real start=0.096153, fork top-up=0.000000, end=0.096136, spent=0.000016 BNB; of which gas=0.000016 (2 txs, gas 330840; at 1 gwei 0.000330, at 3 gwei 0.000992), liquidity=0.000000, test buy=0.000000, test sell back=0.000000 | - | PASS |
| F14.3 | Third-party holders: gas paid from their own real balances | their own claims only, never funded by the fork | holder A: 0 txs, 0.000000 BNB; holder B: 1 txs, 0.000002 BNB | - | NOTE |

Run C verdicts: PASS 12, NOTE 2, FINDING 1, STOP 1, DEVIATION 0; launch invariant asserted after 4 sends; local-fork guard passed 9 times.

## Run D

### F0 (run D) -- Real mainnet reads, then the local fork of chain 56 at block 124565863

| step | action | expected | observed | tx | verdict |
|---|---|---|---|---|---|
| F0.1 | Planned mainnet deployer, read on MAINNET | nonce 0 (never used: phase 1 must predict from nonce 0); no code | nonce=0, balance=0.000000 BNB (0 wei), code=0x | - | PASS |
| F0.2 | DMX owner, read on MAINNET | an EOA; its real BNB balance is what funds 5a-11b | balance=0.096153 BNB (96153397983002775 wei), nonce=1005, code=0x, DMX held=103.8537 B | - | PASS |
| F0.3 | The predecessor's authority and cap, read on MAINNET (checklist: 'confirm the DMX owner still has authority') | owner() == the DMX owner; _maxTxAmount == 1.5B; owner fee-exempt; not in a lock() window (getUnlockTime 0) | owner=0xF8EC459CAEaF1052b64B38BDD67290B0c132B0Ae, _maxTxAmount=1.5000 B, isExcludedFromFee(owner)=true, getUnlockTime=0 | - | PASS |
| F0.4 | ROUTER identity, from source and chain (not guessed) | developer.pancakeswap.finance/contracts/v2/addresses lists router 0x10ED43C718714eb63d5aA57B78B54704E256024E and factory 0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73 for BSC; on chain: router.factory() and router.WETH() match, DMX.uniswapV2Router() is the same router, factory.getPair(DMX, WBNB) == DMX.uniswapV2Pair() | router.factory=0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73, router.WETH=0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c, DMX.uniswapV2Router=0x10ED43C718714eb63d5aA57B78B54704E256024E, factory.getPair(DMX,WBNB)=0xB24916823C61Ee6272448209174F75fAfD297B82, DMX.uniswapV2Pair=0xB24916823C61Ee6272448209174F75fAfD297B82, INIT_CODE_PAIR_HASH=0x00fb7f630766e6a796048ea87d01acd3068e8ff67d078148a3fa3f4a84f69bd5 | - | PASS |
| F0.5 | Mainnet gas price at fork time | every fork transaction pays exactly this, so the BNB totals are the real funding numbers | eth_gasPrice=50000000 wei (0.05 gwei) | - | NOTE |
| F0.6 | Local fork up | Anvil on 127.0.0.1:8555, chain 56, forked from the upstream at the pinned block | clientVersion="anvil/v1.5.1", chainId=56, forkUrl=https://bsc-mainnet.public.blastapi.io, forkBlockNumber=124565863, local head=124565863 | - | PASS |
| F0.7 | Roles on the fork: deployer and owner impersonated (no key anywhere); deployer set to exactly 0.2 BNB (anvil_setBalance, the only balance ever set); the owner left at its real balance | deployer nonce 0, balance 0.200000 BNB; owner balance on the fork == the mainnet read | deployer nonce=0, balance=0.200000 (200000000000000000 wei); owner fork balance=0.096153 vs mainnet 0.096153 | - | PASS |
| F0.8 | Two REAL third-party DMX holders from the live holder list (BSCTrace, 2026-09-28), impersonated, their real BNB untouched; addresses in a gitignored file, never in this journal | holder A: > 10 B DMX (claims 10.00 B after 11b, 6.7x the old cap); holder B: 1.00-1.50 B (claims 1.00 B, below the cap); neither fee- nor reward-excluded on DMX; neither is a contract | A: > 10 B, EOA with an EIP-7702 delegation, feeExcluded=false, rewardExcluded=false; B: 1.00-1.50 B, plain EOA, feeExcluded=false, rewardExcluded=false | - | PASS |

### F1-F2 (run D) -- Step 1: no DMN/WBNB pair for the predicted proxy; step 2: phase 1 then phase 2 against the real router and the real DMX

| step | action | expected | observed | tx | verdict |
|---|---|---|---|---|---|
| F1.1 | Step 1 (#25): the REAL PancakeSwap factory, getPair(predicted proxy, WBNB), before phase 1 | 0x0; and no code at the predicted proxy, migration and Timelock | deployer nonce=0; predicted impl=0xA7bC2D4D35e49bdfC8329e3673d7De520832941c, proxy=0x160864F9945C52063A7c9f5dcd57C0C89eacbE6a, migration=0x76368b60514b145617385847aCFF7b7EA9764725, timelock=0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891; getPair=0x0000000000000000000000000000000000000000; code chars at the three=6 (6 = three empty '0x') | - | PASS |
| F2.1 | Phase 1 SIMULATED on chain 56 with the launch environment: ROUTER, OLD_DAIMON (real DMX), GUARDIAN_ADDRESS (real Safe); no MARKETING_WALLET, no TESTNET_TREASURY_OVERRIDE; MIGRATION_DURATION unset | exit 0; treasury AND marketing wallet logged '(= predicted timelock)'; no override or warning line | exit=0; derived lines=2; override/warning lines=0; 'Migration duration (days): 30' | - | PASS |

> MIGRATION_DURATION was left unset, so phase 1 used its default: 30 days. No document in the repository fixes the mainnet value; the deadline is immutable from phase 1. It is a launch-day input to decide before phase 1 (LAUNCH_DAY.md, inputs).
| F2.2 | Phase 1 BROADCAST (impersonated deployer, mainnet gas price) | impl/proxy/migration on the predicted nonces 0/1/2; marketingWallet, migration.treasury, migration.governance == the predicted Timelock (nonce 3); migration.oldDaimon == the REAL DMX; token router == the real router; deployer nonce == expectedPhase2Nonce; no override | 3 txs, gas 8503675, cost 0.000425 BNB; token=0x160864F9945C52063A7c9f5dcd57C0C89eacbE6a, migration=0x76368b60514b145617385847aCFF7b7EA9764725, predictedTimelock=0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891; marketingWallet=0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891, treasury=0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891, governance=0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891, oldDaimon=0x36EbA94407B53c631eE822C219e94580fadd67c7, router=0x10ED43C718714eb63d5aA57B78B54704E256024E, pair created=0x40A97Ae210a44057603186B4BE92BAe719342AFA; nonce=3 (expected 3) | journal broadcast/DeployPhase1.s.sol/56 | PASS |

Phase 1 console, completion block verbatim:

```
  Migration duration (days): 30
  === PHASE 1 complete ===
  DaimonV2 (proxy):      0x160864F9945C52063A7c9f5dcd57C0C89eacbE6a
  DaimonMigration:       0x76368b60514b145617385847aCFF7b7EA9764725
  Timelock (predicted):  0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891
  Migration treasury:    0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891 (= predicted timelock)
  Marketing wallet:      0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891 (= predicted timelock)
```
| F2.3 | Phase 2 BROADCAST right after phase 1 (deployer nonce untouched in between) | Timelock lands on the prediction; fees 10/10/20 (liquidityFee 30); share 1000; ONE guardian expiry on three contracts; governor.guardian == the real Safe | nonce before=3 (expected 3); 16 txs, gas 4928945, cost 0.000246 BNB; timelock=0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891, staking=0xBb596e7308D6C5AED55cEC597D372840Cbe575b1, governor=0x1397a7d25595B718BE6FEEDd42ed5E60F66E16De; fees=10/10/20 liq=30; share=1000; expiry token/timelock/governor=1885225030/1885225030/1885225030; governor.guardian=0x37F45839765AD3418E29c97d5D92407Ddbf5c7a8 | journal broadcast/DeployPhase2.s.sol/56 | PASS |
| F2.4 | Deployer after both phases | it signs nothing else for the rest of the day | nonce=19, balance=0.199328 BNB; phases 1+2: 19 txs, gas 13432620, cost 0.000671 BNB | - | NOTE |

### F3-F4 (run D) -- Step 3: the mandatory gate; step 4: automation inert without reserves

| step | action | expected | observed | tx | verdict |
|---|---|---|---|---|---|
| F3.1 | Step 3: script/verify-deploy.ps1 -Rpc <the local fork> | 36/36 green, exit code 0 -- MANDATORY GATE | exit=0; Post-broadcast verification -- chain 56 VERIFICATION PASSED: 36/36 checks green against live chain state. | - | PASS |

Full output of the verification, verbatim:

```
Post-broadcast verification -- chain 56
State file: C:\Users\Utente\Desktop\Daimon dao\deployments\two-phase-56.json


check                                                  expected                                   observed                                   verdict
-----                                                  --------                                   --------                                   -------
code at token                                          present                                    present                                    PASS
code at timelock                                       present                                    present                                    PASS
code at governor                                       present                                    present                                    PASS
code at staking                                        present                                    present                                    PASS
code at migration                                      present                                    present                                    PASS
token: timelock holds GOVERNANCE_ROLE                  true                                       true                                       PASS
token: deployer lacks GOVERNANCE_ROLE                  false                                      false                                      PASS
token: deployer lacks DEFAULT_ADMIN                    false                                      false                                      PASS
token: guardian holds GUARDIAN_ROLE                    true                                       true                                       PASS
token: stakingRewardShareBps == 1000                   1000                                       1000                                       PASS
token: stakingContract is the staking                  0xBb596e7308D6C5AED55cEC597D372840Cbe575b1 0xBb596e7308D6C5AED55cEC597D372840Cbe575b1 PASS
token: marketingWallet as configured                   0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891 0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891 PASS
token: migration is fee-exempt                         true                                       true                                       PASS
token: fees == (10,10,20)                              10,10,20                                   10,10,20                                   PASS
timelock: self-administers                             true                                       true                                       PASS
timelock: deployer lacks ADMIN_ROLE                    false                                      false                                      PASS
timelock: deployer lacks PROPOSER_ROLE                 false                                      false                                      PASS
timelock: deployer lacks EXECUTOR_ROLE                 false                                      false                                      PASS
timelock: governor is proposer                         true                                       true                                       PASS
timelock: governor is executor                         true                                       true                                       PASS
timelock: guardian is canceller                        true                                       true                                       PASS
timelock: governor is canceller                        true                                       true                                       PASS
timelock: self-cancel role present                     true                                       true                                       PASS
expiry: timelock == token (exact)                      1885225030                                 1885225030                                 PASS
expiry: governor == token (exact)                      1885225030                                 1885225030                                 PASS
staking: timelock is governance                        true                                       true                                       PASS
staking: deployer is not governance                    false                                      false                                      PASS
supply: totalSupply == INITIAL_SUPPLY                  1000000000000000000000000000000            1000000000000000000000000000000            PASS
supply: all of it in the migration                     1000000000000000000000000000000            1000000000000000000000000000000            PASS
migration: governance is the timelock                  0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891 0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891 PASS
migration: newDaimon is the token                      0x160864F9945C52063A7c9f5dcd57C0C89eacbE6a 0x160864F9945C52063A7c9f5dcd57C0C89eacbE6a PASS
migration: oldDaimon as configured                     0x36EbA94407B53c631eE822C219e94580fadd67c7 0x36EbA94407B53c631eE822C219e94580fadd67c7 PASS
migration: treasury as configured                      0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891 0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891 PASS
migration: treasury is the timelock                    0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891 0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891 PASS
token: marketingWallet is the deployed timelock (live) 0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891 0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891 PASS
token: pancake pair created                            present                                    present                                    PASS



Guardian expiry raw values: token=1885225030 timelock=1885225030 governor=1885225030
VERIFICATION PASSED: 36/36 checks green against live chain state.

```
| F4.1 | Step 4 (#27): automation before liquidity | enabled by initialize, inert by construction: inventory 0, reserves (0,0), contract BNB 0 | swapAndLiquifyEnabled=true, buyBackEnabled=true, inventory=0, reserves=(0,0), contract BNB=0 | - | PASS |

### F5a (run D) -- Step 5a on the REAL DMX: a non-owner is refused, the owner claims only the liquidity quota

| step | action | expected | observed | tx | verdict |
|---|---|---|---|---|---|
| F5a.1 | A REAL non-owner (holder B, below the cap, not fee-exempt) approves then claims 1.00 B, BEFORE 11b | refused with AmountMismatch (#29): the real DMX takes its 11% on the claimant -> treasury leg; nothing credited | approve mined (holder B's own gas); claim: reverted with AmountMismatch; holder B DMN=0 | 0x07647f4a4cf803214ea60948a9b4207147cf9a495be531ee4b93ac560d557255 | PASS |
| F5a.2 | Why the owner can claim now: its status on the REAL DMX | owner() == the DMX owner (cap-exempt as sender), isExcludedFromFee(owner) true; the Timelock NOT exempt (11b not done); cap 1.5B (11a not done) | owner=0xF8EC459CAEaF1052b64B38BDD67290B0c132B0Ae, isExcludedFromFee(owner)=true, isExcludedFromFee(timelock)=false, _maxTxAmount=1.5000 B | - | PASS |
| F5a.3 | Sizing from live values: the REAL DMX pool on the fork; the largest single addLiquidityETH under the DMN maxTx (decision (c)) | price = DMX pool WBNB reserve x 1e18 / DMX reserve; BNB leg = net(maxTx) x price, floored to 0.001 BNB; net target = BNB x 1e18 / price; gross = ceil(net x 1000 / 960); pair receives >= net target by < 1000 wei; gross <= maxTx | DMX pool reserves DMX=76394917263158812489516157516 (76.3949 B), WBNB=35996660568812417183 (35.996660 BNB) -> DMX price=471191826 wei/token (0.000000000471191826 BNB); DMN maxTx=5.0000 B -> net 4.8000 B; BNB leg=2.261000 BNB (2261000000000000000 wei); net target=4798470336792302504840141263; gross=4998406600825315109208480483 (4.9984 B); net of gross=4798470336792302504840141265 (+2 wei) | - | PASS |
| F5a.4 | Funding preview, BEFORE the owner claims: can the owner's REAL balance fund 5b? | owner BNB >= BNB leg + 0.002 BNB gas reserve | owner=0.096153 BNB; needed=2.263000 (leg 2.261000 + reserve 0.002000); SHORT by 2.166846 BNB | - | FINDING |
| F5a.5 | Step 5a: the owner approves and claims EXACTLY the gross, on the REAL DMX | exact 1:1 on every leg: Timelock DMX +gross, owner DMX -gross, owner DMN +gross, migratedAmount == gross | Timelock DMX +4998406600825315109208480483, owner DMX -4998406600825315109208480483, owner DMN +4998406600825315109208480483, migratedAmount=4998406600825315109208480483 (gross 4998406600825315109208480483); claim gas=284476 | 0x6e476e17231f721f278c4166590764afb9c461459c46b9742ec0030dff8aea49 / 0xb9cf5ea584bc5ff0d45311e2679f900df763cd070bd1ea509e2d65fd682b227c | PASS |

### F5b (run D) -- Step 5b: initial liquidity on the REAL router at the REAL DMX price

| step | action | expected | observed | tx | verdict |
|---|---|---|---|---|---|
| F5b.0 | GATE: the owner's REAL BNB against the 5b requirement | owner BNB >= BNB leg + gas reserve, or STOP | owner=0.096136 BNB (96136855983002775 wei); leg=2.261000, reserve=0.002000, needed=2.263000; SHORTFALL=2.166863 BNB (2166863144016997225 wei) | - | STOP |
| F5b.0b | SETUP DEVIATION, by the operator's switch -FundOwnerForLiquidity: the fork adds EXACTLY the BNB leg to the owner (anvil_setBalance); every gas cost from here is still paid out of the owner's real balance | owner = real balance + leg; the continuation measures what the owner really needs | owner 0.096136 -> 2.357136 BNB (+2.261000) | - | NOTE |
| F5b.P1 | PROBE (inside evm_snapshot, discarded): a stranger, funded 0.01 BNB by the fork for this probe only, wraps 1 wei, sends it to the EMPTY DMN pair and calls sync(); then the owner's planned addLiquidityETH is simulated | recorded: does a 1-wei donation block the router path? | reserves after sync: DMN=0 WBNB=1; addLiquidityETH: reverted with INSUFFICIENT_LIQUIDITY | 0xf248ece498cdf004721740f55c0360a5463363f5500613de66512fc19ecb2e83 | FINDING |
| F5b.P2 | PROBE, recovery path on the same griefed pair: owner transfers the gross DMN to the pair (taxed, automation idle), wraps the BNB leg, sends WBNB, calls pair.mint(owner) | the pool opens anyway: reserve DMN == net, WBNB == leg + the 1 donated wei, price within 1 ppm of the DMX price; LP minted to the owner | reserves DMN=4798470336792302504840141265 (net 4798470336792302504840141265), WBNB=2261000000000000001 (leg+1 = 2261000000000000001); price=471191826 vs DMX 471191826; LP=104160172002005622471664 | 0x187c824acc3b5b8c11c2515af83bdff8fe9a49c10b465e1411f4d995c927533d | PASS |
| F5b.P3 | PROBE discarded: evm_revert to the snapshot | pair back to (0,0); owner DMN back to the gross; the probe's transactions excluded from every total | reserves=(0,0), owner DMN=4998406600825315109208480483 | - | PASS |
| F5b.1 | Step 5b: approve + addLiquidityETH(token, gross, amountTokenMin = gross, amountETHMin = leg, owner) on the REAL router | reserve DMN == net of gross (exact), reserve WBNB == the leg (no refund); owner DMN back to 0; opening price == the DMX price within 1 ppm (never above: the net is rounded up) | BNB=2261000000000000000 wei (2.261000); DMN gross=4998406600825315109208480483 (4.9984 B); DMN received by the pair: reserve=4798470336792302504840141265, balanceOf=4798470336792302504840141265 (4.7984 B), expected 4798470336792302504840141265; reserve WBNB=2261000000000000000; OPENING PRICE=471191825 wei/token vs DMX 471191826 (diff 1 wei, 0.000000 %); owner DMN after=0; LP minted=104160172002005622471664; gas approve=50973, add=379973 | 0xe0e19e03e299d8c3bec3d1a307a79a93c6485253ce3f1cd8f013d30bd731a3e5 / 0x48e0a0f89da3356d414e48ccf06cc4badd67fbd66d385407e26b1be2c4bce255 | PASS |

### F6-F8 (run D) -- Step 6: every LP token to the Timelock; step 7: one pool; step 8: reserves non-zero

| step | action | expected | observed | tx | verdict |
|---|---|---|---|---|---|
| F6.1 | Step 6: ALL the LP tokens, owner -> Timelock | owner LP 0, deployer LP 0, Timelock LP == totalSupply - MINIMUM_LIQUIDITY (1000) | moved=104160172002005622471664; owner=0, deployer=0, timelock=104160172002005622471664, totalSupply=104160172002005622472664, MINIMUM_LIQUIDITY=1000; gas=46883 | 0x9ae42c615787987c99e5c722a31c9eb7143e2f089bd54f57cfecf7d1c7b22d6e | PASS |
| F7.1 | Step 7: one pool only; stored pair == factory pair | factory.getPair(DMN, WBNB) == token.uniswapV2Pair; no DMN/USDT or DMN/BUSD pair | stored=0x40A97Ae210a44057603186B4BE92BAe719342AFA, factory=0x40A97Ae210a44057603186B4BE92BAe719342AFA; USDT pair=0x0000000000000000000000000000000000000000, BUSD pair=0x0000000000000000000000000000000000000000 | - | PASS |
| F8.1 | Step 8: reserves non-zero -> automation live | both reserves > 0; the liquidity transfer was taxed: inventory == gross x 3% (plus at most 0.01% reflection) | DMN=4.7984 B, WBNB=2.261000; inventory=149959729762611153315200333 (0.1499 B), 3% of gross=149952198024759453276254414; threshold minimumTokensBeforeSwap=0.2000 B | - | PASS |

### F9-F10 (run D) -- Step 9: the test swap pays exactly 4%; step 10: the first poke

| step | action | expected | observed | tx | verdict |
|---|---|---|---|---|---|
| F9.1 | The owner buys with 0.001 BNB through the real router (it holds no DMN after 5b: the test sell needs a buy first) | the owner receives 96% of what left the pair (+ its own reflection share, < 0.01%) | left the pair=2116038660940306852053568 (0.0021 B); owner received=2031397157695009437060994; 96%=2031397114502694577971425 (+43192314859089569 wei); gas=241257 | 0xd7c57cdede5d216cc079506d530e6337feb79dc7a9a63de7ad9d1d2210232161 | PASS |
| F9.2 | Step 9: the owner sells half of it through the real router | the pair (balanceOf delta) receives EXACTLY 96% of the amount sent -- fee 4%, not the historical 5%; inventory grows by 3% (+ reflection); no conversion on a router sell (#1): contract BNB 0, Timelock BNB 0 | sold=1015698578847504718530497; pair received=975070635693604529789279 (96%=975070635693604529789277, 95% would be 964913649905129482603972); inventory +30472488805409470477799; BNB back to the owner=0.000458 (458608676268387 wei); contract BNB=0, Timelock BNB=0; gas=194073 | 0x9094433f41d35d2fceebccddafc1503f9328f0620de5f86e8c638ecd17973fd5 / 0xca97c7d0ee2ffaa2507821b030a38f22931dd179d6b0a782d73f5e9d874e02e1 | DEVIATION |
| F10.1 | Step 10: the first poke (1 wei DMN owner -> pair), share 1000 | zero BNB to the Timelock. Recorded: is the inventory above the threshold yet? | inventory=0.1500 B < threshold 0.2000 B: NOTHING converts (inventory after=0.1500 B); staking +0, contract +0, TIMELOCK +0 wei; the first conversion needs 0.0499 B more inventory = about 1.6648 B of further taxed volume; gas=94841 | 0x96cf06bc72953c45287e78cb64c318c554f0ff5b5f0563eeb9606392d1795d27 | FINDING |

> On launch day the first poke is a no-op: the 5b liquidity transfer arms only 3% of ~5B = ~0.15B of inventory, under the 0.2B threshold. The Timelock-receives-nothing property is proven again at the first REAL conversion, which happens later (F10.2 below, after the window opens).

### F11 (run D) -- 11a setMaxTxAmount(full supply), then 11b excludeFromFee(TIMELOCK) -- on the REAL DMX, same session, nothing between

| step | action | expected | observed | tx | verdict |
|---|---|---|---|---|---|
| F11.0 | BEFORE 11a: holder A (real, > 10 B) approves and claims 10.00 B | REVERTS with the real DMX cap message (the cap is checked before any fee logic) | approve mined (holder A's own gas); claim: reverted with Transfer amount exceeds the maxTxAmount. | 0xd3e896cdcb81f0dcff96cd0bf60c4c90bf86f2447571e3a5cf2a9e3fd2af89cc | PASS |
| F11a | Step 11a: setMaxTxAmount(1000000000000 x 1e18) -- a non-owner first (eth_call), then the owner | non-owner refused by Ownable; the owner's call mined; _maxTxAmount == the full supply == totalSupply() | non-owner: reverted with Ownable: caller is not the owner; _maxTxAmount 1.5000 B -> 1000.0000 B (totalSupply 1000.0000 B); logs emitted by the call=0; gas=28742; block 124565894 | 0x376244f1921fcd484b134f411a316cf41f7f30935e4f1a5ca585c36292c0c6c0 | PASS |
| F11b | Step 11b, LAST: excludeFromFee(TIMELOCK) -- the treasury, not the Migration; the window opens | isExcludedFromFee(timelock) true, (migration) false; mined right after 11a with nothing in between | timelock=true, migration=false; logs emitted=0; 11a block 124565894 -> 11b block 124565895; gas=46232 | 0x97ab6f75da75bf776158b0bee8b65213fc82a6445483b61002086e9d55951b75 | PASS |
| F11.x | Events: what an observer sees of 11a and 11b | recorded against the mock (CampaignOldDaimon emits MaxTxAmountUpdated on setMaxTxAmount) | the REAL DMX emitted 0 log(s) on setMaxTxAmount and 0 on excludeFromFee: both are silent -- only the calldata and a storage read show them | - | FINDING |

### F12 (run D) -- After 11b: real third-party holders claim through the open window

| step | action | expected | observed | tx | verdict |
|---|---|---|---|---|---|
| F12.1 | Holder A (real, > 10 B, not the owner, not exempt) repeats the SAME 10.00 B claim (the F11.0 approve still stands) | passes 1:1, no fee: Timelock DMX +10.00 B exactly, holder A DMX -10.00 B exactly, holder A DMN +10.00 B exactly, migratedAmount 10.00 B | Timelock DMX +10000000000000000000000000000, holder A DMX -10000000000000000000000000000, holder A DMN +10000000000000000000000000000, migratedAmount=10000000000000000000000000000 (10.00 B = 10000000000000000000000000000); gas=249104 | 0x8f32e20ce80cd8181c7151de41e0e8d8c881fa51dca4f74a113cde62f2418606 | PASS |
| F12.2 | Holder B (real, below the old cap) claims 1.00 B with the approve of F5a.1 | exact 1:1 on every leg | Timelock DMX +1000000000000000000000000000, holder B DMX -1000000000000000000000000000, holder B DMN +1000000000000000000000000000; gas=249104 | 0x271b79d402a24893793c14fbdf7f7c74285ce9fc2b672454de47cd3e8af12573 | PASS |
| F12.3 | The treasury (= the Timelock) after the day's claims | DMX held == totalMigrated (owner 5a + holder A + holder B) | Timelock DMX=15998406600825315109208480483 (15.9984 B); totalMigrated=15998406600825315109208480483 (15.9984 B); owner 4.9984 B + A 10.0000 B + B 1.0000 B | - | PASS |
| F12.4 | Behaviour the mock does not have: a taxed DMX transfer between two other holders (holder A -> holder B, 0.01 B) after the claims | recorded: does the treasury's DMX move without any claim? | Timelock isExcludedFromReward on DMX=false; Timelock DMX 15998406600825315109208480483 -> 15998413000190515185414554648 (+6399365200076206074165 wei) while totalMigrated stays 15998406600825315109208480483 | 0x8b13a31b93ebb51eafece354f173a6754f392a1dcb408610e9441c4ce76dc36e | FINDING |
| F10.2a | Arming the first conversion with ordinary volume: holder A sends DMN to holder B (a taxed transfer, under the 5B maxTx) | inventory >= threshold afterwards | sent=1.6700 B; inventory=0.2001 B vs threshold 0.2000 B | 0xe081fa1fa9906996316c358886af53d2ce3189c5fdab8f3832fc2e237b949d27 | PASS |
| F10.2 | The first REAL conversion on the REAL router: holder B pokes (1 wei to the pair), share 1000 | one threshold chunk sold; 20/30 of the BNB to staking, 10/30 kept for buyback, ZERO to the Timelock | consumed=0.2000 B (threshold 0.2000 B); received=0.090292 BNB: staking +0.060195 (exp 0.060195), contract +0.030097, TIMELOCK +0 wei; gas=306963 | 0x28b83e97c21b740009c46e63f16431a9868ee5142abc53d9e38703b75717bc0d | PASS |
| F10.3 | THE NUMBER on the real pool: the chunk against the DMN reserve, and the price move | recorded | chunk 0.2000 B vs DMN reserve 4.7973 B = 4.16 %; BNB drawn 0.090292 of 2.261541 = 3.99 %; price 471416744 -> 434481794 wei/token, move -7.83 % | - | NOTE |
| F13.1 | The Timelock at the end of the day | BNB 0 and DMN 0 (share 1000: nothing from the token), every LP token, the claimed DMX | BNB=0, DMN=0, LP=104160172002005622471664 of 104160172002005622472664, DMX=15.9984 B | - | PASS |

### Gas ledger (run D) -- every mined transaction of the day, probes excluded

| step | signer | call | gas used | gas price (wei) | cost (BNB) |
|---|---|---|---|---|---|
| 2 phase 1 | deployer | DeployPhase1.s.sol tx 0 | 3569417 | 50000000 | 0.000178 |
| 2 phase 1 | deployer | DeployPhase1.s.sol tx 1 | 4192820 | 50000000 | 0.000209 |
| 2 phase 1 | deployer | DeployPhase1.s.sol tx 2 | 741438 | 50000000 | 0.000037 |
| 2 phase 2 | deployer | DeployPhase2.s.sol tx 0 | 1013596 | 50000000 | 0.000050 |
| 2 phase 2 | deployer | DeployPhase2.s.sol tx 1 | 1825591 | 50000000 | 0.000091 |
| 2 phase 2 | deployer | DeployPhase2.s.sol tx 2 | 1510972 | 50000000 | 0.000075 |
| 2 phase 2 | deployer | DeployPhase2.s.sol tx 3 | 51213 | 50000000 | 0.000002 |
| 2 phase 2 | deployer | DeployPhase2.s.sol tx 4 | 51213 | 50000000 | 0.000002 |
| 2 phase 2 | deployer | DeployPhase2.s.sol tx 5 | 51213 | 50000000 | 0.000002 |
| 2 phase 2 | deployer | DeployPhase2.s.sol tx 6 | 29640 | 50000000 | 0.000001 |
| 2 phase 2 | deployer | DeployPhase2.s.sol tx 7 | 29640 | 50000000 | 0.000001 |
| 2 phase 2 | deployer | DeployPhase2.s.sol tx 8 | 47896 | 50000000 | 0.000002 |
| 2 phase 2 | deployer | DeployPhase2.s.sol tx 9 | 23984 | 50000000 | 0.000001 |
| 2 phase 2 | deployer | DeployPhase2.s.sol tx 10 | 97349 | 50000000 | 0.000004 |
| 2 phase 2 | deployer | DeployPhase2.s.sol tx 11 | 36062 | 50000000 | 0.000001 |
| 2 phase 2 | deployer | DeployPhase2.s.sol tx 12 | 46173 | 50000000 | 0.000002 |
| 2 phase 2 | deployer | DeployPhase2.s.sol tx 13 | 56384 | 50000000 | 0.000002 |
| 2 phase 2 | deployer | DeployPhase2.s.sol tx 14 | 33478 | 50000000 | 0.000001 |
| 2 phase 2 | deployer | DeployPhase2.s.sol tx 15 | 24541 | 50000000 | 0.000001 |
| 5a check | holder B | approve(address,uint256) | 46328 | 50000000 | 0.000002 |
| 5a | owner | approve(address,uint256) | 46364 | 50000000 | 0.000002 |
| 5a | owner | claim(uint256) | 284476 | 50000000 | 0.000014 |
| 5b | owner | approve(address,uint256) | 50973 | 50000000 | 0.000002 |
| 5b | owner | addLiquidityETH(address,uint256,uint256,uint256,address,uint256) | 379973 | 50000000 | 0.000018 |
| 6 | owner | transfer(address,uint256) | 46883 | 50000000 | 0.000002 |
| 9 buy | owner | swapExactETHForTokensSupportingFeeOnTransferTokens(uint256,address[],address,uint256) | 241257 | 50000000 | 0.000012 |
| 9 sell | owner | approve(address,uint256) | 50949 | 50000000 | 0.000002 |
| 9 sell | owner | swapExactTokensForETHSupportingFeeOnTransferTokens(uint256,uint256,address[],address,uint256) | 194073 | 50000000 | 0.000009 |
| 10 poke | owner | transfer(address,uint256) | 94841 | 50000000 | 0.000004 |
| 11 check | holder A | approve(address,uint256) | 46328 | 50000000 | 0.000002 |
| 11a | owner | setMaxTxAmount(uint256) | 28742 | 50000000 | 0.000001 |
| 11b | owner | excludeFromFee(address) | 46232 | 50000000 | 0.000002 |
| 12 claim A | holder A | claim(uint256) | 249104 | 50000000 | 0.000012 |
| 12 claim B | holder B | claim(uint256) | 249104 | 50000000 | 0.000012 |
| 12 reflection | holder A | transfer(address,uint256) | 87154 | 50000000 | 0.000004 |
| 10 again arm | holder A | transfer(address,uint256) | 109100 | 50000000 | 0.000005 |
| 10 again poke | holder B | transfer(address,uint256) | 306963 | 50000000 | 0.000015 |

### F14 (run D) -- Gas and BNB: what the day actually cost (complete through 11b and the post-window claims)

| step | action | expected | observed | tx | verdict |
|---|---|---|---|---|---|
| F14.1 | DEPLOYER: total spent, from its balance (start - end) and from the ledger | the two phases only (19 transactions); start 0.2 BNB exactly; spent == sum of gas x price | start=0.200000, end=0.199328, spent=0.000671 BNB (671631000000000 wei); ledger: 19 txs, gas 13432620, cost 0.000671; at 1 gwei the same gas would cost 0.013432, at 3 gwei 0.040297; headroom left of the 0.2 BNB plan: 0.199328 | - | PASS |
| F14.2 | DMX OWNER: total spent | spent == gas + BNB into the pool + test buy - test sell proceeds | real start=0.096153, fork top-up=2.261000, end=0.095538, spent=2.261614 BNB; of which gas=0.000073 (11 txs, gas 1464763; at 1 gwei 0.001464, at 3 gwei 0.004394), liquidity=2.261000, test buy=0.001000, test sell back=0.000458 | - | PASS |
| F14.3 | Third-party holders: gas paid from their own real balances | their own claims only, never funded by the fork | holder A: 4 txs, 0.000024 BNB; holder B: 3 txs, 0.000030 BNB | - | NOTE |

Run D verdicts: PASS 28, NOTE 4, FINDING 5, STOP 1, DEVIATION 1; launch invariant asserted after 27 sends; local-fork guard passed 35 times.

> Annotation to F9.2 (harness-side DEVIATION, not a launch finding): the pair received 975070635693604529789279, which is EXACTLY the token's net of the amount sold -- amount - floor(1%) - floor(3%) = 1015698578847504718530497 - 10156985788475047185304 - 30470957365425141555914 -- while the assert compared against floor(96%) = ...277. Two floor divisions leave up to 2 wei more than one; Chapel's H1.19 sold a round 0.05 B, where the two coincide. Fee 4% confirmed on the real router (95% would have been 964913649905129482603972). The runner now asserts the exact net (NetOfGross), as 5b already did; run E below is the clean re-run.

## Run E

### F0 (run E) -- Real mainnet reads, then the local fork of chain 56 at block 124566248

| step | action | expected | observed | tx | verdict |
|---|---|---|---|---|---|
| F0.1 | Planned mainnet deployer, read on MAINNET | nonce 0 (never used: phase 1 must predict from nonce 0); no code | nonce=0, balance=0.000000 BNB (0 wei), code=0x | - | PASS |
| F0.2 | DMX owner, read on MAINNET | an EOA; its real BNB balance is what funds 5a-11b | balance=0.096153 BNB (96153397983002775 wei), nonce=1005, code=0x, DMX held=103.8537 B | - | PASS |
| F0.3 | The predecessor's authority and cap, read on MAINNET (checklist: 'confirm the DMX owner still has authority') | owner() == the DMX owner; _maxTxAmount == 1.5B; owner fee-exempt; not in a lock() window (getUnlockTime 0) | owner=0xF8EC459CAEaF1052b64B38BDD67290B0c132B0Ae, _maxTxAmount=1.5000 B, isExcludedFromFee(owner)=true, getUnlockTime=0 | - | PASS |
| F0.4 | ROUTER identity, from source and chain (not guessed) | developer.pancakeswap.finance/contracts/v2/addresses lists router 0x10ED43C718714eb63d5aA57B78B54704E256024E and factory 0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73 for BSC; on chain: router.factory() and router.WETH() match, DMX.uniswapV2Router() is the same router, factory.getPair(DMX, WBNB) == DMX.uniswapV2Pair() | router.factory=0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73, router.WETH=0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c, DMX.uniswapV2Router=0x10ED43C718714eb63d5aA57B78B54704E256024E, factory.getPair(DMX,WBNB)=0xB24916823C61Ee6272448209174F75fAfD297B82, DMX.uniswapV2Pair=0xB24916823C61Ee6272448209174F75fAfD297B82, INIT_CODE_PAIR_HASH=0x00fb7f630766e6a796048ea87d01acd3068e8ff67d078148a3fa3f4a84f69bd5 | - | PASS |
| F0.5 | Mainnet gas price at fork time | every fork transaction pays exactly this, so the BNB totals are the real funding numbers | eth_gasPrice=50000000 wei (0.05 gwei) | - | NOTE |
| F0.6 | Local fork up | Anvil on 127.0.0.1:8555, chain 56, forked from the upstream at the pinned block | clientVersion="anvil/v1.5.1", chainId=56, forkUrl=https://bsc-mainnet.public.blastapi.io, forkBlockNumber=124566248, local head=124566248 | - | PASS |
| F0.7 | Roles on the fork: deployer and owner impersonated (no key anywhere); deployer set to exactly 0.2 BNB (anvil_setBalance, the only balance ever set); the owner left at its real balance | deployer nonce 0, balance 0.200000 BNB; owner balance on the fork == the mainnet read | deployer nonce=0, balance=0.200000 (200000000000000000 wei); owner fork balance=0.096153 vs mainnet 0.096153 | - | PASS |
| F0.8 | Two REAL third-party DMX holders from the live holder list (BSCTrace, 2026-09-28), impersonated, their real BNB untouched; addresses in a gitignored file, never in this journal | holder A: > 10 B DMX (claims 10.00 B after 11b, 6.7x the old cap); holder B: 1.00-1.50 B (claims 1.00 B, below the cap); neither fee- nor reward-excluded on DMX; neither is a contract | A: > 10 B, EOA with an EIP-7702 delegation, feeExcluded=false, rewardExcluded=false; B: 1.00-1.50 B, plain EOA, feeExcluded=false, rewardExcluded=false | - | PASS |

### F1-F2 (run E) -- Step 1: no DMN/WBNB pair for the predicted proxy; step 2: phase 1 then phase 2 against the real router and the real DMX

| step | action | expected | observed | tx | verdict |
|---|---|---|---|---|---|
| F1.1 | Step 1 (#25): the REAL PancakeSwap factory, getPair(predicted proxy, WBNB), before phase 1 | 0x0; and no code at the predicted proxy, migration and Timelock | deployer nonce=0; predicted impl=0xA7bC2D4D35e49bdfC8329e3673d7De520832941c, proxy=0x160864F9945C52063A7c9f5dcd57C0C89eacbE6a, migration=0x76368b60514b145617385847aCFF7b7EA9764725, timelock=0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891; getPair=0x0000000000000000000000000000000000000000; code chars at the three=6 (6 = three empty '0x') | - | PASS |
| F2.1 | Phase 1 SIMULATED on chain 56 with the launch environment: ROUTER, OLD_DAIMON (real DMX), GUARDIAN_ADDRESS (real Safe); no MARKETING_WALLET, no TESTNET_TREASURY_OVERRIDE; MIGRATION_DURATION unset | exit 0; treasury AND marketing wallet logged '(= predicted timelock)'; no override or warning line | exit=0; derived lines=2; override/warning lines=0; 'Migration duration (days): 30' | - | PASS |

> MIGRATION_DURATION was left unset, so phase 1 used its default: 30 days. No document in the repository fixes the mainnet value; the deadline is immutable from phase 1. It is a launch-day input to decide before phase 1 (LAUNCH_DAY.md, inputs).
| F2.2 | Phase 1 BROADCAST (impersonated deployer, mainnet gas price) | impl/proxy/migration on the predicted nonces 0/1/2; marketingWallet, migration.treasury, migration.governance == the predicted Timelock (nonce 3); migration.oldDaimon == the REAL DMX; token router == the real router; deployer nonce == expectedPhase2Nonce; no override | 3 txs, gas 8503675, cost 0.000425 BNB; token=0x160864F9945C52063A7c9f5dcd57C0C89eacbE6a, migration=0x76368b60514b145617385847aCFF7b7EA9764725, predictedTimelock=0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891; marketingWallet=0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891, treasury=0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891, governance=0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891, oldDaimon=0x36EbA94407B53c631eE822C219e94580fadd67c7, router=0x10ED43C718714eb63d5aA57B78B54704E256024E, pair created=0x40A97Ae210a44057603186B4BE92BAe719342AFA; nonce=3 (expected 3) | journal broadcast/DeployPhase1.s.sol/56 | PASS |

Phase 1 console, completion block verbatim:

```
  Migration duration (days): 30
  === PHASE 1 complete ===
  DaimonV2 (proxy):      0x160864F9945C52063A7c9f5dcd57C0C89eacbE6a
  DaimonMigration:       0x76368b60514b145617385847aCFF7b7EA9764725
  Timelock (predicted):  0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891
  Migration treasury:    0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891 (= predicted timelock)
  Marketing wallet:      0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891 (= predicted timelock)
```
| F2.3 | Phase 2 BROADCAST right after phase 1 (deployer nonce untouched in between) | Timelock lands on the prediction; fees 10/10/20 (liquidityFee 30); share 1000; ONE guardian expiry on three contracts; governor.guardian == the real Safe | nonce before=3 (expected 3); 16 txs, gas 4928945, cost 0.000246 BNB; timelock=0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891, staking=0xBb596e7308D6C5AED55cEC597D372840Cbe575b1, governor=0x1397a7d25595B718BE6FEEDd42ed5E60F66E16De; fees=10/10/20 liq=30; share=1000; expiry token/timelock/governor=1885225198/1885225198/1885225198; governor.guardian=0x37F45839765AD3418E29c97d5D92407Ddbf5c7a8 | journal broadcast/DeployPhase2.s.sol/56 | PASS |
| F2.4 | Deployer after both phases | it signs nothing else for the rest of the day | nonce=19, balance=0.199328 BNB; phases 1+2: 19 txs, gas 13432620, cost 0.000671 BNB | - | NOTE |

### F3-F4 (run E) -- Step 3: the mandatory gate; step 4: automation inert without reserves

| step | action | expected | observed | tx | verdict |
|---|---|---|---|---|---|
| F3.1 | Step 3: script/verify-deploy.ps1 -Rpc <the local fork> | 36/36 green, exit code 0 -- MANDATORY GATE | exit=0; Post-broadcast verification -- chain 56 VERIFICATION PASSED: 36/36 checks green against live chain state. | - | PASS |

Full output of the verification, verbatim:

```
Post-broadcast verification -- chain 56
State file: C:\Users\Utente\Desktop\Daimon dao\deployments\two-phase-56.json


check                                                  expected                                   observed                                   verdict
-----                                                  --------                                   --------                                   -------
code at token                                          present                                    present                                    PASS
code at timelock                                       present                                    present                                    PASS
code at governor                                       present                                    present                                    PASS
code at staking                                        present                                    present                                    PASS
code at migration                                      present                                    present                                    PASS
token: timelock holds GOVERNANCE_ROLE                  true                                       true                                       PASS
token: deployer lacks GOVERNANCE_ROLE                  false                                      false                                      PASS
token: deployer lacks DEFAULT_ADMIN                    false                                      false                                      PASS
token: guardian holds GUARDIAN_ROLE                    true                                       true                                       PASS
token: stakingRewardShareBps == 1000                   1000                                       1000                                       PASS
token: stakingContract is the staking                  0xBb596e7308D6C5AED55cEC597D372840Cbe575b1 0xBb596e7308D6C5AED55cEC597D372840Cbe575b1 PASS
token: marketingWallet as configured                   0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891 0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891 PASS
token: migration is fee-exempt                         true                                       true                                       PASS
token: fees == (10,10,20)                              10,10,20                                   10,10,20                                   PASS
timelock: self-administers                             true                                       true                                       PASS
timelock: deployer lacks ADMIN_ROLE                    false                                      false                                      PASS
timelock: deployer lacks PROPOSER_ROLE                 false                                      false                                      PASS
timelock: deployer lacks EXECUTOR_ROLE                 false                                      false                                      PASS
timelock: governor is proposer                         true                                       true                                       PASS
timelock: governor is executor                         true                                       true                                       PASS
timelock: guardian is canceller                        true                                       true                                       PASS
timelock: governor is canceller                        true                                       true                                       PASS
timelock: self-cancel role present                     true                                       true                                       PASS
expiry: timelock == token (exact)                      1885225198                                 1885225198                                 PASS
expiry: governor == token (exact)                      1885225198                                 1885225198                                 PASS
staking: timelock is governance                        true                                       true                                       PASS
staking: deployer is not governance                    false                                      false                                      PASS
supply: totalSupply == INITIAL_SUPPLY                  1000000000000000000000000000000            1000000000000000000000000000000            PASS
supply: all of it in the migration                     1000000000000000000000000000000            1000000000000000000000000000000            PASS
migration: governance is the timelock                  0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891 0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891 PASS
migration: newDaimon is the token                      0x160864F9945C52063A7c9f5dcd57C0C89eacbE6a 0x160864F9945C52063A7c9f5dcd57C0C89eacbE6a PASS
migration: oldDaimon as configured                     0x36EbA94407B53c631eE822C219e94580fadd67c7 0x36EbA94407B53c631eE822C219e94580fadd67c7 PASS
migration: treasury as configured                      0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891 0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891 PASS
migration: treasury is the timelock                    0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891 0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891 PASS
token: marketingWallet is the deployed timelock (live) 0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891 0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891 PASS
token: pancake pair created                            present                                    present                                    PASS



Guardian expiry raw values: token=1885225198 timelock=1885225198 governor=1885225198
VERIFICATION PASSED: 36/36 checks green against live chain state.

```
| F4.1 | Step 4 (#27): automation before liquidity | enabled by initialize, inert by construction: inventory 0, reserves (0,0), contract BNB 0 | swapAndLiquifyEnabled=true, buyBackEnabled=true, inventory=0, reserves=(0,0), contract BNB=0 | - | PASS |

### F5a (run E) -- Step 5a on the REAL DMX: a non-owner is refused, the owner claims only the liquidity quota

| step | action | expected | observed | tx | verdict |
|---|---|---|---|---|---|
| F5a.1 | A REAL non-owner (holder B, below the cap, not fee-exempt) approves then claims 1.00 B, BEFORE 11b | refused with AmountMismatch (#29): the real DMX takes its 11% on the claimant -> treasury leg; nothing credited | approve mined (holder B's own gas); claim: reverted with AmountMismatch; holder B DMN=0 | 0x07647f4a4cf803214ea60948a9b4207147cf9a495be531ee4b93ac560d557255 | PASS |
| F5a.2 | Why the owner can claim now: its status on the REAL DMX | owner() == the DMX owner (cap-exempt as sender), isExcludedFromFee(owner) true; the Timelock NOT exempt (11b not done); cap 1.5B (11a not done) | owner=0xF8EC459CAEaF1052b64B38BDD67290B0c132B0Ae, isExcludedFromFee(owner)=true, isExcludedFromFee(timelock)=false, _maxTxAmount=1.5000 B | - | PASS |
| F5a.3 | Sizing from live values: the REAL DMX pool on the fork; the largest single addLiquidityETH under the DMN maxTx (decision (c)) | price = DMX pool WBNB reserve x 1e18 / DMX reserve; BNB leg = net(maxTx) x price, floored to 0.001 BNB; net target = BNB x 1e18 / price; gross = ceil(net x 1000 / 960); pair receives >= net target by < 1000 wei; gross <= maxTx | DMX pool reserves DMX=76394917263158812489516157516 (76.3949 B), WBNB=35996660568812417183 (35.996660 BNB) -> DMX price=471191826 wei/token (0.000000000471191826 BNB); DMN maxTx=5.0000 B -> net 4.8000 B; BNB leg=2.261000 BNB (2261000000000000000 wei); net target=4798470336792302504840141263; gross=4998406600825315109208480483 (4.9984 B); net of gross=4798470336792302504840141265 (+2 wei) | - | PASS |
| F5a.4 | Funding preview, BEFORE the owner claims: can the owner's REAL balance fund 5b? | owner BNB >= BNB leg + 0.002 BNB gas reserve | owner=0.096153 BNB; needed=2.263000 (leg 2.261000 + reserve 0.002000); SHORT by 2.166846 BNB | - | FINDING |
| F5a.5 | Step 5a: the owner approves and claims EXACTLY the gross, on the REAL DMX | exact 1:1 on every leg: Timelock DMX +gross, owner DMX -gross, owner DMN +gross, migratedAmount == gross | Timelock DMX +4998406600825315109208480483, owner DMX -4998406600825315109208480483, owner DMN +4998406600825315109208480483, migratedAmount=4998406600825315109208480483 (gross 4998406600825315109208480483); claim gas=284476 | 0x6e476e17231f721f278c4166590764afb9c461459c46b9742ec0030dff8aea49 / 0xb9cf5ea584bc5ff0d45311e2679f900df763cd070bd1ea509e2d65fd682b227c | PASS |

### F5b (run E) -- Step 5b: initial liquidity on the REAL router at the REAL DMX price

| step | action | expected | observed | tx | verdict |
|---|---|---|---|---|---|
| F5b.0 | GATE: the owner's REAL BNB against the 5b requirement | owner BNB >= BNB leg + gas reserve, or STOP | owner=0.096136 BNB (96136855983002775 wei); leg=2.261000, reserve=0.002000, needed=2.263000; SHORTFALL=2.166863 BNB (2166863144016997225 wei) | - | STOP |
| F5b.0b | SETUP DEVIATION, by the operator's switch -FundOwnerForLiquidity: the fork adds EXACTLY the BNB leg to the owner (anvil_setBalance); every gas cost from here is still paid out of the owner's real balance | owner = real balance + leg; the continuation measures what the owner really needs | owner 0.096136 -> 2.357136 BNB (+2.261000) | - | NOTE |
| F5b.P1 | PROBE (inside evm_snapshot, discarded): a stranger, funded 0.01 BNB by the fork for this probe only, wraps 1 wei, sends it to the EMPTY DMN pair and calls sync(); then the owner's planned addLiquidityETH is simulated | recorded: does a 1-wei donation block the router path? | reserves after sync: DMN=0 WBNB=1; addLiquidityETH: reverted with INSUFFICIENT_LIQUIDITY | 0xf248ece498cdf004721740f55c0360a5463363f5500613de66512fc19ecb2e83 | FINDING |
| F5b.P2 | PROBE, recovery path on the same griefed pair: owner transfers the gross DMN to the pair (taxed, automation idle), wraps the BNB leg, sends WBNB, calls pair.mint(owner) | the pool opens anyway: reserve DMN == net, WBNB == leg + the 1 donated wei, price within 1 ppm of the DMX price; LP minted to the owner | reserves DMN=4798470336792302504840141265 (net 4798470336792302504840141265), WBNB=2261000000000000001 (leg+1 = 2261000000000000001); price=471191826 vs DMX 471191826; LP=104160172002005622471664 | 0x187c824acc3b5b8c11c2515af83bdff8fe9a49c10b465e1411f4d995c927533d | PASS |
| F5b.P3 | PROBE discarded: evm_revert to the snapshot | pair back to (0,0); owner DMN back to the gross; the probe's transactions excluded from every total | reserves=(0,0), owner DMN=4998406600825315109208480483 | - | PASS |
| F5b.1 | Step 5b: approve + addLiquidityETH(token, gross, amountTokenMin = gross, amountETHMin = leg, owner) on the REAL router | reserve DMN == net of gross (exact), reserve WBNB == the leg (no refund); owner DMN back to 0; opening price == the DMX price within 1 ppm (never above: the net is rounded up) | BNB=2261000000000000000 wei (2.261000); DMN gross=4998406600825315109208480483 (4.9984 B); DMN received by the pair: reserve=4798470336792302504840141265, balanceOf=4798470336792302504840141265 (4.7984 B), expected 4798470336792302504840141265; reserve WBNB=2261000000000000000; OPENING PRICE=471191825 wei/token vs DMX 471191826 (diff 1 wei, 0.000000 %); owner DMN after=0; LP minted=104160172002005622471664; gas approve=50973, add=379973 | 0xe0e19e03e299d8c3bec3d1a307a79a93c6485253ce3f1cd8f013d30bd731a3e5 / 0xf4237c506534a37fd88199aa0508aae4eb44d202ebf4a6f5c6f58e02518265d1 | PASS |

### F6-F8 (run E) -- Step 6: every LP token to the Timelock; step 7: one pool; step 8: reserves non-zero

| step | action | expected | observed | tx | verdict |
|---|---|---|---|---|---|
| F6.1 | Step 6: ALL the LP tokens, owner -> Timelock | owner LP 0, deployer LP 0, Timelock LP == totalSupply - MINIMUM_LIQUIDITY (1000) | moved=104160172002005622471664; owner=0, deployer=0, timelock=104160172002005622471664, totalSupply=104160172002005622472664, MINIMUM_LIQUIDITY=1000; gas=46883 | 0x9ae42c615787987c99e5c722a31c9eb7143e2f089bd54f57cfecf7d1c7b22d6e | PASS |
| F7.1 | Step 7: one pool only; stored pair == factory pair | factory.getPair(DMN, WBNB) == token.uniswapV2Pair; no DMN/USDT or DMN/BUSD pair | stored=0x40A97Ae210a44057603186B4BE92BAe719342AFA, factory=0x40A97Ae210a44057603186B4BE92BAe719342AFA; USDT pair=0x0000000000000000000000000000000000000000, BUSD pair=0x0000000000000000000000000000000000000000 | - | PASS |
| F8.1 | Step 8: reserves non-zero -> automation live | both reserves > 0; the liquidity transfer was taxed: inventory == gross x 3% (plus at most 0.01% reflection) | DMN=4.7984 B, WBNB=2.261000; inventory=149959729762611153315200333 (0.1499 B), 3% of gross=149952198024759453276254414; threshold minimumTokensBeforeSwap=0.2000 B | - | PASS |

### F9-F10 (run E) -- Step 9: the test swap pays exactly 4%; step 10: the first poke

| step | action | expected | observed | tx | verdict |
|---|---|---|---|---|---|
| F9.1 | The owner buys with 0.001 BNB through the real router (it holds no DMN after 5b: the test sell needs a buy first) | the owner receives the net of what left the pair -- amount - floor(1%) - floor(3%) -- plus its own reflection share (< 0.01%) | left the pair=2116038660940306852053568 (0.0021 B); owner received=2031397157695009437060994; net (96%, floors per fee)=2031397114502694577971426 (+43192314859089568 wei); gas=241257 | 0x076af78f94f5c08682535e0ddc4650f54fdf3b2af6f933eb06e28f36f3e39cc5 | PASS |
| F9.2 | Step 9: the owner sells half of it through the real router | the pair (balanceOf delta, reward-excluded) receives EXACTLY the net: amount - floor(1%) - floor(3%), i.e. 96% up to the two floors -- fee 4%, not the historical 5%; inventory grows by 3% (+ reflection); no conversion on a router sell (#1): contract BNB 0, Timelock BNB 0 | sold=1015698578847504718530497; pair received=975070635693604529789279 (net=975070635693604529789279, floor(96%)=975070635693604529789277, 95% would be 964913649905129482603972); inventory +30472488805409470477799; BNB back to the owner=0.000458 (458608676268387 wei); contract BNB=0, Timelock BNB=0; gas=194073 | 0x9094433f41d35d2fceebccddafc1503f9328f0620de5f86e8c638ecd17973fd5 / 0x8ec4aa70d4169ed10061c48085cefd52c57d04ac5dcfea509b4d45ed7470e150 | PASS |
| F10.1 | Step 10: the first poke (1 wei DMN owner -> pair), share 1000 | zero BNB to the Timelock. Recorded: is the inventory above the threshold yet? | inventory=0.1500 B < threshold 0.2000 B: NOTHING converts (inventory after=0.1500 B); staking +0, contract +0, TIMELOCK +0 wei; the first conversion needs 0.0499 B more inventory = about 1.6648 B of further taxed volume; gas=94841 | 0x96cf06bc72953c45287e78cb64c318c554f0ff5b5f0563eeb9606392d1795d27 | FINDING |

> On launch day the first poke is a no-op: the 5b liquidity transfer arms only 3% of ~5B = ~0.15B of inventory, under the 0.2B threshold. The Timelock-receives-nothing property is proven again at the first REAL conversion, which happens later (F10.2 below, after the window opens).

### F11 (run E) -- 11a setMaxTxAmount(full supply), then 11b excludeFromFee(TIMELOCK) -- on the REAL DMX, same session, nothing between

| step | action | expected | observed | tx | verdict |
|---|---|---|---|---|---|
| F11.0 | BEFORE 11a: holder A (real, > 10 B) approves and claims 10.00 B | REVERTS with the real DMX cap message (the cap is checked before any fee logic) | approve mined (holder A's own gas); claim: reverted with Transfer amount exceeds the maxTxAmount. | 0xd3e896cdcb81f0dcff96cd0bf60c4c90bf86f2447571e3a5cf2a9e3fd2af89cc | PASS |
| F11a | Step 11a: setMaxTxAmount(1000000000000 x 1e18) -- a non-owner first (eth_call), then the owner | non-owner refused by Ownable; the owner's call mined; _maxTxAmount == the full supply == totalSupply() | non-owner: reverted with Ownable: caller is not the owner; _maxTxAmount 1.5000 B -> 1000.0000 B (totalSupply 1000.0000 B); logs emitted by the call=0; gas=28742; block 124566279 | 0x376244f1921fcd484b134f411a316cf41f7f30935e4f1a5ca585c36292c0c6c0 | PASS |
| F11b | Step 11b, LAST: excludeFromFee(TIMELOCK) -- the treasury, not the Migration; the window opens | isExcludedFromFee(timelock) true, (migration) false; mined right after 11a with nothing in between | timelock=true, migration=false; logs emitted=0; 11a block 124566279 -> 11b block 124566280; gas=46232 | 0x97ab6f75da75bf776158b0bee8b65213fc82a6445483b61002086e9d55951b75 | PASS |
| F11.x | Events: what an observer sees of 11a and 11b | recorded against the mock (CampaignOldDaimon emits MaxTxAmountUpdated on setMaxTxAmount) | the REAL DMX emitted 0 log(s) on setMaxTxAmount and 0 on excludeFromFee: both are silent -- only the calldata and a storage read show them | - | FINDING |

### F12 (run E) -- After 11b: real third-party holders claim through the open window

| step | action | expected | observed | tx | verdict |
|---|---|---|---|---|---|
| F12.1 | Holder A (real, > 10 B, not the owner, not exempt) repeats the SAME 10.00 B claim (the F11.0 approve still stands) | passes 1:1, no fee: Timelock DMX +10.00 B exactly, holder A DMX -10.00 B exactly, holder A DMN +10.00 B exactly, migratedAmount 10.00 B | Timelock DMX +10000000000000000000000000000, holder A DMX -10000000000000000000000000000, holder A DMN +10000000000000000000000000000, migratedAmount=10000000000000000000000000000 (10.00 B = 10000000000000000000000000000); gas=249104 | 0x8f32e20ce80cd8181c7151de41e0e8d8c881fa51dca4f74a113cde62f2418606 | PASS |
| F12.2 | Holder B (real, below the old cap) claims 1.00 B with the approve of F5a.1 | exact 1:1 on every leg | Timelock DMX +1000000000000000000000000000, holder B DMX -1000000000000000000000000000, holder B DMN +1000000000000000000000000000; gas=249104 | 0x271b79d402a24893793c14fbdf7f7c74285ce9fc2b672454de47cd3e8af12573 | PASS |
| F12.3 | The treasury (= the Timelock) after the day's claims | DMX held == totalMigrated (owner 5a + holder A + holder B) | Timelock DMX=15998406600825315109208480483 (15.9984 B); totalMigrated=15998406600825315109208480483 (15.9984 B); owner 4.9984 B + A 10.0000 B + B 1.0000 B | - | PASS |
| F12.4 | Behaviour the mock does not have: a taxed DMX transfer between two other holders (holder A -> holder B, 0.01 B) after the claims | recorded: does the treasury's DMX move without any claim? | Timelock isExcludedFromReward on DMX=false; Timelock DMX 15998406600825315109208480483 -> 15998413000190515185414554648 (+6399365200076206074165 wei) while totalMigrated stays 15998406600825315109208480483 | 0x8b13a31b93ebb51eafece354f173a6754f392a1dcb408610e9441c4ce76dc36e | FINDING |
| F10.2a | Arming the first conversion with ordinary volume: holder A sends DMN to holder B (a taxed transfer, under the 5B maxTx) | inventory >= threshold afterwards | sent=1.6700 B; inventory=0.2001 B vs threshold 0.2000 B | 0xe081fa1fa9906996316c358886af53d2ce3189c5fdab8f3832fc2e237b949d27 | PASS |
| F10.2 | The first REAL conversion on the REAL router: holder B pokes (1 wei to the pair), share 1000 | one threshold chunk sold; 20/30 of the BNB to staking, 10/30 kept for buyback, ZERO to the Timelock | consumed=0.2000 B (threshold 0.2000 B); received=0.090292 BNB: staking +0.060195 (exp 0.060195), contract +0.030097, TIMELOCK +0 wei; gas=306963 | 0x28b83e97c21b740009c46e63f16431a9868ee5142abc53d9e38703b75717bc0d | PASS |
| F10.3 | THE NUMBER on the real pool: the chunk against the DMN reserve, and the price move | recorded | chunk 0.2000 B vs DMN reserve 4.7973 B = 4.16 %; BNB drawn 0.090292 of 2.261541 = 3.99 %; price 471416744 -> 434481794 wei/token, move -7.83 % | - | NOTE |
| F13.1 | The Timelock at the end of the day | BNB 0 and DMN 0 (share 1000: nothing from the token), every LP token, the claimed DMX | BNB=0, DMN=0, LP=104160172002005622471664 of 104160172002005622472664, DMX=15.9984 B | - | PASS |

### Gas ledger (run E) -- every mined transaction of the day, probes excluded

| step | signer | call | gas used | gas price (wei) | cost (BNB) |
|---|---|---|---|---|---|
| 2 phase 1 | deployer | DeployPhase1.s.sol tx 0 | 3569417 | 50000000 | 0.000178 |
| 2 phase 1 | deployer | DeployPhase1.s.sol tx 1 | 4192820 | 50000000 | 0.000209 |
| 2 phase 1 | deployer | DeployPhase1.s.sol tx 2 | 741438 | 50000000 | 0.000037 |
| 2 phase 2 | deployer | DeployPhase2.s.sol tx 0 | 1013596 | 50000000 | 0.000050 |
| 2 phase 2 | deployer | DeployPhase2.s.sol tx 1 | 1825591 | 50000000 | 0.000091 |
| 2 phase 2 | deployer | DeployPhase2.s.sol tx 2 | 1510972 | 50000000 | 0.000075 |
| 2 phase 2 | deployer | DeployPhase2.s.sol tx 3 | 51213 | 50000000 | 0.000002 |
| 2 phase 2 | deployer | DeployPhase2.s.sol tx 4 | 51213 | 50000000 | 0.000002 |
| 2 phase 2 | deployer | DeployPhase2.s.sol tx 5 | 51213 | 50000000 | 0.000002 |
| 2 phase 2 | deployer | DeployPhase2.s.sol tx 6 | 29640 | 50000000 | 0.000001 |
| 2 phase 2 | deployer | DeployPhase2.s.sol tx 7 | 29640 | 50000000 | 0.000001 |
| 2 phase 2 | deployer | DeployPhase2.s.sol tx 8 | 47896 | 50000000 | 0.000002 |
| 2 phase 2 | deployer | DeployPhase2.s.sol tx 9 | 23984 | 50000000 | 0.000001 |
| 2 phase 2 | deployer | DeployPhase2.s.sol tx 10 | 97349 | 50000000 | 0.000004 |
| 2 phase 2 | deployer | DeployPhase2.s.sol tx 11 | 36062 | 50000000 | 0.000001 |
| 2 phase 2 | deployer | DeployPhase2.s.sol tx 12 | 46173 | 50000000 | 0.000002 |
| 2 phase 2 | deployer | DeployPhase2.s.sol tx 13 | 56384 | 50000000 | 0.000002 |
| 2 phase 2 | deployer | DeployPhase2.s.sol tx 14 | 33478 | 50000000 | 0.000001 |
| 2 phase 2 | deployer | DeployPhase2.s.sol tx 15 | 24541 | 50000000 | 0.000001 |
| 5a check | holder B | approve(address,uint256) | 46328 | 50000000 | 0.000002 |
| 5a | owner | approve(address,uint256) | 46364 | 50000000 | 0.000002 |
| 5a | owner | claim(uint256) | 284476 | 50000000 | 0.000014 |
| 5b | owner | approve(address,uint256) | 50973 | 50000000 | 0.000002 |
| 5b | owner | addLiquidityETH(address,uint256,uint256,uint256,address,uint256) | 379973 | 50000000 | 0.000018 |
| 6 | owner | transfer(address,uint256) | 46883 | 50000000 | 0.000002 |
| 9 buy | owner | swapExactETHForTokensSupportingFeeOnTransferTokens(uint256,address[],address,uint256) | 241257 | 50000000 | 0.000012 |
| 9 sell | owner | approve(address,uint256) | 50949 | 50000000 | 0.000002 |
| 9 sell | owner | swapExactTokensForETHSupportingFeeOnTransferTokens(uint256,uint256,address[],address,uint256) | 194073 | 50000000 | 0.000009 |
| 10 poke | owner | transfer(address,uint256) | 94841 | 50000000 | 0.000004 |
| 11 check | holder A | approve(address,uint256) | 46328 | 50000000 | 0.000002 |
| 11a | owner | setMaxTxAmount(uint256) | 28742 | 50000000 | 0.000001 |
| 11b | owner | excludeFromFee(address) | 46232 | 50000000 | 0.000002 |
| 12 claim A | holder A | claim(uint256) | 249104 | 50000000 | 0.000012 |
| 12 claim B | holder B | claim(uint256) | 249104 | 50000000 | 0.000012 |
| 12 reflection | holder A | transfer(address,uint256) | 87154 | 50000000 | 0.000004 |
| 10 again arm | holder A | transfer(address,uint256) | 109100 | 50000000 | 0.000005 |
| 10 again poke | holder B | transfer(address,uint256) | 306963 | 50000000 | 0.000015 |

### F14 (run E) -- Gas and BNB: what the day actually cost (complete through 11b and the post-window claims)

| step | action | expected | observed | tx | verdict |
|---|---|---|---|---|---|
| F14.1 | DEPLOYER: total spent, from its balance (start - end) and from the ledger | the two phases only (19 transactions); start 0.2 BNB exactly; spent == sum of gas x price | start=0.200000, end=0.199328, spent=0.000671 BNB (671631000000000 wei); ledger: 19 txs, gas 13432620, cost 0.000671; at 1 gwei the same gas would cost 0.013432, at 3 gwei 0.040297; headroom left of the 0.2 BNB plan: 0.199328 | - | PASS |
| F14.2 | DMX OWNER: total spent | spent == gas + BNB into the pool + test buy - test sell proceeds | real start=0.096153, fork top-up=2.261000, end=0.095538, spent=2.261614 BNB; of which gas=0.000073 (11 txs, gas 1464763; at 1 gwei 0.001464, at 3 gwei 0.004394), liquidity=2.261000, test buy=0.001000, test sell back=0.000458 | - | PASS |
| F14.3 | Third-party holders: gas paid from their own real balances | their own claims only, never funded by the fork | holder A: 4 txs, 0.000024 BNB; holder B: 3 txs, 0.000030 BNB | - | NOTE |

Run E verdicts: PASS 29, NOTE 4, FINDING 5, STOP 1, DEVIATION 0; launch invariant asserted after 27 sends; local-fork guard passed 35 times.

## Run F

### F0 (run F) -- Real mainnet reads, then the local fork of chain 56 at block 124566656

| step | action | expected | observed | tx | verdict |
|---|---|---|---|---|---|
| F0.1 | Planned mainnet deployer, read on MAINNET | nonce 0 (never used: phase 1 must predict from nonce 0); no code | nonce=0, balance=0.000000 BNB (0 wei), code=0x | - | PASS |
| F0.2 | DMX owner, read on MAINNET | an EOA; its real BNB balance is what funds 5a-11b | balance=0.096153 BNB (96153397983002775 wei), nonce=1005, code=0x, DMX held=103.8537 B | - | PASS |
| F0.3 | The predecessor's authority and cap, read on MAINNET (checklist: 'confirm the DMX owner still has authority') | owner() == the DMX owner; _maxTxAmount == 1.5B; owner fee-exempt; not in a lock() window (getUnlockTime 0) | owner=0xF8EC459CAEaF1052b64B38BDD67290B0c132B0Ae, _maxTxAmount=1.5000 B, isExcludedFromFee(owner)=true, getUnlockTime=0 | - | PASS |
| F0.4 | ROUTER identity, from source and chain (not guessed) | developer.pancakeswap.finance/contracts/v2/addresses lists router 0x10ED43C718714eb63d5aA57B78B54704E256024E and factory 0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73 for BSC; on chain: router.factory() and router.WETH() match, DMX.uniswapV2Router() is the same router, factory.getPair(DMX, WBNB) == DMX.uniswapV2Pair() | router.factory=0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73, router.WETH=0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c, DMX.uniswapV2Router=0x10ED43C718714eb63d5aA57B78B54704E256024E, factory.getPair(DMX,WBNB)=0xB24916823C61Ee6272448209174F75fAfD297B82, DMX.uniswapV2Pair=0xB24916823C61Ee6272448209174F75fAfD297B82, INIT_CODE_PAIR_HASH=0x00fb7f630766e6a796048ea87d01acd3068e8ff67d078148a3fa3f4a84f69bd5 | - | PASS |
| F0.5 | Mainnet gas price at fork time | every fork transaction pays exactly this, so the BNB totals are the real funding numbers | eth_gasPrice=50000000 wei (0.05 gwei) | - | NOTE |
| F0.6 | Local fork up | Anvil on 127.0.0.1:8555, chain 56, forked from the upstream at the pinned block | clientVersion="anvil/v1.5.1", chainId=56, forkUrl=https://bsc-mainnet.public.blastapi.io, forkBlockNumber=124566656, local head=124566656 | - | PASS |
| F0.7 | Roles on the fork: deployer and owner impersonated (no key anywhere); deployer set to exactly 0.2 BNB (anvil_setBalance, the only balance ever set); the owner left at its real balance | deployer nonce 0, balance 0.200000 BNB; owner balance on the fork == the mainnet read | deployer nonce=0, balance=0.200000 (200000000000000000 wei); owner fork balance=0.096153 vs mainnet 0.096153 | - | PASS |
| F0.8 | Two REAL third-party DMX holders from the live holder list (BSCTrace, 2026-09-28), impersonated, their real BNB untouched; addresses in a gitignored file, never in this journal | holder A: > 10 B DMX (claims 10.00 B after 11b, 6.7x the old cap); holder B: 1.00-1.50 B (claims 1.00 B, below the cap); neither fee- nor reward-excluded on DMX; neither is a contract | A: > 10 B, EOA with an EIP-7702 delegation, feeExcluded=false, rewardExcluded=false; B: 1.00-1.50 B, plain EOA, feeExcluded=false, rewardExcluded=false | - | PASS |

### F1-F2 (run F) -- Step 1: no DMN/WBNB pair for the predicted proxy; step 2: phase 1 then phase 2 against the real router and the real DMX

| step | action | expected | observed | tx | verdict |
|---|---|---|---|---|---|
| F1.1 | Step 1 (#25): the REAL PancakeSwap factory, getPair(predicted proxy, WBNB), before phase 1 | 0x0; and no code at the predicted proxy, migration and Timelock | deployer nonce=0; predicted impl=0xA7bC2D4D35e49bdfC8329e3673d7De520832941c, proxy=0x160864F9945C52063A7c9f5dcd57C0C89eacbE6a, migration=0x76368b60514b145617385847aCFF7b7EA9764725, timelock=0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891; getPair=0x0000000000000000000000000000000000000000; code chars at the three=6 (6 = three empty '0x') | - | PASS |
| F2.1 | Phase 1 SIMULATED on chain 56 with the launch environment: ROUTER, OLD_DAIMON (real DMX), GUARDIAN_ADDRESS (real Safe); no MARKETING_WALLET, no TESTNET_TREASURY_OVERRIDE; MIGRATION_DURATION unset | exit 0; treasury AND marketing wallet logged '(= predicted timelock)'; no override or warning line | exit=0; derived lines=2; override/warning lines=0; 'Migration duration (days): 30' | - | PASS |

> MIGRATION_DURATION was left unset, so phase 1 used its default: 30 days. No document in the repository fixes the mainnet value; the deadline is immutable from phase 1. It is a launch-day input to decide before phase 1 (LAUNCH_DAY.md, inputs).
| F2.2 | Phase 1 BROADCAST (impersonated deployer, mainnet gas price) | impl/proxy/migration on the predicted nonces 0/1/2; marketingWallet, migration.treasury, migration.governance == the predicted Timelock (nonce 3); migration.oldDaimon == the REAL DMX; token router == the real router; deployer nonce == expectedPhase2Nonce; no override | 3 txs, gas 8503675, cost 0.000425 BNB; token=0x160864F9945C52063A7c9f5dcd57C0C89eacbE6a, migration=0x76368b60514b145617385847aCFF7b7EA9764725, predictedTimelock=0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891; marketingWallet=0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891, treasury=0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891, governance=0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891, oldDaimon=0x36EbA94407B53c631eE822C219e94580fadd67c7, router=0x10ED43C718714eb63d5aA57B78B54704E256024E, pair created=0x40A97Ae210a44057603186B4BE92BAe719342AFA; nonce=3 (expected 3) | journal broadcast/DeployPhase1.s.sol/56 | PASS |

Phase 1 console, completion block verbatim:

```
  Migration duration (days): 30
  === PHASE 1 complete ===
  DaimonV2 (proxy):      0x160864F9945C52063A7c9f5dcd57C0C89eacbE6a
  DaimonMigration:       0x76368b60514b145617385847aCFF7b7EA9764725
  Timelock (predicted):  0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891
  Migration treasury:    0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891 (= predicted timelock)
  Marketing wallet:      0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891 (= predicted timelock)
```
| F2.3 | Phase 2 BROADCAST right after phase 1 (deployer nonce untouched in between) | Timelock lands on the prediction; fees 10/10/20 (liquidityFee 30); share 1000; ONE guardian expiry on three contracts; governor.guardian == the real Safe | nonce before=3 (expected 3); 16 txs, gas 4928945, cost 0.000246 BNB; timelock=0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891, staking=0xBb596e7308D6C5AED55cEC597D372840Cbe575b1, governor=0x1397a7d25595B718BE6FEEDd42ed5E60F66E16De; fees=10/10/20 liq=30; share=1000; expiry token/timelock/governor=1885225378/1885225378/1885225378; governor.guardian=0x37F45839765AD3418E29c97d5D92407Ddbf5c7a8 | journal broadcast/DeployPhase2.s.sol/56 | PASS |
| F2.4 | Deployer after both phases | it signs nothing else for the rest of the day | nonce=19, balance=0.199328 BNB; phases 1+2: 19 txs, gas 13432620, cost 0.000671 BNB | - | NOTE |

### F3-F4 (run F) -- Step 3: the mandatory gate; step 4: automation inert without reserves

| step | action | expected | observed | tx | verdict |
|---|---|---|---|---|---|
| F3.1 | Step 3: script/verify-deploy.ps1 -Rpc <the local fork> | 36/36 green, exit code 0 -- MANDATORY GATE | exit=0; Post-broadcast verification -- chain 56 VERIFICATION PASSED: 36/36 checks green against live chain state. | - | PASS |

Full output of the verification, verbatim:

```
Post-broadcast verification -- chain 56
State file: C:\Users\Utente\Desktop\Daimon dao\deployments\two-phase-56.json


check                                                  expected                                   observed                                   verdict
-----                                                  --------                                   --------                                   -------
code at token                                          present                                    present                                    PASS
code at timelock                                       present                                    present                                    PASS
code at governor                                       present                                    present                                    PASS
code at staking                                        present                                    present                                    PASS
code at migration                                      present                                    present                                    PASS
token: timelock holds GOVERNANCE_ROLE                  true                                       true                                       PASS
token: deployer lacks GOVERNANCE_ROLE                  false                                      false                                      PASS
token: deployer lacks DEFAULT_ADMIN                    false                                      false                                      PASS
token: guardian holds GUARDIAN_ROLE                    true                                       true                                       PASS
token: stakingRewardShareBps == 1000                   1000                                       1000                                       PASS
token: stakingContract is the staking                  0xBb596e7308D6C5AED55cEC597D372840Cbe575b1 0xBb596e7308D6C5AED55cEC597D372840Cbe575b1 PASS
token: marketingWallet as configured                   0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891 0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891 PASS
token: migration is fee-exempt                         true                                       true                                       PASS
token: fees == (10,10,20)                              10,10,20                                   10,10,20                                   PASS
timelock: self-administers                             true                                       true                                       PASS
timelock: deployer lacks ADMIN_ROLE                    false                                      false                                      PASS
timelock: deployer lacks PROPOSER_ROLE                 false                                      false                                      PASS
timelock: deployer lacks EXECUTOR_ROLE                 false                                      false                                      PASS
timelock: governor is proposer                         true                                       true                                       PASS
timelock: governor is executor                         true                                       true                                       PASS
timelock: guardian is canceller                        true                                       true                                       PASS
timelock: governor is canceller                        true                                       true                                       PASS
timelock: self-cancel role present                     true                                       true                                       PASS
expiry: timelock == token (exact)                      1885225378                                 1885225378                                 PASS
expiry: governor == token (exact)                      1885225378                                 1885225378                                 PASS
staking: timelock is governance                        true                                       true                                       PASS
staking: deployer is not governance                    false                                      false                                      PASS
supply: totalSupply == INITIAL_SUPPLY                  1000000000000000000000000000000            1000000000000000000000000000000            PASS
supply: all of it in the migration                     1000000000000000000000000000000            1000000000000000000000000000000            PASS
migration: governance is the timelock                  0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891 0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891 PASS
migration: newDaimon is the token                      0x160864F9945C52063A7c9f5dcd57C0C89eacbE6a 0x160864F9945C52063A7c9f5dcd57C0C89eacbE6a PASS
migration: oldDaimon as configured                     0x36EbA94407B53c631eE822C219e94580fadd67c7 0x36EbA94407B53c631eE822C219e94580fadd67c7 PASS
migration: treasury as configured                      0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891 0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891 PASS
migration: treasury is the timelock                    0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891 0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891 PASS
token: marketingWallet is the deployed timelock (live) 0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891 0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891 PASS
token: pancake pair created                            present                                    present                                    PASS



Guardian expiry raw values: token=1885225378 timelock=1885225378 governor=1885225378
VERIFICATION PASSED: 36/36 checks green against live chain state.

```
| F4.1 | Step 4 (#27): automation before liquidity | enabled by initialize, inert by construction: inventory 0, reserves (0,0), contract BNB 0 | swapAndLiquifyEnabled=true, buyBackEnabled=true, inventory=0, reserves=(0,0), contract BNB=0 | - | PASS |

### F5a (run F) -- Step 5a on the REAL DMX: a non-owner is refused, the owner claims only the liquidity quota

| step | action | expected | observed | tx | verdict |
|---|---|---|---|---|---|
| F5a.1 | A REAL non-owner (holder B, below the cap, not fee-exempt) approves then claims 1.00 B, BEFORE 11b | refused with AmountMismatch (#29): the real DMX takes its 11% on the claimant -> treasury leg; nothing credited | approve mined (holder B's own gas); claim: reverted with AmountMismatch; holder B DMN=0 | 0x07647f4a4cf803214ea60948a9b4207147cf9a495be531ee4b93ac560d557255 | PASS |
| F5a.1b | The LAUNCH-DAY form of the check: eth_call claim(1.00 B) from a real holder that never approved (holder A), the DMX allowance supplied by --override-state on slot keccak(migration . keccak(holder . 7)) | reverts with AmountMismatch exactly like the mined approve + claim above; nothing mined, the real allowance untouched | real allowance before=0; claim: reverted (different reason): cast : Error: server returned an error response: error code 3: execution reverted: SafeMath: division by zero, data: "0 x08c379a000000000000000000000000000000000000000000000000000000000000000200000000; holder A DMN=0; real allowance after=0 | - | DEVIATION |
| F5a.2 | Why the owner can claim now: its status on the REAL DMX | owner() == the DMX owner (cap-exempt as sender), isExcludedFromFee(owner) true; the Timelock NOT exempt (11b not done); cap 1.5B (11a not done) | owner=0xF8EC459CAEaF1052b64B38BDD67290B0c132B0Ae, isExcludedFromFee(owner)=true, isExcludedFromFee(timelock)=false, _maxTxAmount=1.5000 B | - | PASS |
| F5a.3 | Sizing from live values: the REAL DMX pool on the fork; the largest single addLiquidityETH under the DMN maxTx (decision (c)) | price = DMX pool WBNB reserve x 1e18 / DMX reserve; BNB leg = net(maxTx) x price, floored to 0.001 BNB; net target = BNB x 1e18 / price; gross = ceil(net x 1000 / 960); pair receives >= net target by < 1000 wei; gross <= maxTx | DMX pool reserves DMX=76394917263158812489516157516 (76.3949 B), WBNB=35996660568812417183 (35.996660 BNB) -> DMX price=471191826 wei/token (0.000000000471191826 BNB); DMN maxTx=5.0000 B -> net 4.8000 B; BNB leg=2.261000 BNB (2261000000000000000 wei); net target=4798470336792302504840141263; gross=4998406600825315109208480483 (4.9984 B); net of gross=4798470336792302504840141265 (+2 wei) | - | PASS |
| F5a.4 | Funding preview, BEFORE the owner claims: can the owner's REAL balance fund 5b? | owner BNB >= BNB leg + 0.002 BNB gas reserve | owner=0.096153 BNB; needed=2.263000 (leg 2.261000 + reserve 0.002000); SHORT by 2.166846 BNB | - | FINDING |
| F5a.5 | Step 5a: the owner approves and claims EXACTLY the gross, on the REAL DMX | exact 1:1 on every leg: Timelock DMX +gross, owner DMX -gross, owner DMN +gross, migratedAmount == gross | Timelock DMX +4998406600825315109208480483, owner DMX -4998406600825315109208480483, owner DMN +4998406600825315109208480483, migratedAmount=4998406600825315109208480483 (gross 4998406600825315109208480483); claim gas=284476 | 0x6e476e17231f721f278c4166590764afb9c461459c46b9742ec0030dff8aea49 / 0xb9cf5ea584bc5ff0d45311e2679f900df763cd070bd1ea509e2d65fd682b227c | PASS |

### F5b (run F) -- Step 5b: initial liquidity on the REAL router at the REAL DMX price

| step | action | expected | observed | tx | verdict |
|---|---|---|---|---|---|
| F5b.0 | GATE: the owner's REAL BNB against the 5b requirement | owner BNB >= BNB leg + gas reserve, or STOP | owner=0.096136 BNB (96136855983002775 wei); leg=2.261000, reserve=0.002000, needed=2.263000; SHORTFALL=2.166863 BNB (2166863144016997225 wei) | - | STOP |
| F5b.0b | SETUP DEVIATION, by the operator's switch -FundOwnerForLiquidity: the fork adds EXACTLY the BNB leg to the owner (anvil_setBalance); every gas cost from here is still paid out of the owner's real balance | owner = real balance + leg; the continuation measures what the owner really needs | owner 0.096136 -> 2.357136 BNB (+2.261000) | - | NOTE |
| F5b.P1 | PROBE (inside evm_snapshot, discarded): a stranger, funded 0.01 BNB by the fork for this probe only, wraps 1 wei, sends it to the EMPTY DMN pair and calls sync(); then the owner's planned addLiquidityETH is simulated | recorded: does a 1-wei donation block the router path? | reserves after sync: DMN=0 WBNB=1; addLiquidityETH: reverted with INSUFFICIENT_LIQUIDITY | 0xf248ece498cdf004721740f55c0360a5463363f5500613de66512fc19ecb2e83 | FINDING |
| F5b.P2 | PROBE, recovery path on the same griefed pair: owner transfers the gross DMN to the pair (taxed, automation idle), wraps the BNB leg, sends WBNB, calls pair.mint(owner) | the pool opens anyway: reserve DMN == net, WBNB == leg + the 1 donated wei, price within 1 ppm of the DMX price; LP minted to the owner | reserves DMN=4798470336792302504840141265 (net 4798470336792302504840141265), WBNB=2261000000000000001 (leg+1 = 2261000000000000001); price=471191826 vs DMX 471191826; LP=104160172002005622471664 | 0x187c824acc3b5b8c11c2515af83bdff8fe9a49c10b465e1411f4d995c927533d | PASS |
| F5b.P3 | PROBE discarded: evm_revert to the snapshot | pair back to (0,0); owner DMN back to the gross; the probe's transactions excluded from every total | reserves=(0,0), owner DMN=4998406600825315109208480483 | - | PASS |
| F5b.1 | Step 5b: approve + addLiquidityETH(token, gross, amountTokenMin = gross, amountETHMin = leg, owner) on the REAL router | reserve DMN == net of gross (exact), reserve WBNB == the leg (no refund); owner DMN back to 0; opening price == the DMX price within 1 ppm (never above: the net is rounded up) | BNB=2261000000000000000 wei (2.261000); DMN gross=4998406600825315109208480483 (4.9984 B); DMN received by the pair: reserve=4798470336792302504840141265, balanceOf=4798470336792302504840141265 (4.7984 B), expected 4798470336792302504840141265; reserve WBNB=2261000000000000000; OPENING PRICE=471191825 wei/token vs DMX 471191826 (diff 1 wei, 0.000000 %); owner DMN after=0; LP minted=104160172002005622471664; gas approve=50973, add=379973 | 0xe0e19e03e299d8c3bec3d1a307a79a93c6485253ce3f1cd8f013d30bd731a3e5 / 0xd9ce50d30e9eb89ba4de5a95fe987b9f89615b9754531aeecf5a293bc62c24d6 | PASS |

### F6-F8 (run F) -- Step 6: every LP token to the Timelock; step 7: one pool; step 8: reserves non-zero

| step | action | expected | observed | tx | verdict |
|---|---|---|---|---|---|
| F6.1 | Step 6: ALL the LP tokens, owner -> Timelock | owner LP 0, deployer LP 0, Timelock LP == totalSupply - MINIMUM_LIQUIDITY (1000) | moved=104160172002005622471664; owner=0, deployer=0, timelock=104160172002005622471664, totalSupply=104160172002005622472664, MINIMUM_LIQUIDITY=1000; gas=46883 | 0x9ae42c615787987c99e5c722a31c9eb7143e2f089bd54f57cfecf7d1c7b22d6e | PASS |
| F7.1 | Step 7: one pool only; stored pair == factory pair | factory.getPair(DMN, WBNB) == token.uniswapV2Pair; no DMN/USDT or DMN/BUSD pair | stored=0x40A97Ae210a44057603186B4BE92BAe719342AFA, factory=0x40A97Ae210a44057603186B4BE92BAe719342AFA; USDT pair=0x0000000000000000000000000000000000000000, BUSD pair=0x0000000000000000000000000000000000000000 | - | PASS |
| F8.1 | Step 8: reserves non-zero -> automation live | both reserves > 0; the liquidity transfer was taxed: inventory == gross x 3% (plus at most 0.01% reflection) | DMN=4.7984 B, WBNB=2.261000; inventory=149959729762611153315200333 (0.1499 B), 3% of gross=149952198024759453276254414; threshold minimumTokensBeforeSwap=0.2000 B | - | PASS |

### F9-F10 (run F) -- Step 9: the test swap pays exactly 4%; step 10: the first poke

| step | action | expected | observed | tx | verdict |
|---|---|---|---|---|---|
| F9.1 | The owner buys with 0.001 BNB through the real router (it holds no DMN after 5b: the test sell needs a buy first) | the owner receives the net of what left the pair -- amount - floor(1%) - floor(3%) -- plus its own reflection share (< 0.01%) | left the pair=2116038660940306852053568 (0.0021 B); owner received=2031397157695009437060994; net (96%, floors per fee)=2031397114502694577971426 (+43192314859089568 wei); gas=241257 | 0xaf6e2fc3793895b49c9c5ce9a969db52484bd014ceb5304dd2be4ecc81d655bf | PASS |
| F9.2 | Step 9: the owner sells half of it through the real router | the pair (balanceOf delta, reward-excluded) receives EXACTLY the net: amount - floor(1%) - floor(3%), i.e. 96% up to the two floors -- fee 4%, not the historical 5%; inventory grows by 3% (+ reflection); no conversion on a router sell (#1): contract BNB 0, Timelock BNB 0 | sold=1015698578847504718530497; pair received=975070635693604529789279 (net=975070635693604529789279, floor(96%)=975070635693604529789277, 95% would be 964913649905129482603972); inventory +30472488805409470477799; BNB back to the owner=0.000458 (458608676268387 wei); contract BNB=0, Timelock BNB=0; gas=194073 | 0x9094433f41d35d2fceebccddafc1503f9328f0620de5f86e8c638ecd17973fd5 / 0x1161701c9f74a7b018e2a7324de769867ec84eb443a4da66675678c31473564a | PASS |
| F10.1 | Step 10: the first poke (1 wei DMN owner -> pair), share 1000 | zero BNB to the Timelock. Recorded: is the inventory above the threshold yet? | inventory=0.1500 B < threshold 0.2000 B: NOTHING converts (inventory after=0.1500 B); staking +0, contract +0, TIMELOCK +0 wei; the first conversion needs 0.0499 B more inventory = about 1.6648 B of further taxed volume; gas=94841 | 0x96cf06bc72953c45287e78cb64c318c554f0ff5b5f0563eeb9606392d1795d27 | FINDING |

> On launch day the first poke is a no-op: the 5b liquidity transfer arms only 3% of ~5B = ~0.15B of inventory, under the 0.2B threshold. The Timelock-receives-nothing property is proven again at the first REAL conversion, which happens later (F10.2 below, after the window opens).

### F11 (run F) -- 11a setMaxTxAmount(full supply), then 11b excludeFromFee(TIMELOCK) -- on the REAL DMX, same session, nothing between

| step | action | expected | observed | tx | verdict |
|---|---|---|---|---|---|
| F11.0 | BEFORE 11a: holder A (real, > 10 B) approves and claims 10.00 B | REVERTS with the real DMX cap message (the cap is checked before any fee logic) | approve mined (holder A's own gas); claim: reverted with Transfer amount exceeds the maxTxAmount. | 0xd3e896cdcb81f0dcff96cd0bf60c4c90bf86f2447571e3a5cf2a9e3fd2af89cc | PASS |
| F11a | Step 11a: setMaxTxAmount(1000000000000 x 1e18) -- a non-owner first (eth_call), then the owner | non-owner refused by Ownable; the owner's call mined; _maxTxAmount == the full supply == totalSupply() | non-owner: reverted with Ownable: caller is not the owner; _maxTxAmount 1.5000 B -> 1000.0000 B (totalSupply 1000.0000 B); logs emitted by the call=0; gas=28742; block 124566687 | 0x376244f1921fcd484b134f411a316cf41f7f30935e4f1a5ca585c36292c0c6c0 | PASS |
| F11b | Step 11b, LAST: excludeFromFee(TIMELOCK) -- the treasury, not the Migration; the window opens | isExcludedFromFee(timelock) true, (migration) false; mined right after 11a with nothing in between | timelock=true, migration=false; logs emitted=0; 11a block 124566687 -> 11b block 124566688; gas=46232 | 0x97ab6f75da75bf776158b0bee8b65213fc82a6445483b61002086e9d55951b75 | PASS |
| F11.x | Events: what an observer sees of 11a and 11b | recorded against the mock (CampaignOldDaimon emits MaxTxAmountUpdated on setMaxTxAmount) | the REAL DMX emitted 0 log(s) on setMaxTxAmount and 0 on excludeFromFee: both are silent -- only the calldata and a storage read show them | - | FINDING |

### F12 (run F) -- After 11b: real third-party holders claim through the open window

| step | action | expected | observed | tx | verdict |
|---|---|---|---|---|---|
| F12.1 | Holder A (real, > 10 B, not the owner, not exempt) repeats the SAME 10.00 B claim (the F11.0 approve still stands) | passes 1:1, no fee: Timelock DMX +10.00 B exactly, holder A DMX -10.00 B exactly, holder A DMN +10.00 B exactly, migratedAmount 10.00 B | Timelock DMX +10000000000000000000000000000, holder A DMX -10000000000000000000000000000, holder A DMN +10000000000000000000000000000, migratedAmount=10000000000000000000000000000 (10.00 B = 10000000000000000000000000000); gas=249104 | 0x8f32e20ce80cd8181c7151de41e0e8d8c881fa51dca4f74a113cde62f2418606 | PASS |
| F12.2 | Holder B (real, below the old cap) claims 1.00 B with the approve of F5a.1 | exact 1:1 on every leg | Timelock DMX +1000000000000000000000000000, holder B DMX -1000000000000000000000000000, holder B DMN +1000000000000000000000000000; gas=249104 | 0x271b79d402a24893793c14fbdf7f7c74285ce9fc2b672454de47cd3e8af12573 | PASS |
| F12.3 | The treasury (= the Timelock) after the day's claims | DMX held == totalMigrated (owner 5a + holder A + holder B) | Timelock DMX=15998406600825315109208480483 (15.9984 B); totalMigrated=15998406600825315109208480483 (15.9984 B); owner 4.9984 B + A 10.0000 B + B 1.0000 B | - | PASS |
| F12.4 | Behaviour the mock does not have: a taxed DMX transfer between two other holders (holder A -> holder B, 0.01 B) after the claims | recorded: does the treasury's DMX move without any claim? | Timelock isExcludedFromReward on DMX=false; Timelock DMX 15998406600825315109208480483 -> 15998413000190515185414554648 (+6399365200076206074165 wei) while totalMigrated stays 15998406600825315109208480483 | 0x8b13a31b93ebb51eafece354f173a6754f392a1dcb408610e9441c4ce76dc36e | FINDING |
| F10.2a | Arming the first conversion with ordinary volume: holder A sends DMN to holder B (a taxed transfer, under the 5B maxTx) | inventory >= threshold afterwards | sent=1.6700 B; inventory=0.2001 B vs threshold 0.2000 B | 0xe081fa1fa9906996316c358886af53d2ce3189c5fdab8f3832fc2e237b949d27 | PASS |
| F10.2 | The first REAL conversion on the REAL router: holder B pokes (1 wei to the pair), share 1000 | one threshold chunk sold; 20/30 of the BNB to staking, 10/30 kept for buyback, ZERO to the Timelock | consumed=0.2000 B (threshold 0.2000 B); received=0.090292 BNB: staking +0.060195 (exp 0.060195), contract +0.030097, TIMELOCK +0 wei; gas=306963 | 0x28b83e97c21b740009c46e63f16431a9868ee5142abc53d9e38703b75717bc0d | PASS |
| F10.3 | THE NUMBER on the real pool: the chunk against the DMN reserve, and the price move | recorded | chunk 0.2000 B vs DMN reserve 4.7973 B = 4.16 %; BNB drawn 0.090292 of 2.261541 = 3.99 %; price 471416744 -> 434481794 wei/token, move -7.83 % | - | NOTE |
| F13.1 | The Timelock at the end of the day | BNB 0 and DMN 0 (share 1000: nothing from the token), every LP token, the claimed DMX | BNB=0, DMN=0, LP=104160172002005622471664 of 104160172002005622472664, DMX=15.9984 B | - | PASS |

### Gas ledger (run F) -- every mined transaction of the day, probes excluded

| step | signer | call | gas used | gas price (wei) | cost (BNB) |
|---|---|---|---|---|---|
| 2 phase 1 | deployer | DeployPhase1.s.sol tx 0 | 3569417 | 50000000 | 0.000178 |
| 2 phase 1 | deployer | DeployPhase1.s.sol tx 1 | 4192820 | 50000000 | 0.000209 |
| 2 phase 1 | deployer | DeployPhase1.s.sol tx 2 | 741438 | 50000000 | 0.000037 |
| 2 phase 2 | deployer | DeployPhase2.s.sol tx 0 | 1013596 | 50000000 | 0.000050 |
| 2 phase 2 | deployer | DeployPhase2.s.sol tx 1 | 1825591 | 50000000 | 0.000091 |
| 2 phase 2 | deployer | DeployPhase2.s.sol tx 2 | 1510972 | 50000000 | 0.000075 |
| 2 phase 2 | deployer | DeployPhase2.s.sol tx 3 | 51213 | 50000000 | 0.000002 |
| 2 phase 2 | deployer | DeployPhase2.s.sol tx 4 | 51213 | 50000000 | 0.000002 |
| 2 phase 2 | deployer | DeployPhase2.s.sol tx 5 | 51213 | 50000000 | 0.000002 |
| 2 phase 2 | deployer | DeployPhase2.s.sol tx 6 | 29640 | 50000000 | 0.000001 |
| 2 phase 2 | deployer | DeployPhase2.s.sol tx 7 | 29640 | 50000000 | 0.000001 |
| 2 phase 2 | deployer | DeployPhase2.s.sol tx 8 | 47896 | 50000000 | 0.000002 |
| 2 phase 2 | deployer | DeployPhase2.s.sol tx 9 | 23984 | 50000000 | 0.000001 |
| 2 phase 2 | deployer | DeployPhase2.s.sol tx 10 | 97349 | 50000000 | 0.000004 |
| 2 phase 2 | deployer | DeployPhase2.s.sol tx 11 | 36062 | 50000000 | 0.000001 |
| 2 phase 2 | deployer | DeployPhase2.s.sol tx 12 | 46173 | 50000000 | 0.000002 |
| 2 phase 2 | deployer | DeployPhase2.s.sol tx 13 | 56384 | 50000000 | 0.000002 |
| 2 phase 2 | deployer | DeployPhase2.s.sol tx 14 | 33478 | 50000000 | 0.000001 |
| 2 phase 2 | deployer | DeployPhase2.s.sol tx 15 | 24541 | 50000000 | 0.000001 |
| 5a check | holder B | approve(address,uint256) | 46328 | 50000000 | 0.000002 |
| 5a | owner | approve(address,uint256) | 46364 | 50000000 | 0.000002 |
| 5a | owner | claim(uint256) | 284476 | 50000000 | 0.000014 |
| 5b | owner | approve(address,uint256) | 50973 | 50000000 | 0.000002 |
| 5b | owner | addLiquidityETH(address,uint256,uint256,uint256,address,uint256) | 379973 | 50000000 | 0.000018 |
| 6 | owner | transfer(address,uint256) | 46883 | 50000000 | 0.000002 |
| 9 buy | owner | swapExactETHForTokensSupportingFeeOnTransferTokens(uint256,address[],address,uint256) | 241257 | 50000000 | 0.000012 |
| 9 sell | owner | approve(address,uint256) | 50949 | 50000000 | 0.000002 |
| 9 sell | owner | swapExactTokensForETHSupportingFeeOnTransferTokens(uint256,uint256,address[],address,uint256) | 194073 | 50000000 | 0.000009 |
| 10 poke | owner | transfer(address,uint256) | 94841 | 50000000 | 0.000004 |
| 11 check | holder A | approve(address,uint256) | 46328 | 50000000 | 0.000002 |
| 11a | owner | setMaxTxAmount(uint256) | 28742 | 50000000 | 0.000001 |
| 11b | owner | excludeFromFee(address) | 46232 | 50000000 | 0.000002 |
| 12 claim A | holder A | claim(uint256) | 249104 | 50000000 | 0.000012 |
| 12 claim B | holder B | claim(uint256) | 249104 | 50000000 | 0.000012 |
| 12 reflection | holder A | transfer(address,uint256) | 87154 | 50000000 | 0.000004 |
| 10 again arm | holder A | transfer(address,uint256) | 109100 | 50000000 | 0.000005 |
| 10 again poke | holder B | transfer(address,uint256) | 306963 | 50000000 | 0.000015 |

### F14 (run F) -- Gas and BNB: what the day actually cost (complete through 11b and the post-window claims)

| step | action | expected | observed | tx | verdict |
|---|---|---|---|---|---|
| F14.1 | DEPLOYER: total spent, from its balance (start - end) and from the ledger | the two phases only (19 transactions); start 0.2 BNB exactly; spent == sum of gas x price | start=0.200000, end=0.199328, spent=0.000671 BNB (671631000000000 wei); ledger: 19 txs, gas 13432620, cost 0.000671; at 1 gwei the same gas would cost 0.013432, at 3 gwei 0.040297; headroom left of the 0.2 BNB plan: 0.199328 | - | PASS |
| F14.2 | DMX OWNER: total spent | spent == gas + BNB into the pool + test buy - test sell proceeds | real start=0.096153, fork top-up=2.261000, end=0.095538, spent=2.261614 BNB; of which gas=0.000073 (11 txs, gas 1464763; at 1 gwei 0.001464, at 3 gwei 0.004394), liquidity=2.261000, test buy=0.001000, test sell back=0.000458 | - | PASS |
| F14.3 | Third-party holders: gas paid from their own real balances | their own claims only, never funded by the fork | holder A: 4 txs, 0.000024 BNB; holder B: 3 txs, 0.000030 BNB | - | NOTE |

Run F verdicts: PASS 29, NOTE 4, FINDING 5, STOP 1, DEVIATION 1; launch invariant asserted after 27 sends; local-fork guard passed 36 times.

> Annotation to F5a.1b (harness-side DEVIATION, and a launch-day pitfall): cast's --override-state REPLACES the account's whole storage with the given slots, so the eth_call ran against a DMX with every other slot zeroed and died in _getRate ('SafeMath: division by zero') before reaching the migration's check. The flag that patches one slot and keeps the rest is --override-state-diff. The runner now uses it; run G below re-runs the day with it. LAUNCH_DAY.md prints the -diff form and warns against the other.

## Run G

### F0 (run G) -- Real mainnet reads, then the local fork of chain 56 at block 124566908

| step | action | expected | observed | tx | verdict |
|---|---|---|---|---|---|
| F0.1 | Planned mainnet deployer, read on MAINNET | nonce 0 (never used: phase 1 must predict from nonce 0); no code | nonce=0, balance=0.000000 BNB (0 wei), code=0x | - | PASS |
| F0.2 | DMX owner, read on MAINNET | an EOA; its real BNB balance is what funds 5a-11b | balance=0.096153 BNB (96153397983002775 wei), nonce=1005, code=0x, DMX held=103.8537 B | - | PASS |
| F0.3 | The predecessor's authority and cap, read on MAINNET (checklist: 'confirm the DMX owner still has authority') | owner() == the DMX owner; _maxTxAmount == 1.5B; owner fee-exempt; not in a lock() window (getUnlockTime 0) | owner=0xF8EC459CAEaF1052b64B38BDD67290B0c132B0Ae, _maxTxAmount=1.5000 B, isExcludedFromFee(owner)=true, getUnlockTime=0 | - | PASS |
| F0.4 | ROUTER identity, from source and chain (not guessed) | developer.pancakeswap.finance/contracts/v2/addresses lists router 0x10ED43C718714eb63d5aA57B78B54704E256024E and factory 0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73 for BSC; on chain: router.factory() and router.WETH() match, DMX.uniswapV2Router() is the same router, factory.getPair(DMX, WBNB) == DMX.uniswapV2Pair() | router.factory=0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73, router.WETH=0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c, DMX.uniswapV2Router=0x10ED43C718714eb63d5aA57B78B54704E256024E, factory.getPair(DMX,WBNB)=0xB24916823C61Ee6272448209174F75fAfD297B82, DMX.uniswapV2Pair=0xB24916823C61Ee6272448209174F75fAfD297B82, INIT_CODE_PAIR_HASH=0x00fb7f630766e6a796048ea87d01acd3068e8ff67d078148a3fa3f4a84f69bd5 | - | PASS |
| F0.5 | Mainnet gas price at fork time | every fork transaction pays exactly this, so the BNB totals are the real funding numbers | eth_gasPrice=50000000 wei (0.05 gwei) | - | NOTE |
| F0.6 | Local fork up | Anvil on 127.0.0.1:8555, chain 56, forked from the upstream at the pinned block | clientVersion="anvil/v1.5.1", chainId=56, forkUrl=https://bsc-mainnet.public.blastapi.io, forkBlockNumber=124566908, local head=124566908 | - | PASS |
| F0.7 | Roles on the fork: deployer and owner impersonated (no key anywhere); deployer set to exactly 0.2 BNB (anvil_setBalance, the only balance ever set); the owner left at its real balance | deployer nonce 0, balance 0.200000 BNB; owner balance on the fork == the mainnet read | deployer nonce=0, balance=0.200000 (200000000000000000 wei); owner fork balance=0.096153 vs mainnet 0.096153 | - | PASS |
| F0.8 | Two REAL third-party DMX holders from the live holder list (BSCTrace, 2026-09-28), impersonated, their real BNB untouched; addresses in a gitignored file, never in this journal | holder A: > 10 B DMX (claims 10.00 B after 11b, 6.7x the old cap); holder B: 1.00-1.50 B (claims 1.00 B, below the cap); neither fee- nor reward-excluded on DMX; neither is a contract | A: > 10 B, EOA with an EIP-7702 delegation, feeExcluded=false, rewardExcluded=false; B: 1.00-1.50 B, plain EOA, feeExcluded=false, rewardExcluded=false | - | PASS |

### F1-F2 (run G) -- Step 1: no DMN/WBNB pair for the predicted proxy; step 2: phase 1 then phase 2 against the real router and the real DMX

| step | action | expected | observed | tx | verdict |
|---|---|---|---|---|---|
| F1.1 | Step 1 (#25): the REAL PancakeSwap factory, getPair(predicted proxy, WBNB), before phase 1 | 0x0; and no code at the predicted proxy, migration and Timelock | deployer nonce=0; predicted impl=0xA7bC2D4D35e49bdfC8329e3673d7De520832941c, proxy=0x160864F9945C52063A7c9f5dcd57C0C89eacbE6a, migration=0x76368b60514b145617385847aCFF7b7EA9764725, timelock=0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891; getPair=0x0000000000000000000000000000000000000000; code chars at the three=6 (6 = three empty '0x') | - | PASS |
| F2.1 | Phase 1 SIMULATED on chain 56 with the launch environment: ROUTER, OLD_DAIMON (real DMX), GUARDIAN_ADDRESS (real Safe); no MARKETING_WALLET, no TESTNET_TREASURY_OVERRIDE; MIGRATION_DURATION unset | exit 0; treasury AND marketing wallet logged '(= predicted timelock)'; no override or warning line | exit=0; derived lines=2; override/warning lines=0; 'Migration duration (days): 30' | - | PASS |

> MIGRATION_DURATION was left unset, so phase 1 used its default: 30 days. No document in the repository fixes the mainnet value; the deadline is immutable from phase 1. It is a launch-day input to decide before phase 1 (LAUNCH_DAY.md, inputs).
| F2.2 | Phase 1 BROADCAST (impersonated deployer, mainnet gas price) | impl/proxy/migration on the predicted nonces 0/1/2; marketingWallet, migration.treasury, migration.governance == the predicted Timelock (nonce 3); migration.oldDaimon == the REAL DMX; token router == the real router; deployer nonce == expectedPhase2Nonce; no override | 3 txs, gas 8503675, cost 0.000425 BNB; token=0x160864F9945C52063A7c9f5dcd57C0C89eacbE6a, migration=0x76368b60514b145617385847aCFF7b7EA9764725, predictedTimelock=0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891; marketingWallet=0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891, treasury=0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891, governance=0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891, oldDaimon=0x36EbA94407B53c631eE822C219e94580fadd67c7, router=0x10ED43C718714eb63d5aA57B78B54704E256024E, pair created=0x40A97Ae210a44057603186B4BE92BAe719342AFA; nonce=3 (expected 3) | journal broadcast/DeployPhase1.s.sol/56 | PASS |

Phase 1 console, completion block verbatim:

```
  Migration duration (days): 30
  === PHASE 1 complete ===
  DaimonV2 (proxy):      0x160864F9945C52063A7c9f5dcd57C0C89eacbE6a
  DaimonMigration:       0x76368b60514b145617385847aCFF7b7EA9764725
  Timelock (predicted):  0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891
  Migration treasury:    0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891 (= predicted timelock)
  Marketing wallet:      0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891 (= predicted timelock)
```
| F2.3 | Phase 2 BROADCAST right after phase 1 (deployer nonce untouched in between) | Timelock lands on the prediction; fees 10/10/20 (liquidityFee 30); share 1000; ONE guardian expiry on three contracts; governor.guardian == the real Safe | nonce before=3 (expected 3); 16 txs, gas 4928945, cost 0.000246 BNB; timelock=0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891, staking=0xBb596e7308D6C5AED55cEC597D372840Cbe575b1, governor=0x1397a7d25595B718BE6FEEDd42ed5E60F66E16De; fees=10/10/20 liq=30; share=1000; expiry token/timelock/governor=1885225493/1885225493/1885225493; governor.guardian=0x37F45839765AD3418E29c97d5D92407Ddbf5c7a8 | journal broadcast/DeployPhase2.s.sol/56 | PASS |
| F2.4 | Deployer after both phases | it signs nothing else for the rest of the day | nonce=19, balance=0.199328 BNB; phases 1+2: 19 txs, gas 13432620, cost 0.000671 BNB | - | NOTE |

### F3-F4 (run G) -- Step 3: the mandatory gate; step 4: automation inert without reserves

| step | action | expected | observed | tx | verdict |
|---|---|---|---|---|---|
| F3.1 | Step 3: script/verify-deploy.ps1 -Rpc <the local fork> | 36/36 green, exit code 0 -- MANDATORY GATE | exit=0; Post-broadcast verification -- chain 56 VERIFICATION PASSED: 36/36 checks green against live chain state. | - | PASS |

Full output of the verification, verbatim:

```
Post-broadcast verification -- chain 56
State file: C:\Users\Utente\Desktop\Daimon dao\deployments\two-phase-56.json


check                                                  expected                                   observed                                   verdict
-----                                                  --------                                   --------                                   -------
code at token                                          present                                    present                                    PASS
code at timelock                                       present                                    present                                    PASS
code at governor                                       present                                    present                                    PASS
code at staking                                        present                                    present                                    PASS
code at migration                                      present                                    present                                    PASS
token: timelock holds GOVERNANCE_ROLE                  true                                       true                                       PASS
token: deployer lacks GOVERNANCE_ROLE                  false                                      false                                      PASS
token: deployer lacks DEFAULT_ADMIN                    false                                      false                                      PASS
token: guardian holds GUARDIAN_ROLE                    true                                       true                                       PASS
token: stakingRewardShareBps == 1000                   1000                                       1000                                       PASS
token: stakingContract is the staking                  0xBb596e7308D6C5AED55cEC597D372840Cbe575b1 0xBb596e7308D6C5AED55cEC597D372840Cbe575b1 PASS
token: marketingWallet as configured                   0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891 0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891 PASS
token: migration is fee-exempt                         true                                       true                                       PASS
token: fees == (10,10,20)                              10,10,20                                   10,10,20                                   PASS
timelock: self-administers                             true                                       true                                       PASS
timelock: deployer lacks ADMIN_ROLE                    false                                      false                                      PASS
timelock: deployer lacks PROPOSER_ROLE                 false                                      false                                      PASS
timelock: deployer lacks EXECUTOR_ROLE                 false                                      false                                      PASS
timelock: governor is proposer                         true                                       true                                       PASS
timelock: governor is executor                         true                                       true                                       PASS
timelock: guardian is canceller                        true                                       true                                       PASS
timelock: governor is canceller                        true                                       true                                       PASS
timelock: self-cancel role present                     true                                       true                                       PASS
expiry: timelock == token (exact)                      1885225493                                 1885225493                                 PASS
expiry: governor == token (exact)                      1885225493                                 1885225493                                 PASS
staking: timelock is governance                        true                                       true                                       PASS
staking: deployer is not governance                    false                                      false                                      PASS
supply: totalSupply == INITIAL_SUPPLY                  1000000000000000000000000000000            1000000000000000000000000000000            PASS
supply: all of it in the migration                     1000000000000000000000000000000            1000000000000000000000000000000            PASS
migration: governance is the timelock                  0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891 0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891 PASS
migration: newDaimon is the token                      0x160864F9945C52063A7c9f5dcd57C0C89eacbE6a 0x160864F9945C52063A7c9f5dcd57C0C89eacbE6a PASS
migration: oldDaimon as configured                     0x36EbA94407B53c631eE822C219e94580fadd67c7 0x36EbA94407B53c631eE822C219e94580fadd67c7 PASS
migration: treasury as configured                      0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891 0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891 PASS
migration: treasury is the timelock                    0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891 0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891 PASS
token: marketingWallet is the deployed timelock (live) 0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891 0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891 PASS
token: pancake pair created                            present                                    present                                    PASS



Guardian expiry raw values: token=1885225493 timelock=1885225493 governor=1885225493
VERIFICATION PASSED: 36/36 checks green against live chain state.

```
| F4.1 | Step 4 (#27): automation before liquidity | enabled by initialize, inert by construction: inventory 0, reserves (0,0), contract BNB 0 | swapAndLiquifyEnabled=true, buyBackEnabled=true, inventory=0, reserves=(0,0), contract BNB=0 | - | PASS |

### F5a (run G) -- Step 5a on the REAL DMX: a non-owner is refused, the owner claims only the liquidity quota

| step | action | expected | observed | tx | verdict |
|---|---|---|---|---|---|
| F5a.1 | A REAL non-owner (holder B, below the cap, not fee-exempt) approves then claims 1.00 B, BEFORE 11b | refused with AmountMismatch (#29): the real DMX takes its 11% on the claimant -> treasury leg; nothing credited | approve mined (holder B's own gas); claim: reverted with AmountMismatch; holder B DMN=0 | 0x07647f4a4cf803214ea60948a9b4207147cf9a495be531ee4b93ac560d557255 | PASS |
| F5a.1b | The LAUNCH-DAY form of the check: eth_call claim(1.00 B) from a real holder that never approved (holder A), the DMX allowance supplied by --override-state-diff on slot keccak(migration . keccak(holder . 7)) | reverts with AmountMismatch exactly like the mined approve + claim above; nothing mined, the real allowance untouched | real allowance before=0; claim: reverted with AmountMismatch; holder A DMN=0; real allowance after=0 | - | PASS |
| F5a.2 | Why the owner can claim now: its status on the REAL DMX | owner() == the DMX owner (cap-exempt as sender), isExcludedFromFee(owner) true; the Timelock NOT exempt (11b not done); cap 1.5B (11a not done) | owner=0xF8EC459CAEaF1052b64B38BDD67290B0c132B0Ae, isExcludedFromFee(owner)=true, isExcludedFromFee(timelock)=false, _maxTxAmount=1.5000 B | - | PASS |
| F5a.3 | Sizing from live values: the REAL DMX pool on the fork; the largest single addLiquidityETH under the DMN maxTx (decision (c)) | price = DMX pool WBNB reserve x 1e18 / DMX reserve; BNB leg = net(maxTx) x price, floored to 0.001 BNB; net target = BNB x 1e18 / price; gross = ceil(net x 1000 / 960); pair receives >= net target by < 1000 wei; gross <= maxTx | DMX pool reserves DMX=76394917263158812489516157516 (76.3949 B), WBNB=35996660568812417183 (35.996660 BNB) -> DMX price=471191826 wei/token (0.000000000471191826 BNB); DMN maxTx=5.0000 B -> net 4.8000 B; BNB leg=2.261000 BNB (2261000000000000000 wei); net target=4798470336792302504840141263; gross=4998406600825315109208480483 (4.9984 B); net of gross=4798470336792302504840141265 (+2 wei) | - | PASS |
| F5a.4 | Funding preview, BEFORE the owner claims: can the owner's REAL balance fund 5b? | owner BNB >= BNB leg + 0.002 BNB gas reserve | owner=0.096153 BNB; needed=2.263000 (leg 2.261000 + reserve 0.002000); SHORT by 2.166846 BNB | - | FINDING |
| F5a.5 | Step 5a: the owner approves and claims EXACTLY the gross, on the REAL DMX | exact 1:1 on every leg: Timelock DMX +gross, owner DMX -gross, owner DMN +gross, migratedAmount == gross | Timelock DMX +4998406600825315109208480483, owner DMX -4998406600825315109208480483, owner DMN +4998406600825315109208480483, migratedAmount=4998406600825315109208480483 (gross 4998406600825315109208480483); claim gas=284476 | 0x6e476e17231f721f278c4166590764afb9c461459c46b9742ec0030dff8aea49 / 0xb9cf5ea584bc5ff0d45311e2679f900df763cd070bd1ea509e2d65fd682b227c | PASS |

### F5b (run G) -- Step 5b: initial liquidity on the REAL router at the REAL DMX price

| step | action | expected | observed | tx | verdict |
|---|---|---|---|---|---|
| F5b.0 | GATE: the owner's REAL BNB against the 5b requirement | owner BNB >= BNB leg + gas reserve, or STOP | owner=0.096136 BNB (96136855983002775 wei); leg=2.261000, reserve=0.002000, needed=2.263000; SHORTFALL=2.166863 BNB (2166863144016997225 wei) | - | STOP |
| F5b.0b | SETUP DEVIATION, by the operator's switch -FundOwnerForLiquidity: the fork adds EXACTLY the BNB leg to the owner (anvil_setBalance); every gas cost from here is still paid out of the owner's real balance | owner = real balance + leg; the continuation measures what the owner really needs | owner 0.096136 -> 2.357136 BNB (+2.261000) | - | NOTE |
| F5b.P1 | PROBE (inside evm_snapshot, discarded): a stranger, funded 0.01 BNB by the fork for this probe only, wraps 1 wei, sends it to the EMPTY DMN pair and calls sync(); then the owner's planned addLiquidityETH is simulated | recorded: does a 1-wei donation block the router path? | reserves after sync: DMN=0 WBNB=1; addLiquidityETH: reverted with INSUFFICIENT_LIQUIDITY | 0xf248ece498cdf004721740f55c0360a5463363f5500613de66512fc19ecb2e83 | FINDING |
| F5b.P2 | PROBE, recovery path on the same griefed pair: owner transfers the gross DMN to the pair (taxed, automation idle), wraps the BNB leg, sends WBNB, calls pair.mint(owner) | the pool opens anyway: reserve DMN == net, WBNB == leg + the 1 donated wei, price within 1 ppm of the DMX price; LP minted to the owner | reserves DMN=4798470336792302504840141265 (net 4798470336792302504840141265), WBNB=2261000000000000001 (leg+1 = 2261000000000000001); price=471191826 vs DMX 471191826; LP=104160172002005622471664 | 0x187c824acc3b5b8c11c2515af83bdff8fe9a49c10b465e1411f4d995c927533d | PASS |
| F5b.P3 | PROBE discarded: evm_revert to the snapshot | pair back to (0,0); owner DMN back to the gross; the probe's transactions excluded from every total | reserves=(0,0), owner DMN=4998406600825315109208480483 | - | PASS |
| F5b.1 | Step 5b: approve + addLiquidityETH(token, gross, amountTokenMin = gross, amountETHMin = leg, owner) on the REAL router | reserve DMN == net of gross (exact), reserve WBNB == the leg (no refund); owner DMN back to 0; opening price == the DMX price within 1 ppm (never above: the net is rounded up) | BNB=2261000000000000000 wei (2.261000); DMN gross=4998406600825315109208480483 (4.9984 B); DMN received by the pair: reserve=4798470336792302504840141265, balanceOf=4798470336792302504840141265 (4.7984 B), expected 4798470336792302504840141265; reserve WBNB=2261000000000000000; OPENING PRICE=471191825 wei/token vs DMX 471191826 (diff 1 wei, 0.000000 %); owner DMN after=0; LP minted=104160172002005622471664; gas approve=50973, add=379973 | 0xe0e19e03e299d8c3bec3d1a307a79a93c6485253ce3f1cd8f013d30bd731a3e5 / 0xcf0b32f34d6e3fc3ed3a873b19c711ce4a8a7cfe99e82a2e9d33ec1c62ed3df3 | PASS |

### F6-F8 (run G) -- Step 6: every LP token to the Timelock; step 7: one pool; step 8: reserves non-zero

| step | action | expected | observed | tx | verdict |
|---|---|---|---|---|---|
| F6.1 | Step 6: ALL the LP tokens, owner -> Timelock | owner LP 0, deployer LP 0, Timelock LP == totalSupply - MINIMUM_LIQUIDITY (1000) | moved=104160172002005622471664; owner=0, deployer=0, timelock=104160172002005622471664, totalSupply=104160172002005622472664, MINIMUM_LIQUIDITY=1000; gas=46883 | 0x9ae42c615787987c99e5c722a31c9eb7143e2f089bd54f57cfecf7d1c7b22d6e | PASS |
| F7.1 | Step 7: one pool only; stored pair == factory pair | factory.getPair(DMN, WBNB) == token.uniswapV2Pair; no DMN/USDT or DMN/BUSD pair | stored=0x40A97Ae210a44057603186B4BE92BAe719342AFA, factory=0x40A97Ae210a44057603186B4BE92BAe719342AFA; USDT pair=0x0000000000000000000000000000000000000000, BUSD pair=0x0000000000000000000000000000000000000000 | - | PASS |
| F8.1 | Step 8: reserves non-zero -> automation live | both reserves > 0; the liquidity transfer was taxed: inventory == gross x 3% (plus at most 0.01% reflection) | DMN=4.7984 B, WBNB=2.261000; inventory=149959729762611153315200333 (0.1499 B), 3% of gross=149952198024759453276254414; threshold minimumTokensBeforeSwap=0.2000 B | - | PASS |

### F9-F10 (run G) -- Step 9: the test swap pays exactly 4%; step 10: the first poke

| step | action | expected | observed | tx | verdict |
|---|---|---|---|---|---|
| F9.1 | The owner buys with 0.001 BNB through the real router (it holds no DMN after 5b: the test sell needs a buy first) | the owner receives the net of what left the pair -- amount - floor(1%) - floor(3%) -- plus its own reflection share (< 0.01%) | left the pair=2116038660940306852053568 (0.0021 B); owner received=2031397157695009437060994; net (96%, floors per fee)=2031397114502694577971426 (+43192314859089568 wei); gas=241257 | 0xcf3e4d020e2a3ffb36f5fc6a7f8c25713c804fc2087af5c3827f6617b3378f49 | PASS |
| F9.2 | Step 9: the owner sells half of it through the real router | the pair (balanceOf delta, reward-excluded) receives EXACTLY the net: amount - floor(1%) - floor(3%), i.e. 96% up to the two floors -- fee 4%, not the historical 5%; inventory grows by 3% (+ reflection); no conversion on a router sell (#1): contract BNB 0, Timelock BNB 0 | sold=1015698578847504718530497; pair received=975070635693604529789279 (net=975070635693604529789279, floor(96%)=975070635693604529789277, 95% would be 964913649905129482603972); inventory +30472488805409470477799; BNB back to the owner=0.000458 (458608676268387 wei); contract BNB=0, Timelock BNB=0; gas=194073 | 0x9094433f41d35d2fceebccddafc1503f9328f0620de5f86e8c638ecd17973fd5 / 0x744f1d6193c3263bc31ebeafa5ee1d938f6ae47dc7a1a19329ac3cfc55e78b9d | PASS |
| F10.1 | Step 10: the first poke (1 wei DMN owner -> pair), share 1000 | zero BNB to the Timelock. Recorded: is the inventory above the threshold yet? | inventory=0.1500 B < threshold 0.2000 B: NOTHING converts (inventory after=0.1500 B); staking +0, contract +0, TIMELOCK +0 wei; the first conversion needs 0.0499 B more inventory = about 1.6648 B of further taxed volume; gas=94841 | 0x96cf06bc72953c45287e78cb64c318c554f0ff5b5f0563eeb9606392d1795d27 | FINDING |

> On launch day the first poke is a no-op: the 5b liquidity transfer arms only 3% of ~5B = ~0.15B of inventory, under the 0.2B threshold. The Timelock-receives-nothing property is proven again at the first REAL conversion, which happens later (F10.2 below, after the window opens).

### F11 (run G) -- 11a setMaxTxAmount(full supply), then 11b excludeFromFee(TIMELOCK) -- on the REAL DMX, same session, nothing between

| step | action | expected | observed | tx | verdict |
|---|---|---|---|---|---|
| F11.0 | BEFORE 11a: holder A (real, > 10 B) approves and claims 10.00 B | REVERTS with the real DMX cap message (the cap is checked before any fee logic) | approve mined (holder A's own gas); claim: reverted with Transfer amount exceeds the maxTxAmount. | 0xd3e896cdcb81f0dcff96cd0bf60c4c90bf86f2447571e3a5cf2a9e3fd2af89cc | PASS |
| F11a | Step 11a: setMaxTxAmount(1000000000000 x 1e18) -- a non-owner first (eth_call), then the owner | non-owner refused by Ownable; the owner's call mined; _maxTxAmount == the full supply == totalSupply() | non-owner: reverted with Ownable: caller is not the owner; _maxTxAmount 1.5000 B -> 1000.0000 B (totalSupply 1000.0000 B); logs emitted by the call=0; gas=28742; block 124566939 | 0x376244f1921fcd484b134f411a316cf41f7f30935e4f1a5ca585c36292c0c6c0 | PASS |
| F11b | Step 11b, LAST: excludeFromFee(TIMELOCK) -- the treasury, not the Migration; the window opens | isExcludedFromFee(timelock) true, (migration) false; mined right after 11a with nothing in between | timelock=true, migration=false; logs emitted=0; 11a block 124566939 -> 11b block 124566940; gas=46232 | 0x97ab6f75da75bf776158b0bee8b65213fc82a6445483b61002086e9d55951b75 | PASS |
| F11.x | Events: what an observer sees of 11a and 11b | recorded against the mock (CampaignOldDaimon emits MaxTxAmountUpdated on setMaxTxAmount) | the REAL DMX emitted 0 log(s) on setMaxTxAmount and 0 on excludeFromFee: both are silent -- only the calldata and a storage read show them | - | FINDING |

### F12 (run G) -- After 11b: real third-party holders claim through the open window

| step | action | expected | observed | tx | verdict |
|---|---|---|---|---|---|
| F12.1 | Holder A (real, > 10 B, not the owner, not exempt) repeats the SAME 10.00 B claim (the F11.0 approve still stands) | passes 1:1, no fee: Timelock DMX +10.00 B exactly, holder A DMX -10.00 B exactly, holder A DMN +10.00 B exactly, migratedAmount 10.00 B | Timelock DMX +10000000000000000000000000000, holder A DMX -10000000000000000000000000000, holder A DMN +10000000000000000000000000000, migratedAmount=10000000000000000000000000000 (10.00 B = 10000000000000000000000000000); gas=249104 | 0x8f32e20ce80cd8181c7151de41e0e8d8c881fa51dca4f74a113cde62f2418606 | PASS |
| F12.2 | Holder B (real, below the old cap) claims 1.00 B with the approve of F5a.1 | exact 1:1 on every leg | Timelock DMX +1000000000000000000000000000, holder B DMX -1000000000000000000000000000, holder B DMN +1000000000000000000000000000; gas=249104 | 0x271b79d402a24893793c14fbdf7f7c74285ce9fc2b672454de47cd3e8af12573 | PASS |
| F12.3 | The treasury (= the Timelock) after the day's claims | DMX held == totalMigrated (owner 5a + holder A + holder B) | Timelock DMX=15998406600825315109208480483 (15.9984 B); totalMigrated=15998406600825315109208480483 (15.9984 B); owner 4.9984 B + A 10.0000 B + B 1.0000 B | - | PASS |
| F12.4 | Behaviour the mock does not have: a taxed DMX transfer between two other holders (holder A -> holder B, 0.01 B) after the claims | recorded: does the treasury's DMX move without any claim? | Timelock isExcludedFromReward on DMX=false; Timelock DMX 15998406600825315109208480483 -> 15998413000190515185414554648 (+6399365200076206074165 wei) while totalMigrated stays 15998406600825315109208480483 | 0x8b13a31b93ebb51eafece354f173a6754f392a1dcb408610e9441c4ce76dc36e | FINDING |
| F10.2a | Arming the first conversion with ordinary volume: holder A sends DMN to holder B (a taxed transfer, under the 5B maxTx) | inventory >= threshold afterwards | sent=1.6700 B; inventory=0.2001 B vs threshold 0.2000 B | 0xe081fa1fa9906996316c358886af53d2ce3189c5fdab8f3832fc2e237b949d27 | PASS |
| F10.2 | The first REAL conversion on the REAL router: holder B pokes (1 wei to the pair), share 1000 | one threshold chunk sold; 20/30 of the BNB to staking, 10/30 kept for buyback, ZERO to the Timelock | consumed=0.2000 B (threshold 0.2000 B); received=0.090292 BNB: staking +0.060195 (exp 0.060195), contract +0.030097, TIMELOCK +0 wei; gas=306963 | 0x28b83e97c21b740009c46e63f16431a9868ee5142abc53d9e38703b75717bc0d | PASS |
| F10.3 | THE NUMBER on the real pool: the chunk against the DMN reserve, and the price move | recorded | chunk 0.2000 B vs DMN reserve 4.7973 B = 4.16 %; BNB drawn 0.090292 of 2.261541 = 3.99 %; price 471416744 -> 434481794 wei/token, move -7.83 % | - | NOTE |
| F13.1 | The Timelock at the end of the day | BNB 0 and DMN 0 (share 1000: nothing from the token), every LP token, the claimed DMX | BNB=0, DMN=0, LP=104160172002005622471664 of 104160172002005622472664, DMX=15.9984 B | - | PASS |

### Gas ledger (run G) -- every mined transaction of the day, probes excluded

| step | signer | call | gas used | gas price (wei) | cost (BNB) |
|---|---|---|---|---|---|
| 2 phase 1 | deployer | DeployPhase1.s.sol tx 0 | 3569417 | 50000000 | 0.000178 |
| 2 phase 1 | deployer | DeployPhase1.s.sol tx 1 | 4192820 | 50000000 | 0.000209 |
| 2 phase 1 | deployer | DeployPhase1.s.sol tx 2 | 741438 | 50000000 | 0.000037 |
| 2 phase 2 | deployer | DeployPhase2.s.sol tx 0 | 1013596 | 50000000 | 0.000050 |
| 2 phase 2 | deployer | DeployPhase2.s.sol tx 1 | 1825591 | 50000000 | 0.000091 |
| 2 phase 2 | deployer | DeployPhase2.s.sol tx 2 | 1510972 | 50000000 | 0.000075 |
| 2 phase 2 | deployer | DeployPhase2.s.sol tx 3 | 51213 | 50000000 | 0.000002 |
| 2 phase 2 | deployer | DeployPhase2.s.sol tx 4 | 51213 | 50000000 | 0.000002 |
| 2 phase 2 | deployer | DeployPhase2.s.sol tx 5 | 51213 | 50000000 | 0.000002 |
| 2 phase 2 | deployer | DeployPhase2.s.sol tx 6 | 29640 | 50000000 | 0.000001 |
| 2 phase 2 | deployer | DeployPhase2.s.sol tx 7 | 29640 | 50000000 | 0.000001 |
| 2 phase 2 | deployer | DeployPhase2.s.sol tx 8 | 47896 | 50000000 | 0.000002 |
| 2 phase 2 | deployer | DeployPhase2.s.sol tx 9 | 23984 | 50000000 | 0.000001 |
| 2 phase 2 | deployer | DeployPhase2.s.sol tx 10 | 97349 | 50000000 | 0.000004 |
| 2 phase 2 | deployer | DeployPhase2.s.sol tx 11 | 36062 | 50000000 | 0.000001 |
| 2 phase 2 | deployer | DeployPhase2.s.sol tx 12 | 46173 | 50000000 | 0.000002 |
| 2 phase 2 | deployer | DeployPhase2.s.sol tx 13 | 56384 | 50000000 | 0.000002 |
| 2 phase 2 | deployer | DeployPhase2.s.sol tx 14 | 33478 | 50000000 | 0.000001 |
| 2 phase 2 | deployer | DeployPhase2.s.sol tx 15 | 24541 | 50000000 | 0.000001 |
| 5a check | holder B | approve(address,uint256) | 46328 | 50000000 | 0.000002 |
| 5a | owner | approve(address,uint256) | 46364 | 50000000 | 0.000002 |
| 5a | owner | claim(uint256) | 284476 | 50000000 | 0.000014 |
| 5b | owner | approve(address,uint256) | 50973 | 50000000 | 0.000002 |
| 5b | owner | addLiquidityETH(address,uint256,uint256,uint256,address,uint256) | 379973 | 50000000 | 0.000018 |
| 6 | owner | transfer(address,uint256) | 46883 | 50000000 | 0.000002 |
| 9 buy | owner | swapExactETHForTokensSupportingFeeOnTransferTokens(uint256,address[],address,uint256) | 241257 | 50000000 | 0.000012 |
| 9 sell | owner | approve(address,uint256) | 50949 | 50000000 | 0.000002 |
| 9 sell | owner | swapExactTokensForETHSupportingFeeOnTransferTokens(uint256,uint256,address[],address,uint256) | 194073 | 50000000 | 0.000009 |
| 10 poke | owner | transfer(address,uint256) | 94841 | 50000000 | 0.000004 |
| 11 check | holder A | approve(address,uint256) | 46328 | 50000000 | 0.000002 |
| 11a | owner | setMaxTxAmount(uint256) | 28742 | 50000000 | 0.000001 |
| 11b | owner | excludeFromFee(address) | 46232 | 50000000 | 0.000002 |
| 12 claim A | holder A | claim(uint256) | 249104 | 50000000 | 0.000012 |
| 12 claim B | holder B | claim(uint256) | 249104 | 50000000 | 0.000012 |
| 12 reflection | holder A | transfer(address,uint256) | 87154 | 50000000 | 0.000004 |
| 10 again arm | holder A | transfer(address,uint256) | 109100 | 50000000 | 0.000005 |
| 10 again poke | holder B | transfer(address,uint256) | 306963 | 50000000 | 0.000015 |

### F14 (run G) -- Gas and BNB: what the day actually cost (complete through 11b and the post-window claims)

| step | action | expected | observed | tx | verdict |
|---|---|---|---|---|---|
| F14.1 | DEPLOYER: total spent, from its balance (start - end) and from the ledger | the two phases only (19 transactions); start 0.2 BNB exactly; spent == sum of gas x price | start=0.200000, end=0.199328, spent=0.000671 BNB (671631000000000 wei); ledger: 19 txs, gas 13432620, cost 0.000671; at 1 gwei the same gas would cost 0.013432, at 3 gwei 0.040297; headroom left of the 0.2 BNB plan: 0.199328 | - | PASS |
| F14.2 | DMX OWNER: total spent | spent == gas + BNB into the pool + test buy - test sell proceeds | real start=0.096153, fork top-up=2.261000, end=0.095538, spent=2.261614 BNB; of which gas=0.000073 (11 txs, gas 1464763; at 1 gwei 0.001464, at 3 gwei 0.004394), liquidity=2.261000, test buy=0.001000, test sell back=0.000458 | - | PASS |
| F14.3 | Third-party holders: gas paid from their own real balances | their own claims only, never funded by the fork | holder A: 4 txs, 0.000024 BNB; holder B: 3 txs, 0.000030 BNB | - | NOTE |

Run G verdicts: PASS 30, NOTE 4, FINDING 5, STOP 1, DEVIATION 0; launch invariant asserted after 27 sends; local-fork guard passed 36 times.

## Closure (2026-09-28)

Seven runs, one fork each, all from fresh mainnet state:

| run | upstream | fork block | owner BNB | how it ended |
|---|---|---|---|---|
| A | publicnode | 124563923 | real | STOP at F1.0: pruned state (the plan's stop condition) |
| B | blastapi | 124565466 | real | harness DEVIATION at F2.3 (annotated), ended there |
| C | blastapi | 124565662 | real | **the faithful run**: STOP at 5b, owner short by 2.166863 BNB |
| D | blastapi | 124565863 | +leg at 5b | through 11b; harness DEVIATION at F9.2 (annotated) |
| E | blastapi | 124566248 | +leg at 5b | through 11b, clean |
| F | blastapi | 124566656 | +leg at 5b | through 11b; harness DEVIATION at F5a.1b (annotated) |
| G | blastapi | 124566908 | +leg at 5b | **the reference run**: through 11b, 30 PASS, 0 DEVIATION |

Every DEVIATION was the harness's own assert, annotated under its row; no
launch expectation failed. Runs D-G reproduced each other to the wei (the
DMX pool did not trade between them).

Findings the launch must absorb (all carried into LAUNCH_DAY.md):

1. The DMX owner holds 0.096153 BNB; step 5b needs the 2.261 BNB leg at the
   live DMX price (4.71191826e-10 BNB/token): short by 2.1669 BNB (C F5a.4,
   C F5b.0). The faithful run stopped there, after 5a had already been
   claimed -- so the funding check belongs BEFORE phase 1 (LAUNCH_DAY P4).
2. Public full nodes serve only ~60-128 blocks of state; a fork rehearsal
   needs an endpoint that serves history (A F1.0). Launch day itself is
   unaffected (it reads the head).
3. A 1-wei WBNB donation + sync() to the empty DMN pair makes
   addLiquidityETH revert (F5b.P1). The direct transfer + mint path still
   opens the pool at the right price (F5b.P2), but as separate transactions
   it exposes both legs to skim() until mint: on mainnet it must be atomic.
   (Analysis added at closure: the probe ran without an adversary, so the
   skim race itself is not in any row.)
4. The first poke of the day converts nothing: 0.15 B inventory against a
   0.2 B threshold; about 1.66 B of taxed volume arms the first conversion
   (F10.1). When it came, the Timelock received zero and the price moved
   -7.83 % on the launch pool (F10.2, F10.3), as the checklist estimated.
5. 11a and 11b emit no event on the real DMX (F11.x).
6. The Timelock accrues DMX reflections: its DMX balance exceeds
   totalMigrated after any taxed DMX transfer (F12.4).
7. MIGRATION_DURATION is set by no document; unset, phase 1 uses 30 days.
8. A launch-day proof that a non-owner claim reverts needs no holder
   signature: eth_call with --override-state-diff on DMX slot 7 (G F5a.1b);
   plain --override-state wipes DMX's storage (F F5a.1b annotation).

Real funding, measured: the deployer spends 0.000672 BNB at 0.05 gwei
(13,432,620 gas; 0.2 BNB covers it even at 3 gwei), the owner 0.000073 BNB
of gas (1,464,763 gas) plus the 2.261 BNB leg plus 0.000542 net for the
test swap (G F14.1, G F14.2).

Nothing was broadcast to the real network: every send passed the
local-fork guard (36 checks in run G alone) and no private key was loaded.
The fork artifacts (two-phase-56.json, the chain-56 broadcast journals,
anvil logs) were moved to script/fork/out/ (gitignored) at the end of each
run, so nothing stale is left for launch day.
