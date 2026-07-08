/*
 * ABI minimale della pair PancakeSwap V2 (solo lettura reserve/token0).
 * Non e' un contratto del monorepo, quindi non esiste un artifact Foundry
 * da cui generarlo: e' l'interfaccia standard UniswapV2Pair.
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
