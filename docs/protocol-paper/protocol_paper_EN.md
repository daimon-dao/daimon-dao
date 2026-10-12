# DAIMON (DMN)
## An Ownerless, DAO-Governed Deflationary Protocol on BNB Chain

**Protocol paper — v0.3**
*Mainnet release. Previously published as "Protocol paper — v0.2" (post-audit
release, 11 September 2026) and, before that, as "Whitepaper — Draft v0.1".*

---

# 1. Abstract

Daimon is a deflationary token governed entirely by its holders, deployed on
BNB Chain. It has no owner, no administrator, and no minting function. Its
total supply can only decrease — from an initial 1,000 billion tokens toward
an immutable floor of 21 billion, below which the code makes further burning
mathematically impossible.

Every parameter that governs the protocol — transaction fees, staking
mechanics, treasury allocation, even the code itself — can be changed only
through an on-chain vote followed by a mandatory seven-day public timelock.
No individual, including those who built it, holds the power to alter,
accelerate, or bypass that process. One safeguard account exists — the
guardian, a 2-of-3 multisig — and its powers are purely negative: it can
pause the token in windows of at most fourteen days that expire on their
own, and it can cancel an in-flight decision before execution, through the
governor or directly at the timelock. Every one of those powers ends at an
unmovable deadline 36 months after launch; nothing it armed survives that
instant. This is not a commitment we ask you to trust: it is a property of
the deployed contracts, verifiable by anyone at any time.

Holders who lock their tokens receive voting power proportional to both the
amount and the duration of their commitment, along with rewards paid in BNB —
funded by real trading activity, never by newly issued tokens. There is no
inflation, because there is no mechanism capable of producing it.

Daimon is the migration of an existing token toward complete
decentralization. Where the previous version had an owner with discretionary
control and an 11% transaction fee, the new protocol has no owner, a 4% fee
that only a public vote can change, and a hard ceiling written into the code
that no future vote can exceed.

The contracts have been independently audited. The report is public, and
every one of its findings is either fixed in the code or accepted with
written reasoning (Section 10.7). The audited code was rehearsed four more
times with the mainnet scripts, twice on a public chain in real time, and
was deployed unchanged to BNB Smart Chain mainnet on 29 September 2026
(Section 10.6). The migration window is open until 28 December 2026
(Section 4.3).

The protocol does not promise returns. It guarantees rules: scarcity that
cannot be diluted, decisions that cannot be taken in private, and a system
that continues to function exactly as specified whether or not anyone is
watching over it.

---

# 2. The Name

In ancient Greece, the *daimon* was not a demon. It was a guiding spirit — a
lesser divine force that dwelt in the space between gods and mortals, neither
above humanity nor beneath it, but alongside.

The word derives from a verb meaning *to divide*, *to apportion*, *to
distribute a share*. The daimon was the one who apportioned destiny: not a
ruler who imposed it, but a custodian who accompanied it.

For the Greeks, happiness itself was named after this relationship.
*Eudaimonia* — literally, *to have a good daimon beside you*. Flourishing was
not something granted from above; it was the result of a good guide, well
followed.

The philosophers each understood it differently, and each reading matters
here:

**Socrates** described his *daimonion* as an inner voice that never told him
what to do — only when to stop. A restraint, not a command. It intervened
solely to prevent error.

**Plato**, in the Myth of Er, wrote that souls choose their own daimon before
birth. The guide is not assigned from above: it is selected by the one who
will be guided.

**Heraclitus** put it most sharply: *character is destiny* — a person's own
disposition is their daimon. Nothing external. The guide and the guided are
the same thing.

## 2.1 The concept came first

This protocol was not built and then named. The name is not a label applied
afterwards to a finished system, and the correspondence described below is not
a coincidence noticed in retrospect.

The concept of the daimon is what produced the project. Every architectural
decision — what the protocol may do, what it must refuse to do, where
authority is placed and where it is deliberately absent — was made against
that idea. The code is the concept written in Solidity.

The three readings above are not decoration. Each one corresponds to a
specific property of the deployed contracts.

## 2.2 Socrates — the guide that restrains rather than commands

The *daimonion* never told Socrates what to do. It intervened only to stop
him. A negative signal: not direction, but restraint.

```solidity
if (block.timestamp < op.readyTimestamp) revert TooEarly();
```

The timelock contains no logic about what constitutes a good decision. It does
not approve, advise, weigh or improve. It has no opinion about the proposal
passing through it. Its entire contribution is a refusal conditioned on time.

Governance decides. The timelock only prevents anything from happening faster
than it can be examined. It is a restraint, and nothing else — which is the
only form of authority in the system that operates without a vote.

## 2.3 Plato — the guide is chosen, before the question arises

In the Myth of Er, souls select their daimon *before* birth. The guide is not
assigned by a higher power; it is chosen by the one who will be guided, and
chosen in advance.

```solidity
votingPowerAt(voter, proposal.snapshotBlock)
```

Voting power is evaluated at the last block sealed *before* a proposal was
created, not at the moment of voting. Influence over a decision derives from
a commitment made before that decision existed as a question.

The practical effect is that power cannot be acquired in reaction to
something already on chain: when a proposal lands, the snapshot block behind
it is already sealed, so influence bought afterwards — even in the very same
block — counts for nothing. The choice precedes the question — which is
precisely what Plato described, and precisely what a snapshot enforces.

## 2.4 Heraclitus — the guide and the guided are the same

*Character is destiny.* For Heraclitus the daimon was not external at all: a
person's own disposition is their daimon. There is no separate entity.

```
GOVERNANCE_ROLE  →  DaimonTimelock
                    (no other holder, in any contract)
```

There is no authority above the protocol. No owner, no administrator, no
council, no foundation, no address that can act on the system from outside
it. The only role that exists is held by a contract that does nothing except
execute what the community has already decided.

What the holders choose is what the protocol becomes. Not because we promise
to respect their decisions, but because there is no mechanism through which
anyone could fail to. The character of the community is the destiny of the
system — and the absence of any other authority is what makes that statement
structural rather than aspirational.

## 2.5 What follows from this

Three properties, three readings, one concept: an authority that apportions
rather than accumulates, restrains rather than commands, and is chosen rather
than imposed.

Everything in the remainder of this document is an elaboration of that idea
into specific mechanisms. Where the two ever conflicted during development,
the concept won — including when it made the work considerably harder, as
Section 4.5 describes.

---

# 3. The Problem

## 3.1 A token with an owner is a promise, not a system

Most tokens are deployed with an administrative account — the *owner* — that
retains privileged functions. Depending on the implementation, the owner can change
transaction fees, freeze transfers, exclude addresses from limits, withdraw
accumulated funds, and in many cases mint new tokens. These capabilities are not hidden: they are
written in the contract, visible to anyone who reads it.

The question is not whether such powers exist. It is what stands between
those powers and their misuse.

In almost every case, the answer is: the owner's intentions. Nothing else.
No procedure, no delay, no requirement to announce, no way for holders to
object before the fact. The security model reduces to a sentence that
appears, in some form, in thousands of projects: *trust us*.

This is not a criticism of any particular team's honesty. It is an
observation about structure. A system whose safety depends on the continued
good faith of a single private key is not a safe system — it is a bet on a
person. Keys are lost. Accounts are compromised. People change their minds,
face pressure, or make mistakes at three in the morning. And a bet that pays
out reliably for two years is still a bet.

## 3.2 The same structure, at a larger scale

The pattern is not unique to crypto. It is the pattern of the financial
system that most people already live inside.

Decisions that determine the value of ordinary people's savings — how much
currency to issue, what fees to apply, which terms to change and when — are
taken by institutions that do not consult those affected, do not announce
changes in advance, and explain them afterward in language engineered to
discourage examination. Depositors are not participants; they are the
subject matter. The information asymmetry is not a side effect of the
system: it is a feature of it.

Inflation is the clearest example. It is not a natural phenomenon. It is a
decision, taken by a small number of people, whose effect is to reduce the
value of savings held by everyone else. It requires no consent, offers no
opt-out, and is rarely described as what it is.

Crypto was supposed to be the alternative. Yet a token whose owner can change
the rules at will has simply reproduced the same structure with a smaller
budget: an opaque authority, discretionary decisions, and participants who
find out afterward.

## 3.3 What the alternative requires

A genuine alternative cannot rely on better intentions. It has to make the
problematic actions structurally impossible.

That means, concretely:

- **No mint function.** Not disabled — absent. Dilution cannot be voted into
  existence, cannot be enabled by an upgrade, cannot be introduced by anyone
  under any circumstances, because the code to perform it does not exist.

- **No privileged account.** After deployment, no externally owned wallet
  holds administrative rights over the protocol. Not the deployer, not the
  team, not any individual.

- **No silent changes.** Every modification passes through a public proposal,
  a vote with a minimum participation threshold, and a mandatory delay long
  enough for anyone to read what is coming and act on it.

- **No unbounded parameters.** Even the community, voting unanimously, cannot
  raise fees above a ceiling fixed in the code, or burn supply below the
  floor. The system limits its own governance.

- **No required trust.** Every claim in this document corresponds to code
  that is public, deployed, and verifiable. Nothing here asks to be believed.

Daimon is an attempt to build exactly this, and to do so for an existing
community: not as a new launch, but as the migration of a token that already
had an owner toward a system that has none.

## 3.4 A note on method

This document contains a critique of concentrated financial power. It
contains no call to action beyond one: read the code.

There is a form of dissent that consists of demanding that those in charge
behave differently. There is another that consists of building something
that does not require them to. This project belongs to the second kind. Not
because the first is illegitimate, but because a working alternative is a
more durable argument than a complaint — and because a system that removes
the need for trust cannot be persuaded to change its mind.

The remainder of this document describes how, and — equally important —
where the limits are.

---

# 4. From DMX to DMN

## 4.1 What existed before

Daimon did not begin as a decentralized protocol. It began as DMX
(`0x36EbA94407B53c631eE822C219e94580fadd67c7`), a reflection token on BNB
Chain with the structure common to that category: an owner account holding
seventeen administrative functions, and an 11% transaction fee.

| | DMX (previous) |
|---|---|
| Reflection fee | 4% |
| Marketing fee | 5% |
| Buyback fee | 2% |
| **Total fee** | **11%** |
| Fee ceiling | **none** |
| Owner | yes, ownership never renounced |
| Who decides | the owner, with immediate effect |
| Supply floor | none |
| Supply reduction | none — see 4.1.2 |
| Staking | none |
| Governance | none |

This section is not written as an accusation. DMX is our own earlier work,
and the structure described here was the standard pattern of its generation.
It is documented precisely because the community that holds those tokens
deserves to know exactly what they are migrating away from — and because
several of these properties are not visible without reading the source.

### 4.1.1 Parameters without bounds

The fee values were not fixed in the code. They were constructor parameters,
adjustable afterwards by three setter functions:

```solidity
function setTaxFee(uint256 taxFee) external onlyOwner() {
    _taxFee = taxFee;
}
```

A plain assignment. No `require`, no upper bound, no delay, no announcement.
The owner could set any fee to any value, including 100%, effective on the
next transaction.

The same applies to the maximum transaction size. Deployed at 0.3% of supply,
it stood at 0.15% — 1.5 billion DMX — when read on-chain on 11 September
2026: the owner had halved it at some point using a setter with no lower
bound. On 29 September 2026, so that any holding could migrate in one
transaction, the owner set it to the entire supply (transaction
`0xfaef2123e54dd4d5054b9195284d43576e35c5161e178ae5e8b810f9b620b47b`,
18:53:34 UTC; the value read back at block 127,195,880 on 12 October 2026).
The same setter could have taken it to one wei, which would have made the
token effectively untransferable. Nothing in the code prevented either.

