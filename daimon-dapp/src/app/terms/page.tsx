import type { Metadata } from "next";
import { TermsDocument } from "@/components/TermsDocument";

export const metadata: Metadata = { title: "Terms of use — Daimon DAO" };

export default function TermsEn() {
  return <TermsDocument lang="en" />;
}
