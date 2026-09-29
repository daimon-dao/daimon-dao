import type { Metadata } from "next";
import { TermsDocument } from "@/components/TermsDocument";

export const metadata: Metadata = { title: "Condizioni d'uso — Daimon DAO" };

export default function TermsIt() {
  return <TermsDocument lang="it" />;
}
