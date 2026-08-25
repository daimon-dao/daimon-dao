# Deploy on BSC Testnet — Daimon DAO

Step-by-step guide to deploy the entire stack (DaimonV2 token + staking +
governor + timelock + migration + mock of the old Daimon) on BSC testnet
(chain id 97) with Foundry.

## What the scripts do

The deploy is **two separate broadcasts**, run one after the other. The
reason: the token's `guardianExpiry` is computed by `initialize()` from the
block the proxy is MINED in, while a single-run script fixes the value it
passes to the Timelock/Governor constructors during simulation — on a live
chain the two skew by the simulation-to-inclusion delay. Phase 2 starts
after the token is mined and reads the expiry from live chain state, so the
three copies are identical by construction.

**Phase 1 — [script/DeployPhase1.s.sol](script/DeployPhase1.s.sol):**

1. **MockOldDaimon** — replica of the old token with a 5% fee, the entire
   old-supply to the deployer (to test the migration). Skipped if you set
   `OLD_DAIMON` in the environment.
2. **DaimonV2** implementation + **ERC1967 proxy** with an atomic
   `initialize()`. The `_migrationContract` passed to initialize is the **real
   DaimonMigration**, whose address is precomputed from the deployer's CREATE
   nonce: the entire supply is born already inside the migration contract,
   excluded from fees, without ever passing through an EOA.
3. **DaimonMigration** (30-day window, configurable) — the LAST transaction
   of phase 1, with its immutable `governance` AND its immutable `treasury`
   both bound to the PREDICTED timelock address (the deployer's next
   CREATE): the treasury IS the Timelock, derived rather than typed, and
   `TREASURY_ADDRESS` no longer exists (rehearsals may set
   `TESTNET_TREASURY_OVERRIDE` — loudly logged, refused on chain 56).
   Phase-1 asserts (10), then the addresses and expected nonce are written
   to `deployments/two-phase-<chainid>.json` — deliberately no expiry value.
   Note the predecessor fee exemption is NOT performed here: without it
   `claim()` reverts with `AmountMismatch` (#29), which keeps the migration
   inert until the deployment is verified — see step 4 below.

⚠️ **Between the phases, send NOTHING from the deployer**: a nonce change
makes the predicted timelock address unreachable and phase 2 refuses to run.
If that happens, abandon the phase-1 contracts and rerun phase 1 fresh:
the predecessor fee exemption is not yet in place, so no claim can have
occurred -- the cost is gas only.

**Phase 2 — [script/DeployPhase2.s.sol](script/DeployPhase2.s.sol):**

4. **Preflight** (before broadcasting anything): the live chain must match
   the state file — right chain and deployer, nonce untouched, code in
   place, none at the predicted timelock address, supply in the migration.
   Then it reads `token.guardianExpiry()` **from the live token** — the only
   source; no file and no human ever carries the value.
5. **DaimonTimelock** (minDelay 7 days; must land on the predicted address),
   **DaimonStaking**, **DaimonGovernor** (quorum 10%, threshold 1000 DMN).
6. **Full wiring**: governor = proposer + executor + canceller of the
   timelock, timelock = governance of the token and staking,
   `stakingRewardShareBps = 1000` (launch compliance), and a **final
   renounce of all the deployer's bootstrap roles** (including the
   timelock's ADMIN_ROLE). Phase-2 asserts (20). If interrupted
   mid-broadcast, resume with `--resume` — a fresh rerun would refuse.

**Post-broadcast verification — [script/verify-deploy.ps1](script/verify-deploy.ps1):**
the mandatory final gate. The in-script asserts run in the simulation
context; this runner re-reads 34 invariants from MINED state through plain
`eth_call`, including the guardian expiry EXACTLY equal across the three
contracts and the migration treasury being the Timelock, and exits non-zero
on any failure.

> The guardian keeps only pause (token) and cancel (timelock/governor), by
> design. On testnet it can be the deployer; **in production it must be a
> multisig**, with a dedicated marketing wallet. The migration treasury is
> derived -- it IS the Timelock -- and is not an address you choose.

## 1. Prerequisites

- Foundry installed (`forge --version`). If missing: download
  `foundry_stable_win32_amd64.zip` from the releases at
  https://github.com/foundry-rs/foundry and put the binaries in the PATH, or
  on Linux/macOS: `curl -L https://foundry.paradigm.xyz | bash && foundryup`
- Project dependencies already in `lib/` (`forge build` must pass).

## 2. BNB testnet from the faucet

1. Create/use a wallet **dedicated to the testnet deploy** (never the main
   wallet).
2. Go to the official BNB Chain faucet:
   **https://www.bnbchain.org/en/testnet-faucet** (requires a GitHub login or
   a small BNB balance on mainnet depending on the period). Alternatively:
   https://faucet.quicknode.com/binance-smart-chain/bnb-testnet
