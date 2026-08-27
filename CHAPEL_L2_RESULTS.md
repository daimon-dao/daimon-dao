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
