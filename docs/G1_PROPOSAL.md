# G1 -- the 60/40 split (the first mainnet proposal)

*Prepared 2026-10-01. **Not proposed** as of this commit: the Governor's
`proposalCount` was 0 at block 125008614. When G1 is created, its id,
transaction and block are added here. Where this text and the deployed
code disagree, the code is the only authority.*

G1 is the first proposal of `docs/CALENDARIO_GOVERNANCE_Q1.md`. It is
also the first vote in the order set by the Treasury Policy (section 7),
v1.2, in force from G1's execution:
[`docs/TREASURY_POLICY_v1.0.md` at the tag `treasury-policy-v1.2`](https://github.com/daimon-dao/daimon-dao/blob/treasury-policy-v1.2/docs/TREASURY_POLICY_v1.0.md)
(section 2). The same proposal ran end to end on BSC testnet first:
Chapel campaign 2b, proposal 0, in `docs/CHAPEL_2B_RESULTS.md` (propose
14/09, vote 15/09, queue 21/09, execute and first poke 28/09).

## What G1 changes

One call: the Timelock calls `setStakingRewardShareBps(600)` on the DMN
token. The value goes from 1000 to 600. It is in tenths of a percent,
despite its name (`DaimonV2.sol:914-918`, bounded to <= 1000).

The fee is unchanged: 4 % per taxed transfer -- 1 % reflection, 1 %
buyback, 2 % marketing branch (`taxFee` 10, `buybackFee` 10,
`marketingFee` 20, `liquidityFee` 30, per mille). The 3 % accumulates
in the token as DMN. Once it reaches `minimumTokensBeforeSwap`
(0.2 B DMN), any direct transfer to the pair converts one 0.2 B chunk
to BNB (`SwapAndLiquify`). The BNB of each conversion splits
(`DaimonV2.sol:705-723`):

```
marketingEth = floor(ethReceived x marketingFee / liquidityFee)      20/30 of it
toStaking    = floor(marketingEth x stakingRewardShareBps / 1000)    -> staking.notifyRewardAmount
toTimelock   = marketingEth - toStaking                              -> marketingWallet = the Timelock
the token keeps ethReceived - marketingEth                           10/30, the buyback reserve
```

| share of each conversion's BNB | today (1000) | after G1 (600) |
|---|---|---|
| stakers | 66.67 % | 40.00 % |
| **treasury (the Timelock)** | **0** | **26.67 %** |
| buyback reserve (stays in the token) | 33.33 % | 33.33 % |

The destination is not voted. `marketingWallet` has been the Timelock
`0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891` since deploy. G1 sets only
the split. Nothing leaves the treasury without a further proposal: a
vote, then seven days.

## The proposal, exactly

| field | value |
|---|---|
| Governor | `0x1397a7d25595B718BE6FEEDd42ed5E60F66E16De`, `propose(address,uint256,bytes,string)`, selector `0x82ff16c1` |
| target | `0x160864F9945C52063A7c9f5dcd57C0C89eacbE6a` (DMN, the proxy) |
| value | `0` |
| data | `0x6cf839b90000000000000000000000000000000000000000000000000000000000000258` = `setStakingRewardShareBps(600)` |
| expected id | 0, if no other proposal is created first; if one is, only the id changes |

The description, one line, 455 ASCII bytes, no trailing newline,
keccak256 `0x959bae3ee5b4ab07bb5ac9a3a14a2b29985311571294b54e4c30dc9fcdd70058`:

```
G1 - The treasury begins to accumulate. Sets stakingRewardShareBps from 1000 to 600 on the DMN token: of the BNB from each fee conversion's marketing branch, 60% goes to stakers and 40% to the treasury (the Timelock). No person can move treasury funds: every use requires a DAO vote and a 7-day timelock. Rehearsed on Chapel testnet (campaign 2b, proposal 0). Policy: github.com/daimon-dao/daimon-dao/blob/treasury-policy-v1.2/docs/TREASURY_POLICY_v1.0.md
```

The policy link points at a tag, not a branch, so it does not follow
later edits. On 2026-10-01 it
answered HTTP 200. The file served there is byte-identical to the
tagged commit `167c874`.

The full `propose()` calldata, 740 bytes, keccak256
`0xf171c8aee6fdbab2bea8b58281f65f9ea79227c97ae28492a3a8e198f0e58e6a`:

```
0x82ff16c1000000000000000000000000160864f9945c52063a7c9f5dcd57c0c89eacbe6a0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000000e000000000000000000000000000000000000000000000000000000000000000246cf839b900000000000000000000000000000000000000000000000000000000000002580000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001c74731202d2054686520747265617375727920626567696e7320746f20616363756d756c6174652e2053657473207374616b696e6752657761726453686172654270732066726f6d203130303020746f20363030206f6e2074686520444d4e20746f6b656e3a206f662074686520424e422066726f6d20656163682066656520636f6e76657273696f6e2773206d61726b6574696e67206272616e63682c2036302520676f657320746f207374616b65727320616e642034302520746f2074686520747265617375727920287468652054696d656c6f636b292e204e6f20706572736f6e2063616e206d6f76652074726561737572792066756e64733a2065766572792075736520726571756972657320612044414f20766f746520616e64206120372d6461792074696d656c6f636b2e20526568656172736564206f6e2043686170656c20746573746e6574202863616d706169676e2032622c2070726f706f73616c2030292e20506f6c6963793a206769746875622e636f6d2f6461696d6f6e2d64616f2f6461696d6f6e2d64616f2f626c6f622f74726561737572792d706f6c6963792d76312e322f646f63732f54524541535552595f504f4c4943595f76312e302e6d6400000000000000000000000000000000000000000000000000
```

Decoding it gives back the four fields above, the description byte for
byte. The dApp's create-proposal form encodes the same 740 bytes from
the four fields, in English and in Italian. This was checked with the
dApp's own ABI, its own value parser and its viem. The form sends the
description **untrimmed**: a trailing newline, a trailing space or a
line break inside the pasted text produces different bytes.

## Timeline rule

Let T be the timestamp of the block that includes the propose
transaction.

| step | when | who |
|---|---|---|
| snapshot of voting power | the block before the propose block | -- |
| voting opens | T + 86,400 s (1 day) | stakers with power at the snapshot |
| voting closes | T + 6 days, inclusive (`castVote` accepted while `block.timestamp <= voteEnd`) | -- |
| `queue(id)` | from voteEnd + 1 s, if For + Abstain >= 10 % of the snapshot's total voting power and For > Against | anyone |
| `execute(id)` | from the queue block's timestamp + 604,800 s (7 days) | anyone |
| cancel | any time before execution: through the Governor in any state, or directly at the Timelock once queued | the guardian Safe `0x37F4...c7a8`, mandate until 2029-09-28 01:08:32 UTC |

The earliest execution is about T + 13 days. Example: proposed at
2026-10-01 12:00:00 UTC, voting runs from 2026-10-02 12:00:00 to
2026-10-07 12:00:00 UTC. Queued at 12:00:01 that day, it executes from
**2026-10-14 12:00:01 UTC**.

Voting power is read at the snapshot. A stake mined in the propose
block or later adds nothing for G1. A wallet with no voting power at
the snapshot cannot vote on it: `castVote` reverts
`InsufficientVotingPower`. At block 125008614 the total voting power was
278.25 B over 20 staking owners, so a proposal created then needs
27.83 B For + Abstain.

## Creating it (for the proposer)

1. Every wallet that intends to vote must have its stake mined before
   the propose transaction. The proposer needs at least 1000 DMN of
   live voting power. The token must not be paused.
2. Use one of three paths, all producing the bytes above:
   - **The dApp** (app.daimon.money, Governance, new proposal): target,
     value `0`, data, and the description pasted as one line.
   - **BscScan**: the Governor, Write Contract, `propose`, with the same
     four fields.
   - **MetaMask with hex data**: 0 BNB to the Governor, with the full
     calldata. No form can reformat the text on this path.

   Before signing, check: to = the Governor, data starts with
   `0x82ff16c1`, 740 bytes.
3. Afterwards, compare the transaction input with the calldata keccak
   above (see "How to verify"), then record the id, transaction and
   block in this file.

Gas measured on the fork: propose 696,183, queue 114,598, execute
114,198. A vote cost 87,520 on Chapel. At 0.05 gwei, proposing costs
about 0.000035 BNB and each other step under 0.000006 BNB.

The project's monitor treats any change of `stakingRewardShareBps` as
URGENT (`docs/SPEC_MONITOR.md`). It alerts when the proposal is created
(the decoded `ProposalCreated`) and again on execution
(`ParamsUpdated("stakingRewardShareBps", 600)`). For G1 both alerts are
expected and confirmed by hand. On execution day, its rule for BNB
reaching the Timelock from the token is switched by hand from URGENT to
NOTIFY with the amount. Any outflow from the Timelock not matched to an
executed operation stays URGENT.

## Rehearsal on a mainnet fork: 20/20 PASS

**Setup.**
- A local anvil fork of BSC mainnet at block 125008614
  (2026-10-01 00:58:58 UTC). Every write stayed on the local node,
  through account impersonation, with no key anywhere. Nothing was sent
  to mainnet.
- **The proposer:** a real mainnet staker with 17.2 M DMN of voting
  power, chosen by a fixed rule: the owner of the oldest staking lock
  whose owner holds at least the threshold. Its address is not recorded
  here. It sent the exact 740 bytes above.
- **The FOR votes:** team-sized positions -- 140 B DMN, the size
  `CALENDARIO_GOVERNANCE_Q1.md` (Scenario W) uses for the team's
  personal holdings. Staked for 365 days (4.0x) in four fork-only
  wallets, 560 B of voting power, before the proposal.
- That DMN was taken on the fork from the Migration's unclaimed
  balance. The Migration is a fee-exempt sender, so the token's fee
  inventory did not move. This funding exists only on the fork.
- **Reproduce it:** run `node script/g1/g1-fork.mjs` against a fresh
  fork (see [script/g1/README.md](../script/g1/README.md)). The committed
  script reads the bytes from this file. It gave the same 20/20, with
  identical amounts, at fork blocks 125013681 (Node 24) and 125014404
  (Node 22).

| row | check | result |
|---|---|---|
| F.0 | local fork of chain 56 at the latest block | PASS |
| G.1 | live Governor: `propose` selector in the bytecode, threshold 1000 DMN, quorum 1000 bps, delay 86,400 s, period 432,000 s, `proposalCount` 0 | PASS |
| G.2 | real stakers from `locks(id)` storage: 42 locks, 20 owners, their sum == `totalVotingPower` (278.25 B) | PASS |
| G.3 | before G1: share 1000, `marketingWallet` == the Timelock, fees 10/10/20; the Timelock holds `GOVERNANCE_ROLE`; the Governor is the Timelock's PROPOSER and EXECUTOR; the deployer holds neither `GOVERNANCE_ROLE` nor the Timelock's admin role | PASS |
| R.1 | team-sized positions staked before the proposal: +560 B voting power, fee inventory unchanged | PASS |
| R.2 | propose with the exact 740 bytes: input == the calldata; stored target, value, data and description verbatim; snapshot = block - 1; voteStart = T + 86,400 s; voteEnd = voteStart + 432,000 s; one log, `ProposalCreated`, description verbatim | PASS |
| R.3 | before voteStart: Pending; `castVote` -> `VotingClosed` | PASS |
| R.4 | at voteStart, five FOR votes, each weight == `votingPowerAt(voter, snapshot)`: For 560.02 B against a quorum of 83.83 B (10 % of 838.25 B) | PASS |
| R.5 | variant: the other 19 real staking owners all vote AGAINST (278.23 B): still Succeeded | PASS |
| R.6 | variant: only the proposer votes: Defeated, `queue` -> `ProposalNotSucceeded` | PASS |
| R.7 | at voteEnd still Active (queue refused); at voteEnd + 1 s Succeeded. `queue(0)` by a third party: `CallScheduled` and `ProposalQueued` only; operation id on chain == local keccak; `readyTimestamp` == queue time + 604,800 s exactly | PASS |
| R.8 | what the queued operation cannot do (below) | PASS |
| R.9 | `execute(0)` one second early -> `TooEarly`. At `readyTimestamp`, by a third party: Executed, share 600, exactly three logs: `ParamsUpdated("stakingRewardShareBps", 600)`, `CallExecuted`, `ProposalExecuted` | PASS |
| R.10 | 185 values read just before and just after execute: one difference | PASS |
| R.11 | storage written by the execute transaction: three slots | PASS |
| R.12 | a second `execute(0)` -> `AlreadyExecuted` | PASS |
| R.13-cf | poke at share 1000 (counterfactual: what a poke does today, without G1): split exact to the wei | PASS |
| R.13 | the same poke at share 600, after execution: split exact to the wei | PASS |
| R.14 | the two pokes on the same pool state: identical BNB received, different split | PASS |
| R.15 | after the poke, only the treasury's BNB (+ the 40 % leg) and staking's reward accumulator moved | PASS |

### The 60/40 split, wei-exact

No arming was needed: the token's fee inventory on mainnet was already
0.268 B DMN, above the 0.2 B threshold. One wei of DMN sent straight to
the pair triggered one conversion of exactly 0.2 B DMN. The same poke
ran on the same pool state at both shares. The amounts depend on the
pool at the fork block; the proportions do not.

| leg (wei) | share 1000 (today) | share 600 (after G1) |
|---|---|---|
| BNB received (0.0861 BNB) | 86,124,024,652,199,605 | 86,124,024,652,199,605 |
| marketing branch, 20/30 | 57,416,016,434,799,736 | 57,416,016,434,799,736 |
| staking (`RewardNotified`) | 57,416,016,434,799,736 | **34,449,609,860,879,841** (60 %) |
| **the Timelock** | **0** | **22,966,406,573,919,895** (40 %) |
| the token (buyback reserve) | 28,708,008,217,399,869 | 28,708,008,217,399,869 |

Each balance delta, read between the block before the poke and the
poke block, equals its formula. The three deltas sum to the BNB
received. The Timelock's `receive()` accepted the payment: the
conversion completed and emitted `SwapAndLiquify`, which comes after
the payment's `require`. No buyback fired (the token holds less than
1 BNB). On Chapel the same first leg was 8,842,953,496,697,856 wei
(`docs/CHAPEL_2B_RESULTS.md`, H3.4).