### 4.1.2 The burn that did not burn

DMX had no burn function. What it had was a buyback that purchased tokens on
the market and sent them to the dead address `0x…dEaD`.

The distinction is not semantic. Tokens sent to an unspendable address are
economically destroyed but remain in the accounting:

| | DMX, on-chain (26 July 2026) | DMX, on-chain (12 October 2026, block 127,195,880) |
|---|---|---|
| `totalSupply()` | 1,000,000,000,000 — unchanged since deployment | 1,000,000,000,000 — still unchanged |
| Held at dead address | 30,058,718,442 (3.0058%) | 30,961,537,947 (3.0962%) |
| Circulating | 969,941,281,557 | 969,038,462,053 |

The dead address balance keeps growing, since the buyback mechanism is
still running; both readings are snapshots. The total supply is not a
snapshot — it has never decreased by a single wei. Any metric derived from `totalSupply()` —
market capitalisation among them — was computed on a figure that overstated
the tokens in existence.

This is not unique to DMX; it is how most reflection tokens of that
generation handled burning. DMN separates the two steps: tokens are sent to
the dead address, and a second permissionless function removes that balance
from `totalSupply()` for real, bounded by the floor.

### 4.1.3 Ownership renunciation, reversible

The contract includes a function worth describing in full, because its
appearance and its effect differ:

```solidity
function lock(uint256 time) public virtual onlyOwner {
    _previousOwner = _owner;
    _owner = address(0);              // appears renounced
    _lockTime = block.timestamp + time;
}

function unlock() public virtual {
    require(_previousOwner == msg.sender, ...);
    require(block.timestamp > _lockTime, ...);
    _owner = _previousOwner;          // takes it back
}
```

After calling `lock()`, `owner()` returns the zero address. On any block
explorer this is indistinguishable from a permanent renunciation — the
signal most commonly cited as proof that a project cannot be altered by its
creators. It is temporary, and the previous owner can reclaim control when
the timer expires.

This function was never used on DMX (`getUnlockTime()` returns zero, and
ownership was never renounced). It is documented here because the pattern is
widespread, and because a reader evaluating any token should know that
`owner() == 0x0` is not, by itself, evidence of anything.

### 4.1.4 What DMX did not have — stated fairly

Several powers commonly found in tokens of this kind are absent from DMX, and
accuracy requires saying so:

- **No mint function.** None. The supply was fixed at deployment and could
  not be expanded by anyone. On this point the contract was already sound.
- **No pause and no blacklist.** The owner could not freeze transfers or
  block specific addresses.
- **No withdraw or rescue function.** The owner could not extract arbitrary
  funds held by the contract.

The problem with DMX was never that it could be drained. It was that its
economics were entirely at the discretion of one account, with no bound, no
delay, and no obligation to inform anyone.

One further detail completes the picture. DMX routes its marketing fee to
**two** wallets. `marketingAddress1` is the owner itself:
`0xF8EC459CAEaF1052b64B38BDD67290B0c132B0Ae`, an externally owned account
holding no code, whose ownership was never renounced — `owner()` still
returns it, read on 11 September 2026 at block 121,166,526 and again on
12 October 2026 at block 127,195,880.
`marketingAddress2` is `0x41B533AF0Db427dc97988B47f86383f42372f395`. The 7%
of every transfer that is not reflected is divided in seventieths: 25 to
each marketing wallet and 20 to the buyback — 2.5% to each wallet, 2% to the
buyback. The party controlling the parameters is therefore also a direct
recipient of the revenue it controls. Nothing about that arrangement was
hidden — it is visible on-chain to anyone who looks — but it is precisely
the concentration that the new architecture is designed to eliminate. Both
wallets hold DMX; what becomes of those holdings is stated in Section 11.5.

On 29 September 2026 the owner used two of these administrative functions
one last time, to open the migration: it raised the transaction cap to the
entire supply (4.1.1), and it excluded the migration treasury — the
timelock, Section 11 — from the DMX fee (transaction
`0x8aaac289174a13a61040a68503550d79b31cdc25e1884686e8a42632f04cd54d`,
20:06:24 UTC), the two settings without which a 1:1 claim cannot be exact
(Section 4.3). For the whole migration window the owner is bound not to
reverse either, nor to lock, renounce or transfer the ownership that keeps
them in force; the launch record states the rule.

### 4.1.5 On how it came to be this way

DMX was our apprenticeship. We built it with the knowledge we had at the
time, following the patterns that were standard for that generation of
tokens — patterns shared by hundreds of projects, including many with funded
teams and published audits.

What followed was a period of study, and this protocol is what came out of
it. The migration exists because the honest response to understanding a
limitation is not to defend it.

It is worth noting what DMX did *not* inherit from those templates: no mint
function, no pause, no blacklist, no withdrawal mechanism. The four
capabilities most often used to extract value from holders were absent from
the first version as well. The judgement was there before the vocabulary
was.

The new version does not attempt to defend that structure. It replaces it with
a better one.

## 4.2 What replaces it

| | DMX (previous) | DMN (new) |
|---|---|---|
| Reflection fee | 4% | 1% |
| Marketing fee | 5% | 2% — split between stakers and the treasury by a governance-set share: 100% to stakers at launch, 60/40 after the first mainnet vote (Section 11) |
| Buyback fee | 2% | 1% |
| **Total fee** | **11%** | **4%** |
| **Fee ceiling** | **none** | **10%, enforced in code** |
| Owner | yes, never renounced | **none, structurally** |
| Who decides | the owner, immediately | on-chain vote + 7-day timelock |
| Parameter changes | instant, unannounced | 13 days minimum, fully public |
| Minting | not possible | not possible |
| Supply reduction | tokens moved, supply unchanged | **supply actually reduced** |
| Supply floor | none | **21B, immutable** |
| Exclusion from reflection | owner-toggleable at runtime | **immutable set, fixed at deployment: dead address and liquidity pair** |
| Swap slippage protection | none — accepts any output | bounded against the router's own quote — not a bound on MEV loss |
| Marketing recipient | two wallets, one of them the owner | governance-set — the timelock itself, which is the treasury (Section 11) |
| Staking | none | vote-escrow, rewards in BNB |
| Governance | none | full on-chain governance |

Two points deserve emphasis.

**The fee reduction is not the important part.** Fees can be adjusted by any
project at any time; a lower number proves nothing about how it was arrived
at. What matters is where the number lives and who can touch it. The audited
code initialises the fees at 10/20/20 — reflection 1%, buyback 2%, marketing
2%, a 5% total. The launch configuration set them to 10/10/20 — the 4%
above — in phase 2 of the mainnet deployment on 29 September 2026
(transaction
`0x0e486b53cf9f2b65f34ec78a150e9f814e32c8e2044b1849943e336af102bcca`),
through the temporary governance role the deployer held during setup,
before that role was handed to the timelock and revoked; the post-broadcast
verification read the three values back from the mined chain, and they
read the same at block 127,195,880 on 12 October 2026. No trade had
happened yet: the pool received its liquidity two and a half hours later.
From that moment no single account can change them again: the
only path is a public vote followed by a seven-day timelock. The first time
that path was walked — proposal #0, on testnet, which took the fees from 5%
to 4% — is documented with every transaction hash in Section 9.

**The ceiling matters more than the current value.** The code rejects any
total fee above 10%. This is not a policy that governance can revise: it is a
`require` statement in the contract. Even if every token holder voted in
favour, the transaction would revert. The practical consequence is that DMN
can never become as expensive to transact as DMX is today, regardless of who
controls the protocol in ten years.

**The row on supply reduction is the least obvious and the most
consequential.** In DMX, buyback tokens accumulated at the dead address while
`totalSupply()` stayed at its deployment value forever. In DMN, a
permissionless function removes that balance from the total for real — down
to the floor and no further. The reported supply is the supply.

## 4.3 How the migration works

The migration is a 1:1 exchange with no fee and no deadline pressure beyond a
fixed window. On mainnet the window is 90 days from the migration contract's
deployment: `migrationDeadline` is 1798420124 — 28 December 2026 at
01:08:44 UTC — an immutable value read from the contract. Claims became
possible on 29 September 2026 at 20:06:24 UTC, once the DMX owner had
excluded the migration treasury from the DMX fee (Section 4.1.4), so the
effective window is a few hours short of 90 days. A guardian pause, if one
ever happens, extends the deadline by exactly the paused time (Section 8.6).

At deployment, the entire initial supply of 1,000 billion DMN is created
inside the migration contract. Not in a team wallet, not in a treasury, not
in a distribution contract — inside the contract that exists solely to
exchange old tokens for new ones. No allocation is reserved for founders,
advisors, or private investors, because no such allocation exists to reserve.

The process for a holder is three steps:

1. **Approve** — authorise the migration contract to receive a specified
   amount of legacy tokens.
2. **Claim** — the contract takes the legacy tokens and sends back exactly
   the same number of DMN. No fee is applied in either direction.
3. **Done** — the legacy tokens are transferred to the DAO treasury, not
   destroyed.

Every claim is a transfer of tokens that already existed. Nothing is minted.
The total supply of DMN does not change by a single wei during the entire
migration, and this can be verified on-chain at any point. At block
127,195,880 (12 October 2026), on the thirteenth day of the window,
`totalMigrated` read 341,306,088,146.86 DMX — 34.1% of the old supply, the
initial-liquidity quota of Section 11.5 included — and the total supply of
DMN read exactly 1,000,000,000,000.

## 4.4 What happens to tokens that are never claimed

Not every holder will migrate. Wallets are abandoned, keys are lost,
announcements go unread. Some portion of the supply will remain in the
migration contract when the window closes.

Those tokens are not burned automatically, and they do not become anyone's
property. They remain locked in the migration contract until the DAO decides
otherwise — and that decision requires the full governance cycle: a proposal,
a vote, a seven-day timelock, and an execution that anyone can trigger.

The function that performs this transfer, `sweepUnclaimed()`, has three
constraints written into it:

- it can only be called by the timelock, meaning only as the result of a
  passed vote;
- it reverts if called before the migration deadline has passed;
- it can send the tokens to one address only — the treasury — whose address
  is `immutable`, fixed at deployment and unchangeable by anyone, including
  governance.

There is a detail worth stating plainly, because it will otherwise be
discovered and questioned: the migration contract is a token holder like any
other, and therefore accumulates reflection from ordinary transfers during
the migration window. The balance swept to the treasury will be slightly
larger than the amount left unclaimed. This is the reflection mechanism
working as designed, and the surplus follows the same path as the rest — to
the DAO, decided by vote.

Two holdings will stay almost entirely unclaimed, by decision rather than by
accident: the project's own legacy tokens, held in the two DMX marketing
wallets described in 4.1.4 — about 42% of the old supply before the launch,
39.7% of it after the one claim they made (11.5 gives the dated figures).
The project wallets claimed only the initial-liquidity quota, before the
migration window opened, and the LP tokens of that liquidity went to the
timelock in a published transaction. Everything else stays unclaimed: the
corresponding DMN reach the treasury through `sweepUnclaimed()` like every
other unclaimed token, and they do not vote. Section 11.5 states the
commitment, and what was done, in full.

## 4.5 Why a migration rather than renouncing ownership

A reasonable question: if the goal was to remove the owner, why not simply
call `renounceOwnership()` on the existing contract?

Because renouncing ownership on DMX would have produced a token that nobody
could change — including a token that nobody could fix, improve, or govern.
The fee would have been frozen at 11% permanently. There would be no staking,
no voting, no way for holders to decide anything. The result is not
decentralization; it is abandonment.

Decentralization means decisions are taken collectively, not that decisions
become impossible. That requires a governance system, a timelock, a staking
mechanism to weight participation, and contracts designed around the absence
of an administrator from the first line. None of that could be retrofitted
onto the existing contract.

