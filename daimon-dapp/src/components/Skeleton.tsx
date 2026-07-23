/*
 * Pulsing loading placeholder: replaces the static "…" where the value is the
 * primary content. On a slow RPC (the norm at peak times, not the exception)
 * the user must SEE that something is coming.
 */
export function Skeleton({ className = "" }: { className?: string }) {
  return (
    <span
      className={`inline-block animate-pulse rounded bg-bordi/70 align-middle ${className}`}
      aria-hidden
    />
  );
}
