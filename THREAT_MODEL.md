# Threat model and trust assumptions

Document for the professional auditor and for the community. It describes
what each actor can and cannot do, the defenses in place, the known and
accepted limits, and the trust assumptions the system rests on.

Status: contracts deployed and verified on BSC testnet; test suite (unit +
fuzz + invariant + adversarial) green; Slither static analysis performed.
**Not yet subjected to an external professional audit.**

Contracts in scope: `DaimonV2` (token), `DaimonStaking`, `DaimonGovernor`,
`DaimonTimelock`, `DaimonMigration`.

To report a vulnerability: see [SECURITY.md](SECURITY.md) (the repository's
security policy).

---

## 1. Actors and capabilities

| Actor | Who it is | What it can do | What it CANNOT do |
|---|---|---|---|
| **User/holder** | anyone | transfer, stake, vote (if it has vp at the snapshot), migrate, claim rewards, `burnDeadBalanceToFloor` | change parameters, mint, unlock locks early |
| **External attacker** | hostile EOA/contract with no roles | interact like any user, attempt reentrancy/MEV | acquire roles, drain funds, mint, exceed the hardcoded limits |
| **Whale** | holder with large capital | accumulate voting power (only by locking tokens over time), influence votes | vote with power acquired *after* the proposal; flash-loan governance |
| **Governance (DAO via Timelock)** | Timelock driven by the Governor | change fees (≤10%), addresses, limits, **UUPS upgrade of the token** | mint, push the supply below the floor, zero out the Timelock delay, act without the public 7-day delay |
| **Guardian** | emergency multisig | pause the token (≤36 months), cancel malicious proposals/operations | economic powers, execute proposals, pause after expiry (but can always *unpause*) |
| **Deployer** | whoever runs the deploy script | only the initial wiring | **nothing after deploy**: renounces every role (verified on-chain) |

---

## 2. Threats and defenses per actor

### 2.1 External attacker

- **Minting / supply inflation.** No mint function exists anywhere in the
  code. The supply is created once in `initialize()` and can only decrease
  (burn toward the floor). *Tested invariant:* `totalSupply ≤ INITIAL_SUPPLY`
  and `≥ MIN_SUPPLY` at all times.
- **Reentrancy.** Every function that moves value uses OpenZeppelin's
  `ReentrancyGuard` (`stake`, `withdraw`, `claimReward`, `claim`,
  `sweepUnclaimed`, `burnDeadBalanceToFloor`, the internal swaps). The
  checks-effects-interactions pattern is respected: state is updated before
  external calls. Slither flags reentrancy only on paths already protected by
  the guard or on calls to trusted contracts (router, staking) — see §4.
- **Role acquisition.** Access control is OZ `AccessControl` (token, timelock)
  and a dedicated governance mapping (staking). `GOVERNANCE_ROLE` administers
  itself; no `DEFAULT_ADMIN_ROLE` is assigned on the token. *Tested
  invariant:* no EOA/actor holds administrative roles in any sequence of
  actions.
- **DoS.** No loop over user-controlled-length arrays in public functions
  (locks are indexed by id; voting-power checkpoints use O(log n) binary
  search). The only loop is over `_excluded` (reflection), populated only by
  governance and effectively limited to the dead address.

### 2.2 MEV / front-running

- **Fee and buyback swaps.** They derive `amountOutMin` from `getAmountsOut`
  minus a governed slippage tolerance (`maxSwapSlippageBps`, default 5%,
  bounded between 0.5% and 30%). The swaps run inside `try/catch`: if the
  price leaves the tolerance the swap is *skipped* (funds preserved), without
  reverting the transfer of the user who triggered it (avoids a DoS vector on
  sells).
- **Accepted known limit — read this precisely.** `maxSwapSlippageBps` bounds
  the deviation from the router's **contemporaneous quote**, and nothing more.
  It does **not** bound the loss relative to a fair price: the quote is read in
  the same block as the swap, from a pool an attacker may already have moved.
  Someone who shifts the reserves first makes the quote itself unfavourable,
  and the tolerance is then measured against that manipulated number — so the
  real extractable value is not limited by this parameter.
  The protocol reads **no external price feed and uses no oracle**, by design.
  The residual MEV exposure is therefore an accepted risk that is explicitly
  **not** bounded (see §3 and §7).