The migration is the cost of doing it properly.

---

# 5. Architecture

## 5.1 Five contracts

The protocol consists of five contracts, each with a narrow responsibility.

**DaimonV2** — the token. Implements the ERC-20 interface with
reflection-based fee redistribution, the buyback and burn cycle, and the
immutable supply floor. Deployed behind a UUPS proxy, upgradeable only
through governance.

**DaimonStaking** — vote-escrow staking. Holds locked tokens, computes voting
power as a function of amount and lock duration, maintains historical
checkpoints of that voting power, and distributes BNB rewards proportionally.

**DaimonGovernor** — the governance engine. Accepts proposals from holders
above a threshold, runs the voting period, evaluates quorum against a
snapshot taken at proposal creation, and queues successful proposals into the
timelock.

**DaimonTimelock** — the mandatory delay. Holds every approved decision for
seven days before it can be executed, and is the only account with authority
to call privileged functions on the other contracts. It administers itself:
no external account can modify its parameters or its roles.

**DaimonMigration** — the 1:1 exchange. Holds the initial supply, converts
legacy tokens on demand, and can transfer any unclaimed remainder to the
treasury after the deadline, on instruction from the timelock only.

## 5.2 Where authority sits

The distribution of authority is the property most worth verifying
independently, so it is stated here in full.

**No contract has an owner.** There is no `Ownable` inheritance, no
`owner()`, no `onlyOwner` modifier anywhere in the protocol. Access control
is role-based, and after deployment exactly one role holder exists:

```
GOVERNANCE_ROLE  →  held by DaimonTimelock, and nothing else
```

The deployer holds no role. This is not a matter of intention: the deployment
ran in two phases on 29 September 2026, and its scripts renounced every role
they temporarily held during setup, then asserted — with thirty separate
checks across the two phases, each of which would have aborted the
deployment — that no externally owned account retained authority over any
contract. Because an assertion inside a deployment script proves the
simulated state rather than the mined one, a standalone verification then
re-read thirty-six invariants from the live chain: 36 of 36 passed at block
124,627,634, before any liquidity existed (Section 10.6). The same script,
in a post-launch mode with a thirty-seventh check for the open window, can
be re-run by anyone against the live chain; the deployer's roles were read
again at block 127,224,280 on 12 October 2026 — none, on any contract.

Consequently, changing the fee, changing the marketing wallet, changing the
staking contract, adding a lock option, sweeping unclaimed migration tokens,
or upgrading the token implementation are all operations that can only occur
at the end of this sequence:

```
proposal → 1-day delay → 5-day vote → quorum reached
         → queue → 7-day timelock → execution
```

Execution itself is permissionless: once the timelock has elapsed, any
address can trigger it. The decision was made by the vote; the execution is
mechanical.

## 5.3 The two exceptions

Two elements sit outside this structure, and both are deliberate.

**Immutable addresses.** The dead address (destination of burned tokens) and
the migration treasury — the timelock itself, bound in the migration
contract's constructor — are fixed at deployment and cannot be changed by
anyone — not by the deployer, not by governance, not by an upgrade. Some
destinations should not be redirectable, even by a majority.

**The guardian.** One account — on mainnet a Safe multisig,
`0x37F45839765AD3418E29c97d5D92407Ddbf5c7a8`, with three signers and a
threshold of two, the keys held by different people — holds a narrow set of
defensive powers outside the
governance cycle. Three, precisely. It can pause the token in an emergency,
for at most fourteen days per activation, after which the pause lifts on its
own. It can cancel an in-flight governance proposal through the governor,
which atomically cancels the scheduled timelock operation behind it. And it
can cancel a scheduled operation directly at the timelock — a second path
that does not depend on the governor being intact. It cannot change fees,
move funds, alter governance parameters, mint, or upgrade anything, and it
cannot execute: every one of its powers is a brake, never an engine. It
exists because in the early life of a protocol, seven days of timelock is
too slow a response to an exploit in progress.

Every guardian power expires at the same instant, 36 months after launch:
timestamp 1885252112, 28 September 2029 at 01:08:32 UTC. This is not a
commitment to renounce; it is one value, computed by the token when it was
deployed and copied verbatim into the governor and the timelock in the
second deployment phase — read identical from the three contracts at block
127,195,880 — that no one, governance included, can remove or postpone.
After that date pausing and both guardian
cancellation paths stop working, and any pause still armed has already
lapsed. Exactly one way to cancel a queued operation remains: the timelock
cancelling its own operation, which only a self-call can trigger — that is,
an executed governance proposal, never a single party. Decentralization
completes itself without anyone's cooperation.

Section 8.6 describes the guardian's constraints in full.

## 5.4 The deployed contracts

BNB Smart Chain, chain id 56. The contracts were deployed on 29 September
2026 by a deployer that holds no role; every deployment transaction, with
its block and its read-back, is in the launch record (Section 10.6). Verify
an address on chain before interacting with it: a document can be copied, a
contract cannot.

| Contract | Address |
|---|---|
| DMN — the token (`DaimonV2`, UUPS proxy) | `0x160864F9945C52063A7c9f5dcd57C0C89eacbE6a` |
| DMN implementation behind the proxy | `0xA7bC2D4D35e49bdfC8329e3673d7De520832941c` |
| `DaimonMigration` — DMX to DMN, 1:1 | `0x76368b60514b145617385847aCFF7b7EA9764725` |
| `DaimonStaking` | `0xBb596e7308D6C5AED55cEC597D372840Cbe575b1` |
| `DaimonGovernor` | `0x1397a7d25595B718BE6FEEDd42ed5E60F66E16De` |
| `DaimonTimelock` — the treasury; holds the LP tokens | `0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891` |
| PancakeSwap v2 pair DMN/WBNB — the launch pool | `0x40A97Ae210a44057603186B4BE92BAe719342AFA` |
| Guardian — Safe multisig, 2 of 3, until 28 September 2029 | `0x37F45839765AD3418E29c97d5D92407Ddbf5c7a8` |
| DMX — the predecessor (Section 4.1) | `0x36EbA94407B53c631eE822C219e94580fadd67c7` |
| Dead address — destination of burned tokens | `0x000000000000000000000000000000000000dEaD` |

The seven contracts of the deployment — the token proxy, its
implementation, the migration contract, the staking contract, the governor,
the timelock, and the single-use
liquidity seeder of Section 11.3 — were verified on Sourcify and BscScan on
launch day, exact match of creation and runtime bytecode; the audited range
`audit-final` and the deployed source are the same code (Section 10.7).

---

# 6. Tokenomics

## 6.1 Supply

The initial supply is 1,000,000,000,000 DMN — one thousand billion tokens,
with 18 decimals. This number was fixed at deployment and can never increase.

The reason it can never increase is not a policy. **There is no mint
function in the contract.** Not disabled, not permission-gated, not
restricted to governance: absent. No sequence of votes, no upgrade, no
compromised key, and no future decision can produce a single additional
token, because the code capable of producing one does not exist.

Supply can only move in one direction: down.

## 6.2 The floor

Burning is bounded. The contract defines an immutable minimum supply of
21,000,000,000 DMN — twenty-one billion — below which burning is
mathematically impossible.

```
INITIAL SUPPLY   1,000,000,000,000 DMN
                          │
                          ▼  (burn, one direction only)
                          │
FLOOR                21,000,000,000 DMN   ← cannot be crossed
```

The burn function checks this bound before executing and stops exactly at the
floor: if a burn would take supply below 21 billion, only the portion that
reaches the floor is burned, and the remainder is not. Called again
afterwards, the function performs no operation.

This ceiling on deflation exists for a practical reason. A supply that can
approach zero eventually breaks: divisibility limits, rounding behaviour and
liquidity all degrade as the token count collapses. The floor is the point at
which the protocol stops shrinking and starts operating in a different mode —
described in 6.6.

**The floor is a bound, not a destination.** Nothing guarantees that supply
will ever reach 21 billion, and one force works quietly against it: lost
wallets. Tokens whose keys are gone remain part of the total supply. They
keep accruing reflection, so their balance grows; they can never be sold, so
the buyback can never purchase them; they can never be moved, so no one can
burn them. Over time the share of supply that burning can actually reach
shrinks while the unreachable share compounds — and if enough tokens end up
in inaccessible wallets, burning stalls somewhere above 21 billion,
permanently short of the floor.

No function exists to intervene, and none could be added, by construction: a
contract able to take tokens from an address it does not control would no
longer be ownerless — it would hold precisely the power this design exists
to remove. Bitcoin lives with the same asymmetry: millions of BTC sit in
lost wallets, Satoshi's among them, and no one has seriously proposed
recovering them, because the remedy would be worse than the loss. What the
floor guarantees is unaffected either way: burning can never take the supply
below 21 billion. How close it comes is a question of market history, not of
code.

## 6.3 Transaction fees

Every transfer applies a fee, 4% of the transferred amount since launch, split
into three components:

| Component | Rate | Destination |
|---|---|---|
| Reflection | 1% | redistributed to all holders |
| Buyback & burn | 1% | accumulated, then used to buy and burn |
| Marketing / treasury | 2% | converted to BNB; split between the staking reward pool and the treasury by a governance-set share — 100% to stakers at launch, 60/40 after the first mainnet vote |
| **Total** | **4%** | |

Three structural properties matter more than the current numbers.

**The ceiling.** The contract rejects any configuration where the total fee
exceeds 10%. This is enforced by a `require` statement, not by policy. A
proposal setting fees to 11% would pass a vote, wait out the timelock, and
then revert on execution. Governance is bounded by the code it governs.

**Who can change them.** Only the timelock, meaning only the outcome of a
completed governance cycle. The 4% is the launch configuration, set on
29 September 2026 in the second deployment phase, before the deployer's
temporary role was revoked (Section 4.2), and in force from the first trade:
the launch record verifies it to the wei on the first buy and the first sell
the pool ever saw. The first governance cycle in Daimon's history took the
fees from the audited code's 5% to this same 4%, on testnet, and its full
record appears in Section 9. On mainnet no proposal had been created at
block 127,195,880 (12 October 2026).

**Zero is legal — and it is a model change, not a tuning.** The range has a
ceiling and no floor: governance can set every fee to zero. Doing so
switches off nearly everything the fees feed. Reflection stops; no new BNB
accrues; buyback, burn, staking rewards and treasury income run dry once
the already-collected inventory is spent; and for as long as fees stay
at zero, the 21-billion floor of 6.2 is out of reach for good. What would
remain is a freely transferable token with working governance and staking
as pure voting weight. The decision is reversible by the same path that
took it — a later vote can restore any total up to 10% — and thirteen days
of public process stand between the proposal and its effect, which is time
enough to notice, if someone is watching. There is one configuration in
which zero makes sense: a protocol that already has another source of
revenue can drop its transfer fees to remove friction without switching
anything off. That source has to exist first — zeroing the fees does not
create it.

## 6.4 Reflection

The reflection component redistributes 1% of every transfer to all holders,
proportionally to their balance, without any transaction being required to
claim it.

Mechanically, balances are stored in an internal unit of account rather than
in tokens directly. Each taxed transfer reduces the total of that internal
unit, which increases the number of tokens each unit represents. Every
holder's balance grows without any transfer occurring — the redistribution is
a change in the conversion rate, applied simultaneously to everyone.

The practical consequence is that holding tokens produces a slow accumulation
funded by trading activity, with no action required and no gas paid.

