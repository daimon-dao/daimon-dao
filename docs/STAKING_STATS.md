# DMN staking: active locks by period

How much DMN is staked, for how long, and how the voting power splits between
the lock periods. Every number here is read from BNB Smart Chain at a stated
block and checked against the staking contract's own counters; nothing is
self-reported. Aggregates only: no holder, no single position.

## The contract

| | |
|---|---|
| Staking (`DaimonStaking`) | [`0xBb596e7308D6C5AED55cEC597D372840Cbe575b1`](https://bscscan.com/address/0xBb596e7308D6C5AED55cEC597D372840Cbe575b1) |
| Deploy block | 124,626,901 |
| Lock options at deployment | 30 days × 1.0, 90 days × 1.5, 180 days × 2.2, 365 days × 4.0 |

A stake locks an amount of DMN for one of the lock options and grants
**voting power = amount × multiplier**, credited to the holder for the life of
the lock. The multiplier of each lock is fixed when it is created; governance
can add or disable options later, which is why the script reads the period of
every lock from the chain instead of from this table.

DMN and voting power have 18 decimals. The on-chain totals below are in wei
(10^-18 DMN); the voting power uses the same unit.

## Values read on 2026-10-20

Block **128,734,429**, timestamp 1792494015 = **2026-10-20 11:00:15 UTC**,
read through `bsc-rpc.publicnode.com` with the command in
[Reproduce it yourself](#reproduce-it-yourself) (`--source state`).

| Lock period | Locks | DMN staked | % of staked DMN | Voting power | % of voting power |
|---|---:|---:|---:|---:|---:|
| 30 days | 29 | 81,839,660,745.62 | 23.26 % | 81,839,660,745.62 | 7.10 % |
| 180 days | 6 | 5,176,560,139.00 | 1.47 % | 11,388,432,305.80 | 0.98 % |
| 365 days | 184 | 264,694,561,875.13 | 75.25 % | 1,058,778,247,500.53 | 91.90 % |
| **Total** | **219** | **351,710,782,759.75** | **100.00 %** | **1,152,006,340,551.95** | **100.00 %** |

The contract's counters at the same block, which the table above reproduces
to the wei:

| | wei |
|---|---|
| `totalStakedAmount()` | 351710782759752578000000000001 |
| `totalVotingPower()` | 1152006340551950312000000000001 |
| `nextLockId()` (locks ever created) | 219 |

So, at that block:

- **219 locks** had been created since deployment and **none had been
  withdrawn**: all 219 are active.
- **365-day locks hold 75.25 % of the staked DMN and 91.90 % of the voting
  power.** The 4.0 multiplier is what moves the second figure away from the
  first.
- No 90-day lock existed, so the 90-day line is absent. Every period present
  has at least 3 locks, so no "small buckets" line appears (see the method).
- The staked total is 35.17 % of the 1,000,000,000,000 DMN total supply.

Every figure here is a snapshot. The counts, the amounts and the shares change
with every new lock and every withdrawal; a reading taken at another block
will differ. Only the block and the method are stable.

## Method

**What is counted.** Each stake creates one lock in the contract, with the
amount, the period chosen by the holder and the voting power granted
(amount × multiplier of the chosen option, computed by the contract at stake
time). Locks are numbered from 0; `nextLockId()` is the number of locks ever
created.

**When a lock is active.** A lock is active at a block if it has been created
and not withdrawn at that block. Withdrawal is the only way out: it returns
the amount one-for-one and removes exactly the voting power that was granted.
A lock whose period has ended but which has not been withdrawn is still
active: its DMN are still in the contract and its voting power still counts.
This document does not say when any lock ends.

**Two ways to rebuild the active locks, same result.**

- *Events*: read every `Staked` and `Withdrawn` event of the contract from the
  deploy block to the target block, in chain order; a lock is active if it was
  staked and not withdrawn. `Staked` carries the amount, the period and the
  voting power granted.
- *State*: read `locks(i)` for every `i` below `nextLockId()` at the target
  block; a lock is active if its `withdrawn` flag is false. The period is
  `unlockTime − start`, both stored at stake time.

**Why it must match the contract's totals.** `stake()` adds the amount to
`totalStakedAmount` and the granted voting power to `totalVotingPower`;
`withdraw()` subtracts the stored amount and the stored voting power of that
lock, never a recomputation; no other function touches either counter. So the
sum over the active locks equals each counter exactly, at any block. The script
reads both counters and `nextLockId()` at the target block and **exits with an
error if any of the three differs from the rebuild by a single wei**. The
table is printed only after this check passes.

**Grouping.** Active locks are grouped by period (the duration in seconds,
shown in days). Per period: number of locks, DMN, share of the staked DMN,
voting power, share of the voting power. A period with fewer than 3 active
locks is not shown on its own: its locks, amount and voting power are merged
into one "small buckets" line, so that no line describes one or two positions.
Amounts are shown with two decimals and shares with two decimals, both
truncated; the exact wei are the contract's counters above.

**What is never read.** The holder of each lock (the indexed `user` of the
events, the `owner` field of the struct) is not decoded, stored or printed.
The script works with lock ids and amounts only.

## Reproduce it yourself

The script is [`script/stats/staking-stats.mjs`](../script/stats/staking-stats.mjs):
Node.js 22 or later, no dependency, no key, read-only, public endpoints. From
the repository root:

```bash
node script/stats/staking-stats.mjs --source state
```

reads the lock structs at the current head minus 20 blocks through
`bsc-rpc.publicnode.com` and prints the table above for that block. To read a
given block, the one of this document for example:

```bash
node script/stats/staking-stats.mjs --source state --block 128734429 --state-rpc <URL>
```

- `--block N` sets the target block. The endpoint must serve contract state
  at that block: `bsc-rpc.publicnode.com` (the default) answers only for the
  last few minutes, so a past block needs an endpoint with historical state,
  passed with `--state-rpc`. The free public BSC endpoints tried on
  2026-10-20 either served the last few minutes only or refused; a personal
  endpoint of any archive provider works.
- `--source events` (the default when `--source` is omitted) replays the
  `Staked` and `Withdrawn` events from the deploy block, in 5000-block pages,
  through `bsc.rpc.blxrbdn.com` (bloXroute) or the `--history-rpc` given. On
  2026-10-20 bloXroute answered HTTP 403 to every `eth_getLogs` request, so
  the reading above used `--source state`; both sources are checked against
  the same counters and give the same table whenever both are reachable.
- `node script/stats/staking-stats.mjs --help` lists the options.

Whatever the source, the script prints the block, its UTC time, the table and
the three counters, and fails loudly on a mismatch.
