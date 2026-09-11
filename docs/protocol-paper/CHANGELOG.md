# Protocol paper changelog

Newest version first. Every released version is preserved in this directory
and referenced by an annotated git tag (`protocol-paper-vX.Y`; the first
release, made under the document's previous name, is `whitepaper-v0.1`), so
any statement can be cited against an immutable snapshot.

---

## [0.2] — 2026-09-11

**Post-audit release.** The document is renamed **protocol paper**: files,
title, README links and cross-references. The sources were moved with
`git mv`, so their history is continuous (`git log --follow`); the v0.1 PDFs
keep their original file names as the historical record. Sources and PDFs
realign at this version: the v0.2 PDFs are rebuilt from the `.md` sources by
`build_pdf.py` in this directory.

### Corrections queued since August (all included here, none in the v0.1 PDFs)

- **§5 and threat-model summary, deployment checks** (EN and IT): the deploy
  is now two phases plus a standalone post-broadcast verification. The
  assertion count changes from twenty to thirty across the two phases,
  and thirty-four further checks are re-read from the live chain — because
  an assertion inside a deployment script proves the simulated state, not
  the mined one (Level 1 testnet campaign, deviation A1.8). The guardian
  expiry passage changes from "fixed independently ... verified identical"
  to identical **by construction**: phase 2 reads the token's mined value
  from the chain and passes it verbatim to the governor and timelock
  constructors.
- **§6.5, burn cycle, step 2** (EN and IT): the contract does not sell "the
  accumulated tokens" — it sells one threshold-sized tranche per qualifying
  sell, at most one per block (per-block budgets introduced by the Zenith
  #28 fix). Same class of imprecision as the #20 threat-model correction:
  the swap threshold sizes the tranche, it does not bound the inventory.
- **§6.5, burn cycle, steps 2/4 and closing paragraph** (EN and IT): the
  automation trigger changed with the Zenith #1 fix. Ordinary sales through
  the router deliberately no longer trigger the fee swap or the buyback;
  the trigger is a permissionless direct transfer of DMN to the pair, with
  per-block budgets capping the aggregate. The old wording ("a sale to the
  liquidity pool occurs", "steps 2 and 4 are automatic") described the
  pre-fix model.
- **§6.3, zeroing the fees is a model change** (EN and IT). `setFees` has a
  ceiling and no minimum, so zero is a legal governance action — and it
  switches off nearly everything the fees feed: reflection, new buyback
  BNB, burn, staking rewards, operational funding, with the 21B floor of
  §6.2 out of reach for as long as zero persists. Verified against the
  integrated contracts before writing: no division-by-zero (the only
  fee division is guarded), residual inventory keeps converting on pokes
  (all proceeds join the buyback pool once the split is skipped) and the
  accumulated BNB stays spendable down to the 1-BNB trigger. The section
  states the reversibility, the 13-day window, and the one configuration
  where zero is coherent (an existing alternative revenue source). Same
  entry added to THREAT_MODEL par.2.4 as an accepted known limit.
- **§6.2/§6.6, the floor as a bound, not a destination** (EN and IT).
  Nothing guarantees the supply will ever reach 21 billion: tokens in lost
  wallets stay in the total supply, keep accruing reflection (their balance
  grows), can never be bought by the buyback nor burned by anyone, and no
  function can intervene — by construction, since a contract able to take
  tokens from an address it does not control would no longer be ownerless.
  Enough lost tokens would stall the burn permanently above the floor.
  §6.2 gains the full statement (with the Bitcoin lost-coins precedent);
  §6.6's "when the supply reaches" becomes conditional and its closing
  notes the terminal state is specified, not promised. Same conditional
  applied to the dApp's floor tagline (DAPP_SPEC and en/it messages, key
  `floorPromise` — the IT string promised arrival outright).
- **Systematic precision pass** (EN and IT), following a claims-vs-code
  audit of the whole document. In order of weight: §6.5's "no one can
  prevent" the floor burn — false since the Zenith #5 fix, which gates
  `burnDeadBalanceToFloor` behind the emergency pause (now stated, with the
  window bound); §7.2's zero-staker rewards "distributed to the next
  stakers" — the exact behaviour the #35 fix removed, they now sit in a
  governance-recoverable reserve; §11.3's "two addresses outside anyone's
  reach" — true for the dead address, but for the migration treasury only
  the pointer is immutable, the funds are managed by its signers (now
  stated, with the custody commitment); the abstract now names the guardian
  and its veto instead of listing only what nobody can do; §2.3/§7.3
  snapshot machinery updated from timestamp keys to sealed-block keys
  (#12) — including the one code snippet in the document that showed a
  no-longer-existing interface (all other snippets verified against the
  integrated contracts); the §4.2 table's reflection-exclusion set now
  lists both entries (dead address and pair, #30) and its slippage row
  carries the #34 caveat (a bound against the router's own quote, not
  against MEV loss); the deploy assertion count updated from fourteen to
  nineteen (#36).
- **§5 guardian paragraph, §8.6, and the actor summary** (EN and IT): the
  guardian's perimeter was understated — it has always also held the two
  cancellation powers (governance proposals and their queued timelock
  operations), not just the pause. The sections now state the real
  perimeter, the window model introduced by the Zenith #36 fix (14-day
  self-terminating pauses, renewals visible on-chain), the single 36-month
  expiry replicated across the three contracts, and the migration pause
  credit. Note: §8.6's claim that "no one can leave Daimon paused
  indefinitely" only became true with the #36 fix — before it, an armed
  pause survived the guardian's expiry.

### Decisions applied at this release (EN and IT, section by section)

- **Title, header, footer.** "Whitepaper — Draft v0.1 — pending external
  audit" becomes "Protocol paper — v0.2 — post-audit release". The footer
  names the audited reference (`audit-final`, scope submitted at
  `audit-scope-v2`) and links the Zenith report.
- **§1 abstract.** The guardian is named as a 2-of-3 multisig with its two
  cancellation paths (governor, timelock); "a 4% fee set by community vote"
  becomes "a 4% fee that only a public vote can change"; a paragraph states
  the audit is complete and the audited code was rehearsed twice more with
  the mainnet scripts.
- **§4.1.1, §4.1.4 — the predecessor's facts as in CHECKLIST_MAINNET.** DMX
  has **two** marketing wallets (`marketingAddress1` = the owner,
  `marketingAddress2`), the non-reflected 7% split in seventieths — 25 to
  each wallet, 20 to the buyback; the owner is an EOA holding no code,
  ownership never renounced, re-read on 2026-09-11 at block 121,166,526;
  `_maxTxAmount` 1.5B. The document described one wallet.
- **§4.2 — fees.** The audited code initialises 10/20/20 (5%); the launch
  configuration sets 10/10/20 (4%) in deploy phase 2, through the
  deployer's temporary governance role, before that role is handed to the
  timelock and revoked, verified by a post-broadcast assert. The old text
  claimed the mainnet 4% was itself the product of a vote (that was
  proposal #0, on testnet, now cited as such in Section 9 — the old
  cross-reference pointed at Section 8). Table rows for the marketing fee
  and its recipient updated to the launch split and the timelock.
- **§4.4.** New closing paragraph: the project's own legacy holdings never
  claim and reach the treasury through `sweepUnclaimed()`; they do not vote.
- **§5.3, §8.6, §10.1 — the guardian, fully.** Three authorities: pause
  (max 14 days, self-lifting), cancel via the governor (atomic
  cross-cancel), cancel directly at the timelock; one expiry 36 months
  after launch across the three contracts, copied verbatim in phase 2
  (§5.3 still said "fixed independently"); after expiry only a governance
  self-call can cancel a queued operation; the guardian is a 2-of-3
  multisig held by different people. The migration treasury in §5.3 and
  the §8.4 table is named as the timelock.
- **§6.3, §6.5, §7.2, §8.5 — the fee split at launch.** "60% to stakers,
  40% to operations" everywhere becomes a governance-set share: 100% to
  stakers at launch (`stakingRewardShareBps = 1000`), 60/40 after the first
  mainnet vote, the 40% to the treasury. "Operational funding" becomes
  "treasury income"; §8.5's governance powers reworded accordingly.
- **§6.4 — two reflection exclusions.** The section still said one address
  (the dead address) while the §4.2 table already listed two; it now states
  the pair as well, with the #30 rationale (passive balance growth
  skimmable from the pair).
- **§10.2.** 180 tests (not 74), six categories: a sixth group of audit
  regression tests reproduces the findings fixed in code.
- **§10.4.** The least-proven path was exercised in both testnet campaigns
  (July, and the level-2 rehearsal on a real router); findings #1 and #28
  changed its trigger.
- **§10.6.** The sweep is no longer "in progress": proposal #2 executed on
  2026-08-07, 999,121,813,473 DMN to the treasury, supply unchanged. New
  paragraph on the two post-audit rehearsals, with links to
  `TESTNET_L1_RESULTS.md`, `TWO_PHASE_RESULTS.md` and `CHAPEL_L2_RESULTS.md`.
- **§10.7 — audit complete.** Zenith, 37 findings (1 critical, 1 high, 7
  medium, 12 low, 16 informational), 29 fixed in code, 8 accepted with
  written reasoning, report public and linked, audited range frozen at
  `audit-final`; the three pre-audit commitments restated with their status.
- **§11 — replaced.** The two-wallet model gives way to the single treasury
  of `docs/TREASURY_POLICY_v1.0.md`: the timelock is the only treasury;
  `marketingWallet` is the timelock at deploy with the staker share at 1000
  (nothing flows); the first mainnet proposal sets 60/40; no operational
  multisig; small recurring expenses come from the legal entity through
  periodic budgets voted by proposal; the project's legacy holdings (the
  two DMX wallets, ~42% of the old supply) never claim, reach the treasury
  through `sweepUnclaimed()` and do not vote; the continuity burn; the LP
  tokens of the initial liquidity held by the timelock. Dropped: "signers
  will be public" and "the migration treasury is a multisig". Subsections
  renumbered 11.1–11.7.
- **§12.1.** Phase 1 status: audited, rehearsed three times on testnet;
  what remains is listed without a date.
- **§12.2 — the treasury module.** Folded into Phase 2: it comes after
  launch and after the first service module, when the treasury can pay for
  it; target allocation 20% BNB / 40% BTCB / 40% XAUt, never stablecoins;
  BTCB and XAUt named plainly as custodial wrappers ("a choice of chain,
  not of faith"); yields may be positive, zero or negative. The former
  §12.3 "An active treasury" is absorbed; Infrastructure becomes §12.3
  (Phase 3) and "The roadmap is not fixed" becomes §12.4. Nothing was added
  about future service modules beyond the direction §12 already gave.
- **§13, §14.** "Submitted for independent review" becomes "independently
  audited, with the report public"; §14 points to the published
  `DISCLAIMER_TERMS` (English authoritative).

| File | Role |
|---|---|
| `Daimon_Protocol_Paper_EN_v0.2.pdf` | English edition (primary) |
| `Daimon_Protocol_Paper_IT_v0.2.pdf` | Italian edition (translation) |
| `protocol_paper_EN.md` | English source |
| `protocol_paper_IT.md` | Italian source |
| `build_pdf.py` | builds both PDFs from the sources |

Git tag: `protocol-paper-v0.2`.

## v0.1 — 2026-07-27

First public release, under the name **whitepaper**. **Draft pending
external security audit.** Contracts frozen at tag `audit-scope-v2`.

| File | Role |
|---|---|
| `Daimon_Whitepaper_EN_v0.1.pdf` | English edition (primary) |
| `Daimon_Whitepaper_IT_v0.1.pdf` | Italian edition (translation) |
| `whitepaper_EN.md` | English source (now `protocol_paper_EN.md`) |
| `whitepaper_IT.md` | Italian source (now `protocol_paper_IT.md`) |

Git tag: `whitepaper-v0.1`.
