# Deploy on BSC Testnet — Daimon DAO

Step-by-step guide to deploy the entire stack (DaimonV2 token + staking +
governor + timelock + migration + mock of the old Daimon) on BSC testnet
(chain id 97) with Foundry.

## What the script does

[script/Deploy.s.sol](script/Deploy.s.sol) deploys, in a single run:

1. **MockOldDaimon** — replica of the old token with a 5% fee, the entire
   old-supply to the deployer (to test the migration). Skipped if you set
   `OLD_DAIMON` in the environment.
2. **DaimonV2** implementation + **ERC1967 proxy** with an atomic
   `initialize()`. The `_migrationContract` passed to initialize is the **real
   DaimonMigration**, whose address is precomputed from the deployer's CREATE
   nonce: the entire supply is born already inside the migration contract,
   excluded from fees, without ever passing through an EOA.
3. **DaimonStaking**, **DaimonTimelock** (minDelay 7 days), **DaimonGovernor**
   (quorum 10%, threshold 1000 DMN), **DaimonMigration** (30-day window,
   configurable).
4. **Full wiring**: governor = proposer + executor of the timelock, timelock =
   governance of the token and staking, and a **final renounce of all the
   deployer's bootstrap roles** (including the timelock's ADMIN_ROLE).
5. **Final on-chain asserts**: the script fails if an EOA still holds an
   administrative role or if the supply is not entirely in the migration.

> The guardian keeps only pause (token) and cancel (timelock/governor), by
> design. On testnet it can be the deployer; **in production it must be a
> multisig**, and treasury/marketing wallet dedicated addresses.

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
`GUARDIAN_ADDRESS`, `MARKETING_WALLET`, `TREASURY_ADDRESS`,
`ETHERSCAN_API_KEY`, `OLD_DAIMON`, `MIGRATION_DURATION`. If you leave them
empty the script uses the deployer and logs a warning (acceptable on testnet
only).

## 4. Simulation (recommended before deploy)

The command without `--broadcast` runs everything in simulation against the
real chain (including the calls to the PancakeSwap testnet router and the
final asserts), **without sending anything**:

```sh
forge script script/Deploy.s.sol:Deploy --rpc-url bsc_testnet --account daimon-deployer -vvv
```

Check in the log the expected addresses and that the confirmation that all
decentralization asserts passed appears.

## 5. Real deploy

```sh
forge script script/Deploy.s.sol:Deploy `
  --rpc-url bsc_testnet `
  --account daimon-deployer `
  --broadcast `
  --verify `
  -vvv
```

(In bash replace the backticks with `\`. With option B use `--private-key ...`
instead of `--account ...`.)

- `--broadcast` sends the transactions.
- `--verify` automatically verifies all the contracts on BscScan testnet at
  the end (requires `ETHERSCAN_API_KEY` in the environment, see below).
- The deployed addresses are printed at the end of the script and saved in
  `broadcast/Deploy.s.sol/97/run-latest.json`.

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
`broadcast/Deploy.s.sol/97/run-latest.json`. On BscScan, after verifying the
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