Two addresses are excluded from reflection, both fixed when the token is
initialised. The first is the dead address that receives burned tokens:
excluding it prevents burned supply from accruing redistribution that would
inflate the apparent burn figure. The tokens counted as burned are burned;
nothing is added to that number by the mechanism itself. The second is the
liquidity pair: a pair whose balance grows passively while its recorded
reserves stay still is a pair whose surplus anyone can pocket by calling
`skim()` — value taken from the holders the reflection was meant for (audit
finding #30).

There are no other exclusions, and no function exists to create one. This is
a deliberate structural choice: the ability to toggle addresses in and out of
reflection at runtime has historically been the source of the most serious
accounting failures in reflection tokens. That entire class of failure is
absent here because the capability is absent.

## 6.5 The burn cycle

Burning is not scheduled, announced, or triggered by anyone in particular. It
is a consequence of trading.

```
1.  Trading occurs → fees accumulate as DMN inside the contract

2.  Once accumulated fees exceed a threshold, any direct transfer
    of DMN to the liquidity pair — one wei is enough, sent by
    anyone — makes the contract sell one threshold-sized tranche
    on the market, at most one per block → receives BNB

3.  The BNB is split:
        marketing share  →  staking reward pool / treasury, by a
                            governance-set share (100% to stakers
                            at launch, 60/40 after the first vote)
        buyback share    →  retained in the contract

4.  On the same trigger, when the retained BNB exceeds a threshold,
    the contract buys DMN on the open market and sends it to the
    dead address — at most one slice per block

5.  burnDeadBalanceToFloor() removes that balance from total
    supply — permanently, and down to the floor at most
```

Step 5 is **permissionless**: any address can call it, with no special role
required. No one can force it past the floor, and exactly one thing can
delay it: the function respects the guardian's emergency pause — a
deliberate choice, because it writes the same supply accounting an incident
responder would want frozen. During an armed pause window the burn waits, at
most fourteen days per window; otherwise no one can prevent it, and once the
guardian's 36-month mandate ends, nothing can pause it ever again. The
function has no privileged caller because it needs none — its only possible
effect is to reduce supply toward a bound fixed in the code.

Steps 2 and 4 fire on a permissionless trigger and use the public liquidity
pool. Ordinary sales through the router deliberately do **not** trigger
them: the router computes its amounts from a snapshot of the pool's
reserves, and running the protocol's own swaps inside that window would let
a liquidity deposit be mispriced (audit finding #1). The trigger is
therefore a plain transfer of DMN to the pair — anyone can send one wei to
advance the cycle, and per-block budgets cap the aggregate regardless of who
calls or how often. If nobody triggers, fees simply accumulate until someone
does: nothing is lost and nothing blocks. The swaps are protected by a
slippage bound and wrapped so that a failed swap cannot block transfers: if
market conditions make a swap unfavourable, it is skipped and retried at the
next trigger rather than reverting the caller's transaction.

On mainnet, steps 1 to 3 ran for the first time on 29 September 2026, at
05:04:08 UTC, inside the transaction described in Section 10.4:
200,000,000 DMN of fee inventory were sold for 0.081248 BNB, two thirds of
it notified to the staking contract and one third retained for the buyback.
Step 4 waits for the retained BNB to exceed 1 BNB, and each trigger then
spends 5% of it; at block 127,195,880 (12 October 2026) it had not fired
yet, and the dead address held 0 DMN. Step 5 has therefore had nothing to
remove so far.

## 6.6 What happens at the floor

If burning ever brings the total supply to 21 billion, it stops there
permanently. It does not resume, and no vote can restart it.

At that point the buyback component no longer has a destination that reduces
supply. The protocol's design specifies that the revenue previously directed
to burning is redirected in full to stakers — the mechanism switches from
reducing supply to distributing yield, automatically, based on a supply check
rather than a decision.

This is a distant scenario, and — as 6.2 explains — not a guaranteed one. It
is described here because a protocol should specify its terminal state, not
because that state is promised.

---

# 7. Staking

## 7.1 Lock and weight

Staking in Daimon is vote-escrow: tokens are locked for a chosen duration,
and both voting power and reward share are weighted by that duration.

| Lock period | Multiplier |
|---|---|
| 30 days | 1× |
| 90 days | 1.5× |
| 180 days | 2.2× |
| 365 days | 4× |

Voting power is the staked amount multiplied by the period's weight. One
million DMN locked for a year carries the same weight as four million locked
for a month.

The intent is explicit: **influence should track commitment, not only
capital.** A holder who accepts a year of illiquidity has demonstrably more
at stake in the protocol's future than one who can exit in thirty days, and
the weighting reflects that.

Locked tokens cannot be withdrawn before the lock expires. There is no early
exit, no penalty option, no administrative override. The commitment is the
mechanism; making it reversible would remove its meaning.

## 7.2 Rewards in BNB

Staking rewards are paid in **BNB**, never in DMN.

This is a consequence of the supply design rather than a preference. With no
mint function, rewards denominated in DMN could only come from a pre-allocated
reserve — which would eventually be exhausted, and which would have required
holding a large team-controlled balance from day one. Neither was acceptable.

Rewards therefore come from the marketing share of transaction fees. The
protocol converts that share to BNB and deposits a governance-set portion of
it into the staking reward pool — all of it at launch, 60% once the first
mainnet vote routes the remaining 40% to the treasury (Section 11) — where
it is distributed among stakers in proportion to voting power.

Three properties follow:

- **No inflation.** No token is created to pay anyone. The reward pool is
  funded by trading activity that has already occurred.
- **No sell pressure.** A staker claiming rewards receives BNB, not DMN.
  Claiming never puts tokens on the market.
- **External value.** Rewards are denominated in the chain's native asset,
  whose value does not depend on Daimon.

The combined effect is that staking removes tokens from circulation while
returning value that does not have to be sold back into the same market.

Rewards accrue continuously and are claimed on demand. If rewards arrive at a
moment when no tokens are staked, they are set aside in a dedicated reserve
rather than lost — recoverable only by an explicit governance decision, and
never silently folded into a later distribution, where the first staker to
arrive could have captured them.

## 7.3 Voting power checkpoints

The staking contract does not only record current voting power. It records
its history.

Every change — a new lock, a withdrawal — writes a checkpoint keyed by block
number. This allows the governance contract to ask a specific question:
*what was this address's voting power at the block sealed just before
proposal N was created?*

This is what prevents the most obvious governance attack. Without historical
checkpoints, an actor could observe a proposal they dislike, acquire and
stake a large position, and vote it down with power purchased after the
question was raised. With them, the vote is settled against a snapshot of an
already-sealed block: power acquired afterwards — even in the proposal's own
block — counts for nothing.

We tested this specifically, with a simulated attacker holding an
overwhelming position staked immediately after a proposal's creation. Their
voting power at the snapshot was zero, and the vote was rejected — as
designed.

## 7.4 A design choice: voting power does not decay

In the vote-escrow model introduced by Curve Finance, voting power decays
linearly as the lock approaches expiry. A four-year lock confers full weight
on day one and zero weight at maturity; holding influence requires
continuously re-locking.

**Daimon does not implement decay.** Voting power is fixed at the moment of
staking and remains constant until withdrawal, including after the lock has
expired.

This is a deliberate divergence, and it has a real consequence worth stating
openly: a holder who locks at 4×, waits out the year, and never withdraws
retains full voting weight indefinitely while holding the ability to exit at
any time. Influence can concentrate among early, long-term stakers rather
than tracking present commitment.

We accept this trade-off for three reasons. It is simpler and predictable —
voting power is a number a holder can understand without recomputing it every
block. It rewards demonstrated loyalty rather than requiring perpetual
re-commitment. And it avoids the friction of a mechanism that penalises
holders precisely as they approach the end of a commitment they honoured.

A decaying model is not ruled out permanently. It would be a significant
redesign, and if the community concludes it is preferable, it can be
introduced through the same governance process that governs everything else.
The choice is documented here rather than discovered later.

## 7.5 Limits

Two constraints apply to staking and are stated for completeness.

A single stake transaction is bounded by the token's maximum transaction size
(0.5% of supply), an anti-dump limit that applies to all transfers. Very large
positions must be staked across multiple transactions.

The staking contract is excluded from transaction fees automatically when it
is registered, so staking and unstaking do not incur the 4% fee. This
exclusion applies to the contract itself, not to any individual, and is set
by the same governance-only function that registers the contract.

---

# 8. Governance

## 8.1 The cycle

Every change to the protocol follows the same path. There are no shortcuts,
no emergency procedures that bypass it, and no accounts exempt from it.

```
PROPOSAL          any holder above the proposal threshold
     │            submits a target contract and an encoded call
     ▼
1-DAY DELAY       nothing can be voted immediately
     │            voting power is snapshotted at proposal creation
     ▼
5-DAY VOTE        For / Against / Abstain, weighted by voting power
     │            held at the snapshot
     ▼
QUORUM CHECK      at least 10% of total voting power must participate
     │            (For + Abstain — see 8.3)
     ▼
QUEUE             the approved call enters the timelock
     ▼
7-DAY TIMELOCK    mandatory public delay, 604,800 seconds exactly
     │            no one can shorten it
     ▼
EXECUTION         permissionless — any address can trigger it
```

Minimum elapsed time from proposal to effect: **thirteen days**. This is not
a convenience. It is the window in which anyone — a holder, a researcher, a
journalist, an adversary — can read what is coming and act on it before it
happens.

## 8.2 Voting power at the snapshot

Votes are weighted by voting power held **at the moment the proposal was
created**, not at the moment of voting.

This single property closes the most direct attack on any token-weighted
governance: observing a proposal, acquiring a large position, and voting with
influence purchased specifically to decide that question. Under snapshot
voting, tokens staked after a proposal exists carry zero weight on it.

The mechanism is a historical checkpoint written on every change to a
holder's staked position. The governance contract queries that history rather
than the present state.

## 8.3 What counts toward quorum

Quorum is measured as the sum of **For and Abstain** votes, against 10% of
total voting power at the snapshot. Against votes are counted in determining
the outcome, but not in reaching quorum.

This distinction is not cosmetic, and it was not in our original
implementation. During adversarial testing we found that counting Against
votes toward quorum produced a perverse incentive: a minority opposing a
proposal could, by voting against it, supply the participation needed to
validate the vote — and thereby cause the proposal to pass. Remaining silent
was strictly more effective than voting no.

We reproduced the scenario in a test, confirmed it, and changed the
calculation to match the OpenZeppelin standard, which excludes Against votes
from quorum for exactly this reason. The finding, the fix and the test that
demonstrates the corrected behaviour are all in the public repository.

A proposal that nobody supports now fails by not reaching quorum — which is
the correct outcome, and requires no one to actively defeat it.

## 8.4 Bounds on governance itself

A system where the majority can do anything is not safer than a system where
one person can do anything; it is only slower. Several constraints are
therefore placed above governance, in the code, where no vote can reach them:

| Constraint | Value | Who can change it |
|---|---|---|
| Maximum total fee | 10% | **no one** |
| Minimum supply (burn floor) | 21 billion | **no one** |
| Minimum quorum | 10% | **no one** |
| Minimum timelock delay | 7 days | **no one** |
| Dead address | fixed at deployment | **no one** |
| Migration treasury address (the timelock) | fixed at deployment | **no one** |
| Mint capability | does not exist | **no one** |

A proposal violating any of these would pass a vote, wait out the timelock,
and revert on execution. The protocol declines instructions it was built to
refuse.

## 8.5 What governance can do

Within those bounds, the DAO controls the protocol completely:

- adjust the fee split and total (up to the ceiling)
- change the recipient of the treasury share of the fees, and the split
  between stakers and treasury
- change the staking contract
- add or disable staking lock options
- adjust operational thresholds (swap trigger, slippage tolerance, maximum
  transaction size)
- sweep unclaimed migration tokens to the treasury after the deadline
- **upgrade the token implementation itself**

The last item deserves emphasis. The token is deployed behind a UUPS proxy,
and the upgrade authorisation function is restricted to the timelock. This
means the protocol can evolve — but only through the full public cycle, and
never at the discretion of any individual. It also means the community
carries real responsibility: an upgrade is the most powerful instrument in
the system, and the seven-day delay exists so that a bad one can be seen
coming.

## 8.6 The guardian

One account holds a small set of powers outside the governance cycle, all
defensive. The guardian is a 2-of-3 multisig — on mainnet the Safe of
Section 5.4: three keys held by different people, two of which must sign.
It holds exactly three authorities. It can
**pause the contract**. It can **cancel a governance proposal through the
governor** — an atomic cross-cancel that also voids the timelock operation
of a proposal already queued. And it can **cancel a scheduled operation
directly at the timelock**, a second path that does not depend on the
governor being intact. That is the entire scope of its authority: brakes,
never an engine.

It cannot change fees, move funds, alter governance parameters, mint,
upgrade, propose, or vote. It can stop transfers for a bounded window and it
can stop a specific governance action from executing; nothing else.

It exists for a narrow reason: in the early life of a protocol, seven days
of timelock is not a viable response time to an exploit in progress — and a
malicious proposal caught mid-flight needs a faster off-switch than a
counter-proposal. The guardian is the fire alarm, not a seat at the table.

Four constraints define it:

**A pause is a window, not a switch.** Activating the pause arms it for at
most fourteen days — enough to cover one full governance response cycle —
and then it lapses on its own, with no transaction needed. Keeping the token
paused requires actively renewing the window, and every renewal is a public,
visible act. A lost key or a silent guardian cannot leave the protocol
frozen.

**Everything expires, at one instant.** All three authorities — the pause
and both cancellation paths — end 36 months after launch: on 28 September
2029 at 01:08:32 UTC, timestamp 1885252112. The deadline is a timestamp the
token computed at deployment; the governor and the timelock, deployed in a
second phase, received that exact value read back from the chain, so the
three copies are identical by construction — re-verified on-chain after
deployment, read identical again at block 127,195,880, and modifiable by no
one, governance included.
After it, new pauses and both guardian cancellation paths are refused, and
any pause still armed has already lapsed. From that moment only one thing
can cancel a queued operation: the timelock itself, through a self-call —
which is to say an executed governance proposal, thirteen public days and a
majority vote, never a single party. Whatever passes the vote and the
timelock, executes.

**It cannot cost holders the migration.** Every second of pause is credited
to the migration deadline: if a pause blocks claims, the claim window is
extended by exactly the blocked time. Censorship can delay the exchange; it
cannot consume it.

**It is visible.** Pausing, renewing a pause, and cancelling are on-chain
events. There is no way to use these powers quietly.

The guardian is a temporary compromise with reality, bounded in scope,
bounded in time, and designed to disappear without requiring anyone's
cooperation.

---

# 9. Case study: Proposal #0

Every claim in Section 8 describes intended behaviour. This section describes
what actually happened when the system was used.

The following is the complete record of the first decision taken by the
Daimon DAO, executed on BSC testnet. Every step is a public transaction.

## 9.1 The decision

**Proposal #0 — reduce total fees from 5% to 4%** (reflection 1%, buyback 1%,
marketing 2%).

The proposal was created by a holder, targeted the token contract, and encoded
a call to `setFees(10, 10, 20)`. Nothing about its creation required
permission.

Its on-chain description reads:

> *"Riduzione fee totale al 4% (tax 1%, buyback 1%, marketing 2%)"*

The text is in Italian and appears untranslated throughout the interface,
including in the English version. Proposal descriptions are on-chain content
authored by the proposer and immutable once submitted; translating them in
the interface would break the correspondence between what a user reads and
what the blockchain contains. What is displayed is byte-for-byte what was
recorded.

## 9.2 The timeline

All times UTC. Every value below is read from contract state, not from
project documentation.

| Stage | Timestamp | UTC |
|---|---|---|
| Created — voting power snapshotted | `1783467501` | 7 Jul 2026, 23:38:21 |
| Voting opened (after 1-day delay) | `1783553901` | 8 Jul 2026, 23:38:21 |
| Vote cast — 3,000,000 in favour | | 9 Jul 2026, 22:36:42 |
| Voting closed (after 5-day period) | `1783985901` | 13 Jul 2026, 23:38:21 |
| Queued into the timelock | `1783991100` | 14 Jul 2026, 01:05:00 |
| **Executable from** | `1784595900` | **21 Jul 2026, 01:05:00** |
| **Executed** | | **21 Jul 2026, 01:11:09** |

Result: 3,000,000 voting power in favour, 0 against, 0 abstaining, against a
required quorum of 300,000. Final status: **Executed**.

The interval between queueing and executability is 604,800 seconds — seven
days, to the second.

Transactions:

| Action | Hash |
|---|---|
| Propose | `0xa6e465fb70da2b587f8ab7795a22cfc7c29bc984d571020260178b6af2cb5035` |
| Vote | `0x90e22db141f83b1b9fb004faaabde852da721b55856594122c1f0cf9564e1480` |
| Queue | `0x3d5adeac84a205edd963af483de98bd0f40be0491532ed4dc9b0f2418fee2920` |
| Execute | `0x5aa519a9884d24037f0cb903f3565f1a9e5e87529e5d4c1baa3f0c054302fe5f` |

The complete cycle is public. Nothing about this decision happened off-chain.

All four were sent from the same address. The propose, vote and queue
transactions occupy nonces 6, 8 and 9 in that wallet's sequence — the order
the protocol requires, with the vote correctly positioned between the other
two.

## 9.3 The part that matters most

On 17 July — four days before execution was possible — we attempted to
execute the proposal.

It was a human error: a mistake about the date, made by people who had built
the system and knew precisely how it worked. We ran a coherence check before
signing, and it returned the reason the attempt would fail:

```
readyTimestamp   21 Jul 2026, 01:05:00 UTC
current time     17 Jul 2026, 08:34:44 UTC
remaining        318,613 seconds  (3 days, 16.5 hours)
```

Had we proceeded anyway, the transaction would have reverted with `TooEarly`.
The contract does not distinguish between a malicious early execution and a
confused one; it refuses both identically.

This is the entire argument for a timelock, demonstrated rather than asserted.
It does not exist because we distrust bad intentions. It exists because
good intentions are not sufficient — people lose track of dates, work at
three in the morning, and are certain about things that are wrong. The system
is not.

Four days later, execution succeeded six minutes after the window opened. Not
one second earlier, because it was not possible.

## 9.4 Verification of the result

The fee change was confirmed on two independent levels.

**Contract state**, read directly:
```
taxFee        = 10   →  1%   (reflection)
buybackFee    = 10   →  1%   (buyback & burn)
marketingFee  = 20   →  2%   (marketing / operations)
                        ────
                        4%
```

**Economic behaviour**, measured on a real transfer of 1,000,000 DMN:

| | Amount |
|---|---|
| Sent | 1,000,000.000000 DMN |
| Fee applied | **40,000.000000 DMN — exactly 4.00%** |
| Received | 960,000.000000 DMN |
| Total supply change | zero |

Before execution the same transfer would have carried a 50,000 DMN fee. The
governance cycle did not merely update a stored value: it changed how the
token behaves, and the change is measurable to the wei.

## 9.5 The proposal cannot be executed twice

Calling `execute(0)` again returns:

```
execution reverted: 0x0dc10197   →   AlreadyExecuted()
```

The check is the first statement in the function, before any other logic. A
signed and paid transaction would fail identically. The interface offers no
button for it, because the executed state has no available actions.

## 9.6 A proposal that failed

Proposal #1 was created deliberately as a test and deliberately not voted on
by anyone.

At the end of its five-day voting period it reached zero votes, failed to meet
quorum, and its status became **Defeated** — automatically, with no
transaction required and no one acting to reject it.

This is the outcome we wanted to observe on-chain. In a system with no veto
power, a proposal without support does not need to be stopped. It expires.

## 9.7 What this record demonstrates

Between these two proposals, every state of the governance machine has been
observed with real transactions: Pending, Active, Succeeded, Queued, Executed,
and Defeated. The rejection paths — execution before the timelock expires,
and execution of an already-executed proposal — were both triggered and both
refused.

The complete record, including transaction hashes for every step, is
published in `TESTNET_RESULTS.md` in the project repository.

---

# 10. Security

## 10.1 Threat model

Security begins by naming the adversaries. The following actors are
considered, with what each can and cannot do.

**An external attacker.** Can call any public function, in any order, at any
time, with any amount. Cannot acquire an administrative role, because none
is assignable: `GOVERNANCE_ROLE` administers itself and there is no
`DEFAULT_ADMIN_ROLE` through which it could be granted.

**A whale.** Can accumulate a large position and stake it for maximum
weight. Cannot vote on any proposal created before their stake, because
voting power is evaluated against a historical snapshot. Cannot exceed the
maximum transaction size in a single transfer.

**Governance itself.** Can change every operational parameter and upgrade the
token implementation. Cannot mint, cannot burn below the floor, cannot raise
fees above 10%, cannot lower the quorum below 10% or the timelock below seven
days, cannot redirect the dead address or the migration treasury. The
protocol constrains its own governance.

**The guardian** — a 2-of-3 multisig (Section 5.4). Can pause the contract in
self-terminating fourteen-day windows, cancel a proposal through the
governor, and cancel a queued operation directly at the timelock. Cannot
touch funds, parameters, or execution — and every one of these powers ends
at the same 36-month expiry, after which any armed pause has already lapsed
and only a governance self-call can cancel.

**The deployer.** Could deploy the contracts and pay the gas. Held a
temporary governance role during the second deployment phase, used for the
launch configuration and revoked in the same broadcast. Holds no role
afterwards: the deployment scripts renounced every temporary permission and
then verified, with thirty assertions across the two deployment phases
and a thirty-six-check verification read back from the live chain, that
no externally owned account retained authority anywhere in the system. On
mainnet the deployer's last transaction was the single-use liquidity-seeding
contract of Section 11.3; it has signed nothing since, and at block
127,224,280 (12 October 2026) it held no role on any contract.

The full threat model, including the reasoning behind each conclusion, is
published as `THREAT_MODEL.md` in the repository.

## 10.2 What has been tested

The protocol carries 203 automated tests, all passing: the 180 of the audited
range `audit-final`, across the six categories below, and 23 added after the
audit for the launch tooling outside that range — the single-use
liquidity-seeding contract of Section 11.3 and the predecessor's transaction
cap as the migration meets it.

**Unit tests** cover individual functions and their boundaries.

**Governance sequence tests** verify that no ordering of operations produces
an execution without a passed vote, a completed queue and an elapsed timelock.

**Fuzz tests** run each property against 512 randomised inputs: that
transfers never create tokens, that staking grants exactly the weighted
voting power, that withdrawal returns capital 1:1, that migration is exactly
1:1, that rewards never exceed the BNB deposited, that fees can never be set
above the cap.

**Invariant tests** are handler-based: a driver hammers the system with
random sequences of actions — 16,384 calls per invariant — while the
following must hold at every step:

- total supply never exceeds the initial supply and never falls below the
  floor
- total voting power equals the sum of active locks, and equals the sum of
  per-user voting power
- migration accounting is conserved
- the reward balance equals deposits minus claims
- no administrative role is acquirable by any actor

**Adversarial tests** target the system as an attacker would: snapshot
manipulation, extreme boundary values (one wei, the entire supply, the exact
floor, one second before the timelock expires), and game-theoretic incentives.

**Audit regression tests** reproduce the audit findings that were fixed in
code. Each asserts the secure behaviour, so it failed on the pre-fix code
and passes on the audited range: a regression would be caught by the test
that reproduced the original finding.

Static analysis is run with Slither. Every High and Medium finding has been
examined and documented — with the reasoning — as either a false positive in
this context or an already-mitigated condition; the classification is
published in `THREAT_MODEL.md`. Low-severity hardening suggestions were
applied to the code.

## 10.3 What we found ourselves

Two findings emerged from our own adversarial round, after the code was
otherwise complete. Both are documented here because a security section that
reports only successes is not a security section.

**Finding 1 — Against votes counted toward quorum.** As described in 8.3,
this created a perverse incentive: opposing a proposal could help it pass.
We reproduced it in a test, then changed the quorum calculation to count
For + Abstain only, matching the OpenZeppelin standard. Fixed before the
audit scope was frozen.

**Finding 2 — Voting power does not decay after the lock expires.** Described
in 7.4. This is a design consequence rather than a defect: influence can
concentrate among early long-term stakers. We accepted and documented it
rather than fixing it, because a decay mechanism is a redesign rather than a
correction. It remains open to a future governance decision.

## 10.4 Known limitations

The following are properties of the system that we consider acceptable but
which a reader should know. None of them are hidden in the code.

**Residual MEV exposure.** Automated swaps are protected by a slippage bound,
which limits but does not eliminate sandwich attacks. Fully removing the
exposure would require a time-weighted price oracle; the bound is the
trade-off chosen.

**Upgradeability.** The token can be upgraded by governance. This is a
capability, and capabilities carry risk: a harmful upgrade approved by a
majority is possible in principle. The seven-day timelock exists so that such
a proposal is visible for a week before it can take effect.

**Rounding dust.** Reflection and reward calculations use integer division,
leaving amounts of a few wei unattributed. We measured this precisely during
testnet reward distribution: across three claims, the residue was two wei,
each attributable to one floor division. It is accounted for, not ignored.

**Router dependency.** Automated swaps depend on the PancakeSwap router. If
that contract were compromised or the liquidity pool drained, the swap
mechanism would degrade. Swaps are wrapped so that failure cannot block
ordinary transfers.

**The least-proven path.** The sequence fee accumulation → swap to BNB →
distribution → automatic buyback was, until launch, exercised on testnet
only: in the July campaign on a pool with minimal liquidity, in the level-2
rehearsal of August–September on a real router with real gas, where the
first conversions moved a testnet-sized pool heavily, and in the
launch-configuration campaign of September. We considered it the
least-proven surface of the protocol; it was flagged as such to the auditor,
and two of the audit's findings (#1 and #28) changed how it is triggered —
Section 6.5 describes the result. On mainnet the first three steps ran on
29 September 2026, under adversarial conditions from the first minute: the
transaction described next converted the first 200,000,000 DMN of fee
inventory into 0.081248 BNB and the split distributed it as designed. The
automatic buyback had not fired at block 127,195,880 (12 October 2026); it
waits for the retained BNB to exceed its threshold. From here on the record
of this path is the chain, not a test.

**A dust stake placed just before a reward notification.** Found on launch
day, 29 September 2026: when the launch runbook resumed at 17:12 UTC, the
values it expected no longer held, and the protocol's monitor (Section
10.5) identified the cause. One transaction,
`0xa1238092425b7c1cc0840568d1ce9fe7534f842e584555049df353363f2ed048`
(block 124,657,486, 05:04:08 UTC — one hour and eighteen minutes after the
liquidity was added, before anyone had staked), did the following in one
atomic sequence: it borrowed 0.022 BNB in a flash loan; bought DMN from the
launch pool; staked one wei of it for thirty days, which made its voting
power the whole of `totalVotingPower`, until then zero; donated
48,438,526.78 DMN to the token contract, lifting the fee inventory past the
200,000,000 swap threshold; sold the DMN it still held; then sent one wei
of DMN to the pair, the public trigger of Section 6.5. The contract sold
200,000,000 DMN for 0.081248 BNB and notified the staking share — two
thirds, 0.054165 BNB — to the staking contract, where a single staker with
one wei of voting power held 100% of it; the same transaction claimed it.
Two figures circulate for this event and both are right: 0.054165 BNB is
the staking share captured, read from the `RewardNotified` and
`RewardClaimed` events of the receipt; about 0.033 BNB is what the sender
kept after repaying the flash loan (0.022055 BNB) and adding its small sale
(0.000699 BNB) — the difference is the DMN it bought and gave away to arm
the trigger.

