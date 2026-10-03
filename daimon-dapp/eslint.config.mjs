// ESLint flat config (ESLint 9) with Next's rule sets. `next lint` is
// deprecated in Next 15.5 and gone in 16: `npm run lint` runs ESLint directly.
import { FlatCompat } from "@eslint/eslintrc";

const compat = new FlatCompat({ baseDirectory: import.meta.dirname });

const config = [
  ...compat.extends("next/core-web-vitals", "next/typescript"),
  {
    ignores: [".next/**", "node_modules/**", "next-env.d.ts"],
  },
];

export default config;
