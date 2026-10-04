import { Inter } from "next/font/google";

// Vercel target (see font.ts): Inter from Google Fonts, self-hosted by the build.
const inter = Inter({ subsets: ["latin"] });

export const fontClassName = inter.className;