What this is, exactly. The audit fix #35 (Section 7.2) protects BNB that
arrives while nobody is staked: it goes to a reserve only governance can
move. It does not protect BNB that arrives when the total voting power is
nearly zero rather than zero: once any power exists, a notification is
distributed pro rata, and one wei against one wei is everything. The trigger
is public by design, and a donation to the token contract can arm it. We
did not foresee the combination. The
exposure is structural to the empty-staking period and closes by itself as
soon as real positions exist, because a stake cannot exit for thirty days
and a dust position receives a dust share of anything notified afterwards.
That period is over: at block 127,195,880 (12 October 2026) the staking
contract held 255.23 billion DMN in about 170 locks, with a total voting
power of 1.0028 × 10^30. What the transaction took was the staking share of
the first conversion, at a moment when no one else was staked to receive
it. The transaction touched neither the migration's
custody nor the pool's LP tokens, and it gave the sender no governance
power: one wei is far below the proposal threshold, which the governor
reads as 1,000 × 10^18 units of voting power — the power of 1,000 DMN
locked for thirty days at the 1× multiplier (read at block 127,226,547,
12 October 2026). The 4% fee of Section 6.3 was verified to the wei on this
transaction's own buy and sell. The reconstruction from the forty logs of
the receipt is in the launch record (Section 10.6).