### What G1 cannot do

- **Only this call.** The Governor stores target, value and data at
  creation, and `execute(id)` passes exactly those to the Timelock. The
  Timelock runs only an operation whose id, `keccak256(target, value,
  data, 0, salt)`, was scheduled by `queue`. Four alternatives were
  tried with G1's own salt on the fork: share 700; the same call with
  1 BNB attached; `setMarketingWallet(Safe)`; `setFees(10, 0, 30)`.
  Each was a different operation id, never scheduled, and the Timelock
  refused each one with `OperationNotReady`, even from the Governor.
- **Nothing else changes.** 185 values were read before and after
  execute: every zero-argument view of the token, Governor, Timelock
  and staking; roles across eight accounts; fee exemptions; staking
  governance and lock options; the token's implementation slot; and
  the treasury's BNB, DMN, LP and DMX. The only difference:
  `stakingRewardShareBps` 1000 -> 600.
- **Three storage slots, at the storage level.** The execute
  transaction's state diff (`debug_traceTransaction`, `prestateTracer`,
  diff mode) wrote exactly three slots: token slot 19 (1000 -> 600),
  the Timelock's executed flag for this operation, and the Governor's
  executed flag for this proposal. No balance moved, no code changed.
- **No funds move.** Value is 0. The treasury's balances are the same
  before and after execution. The first BNB reaches the Timelock only
  at the next conversion, and from then on at every conversion.
