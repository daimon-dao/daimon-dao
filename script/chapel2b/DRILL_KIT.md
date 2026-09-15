# Chapel 2b -- Guardian drill kit (H4, Scenarios H4.1-H4.7)

Prepared 2026-09-15 22:49-22:57 UTC from live Chapel state (block 131257516
onwards, chain 97). Everything below is either read from the chain or
deterministically derived from what is on it; nothing is assumed. The
signers paste the **target** and the **calldata** into Safe{Wallet} ->
New transaction -> Contract interaction -> custom (hex) data, value 0.
Rule H4.8 applies to every row: whoever confirms says aloud, in the group,
the contract and the function decoded from the hex BEFORE confirming.

## 1. Addresses (BSC Chapel, chain id 97)

| role | address |
|---|---|
| DaimonV2 token (proxy) | `0x48BD45D02641e688f63bD5129272C30A8828ad0b` |
| DaimonTimelock | `0xd8e86A7764247aA4Ecd751A4AFaB6e68a53f9736` |
| DaimonGovernor | `0x41F55DAc95A028c58Dd51FD72eec9101ed2DEd05` |
| Guardian: the test Safe (2 of 3, Safe v1.3.0) | `0x4253f80666E48a04CAbE4966Aa63035Dbb4f104F` |
| DaimonStaking (for the reads) | `0xdB1C23eAAa306A7dbaD410E0aAa8eBDD249c62d1` |

Safe owners as read on chain: `0xD9dB15E21836789a2CB9AfFe6EEbe2454162fc16`,
`0xdFfeAEb85Bb580641351649D4AD4ce0C6ABf687f`, `0xacA4FaA9A0CB89749ad8CB4383EF8c3AE1530F9b`;
threshold 2.

## 2. Guardian actions: target + calldata

All four are `value = 0`. Selectors: `setPaused(bool)` = `0x16c38b3c`,
`Governor.cancel(uint256)` = `0x40e58ee5`, `Timelock.cancel(bytes32)` =
`0xc4d252f5`. Regenerate with `cast calldata "<sig>" <args>`; decode what you
are about to sign with `cast calldata-decode "<sig>" <hex>`.

### 2a. Pause / unpause (H4.1, H4.2, H4.4) -- target: the TOKEN

| action | target | calldata |
|---|---|---|
| `setPaused(true)` | `0x48BD45D02641e688f63bD5129272C30A8828ad0b` | `0x16c38b3c0000000000000000000000000000000000000000000000000000000000000001` |
| `setPaused(false)` | `0x48BD45D02641e688f63bD5129272C30A8828ad0b` | `0x16c38b3c0000000000000000000000000000000000000000000000000000000000000000` |

