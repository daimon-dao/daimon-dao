# Audit brief — Daimon DAO

Documento di orientamento per l'auditor. Lo **scope congelato** è il tag
**[`audit-scope-v1`](https://github.com/daimon-dao/daimon-dao/releases/tag/audit-scope-v1)**
(tag annotato `980fd99` → commit `bd6d544`). Fai il checkout di quel tag: è
lo stato definitivo dei contratti.

```sh
git fetch --tags
git checkout audit-scope-v1
forge build && forge test
```

## Scope (in audit)

I cinque contratti in `src/`:

| Contratto | Descrizione |
|---|---|
| `DaimonV2.sol` | Token BEP-20 reflection (RFI), fee autonome + buyback&burn, floor 21B, UUPS upgradeable, AccessControl |
| `DaimonStaking.sol` | Staking vote-escrow, voting power con checkpoint (ricerca binaria), reward in BNB stile MasterChef |
| `DaimonGovernor.sol` | Governance: propose → vote → queue → execute, quorum su snapshot |
| `DaimonTimelock.sol` | Timelock con `MIN_DELAY` = 7 giorni hardcodato |
| `DaimonMigration.sol` | Migrazione 1:1 dal vecchio token, sweep post-deadline alla treasury |

Fuori scope: `src/mocks/`, `test/`, `script/`, la dApp (`daimon-dapp/`),
le dipendenze `lib/` (OpenZeppelin v5.4.0, considerate corrette).

## Vincoli di build

- `via_ir = true` **obbligatorio** (la matematica reflection va in "stack too
  deep" senza), `evm_version = shanghai` (BSC), `solc 0.8.26`. Vedi
  `foundry.toml`.

## Modello di fiducia e limiti noti

Documento completo in **[THREAT_MODEL.md](THREAT_MODEL.md)**. In sintesi:

- **Nessun owner, nessun mint.** Il controllo è del Timelock (7 giorni di
  delay); il deployer rinuncia a ogni ruolo (assert nello script + invariant
  test). Nessun `DEFAULT_ADMIN_ROLE`; `GOVERNANCE_ROLE` auto-amministra.
- **Floor 21B immutabile**, supply solo decrescente.
- **Destinazioni fee** (`marketingWallet`, `stakingContract`, split) tutte
  `onlyRole(GOVERNANCE_ROLE)`; `deadAddress` è `constant`, `treasury` della
  migration è `immutable`. Nessun percorso EOA.
- **Limite accettato — upgrade UUPS:** la DAO può sostituire la logica del
  token (solo via Timelock + delay). Trade-off esplicito aggiornabilità vs
  immutabilità.

## Esito del giro avversariale pre-freeze

Dettaglio in **[TESTNET_RESULTS.md](TESTNET_RESULTS.md)** (Test 10). Due
finding di governance (nessuna perdita fondi):

- **Finding 1 — CORRETTO.** Il quorum contava gli against
  (`for+against+abstain`), creando un incentivo perverso: opporsi poteva far
  raggiungere il quorum e passare la proposta. Ora quorum su `for+abstain`
  (against escluso), allineato a OpenZeppelin `GovernorCountingSimple`.
  Regressione coperta da test (`test/Adversarial.t.sol`).
- **Finding 2 — ACCETTATO e documentato.** Il voting power non decade dopo la
  scadenza del lock (premia i locker storici, differisce dai ve-token). Scelta
  di design consapevole per la v1; un decay è materiale fase 2 via governance.
  Vedi THREAT_MODEL §3.6.

## Copertura di test

**74 test verdi** (`forge test`): unit, sequenze di governance, fuzz (512
run), invariant handler-based (256 × 64), e la suite avversariale mirata
(snapshot/whale, valori limite, incentivi, reflection edge). Analisi statica
Slither eseguita — note sui finding in THREAT_MODEL §4.

## Aree su cui porre attenzione particolare

- Matematica reflection RFI (`_getRate`/`_getValues`/`_getCurrentSupply`),
  dust e conservazione al wei; interazione con `deadAddress` (unico escluso
  dai reward) e con il contratto stesso come holder.
- Percorso fee-swap → distribuzione marketing/staking e buyback&burn con la
  pool **reale** sotto slippage reale (su testnet esercitato in laboratorio).
- Timing governance: snapshot del voting power, quorum su snapshot, delay del
  Timelock ai boundary.

## Stato

Deployato e verificato su **BSC testnet**; **non ancora** su mainnet — il
deploy mainnet avverrà solo dopo questo audit (checklist in
[CHECKLIST_MAINNET.md](CHECKLIST_MAINNET.md)).

## Segnalazioni

Vulnerabilità: canale privato GitHub (**Security → Report a vulnerability**),
vedi [SECURITY.md](SECURITY.md). Non aprire issue pubbliche.
