"use client";

import { explorerTx } from "@/config/contracts";
import type { TxPhase } from "@/hooks/useTx";
import { useI18n } from "@/components/LocaleProvider";

export function TxStatus({
  phase,
  hash,
  errorMessage,
  notice,
}: {
  phase: TxPhase;
  hash?: `0x${string}`;
  errorMessage?: string | null;
  notice?: string | null;
}) {
  const { t } = useI18n();

  // Avviso neutro (es. firma annullata dall'utente): non e' un errore.
  if (phase === "idle" && notice) {
    return (
      <div className="mt-3 rounded-lg border border-bordi bg-bg/40 px-3 py-2 text-sm text-secondario">
        ℹ {notice}
      </div>
    );
  }
  if (phase === "idle") return null;

  return (
    <div className="mt-3 text-sm rounded-lg border border-bordi bg-bg/40 px-3 py-2">
      {phase === "signing" && (
        <span className="text-secondario">{t("tx.signing")}</span>
      )}
      {phase === "pending" && (
        <span className="text-oro">
          {t("tx.pending")} {hash && <TxLink hash={hash} />}
        </span>
      )}
      {phase === "success" && (
        <span className="text-verde">
          {t("tx.confirmed")} {hash && <TxLink hash={hash} />}
        </span>
      )}
      {phase === "error" && (
        <span className="text-rosso">
          ✕ {errorMessage ?? t("tx.failed")} {hash && <TxLink hash={hash} />}
        </span>
      )}
    </div>
  );
}

function TxLink({ hash }: { hash: `0x${string}` }) {
  const { t } = useI18n();
  return (
    <a
      href={explorerTx(hash)}
      target="_blank"
      rel="noreferrer"
      className="underline underline-offset-2 hover:text-orochiaro"
    >
      {t("tx.viewOnBscscan")}
    </a>
  );
}