- **Late voting.** Voting power is snapshotted at proposal creation
  (`votingPowerAt`): buying and staking after creation grants no power over
  that proposal.

### 2.3 Whale / governance manipulation

- Voting power derives **exclusively** from tokens locked over time
  (vote-escrow), not from the freely-movable ERC20 balance. To weigh on a
  proposal you must have locked **before** its creation (snapshot with binary
  search over the checkpoints). This neutralizes both flash-loans and
  purchases aimed at an already-visible proposal.
- The quorum is computed on the **snapshot** of `totalVotingPower` at
  creation, not on the live value: later stake/unstake do not alter the
  threshold. Quorum floor hardcoded at 10% (`MIN_QUORUM_BPS`).
- The quorum counts **`forVotes + abstainVotes`**, excluding against-votes
  (aligned with OpenZeppelin `GovernorCountingSimple`). Counting against in
  the quorum would create a perverse incentive — opposing could push a
  proposal over quorum and pass it, while staying silent would deny it: by
  excluding them, voting no **never helps** clear the threshold (only the
  `forVotes > againstVotes` outcome is decided by them). Fixed pre-audit as
  Finding 1 of the adversarial round; regression covered by tests.

### 2.4 Governance itself (semi-trusted actor)

The DAO is powerful but **bound by non-bypassable hardcoded limits**:

- **Fees:** `setFees` has an immutable 10% total cap (`FeeTooHigh`).
- **Supply:** no path, upgrade at the storage level included, can mint or go
  below `MIN_SUPPLY` (floor enforced in every burn).
- **Timelock:** `MIN_DELAY = 7 days` hardcoded; `updateDelay` can only stay
  ≥ this floor. Every governance action goes through the Timelock with a
  public delay → the community always has a window to react.
- **maxTx / swap threshold:** the setters have minimum bounds against
  self-DoS.
- **Accepted known limit — UUPS upgrade.** The DAO *can* replace the token
  logic via upgrade (authorized only by the Timelock, with delay). A
  malicious upgrade approved by governance could in theory reintroduce a mint
  or alter the logic. This is the intrinsic limit of any upgradable system
  and is **accepted by design**: the defense is procedural (public 7-day
  delay + code in the clear + community reaction), not technical. *Tested:*
  only the Timelock can upgrade; guardian and EOAs cannot; state is preserved.

### 2.5 Guardian

- **Defensive powers only**: pausing the token and cancelling
  proposals/operations. No economic power, no execution.
- **36-month expiry** (`guardianExpiry`): after it, `setPaused(true)` reverts
  forever (definitive decentralization, verifiable on-chain). `setPaused(false)`
  always stays possible → a contract paused at expiry does not stay frozen
  forever.
- Assumption: the guardian is a **multisig** (in production). A compromised
  guardian can pause (temporary DoS, not theft) and cancel legitimate
  proposals (temporary censorship) until expiry.

### 2.6 Migration

- **Pull, not push:** each user initiates their own claim.
- **1:1 check on both sides:** balance-before/after on the old token
  (incoming) and on the new one (outgoing); any discrepancy from unexpected
  fee-on-transfer reverts, protecting the user (`AmountMismatch`).
- **Cap:** the migration cannot distribute more than the supply assigned to
  it at deploy (no supply creation). *Tested invariant:* old tokens in the
  treasury == `totalMigrated`, and the migration never distributes more DMN
  than owed.
- **Sweep:** only after the deadline, only from the Timelock, only to the DAO
  treasury, once.

---

## 3. Known and accepted limits

