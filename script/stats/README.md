# Staking statistics

`staking-stats.mjs` rebuilds the active locks of the mainnet staking contract
from the chain, checks the rebuild against `totalStakedAmount()`,
`totalVotingPower()` and `nextLockId()` at the target block, and prints the
locks, DMN and voting power per lock period. The method, a reading and the
caveats are in [docs/STAKING_STATS.md](../../docs/STAKING_STATS.md).

Read-only, no key, no dependency: Node.js 22 or later and public RPC
endpoints. Aggregates only: the holder of a lock is never decoded.

```sh
node script/stats/staking-stats.mjs --source state            # at head - 20
node script/stats/staking-stats.mjs --source events           # replay Staked/Withdrawn
node script/stats/staking-stats.mjs --help
```

Exit code 1, with the differences printed, if the rebuilt totals do not match
the contract's counters to the wei.
