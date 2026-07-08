"use client";

import { explorerTx } from "@/config/contracts";
import type { TxPhase } from "@/hooks/useTx";

export function TxStatus({
  phase,
  hash,
  errorMessage,
}: {
  phase: TxPhase;
  hash?: `0x${string}`;
  errorMessage?: string | null;
}) {
  if (phase === "idle") return null;

  return (
    <div className="mt-3 text-sm rounded-lg border border-bordi bg-bg/40 px-3 py-2">
      {phase === "signing" && (
        <span className="text-secondario">✍️ In attesa di firma nel wallet…</span>
      )}
      {phase === "pending" && (
        <span className="text-oro">
          ⏳ Transazione inviata, in attesa di conferma…{" "}
          {hash && <TxLink hash={hash} />}
        </span>
      )}
      {phase === "success" && (
        <span className="text-verde">
          ✔ Transazione confermata. {hash && <TxLink hash={hash} />}
        </span>
      )}
      {phase === "error" && (
        <span className="text-rosso">
          ✕ {errorMessage ?? "Transazione fallita."} {hash && <TxLink hash={hash} />}
        </span>
      )}
    </div>
  );
}

function TxLink({ hash }: { hash: `0x${string}` }) {
  return (
    <a
      href={explorerTx(hash)}
      target="_blank"
      rel="noreferrer"
      className="underline underline-offset-2 hover:text-orochiaro"
    >
      Vedi su BscScan ↗
    </a>
  );
}
