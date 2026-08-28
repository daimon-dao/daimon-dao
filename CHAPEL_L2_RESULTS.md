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
