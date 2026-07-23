<div align="center">

<img src="social-assets/logo-512.png" alt="Daimon DAO" width="140" />

# Daimon DAO

**No owner. No mint. Floor 21B. — DAO on BNB Chain**

</div>

---

Daimon is a BEP-20 token with reflection, vote-escrow staking, on-chain
governance and a public timelock, on BNB Chain / PancakeSwap. No owner, no
mint function, an immutable supply floor at 21 billion: everything is
verifiable on-chain, and the deployer renounces every role after deploy.

## Key properties

- **No owner, no mint.** Control belongs to the DAO via the Timelock; the
  deployer holds no role after deploy (verified on-chain and by the
  invariants).
- **Immutable 21B floor.** The supply can only decrease (deflationary burn)
  and never below `MIN_SUPPLY`, enforced at the code level.
- **Public 7-day timelock** on every governance action — a reaction window
  for the community, valid for the DAO itself too.
- **Vote-escrow.** Voting power derives only from tokens locked over time,
  snapshotted at the proposal's creation (no flash-loan governance).

## Contracts (`src/`)

| Contract | Role |
|---|---|
| `DaimonV2` | BEP-20 token: reflection, autonomous fees, buyback&burn, 21B floor (UUPS) |
| `DaimonStaking` | Vote-escrow staking, checkpoint-based voting power, BNB rewards |
| `DaimonGovernor` | Governance: propose → vote → queue → execute, snapshot-based quorum |
| `DaimonTimelock` | Timelock hardcoded to 7 days on every execution |
| `DaimonMigration` | 1:1 migration from the old token, post-deadline sweep to the treasury |

## Status

Contracts deployed and verified on **BSC testnet**; test suite (unit + fuzz +
invariant + adversarial, **74 tests green**) and Slither static analysis
performed. **Not yet subjected to an external professional audit** — the
mainnet deploy will happen only after the audit.

## Documentation

- [THREAT_MODEL.md](THREAT_MODEL.md) — threat model, actors, defenses, known
  limits and design choices
- [SECURITY.md](SECURITY.md) — how to report vulnerabilities (responsible
  disclosure)
- [TESTNET_RESULTS.md](TESTNET_RESULTS.md) — results of the end-to-end tests
  on the live testnet
- [AUDIT_BRIEF.md](AUDIT_BRIEF.md) — orientation for the auditor (frozen scope
  tag)
- [DEPLOY.md](DEPLOY.md) — deploy procedure
- [daimon-dapp/](daimon-dapp/) — the official dApp (Next.js + wagmi), with its
  own [README](daimon-dapp/README.md)

## Security

Found a vulnerability? **Do not open a public issue.** Use the private channel
(GitHub → Security → Report a vulnerability) — details in
[SECURITY.md](SECURITY.md).

## Build & test

```sh
forge build
forge test
```

The project requires `via_ir = true` (the reflection math hits "stack too
deep" without it) and EVM `shanghai` for BSC. See `foundry.toml`.
