# Audit brief — Daimon DAO

Orientation document for the auditor. The **frozen scope** is the tag
**[`audit-scope-v2`](https://github.com/daimon-dao/daimon-dao/releases/tag/audit-scope-v2)**
— the same contracts as `audit-scope-v1` with **byte-identical bytecode**, and
comments/natspec translated to English. Check out that tag: it is the
definitive state of the contracts.

```sh
git fetch --tags
git checkout audit-scope-v2
forge build && forge test
```

> Note: `audit-scope-v1` remains as a historical marker. `v2` differs from
> `v1` only in code comments/natspec — the compiled bytecode of all five
> contracts is identical (verified with `bytecode_hash=none`).

## Scope (in audit)

The five contracts in `src/`:

| Contract | Description |
|---|---|
| `DaimonV2.sol` | Reflection BEP-20 token (RFI), autonomous fees + buyback&burn, 21B floor, UUPS upgradeable, AccessControl |
| `DaimonStaking.sol` | Vote-escrow staking, checkpoint-based voting power (binary search), MasterChef-style BNB rewards |
| `DaimonGovernor.sol` | Governance: propose → vote → queue → execute, snapshot-based quorum |
| `DaimonTimelock.sol` | Timelock with a hardcoded `MIN_DELAY` = 7 days |
| `DaimonMigration.sol` | 1:1 migration from the old token, post-deadline sweep to the treasury |

Out of scope: `src/mocks/`, `test/`, `script/`, the dApp (`daimon-dapp/`),
and the `lib/` dependencies (OpenZeppelin v5.4.0, assumed correct).

## Build constraints

- `via_ir = true` is **required** (the reflection math hits "stack too deep"
  without it), `evm_version = shanghai` (BSC), `solc 0.8.26`. See
  `foundry.toml`.

## Trust model and known limits

Full document in **[THREAT_MODEL.md](THREAT_MODEL.md)**. In short:

- **No owner, no mint.** Control belongs to the Timelock (7-day delay); the
  deployer renounces every role (asserts in the script + invariant tests).
  No `DEFAULT_ADMIN_ROLE`; `GOVERNANCE_ROLE` self-administers.
- **Immutable 21B floor**, supply strictly decreasing.
- **Fee destinations** (`marketingWallet`, `stakingContract`, split) are all
  `onlyRole(GOVERNANCE_ROLE)`; `deadAddress` is `constant`, the migration
  `treasury` is `immutable`. No EOA path.
- **Accepted limit — UUPS upgrade:** the DAO can replace the token logic
  (only via Timelock + delay). An explicit trade-off between upgradability
  and absolute immutability.

## Result of the pre-freeze adversarial round

Details in **[TESTNET_RESULTS.md](TESTNET_RESULTS.md)** (Test 10). Two
governance findings (no loss of funds):

- **Finding 1 — FIXED.** Quorum counted against-votes
  (`for+against+abstain`), creating a perverse incentive: opposing could push
  a proposal over quorum and pass it. Quorum is now `for+abstain` (against
  excluded), aligned with OpenZeppelin `GovernorCountingSimple`. Regression
  covered by tests (`test/Adversarial.t.sol`).
- **Finding 2 — ACCEPTED and documented.** Voting power does not decay after
  lock expiry (rewards historical lockers, differs from ve-tokens). A
  conscious v1 design choice; a decay is phase-2 governance material. See
  THREAT_MODEL §3.6.

## Test coverage

**74 tests green** (`forge test`): unit, governance sequences, fuzz (512
runs), handler-based invariants (256 × 64), and the targeted adversarial
suite (snapshot/whale, boundary values, incentives, reflection edge). Slither
static analysis performed — notes on findings in THREAT_MODEL §4.

## Areas deserving particular attention

- The RFI reflection math (`_getRate`/`_getValues`/`_getCurrentSupply`), dust
  and wei-level conservation; interaction with `deadAddress` (the only
  reward-excluded account) and with the contract itself as a holder.
- The fee-swap → marketing/staking distribution and buyback&burn path against
  the **real** pool under real slippage (exercised in the lab on testnet).
- Governance timing: voting-power snapshot, snapshot-based quorum, Timelock
  delay at the boundaries.

## Status

Deployed and verified on **BSC testnet**; **not yet** on mainnet — the
mainnet deploy will happen only after this audit (checklist in
[CHECKLIST_MAINNET.md](CHECKLIST_MAINNET.md)).

## Reporting

Vulnerabilities: private GitHub channel (**Security → Report a
vulnerability**), see [SECURITY.md](SECURITY.md). Do not open public issues.
