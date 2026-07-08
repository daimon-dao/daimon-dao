/*
 * UNICO punto di configurazione chain + indirizzi (DAPP_SPEC.md §1).
 * Per passare a mainnet: compilare BSC_MAINNET qui sotto e impostare
 * NEXT_PUBLIC_CHAIN_ID=56 (vedi README).
 */
import { bsc, bscTestnet } from "wagmi/chains";

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

// Da compilare al deploy mainnet.
const BSC_MAINNET: ContractAddresses = {
  daimonV2: "0x0000000000000000000000000000000000000000",
  daimonStaking: "0x0000000000000000000000000000000000000000",
  daimonGovernor: "0x0000000000000000000000000000000000000000",
  daimonTimelock: "0x0000000000000000000000000000000000000000",
  daimonMigration: "0x0000000000000000000000000000000000000000",
  oldDaimon: "0x0000000000000000000000000000000000000000",
  pancakePair: "0x0000000000000000000000000000000000000000",
  wbnb: "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c",
};

const CHAIN_ID = Number(process.env.NEXT_PUBLIC_CHAIN_ID ?? 97);

export const ACTIVE_CHAIN = CHAIN_ID === 56 ? bsc : bscTestnet;

export const ADDRESSES: ContractAddresses =
  CHAIN_ID === 56 ? BSC_MAINNET : BSC_TESTNET;

export const IS_TESTNET = ACTIVE_CHAIN.id === 97;

export const EXPLORER =
  ACTIVE_CHAIN.id === 56
    ? "https://bscscan.com"
    : "https://testnet.bscscan.com";

export const RPC_URL =
  ACTIVE_CHAIN.id === 56
    ? "https://bsc-dataseed.binance.org"
    : "https://data-seed-prebsc-1-s1.binance.org:8545";

export function explorerAddress(addr: string): string {
  return `${EXPLORER}/address/${addr}`;
}

export function explorerTx(hash: string): string {
  return `${EXPLORER}/tx/${hash}`;
}
