# G1 fork rehearsal

`g1-fork.mjs` takes G1 ([docs/G1_PROPOSAL.md](../../docs/G1_PROPOSAL.md))
through its whole life on a local fork of BSC mainnet:

1. propose, with the exact bytes published in that file;
2. vote, then check the quorum;
3. queue, then wait the seven days;
4. execute;
5. one fee conversion ("poke"), with the 60/40 split checked to the wei.

It also checks what G1 cannot do. It prints 20 rows and exits 0 only if
every row passes. Nothing is sent to mainnet: every transaction goes to
your local anvil, through account impersonation, with no key anywhere.

## Requirements

- [Foundry](https://getfoundry.sh): `anvil`, plus `forge build` at the
  repository root, for the ABIs in `out/`. The build uses `via_ir` and
  takes a while.
- Node.js 22 or later (tested with 22.12 and 24.20).
- `npm ci` in `daimon-dapp/`. The script uses the dApp's pinned `viem`
  and adds no dependency of its own.
- An upstream RPC that serves recent BSC state. On 2026-10-01,
  `bsc-mainnet.public.blastapi.io` and `bsc.drpc.org` did.
  `bsc-dataseed` and publicnode did not (the fork fails with
  `missing trie node` or HTTP 403).

## Run

```sh
forge build
(cd daimon-dapp && npm ci)
anvil --fork-url https://bsc-mainnet.public.blastapi.io --chain-id 56 --auto-impersonate --gas-price 0 --block-base-fee-per-gas 0
# in another shell, from any directory:
node script/g1/g1-fork.mjs
```

A run takes a few minutes, because anvil fetches state from the
upstream on demand. Every run needs a **fresh fork**: stop anvil and
start it again. The script refuses a fork that a previous run has
already used.

| variable | default | |
|---|---|---|
| `G1_FORK_RPC` | `http://127.0.0.1:8545` | the anvil endpoint |
| `G1_OUT_DIR` | `script/g1/out/` (gitignored) | where results are written |
| `G1_PROPOSER` | the rule below | an address to propose from instead |

## What it does, and its rules

- **The bytes under test** are read from `docs/G1_PROPOSAL.md`: the one
  line that starts with `G1 - ` (the description) and the one that
  starts with `0x82ff16c1` (the calldata). The script first re-encodes
  `propose(token, 0, setStakingRewardShareBps(600), description)` and
  stops if the published calldata differs. A run therefore checks that
  page too.
- **The proposer** is a real staker, impersonated: the owner of the
  oldest staking lock whose owner holds at least `proposalThreshold` of
  voting power. It is read from `locks(id)` at run time; no holder
  address is stored in this repository. Its address is printed
  shortened.
- **The FOR votes** come from team-sized positions: 140 B DMN, the size
  `docs/CALENDARIO_GOVERNANCE_Q1.md` (Scenario W) uses for the team's
  personal holdings, staked for 365 days (4.0x). They sit in four
  fork-only wallets, `0x7ea7...0001` to `0x7ea7...0004`, funded on the
  fork from the Migration's unclaimed DMN. The Migration is a
  fee-exempt sender, so the fee inventory does not move. The stakes are
  made before the proposal, because votes are weighed at the block
  before the propose block.
- **Two variants** run on anvil snapshots and are reverted afterwards:
  - R.5: every other real staking owner votes AGAINST.
  - R.6: only the proposer votes.
- **The poke** is 1 wei of DMN sent from a fork-only wallet straight to
  the pair. It runs once at share 1000 (what a poke does today) and
  once at 600 (after execution), on the same pool state. If the token's
  fee inventory is below `minimumTokensBeforeSwap`, the gap is donated
  from the Migration on the fork, and the R.13 rows say so.
- **Gas price is zero.** That's why the base fee must be 0: contract
  balance deltas are then exactly the protocol's own movements.
- **Guards.** The script refuses to run unless the endpoint is an anvil
  fork of chain 56 (`anvil_nodeInfo`) with a zero base fee, and it
  refuses a fork already used by a previous run.

## Output (`out/`)

| file | contents |
|---|---|
| `results.md` | the 20 rows: step, action, expected, observed, tx, verdict |
| `facts.json` | the key numbers: fork block, gas, the split in wei |
| `params-*.json` | the 185 values read at each stage: base, before execute, after execute, after the poke |
| `execute-statediff.json` | the execute transaction's state diff (`prestateTracer`, diff mode) |

The rows, summarized in `docs/G1_PROPOSAL.md`:

| rows | what they check |
|---|---|
| F.0 | the local fork |
| G.1-G.3 | the live Governor, the real stakers, and the token before G1 |
| R.1-R.4 | team-sized stakes, propose, Pending, the vote with the quorum |
| R.5-R.6 | the variants |
| R.7 | queue, at the voteEnd edge |
| R.8 | what the queued operation cannot do |
| R.9-R.12 | execute; nothing else changed (185 values, three storage slots); no second execute |
| R.13-cf, R.13, R.14 | the poke at 1000 and at 600, and their A/B comparison |
| R.15 | what the poke moved |

## When it stops applying

- **After G1 executes on mainnet.** Row G.3 expects share 1000 and
  fails, by design.
- **After the migration sweep.** The Migration no longer holds the DMN
  that funds the fork-only positions, and the script refuses.
- **If G1 already exists on mainnet**, the fork proposes a second,
  identical one (its id is `proposalCount`). That is still a valid
  rehearsal of the cycle.

BNB amounts follow the pool at the fork block; the 60/40 proportions
do not.