## 10.5 The interface is not the protocol

A question worth answering explicitly: what happens if the website is
compromised?

The web interface is a stateless public frontend. It holds no keys, custodies
no funds, maintains no database and no authenticated sessions, and never
signs anything. Every interaction with the chain happens in the user's own
browser, with the user's own wallet, requiring the user's own signature.

The interface is never in the custody path or the signing path. Its attack
surface is therefore **availability, not funds** — a compromised or
unavailable frontend cannot move anyone's tokens, because it never had the
ability to move them in the first place.

The realistic worst case is that the page stops working. The contracts remain
fully usable through a block explorer or a command-line tool, as they were
throughout months of testing before the interface existed.

This is a deliberate consequence of the architecture rather than a fortunate
accident: the protocol is the contracts, and the interface is a convenience
placed in front of them. Anything that can be done through the interface can
be done without it.

The interface is published at `app.daimon.money`; the project's site is
`daimon.money`. Since 8 October 2026 (current version since 9 October) the
interface has a second, content-addressed home: a static build on IPFS,
reachable through the name
`daimon.blockchain` (an Unstoppable Domains name whose records live on
Polygon) and identified by its content hash —
`bafybeidmjrqs56gw4vqlnqptv4fungoayec6do7oojstfmoxjzidd6kvyq` for the
current version, tag `mirror-v2`. The build is reproducible: a pinned
container recipe in the repository produces the same hash from the tagged
commit, so anyone can rebuild it and compare. A different hash is a
different site, whoever serves it. The procedure, the pins and the name
record are in `docs/IPFS_MIRROR.md`.

A separate service, the monitor, watches the contracts and reports what it
sees on a private alert channel of the project. It is read-only: it holds no
key that can move funds or sign a transaction; its only secrets are its own
alert and data-provider credentials. Its specification is
`docs/SPEC_MONITOR.md`. It has run
on mainnet since launch day; when, on that day, the state no longer matched
the runbook's expectations, it is what identified the transaction of
Section 10.4 as the cause.

The same reasoning applies to the interface's software dependencies. Known
advisories affecting them are documented in `SECURITY.md`, together with an
assessment of whether the conditions required to exploit each one exist in
this application at all. The contracts themselves have no runtime
dependencies of this kind.

## 10.6 What has been demonstrated on-chain

Beyond automated testing, the following functional cycles have been executed
and documented on BSC testnet, each with transaction hashes:

- 1:1 migration, verified to the wei
- fee application and reflection distribution, verified to the wei
- vote-escrow staking with weighted voting power, and rejection of early
  withdrawal
- the complete governance cycle described in Section 9
- autonomous fee-swap on a real liquidity pool, with BNB actually received
  by the marketing wallet and the staking reward pool
- the first real burn: 44,785,811 DMN removed from total supply
- multi-wallet reward claims, reconciled to the wei across three addresses
- guardian pause and unpause
- rejection of early execution (`TooEarly`) and of double execution
  (`AlreadyExecuted`)
- economic verification of the post-execution fee: exactly 4.00%

The last function of the system — the governance sweep of unclaimed
migration tokens to the treasury — was executed afterwards, on 7 August
2026, as proposal #2: 999,121,813,473 DMN moved from the migration contract
to the treasury by a passed vote, after its seven days, with the total
supply unchanged to the wei.

