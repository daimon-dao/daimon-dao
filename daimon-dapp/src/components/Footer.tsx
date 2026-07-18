import { ADDRESSES, explorerAddress, IS_TESTNET } from "@/config/contracts";

const LINKS: Array<[string, string]> = [
  ["Token DMN", ADDRESSES.daimonV2],
  ["Staking", ADDRESSES.daimonStaking],
  ["Governor", ADDRESSES.daimonGovernor],
  ["Timelock", ADDRESSES.daimonTimelock],
  ["Migrazione", ADDRESSES.daimonMigration],
];

export function Footer() {
  return (
    <footer className="mt-16 border-t border-bordi py-8">
      <div className="mx-auto max-w-6xl px-4">
        <p className="mb-3 text-xs uppercase tracking-widest text-secondario">
          Contratti verificati su BscScan{IS_TESTNET ? " (testnet)" : ""}
        </p>
        <div className="flex flex-wrap gap-x-6 gap-y-2 text-sm">
          {LINKS.map(([label, addr]) => (
            <a
              key={label}
              href={explorerAddress(addr)}
              target="_blank"
              rel="noreferrer"
              className="text-secondario underline-offset-2 hover:text-oro hover:underline"
            >
              {label} ↗
            </a>
          ))}
          {/* Link discreto alla pool ufficiale: solo su mainnet (su testnet
              PancakeSwap non ha una UI di swap). */}
          {!IS_TESTNET && (
            <a
              href={`https://pancakeswap.finance/swap?outputCurrency=${ADDRESSES.daimonV2}`}
              target="_blank"
              rel="noopener noreferrer"
              className="text-oro underline-offset-2 hover:underline"
            >
              Compra DMN su PancakeSwap ↗
            </a>
          )}
        </div>
        <p className="mt-6 text-xs text-secondario">
          Daimon DAO — nessun owner, nessun mint, floor di supply a 21B. Verifica tutto on-chain.
        </p>
      </div>
    </footer>
  );
}
