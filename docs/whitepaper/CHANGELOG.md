# Whitepaper changelog

Newest version first. Every released version is preserved in this directory
and referenced by an annotated git tag (`whitepaper-vX.Y`), so any statement
can be cited against an immutable snapshot.

---

## Unreleased (sources only)

Corrections applied to the `.md` sources ahead of the post-audit release.
The v0.1 PDFs intentionally do NOT include them: sources and PDFs realign
at the next released version, together with the final audit report.

- **§6.5, burn cycle, step 2** (EN and IT): the contract does not sell "the
  accumulated tokens" — it sells one threshold-sized tranche per qualifying
  sell, at most one per block (per-block budgets introduced by the Zenith
  #28 fix). Same class of imprecision as the #20 threat-model correction:
  the swap threshold sizes the tranche, it does not bound the inventory.

## v0.1 — 2026-07-27

First public release. **Draft pending external security audit.** Contracts
frozen at tag `audit-scope-v2`.

| File | Role |
|---|---|
| `Daimon_Whitepaper_EN_v0.1.pdf` | English edition (primary) |
| `Daimon_Whitepaper_IT_v0.1.pdf` | Italian edition (translation) |
| `whitepaper_EN.md` | English source |
| `whitepaper_IT.md` | Italian source |

Git tag: `whitepaper-v0.1`.