- **Not early, not twice, not by the guardian.** One second before
  `readyTimestamp` the call reverts `TooEarly`. A second execute
  reverts `AlreadyExecuted`. The guardian Safe cannot execute
  (`AccessControlUnauthorizedAccount`); it can only cancel.

## How to verify, before voting

Everything below is read-only against mainnet, or runs on your own
local fork. It needs [Foundry](https://getfoundry.sh) (`cast`,
`anvil`).

```bash
RPC=https://bsc-dataseed.bnbchain.org
GOV=0x1397a7d25595B718BE6FEEDd42ed5E60F66E16De
TOKEN=0x160864F9945C52063A7c9f5dcd57C0C89eacbE6a
TL=0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891
DATA=0x6cf839b90000000000000000000000000000000000000000000000000000000000000258
```

**1. The calldata says what this page says** (no chain needed):

```bash
cast calldata-decode "propose(address,uint256,bytes,string)" <the 740-byte calldata above>
cast calldata-decode "setStakingRewardShareBps(uint256)" $DATA   # 600
cast sig "setStakingRewardShareBps(uint256)"                      # 0x6cf839b9
```

**2. The proposal on chain is this one.** Once it exists, use the
propose transaction's hash and the id from its `ProposalCreated` event:

```bash
cast keccak $(cast tx <PROPOSE_TX_HASH> input --rpc-url $RPC)
#   == 0xf171c8aee6fdbab2bea8b58281f65f9ea79227c97ae28492a3a8e198f0e58e6a
cast call $GOV "proposals(uint256)(address,address,uint256,bytes,string,uint256,uint256,uint256,uint256,uint256,uint256,uint256,bool,bool,bool,bytes32,uint256)" <ID> --rpc-url $RPC
cast call $GOV "state(uint256)(uint8)" <ID> --rpc-url $RPC
#   0 Pending, 1 Active, 2 Defeated, 3 Succeeded, 4 Queued, 5 Executed, 6 Canceled
```

