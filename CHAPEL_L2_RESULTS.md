# Level 2 campaign -- BSC Chapel, real time (branch chapel/level-2)

Level 1 proved the logical sequences on a local fork, where time can be
warped. This level proves what a local node cannot show: real latency, real
nonces, real gas, a 7-day timelock that actually takes 7 days, and the
launch order rehearsed end to end with the exact scripts that will run on
mainnet. Methodology as the July testnet campaign: every step recorded,
every transaction hash preserved.

Base: master `813be30` (consolidated: Level 1 harness + two-phase deploy).
Chain: BSC Chapel (id 97), RPC `https://bsc-testnet.publicnode.com`.
Configuration: REAL -- timelock 7 days, nothing shortened.

## Account safety (recorded before any funding was used)

Level 1 finding carried forward: the ten well-known public development
mnemonic accounts carry EIP-7702 delegation designators on BSC testnet --
funds sent to them are forwarded away automatically (one account was
drained this way during scenario B2). None of those accounts is used here.
Every role below was generated fresh by the operator, lives in an encrypted
keystore (`cast wallet import --interactive`), and no private key is ever
written in any file, script or log of this campaign.

Verified at block **127607314** (2026-08-28, chain id 97 confirmed):

| role | address | code | balance | nonce |
|---|---|---|---|---|
| deployer | 0x052bB2834d292d078cf686F5f4BB2bb55E424943 | `0x` (none) | 0.35 tBNB | 0 |
| guardian | 0x74D6140C874E0C9142b8312eDA8175B3c447a0F2 | `0x` (none) | 0.08 tBNB | -- |
| staker1 | 0xfbcE9e13C309549c82B0775C8587E3470f2837b0 | `0x` (none) | 0.08 tBNB | -- |
| staker2 | 0x36E3A9f60AD6e89835Ee0f3a4b8BC9283cFA83d1 | `0x` (none) | 0.08 tBNB | -- |
| staker3 | 0xbb843DFe3dec6D7dFc4Ef194A1a9BDc7A07eac84 | `0x` (none) | 0.08 tBNB | -- |
| holder1 | 0x583982463dA108879566868506Cba32E7b023576 | `0x` (none) | 0.08 tBNB | -- |
| holder2 | 0x66332d032b4F9583A4D85FB2b97B93F8311A39F2 | `0x` (none) | 0.08 tBNB | -- |
| holder3 | 0xD7ca3011eB7Caae4A76c245c93FaAc56A7F58DaE | `0x` (none) | 0.08 tBNB | -- |
| stranger | 0x05Eb589Cba778FdFeE6bf2Dc0C1EFd32b48006e2 | `0x` (none) | 0.08 tBNB | 0 |

Every role: **no code** (no EIP-7702 delegation, no contract), balance
exactly as funded. The deployer nonce is 0 -- virgin, which matters for the
CREATE-address predictions of the two-phase deploy.

Marketing wallet for this campaign: `0x000000000000000000000000000000000000A001`
-- keyless and code-free (verified: `code=0x`, balance 0). The global
invariant asserts after every send that it holds zero DMN and zero native.

## The global invariant

After every step of every part: the marketing wallet has received nothing,
checked programmatically by the harness (`script/chapel/lib.ps1`,
`Assert-Invariants`). The total count of checks is reported at closing.

## Signing model

Every transaction is signed through `cast send --account <keystore-name>
--password-file <path>`. Keystore names and the password-file path live in
`script/chapel/keystore-map.json`, which is gitignored: no key, no password
and no path appears in the repository or in this log.

---
## Part 3 scope note and static event check

The monitor spec now lives at `docs/SPEC_MONITOR.md` (added on operator
instruction; the bot itself is a SEPARATE project, read-only, no private
keys, built outside this repository). For this campaign, Part 3 is limited
to two things: verifying that the events the monitor will observe are
actually emitted and readable on the Chapel contracts, and recording the
deployed addresses the bot will be pointed at.

Static cross-check of the spec's "urgent" event names against the source,
done before deploy (all seven resolve):

| event | defined in |
|---|---|
| PausedSet(bool) | src/DaimonV2.sol:273 |
| PauseScheduled(uint256) | src/DaimonV2.sol:276 |
| FeesUpdated(uint256,uint256,uint256) | src/DaimonV2.sol:271 |
| ExcludedFromFeeSet(address,bool) | src/DaimonV2.sol:279 |
| MarketingWalletSet(address) | src/DaimonV2.sol:278 |
| ParamsUpdated(string,uint256) | src/DaimonV2.sol:272 |
| Upgraded(address) | ERC-1967 standard, emitted by the proxy (OZ IERC1967) |

---
## Keystore mapping verification

Before any signature: each keystore NAME resolved to its expected role
address via `cast wallet address` (reads the address only; no key ever
leaves the keystore). Result: **9 of 9 match** (deployer, guardian,
staker1-3, holder1-3, stranger). A tenth keystore present on the machine
(`daimon-deployer2`) is an old account, NOT part of this campaign, and is
never referenced by the harness map.

Harness note, recorded because it cost the first hour: PowerShell variable
names are case-insensitive, so a scenario-level `$addr` silently OVERWROTE
the harness global `$script:Addr` (and `$ks` did the same to `$script:KS`),
emptying the role maps after the first signed call. The globals are renamed
to collision-proof names (`AddrBook`, `KsMap`). Harness-side fix; no chain
interaction was affected.

## The mock predecessor distribution (operator-confirmed)

1000B total, shaped like the live predecessor: one large third-party
holder (~17% of third-party circulating, ratio large/medium ~3:1), a
medium group, the real team share, and a non-migratable share.

| account | amount | meaning |
|---|---|---|
| holder1 | 170B | the large third party |
| holder2 | 60B | medium |
| holder3 | 40B | medium |
| staker1 | 15B | staker |
| staker2 | 15B | staker |
| staker3 | 15B | staker |
| deployer (kept) | 427B | team share (two real wallets, merged here) |
| dead | 20B | non-migratable |
| mock contract | 15B | non-migratable |
| deployer (kept) | 223B | the world that does not migrate |