The complete record is published as
[`TESTNET_RESULTS.md`](https://github.com/daimon-dao/daimon-dao/blob/master/TESTNET_RESULTS.md).

**Four rehearsals of the launch itself.** After the audit, the audited code
was deployed four more times with the mainnet scripts, at increasing
fidelity. Level 1, on a local fork where time can be warped, proved the
logical sequences: the launch order, the cancellation paths, the pause and
its expiry, and the
deviation that turned the deployment into two phases (a single-broadcast
script fixes the guardian expiry during simulation while the token computes
its own from the block it is mined in). Level 2, on the public BSC testnet
in real time from 28 August to 10 September 2026, proved what a local node
cannot: real nonces, real gas, 34 of 34 post-broadcast checks read from
mined state, the guardian expiry identical across the three contracts, and
a full governance cycle on a real clock — propose, vote, queue, seven real
days of timelock, execute — every transaction signed from an encrypted
keystore and recorded. A third campaign, on the same testnet from 14 to
28 September 2026, rehearsed the launch configuration as finally decided —
the 4% set at deploy, the timelock as the fee destination, the
liquidity-seeding step, two further verification checks (34 became 36) —
and ran the first mainnet proposal, the 60/40 split of Section 11.3, end to
end on a real clock as its proposal 0. The fourth rehearsal ran the launch
day step by step on a local fork of BNB Smart Chain mainnet against the
real DMX contract, the real DMX pool and the real router, at the real gas
price, so that the funding figures of the launch were the figures of the
rehearsal. All the journals are public:
[`TESTNET_L1_RESULTS.md`](https://github.com/daimon-dao/daimon-dao/blob/master/TESTNET_L1_RESULTS.md)
(with its follow-up
[`TWO_PHASE_RESULTS.md`](https://github.com/daimon-dao/daimon-dao/blob/master/TWO_PHASE_RESULTS.md)),
[`CHAPEL_L2_RESULTS.md`](https://github.com/daimon-dao/daimon-dao/blob/master/CHAPEL_L2_RESULTS.md),
[`CHAPEL_2B_RESULTS.md`](https://github.com/daimon-dao/daimon-dao/blob/master/docs/CHAPEL_2B_RESULTS.md)
and
[`MAINNET_FORK_RESULTS.md`](https://github.com/daimon-dao/daimon-dao/blob/master/docs/MAINNET_FORK_RESULTS.md).

**Mainnet.** On 29 September 2026 the audited code was deployed to BNB Smart
Chain, chain id 56, unchanged: `src/` at the deploying commit differed from
`audit-final` by nothing, and still does at the commit that releases this
document. The sequence, all times UTC:

| Step | Block | Time | What happened |
|---|---|---|---|
| Phase 1 | 124,626,062 – 124,626,108 | 01:08:24 – 01:08:44 | token implementation, token proxy (DMN) and migration contract deployed; the migration deadline fixed, immutably, at 1798420124 |
| Phase 2 | 124,626,867 – 124,627,202 | 01:14:26 – 01:16:57 | timelock, staking and governor deployed; roles granted to the timelock and the guardian; fees set to 10/10/20 and the staker share to 1000; every temporary role revoked — sixteen transactions, `All decentralization asserts passed` |
| Verification | 124,627,634 | | 36 of 36 invariants read back from mined state |
| Source verification | | | the seven contracts of the deployment verified on Sourcify and BscScan, exact match |
| Initial liquidity | 124,642,589 → 124,647,068 | 03:12:23 → 03:45:59 | the DMX owner exchanged 4,999,548,574.36 DMX for DMN 1:1 (`0x39b44eab12057cd2396cbc1200e45bc89f9b2bd9623cc717a4c5557af4889549`); a single-use seeding contract then added 4,799,566,631.39 DMN and 1.994 BNB to the pair and sent the 97,828.093 LP tokens to the timelock, in one transaction (`0xdc8dd206e10e5293e7380163d13d3f4bb5575662d0eddef99f9bddd7f7b8dfa4`; Section 11.3) |
| First conversion | 124,657,486 | 05:04:08 | the fee cycle of Section 6.5 ran for the first time, inside the transaction of Section 10.4 |
| Window opened | 124,767,991 → 124,777,699 | 18:53:34 → 20:06:24 | the DMX owner raised the DMX transaction cap to the entire supply (`0xfaef2123e54dd4d5054b9195284d43576e35c5161e178ae5e8b810f9b620b47b`), then excluded the migration treasury from the DMX fee (`0x8aaac289174a13a61040a68503550d79b31cdc25e1884686e8a42632f04cd54d`); from that block any DMX holder can claim |

Two steps of the runbook were skipped by decision: a test swap by the owner,
because the 4% fee had already been verified to the wei on the buy and the
sell of the first-conversion transaction, and a first manual trigger of the
fee swap, because the first conversion had already happened. Every
transaction, every read-back, the eight deviations from the runbook and the
reconstruction of the incident are in the launch record,
[`docs/MAINNET_LAUNCH_RECORD.md`](https://github.com/daimon-dao/daimon-dao/blob/master/docs/MAINNET_LAUNCH_RECORD.md).

Read at block 127,195,880, 12 October 2026: 341,306,088,146.86 DMX
migrated (34.1% of the old supply, the initial-liquidity quota included);
255.23 billion DMN staked; no proposal yet in the governor; the token never
paused; the timelock holding exactly the 97,828.093 LP tokens minted at the
seed, no BNB, and 341,401,083,142.59 DMX in custody; the deployer with no
role anywhere; the three guardian-expiry values identical.

## 10.7 External audit

Everything above was produced by the same people who wrote the code. That is
useful and insufficient.

The contracts were frozen at tag `audit-scope-v2` and reviewed
independently by Zenith. The audit is complete. The report is published in
full — not a summary, not a certificate, not selected excerpts:
[Daimon DAO — Zenith Audit Report](https://github.com/zenith-security/reports/blob/main/reports/Daimon%20DAO%20-%20Zenith%20Audit%20Report.pdf).

It records 37 findings: 1 critical, 1 high, 7 medium, 12 low and 16
informational. 29 were fixed in code; 8 were accepted, each with written
reasoning. The exact range of code the report describes is frozen forever at
tag `audit-final`. Every rehearsal since ran that code untouched, and so did
the mainnet deployment of 29 September 2026: `src/` differed from
`audit-final` by nothing at the deploying commit, and differs by nothing at
the commit that releases this document.

Three commitments were made before the audit. Their status:

**The report is published in full** — kept, at the link above.

**We will not deploy to mainnet before it is complete** — kept. The audit
was complete and its report public in August 2026; the mainnet deployment
followed on 29 September, after the four rehearsals of Section 10.6 and the
published mainnet checklist, which marks as such the items it left open at
launch.

**The auditor received our own list of concerns**, including the
least-proven path described in 10.4. Two findings (#1 and #28) came out of
that surface. An audit exists to find what we missed, not to confirm what
we already know.

A bug bounty funded by the treasury will be proposed to governance, so that
the incentive to report a vulnerability permanently exceeds the incentive to
exploit it. Until then, responsible disclosure is welcome and will be
credited publicly (`SECURITY.md`).

---

# 11. Funds and treasury

## 11.1 One treasury, and it is a contract

Protocol funds have one home: the timelock. The DaimonTimelock contract
*is* the treasury — not a wallet that points to it, not a multisig that
manages it on its behalf. It has no owner and no keys. Nothing leaves it
except through a public governance proposal: five days of voting, seven days
in the open, then an execution anyone can trigger. The guardian, during its
36-month mandate, can cancel a queued outflow; it can never redirect one,
and after the mandate only a vote can cancel at all.

The migration contract's `treasury` pointer is the timelock's address,
bound `immutable` in its constructor and derived at deployment rather than
typed in: phase 1 bound it to the timelock address phase 2 would create,
phase 2 verified the prediction came true, and the post-broadcast
verification re-read it from the live chain; it reads
`0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891` (Section 5.4) at block
127,195,880. The legacy tokens collected by every claim, and the unclaimed
DMN swept after the deadline, therefore land in the same governed contract
as everything else.

## 11.2 Why there is no operational wallet

The v0.1 draft of this document described two locations: a governed
treasury, and an operational multisig receiving the marketing share of the
fees in BNB, with known signers, for small recurring expenses. That model is
withdrawn, and the reason is worth stating rather than hiding.

Part of the protocol's income, paid into a wallet managed by people, is —
for a project with no legal entity — income of those people. A contract
governed by public vote is not, until it distributes. So there is one
treasury and no operational wallet, and no signer anywhere in the flow of
funds. The flexibility the operational wallet was meant to provide — small,
frequent expenses without a vote for each — will come from the legal entity
the protocol is expected to fund, once it exists, through periodic budgets
approved by proposal and accounted for in public. Until then, a payment for
work done for the protocol is a proposal like any other.

## 11.3 What flows in, and when

**At launch, nothing from fees.** `marketingWallet` was set to the timelock
at deployment, and the share of the marketing fee routed to stakers was set
to 1000 basis points — all of it — in the second deployment phase. The
arithmetic makes the amount that would reach the treasury exactly zero, and
no transaction to that address fires. The post-broadcast verification
asserted the share from mined state; at block 127,195,880 (12 October 2026)
the share still read 1000 and the timelock held no BNB.

**From the first vote, 40%.** The first mainnet proposal sets the split to
60% stakers / 40% treasury — the 60/40 the code was written with, now
pointed at a contract rather than a wallet. From that vote on, the
treasury's share accumulates in BNB, untouched by anyone, until a further
vote spends it. The proposal is written: `docs/G1_PROPOSAL.md` gives its
exact calldata, its timeline and its rehearsal on a fork of mainnet, and the
same call ran end to end on the public testnet as proposal 0 of the
launch-configuration campaign (Section 10.6). At block 127,195,880 it had
not been created: the governor's proposal count read zero. The order of the
first votes — the split; the fee exemption of the treasury; a first, small
deposit; after the window closes, the sweep and the continuity burn of 11.6;
the first budget of a legal entity, if one is formed — is published in the
treasury policy (section 7) and, proposal by proposal, in
`docs/CALENDARIO_GOVERNANCE_Q1.md`.

**Three inflows the code provides by itself.**

- *The legacy tokens.* Every migrating holder's DMX are transferred to the
  treasury, where they stay in non-circulating custody until the sweep of
  the unclaimed DMN has executed — the effective deadline, pause credit
  included — an audit requirement (finding #6), now a property of a
  contract rather than a promise by signers: nothing can move them before a
  vote. At block 127,195,880 the timelock held 341,401,083,142.59 DMX.
- *The unclaimed DMN.* After the deadline, governance sweeps whatever DMN
  remain in the migration contract into the treasury (Section 4.4).
- *The pool itself.* The LP tokens of the initial DMN/WBNB liquidity were
  minted straight to the timelock. On 29 September 2026 the liquidity
  provider — the DMX owner, which claimed only that quota (11.5) — approved
  a single-use seeding contract, `LiquiditySeeder` at
  `0x21ab79825b86137CF1b04884FCFC4e4b717ce062`, and the contract added
  4,799,566,631.39 DMN and 1.994 BNB to the pair and sent the 97,828.093 LP
  tokens it received to the timelock in the same transaction
  (`0xdc8dd206e10e5293e7380163d13d3f4bb5575662d0eddef99f9bddd7f7b8dfa4`,
  block 124,647,068, 03:45:59 UTC). The 4,999,548,574.36 DMN the owner had
  claimed became 4,799,566,631.39 in the pool because the seeding transfer
  paid the 4% fee like any other; its 3% non-reflected part, about
  150 million DMN, was the protocol's first fee inventory. The launch record
  asserts from mined state that neither the owner nor the deployer held any
  LP token afterwards; at block 127,195,880 the timelock's balance still
  equalled the whole minted supply less the pair's own minimum liquidity.
  The pool cannot be withdrawn except by vote, and the treasury's position
  in it grows with every swap's fee.

**And, in future, the fees of any service module the DAO adds.**

## 11.4 What governance controls here

The recipient of the fee share and the split between stakers and treasury
are set by governance-only functions: the DAO can redirect that stream at
any time, by vote. Every outflow is a proposal; there is no standing budget
inside the protocol and no one authorised to spend without a vote.

The timelock is not exempt from the transfer fee. At launch it was
deliberately left an ordinary holder, so any DMN that leaves it — for the
continuity burn, for liquidity, for a payment — pays the 4% like anyone
else until a vote exempts it, the second proposal of the published order
(11.3). At block 127,195,880 it was not exempt; the staking contract, by
contrast, is (Section 7.5).

Two *destinations* are permanently fixed, beyond even governance's power to
redirect: the dead address that receives burned tokens, and the migration
treasury. Both pointers are `immutable`, set at deployment. Tokens at the
dead address are beyond anyone's reach, forever. The migration treasury is
the timelock: its address cannot be changed by anyone, and what it holds
moves only by vote. What no majority can do is quietly point either stream
somewhere else.

## 11.5 The project's own tokens

The two DMX marketing wallets described in 4.1.4 — the owner's and the
second one — held about 42% of the old supply before the launch, and
396,610,400,010.00 DMX at block 127,195,880 (12 October 2026): 39.7% of the
total supply, about 41% of the supply outside the dead address. They claimed
only the initial-liquidity quota, before the migration window opened: on
29 September 2026 the owner exchanged 4,999,548,574.36 DMX for the same
number of DMN
(`0x39b44eab12057cd2396cbc1200e45bc89f9b2bd9623cc717a4c5557af4889549`,
block 124,642,589, 03:12:23 UTC), and all of it went into the pool, with the
LP tokens of that liquidity in the timelock (11.3); the owner's DMN balance
was zero at the end of the launch day, and the launch record asserts it.
Everything else stays in the migration contract and reaches the
treasury through `sweepUnclaimed()` after the deadline, without a transfer,
without a fee, and without passing through any person's hands, and does not
vote. The project's tokens become the protocol's: governance is decided by those
who bought their tokens, the team included. What they are for is decided
use by use, by public vote; what they are not for is written in the
treasury policy (version 1.2, tag `treasury-policy-v1.2`) — no burn by
decision, no distribution to holders, stakers or anyone who has not done
work for the protocol, no lotteries.

The personal holdings of the people who build the protocol are a separate
matter, stated in `docs/TEAM_HOLDINGS.md`: DMX bought with their own funds
since 2022, or received as payment for work done; a commitment of conduct —
no sale without thirty days' public notice and an amended version of that
document committed first — dated by the repository's history and binding no
one in law. They migrate like anyone else, 1:1.

## 11.6 The continuity burn

DMX tokens sent to the dead address over the years cannot migrate: no key
exists to claim for them. The DMN that correspond to them are swept to the
treasury with the rest and then sent, by governance vote, to the dead
address — the same amount the DMX dead address holds at a stated block. Once
there, anyone may call `burnDeadBalanceToFloor()` and remove them from the
supply for good. DMN's supply thus resumes exactly where DMX's burn left off
— and this time the supply actually decreases, which the predecessor's
accounting never did (4.1.2).

## 11.7 Commitments

The treasury's address, its balances and every proposal are public. Its
spending is reportable on-chain because every transaction it makes is
visible by construction. Its policy — what it holds, what it may do, what it
will never do — is published as
[`docs/TREASURY_POLICY_v1.0.md`](https://github.com/daimon-dao/daimon-dao/blob/master/docs/TREASURY_POLICY_v1.0.md)
— version 1.2 at the time of this release, frozen at tag
`treasury-policy-v1.2` and in force from the execution of the first
proposal; the file name keeps "v1.0" so that links stay stable — and can be
amended only by the same process that moves the funds. There are
no signers to name, because there is no one to trust.

---

# 12. Roadmap

This roadmap distinguishes between what exists, what is intended, and what is
a long-term possibility. No dates are given beyond the current phase, and
nothing below constitutes a commitment to deliver.

It is also, by design, incomplete. Section 12.4 explains why.

## 12.1 Phase 1 — Now

The protocol described in this document: token, staking, governance, timelock,
migration. Audited, with the report published and the audited range frozen
at tag `audit-final`; rehearsed five times — the July testnet campaign, then
the four post-audit rehearsals of the launch order with the mainnet scripts
(Section 10.6); live on BNB Smart Chain mainnet since 29 September 2026
(Section 5.4), with the migration window open until 28 December 2026 at
01:08:44 UTC, the initial liquidity in place with its LP tokens in the
treasury, and the interface published with a reproducible mirror (Section
10.5).

What remains of this phase: the first governance proposals of the treasury
policy, in the published order (Section 11.3), beginning with the 60/40
split; then, once the window has closed, the sweep of the unclaimed tokens
and the continuity burn (Section 11.6). No date is given.

## 12.2 Phase 2 — Daimon as a DeFi protocol

The current protocol is a token with governance. The intention is for it to
become an ecosystem of financial primitives, owned and directed by the people
who use it.

The direction is deliberate: the tools that determine what happens to
ordinary people's savings — credit, yield, liquidity — are held almost
entirely by institutions that set the terms without consultation. Rebuilding
them as open-source, permissionless contracts governed by their users is the
practical form of the argument made in Section 3.

The primitives we intend to pursue:

**Lending and borrowing.** Supplying assets to earn interest, and borrowing
against collateral. Interest rates determined algorithmically by utilisation
rather than by an institution's policy, collateral requirements visible in
the code, liquidation rules identical for everyone.

**Liquidity provision.** Mechanisms for supplying liquidity and earning a
share of trading activity, with the terms — fee splits, incentive structure,
supported pairs — set by governance rather than by an operator.

**Yield strategies.** Structured products that route capital into
established protocols, with the risk profile of each strategy stated
explicitly rather than buried, and the selection of strategies decided by
vote.

**Further primitives as they mature.** Derivatives, structured credit,
insurance mechanisms, real-world asset integration, cross-chain liquidity —
the DeFi surface expands continuously, and any primitive that can be built as
a permissionless contract is a candidate.

**How this connects to the token.** Each of these generates protocol revenue.
That revenue enters the cycle the token already implements: a share to
buyback and burn, a share to stakers, a share to the treasury. The protocol's
economic engine is already built; Phase 2 is about giving it more to run on.

The stated ambition is that someone with very little capital and no financial
training should be able to access the same instruments as anyone else, on
identical terms, with the rules visible and the governance open to them. That
is the objective. Whether and how far it is reached depends on execution,
resources, and time.

**Constraints that will apply.** Every module will be audited independently
before deployment. Every module will be introduced through governance rather
than announced. Modules that handle user funds will be built with the same
constraints as the core protocol: no owner, no privileged withdrawal, no
parameter without a bound.

**The treasury module.** The treasury exists from launch — it is the
timelock, Section 11 — and until a dedicated module exists it operates by
ad-hoc proposals: few, small, one at a time. A treasury module — an
allowlist of approved assets and protocols, per-operation limits, its own
audit — comes after launch and after the first service module, when the
treasury can pay for it. A treasury able to interact with external contracts
is the largest and most attractive attack surface a protocol can create, and
it is not built on credit.

What the treasury is meant to hold is decided already, and will be reached
by proposals over time: **20% BNB, 40% BTCB, 40% XAUt** — the chain's own
asset for operations, gas and deposits, and the two premises the project
started from, Bitcoin and gold. **Never stablecoins**: not as a reserve, not
as a parking place, not as an exception. What can be printed is not money
by this treasury's definition.

**Said plainly: BTCB and XAUt are custodial wrappers.** Native Bitcoin does
not exist on BNB Chain, and gold exists on no chain except as a claim on
bars in someone's vault. Holding them means accepting an issuer's risk. The
treasury accepts it, states it, and pursues the only mitigation there is:
the deepest, most audited issuers available on this chain, and
diversification across issuers as more become available. The choice of XAUt
is a choice of chain, not of faith.

**On what this is not.** Capital that earns is capital that risks:
third-party contract failure, impermanent loss, market conditions. Yields
may be positive, zero, or negative. Nothing here promises yield; every
strategy is proposed with its risks written in the proposal itself, and what
the treasury will never do — leverage, derivatives, trading, oracles,
stablecoins, distributions to individuals — is written in its policy.

## 12.3 Phase 3 — Infrastructure

A distant possibility, included because a roadmap that stops at the
comfortable horizon is not a roadmap.

If the ecosystem grew to a point where a general-purpose chain became a
genuine constraint — throughput, transaction costs, protocol-level features
unavailable on BNB Chain — the community could evaluate moving to dedicated
infrastructure.

The realistic form is not building a blockchain from scratch. A new chain
starts with no validators and no economic security, which makes it attackable
regardless of how well it is engineered. The viable path is an
application-specific chain or layer-2 that **inherits** security from an
established network rather than attempting to bootstrap its own.

This is explicitly conditional. It happens only if real growth justifies it,
and only by community decision.

**What would carry over.** The tokenomics, the governance model, the staking
design, the principle of ownerlessness — these are logic, and logic is
portable. A different chain would change where the protocol runs, not what it
does.

## 12.4 The roadmap is not fixed

Everything above will be wrong in some respect, and that is expected.

DeFi does not stand still. Primitives that do not exist today will exist in
three years; approaches that look essential now will be superseded; risks not
yet identified will emerge. A roadmap written as a fixed sequence of
deliverables would be obsolete before the first item shipped — and worse, it
would commit the protocol to a plan rather than to a direction.

Daimon is built to change. The upgrade path exists, governance can extend the
system, and the constraints that cannot be altered are deliberately few and
specifically chosen: no minting, a supply floor, a fee ceiling, a mandatory
delay. Everything else is open, because everything else should be able to
improve.

This is not a caveat added for safety. It is the concept the protocol was
named after.

Heraclitus — whose reading of the daimon appears in Section 2 — is also the
philosopher of flux: *everything flows*, nothing remains what it was, and what
endures does so precisely by changing. The river persists because the water
does not. A system designed to remain identical to itself would not be a
faithful implementation of that idea; it would be its opposite.

So the roadmap will move. New frontiers will be added as they appear, and
directions taken here will be abandoned when better ones are found. What will
not change is the small set of constraints that make the protocol what it is
— and the requirement that every change passes through a public vote and
seven days in the open.

The destination is not fixed. The method is.

---

# 13. What Daimon is not

Most whitepapers end with ambition. This one ends with limits, because a
reader deciding whether to participate is better served by knowing what can
go wrong than by another paragraph on what could go right.

**Daimon is not an investment product and does not promise returns.** There
is no yield target, no projection, no expectation of appreciation stated
anywhere in this document. The protocol guarantees rules — a supply that
cannot be inflated, parameters that cannot be changed in private, a floor
that cannot be crossed. It guarantees nothing about price, which is
determined by a market that no code controls.

**Deflation is not a price mechanism.** A shrinking supply does not
mechanically increase value. Demand can fall faster than supply. The floor
guarantees scarcity; it guarantees nothing else.

**There is no team that will protect you.** This is the point of the design,
and it cuts both ways. No one can change the rules against you, and no one
can intervene to help you either. There is no support desk that can reverse a
transaction, recover a lost key, or compensate a loss. Ownerlessness means
exactly what it says.

**Governance can make mistakes.** A majority can approve a bad proposal. The
constraints in the code bound the damage — fees cannot exceed 10%, supply
cannot be minted or burned below the floor, funds cannot be redirected to
arbitrary addresses — but within those bounds, the community can decide
poorly. The seven-day timelock exists so that a mistake is visible before it
takes effect, not so that it becomes impossible.

**The code may contain flaws.** It has been tested extensively, analysed
statically, attacked deliberately by its own authors, and independently
audited, with the report public. None of that makes it perfect. Contracts audited by the
best firms in the industry have been exploited. The honest statement is that
we have reduced the probability of failure as far as we know how, not that we
have eliminated it.

**Participation is voluntary and carries risk.** Tokens can lose value.
Locked tokens cannot be withdrawn early. Smart contracts can fail. Nothing
here should be understood as advice to acquire, hold, or stake anything.

**We are not neutral.** This document was written by the people who built the
protocol. We believe in it, which is a reason to read our claims critically
rather than accept them. Everything asserted here corresponds to code that is
public and deployed, at the addresses of Section 5.4. The appropriate
response to this document is not to trust it. It is to verify it.

---

# 14. Legal disclaimer

This document is provided for informational purposes only. It does not
constitute an offer to sell, a solicitation to buy, or a recommendation
regarding any digital asset, security, or financial instrument.

Nothing in this document constitutes investment, financial, legal, tax, or
accounting advice. Readers should conduct their own research and consult
qualified professionals before making any decision.

Digital assets involve substantial risk, including the total loss of the
amount involved. Past performance, testnet results, and technical
characteristics do not indicate or guarantee future outcomes. Smart contracts
may contain vulnerabilities despite testing and independent review.

Daimon is a decentralized protocol with no owner, no administrator, and no
legal entity operating it. No party guarantees its continued operation,
maintains an obligation to support it, or is able to reverse, modify, or
compensate transactions executed by its contracts.

Statements in this document regarding future development represent intentions
and possibilities, not commitments. Any future phase depends on community
governance decisions, technical feasibility, and available resources.

The regulatory treatment of digital assets varies by jurisdiction and
continues to evolve. Readers are responsible for determining whether their
participation is lawful where they reside.

The information in this document is accurate to the best of the authors'
knowledge at the date of publication. Contract addresses, parameters, and
technical details should be verified directly on-chain, which remains the
authoritative source in all cases.

The full legal disclaimer and terms of use are published in the repository
as `DISCLAIMER_TERMS` (version 0.3, `docs/DISCLAIMER_TERMS_v0.3_EN.md`); the
English text is the authoritative one.

---

**Repository:** `github.com/daimon-dao/daimon-dao`
**Audited reference:** tag `audit-final` (scope submitted at `audit-scope-v2`)
**Audit report:** [Zenith, August 2026](https://github.com/zenith-security/reports/blob/main/reports/Daimon%20DAO%20-%20Zenith%20Audit%20Report.pdf)
**Mainnet:** BNB Smart Chain, chain id 56, since 29 September 2026 — addresses in Section 5.4, launch record in `docs/MAINNET_LAUNCH_RECORD.md`

*v0.3 — mainnet release.*