What the contract does (src/DaimonV2.sol, `setPaused`): a pause is a
WINDOW, `pauseUntil = now + 14 days` clamped to `guardianExpiry`; it ends on
its own. Read `isPaused()`, never `paused`. Unpause always works, even after
the mandate ends; pausing reverts with `GuardianExpired` after
`guardianExpiry`. Every second of window scheduled is credited to the
migration deadline (`cumulativePauseSeconds`), and an early unpause does
NOT claw it back: the H4.1/H4.2 pair will move the effective migration
deadline forward by ~14 days. That is by design (#36); record the new
`effectiveMigrationDeadline()` in the journal.

Sentinel expectations: `PausedSet(true)` + `PauseScheduled(until)` URGENT on
pause; `PausedSet(false)` on unpause.

### 2b. Cancel through the Governor (H4.5) -- target: the GOVERNOR

`Governor.cancel(uint256 id)`: guardian only; works in ANY state before
execution (Pending, Active, Succeeded, Queued). If the proposal is queued it
also cancels the Timelock operation atomically (#26); if the operation was
already canceled directly at the Timelock it just converges the flag.

| proposal | target | calldata |
|---|---|---|
| P-A, id 2 | `0x41F55DAc95A028c58Dd51FD72eec9101ed2DEd05` | `0x40e58ee50000000000000000000000000000000000000000000000000000000000000002` |
| P-B, id 3 | `0x41F55DAc95A028c58Dd51FD72eec9101ed2DEd05` | `0x40e58ee50000000000000000000000000000000000000000000000000000000000000003` |

Sentinel: `ProposalCanceled(id)`; plus `Cancelled(opId)` from the Timelock
if the proposal was queued.

### 2c. Cancel directly at the Timelock (H4.6, H4.7) -- target: the TIMELOCK

`Timelock.cancel(bytes32 opId)`: CANCELLER_ROLE only. **Only valid once the
proposal has been QUEUED**: before `queue(id)` the operation does not exist
and the call reverts with `OperationNotScheduled` (the Safe's simulation will
show the revert). The opId is `keccak256(abi.encode(target, 0, data,
bytes32(0), timelockSalt))`; the salt is fixed at propose time, so the id is
computable now (values below, read back through `timelock.hashOperation`)
but it is only actionable after the queue. Do not sign this row before the
sentinel has shown `CallScheduled(opId, ...)`.

| proposal | opId (after queue) | target | calldata |
|---|---|---|---|
| P-A, id 2 | `0xd895606ccce44f00f6ca3af8a1fa99e6e1dbcf2221fd7b6b3ab50a39d9398e7d` | `0xd8e86A7764247aA4Ecd751A4AFaB6e68a53f9736` | `0xc4d252f5d895606ccce44f00f6ca3af8a1fa99e6e1dbcf2221fd7b6b3ab50a39d9398e7d` |
| P-B, id 3 | `0x86564200b67e9203c71e7eb160f7e5afdc016d7f632d18daf803800bfd0ccb12` | `0xd8e86A7764247aA4Ecd751A4AFaB6e68a53f9736` | `0xc4d252f586564200b67e9203c71e7eb160f7e5afdc016d7f632d18daf803800bfd0ccb12` |

Cross-check the opId on the day, from the chain, before signing:

```bash
cast call 0xd8e86A7764247aA4Ecd751A4AFaB6e68a53f9736 "hashOperation(address,uint256,bytes,bytes32,bytes32)(bytes32)" 0x48BD45D02641e688f63bD5129272C30A8828ad0b 0 <proposal.data> 0x0000000000000000000000000000000000000000000000000000000000000000 <proposal.timelockSalt> --rpc-url https://bsc-testnet.publicnode.com
```

and confirm it is scheduled: `operations(opId)` must return a non-zero
`readyTimestamp`, `executed=false`, `canceled=false`. After the direct
cancel, `Governor.state(id)` must read `6` (Canceled) on its own (#26).
Sentinel: `Cancelled(opId)`.

## 3. Live state at preparation (block 131257516, 2026-09-15 22:49:03 UTC)

| check | expected | read | verdict |
|---|---|---|---|
| token `hasRole(GUARDIAN_ROLE, Safe)` | true | true | PASS |
| token `hasRole(GOVERNANCE_ROLE, Timelock)` | true | true | PASS |
| token `guardianExpiry` | = the other two | 1883988338 (2029-09-13 10:05:38 UTC) | PASS |
| token `isPaused()` / `paused` / `pauseUntil` / `cumulativePauseSeconds` | false / false / 0 / 0 | false / false / 0 / 0 | PASS -- NOT paused |
| timelock `hasRole(CANCELLER_ROLE, Safe)` | true | true | PASS |
| timelock `hasRole(CANCELLER_ROLE, Timelock)` (self, post-mandate path) | true | true | PASS |
| timelock `hasRole(PROPOSER_ROLE, Governor)` / `EXECUTOR_ROLE` | true / true | true / true | PASS |
| timelock: Safe holds PROPOSER / EXECUTOR / ADMIN | false / false / false | false / false / false | PASS -- cancel only |
| timelock `ADMIN_ROLE`: self / deployer | true / false | true / false | PASS |
| timelock `guardianAuthorityExpiry` / `getMinDelay` | 1883988338 / 604800 | 1883988338 / 604800 (7 days) | PASS |
| governor `guardian()` | the Safe | `0x4253f80666E48a04CAbE4966Aa63035Dbb4f104F` | PASS |
| governor `guardianAuthorityExpiry` | 1883988338 | 1883988338 | PASS |
| governor `proposalThreshold` / `quorumBps` | 1000 DMN / 1000 | 1e21 / 1000 | PASS |
| Safe code / `getThreshold` / `VERSION` | present / 2 / 1.3.0 | 345 hex chars / 2 / "1.3.0" | PASS |
| 2b invariant: Timelock BNB / DMN | 0 / 0 | 0 / 0 (re-read after every send below) | PASS |
| token params | -- | `maxTxAmount` 5.00 B, `maxSwapSlippageBps` 500, `minimumTokensBeforeSwap` 0.20 B, `buyBackUpperLimit` 50 BNB, fees 10/10/20, share 1000 | -- |

The three expiries are the same number: one mandate, 2029-09-13 10:05:38 UTC.

## 4. The two throwaway proposals (created 2026-09-15, NOT voted)

### 4.0 Prerequisite, and a deviation from the plan as written

The 2b staking contract had ONE staker, the holder (4.00 B voting power).
The keystores `staker1..3` had never touched the 2b contracts (their stakes
belong to Level 2): zero DMN, zero voting power. To seed proposals from
someone other than the holder, two of them were funded the way a third
party would be on mainnet: predecessor tokens from the mock's owner
(`oldowner`, keystore holder3), a 1:1 claim through DaimonMigration, then a
365-day stake (option 3, 4.0x). Amounts sized so that EACH proposer meets
the 10 % quorum ALONE with its own FOR vote (the premise of Scenario W):

| step | who | tx | block |
|---|---|---|---|
| old.transfer(staker3, 0.30 B) | oldowner | `0xb99d0001bc1f137d0c03b496c961ca99dd8d66ac4fc629dd3e65af9a54f60a44` | 131258111 |
| old.transfer(staker1, 0.30 B) | oldowner | `0x10e139b10311b71fcb5d3f8e3cb6fe547af2b43def5c38624757daca7e186e40` | 131258118 |
| approve old -> migration | staker3 | `0x735e5e550ff68f0bfdb492e394a9133985f7a78d216d2363b0f01111294ddef3` | 131258128 |
| migration.claim(0.30 B), exact 1:1 | staker3 | `0xcd18c365adae290207c20ba4ac4a16f88d6874c0bc0d0d3a528f0b76ec5047d4` | 131258136 |
| approve DMN -> staking | staker3 | `0x5d4ddb094ed643c41fcc38211b8aaaba05762768caac6af2e922d5087badd48b` | 131258144 |
| staking.stake(0.30 B, option 3) -> 1.20 B voting power | staker3 | `0xc67b04e460e7467c1fc816331ab6c7c4844ef40ebeb993b4b2b6aa9a9dbc4bd3` | 131258151 |
| approve old -> migration | staker1 | `0x8f63d1e668be7b8898b074d25c3c00543049f6a87b35be2f16d1e1156d425066` | 131258163 |
| migration.claim(0.30 B), exact 1:1 | staker1 | `0xc751e5d95069e4e35aef1577b2ab04231ce7d89fe98ec10e18c20a61ee38950c` | 131258169 |
| approve DMN -> staking | staker1 | `0x83f585c6129a572934ee9b9f4907474be864ea098f1345fc1f9d5529a2fd8b7f` | 131258177 |
| staking.stake(0.30 B, option 3) -> 1.20 B voting power | staker1 | `0x539822269e40eb11284113fad2be0329745c312ad56b4a0079e74ffe19ec2aa3` | 131258184 |

Effects to carry into the journal: `totalVotingPower` 4.00 B -> 6.40 B
(holder 4.00, staker3 1.20, staker1 1.20); `totalMigrated` +0.60 B and the
Timelock's predecessor balance +0.60 B (the treasury working, allowed by
the invariant); the token contract's fee inventory unchanged (mock owner is
fee-exempt, migration and staking are fee-exempt). Proposal 0 is untouched:
its quorum is a snapshot (0.40 B needed, 4.00 B FOR). Proposal 1 untouched.
The 2b invariant (Timelock BNB 0, DMN 0) was re-read after every send: held.
`state.json` and `docs/CHAPEL_2B_RESULTS.md` were NOT written by this kit;
the operator records H4 in the journal at drill time.

### 4.1 P-A -- the hostile one (Scenario W, H4.7)

| field | value |
|---|---|
| id | **2** |
| proposer | staker3 `0xbb843DFe3dec6D7dFc4Ef194A1a9BDc7A07eac84` (1.20 B at the snapshot) |
| target / value | token `0x48BD45D02641e688f63bD5129272C30A8828ad0b` / 0 |
| data | `0xec28438affffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff` = `setMaxTxAmount(type(uint256).max)` |
| description | "Chapel 2b DRILL P-A (Scenario W, hostile): setMaxTxAmount(type(uint256).max) -- removes the per-transfer cap; throwaway proposal to be canceled by the guardian Safe; do not execute" |
| propose tx / block / ts | `0x6e878b68a920a6f8a5846688f4219c3434c25807b2bd090f7d2b29e1ba2a5af3` / 131258243 / 1789512870 (2026-09-15 22:54:30 UTC), gas 460340 |
| snapshotBlock / snapshotTotalVotingPower | 131258242 / 6.40 B |
| quorum (10 % of snapshot) | **0.64 B** for+abstain, and for > against |
| voteStart | 1789599270 = **2026-09-16 22:54:30 UTC** |
| voteEnd | 1790031270 = **2026-09-21 22:54:30 UTC** |
| earliest execute if queued at voteEnd | 2026-09-28 22:54:30 UTC (7-day Timelock) |
| timelockSalt | `0x58a832d2ab8d15f59c6f9093ab4d93ab2d3a6df30f1d19a0efc3b11163972250` |
| opId once queued | `0xd895606ccce44f00f6ca3af8a1fa99e6e1dbcf2221fd7b6b3ab50a39d9398e7d` |
| state at preparation | 0 = Pending; no votes |

### 4.2 P-B -- the harmless one (H4.5 / H4.6)

| field | value |
|---|---|
| id | **3** |
| proposer | staker1 `0xfbcE9e13C309549c82B0775C8587E3470f2837b0` (1.20 B at the snapshot) |
| target / value | token `0x48BD45D02641e688f63bD5129272C30A8828ad0b` / 0 |
| data | `0xe89d59de00000000000000000000000000000000000000000000000000000000000001f4` = `setMaxSwapSlippageBps(500)`, the CURRENT value: a no-op even if executed |
| description | "Chapel 2b DRILL P-B (harmless): setMaxSwapSlippageBps(500) -- the current value, a no-op; throwaway proposal for the guardian cancel drills" |
| propose tx / block / ts | `0x4f258ce1e03ece42484b296700fe9a5ed98ac3f89d7e654152c9302f7113d8b9` / 131258304 / 1789512898 (2026-09-15 22:54:58 UTC), gas 436898 |
| snapshotBlock / snapshotTotalVotingPower | 131258303 / 6.40 B |
| quorum (10 % of snapshot) | **0.64 B** for+abstain, and for > against |
| voteStart | 1789599298 = **2026-09-16 22:54:58 UTC** |
| voteEnd | 1790031298 = **2026-09-21 22:54:58 UTC** |
| earliest execute if queued at voteEnd | 2026-09-28 22:54:58 UTC |
| timelockSalt | `0xbece6405b58ad27650973b1ef8a096dde74dd496c2574ff41914cb6b0c181213` |
| opId once queued | `0x86564200b67e9203c71e7eb160f7e5afdc016d7f632d18daf803800bfd0ccb12` |
| state at preparation | 0 = Pending; no votes |

### 4.3 Sequencing the cancel drills on the real clock

- **Cancel while Pending/Active** (Governor path only): possible from now
  for either id, no vote needed. This is the cheapest rehearsal of 2b, but
  it does not exercise the Timelock leg.
- **Cancel in the queue** (H4.5 via Governor, H4.6/H4.7 direct at the
  Timelock): the proposal must first PASS. With no vote at all both lapse
  to Defeated after 2026-09-21 22:54 UTC and can no longer be queued. The
  plan's "nobody votes" means nobody ELSE votes: the proposer casts its own
  FOR (1.20 B >= 0.64 B) between 2026-09-16 22:54 and 2026-09-21 22:54 UTC,
  anyone calls `queue(id)` after voteEnd, and the Safe cancels within the 7
  days (stopwatch from `CallScheduled` to `Cancelled`). The holder voting
  AGAINST with 4.00 B is Defense 1 and defeats it; do not, if the queue is
  wanted. Suggested split: P-B -> H4.5 (`Governor.cancel(3)`, atomic
  cross-cancel), P-A -> H4.6+H4.7 (`Timelock.cancel(opId)` direct, then
  `Governor.state(2)` must read Canceled).
- Votes on 2 and 3 are the operator's call at drill time; none were cast.

## 5. Reads to confirm each drill

```bash
RPC=https://bsc-testnet.publicnode.com
cast call 0x48BD45D02641e688f63bD5129272C30A8828ad0b "isPaused()(bool)" --rpc-url $RPC
cast call 0x48BD45D02641e688f63bD5129272C30A8828ad0b "pauseUntil()(uint256)" --rpc-url $RPC
cast call 0x9c54e19bad8AcA0b7910C0E88BfBcAAbB249B718 "effectiveMigrationDeadline()(uint256)" --rpc-url $RPC
cast call 0x41F55DAc95A028c58Dd51FD72eec9101ed2DEd05 "state(uint256)(uint8)" 2 --rpc-url $RPC   # 0 Pending 1 Active 2 Defeated 3 Succeeded 4 Queued 5 Executed 6 Canceled
cast call 0xd8e86A7764247aA4Ecd751A4AFaB6e68a53f9736 "operations(bytes32)(uint256,bool,bool)" 0xd895606ccce44f00f6ca3af8a1fa99e6e1dbcf2221fd7b6b3ab50a39d9398e7d --rpc-url $RPC
```

Migration deadline at preparation: 1791972340 = 2026-10-14 10:05:40 UTC
(moves forward by the pause window scheduled in H4.1).