Migratable maximum: 1000B - 35B = 965B. Funding check (A5 rule): the
Migration holds the full 1000B >= 965B.

Initial liquidity (operator-confirmed): 0.10 tBNB against 0.10B DMN NET --
the BNB leg computed on the DMN the pair actually receives after the 5%
fee, never on the gross sent (#17, proven in B0).

---

### P1.1 -- Mock predecessor deployed and distributed (no treasury exemption yet)

| step | action | expected | observed | tx | verdict |
|---|---|---|---|---|---|
| P1.1.1 | CampaignOldDaimon deployed, 1000B minted to the deployer | contract live, owner = deployer | old=0x80062b0a521d7caE1E7b48514064465e72ADd49f (2026-08-28 00:03 UTC) | 0x64af7faf6722fefbd95418ca060ca0e7d0fc8255e6be1238bbd4cde535b47aec | PASS |
| P1.1.2 | Owner self-exemption for exact distribution | excludedFromFee(deployer)=true | true (2026-08-28 00:03 UTC) | 0xdc97a7248eeeb2b2baaa63635a5b9adbee70333da7d4b0021bd7eb0e23ff0423 | PASS |
| P1.1.3 | Distribute 170.00B to holder1 | exact credit (owner exempt, no fee) | balance=0.0000 B (2026-08-28 00:03 UTC) | 0xc7ea704f0d067fe7dbb3e24805da54ad4b0847ebe77d44b765106e653a5b32cb | PASS |
| P1.1.4 | Distribute 60.00B to holder2 | exact credit (owner exempt, no fee) | balance=0.0000 B (2026-08-28 00:03 UTC) | 0xf6046b8f8e0e285c808c19e5ffad12ebda2a8cdd4fa6f5f75fd83d02dabcd777 | PASS |
| P1.1.5 | Distribute 40.00B to holder3 | exact credit (owner exempt, no fee) | balance=0.0000 B (2026-08-28 00:03 UTC) | 0x3893bf50a34572e7cb620bd71683c104f58383976f83be8fbaa549caf0acb4d7 | PASS |
| P1.1.6 | Distribute 15.00B to staker1 | exact credit (owner exempt, no fee) | balance=0.0000 B (2026-08-28 00:03 UTC) | 0x420b9cbef14dd363a8d870da521d4004599224322e6b28a5f668edb70ec5118e | PASS |
| P1.1.7 | Distribute 15.00B to staker2 | exact credit (owner exempt, no fee) | balance=0.0000 B (2026-08-28 00:03 UTC) | 0x106de1909bc3a3b9ea54f1a050efe80a8823211a4d0f4fc46856603b20ac3323 | PASS |
| P1.1.8 | Distribute 15.00B to staker3 | exact credit (owner exempt, no fee) | balance=0.0000 B (2026-08-28 00:03 UTC) | 0x870d1cb4af414e95a93711e51028ccb2467d7698cb6c142e9b0e7409f2e8e64f | PASS |
| P1.1.9 | Distribute 20.00B to dead | exact credit (owner exempt, no fee) | balance=0.0000 B (2026-08-28 00:03 UTC) | 0x09d9b8be349f1414b3ad2b08db76dda14e5ec80f20d29afe6bfb9c5b712501ce | PASS |
| P1.1.10 | Distribute 15.00B to mock-contract | exact credit (owner exempt, no fee) | balance=0.0000 B (2026-08-28 00:03 UTC) | 0x9285a271c407a833fa51fc90cb5719ad9f57472a5eb6b8b8012d806bd5d54521 | PASS |
| P1.1.11 | Deployer residual: team share 427B + non-migrating world 223B | 650B kept at the deployer (bookkeeping split) | balance=0.0000 B (2026-08-28 00:03 UTC) | - | PASS |
| P1.1.12 | Treasury fee exemption on the mock | NOT set (launch order: it comes AFTER the post-broadcast verification) | not applicable yet: treasury address does not exist until phase 2 (2026-08-28 00:03 UTC) | - | PASS |

> **ATTEMPT INVALIDATED -- harness unit bug, recorded and redone.** The table
> above shows `balance=0.0000 B` on every distribution row with a PASS
> verdict: both sides of the comparison used the same broken `BW` helper,
> which converted to TOKENS instead of BILLIONS (the x1e9 factor was lost
> porting the Level-1 helper). The mock at
> `0x80062b0a521d7caE1E7b48514064465e72ADd49f` received a distribution 1e9
> times too small and is ABANDONED (never referenced again; its tokens have
> no value). Harness fixed (BW carries the x1e9; the tautological-PASS
> lesson: the expected side of an exactness check must come from an
> independent constant, which the redo below does). Phase 1 had not run;
> no protocol contract existed yet. Redone in full as P1.1-bis.

### P1.1-bis -- Mock predecessor deployed and distributed (clean redo; no treasury exemption)

| step | action | expected | observed | tx | verdict |
|---|---|---|---|---|---|
| P1.1b.1 | CampaignOldDaimon deployed, supply minted to the deployer | totalSupply == 1e30 (1000B with 18 decimals) | old=0xa0de1CB265757Cf8C07b4eDCa4454E95bce33c4F, totalSupply=1000000000000000000000000000000 (2026-08-28 00:05 UTC) | 0x74f6c9d455ceb50606ec8f7d574677ad76c0b0c8a8875e91aa6cf507de98914c | PASS |
| P1.1b.2 | Owner self-exemption for exact distribution | excludedFromFee(deployer)=true | true (2026-08-28 00:05 UTC) | 0x19ac7c67f60199c2b765c3338d99f52953727941d4fb9f0388427c839ebcb72c | PASS |
| P1.1b.3 | Distribute 170.00B to holder1 | exact credit: 170000000000000000000000000000 wei | balance=170.0000 B (170000000000000000000000000000 wei) (2026-08-28 00:05 UTC) | 0x753cc622dde781d2a98ae85b85480d9f818cad84a8bce600d4321338d9366253 | PASS |
| P1.1b.4 | Distribute 60.00B to holder2 | exact credit: 60000000000000000000000000000 wei | balance=60.0000 B (60000000000000000000000000000 wei) (2026-08-28 00:05 UTC) | 0x6aa6990fd3f2aedee1873c14064f3766d4684256e39c0298d1255ff7afe8f90f | PASS |
| P1.1b.5 | Distribute 40.00B to holder3 | exact credit: 40000000000000000000000000000 wei | balance=40.0000 B (40000000000000000000000000000 wei) (2026-08-28 00:05 UTC) | 0xdce4e013b1aa9549213681d3310dfe5e0165add9640e49ab1d6fbadad65bfb05 | PASS |
| P1.1b.6 | Distribute 15.00B to staker1 | exact credit: 15000000000000000000000000000 wei | balance=15.0000 B (15000000000000000000000000000 wei) (2026-08-28 00:05 UTC) | 0xab681cad6ff4cce2b27849c5eb6c2f9b3a3b82d41e7140817b64eac7615b28da | PASS |
| P1.1b.7 | Distribute 15.00B to staker2 | exact credit: 15000000000000000000000000000 wei | balance=15.0000 B (15000000000000000000000000000 wei) (2026-08-28 00:05 UTC) | 0x97a6ccbd356b2e5540f64b449a19c8d1a03cbb1e402705dc92138ed9e985eb8d | PASS |
| P1.1b.8 | Distribute 15.00B to staker3 | exact credit: 15000000000000000000000000000 wei | balance=15.0000 B (15000000000000000000000000000 wei) (2026-08-28 00:05 UTC) | 0xc49d216a0a171eec2d5a00d3fb4adce819ca5f1b77bda198ba0cfd7536d009eb | PASS |
| P1.1b.9 | Distribute 20.00B to dead | exact credit: 20000000000000000000000000000 wei | balance=20.0000 B (20000000000000000000000000000 wei) (2026-08-28 00:05 UTC) | 0x262ccbc240522279b422996ad66edf8f1a05658864836062f71311fb8d942c1c | PASS |
| P1.1b.10 | Distribute 15.00B to mock-contract | exact credit: 15000000000000000000000000000 wei | balance=15.0000 B (15000000000000000000000000000 wei) (2026-08-28 00:06 UTC) | 0x226d7504fddf820a4629f8f918307b78ac9cb57972a39d7d51c02244ba81238c | PASS |
| P1.1b.11 | Deployer residual: team 427B + non-migrating world 223B | 650000000000000000000000000000 wei kept | balance=650.0000 B (650000000000000000000000000000 wei) (2026-08-28 00:06 UTC) | - | PASS |
| P1.1b.12 | Treasury fee exemption on the mock | NOT set (launch order: AFTER the post-broadcast verification) | deferred by design (2026-08-28 00:06 UTC) | - | PASS |

### P1.2 -- Phase 1: Migration + token (predicted Timelock recorded; treasury derived)

| step | action | expected | observed | tx | verdict |
|---|---|---|---|---|---|
| P1.2.1 | #25 preflight: pair for the PREDICTED proxy on the factory | zero address - nobody pre-created it | predictedProxy=0x37eEb553de4F6865efC5d8240CFA3B4a465a046f (nonce 21), getPair=0x0000000000000000000000000000000000000000 (2026-08-28 00:07 UTC) | - | PASS |
| P1.2.2 | Phase 1 broadcast: impl + proxy + migration | code at both addresses, proxy at the predicted address | token=0x37eEb553de4F6865efC5d8240CFA3B4a465a046f (code 262 ch), migration=0xBB5A86ad9f337927c271c7698dE8E07dEaF84d42 (code 6122 ch), proxy-as-predicted=True (2026-08-28 00:08 UTC) | journal broadcast/DeployPhase1.s.sol/97 | PASS |
| P1.2.3 | Supply placement | the full 1e30 in the Migration, never through an EOA | 1000.0000 B (1000000000000000000000000000000 wei) (2026-08-28 00:08 UTC) | - | PASS |
| P1.2.4 | The two predictions, from live chain state | governance AND treasury both = the predicted timelock (derived, never typed) | predictedTimelock=0xb5084C65e1ceb2a4DEcb0f391872805110Bd4932, migration.governance=0xb5084C65e1ceb2a4DEcb0f391872805110Bd4932, migration.treasury=0xb5084C65e1ceb2a4DEcb0f391872805110Bd4932, overridden=False (2026-08-28 00:08 UTC) | - | PASS |

State file after phase 1, verbatim:

```json
{
  "chainId": 97,
  "deployer": "0x052bB2834d292d078cf686F5f4BB2bb55E424943",
  "expectedPhase2Nonce": 23,
  "guardian": "0x74D6140C874E0C9142b8312eDA8175B3c447a0F2",
  "marketingWallet": "0x000000000000000000000000000000000000a001",
  "migration": "0xBB5A86ad9f337927c271c7698dE8E07dEaF84d42",
  "oldDaimon": "0xa0de1CB265757Cf8C07b4eDCa4454E95bce33c4F",
  "predictedTimelock": "0xb5084C65e1ceb2a4DEcb0f391872805110Bd4932",
  "router": "0xD99D1c33F9fC3444f8101754aBC46c52416550D1",
  "token": "0x37eEb553de4F6865efC5d8240CFA3B4a465a046f",
  "tokenImplementation": "0x3092A5Fa4136251FBF1dC0469aF27e6c5A65B666",
  "treasury": "0xb5084C65e1ceb2a4DEcb0f391872805110Bd4932",
  "treasuryOverridden": false
}
```

### P1.3 -- Phase 2: Timelock + Staking + Governor -- expiry read from the live chain

| step | action | expected | observed | tx | verdict |
|---|---|---|---|---|---|
| P1.3.1 | Phase 2 broadcast: timelock + staking + governor + wiring + renounce | timelock lands EXACTLY on the phase-1 prediction | timelock=0xb5084C65e1ceb2a4DEcb0f391872805110Bd4932, predicted=0xb5084C65e1ceb2a4DEcb0f391872805110Bd4932, match=True (2026-08-28 00:10 UTC) | journal broadcast/DeployPhase2.s.sol/97 | PASS |
| P1.3.2 | Guardian expiry from the three live contracts on a PUBLIC chain | EXACT equality - the A1.8 skew is what this deploy design removed | token=1882483692, timelock=1882483692, governor=1882483692 (2026-08-28 00:10 UTC) | - | PASS |
| P1.3.3 | The expiry embedded in the phase-2 constructor calldata | equals the live token value (where A1.8 found the 4-second skew) | calldata=1882483692, live=1882483692 (2026-08-28 00:10 UTC) | 0xfe70b471d21e6912d116e39c7c8792e7c274e1e58aef086111b865736c616574 | PASS |
| P1.3.4 | Both phase-1 predictions fulfilled on live state | migration.governance == migration.treasury == the deployed timelock | treasury=0xb5084C65e1ceb2a4DEcb0f391872805110Bd4932 (2026-08-28 00:10 UTC) | - | PASS |
| P1.3.5 | Launch compliance configuration | stakingRewardShareBps == 1000, set and asserted in phase 2 | 1000 (2026-08-28 00:10 UTC) | - | PASS |

State file after phase 2 (the complete deployment record), verbatim:

```json
{
  "chainId": 97,
  "deployer": "0x052bB2834d292d078cf686F5f4BB2bb55E424943",
  "governor": "0xB1eA20ef50546a7206E48F160A0fe54833c20eE0",
  "guardian": "0x74D6140C874E0C9142b8312eDA8175B3c447a0F2",
  "guardianAuthorityExpiry": 1882483692,
  "marketingWallet": "0x000000000000000000000000000000000000a001",
  "migration": "0xBB5A86ad9f337927c271c7698dE8E07dEaF84d42",
  "oldDaimon": "0xa0de1CB265757Cf8C07b4eDCa4454E95bce33c4F",
  "router": "0xD99D1c33F9fC3444f8101754aBC46c52416550D1",
  "staking": "0x2871977e1978f6DAbE66C617d0627B0eFD54FbA4",
  "timelock": "0xb5084C65e1ceb2a4DEcb0f391872805110Bd4932",
  "token": "0x37eEb553de4F6865efC5d8240CFA3B4a465a046f",
  "tokenImplementation": "0x3092A5Fa4136251FBF1dC0469aF27e6c5A65B666",
  "treasury": "0xb5084C65e1ceb2a4DEcb0f391872805110Bd4932",
  "treasuryOverridden": false
}
```

### P1.4 -- Post-broadcast verification: 34 checks from mined state (any failure stops the campaign)

| step | action | expected | observed | tx | verdict |
|---|---|---|---|---|---|
| P1.4.1 | script/verify-deploy.ps1 -Rpc <chapel> | every check green, exit 0 | exit=0; Post-broadcast verification -- chain 97 VERIFICATION PASSED: 34/34 checks green against live chain state. (2026-08-28 00:11 UTC) | - | PASS |

Full output, verbatim:

```
Post-broadcast verification -- chain 97
State file: C:\Users\Utente\Desktop\Daimon dao\deployments\two-phase-97.json


check                                  expected                                   observed                                   verdict
-----                                  --------                                   --------                                   -------
code at token                          present                                    present                                    PASS
code at timelock                       present                                    present                                    PASS
code at governor                       present                                    present                                    PASS
code at staking                        present                                    present                                    PASS
code at migration                      present                                    present                                    PASS
token: timelock holds GOVERNANCE_ROLE  true                                       true                                       PASS
token: deployer lacks GOVERNANCE_ROLE  false                                      false                                      PASS
token: deployer lacks DEFAULT_ADMIN    false                                      false                                      PASS
token: guardian holds GUARDIAN_ROLE    true                                       true                                       PASS
token: stakingRewardShareBps == 1000   1000                                       1000                                       PASS
token: stakingContract is the staking  0x2871977e1978f6DAbE66C617d0627B0eFD54FbA4 0x2871977e1978f6DAbE66C617d0627B0eFD54FbA4 PASS
token: marketingWallet as configured   0x000000000000000000000000000000000000a001 0x000000000000000000000000000000000000a001 PASS
token: migration is fee-exempt         true                                       true                                       PASS
timelock: self-administers             true                                       true                                       PASS
timelock: deployer lacks ADMIN_ROLE    false                                      false                                      PASS
timelock: deployer lacks PROPOSER_ROLE false                                      false                                      PASS
timelock: deployer lacks EXECUTOR_ROLE false                                      false                                      PASS
timelock: governor is proposer         true                                       true                                       PASS
timelock: governor is executor         true                                       true                                       PASS
timelock: guardian is canceller        true                                       true                                       PASS
timelock: governor is canceller        true                                       true                                       PASS
timelock: self-cancel role present     true                                       true                                       PASS
expiry: timelock == token (exact)      1882483692                                 1882483692                                 PASS
expiry: governor == token (exact)      1882483692                                 1882483692                                 PASS
staking: timelock is governance        true                                       true                                       PASS
staking: deployer is not governance    false                                      false                                      PASS
supply: totalSupply == INITIAL_SUPPLY  1000000000000000000000000000000            1000000000000000000000000000000            PASS
supply: all of it in the migration     1000000000000000000000000000000            1000000000000000000000000000000            PASS
migration: governance is the timelock  0xb5084C65e1ceb2a4DEcb0f391872805110Bd4932 0xb5084C65e1ceb2a4DEcb0f391872805110Bd4932 PASS
migration: newDaimon is the token      0x37eEb553de4F6865efC5d8240CFA3B4a465a046f 0x37eEb553de4F6865efC5d8240CFA3B4a465a046f PASS
migration: oldDaimon as configured     0xa0de1CB265757Cf8C07b4eDCa4454E95bce33c4F 0xa0de1CB265757Cf8C07b4eDCa4454E95bce33c4F PASS
migration: treasury as configured      0xb5084C65e1ceb2a4DEcb0f391872805110Bd4932 0xb5084C65e1ceb2a4DEcb0f391872805110Bd4932 PASS
migration: treasury is the timelock    0xb5084C65e1ceb2a4DEcb0f391872805110Bd4932 0xb5084C65e1ceb2a4DEcb0f391872805110Bd4932 PASS
token: pancake pair created            present                                    present                                    PASS



Guardian expiry raw values: token=1882483692 timelock=1882483692 governor=1882483692
VERIFICATION PASSED: 34/34 checks green against live chain state.

```

### P1.5 -- The exemption goes last: claims impossible during the window, then opened

| step | action | expected | observed | tx | verdict |
|---|---|---|---|---|---|
| P1.5.1 | holder1 attempts a 10B claim BEFORE the exemption exists | REVERTS with AmountMismatch (#29): the treasury is not fee-exempt on the predecessor, so no claim was possible at any point between the phases | approved (as expected - approvals are not gated); claim: reverted with AmountMismatch (2026-08-28 00:13 UTC) | - | PASS |
| P1.5.2 | excludeFromFee(TIMELOCK) on the mock predecessor - launch order step 4 | exemption active: the migration window effectively OPENS here | excludedFromFee(timelock)=true (2026-08-28 00:13 UTC) | 0x55c311a9376a1cbd8da6201c441eee5e07fe53fc2d83801c0afd6e572eaf8aa1 | PASS |
| P1.5.3 | The same holder claims 1B immediately after | exact 1:1 receipt - the window is open and clean | DMN=1.0000 B (1000000000000000000000000000 wei), gas=225720 (2026-08-28 00:13 UTC) | 0xcf404bcf8be9ae88c9cee2b8cf284fd876c197d61a1ded5527e9d9a086dbaf27 | PASS |

### P1.8 -- One pool only: stored pair == factory pair

| step | action | expected | observed | tx | verdict |
|---|---|---|---|---|---|
| P1.8.1 | The pair the contracts store vs the pair the factory created | identical - a wrong address breaks fee-swap and buyback silently | token.uniswapV2Pair=0x94bBA28e7E80Fdc6a530bA765Ec966E0dD1CB23C, factory.getPair=0x94bBA28e7E80Fdc6a530bA765Ec966E0dD1CB23C (2026-08-28 00:13 UTC) | - | PASS |


### P1.7 -- Initial liquidity: BNB leg on the NET, opening price verified

| step | action | expected | observed | tx | verdict |
|---|---|---|---|---|---|
| P1.7.1 | Automation state before liquidity (#27) | armed by initialize, and inert by construction: no inventory exists, pokes are the only trigger (#1), and the fail-open fix is in the audited bytecode (BuyBackSkipped paths) | swapAndLiquifyEnabled=true, fee inventory=0.0000 B (2026-08-28 00:15 UTC) | - | PASS |
| P1.7.2 | Deployer migrates 4.5B for the pool and later steps | exact 1:1 (both legs fee-exempt for this path) | DMN=4.5000 B, gas=186720 (2026-08-28 00:15 UTC) | 0xf669d7dac53f7a42f4f2e355111ec2866cf6b94d4f157971f6fcf1ebd58d6b96 | PASS |
| P1.7.3 | addLiquidityETH: gross 105263157894736842105263157 wei DMN + 0.1 tBNB | the pair holds ~1e26 DMN NET (gross minus the 5% fee) and 1e17 BNB | reserves DMN=100000000000000000000000000 (delta from target: 0 wei), BNB=100000000000000000; gas=382188 (2026-08-28 00:15 UTC) | 0x6a1a1b25082d573b5ba219fdda4462ef728d345f46bef5b531cf2f32e9aee65e | PASS |
| P1.7.4 | Opening price from ACTUAL reserves | 1e9 DMN per BNB - the intended price, computed on the net (#17) | ratio=1000000000 DMN/BNB (2026-08-28 00:15 UTC) | - | PASS |

### P1.9 -- Reserves non-zero, automation armed: a small test swap pays the fee

| step | action | expected | observed | tx | verdict |
|---|---|---|---|---|---|
| P1.9.1 | holder1 sells 0.05B through the real router | the 5% fee lands in the token contract as inventory; the seller receives BNB | fee inventory +0.0020 B (expected ~0.0025 B), holder1 BNB +0.0321 (net of est. gas); gas=226811 (2026-08-28 00:15 UTC) | 0x19ac44c05c56b18066d267d724663fa4cc4acc88d7d574784d4f44b3f4d1f773 | PASS |
| P1.9.2 | Did the sell trigger any conversion? (#1) | no: router-initiated transfers skip the automation - inventory only grew | inventory 0.0042 B -> 0.0062 B (2026-08-28 00:15 UTC) | - | PASS |

> Precision note on P1.9.1: the inventory grew by exactly 4% of the sell
> (0.002B), not 5% -- the 5% total splits into 1% taxFee (reflected to
> holders, never inventoried) and 4% liquidityFee (the convertible
> inventory). The "expected ~0.0025B" in the row overstated the inventory
> share; the observed value is the correct one. Expectation-side
> imprecision, recorded not hidden.

### P2.5a -- Stakers migrate and lock: three real accounts, three lock tiers

| step | action | expected | observed | tx | verdict |
|---|---|---|---|---|---|
| P2.5a.1 | staker1 migrates 15B, stakes 5B on option 3 (4.0x/365d) | voting power = 20000000000000000000000000000 wei | vp=20.0000 B (20000000000000000000000000000 wei); claim gas=181920, stake gas=-519198 (2026-08-28 00:17 UTC) | 0xb09c98a877d90a992fbc543be6dbef73603033a9da4493c27ff87d32a8b000e1 / 0x5939a3d0f453cdb0a9d27ce438b55f5e79f9a53d7f8dc2df19b809cd63402137 | PASS |
| P2.5a.2 | staker2 migrates 15B, stakes 5B on option 1 (1.5x/90d) | voting power = 7500000000000000000000000000 wei | vp=7.5000 B (7500000000000000000000000000 wei); claim gas=181920, stake gas=446253 (2026-08-28 00:17 UTC) | 0xe811f3b0d771c75cb371ca86e3935626b16a868667ee13c1670d89c882fcc843 / 0xc9174f9b479d5e0001ee7b6a0469491f3a42f8cb89872a5fd79cc1fe2508617d | PASS |
| P2.5a.3 | staker3 migrates 15B, stakes 5B on option 0 (1.0x/30d) | voting power = 5000000000000000000000000000 wei | vp=5.0000 B (5000000000000000000000000000 wei); claim gas=181920, stake gas=446241 (2026-08-28 00:17 UTC) | 0x2262a919b85308b549ebe629295ca7b64d3742d6e809f5af8a191c74093ec34b / 0xeea51e044ba34e6da2fa251c2722d52c9518cc069bee7a2b394ac0bfd37e1702 | PASS |
| P2.5a.4 | Aggregate voting power | 32.5B = 20 + 7.5 + 5 | 32.5000 B (32500000000000000000000000000 wei) (2026-08-28 00:17 UTC) | - | PASS |

### P2.1 -- Governance cycle, day 1: propose (the 7-day timelock starts its real clock later at queue)

| step | action | expected | observed | tx | verdict |
|---|---|---|---|---|---|
| P2.1.1 | staker1 proposes setFees(10,10,20) (recovered from chain after a harness crash) | proposal 0 created, state Pending (voting delay 1 REAL day) | id=0, state=0 (0=Pending), event block=127621844, recorded 2026-08-28 00:18:56 UTC (2026-08-28 00:18 UTC) | 0x242e0afab36e9a842ce9f5e70a393ea911304d25b87bd52b6a17d3ef557d20aa | PASS |

> The real-time calendar from here: voting opens ~24h after the propose block; the 5-day voting period follows; queue arms the 7-day timelock; execute lands around day 13. Each stage will be recorded with its timestamp and hash as it happens. Harness note: the runner crashed AFTER the propose broadcast on PowerShell's read-only automatic variable PID (renamed); the governor event log recovered the record -- incidentally proving ProposalCreated is emitted and readable, which Part 3 needs.

### P2.2 -- Migration: full-balance, partial, and a holder who waits

| step | action | expected | observed | tx | verdict |
|---|---|---|---|---|---|
| P2.2.1 | holder1 migrates the FULL remaining balance (169.0000 B) | old balance to zero, DMN 1:1 on top of what it already held | old=0.0000 B, DMN=169.9500 B; claim gas=147732 (2026-08-28 00:20 UTC) | 0x5b6f828684292b5b567f589050b5835009cb6ba022ca096ca1569e0230c38158 | PASS |
| P2.2.2 | holder2 migrates 25B of 60B (partial) | 35B old kept, 25B DMN exact | old=35.0000 B, DMN=25.0000 B; gas=186720 (2026-08-28 00:20 UTC) | 0x76442a571dbe43dac992183f786e8ffae790e48cc990b569260e3201e058fa81 | PASS |
| P2.2.3 | holder3 waits (models the late migrator) | 40B old untouched, zero DMN | old=40.0000 B, DMN=0.0000 B (2026-08-28 00:20 UTC) | - | PASS |
| P2.2.4 | Collected predecessor tokens sit at the treasury (the Timelock) | treasury old balance == totalMigrated (claimant -> treasury path, #29 design) | treasury old=244.5000 B, totalMigrated=244.5000 B (2026-08-28 00:20 UTC) | - | PASS |

### P2.3 -- Poke model, real conditions: gas measured on both sides

| step | action | expected | observed | tx | verdict |
|---|---|---|---|---|---|
| P2.3.1 | Ordinary volume: holder1 sends 3B + 2B (taxed) | inventory crosses minimumTokensBeforeSwap (0.2000 B) | inventory=0.2062 B, armed=True (2026-08-28 00:21 UTC) | 0xd7cc76fc3ab2b89965bfd9af20d5e3089c6a71f1cff5d5e319e2b67db8e4df0d / 0x57f128688780228bfea41b6c40da9343bb0b3c6959e5ffc40e2874c92fbf33b5 | PASS |
| P2.3.2 | A REAL router sell (0.5B) with the inventory armed | no conversion: inventory only grows by the sell fee (#1) | inventory 0.2062 B -> 0.2262 B, contract BNB=0.0000; sell gas=192623 (2026-08-28 00:22 UTC) | 0x91dc54cb26f298a27362022af8216bf06613a0870835e7c0214333076b6c0df2 | PASS |
| P2.3.3 | The stranger pokes: 1 wei of DMN to the pair | conversion fires, ~one chunk consumed; staking receives BNB; poke gas vs sell gas | inventory 0.2262 B -> 0.0266 B, contract BNB 0.0000 -> 0.0019, staking BNB 0.0000 -> 0.0019; POKE gas=305492 vs SELL gas=192623 (2026-08-28 00:22 UTC) | 0x3a4cdc8244a24600b35a88bf058bd7edc96e09f10ad51ffaec90c33fe629ddd0 | PASS |
| P2.3.4 | Marketing wallet during a REAL conversion on a public chain | untouched: share=1000 means the transfer branch never runs | DMN=0, native=0 (2026-08-28 00:22 UTC) | - | PASS |

### P2.4 -- Per-block budget: two pokes from two senders aimed at one real block

| step | action | expected | observed | tx | verdict |
|---|---|---|---|---|---|
| P2.4.1 | Refill: 10B taxed volume | inventory >= 2 chunks (0.4000 B) | inventory=0.4266 B (2026-08-28 00:23 UTC) | 0xb1eb687a4ae20602afc0c5b7142539c55dd3777ba22b02a1809992e851ee0ee7 / 0x3455d2234473e2e7e5aab147b65f8ae4159012c70e9b0cb34d7fef1dc972b715 | PASS |
| P2.4.2 | Attempt 1: stranger + staker3 poke back to back | same block -> ONE chunk total (budget is per block, not per sender); adjacent blocks -> the budget rolls and up to two chunks convert | blocks 127622592 / 127622596 (same=False), consumed ~2 chunk(s) (0.4000 B) (2026-08-28 00:23 UTC) | 0x80d5609f9003da151e9beb096610f89c2c4427153c49c478938db59b50cab17d / 0x3de61d077e415761cc18449c944c39d74c2f6e1a86497dad9fc444215a659fc8 | PASS |
| P2.4.3 | Attempt 2: stranger + staker3 poke back to back | same block -> ONE chunk total (budget is per block, not per sender); adjacent blocks -> the budget rolls and up to two chunks convert | blocks 127622650 / 127622654 (same=False), consumed ~2 chunk(s) (0.4000 B) (2026-08-28 00:24 UTC) | 0xdbd99d088122ea971778b4a1651164cf83226fcebae2547d191abb1e304deb6c / 0xf8f699079bc97722cd25be9d7b5342b462e7b60650559c72bb7e328407c4cbde | PASS |
| P2.4.4 | Attempt 3: stranger + staker3 poke back to back | same block -> ONE chunk total (budget is per block, not per sender); adjacent blocks -> the budget rolls and up to two chunks convert | blocks 127622705 / 127622708 (same=False), consumed ~2 chunk(s) (0.4000 B) (2026-08-28 00:24 UTC) | 0xa456fcb53853c1a268585a489937fc6985d2cae20ed2919c93275f4546a3f82e / 0x73c79fc5d750f9caf8f908f52ad2418a5f79ed930da96c58fd05fc315dcffd29 | PASS |

> On a public chain block placement belongs to the validators: the harness aims for colocation and records what actually landed. The Level-1 result (budget is per block and sender-independent, proven with forced same-block mining) is the mechanism; here the record shows real-network behaviour.

### P2.5b -- Checkpoint history on real blocks; rewards from real conversions; claim

| step | action | expected | observed | tx | verdict |
|---|---|---|---|---|---|
| P2.5b.1 | Staked events read back from the chain | 3 events, one per staker | count=3, first stake block=127621738 (2026-08-28 00:25 UTC) | 0x5939a3d0f453cdb0a9d27ce438b55f5e79f9a53d7f8dc2df19b809cd63402137 | PASS |
| P2.5b.2 | staker1 voting power at three real points in history | 0 before the stake block, 20B at it, 20B now | at 127621737=0.0000 B, at 127621738=20.0000 B, live=20.0000 B (2026-08-28 00:25 UTC) | - | PASS |
| P2.5b.3 | The aggregate series (the quorum denominator, #12) | 0 before anyone staked; 32.5B live | at 127621737=0.0000 B, live=32.5000 B (2026-08-28 00:25 UTC) | - | PASS |
| P2.5b.4 | Pending rewards, pro-rata by voting power | ratios 4.0x and 1.5x vs staker3 (20:7.5:5); the sum stays within the pool balance | p1=0.0034, p2=0.0012, p3=0.0008 BNB; ratios x1000: 4000 / 1500; pool=0.0055 (2026-08-28 00:25 UTC) | - | PASS |
| P2.5b.5 | staker1 claims | receives the pending amount (minus own gas); pending resets | balance moved 0.0034 BNB (pending was 0.0034); now pending=0.0000; gas=67772 (2026-08-28 00:25 UTC) | 0x5f665eb04b91c2b0d234146f3bf071064809282efe4519c5b24f63847c8b7a98 | PASS |

### P2.6 -- Guardian pause: real arming, real refusal, manual clear; expiry values re-checked

| step | action | expected | observed | tx | verdict |
|---|---|---|---|---|---|
| P2.6.1 | The guardian arms the pause | isPaused=true; the window is the constant 14 days (contract offers no shorter arm) | isPaused=true, window remaining=1209599 s (~14 days), cumulativePauseSeconds=1209600 (2026-08-28 00:26 UTC) | 0x7898a27e36b6e1bd1926c3d566d38bfde07f16b65e7d112d5360a0290a720e9c | PASS |
| P2.6.2 | The migration credit (#36) on a real deadline | effective deadline = immutable base + 14 days | base=1790467694, effective=1791677294, delta=1209600 s (2026-08-28 00:26 UTC) | - | PASS |
| P2.6.3 | An ordinary transfer while paused | refused | reverted with ContractIsPaused (2026-08-28 00:26 UTC) | - | PASS |
| P2.6.4 | 90 real seconds later: still paused; the guardian clears; transfers resume | isPaused true before the clear, false after, pauseUntil zeroed, a real transfer passes | before=true, after=false, pauseUntil=0 (2026-08-28 00:28 UTC) | 0xcd0b8529894ba637f299362d2e8e98c879433e02da0c052fabab680b9d708bf8 / 0xcca20654339f325ed04eb3d6f51c7c26d0dc1624843290f034cc1c6414e00904 | PASS |
| P2.6.5 | The three stored expiry values, re-read | exactly equal and 36 months from phase 1 | 1882483692 / 1882483692 / 1882483692 (2026-08-28 00:28 UTC) | - | PASS |

> Expectation note, reported not corrected: the campaign document asks for the pause 'self-termination on a real clock (use a short pause window)'. The contract has no short window to use: setPaused(true) always arms min(now + 14 days, guardianExpiry). Observing the lapse-with-no-transaction on a real clock therefore requires 14 real days with the token frozen, which would block the rest of the campaign; the lapse mechanism itself was proven at Level 1 (E2, warped clock). Here the record shows: real arming, exact window arithmetic, real refusal, real credit on the migration deadline, and a real manual clear. Whether a 14-day frozen tail run is wanted at campaign end is a human decision.

### P3 -- Monitor groundwork: every observed event class emitted and read back from Chapel

| step | action | expected | observed | tx | verdict |
|---|---|---|---|---|---|
| P3.1 | Read back: ParamsUpdated(string,uint256) on token | expected 1 [phase-2 setStakingRewardShareBps(1000)] | found=1 (2026-08-28 00:29 UTC) | - | PASS |
| P3.2 | Read back: ExcludedFromFeeSet(address,bool) on token | expected 1 [initialize exclusions (at least migration)] | found=0 (2026-08-28 00:29 UTC) | - | DEVIATION |
| P3.3 | Read back: Upgraded(address) on token(proxy) | expected 1 [ERC-1967 implementation set at deploy] | found=1 (2026-08-28 00:29 UTC) | - | PASS |
| P3.4 | Read back: PausedSet(bool) on token | expected 2 [P2.6 arm + clear] | found=2 (2026-08-28 00:29 UTC) | - | PASS |
| P3.5 | Read back: PauseScheduled(uint256) on token | expected 1 [P2.6 window] | found=1 (2026-08-28 00:29 UTC) | - | PASS |
| P3.6 | Read back: FeesUpdated(uint256,uint256,uint256) on token | expected 0 [none yet - fires at governance execute (~day 13)] | found=0 (2026-08-28 00:29 UTC) | - | PASS |
| P3.7 | Read back: ProposalCreated(uint256,address,address,uint256,bytes,string,uint256,uint256,uint256,uint256) on governor | expected -2 [P2.1 propose (signature checked separately below)] | found=0 (2026-08-28 00:29 UTC) | - | PASS |
| P3.8 | Read back: Staked(address,uint256,uint256,uint256,uint256) on staking | expected 3 [the three stakes] | found=3 (2026-08-28 00:29 UTC) | - | PASS |
| P3.9 | Read back: RewardNotified(uint256) on staking | expected 7 [P2.3 poke + P2.4 six chunks] | found=7 (2026-08-28 00:29 UTC) | - | PASS |
| P3.10 | Read back: RewardClaimed(address,uint256) on staking | expected -2 [staker1 claim (name checked below)] | found=1 (2026-08-28 00:29 UTC) | - | PASS |
| P3.11 | The urgent alert query: Transfer -> marketingWallet | ZERO events across the whole campaign - the alert that must never fire | total token Transfers=                                                  .Count; transfers to marketing=0 (2026-08-28 00:29 UTC) | - | PASS |
| P3.12 | getReserves() readable on the pair (pool-drain check data source) | a plain eth_call answers | first reserve token=2022500000000000000000000006 (2026-08-28 00:29 UTC) | - | PASS |

Address book for the monitor (Chapel, chain 97):

```
DaimonV2 (token/proxy):  0x37eEb553de4F6865efC5d8240CFA3B4a465a046f
DaimonStaking:           0x2871977e1978f6DAbE66C617d0627B0eFD54FbA4
DaimonGovernor:          0xB1eA20ef50546a7206E48F160A0fe54833c20eE0
DaimonTimelock/treasury: 0xb5084C65e1ceb2a4DEcb0f391872805110Bd4932
DaimonMigration:         0xBB5A86ad9f337927c271c7698dE8E07dEaF84d42
Pair DMN/WBNB:           0x94bBA28e7E80Fdc6a530bA765Ec966E0dD1CB23C
marketingWallet:         0x000000000000000000000000000000000000A001  (watched BECAUSE it must stay silent)
Mock predecessor:        0xa0de1CB265757Cf8C07b4eDCa4454E95bce33c4F
```
| P3.13 | ProposalCreated re-read with the REAL signature (uint256,address,address,string) | exactly 1 - the day-1 proposal | found=1 (2026-08-28 00:30 UTC) | - | PASS |

> Diagnosis of P3.2, which side is wrong: the EXPECTATION. initialize() and setStakingContract() write isExcludedFromFee silently (src/DaimonV2.sol:389,395,957); only the governance setter emits ExcludedFromFeeSet (:975). Deploy-time exemptions therefore produce NO events -- the monitor cannot reconstruct the initial exemption set from logs and must read the mapping state at startup, then watch the event for CHANGES. Same lesson for P3.7: the governor's ProposalCreated is the compact 4-field signature above, not the OpenZeppelin 10-field one -- the monitor must take event signatures from the deployed ABI, never from assumptions. Both are tuning data the spec asked Part 3 to produce; no code is wrong.

---

## Day 1 status (2026-08-28)

Deployed, verified 34/34, launch order rehearsed end to end, the slow
clock started. The global invariant -- the marketing wallet has received
nothing, ever -- has been asserted programmatically **43 times** so far
(once after every state-changing harness transaction), plus the event-level
sweep in P3.11: zero Transfer events into the wallet across the whole
campaign. Heartbeat, monitor-style: "marketing wallet: 0 movements ever."

Real-time calendar ahead (proposal 0, proposed 2026-08-28 00:18 UTC):

| stage | due | status |
|---|---|---|
| voting opens (1-day delay) | ~2026-08-29 00:18 UTC | waiting |
| vote (staker1, staker2, staker3) | day 2-6 | waiting |
| voting closes (5-day period) | ~2026-09-03 | waiting |
| queue -> 7-day timelock starts | day 7 | waiting |
| execute setFees(10,10,20) | ~day 13-14 | waiting |
| FeesUpdated event check (P3 follow-up) | at execute | waiting |

Still open beyond the calendar: the pool-depth observation (P2.3/P2.4
conversions moved a testnet-sized pool heavily -- on mainnet the pool
dwarfs the chunk size; recorded as an operational note, not a defect),
the closing gates (forge clean && forge test, src/ diff vs audit-final),
and the operator reminder to delete the shared password file when the
campaign closes.
