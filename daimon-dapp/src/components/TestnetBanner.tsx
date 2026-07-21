import { IS_TESTNET } from "@/config/contracts";

// Striscia informativa fissa in cima: chi arriva sullo staging deve capire
// al primo sguardo che non e' il prodotto lanciato. Sparisce da sola su
// mainnet (NEXT_PUBLIC_CHAIN_ID=56), come il noindex nel layout.
export function TestnetBanner() {
  if (!IS_TESTNET) return null;
  return (
    <div className="border-b border-oro/40 bg-oro/15 px-4 py-1.5 text-center text-xs font-semibold uppercase tracking-widest text-oro">
      Ambiente di test — BSC Testnet · token e dati senza valore reale
    </div>
  );
}