An equal keccak means the same target, value, data and description,
byte for byte. In `proposals(id)`, fields 2-5 are target, value, data
and description; fields 8-9 are voteStart and voteEnd. On BscScan, the
same check is the transaction's Input Data ("Decode Input Data") and
the Governor's Read Contract tab.

**3. The money goes where the description says, and only governance
can make this call:**

```bash
cast call $TOKEN "marketingWallet()(address)" --rpc-url $RPC        # == $TL
cast call $TOKEN "stakingRewardShareBps()(uint256)" --rpc-url $RPC  # 1000 until G1 executes
cast call $TOKEN "marketingFee()(uint256)" --rpc-url $RPC           # 20
cast call $TOKEN "liquidityFee()(uint256)" --rpc-url $RPC           # 30
cast call $TL "getMinDelay()(uint256)" --rpc-url $RPC               # 604800
cast call $TL "hasRole(bytes32,address)(bool)" $(cast keccak PROPOSER_ROLE) $GOV --rpc-url $RPC   # true
cast call $TL "hasRole(bytes32,address)(bool)" $(cast keccak EXECUTOR_ROLE) $GOV --rpc-url $RPC   # true
cast call $TOKEN $DATA --from 0x000000000000000000000000000000000000dEaD --rpc-url $RPC
#   reverts 0xe2517d3f = AccessControlUnauthorizedAccount: anyone else is refused
cast call $TOKEN $DATA --from $TL --rpc-url $RPC                    # succeeds: the Timelock may
```