1. **Residual MEV, not bounded by the slippage setting.** The swap protection
   bounds the deviation from the router's contemporaneous quote, not the loss
   against a fair price: an attacker who moves the reserves first makes that
   quote unfavourable, and the tolerance is measured against the manipulated
   number. No oracle and no on-chain TWAP is used, by design. See §2.2 and §7
   (#34) for the full statement.
2. **Upgrade authorizable by the DAO.** The UUPS upgrade can in theory replace
   the monetary logic; mitigated only by the Timelock's public delay. Explicit
   trade-off between upgradability and absolute immutability.
3. **Reflection and dust.** The reflection accounting (RFI style) accumulates
   rounding: the sum of balances is `≤ totalSupply` (never above), with dust
   lost to integer division. The migration, being a holder, accrues reflection
   on the unclaimed residual (benign: it ends up in the treasury at the
   sweep).
4. **BNB rewards and dust.** The reward accumulator (1e27 scale) can leave
   undistributed fractions; BNB sent with no stakers is queued and
   redistributed at the first useful notify.
5. **Dependency on the PancakeSwap router.** The swaps rely on the external V2
   router; a malfunction of it degrades fees/buyback (handled with try/catch,
   does not block transfers).
6. **Voting power does NOT decay (conscious design choice).** vp is
   `amount × multiplier`, assigned at stake and constant until `withdraw`;
   after the lock expires (`unlockTime`) the user keeps the full vp (up to 4×)
   and the corresponding reward share, while being able to withdraw at any
   time. It is not a Curve-style ve-token (where power decays to zero toward
   expiry): here the system **rewards historical lockers**. Game-theory
   consequence: the rational strategy is to stake once at the maximum
   multiplier, ride out the lock only once and never withdraw, keeping voting
   weight and rewards indefinitely with on-demand liquidity; over time
   governance power tends to ossify around the early/large lockers and
   `totalVotingPower` does not decay. There is no loss of funds nor undue
   advantage on rewards (distribution stays proportional to vp). It is a
   trade-off **accepted for v1**; a possible vp decay/re-lock is **phase-2**
   material, introducible via governance without touching the safety of
   funds. Verified by the adversarial tests (Area 3).

---

## 4. Notes on the static-analysis findings (Slither)

Slither's "High" findings on these contracts are **false positives** in
context or mitigated:

- **`arbitrary-send-eth`** on `_swapAccumulatedFees`, `_buyBackAndBurn`,
  `Timelock.execute`: the recipients are not arbitrary attacker-controlled
  ones — they are the governed `marketingWallet`/`stakingContract` and the
  `target` of a proposal already passed through vote + timelock. There is no
  path where an outsider redirects the ETH.
- **`reentrancy-*`**: the flagged paths are protected by `nonReentrant` or
  interact with trusted contracts (router, staking). State is updated before
  external calls (CEI).
- **`uninitialized-state` on `_vpCheckpoints`**: it is a mapping, empty by
  definition; not a defect.
- **`incorrect-equality` / `divide-before-multiply`**: on reflection
  computations and balance comparisons where strict equality is intended and
  precision is handled; no exploitable impact.
- **`timestamp`**: the temporal comparisons (lock, timelock, vote) use
  `block.timestamp` at day/hour granularity, well beyond the miner's
  manipulation window (seconds). Accepted.

The informational/optimization findings (naming, missing events on some
Governor setters, multiple pragma versions due to the libraries) are tracked
and partly already addressed; none is blocking.

---

## 5. Trust assumptions

- The **deployer** runs the official script and renounces every role
  (verified on-chain by the script's asserts and the invariant tests).
- **Guardian, treasury and marketing wallet** are distinct multisigs in
  production (on testnet they coincide with the deployer, for testing only).
- The **community** monitors proposals during the 7-day delay: it is the last
  line of defense against a malicious upgrade or parameter change.
- The **OpenZeppelin v5.4.0 libraries** (AccessControl, UUPS, Initializable,
  ReentrancyGuard) are assumed correct and audited.
- The **PancakeSwap V2 router** on BSC behaves per interface.

---

## 6. Test coverage (summary)

- 74 tests: unit, governance sequences, fuzz (512 runs each), handler-based
  invariants (256 runs × 64 depth), UUPS-upgrade coverage paths, and the
  targeted adversarial suite (snapshot/whale, boundary values, perverse
  incentives, reflection edge — 14 tests).
- Verified invariants: supply within bounds, `totalVotingPower` = sum of
  active locks and per-user vp, migration conservation, reward balance =
  funded − claimed, no unauthorized admin role.

Detail of the findings and proposed fixes: see the adversarial round in
[TESTNET_RESULTS.md](TESTNET_RESULTS.md) (Test 10) and the hardening report
attached to the review conversation.

---

## 7. Accepted limitations — Zenith audit 2026-08

Findings from the Zenith engagement that were reviewed and **accepted rather
than changed**, each with the reason. They are recorded here so a reader does
not have to re-derive the analysis, and so the acceptance is on the record
rather than implicit.

### #24 — Approvals and queued operations do not expire

A passed proposal stays queueable indefinitely, and a ready timelock operation
stays executable until it is executed or cancelled.

**Accepted.** This matches OpenZeppelin's `TimelockController`, which defines a
minimum delay and no execution deadline. Adding a grace period would introduce
a liveness risk in exchange: an expired operation forces the whole 13-day cycle
(1 day voting delay + 5 days voting + 7 days timelock) to be repeated, and an
operation that expires unnoticed is a governance failure with no alarm. The
defence against stale proposals is the guardian's ability to cancel, plus
monitoring — both available at any point before execution.

### #20 — Unswapped fee inventory is allocated at execution time

The marketing and buyback fees accumulate in a single token balance. When the
swap runs, the resulting BNB is split according to the split **in force at that
moment**, not the one in force when each portion was collected.

**Accepted — allocation happens at execution time.** A change to the split
therefore also applies to inventory already collected and not yet converted;
this is the intended reading and is stated here so it is not mistaken for a
bug. The exposure is bounded: pending inventory cannot exceed the swap
threshold before being converted, and any split change goes through a vote and
the 7-day timelock, so it is public well before it takes effect. Separating the
balances would add storage and accounting to a contract that already carries
findings on its automation.

### #34 — `maxSwapSlippageBps` does not bound the real MEV loss

**This corrects a claim previously made in this document.** Earlier wording
said the swap protection limits the damage "to the set tolerance". That is not
accurate.

`maxSwapSlippageBps` bounds the deviation from the router's **contemporaneous
quote**. It does **not** bound the total loss relative to a fair price: an
attacker who moves the reserves before the swap makes the quote itself
unfavourable, and the tolerance is then measured against that manipulated
number. The protocol reads **no external price feed and uses no oracle**, by
design. The residual MEV exposure is an accepted risk and is explicitly **not**
bounded. §2.2 and §3 have been corrected accordingly.

### #4 — Reentrancy on the timelock predecessor

`execute()` sets `executed = true` before calling the target. A target holding
`EXECUTOR_ROLE` could in principle re-enter with an operation whose predecessor
is the first one, and see it already marked executed.

**Accepted — not reachable.** The Governor is the only executor, and its path
always passes a zero predecessor, so no predecessor relationship is ever
established. Recorded explicitly: **predecessor-based ordering is not supported
under the current execution model.** Anyone extending the executor set, or
introducing predecessors, must revisit this first.

### #6 — Legacy tokens are transferred to the treasury

`claim()` sends the old tokens to the treasury rather than burning or locking
them. If the treasury were to put them back into circulation during the
migration window, they could be migrated again.

**Accepted as a custody risk**, not a code property, and therefore recorded as
a strict operational requirement: **the collected legacy tokens remain in
non-circulating custody for the entire migration window.** Also listed in
[CHECKLIST_MAINNET.md](CHECKLIST_MAINNET.md), which is the document consulted
at deploy time.

### #10 — Staking assumes exact receipt

`stake()` records the requested amount without checking the balance actually
received. This is correct **because** the staking contract is fee-exempt, but
the assumption was not written down anywhere.

**Documented as an accounting invariant**, now stated in the NatSpec of
`stake()`: the staking contract's fee exemption is not a convenience, it is
what makes the recorded amount equal the received amount. Any upgrade or
configuration change must preserve it. The fix for #32 additionally enforces
this on-chain — the exemption can no longer be revoked while
`totalStakedAmount() > 0`.

### #16 and #17 — Double fees on liquidity operations

Removing liquidity pays the transfer fee twice (pair → router → user). Adding
liquidity yields fewer LP tokens than the router's own quote suggests, because
the router computes on the gross amount while the pair receives the net.

**Accepted in the contracts, disclosed in the interface.** The requirement is
recorded in [DAPP_SPEC.md](DAPP_SPEC.md): the interface must state how many
fees are paid and what will actually be received, before the user signs.

⚠️ **Do not "fix" this by exempting the pair or the router.** Doing so would
disable fees on every buy and sell, and would open a fee-free transfer route:
pre-deposit tokens, then call liquidity removal to move them out untaxed. The
double fee is the lesser cost by a wide margin.

---
