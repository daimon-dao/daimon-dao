/*
 * Genera gli ABI TypeScript dagli artifact Foundry del monorepo (../out).
 * Da rilanciare dopo ogni `forge build` che cambia le interfacce:
 *   npm run abis
 */
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = dirname(fileURLToPath(import.meta.url));
const outDir = join(root, "..", "..", "out");
const abiDir = join(root, "..", "src", "config", "abis");

const artifacts = {
  daimonV2: "DaimonV2.sol/DaimonV2.json",
  daimonStaking: "DaimonStaking.sol/DaimonStaking.json",
  daimonGovernor: "DaimonGovernor.sol/DaimonGovernor.json",
  daimonTimelock: "DaimonTimelock.sol/DaimonTimelock.json",
  daimonMigration: "DaimonMigration.sol/DaimonMigration.json",
  mockOldDaimon: "MockOldDaimon.sol/MockOldDaimon.json",
};

mkdirSync(abiDir, { recursive: true });

for (const [name, rel] of Object.entries(artifacts)) {
  const artifact = JSON.parse(readFileSync(join(outDir, rel), "utf8"));
  const body =
    `// GENERATO da scripts/generate-abis.mjs — non modificare a mano.\n` +
    `// Fonte: out/${rel}\n` +
    `export const ${name}Abi = ${JSON.stringify(artifact.abi, null, 2)} as const;\n`;
  writeFileSync(join(abiDir, `${name}.ts`), body);
  console.log(`OK ${name} (${artifact.abi.length} voci)`);
}
