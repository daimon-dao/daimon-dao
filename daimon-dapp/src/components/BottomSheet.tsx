"use client";

import { useEffect, useRef, useState, type ReactNode } from "react";
import { createPortal } from "react-dom";

/*
 * Sotto sm i menu ancorati "galleggiano" e hanno tap target piccoli: lo
 * standard mobile delle dApp e' il bottom sheet. Questo componente e'
 * client-only e viene montato SOLO dopo un'interazione (open=true), quindi
 * non esiste nell'HTML server: zero superficie per hydration mismatch.
 */

/** true sotto il breakpoint sm (639px). Parte false: valutato solo dopo mount. */
export function useIsMobile(): boolean {
  const [mobile, setMobile] = useState(false);
  useEffect(() => {
    const q = window.matchMedia("(max-width: 639px)");
    const update = () => setMobile(q.matches);
    update();
    // 'resize' come cintura oltre al change della MQL: la rotazione di un
    // telefono grande attraversa i 640px e lo stato deve seguire sempre.
    q.addEventListener("change", update);
    window.addEventListener("resize", update);
    return () => {
      q.removeEventListener("change", update);
      window.removeEventListener("resize", update);
    };
  }, []);
  return mobile;
}

export function BottomSheet({
  open,
  onClose,
  label,
  children,
}: {
  open: boolean;
  onClose: () => void;
  label: string;
  children: ReactNode;
}) {
  const panelRef = useRef<HTMLDivElement>(null);
  const prevFocus = useRef<HTMLElement | null>(null);
  const startY = useRef<number | null>(null);
  const dragY = useRef(0);

  useEffect(() => {
    if (!open) return;
    prevFocus.current = document.activeElement as HTMLElement | null;
  }, [open]);

  // Scroll lock: il contenuto sotto non deve scorrere mentre il sheet e' aperto.
  useEffect(() => {
    if (!open) return;
    const prev = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    return () => {
      document.body.style.overflow = prev;
    };
  }, [open]);

  // Focus nel pannello, trap del Tab, Escape per chiudere, focus restituito.
  useEffect(() => {
    if (!open) return;
    panelRef.current?.focus();
    function onKey(e: KeyboardEvent) {
      if (e.key === "Escape") {
        e.stopPropagation();
        onClose();
        return;
      }
      if (e.key !== "Tab") return;
      const els = panelRef.current?.querySelectorAll<HTMLElement>(
        'a[href], button:not([disabled]), [tabindex]:not([tabindex="-1"])'
      );
      if (!els || els.length === 0) return;
      const first = els[0];
      const last = els[els.length - 1];
      if (e.shiftKey && document.activeElement === first) {
        e.preventDefault();
        last.focus();
      } else if (!e.shiftKey && document.activeElement === last) {
        e.preventDefault();
        first.focus();
      }
    }
    document.addEventListener("keydown", onKey);
    return () => {
      document.removeEventListener("keydown", onKey);
      prevFocus.current?.focus?.();
    };
  }, [open, onClose]);

  // Swipe verso il basso: il pannello segue il dito; oltre 80px chiude,
  // altrimenti torna su. I contenuti sono corti (menu), niente conflitto
  // con lo scroll interno.
  function onTouchStart(e: React.TouchEvent) {
    startY.current = e.touches[0].clientY;
  }
  function onTouchMove(e: React.TouchEvent) {
    if (startY.current === null) return;
    dragY.current = Math.max(0, e.touches[0].clientY - startY.current);
    if (panelRef.current) {
      panelRef.current.style.transform = `translateY(${dragY.current}px)`;
      panelRef.current.style.transition = "none";
    }
  }
  function onTouchEnd() {
    const dragged = dragY.current;
    startY.current = null;
    dragY.current = 0;
    if (panelRef.current) {
      panelRef.current.style.transform = "";
      panelRef.current.style.transition = "";
    }
    if (dragged > 80) onClose();
  }

  if (!open) return null;

  return createPortal(
    <div className="fixed inset-0 z-50 sm:hidden">
      <div
        className="absolute inset-0 animate-[sheet-fade_200ms_ease-out] bg-black/60 motion-reduce:animate-none"
        onClick={onClose}
        aria-hidden
      />
      <div
        ref={panelRef}
        role="dialog"
        aria-modal="true"
        aria-label={label}
        tabIndex={-1}
        className="absolute inset-x-0 bottom-0 animate-[sheet-up_200ms_ease-out] rounded-t-2xl border-x border-t border-bordi bg-card pb-[env(safe-area-inset-bottom)] shadow-2xl outline-none transition-transform duration-200 motion-reduce:animate-none"
        onTouchStart={onTouchStart}
        onTouchMove={onTouchMove}
        onTouchEnd={onTouchEnd}
      >
        <div className="mx-auto mt-2.5 h-1 w-10 rounded-full bg-bordi" aria-hidden />
        <div className="px-3 pb-3 pt-2">{children}</div>
      </div>
    </div>,
    document.body
  );
}
