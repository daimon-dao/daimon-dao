/*
 * Minimal ABI of the PancakeSwap V2 pair (read-only reserves/token0).
 * It is not a monorepo contract, so there is no Foundry artifact to generate
 * it from: it is the standard UniswapV2Pair interface.
 */
export const pancakePairAbi = [
  {
    type: "function",
    name: "getReserves",
    inputs: [],
    outputs: [
      { name: "reserve0", type: "uint112" },
      { name: "reserve1", type: "uint112" },
      { name: "blockTimestampLast", type: "uint32" },
    ],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "token0",
    inputs: [],
    outputs: [{ name: "", type: "address" }],
    stateMutability: "view",
  },
] as const;
