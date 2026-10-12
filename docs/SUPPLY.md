# DMN supply: total and circulating

How to compute the total and the circulating supply of DMN from BNB Smart
Chain. Written for the token data sites (CoinGecko, CoinMarketCap) and for
anyone who wants to check their figures. Every number here is read from the
chain at a stated block; nothing is self-reported.

## The addresses

| | Address |
|---|---|
| DMN token (`DaimonV2`, UUPS proxy) | [`0x160864F9945C52063A7c9f5dcd57C0C89eacbE6a`](https://bscscan.com/token/0x160864F9945C52063A7c9f5dcd57C0C89eacbE6a) |
| Migration (`DaimonMigration`), DMX → DMN 1:1 | [`0x76368b60514b145617385847aCFF7b7EA9764725`](https://bscscan.com/address/0x76368b60514b145617385847aCFF7b7EA9764725) |
| Dead address | [`0x000000000000000000000000000000000000dEaD`](https://bscscan.com/address/0x000000000000000000000000000000000000dEaD) |
| Timelock (`DaimonTimelock`), the treasury | [`0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891`](https://bscscan.com/address/0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891) |
| Staking (`DaimonStaking`) | [`0xBb596e7308D6C5AED55cEC597D372840Cbe575b1`](https://bscscan.com/address/0xBb596e7308D6C5AED55cEC597D372840Cbe575b1) |
| PancakeSwap v2 pair DMN/WBNB | [`0x40A97Ae210a44057603186B4BE92BAe719342AFA`](https://bscscan.com/address/0x40A97Ae210a44057603186B4BE92BAe719342AFA) |

DMN has 18 decimals. All on-chain values below are in wei (10^-18 DMN).

## Definitions

**Max supply: 1,000,000,000,000 DMN.** The whole supply was minted once, at
deployment, to the Migration contract (`INITIAL_SUPPLY`). The contract has
no mint function: the supply can only go down, through the burn described
next, and never below the floor `MIN_SUPPLY` = 21,000,000,000 DMN.

**Total supply = `totalSupply()`.** The token's own counter, already net of
burns: `burnDeadBalanceToFloor()` removes DMN sent to the dead address from
`totalSupply()` (down to the floor), so burned DMN never need to be
subtracted twice.

**Circulating supply = `totalSupply()` minus the balances that nobody can
move without a vote, or ever:**

| Subtracted | Why |
|---|---|
| `balanceOf(Migration)` | DMN reserved one-for-one for DMX holders who have not migrated yet. They leave the contract only through `claim()`, which hands them to a holder (and so into circulation), or, once the window has closed, through the sweep to the Timelock (below). |
| `balanceOf(dead address)` | Unrecoverable. Between a buyback and the next `burnDeadBalanceToFloor()` call they still appear in `totalSupply()`; this term removes them. |
| `balanceOf(Timelock)` | The DAO treasury. Moves only by a passed Governor vote followed by the hard-coded seven-day delay. |

Not subtracted, on purpose:

- **Staked DMN** (`balanceOf(Staking)`): they belong to the individual
  holders who staked them, locked for a period each holder chose (30 to
  365 days) and withdrawable at its end; they are public holdings, not
  team or treasury holdings.
- **Pool DMN** (`balanceOf(pair)`): anyone can buy them at the market
  price at any moment; the pool is the market.
- **The token contract's own balance**: fees collected and waiting for the
  contract's automatic swap, which sells them on the market; small and
  transient.

**After the migration deadline, 2026-12-28 01:08:44 UTC** (the on-chain
`effectiveMigrationDeadline()`, 1798420124), the unclaimed DMN are swept
from the Migration contract to the Timelock by `sweepUnclaimed()`; the
formula already excludes them there, so the circulating figure does not
jump on the sweep.

## Recompute it yourself

One command, with [Foundry](https://getfoundry.sh/)'s `cast` and `awk`.
Paste it into a shell:

```bash
RPC=${RPC:-https://bsc.drpc.org}
DMN=0x160864F9945C52063A7c9f5dcd57C0C89eacbE6a
B=${B:-$(cast block-number --rpc-url "$RPC")}
rd() { local v; v=$(cast call "$DMN" "$@" --rpc-url "$RPC" --block "$B") || exit 1; cast from-wei "${v%% *}"; }
TS=$(rd 'totalSupply()(uint256)')
MIG=$(rd 'balanceOf(address)(uint256)' 0x76368b60514b145617385847aCFF7b7EA9764725)
DEAD=$(rd 'balanceOf(address)(uint256)' 0x000000000000000000000000000000000000dEaD)
TL=$(rd 'balanceOf(address)(uint256)' 0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891)
echo "block $B  timestamp $(cast block "$B" --rpc-url "$RPC" --field timestamp)"
echo "total        $TS"; echo "migration    $MIG"; echo "dead         $DEAD"; echo "timelock     $TL"
awk -v t="$TS" -v m="$MIG" -v d="$DEAD" -v l="$TL" 'BEGIN { printf "circulating  %.2f\n", t - m - d - l }'
```

- With no `B` it reads the latest block. `B=127249896` (or any block)
  reproduces a past reading; a block older than a few minutes needs an RPC
  that serves historical state (the default, `bsc.drpc.org`, does;
  `bsc-rpc.publicnode.com` answers only for recent blocks).
- The four `cast from-wei` lines are exact to the wei. The last line is a
  double-precision subtraction, exact to well under 0.01 DMN at this
  magnitude; for the exact circulating wei, subtract the raw integers.

## Values read on 2026-10-12

Block **127,249,896**, timestamp 1791825673 = **2026-10-12 17:21:13 UTC**,
read through `bsc-rpc.publicnode.com` and reproduced through
`bsc.drpc.org` with the command above.

| | wei | DMN |
|---|---|---|
| `totalSupply()` | 1000000000000000000000000000000 | 1,000,000,000,000 |
| `balanceOf(Migration)` | 658960521545839338559781021749 | 658,960,521,545.839338559781021749 |
| `balanceOf(dead address)` | 0 | 0 |
| `balanceOf(Timelock)` | 0 | 0 |
| **Circulating** | **341039478454160661440218978251** | **341,039,478,454.160661440218978251** |

So, at that block:

- **Total supply: 1,000,000,000,000 DMN** (no burn has happened yet).
- **Circulating supply: 341,039,478,454.16 DMN**, 34.10 % of the total.
- **Max supply: 1,000,000,000,000 DMN.**

For reference, inside the circulating figure at the same block:
`balanceOf(Staking)` 255,256,100,649.81 DMN (25.53 % of the total),
`balanceOf(pair)` 4,872,085,683.64 DMN, the token contract's own balance
342,384,457.44 DMN.

The migration balance falls with every `claim()` and the circulating figure
rises by the same amount; both are snapshots. The total supply is not a
snapshot: it changes only when `burnDeadBalanceToFloor()` burns.

## How this maps to the listing forms

- **CoinGecko** (new coin listing form): Max Supply, Total Supply and
  Circulating Supply as the amounts above; the dead address under *Burned
  Wallet*; the Migration contract and the Timelock under *Vested/Locked
  Wallet*; no supply API (the API fields are optional; the project does
  not run one, the chain is the source).
- **CoinMarketCap** (*Add cryptoasset* form): Circulating, Total and Max
  Supply as exact unit counts (341039478454, 1000000000000,
  1000000000000); *API endpoint* fields `NA`; the three excluded addresses
  listed in the Annex A sheet as reserve addresses, with this document as
  the reference.
