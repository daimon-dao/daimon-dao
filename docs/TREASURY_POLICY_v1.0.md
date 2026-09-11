# Daimon Treasury Policy
*Draft v1.0 — September 2026. To be published before the first
mainnet governance proposal. Where this text and the deployed code
disagree, the code is the only authority.*

---

## 1. A contract, not a wallet

The treasury of Daimon is the **DaimonTimelock** contract. It has no
owner and no keys. Nothing leaves it except through a public
governance proposal: five days of voting, then seven days in the
open, then execution — a cycle anyone can watch from the first
minute to the last. The guardian, during its 36-month mandate, can
cancel a queued action; it can never redirect one, and after the
mandate only a vote can cancel at all.

Everything that follows is a consequence of this first fact. A
treasury with no hands attached can hold what a group of people
could not, and can wait as long as a group of people never would.

## 2. Where the money comes from

**At launch, nothing from fees.** The protocol launches with its fee
share routed entirely to stakers — `stakingRewardShareBps = 1000` —
and the protocol's own wallet at zero. Not "small": the arithmetic
makes the amount exactly zero, and no transaction to that address
can fire.

**From the first vote, 40%.** The first governance proposal on
mainnet will do two things: set the treasury contract as the
destination of the protocol's fee share, and set the split to **60%
stakers / 40% treasury** — the 60/40 the code was written with, now
pointed at a contract instead of a wallet. From that vote on, the
40% accumulates in the treasury, in BNB, untouched by anyone, until
a further vote spends it.

**This replaces the two-wallet model of the v0.1 whitepaper** — a
governed treasury plus an operational multisig receiving the fee
stream. That model would have placed part of the protocol's income
in a wallet managed by people, which, for a group with no legal
entity, is income of the people. A contract governed by public vote
is not, until it distributes. So there is one treasury and no
operational wallet. The flexibility the operational wallet was meant
to provide — small, frequent expenses without a vote for each — will
come from the legal entity, once it exists, through periodic budgets
approved by proposal and accounted for in public.

**Three inflows the code provides by itself.**

- *The legacy tokens.* Every migrating holder's DMX are transferred
  to the treasury, where they stay in non-circulating custody until
  `sweepUnclaimed()` has executed — the effective deadline, pause
  credit included — as the audit requires.
- *The unclaimed DMN.* After the deadline, governance sweeps whatever
  DMN remain in the migration contract into the treasury. This
  includes, by choice, the DMN corresponding to the project's own
  legacy holdings — the two deployer-linked wallets from 2022, about
  42% of the old supply — which will never be claimed by anyone: they
  reach the treasury without a transfer, without a fee, and without
  passing through any person's hands. The project's tokens become
  the protocol's, and they do not vote: governance is decided by
  those who bought their tokens, the team included.
- *The pool itself.* The LP tokens of the initial DMN/WBNB liquidity
  are transferred to the treasury at launch, in a published
  transaction. The pool can no longer be withdrawn except by vote,
  and the treasury's share of it grows with every swap's fee.

**And, in future, the fees of any service module the DAO adds.**

## 3. The burn continues where it stopped

DMX tokens sent to the dead address over the years cannot migrate:
no key exists to claim for them. The DMN that correspond to them
therefore remain in the migration contract, are swept to the
treasury with the rest, and are then sent by governance vote to the
dead address — the same amount the DMX dead address holds at a
stated block. Once there, anyone may call `burnDeadBalanceToFloor()`
— except during an emergency pause, which suspends it for at most
14 days — and remove them from the supply for good.

DMN's supply thus resumes exactly where DMX's burn left off — and
this time the supply actually decreases, which the predecessor's
accounting never did.

The rest of the swept DMN — those of holders who simply did not
migrate — are a different thing: the treasury holds them, and
governance may decide their use, including a later migration round.
Nothing is burned without a vote, and nothing below the 21 billion
floor can be burned at all.

## 4. What the treasury holds

Target allocation, reached by proposals over time:

```
20%  BNB      the chain's own asset: operations, gas, deposits
40%  BTCB     Bitcoin, in the only form that exists on BNB Chain
40%  XAUt     gold, tokenized — the premise the protocol started from
```

The treasury holds the two premises of the project: gold and
Bitcoin.

**Never stablecoins.** Not as a reserve, not as a parking place, not
as an exception. What can be printed is not money by this treasury's
definition.

**Said plainly: BTCB and XAUt are custodial wrappers.** Native
Bitcoin does not exist on BNB Chain, and gold exists on no chain
except as a claim on bars in someone's vault. Holding them means
accepting an issuer's risk. This treasury accepts it, states it, and
pursues the only mitigation there is: the deepest, most audited
issuers available on this chain, and diversification across issuers
as more become available. The choice of XAUt is a choice of chain,
not of faith.

