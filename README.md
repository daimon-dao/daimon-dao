<div align="center">

<img src="social-assets/logo-512.png" alt="Daimon DAO" width="140" />

# Daimon DAO

**No owner. No mint. Floor 21B. — DAO on BNB Chain**

**[📄 Protocol paper v0.2 (EN)](docs/protocol-paper/Daimon_Protocol_Paper_EN_v0.2.pdf)** · [versione italiana](docs/protocol-paper/Daimon_Protocol_Paper_IT_v0.2.pdf) · [changelog](docs/protocol-paper/CHANGELOG.md) · [v0.1 release](https://github.com/daimon-dao/daimon-dao/releases/tag/whitepaper-v0.1)

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

**Live on BNB Smart Chain mainnet since 2026-09-29.** The audited code was
deployed unchanged (`git diff audit-final -- src/` empty) and verified on
BscScan and Sourcify (exact match); the deployer renounced every role in the
same run, and the pool's LP tokens belong to the Timelock. Test suite (unit +
fuzz + invariant + adversarial) **203 tests green** — the 180 of
`audit-final` plus 23 for the launch tooling — and Slither static analysis
performed. **External audit by Zenith complete** — the [full report](https://github.com/zenith-security/reports/blob/main/reports/Daimon%20DAO%20-%20Zenith%20Audit%20Report.pdf)
is published and the audited code range is frozen at tag
[`audit-final`](https://github.com/daimon-dao/daimon-dao/releases/tag/audit-final).

**The migration window is open until 2026-12-28 01:08:44 UTC**
(`migrationDeadline` 1798420124): DMX holders swap 1:1 for DMN on
[app.daimon.money](https://app.daimon.money). Every launch step — each
transaction, each read-back, the deviations and the incident during the
pause — is recorded in the
**[mainnet launch record](docs/MAINNET_LAUNCH_RECORD.md)**.

Before mainnet the launch was rehearsed on BSC testnet — a full governance
cycle in real time, seven real days of timelock included
([CHAPEL_L2_RESULTS.md](CHAPEL_L2_RESULTS.md), 2026-08-28 to 2026-09-10),
then the launch configuration ([docs/CHAPEL_2B_RESULTS.md](docs/CHAPEL_2B_RESULTS.md))
— and on a local fork of BSC mainnet against the real DMX
([docs/MAINNET_FORK_RESULTS.md](docs/MAINNET_FORK_RESULTS.md)).

## Mainnet addresses

BNB Smart Chain, chainId 56. Always verify an address on chain before
interacting; the deploy transactions and the implementation behind the DMN
proxy are in the [launch record](docs/MAINNET_LAUNCH_RECORD.md).

| Contract | Address |
|---|---|
| **DMN** — the token (`DaimonV2`, UUPS proxy) | [`0x160864F9945C52063A7c9f5dcd57C0C89eacbE6a`](https://bscscan.com/address/0x160864F9945C52063A7c9f5dcd57C0C89eacbE6a) |
| Migration (`DaimonMigration`) — DMX → DMN, 1:1 | [`0x76368b60514b145617385847aCFF7b7EA9764725`](https://bscscan.com/address/0x76368b60514b145617385847aCFF7b7EA9764725) |
| Staking (`DaimonStaking`) | [`0xBb596e7308D6C5AED55cEC597D372840Cbe575b1`](https://bscscan.com/address/0xBb596e7308D6C5AED55cEC597D372840Cbe575b1) |
| Governor (`DaimonGovernor`) | [`0x1397a7d25595B718BE6FEEDd42ed5E60F66E16De`](https://bscscan.com/address/0x1397a7d25595B718BE6FEEDd42ed5E60F66E16De) |
| Timelock (`DaimonTimelock`) — the treasury, holds the LP | [`0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891`](https://bscscan.com/address/0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891) |
| PancakeSwap v2 pair DMN/WBNB — the launch pool | [`0x40A97Ae210a44057603186B4BE92BAe719342AFA`](https://bscscan.com/address/0x40A97Ae210a44057603186B4BE92BAe719342AFA) |
| Guardian — Safe multisig, 2-of-3: cancel and 14-day pauses only, until 2029-09-28 | [`0x37F45839765AD3418E29c97d5D92407Ddbf5c7a8`](https://bscscan.com/address/0x37F45839765AD3418E29c97d5D92407Ddbf5c7a8) |
| DMX — the old token, migrating to DMN | [`0x36EbA94407B53c631eE822C219e94580fadd67c7`](https://bscscan.com/address/0x36EbA94407B53c631eE822C219e94580fadd67c7) |

## Status of decisions

The protocol paper is **v0.2**, the post-audit release of 2026-09-11 (the
document was called the whitepaper up to v0.1), and it incorporates the
decisions below. The decision documents remain the detailed record: where
the paper and a decision document differ, the decision document takes
precedence, and the deployed code takes precedence over all of them:

- [docs/TREASURY_POLICY_v1.0.md](docs/TREASURY_POLICY_v1.0.md) — the
  treasury: one governed contract, no operational wallet, what it holds
  and what it will never do
- [docs/DISCLAIMER_TERMS_v0.3_EN.md](docs/DISCLAIMER_TERMS_v0.3_EN.md) —
  legal disclaimer and terms of use (authoritative English text; an
  [Italian courtesy translation](docs/DISCLAIMER_TERMS_v0.3_IT.md) sits
  alongside)
- [docs/CALENDARIO_GOVERNANCE_Q1.md](docs/CALENDARIO_GOVERNANCE_Q1.md) —
  the first quarter of mainnet governance, proposal by proposal, each
  written as a scenario before it exists
- [docs/G1_PROPOSAL.md](docs/G1_PROPOSAL.md) — G1, the first proposal of
  that calendar (the 60/40 split): the exact bytes, the timeline, the
  mainnet-fork rehearsal ([script/g1/](script/g1/)) and how to verify it
  before voting
- [docs/SCENARI_TESTNET.md](docs/SCENARI_TESTNET.md) — the test plan the
  two testnet campaigns executed (kept as the original plan)
- [CHAPEL_L2_RESULTS.md](CHAPEL_L2_RESULTS.md) — the level-2 campaign
  journal: every step, every hash, the campaign closure
- [docs/TEAM_HOLDINGS.md](docs/TEAM_HOLDINGS.md) — the team's holdings and
  the commitment not to sell without 30 days' public notice

## Documentation

- [docs/MAINNET_LAUNCH_RECORD.md](docs/MAINNET_LAUNCH_RECORD.md) — the
  mainnet launch journal: every step, every transaction, the deviations and
  the incident, the migration window
- [docs/protocol-paper/](docs/protocol-paper/) — the protocol paper (EN
  primary, IT translation), with versioning policy, changelog and the PDF
  build script
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
| Website | https://daimon.money |
| dApp | https://app.daimon.money |
| Telegram — announcements | https://t.me/Daimon_one |
| Telegram — community group (EN) | https://t.me/Daimon_Official_Group |
| Telegram — community group (IT) | https://t.me/Daimon_Official_Italian_Group |
| X (Twitter) | https://x.com/DaimonDAO |
| GitHub | https://github.com/daimon-dao |
| IPFS mirror of the dApp (backup of app.daimon.money) | `daimon.blockchain` in Brave (with "Resolve Unstoppable Domains names" on) or with the Unstoppable Domains extension; directly: https://bafybeictizb6xnvzktgnoq5t5e4ifctqnl4rvvcz3gezpje43an4y5mrki.ipfs.inbrowser.link/ — CID `bafybeictizb6xnvzktgnoq5t5e4ifctqnl4rvvcz3gezpje43an4y5mrki`, how it is built and verified in [docs/IPFS_MIRROR.md](docs/IPFS_MIRROR.md) |

Additional official channels will be listed here as they go live. Any channel
not listed here is not official. The IPFS mirror is identified by its content
hash (the CID above): a different CID is a different site, whoever serves it.

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