3. Request tBNB for the deployer address. The full deploy uses ~14.6M gas
   (measured in simulation): from 0.0015 tBNB at 0.1 gwei up to ~0.15 tBNB if
   the testnet runs at 10 gwei. With **0.5 tBNB** you are amply covered.
4. Check the balance:
   ```sh
   cast balance <DEPLOYER_ADDRESS> --rpc-url bsc_testnet
   ```

## 3. Private key, securely

**The key must NEVER be hardcoded in versioned files, nor passed in the clear
on the command line** (it would end up in the shell history).

### Option A — encrypted keystore (recommended)

```sh
cast wallet import daimon-deployer --interactive
```

It asks for the private key (hidden input) and a password; it saves it
encrypted in `~/.foundry/keystores/daimon-deployer`. From then on you use
`--account daimon-deployer` and Foundry asks for the password at use time. The
key never touches project files or history.

### Option B — environment variable

Copy `.env.example` to `.env` (already in `.gitignore`), fill in
`PRIVATE_KEY=0x...`, then load it into the shell **for the session only**:

```powershell
# PowerShell
Get-Content .env | Where-Object {$_ -match '^\w+='} | ForEach-Object { $k,$v = $_ -split '=',2; Set-Item "env:$k" $v }
```
```sh
# bash
source .env
```

Then you will use `--private-key $env:PRIVATE_KEY` (PowerShell) or
`--private-key $PRIVATE_KEY` (bash) instead of `--account`.

### Role configuration (optional on testnet)

In the same `.env` (or as environment variables) you can set
`GUARDIAN_ADDRESS`, `MARKETING_WALLET`, `ETHERSCAN_API_KEY`, `OLD_DAIMON`,
`MIGRATION_DURATION`. If you leave them empty the script uses the deployer
and logs a warning (acceptable on testnet only). There is NO treasury
variable: the migration treasury is derived (it IS the Timelock).
`TESTNET_TREASURY_OVERRIDE` exists for rehearsals only -- loudly logged,
refused on chain 56.

## 4. Simulation (recommended before deploy)

The command without `--broadcast` runs phase 1 in simulation against the
real chain (including the calls to the PancakeSwap testnet router),
**without sending anything**:

```sh
forge script script/DeployPhase1.s.sol:DeployPhase1 --rpc-url bsc_testnet --account daimon-deployer -vvv
```

Check in the log the expected addresses. (Phase 2 cannot be simulated before
phase 1 has actually been broadcast: its preflight reads the live chain.)

## 5. Real deploy

**Phase 1:**

```sh
forge script script/DeployPhase1.s.sol:DeployPhase1 `
  --rpc-url bsc_testnet `
  --account daimon-deployer `
  --broadcast `
  --verify `
  -vvv
```

Wait for mining, then — **without sending anything else from the deployer** —

**Phase 2** (no extra environment needed: everything comes from the state
file, cross-checked against the live chain):

```sh
forge script script/DeployPhase2.s.sol:DeployPhase2 `
  --rpc-url bsc_testnet `
  --account daimon-deployer `
  --broadcast `
  --verify `
  -vvv
```

**Verification gate:**

```sh
powershell -File script/verify-deploy.ps1 -Rpc <your-rpc-url>
```