## 5. What the treasury may do

Only by proposal, only in tranches, only with protocols that are
established, audited, and non-custodial in their operation:

- **convert** the BNB it receives into BTCB and XAUt, on the deepest
  pools available, in tranches, with slippage limits stated in the
  proposal;
- **deposit** BNB and BTCB into lending markets (Venus);
- **delegate** BNB to validators through the chain's native staking;
- **provide liquidity** in blue-chip pools of assets it already
  holds;
- **hold**. Gold, today, is a reserve, not a yield source.

Every operation has a stated size. Every allowance granted to an
external contract is for the exact amount and is closed within the
same operation. Whatever these operations earn returns to the cycle
the protocol already runs — a share to the burn, a share to stakers,
a share back to the treasury — in proportions set by vote.

**Capital that earns is capital that risks**: third-party contract
failure, impermanent loss, market conditions. Returns may be
positive, zero, or negative. Nothing here promises yield; every
strategy is proposed with its risks written in the proposal itself.

A dedicated treasury module — an allowlist of approved assets and
protocols, per-operation limits, its own audit — will replace ad-hoc
proposals once the treasury can pay for it and the core protocol has
run on mainnet long enough to be considered stable. Until then,
operations are few, small, and one at a time.

Approved actions do not expire: a queued action stays executable
until executed or canceled. The protocol's monitor reports actions
that remain ready and unexecuted; the guardian can cancel them
during its mandate, and after that only a vote can.

## 6. What the treasury will never do

No leverage. No derivatives. No trading. No yield farms paid in
printed tokens. No oracles. No stablecoins. No distribution of funds
to individuals. Payments leave the treasury only to pay for work
done for the protocol — audits, development, the legal entity that
will one day be able to receive them — always in BNB or BTCB, and
always after a public vote.

## 6b. The protocol's own tokens

After the migration sweep, the treasury will hold the DMN that
correspond to the project's legacy holdings — about 42% of the old
supply, tokens no person owns and no proposal can hand to a person.
They do not vote. What they are for, in order of priority, each use
a public vote:

1. **Liquidity at home.** Deepening the DMN/WBNB pool, with the LP
   tokens held by the treasury. Sized on the depth the market needs,
   not on a percentage.
2. **Liquidity elsewhere.** Should Daimon exist on other chains, the
   pools there need real liquidity, and only the protocol can provide
   it. A bridged representation of DMN would carry no transfer fee
   and no reflection — a plain token, integrable where the native
   one is not — at the cost of the bridge's own custody risk, chosen
   and declared like any other issuer.
3. **Work.** Grants and bounties for verifiable work done for the
   protocol — code, audits of modules, integrations, translations —
   with public rules and milestones, one payment per vote. The
   protocol hires; it does not gift.
4. **Reserve.** A later migration round for holders who did not
   arrive in time, and contingencies of the protocol itself.

What they are not for: **no burn by decision** — the supply falls
through use, not through gestures; the only burn planned is the
continuity burn of §3, which belongs to DMX's history, not to these
tokens. **No lotteries or prize draws** — they need a source of
randomness, which is an oracle, and they are gambling. **No
distribution** to holders, stakers, or anyone who has not done work
for the protocol.

No amount is left "to be decided later": every use above is named
here, and every use requires a vote. The Timelock is the vesting
schedule — nothing leaves without seven public days, and anyone
can object.

## 7. The order of the first votes

Because the treasury is not fee-exempt at launch, and because a DMN
transfer between non-exempt addresses pays the protocol's fee, the
first proposals have a natural order:

```
1  destination = treasury, then split 60/40    the income begins
   (two proposals, executed in that order)
2  fee exemption of the treasury               so DMN can leave it
                                                without loss
3  a first deposit, small, in one place        the capital begins
                                                to work
4  after the migration sweep: the burn of      the supply resumes
   continuity                                   where DMX stopped
5  the legal entity's first budget              the protocol pays
                                                for its own future
```

Each proposal is written as a scenario before it exists — target,
calldata, expected outcome, what the monitor should see — and
published with its risks. Nothing here binds a vote; it describes
the path the code makes possible.

## 8. How to verify

The treasury address, its balances, and every proposal are public.
The protocol's monitor reports the treasury's state on a fixed
cadence. Do not trust this document: read the contract.

---

*This policy can be amended only by the same process that moves the
funds: a public proposal, a vote, and seven days in the open.*
