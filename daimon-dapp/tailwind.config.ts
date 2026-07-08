import type { Config } from "tailwindcss";

/*
 * Colori brand da DAPP_SPEC.md §2, mappati su CSS variables (definite in
 * globals.css) cosi' il toggle dark/light cambia solo le variabili.
 */
const config: Config = {
  content: ["./src/**/*.{ts,tsx}"],
  darkMode: "class",
  theme: {
    extend: {
      colors: {
        bg: "var(--bg)",
        card: "var(--card)",
        bordi: "var(--border)",
        oro: "#c9a227",
        orochiaro: "var(--title)",
        secondario: "var(--muted)",
        testo: "var(--text)",
        verde: "#5dcaa5",
        rosso: "#e24b4a",
      },
      fontFamily: {
        sans: ["Inter", "system-ui", "-apple-system", "Segoe UI", "sans-serif"],
      },
    },
  },
  plugins: [],
};
export default config;
