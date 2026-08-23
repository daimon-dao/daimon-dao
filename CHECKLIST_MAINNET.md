# Checklist deploy mainnet — Daimon DAO

Da eseguire **solo dopo** l'audit professionale, sullo scope congelato al tag
[`audit-scope-v1`](https://github.com/daimon-dao/daimon-dao/releases/tag/audit-scope-v1)
(commit `bd6d544`, contratti in `src/`). Ogni riga è bloccante.

## Indirizzi (attenzione: alcuni sono IMMUTABLE)

- [ ] **`marketingWallet` → MULTISIG.** Mai un EOA. Riceve la quota marketing
      delle fee. Modificabile solo via governance/timelock, ma va impostato
      giusto già al deploy (`initialize`).
- [ ] **`treasury` della migration → MULTISIG scelto con cura.** ⚠️ È
      **`immutable`**: si fissa nel costruttore di `DaimonMigration` e **non
      si può più cambiare**, nemmeno via governance. Destinazione dei vecchi
      token e dello sweep post-deadline. Sbagliarlo = irreversibile.
- [ ] **`guardian` → Ledger dedicato o multisig.** Poteri solo difensivi
      (pausa ≤36 mesi, cancel proposte). Non deve coincidere col deployer.
- [ ] **`deployer` → Ledger dedicato.** Rinuncia a tutti i ruoli a fine
      script; usare comunque un signer hardware, non una hot wallet.
- [ ] **`_governance` (Timelock) = unico GOVERNANCE_ROLE.** Il deployer deve
      risultare senza ruoli dopo il wiring.

Nota: su testnet marketing/treasury coincidono col deployer solo per test —
su mainnet devono essere multisig distinti.

## Verifiche automatiche

- [ ] **`_assertDecentralized()` gira e passa su mainnet** (20 assert nello
      script di deploy): timelock governa token/staking, deployer senza
      ruoli, nessun `DEFAULT_ADMIN`, supply interamente nella migration,
      ruoli CANCELLER (guardian, governor, timelock stesso), **scadenza
      guardian identica nei tre contratti** (#36) e **quota operativa a
      zero** (`stakingRewardShareBps == 1000`, compliance al lancio), ecc.
- [ ] Contratti **verificati su BscScan** (source + costruttori).
- [ ] `MIN_DELAY` del Timelock = **7 giorni**; `MIN_SUPPLY` = **21B**;
      cap fee 10%; `MAX_PAUSE_DURATION` = **14 giorni** e
      `guardianAuthorityExpiry` = `token.guardianExpiry()` su Governor e
      Timelock (#36) — confermati on-chain post-deploy.

## dApp

- [ ] **`NEXT_PUBLIC_CHAIN_ID=56`** nelle env di produzione Vercel: spegne
      automaticamente `noindex` e il banner "ambiente di test", e fa seguire
      a cascata RPC/explorer/indirizzi mainnet (compila `BSC_MAINNET` in
      `daimon-dapp/src/config/contracts.ts`, inclusa la pair PancakeSwap letta
      da `daimonV2.uniswapV2Pair()`).
- [ ] Riattivare la Deployment Protection se l'URL deve restare privato in
      staging; per il lancio pubblico, dominio ufficiale + allowlist
      WalletConnect.

## Automazione fee (post-fix Zenith #1)

- [ ] **Monitorare il saldo DMN del contratto token** dopo il lancio:
      `balanceOf(DaimonV2)` è l'inventario fee non ancora convertito.
- [ ] Quando supera `minimumTokensBeforeSwap`, un **transfer di 1 wei di DMN
      alla pair**, da un indirizzo qualsiasi, innesca la conversione (al
      massimo un chunk di fee-swap e una slice di buyback per blocco: budget
      del #28). Anche il BNB del buyback si muove solo così: le vendite via
      router non innescano più nulla.
- [ ] **NON è un requisito di sicurezza**: se il poke si ferma, le fee si
      accumulano e basta — nessuna scadenza, nessuna perdita, si riparte col
      poke successivo. Modello completo e motivazione in THREAT_MODEL.md §8
      (⚠️ non "correggere" il fix reintroducendo il trigger sulle vendite:
      riaprirebbe il finding #1).

## Governance post-lancio

- [ ] `marketingWallet` e `stakingContract` restano modificabili **solo** via
      proposta → voto → queue → timelock 7g → execute (nessun percorso EOA).
- [ ] Rinnovo/rotazione guardian prima della scadenza a 36 mesi, se voluto,
      via governance.

---

**Freeze:** i contratti in `src/` sono congelati al tag `audit-scope-v1`.
Qualsiasi modifica ai contratti prima del mainnet richiede un nuovo tag
(`audit-scope-v2`, …) e la ri-esecuzione delle verifiche.