**Step 4 — ONLY after the verification is green: open the migration.**
The predecessor fee exemption is what makes claims possible (without it,
`claim()` reverts with `AmountMismatch`, #29), so it goes last, after the
deployment is verified:

```sh
cast send <OLD_DAIMON> "excludeFromFee(address)" <TIMELOCK> --rpc-url bsc_testnet --account <old-token-owner>
```

The immutable migration deadline started at phase 1; claims open here — a
difference of minutes against a window of months, accepted deliberately.

(In bash replace the backticks with `\`. With option B use `--private-key ...`
instead of `--account ...`.)

- `--broadcast` sends the transactions.
- `--verify` automatically verifies all the contracts on BscScan testnet at
  the end (requires `ETHERSCAN_API_KEY` in the environment, see below).
- The deployed addresses are printed at the end of each phase, saved in
  `broadcast/DeployPhase1.s.sol/97/run-latest.json` and
  `broadcast/DeployPhase2.s.sol/97/run-latest.json`, and collected in
  `deployments/two-phase-97.json`.

## 6. Verification on BscScan testnet

### Automatic

With `--verify` in the deploy command nothing else is needed. The API key is a
single Etherscan V2 key (valid for BscScan too): create it at
https://etherscan.io/apis and set it as `ETHERSCAN_API_KEY`.

### Manual (if automatic verification fails)

The compiler settings (solc 0.8.26, optimizer, `via_ir`, `evm_version
shanghai`) are read from foundry.toml automatically. Examples:

```sh
# Token implementation (no constructor arg)
forge verify-contract <IMPL_ADDRESS> src/DaimonV2.sol:DaimonV2 --chain 97 --watch

# Proxy (constructor: implementation + initData)
forge verify-contract <PROXY_ADDRESS> lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy `
  --chain 97 --watch `
  --constructor-args $(cast abi-encode "constructor(address,bytes)" <IMPL_ADDRESS> <INIT_DATA>)

# Staking (constructor: token, temporary governance = deployer)
forge verify-contract <STAKING_ADDRESS> src/DaimonStaking.sol:DaimonStaking --chain 97 --watch `
  --constructor-args $(cast abi-encode "constructor(address,address)" <PROXY_ADDRESS> <DEPLOYER>)
```

`<INIT_DATA>` is the calldata of `initialize(...)`: you find it in the
`arguments`/`transaction.input` field of the proxy inside
`broadcast/DeployPhase1.s.sol/97/run-latest.json`. On BscScan, after verifying the
proxy use "More Options → Is this a proxy?" to link the implementation ABI.

## 7. Post-deploy smoke test

```sh
# Is the supply all in the migration?
cast call <PROXY> "balanceOf(address)(uint256)" <MIGRATION> --rpc-url bsc_testnet
cast call <PROXY> "totalSupply()(uint256)" --rpc-url bsc_testnet

# Does the deployer no longer have roles? (GOVERNANCE_ROLE)
cast call <PROXY> "hasRole(bytes32,address)(bool)" $(cast keccak "GOVERNANCE_ROLE") <DEPLOYER> --rpc-url bsc_testnet
```

### Full migration test

The deployer holds the entire old-supply of the MockOldDaimon:

```sh
# 1. (optional) distribute old tokens to a test wallet
cast send <OLD_DAIMON> "transfer(address,uint256)" <TESTER> 1000000000000000000000 `
  --rpc-url bsc_testnet --account daimon-deployer

# 2. the tester approves the migration on the old token
cast send <OLD_DAIMON> "approve(address,uint256)" <MIGRATION> 1000000000000000000000 `
  --rpc-url bsc_testnet --account <TESTER_ACCOUNT>

# 3. claim 1:1
cast send <MIGRATION> "claim(uint256)" 1000000000000000000000 `
  --rpc-url bsc_testnet --account <TESTER_ACCOUNT>

# 4. check the received DaimonV2 balance (must be exactly 1:1)
cast call <PROXY> "balanceOf(address)(uint256)" <TESTER> --rpc-url bsc_testnet
```

Note: the script has already performed the preparatory step
`oldToken.excludeFromFee(treasury)`; without it, `claim()` would revert with
`AmountMismatch` (a by-design protection against unexpected fees).

## Network references

| | |
|---|---|
| Chain id | 97 |
| RPC | https://data-seed-prebsc-1-s1.binance.org:8545 (alias `bsc_testnet` in foundry.toml) |
| Explorer | https://testnet.bscscan.com |
| PancakeSwap V2 Router | `0xD99D1c33F9fC3444f8101754aBC46c52416550D1` |
| Faucet | https://www.bnbchain.org/en/testnet-faucet |