These role reads show who holds a role, not that nobody else does:
OpenZeppelin `AccessControl` here is not enumerable. That no other
account holds them was established from the deployment's role history
and checked at launch (`docs/MAINNET_LAUNCH_RECORD.md`, step 3: 36/36).

**4. The effect, on your own fork** (no keys; nothing reaches mainnet).
The upstream must serve recent state: on 2026-10-01
`bsc-mainnet.public.blastapi.io` and `bsc.drpc.org` did;
`bsc-dataseed` and publicnode did not.

```bash
anvil --fork-url https://bsc-mainnet.public.blastapi.io --chain-id 56 --auto-impersonate --gas-price 0 --block-base-fee-per-gas 0
# in another shell, with the variables above:
F=http://127.0.0.1:8545
PAIR=0x40A97Ae210a44057603186B4BE92BAe719342AFA
STAKING=0xBb596e7308D6C5AED55cEC597D372840Cbe575b1
MIG=0x76368b60514b145617385847aCFF7b7EA9764725
cast send $TOKEN $DATA --unlocked --from $TL --legacy --gas-price 0 --rpc-url $F   # what execute() does
cast call $TOKEN "stakingRewardShareBps()(uint256)" --rpc-url $F                   # 600
N0=$(cast block-number --rpc-url $F)
# a poke: 1 wei of DMN straight to the pair (here from the Migration, which holds
# DMN; on your fork only). It converts if the token's own DMN balance is at least
# minimumTokensBeforeSwap().
cast send $TOKEN "transfer(address,uint256)" $PAIR 1 --unlocked --from $MIG --legacy --gas-price 0 --rpc-url $F
N1=$(cast block-number --rpc-url $F)
cast balance $TL --block $N0 --rpc-url $F;      cast balance $TL --block $N1 --rpc-url $F
cast balance $STAKING --block $N0 --rpc-url $F; cast balance $STAKING --block $N1 --rpc-url $F
```

Run on 2026-10-01 (poke in fork block 125009690), this printed the
Timelock going from 0 to
22,966,406,573,919,895 wei and staking from 0 to 34,449,609,860,879,841
wei: the 40 % and 60 % legs of the table above. The amounts follow the
pool; the 60/40 ratio of the marketing branch does not.

**5. The whole rehearsal**, all 20 rows, on your own fork:
`node script/g1/g1-fork.mjs` ([script/g1/README.md](../script/g1/README.md)).
It re-reads the calldata and the description from this page and
refuses to run if they don't encode `propose(token, 0,
setStakingRewardShareBps(600), description)`.
