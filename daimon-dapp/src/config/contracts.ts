/*
 * The ONLY place for chain + addresses (DAPP_SPEC.md §1). The chain is picked
 * at build time by NEXT_PUBLIC_CHAIN_ID: 56 = BSC mainnet, anything else (or
 * unset) = BSC testnet 97 (see README).
 */
import { bsc, bscTestnet } from "wagmi/chains";
import { parseAbi } from "viem";

export type ContractAddresses = {
  daimonV2: `0x${string}`;
  daimonStaking: `0x${string}`;
  daimonGovernor: `0x${string}`;
  daimonTimelock: `0x${string}`;
  daimonMigration: `0x${string}`;
  oldDaimon: `0x${string}`;
  pancakePair: `0x${string}`;
  wbnb: `0x${string}`;
};

const BSC_TESTNET: ContractAddresses = {
  daimonV2: "0xf9a4d8b6ae6e37f198443e9855e3788119c94202",
  daimonStaking: "0x2f2135885617cd226214cf8fd3b945fddaea3606",
  daimonGovernor: "0xe2445551f1d6c487e6cfb48f8621ccfb4d919c52",
  daimonTimelock: "0x6a98fd0c0306672e4abfbe90fc303726022427f5",
  daimonMigration: "0x4c6f45b0148534296d8f9660eba5cc3598855bb2",
  oldDaimon: "0xf5de50ae742df53b5b6a6bf5189f64a9d16157cc",
  // letto on-chain da daimonV2.uniswapV2Pair()
  pancakePair: "0x9b44521E5643dD0E393C584E770598deC644a8B5",
  wbnb: "0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd",
};

// BSC mainnet (chainId 56), deployed and verified on 2026-09-29. Each address
// was checked read-only on chain against docs/launch-56/two-phase-56.json before
// being written here: the cross-links (Staking.daimonToken, Governor.staking /
// .timelock, Migration.oldDaimon / .newDaimon / .treasury / .governance) and
// the pair (DaimonV2.uniswapV2Pair(), token0 = DMN, token1 = WBNB).
const BSC_MAINNET: ContractAddresses = {
  // ERC1967 proxy: the address holders use (implementation 0xA7bC…941c)
  daimonV2: "0x160864F9945C52063A7c9f5dcd57C0C89eacbE6a",
  daimonStaking: "0xBb596e7308D6C5AED55cEC597D372840Cbe575b1",
  daimonGovernor: "0x1397a7d25595B718BE6FEEDd42ed5E60F66E16De",
  daimonTimelock: "0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891",
  daimonMigration: "0x76368b60514b145617385847aCFF7b7EA9764725",
  // The real, pre-existing DMX token (the testnet uses a mock)
  oldDaimon: "0x36EbA94407B53c631eE822C219e94580fadd67c7",
  pancakePair: "0x40A97Ae210a44057603186B4BE92BAe719342AFA",
  wbnb: "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c",
};

const CHAIN_ID = Number(process.env.NEXT_PUBLIC_CHAIN_ID ?? 97);

export const ACTIVE_CHAIN = CHAIN_ID === 56 ? bsc : bscTestnet;

export const ADDRESSES: ContractAddresses =
  CHAIN_ID === 56 ? BSC_MAINNET : BSC_TESTNET;

export const IS_TESTNET = ACTIVE_CHAIN.id === 97;

// DaimonV2's immutable supply bounds (INITIAL_SUPPLY, MIN_SUPPLY: 1,000B and
// 21B, checked on chain), for the texts that quote them outside the dashboard,
// which reads them live. Formatted per language like every other number.
export const INITIAL_SUPPLY = 1_000_000_000_000n * 10n ** 18n;
export const SUPPLY_FLOOR = 21_000_000_000n * 10n ** 18n;

export const EXPLORER =
  ACTIVE_CHAIN.id === 56
    ? "https://bscscan.com"
    : "https://testnet.bscscan.com";

/*
 * Public RPC endpoints only: no API key, no private key, no secret of any kind
 * lives in this dApp (everything here ships to the browser). wagmi walks each
 * list in order with viem's fallback transport, so one endpoint down or
 * rate-limiting does not blank the dashboard.
 */
export const RPC_URLS: Record<56 | 97, readonly string[]> = {
  56: [
    "https://bsc-dataseed.binance.org",
    "https://bsc-rpc.publicnode.com",
    "https://bsc-dataseed1.defibit.io",
    "https://bsc-dataseed1.ninicoin.io",
  ],
  97: [
    "https://data-seed-prebsc-1-s1.binance.org:8545",
    "https://bsc-testnet-rpc.publicnode.com",
  ],
};

/*
 * What opens the migration: claim() reverts with AmountMismatch until the
 * Migration's treasury, where the old tokens land, is fee-exempt on the old
 * token. On mainnet the treasury is the Timelock and the exemption is launch
 * step 11b (DMX excludeFromFee(Timelock)). The real DMX
 * and the testnet mock name the getter differently, and only the real DMX has
 * a per-transaction cap (docs/LAUNCH_DAY.md, "The real DMX vs the mock").
 */
export const OLD_DAIMON_FEE_EXEMPT = IS_TESTNET
  ? {
      abi: parseAbi(["function excludedFromFee(address) view returns (bool)"]),
      functionName: "excludedFromFee",
    }
  : {
      abi: parseAbi(["function isExcludedFromFee(address) view returns (bool)"]),
      functionName: "isExcludedFromFee",
    };
export const OLD_DAIMON_MAX_TX_ABI = parseAbi(["function _maxTxAmount() view returns (uint256)"]);
export const OLD_DAIMON_HAS_MAX_TX = !IS_TESTNET;

// Public URL of the production dApp: the WalletConnect metadata points here.
export const APP_URL = "https://app.daimon.money";

export function explorerAddress(addr: string): string {
  return `${EXPLORER}/address/${addr}`;
}

export function explorerTx(hash: string): string {
  return `${EXPLORER}/tx/${hash}`;
}
