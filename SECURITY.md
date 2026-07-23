# Security Policy — Daimon DAO

This page explains how to report vulnerabilities responsibly. For the full
technical threat model (actors, defenses, known limits, trust assumptions)
see [THREAT_MODEL.md](THREAT_MODEL.md).

## How to report a vulnerability

If you think you have found a vulnerability in the contracts, the deploy
scripts, or the dApp, **do not open a public issue and do not disclose it**:
a vulnerability made public before it is fixed puts users' funds at risk.

Use the private GitHub channel, directly from this repository:

> **Security → Report a vulnerability** (Private Vulnerability Reporting)

The report reaches only the maintainers, who can discuss it with you
privately. Once fixed, we publish a coordinated advisory and — if you wish —
credit your contribution publicly.

### What to include

- a description of the issue and the affected contract/file;
- the estimated impact (funds at risk? governance? DoS?);
- reproduction steps — a Foundry PoC (`forge test`) is ideal;
- a suggested fix, if you have one.

## Response times

Actively maintained but by a small team; *best-effort* timelines:

| Step | Within |
|---|---|
| Acknowledgement of receipt | 72 hours |
| First assessment (severity, plan) | 7 days |
| Fix or mitigation for critical issues | as soon as possible, top priority |

We will keep you updated in the private thread at every step. In exchange we
ask for coordinated disclosure: no publication before the fix and the
advisory (we agree on the timing together).

## Scope

**In scope:** the contracts in `src/` (`DaimonV2`, `DaimonStaking`,
`DaimonGovernor`, `DaimonTimelock`, `DaimonMigration`), the deploy scripts in
`script/`, and the dApp (`daimon-dapp/`).

**Out of scope:** third-party sites, public RPCs, upstream dependencies
(report those to their respective projects — e.g. OpenZeppelin has its own
program on Immunefi), social engineering, and anything concerning the test
network only.

## Bug bounty

There is currently **no formal bug bounty program**: it will arrive with the
mainnet launch. Responsible reports received before launch will still be
publicly acknowledged in the advisory and — at the project's discretion — may
be rewarded retroactively when the program starts.

## Project status

Contracts deployed and verified on BSC **testnet**; test suite (unit + fuzz +
invariant) and Slither static analysis performed. **Not yet subjected to an
external professional audit.** The mainnet deploy will happen only after the
audit.
