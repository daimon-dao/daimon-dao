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
- **§6.5, burn cycle, steps 2/4 and closing paragraph** (EN and IT): the
  automation trigger changed with the Zenith #1 fix. Ordinary sales through
  the router deliberately no longer trigger the fee swap or the buyback;
  the trigger is a permissionless direct transfer of DMN to the pair, with
  per-block budgets capping the aggregate. The old wording ("a sale to the
  liquidity pool occurs", "steps 2 and 4 are automatic") described the
  pre-fix model.
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
