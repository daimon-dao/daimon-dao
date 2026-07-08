/*
 * Placeholder del logo (DAPP_SPEC.md §2): cerchio con bordo oro
 * tratteggiato e testo "LOGO". Quando arriva il file definitivo:
 * metterlo in /public/logo.svg e sostituire il contenuto qui sotto con
 * <img src="/logo.svg" alt="Daimon" className="h-9 w-9" />.
 */
export function Logo({ size = 36 }: { size?: number }) {
  return (
    <span
      className="flex items-center justify-center rounded-full border-2 border-dashed border-oro text-oro select-none shrink-0"
      style={{ width: size, height: size, fontSize: size * 0.24 }}
      aria-label="Logo Daimon (segnaposto)"
    >
      LOGO
    </span>
  );
}
