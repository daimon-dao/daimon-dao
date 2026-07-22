/*
 * Placeholder di caricamento pulsante: sostituisce i "…" statici dove il
 * valore e' il contenuto primario. Su RPC lento (la norma nei momenti di
 * picco, non l'eccezione) l'utente deve VEDERE che qualcosa sta arrivando.
 */
export function Skeleton({ className = "" }: { className?: string }) {
  return (
    <span
      className={`inline-block animate-pulse rounded bg-bordi/70 align-middle ${className}`}
      aria-hidden
    />
  );
}
