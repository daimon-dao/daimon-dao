<div align="center">

<img src="social-assets/logo-512.png" alt="Daimon DAO" width="140" />

# Daimon DAO

**No owner. No mint. Floor 21B. — DAO on BNB Chain**

**[📄 Whitepaper v0.1 (EN)](https://github.com/daimon-dao/daimon-dao/releases/download/whitepaper-v0.1/Daimon_Whitepaper_EN_v0.1.pdf)** · [versione italiana](https://github.com/daimon-dao/daimon-dao/releases/download/whitepaper-v0.1/Daimon_Whitepaper_IT_v0.1.pdf) · [release](https://github.com/daimon-dao/daimon-dao/releases/tag/whitepaper-v0.1)

**[🛡️ Zenith Audit Report (Aug 2026)](https://github.com/zenith-security/reports/blob/main/reports/Daimon%20DAO%20-%20Zenith%20Audit%20Report.pdf)** — full report published: 37 findings, all resolved (29 fixed in code, 8 accepted with rationale). Audited reference frozen at tag [`audit-final`](https://github.com/daimon-dao/daimon-dao/releases/tag/audit-final).

</div>

---

Daimon is a BEP-20 token with reflection, vote-escrow staking, on-chain
governance and a public timelock, on BNB Chain / PancakeSwap. No owner, no
mint function, an immutable supply floor at 21 billion: everything is
verifiable on-chain, and the deployer renounces every role after deploy.
The Zenith security audit is complete — every finding fixed or accepted
with a written rationale, and the exact audited code range is frozen
forever at tag `audit-final`.

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
invariant + adversarial, **180 tests green**) and Slither static analysis
performed. **External audit by Zenith complete** — the [full report](https://github.com/zenith-security/reports/blob/main/reports/Daimon%20DAO%20-%20Zenith%20Audit%20Report.pdf)
is published and the audited code range is frozen at tag
[`audit-final`](https://github.com/daimon-dao/daimon-dao/releases/tag/audit-final).

## Documentation

- [docs/whitepaper/](docs/whitepaper/) — the whitepaper (EN primary, IT
  translation), with versioning policy and changelog
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

## Official channels

| Channel | Link |
|---|---|
| Telegram — announcements | https://t.me/Daimon_one |
| Telegram — community group (EN) | https://t.me/Daimon_Official_Group |
| Telegram — community group (IT) | https://t.me/Daimon_Official_Italian_Group |
| X (Twitter) | https://x.com/DaimonDAO |
| GitHub | https://github.com/daimon-dao |

Additional official channels will be listed here as they go live. Any channel
not listed here is not official.

**No admin will ever DM you first. Nobody will ever ask for your seed phrase or
private key. Always verify contract addresses on-chain.**

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

## Disclaimer

> Daimon is experimental open-source software provided "as is", without
> warranties. Nothing here is an offer, solicitation, or financial advice;
> statements about future development are intent, not promises. No entity
> operates the protocol and no one is obliged to maintain it; you interact
> directly with immutable smart contracts on a public blockchain, at your
> own risk. Digital assets can lose all value. Use of the software may be
> restricted in your jurisdiction — you are solely responsible for
> compliance with your local laws. Where this text and the deployed code
> disagree, the code is the only authority.
