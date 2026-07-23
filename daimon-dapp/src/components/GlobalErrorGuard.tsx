"use client";

import { useEffect, useState } from "react";
import { useI18n } from "@/components/LocaleProvider";

/*
 * Final safety net against unhandled rejections that escape the managed flows
 * — in particular the async events from wallet libraries that live OUTSIDE our
 * promises (e.g. @walletconnect/utils' "Proposal expired" when the QR expires
 * after minutes).
 *
 * Policy: NEVER Next's red overlay.
 *  - known benign events (expired QR, rejected signature): console.info, with
 *    a discreet toast only where useful to the user;
 *  - everything else: console.error with the full details + a generic toast.
 *    The overlay is suppressed but nothing is hidden from debugging.
 */
export function GlobalErrorGuard() {
  const { t } = useI18n();
  const [toast, setToast] = useState<string | null>(null);

  useEffect(() => {
    let timer: number | undefined;
    function show(msg: string) {
      setToast(msg);
      window.clearTimeout(timer);
      timer = window.setTimeout(() => setToast(null), 6000);
    }

    // Known benign events from the wallet libraries: they must be intercepted
    // BEFORE Next's dev overlay (bubble phase) shows them. Capture phase +
    // stopImmediatePropagation prevents other listeners from reacting.
    function isBenign(reason: { code?: number; message?: string } | null, msg: string) {
      return (
        /proposal expired|session request expired/i.test(msg) ||
        reason?.code === 4001 ||
        /user rejected|user denied|connection request reset|request expired/i.test(msg)
      );
    }

    function onRejection(e: PromiseRejectionEvent) {
      const reason = e.reason as { code?: number; message?: string } | null;
      const msg = reason?.message ?? String(e.reason ?? "");

      if (isBenign(reason, msg)) {
        e.preventDefault();
        e.stopImmediatePropagation();
        if (/proposal expired|session request expired|request expired/i.test(msg)) {
          console.info("[wallet] WalletConnect request expired (QR not used in time)");
          show(t("guard.connectionExpired"));
        } else {
          console.info("[wallet] request rejected/canceled by the user");
          // no toast: the user decided it
        }
        return;
      }

      // Unexpected error: we suppress the overlay anyway but log everything
      // and warn with a generic toast (never a red page).
      e.preventDefault();
      console.error("[global] unhandled rejection:", e.reason);
      show(t("guard.unexpected"));
    }

    // capture: true -> our handler precedes the bubble-phase ones (Next).
    window.addEventListener("unhandledrejection", onRejection, { capture: true });
    return () => {
      window.removeEventListener("unhandledrejection", onRejection, { capture: true });
      window.clearTimeout(timer);
    };
  }, [t]);

  if (!toast) return null;
  return (
    <div
      role="status"
      className="fixed bottom-4 left-1/2 z-50 -translate-x-1/2 rounded-lg border border-bordi bg-card px-4 py-2.5 text-sm text-testo shadow-xl"
    >
      {toast}
    </div>
  );
}
