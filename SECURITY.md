# SECURITY.md — Modello di minaccia e assunzioni di fiducia

Documento per l'auditor professionale e per la community. Descrive cosa
può e non può fare ciascun attore, le difese in essere, i limiti noti e
accettati, e le assunzioni di fiducia su cui poggia il sistema.

Stato: contratti deployati e verificati su BSC testnet; suite di test
(unit + fuzz + invariant) verde; analisi statica Slither eseguita. **Non
ancora sottoposto ad audit professionale esterno.**

Contratti in scope: `DaimonV2` (token), `DaimonStaking`, `DaimonGovernor`,
`DaimonTimelock`, `DaimonMigration`.

---

## 1. Attori e capacità

| Attore | Chi è | Cosa può fare | Cosa NON può fare |
|---|---|---|---|
| **Utente/holder** | chiunque | trasferire, stakare, votare (se ha vp allo snapshot), migrare, riscuotere reward, `burnDeadBalanceToFloor` | modificare parametri, coniare, sbloccare lock in anticipo |
| **Attaccante esterno** | EOA/contratto ostile senza ruoli | interagire come un utente qualsiasi, tentare reentrancy/MEV | acquisire ruoli, drenare fondi, coniare, superare i limiti hardcodati |
| **Whale** | holder con capitale elevato | accumulare voting power (solo bloccando token nel tempo), influenzare i voti | votare con potere acquistato *dopo* la proposta; flash-loan governance |
| **Governance (DAO via Timelock)** | Timelock guidato dal Governor | cambiare fee (≤10%), indirizzi, limiti, **upgrade UUPS del token** | coniare, portare la supply sotto il floor, azzerare il delay del Timelock, agire senza delay pubblico di 7 giorni |
| **Guardian** | multisig di emergenza | mettere in pausa il token (≤36 mesi), cancellare proposte/operazioni malevole | poteri economici, eseguire proposte, sbloccare pausa dopo scadenza (ma può sempre *togliere* la pausa) |
| **Deployer** | chi esegue lo script di deploy | solo il wiring iniziale | **nulla dopo il deploy**: rinuncia a tutti i ruoli (verificato on-chain) |

---

## 2. Minacce e difese per attore

### 2.1 Attaccante esterno

- **Coniazione / inflazione supply.** Nessuna funzione di mint esiste in
  nessun punto del codice. La supply è creata una sola volta nel
  `initialize()` e può solo scendere (burn verso il floor). *Invariante
  testato:* `totalSupply ≤ INITIAL_SUPPLY` e `≥ MIN_SUPPLY` sempre.
- **Reentrancy.** Tutte le funzioni che muovono valore usano
  `ReentrancyGuard` di OpenZeppelin (`stake`, `withdraw`, `claimReward`,
  `claim`, `sweepUnclaimed`, `burnDeadBalanceToFloor`, gli swap interni).
  Pattern checks-effects-interactions rispettato: gli stati sono aggiornati
  prima delle chiamate esterne. Slither segnala reentrancy solo su percorsi
  già protetti dal guard o su chiamate a contratti fidati (router, staking) —
  vedi §4.
- **Acquisizione di ruoli.** Il controllo accessi è OZ `AccessControl`
  (token, timelock) e un mapping governance dedicato (staking).
  `GOVERNANCE_ROLE` amministra sé stesso; nessun `DEFAULT_ADMIN_ROLE` è
  assegnato sul token. *Invariante testato:* nessun EOA/attore detiene ruoli
  amministrativi in nessuna sequenza di azioni.
- **DoS.** Nessun loop su array a lunghezza utente-controllata nelle
  funzioni pubbliche (i lock sono indicizzati per id; i checkpoint del
  voting power usano ricerca binaria O(log n)). L'unico loop è su
  `_excluded` (reflection), popolato solo dalla governance e limitato di
  fatto al dead address.

### 2.2 MEV / front-running

- **Swap di fee e buyback.** Derivano `amountOutMin` da `getAmountsOut`
  meno una tolleranza di slippage governata (`maxSwapSlippageBps`, default
  5%, limitata tra 0,5% e 30%). Gli swap girano in `try/catch`: se il
  prezzo esce dalla tolleranza lo swap viene *saltato* (fondi conservati),
  senza far revertire il trasferimento dell'utente che lo ha innescato
  (evita un vettore di DoS sui sell).
- **Limite noto accettato:** il quote è letto nello stesso blocco dello
  swap, quindi la protezione limita il danno **alla tolleranza impostata**,
  non lo elimina del tutto. Eliminarlo richiederebbe un oracolo TWAP. È un
  compromesso esplicito (vedi §3).
- **Voto tardivo.** Il voting power è fotografato allo snapshot della
  proposta (`votingPowerAt`): comprare e stakare dopo la creazione non dà
  potere su quella proposta.

### 2.3 Whale / manipolazione della governance

- Il voting power deriva **esclusivamente** da token bloccati nel tempo
  (vote-escrow), non dal balance ERC20 liberamente spostabile. Per pesare
  su una proposta bisogna aver bloccato **prima** della sua creazione
  (snapshot con ricerca binaria sui checkpoint). Questo neutralizza sia i
  flash-loan sia gli acquisti mirati a una proposta già visibile.
- Il quorum è calcolato sullo **snapshot** di `totalVotingPower` alla
  creazione, non sul valore live: stake/unstake successivi non alterano la
  soglia. Floor di quorum hardcodato al 10% (`MIN_QUORUM_BPS`).

### 2.4 Governance stessa (attore semi-fidato)

La DAO è potente ma **vincolata da limiti hardcodati non aggirabili**:

- **Fee:** `setFees` ha un cap del 10% totale immutabile (`FeeTooHigh`).
- **Supply:** nessun percorso, upgrade incluso a livello di storage, può
  coniare o scendere sotto `MIN_SUPPLY` (floor enforced in ogni burn).
- **Timelock:** `MIN_DELAY = 7 giorni` hardcodato; `updateDelay` può solo
  restare ≥ a questo floor. Ogni azione di governance passa per il Timelock
  con delay pubblico → la community ha sempre una finestra per reagire.
- **maxTx / soglia di swap:** i setter hanno bound minimi anti-self-DoS.
- **Limite noto accettato — upgrade UUPS.** La DAO *può* sostituire la
  logica del token via upgrade (autorizzato solo dal Timelock, con delay).
  Un upgrade malevolo approvato dalla governance potrebbe in teoria
  reintrodurre un mint o alterare la logica. Questo è il limite intrinseco
  di qualunque sistema upgradable ed è **accettato per design**: la difesa
  è di processo (delay pubblico di 7 giorni + codice in chiaro + reazione
  della community), non tecnica. *Testato:* solo il Timelock può fare
  upgrade; guardian ed EOA non possono; lo stato è preservato.

### 2.5 Guardian

- Poteri **solo difensivi**: pausa del token e cancel di proposte/operazioni.
  Nessun potere economico, nessuna esecuzione.
- **Scadenza a 36 mesi** (`guardianExpiry`): dopo, `setPaused(true)` reverte
  per sempre (decentralizzazione definitiva, verificabile on-chain).
  `setPaused(false)` resta sempre possibile → un contratto in pausa alla
  scadenza non resta congelato per sempre.
- Assunzione: il guardian è un **multisig** (in produzione). Un guardian
  compromesso può mettere in pausa (DoS temporaneo, non furto) e cancellare
  proposte legittime (censura temporanea) fino alla scadenza.

### 2.6 Migrazione

- **Pull, non push:** ogni utente avvia la propria claim.
- **Verifica 1:1 su entrambi i lati:** balance-before/after sul vecchio
  token (in entrata) e sul nuovo (in uscita); qualsiasi discrepanza da
  fee-on-transfer inattese fa revertire proteggendo l'utente
  (`AmountMismatch`).
- **Cap:** la migration non può distribuire più della supply assegnatale al
  deploy (nessuna creazione di supply). *Invariante testato:* vecchi token
  in treasury == `totalMigrated`, e la migration non distribuisce mai più
  DMN del dovuto.
- **Sweep:** solo dopo la deadline, solo dal Timelock, solo verso la
  treasury della DAO, una volta sola.

---

## 3. Limiti noti e accettati

1. **MEV residuo entro slippage.** La protezione swap limita il danno alla
   tolleranza governata (default 5%), non lo azzera (nessun TWAP on-chain).
2. **Upgrade autorizzabile dalla DAO.** L'upgrade UUPS può in teoria
   sostituire la logica monetaria; mitigato solo dal delay pubblico del
   Timelock. Trade-off esplicito tra aggiornabilità e immutabilità assoluta.
3. **Reflection e dust.** La contabilità reflection (stile RFI) accumula
   rounding: la somma dei saldi è `≤ totalSupply` (mai sopra), con polvere
   persa per divisione intera. La migration, essendo un holder, accumula
   reflection sul residuo non riscattato (benigno: finisce alla treasury
   allo sweep).
4. **Reward BNB e dust.** L'accumulatore reward (scala 1e27) può lasciare
   frazioni non distribuite; i BNB versati senza staker sono accodati e
   ridistribuiti al primo notify utile.
5. **Dipendenza dal router PancakeSwap.** Gli swap si affidano al router V2
   esterno; un suo malfunzionamento degrada fee/buyback (gestito con
   try/catch, non blocca i trasferimenti).

---

## 4. Note sui finding dell'analisi statica (Slither)

I finding "High" di Slither su questi contratti sono **falsi positivi** nel
contesto o mitigati:

- **`arbitrary-send-eth`** su `_swapAccumulatedFees`, `_buyBackAndBurn`,
  `Timelock.execute`: i destinatari non sono arbitrari controllati da un
  attaccante — sono il `marketingWallet`/`stakingContract` governati e il
  `target` di una proposta già passata per voto + timelock. Non c'è percorso
  in cui un esterno dirotti l'ETH.
- **`reentrancy-*`**: i percorsi segnalati sono protetti da `nonReentrant`
  o interagiscono con contratti fidati (router, staking). Gli stati sono
  aggiornati prima delle chiamate esterne (CEI).
- **`uninitialized-state` su `_vpCheckpoints`**: è un mapping, inizializzato
  vuoto per definizione; non è un difetto.
- **`incorrect-equality` / `divide-before-multiply`**: su calcoli reflection
  e confronti di saldo dove l'uguaglianza stretta è voluta e la precisione è
  gestita; nessun impatto sfruttabile.
- **`timestamp`**: i confronti temporali (lock, timelock, voto) usano
  `block.timestamp` con granularità di giorni/ore, ben oltre la finestra di
  manipolazione del miner (secondi). Accettato.

I finding informational/optimization (naming, eventi mancanti su alcuni
setter del Governor, versioni pragma multiple dovute alle librerie) sono
tracciati e in parte già indirizzati; nessuno è bloccante.

---

## 5. Assunzioni di fiducia

- Il **deployer** esegue lo script ufficiale e rinuncia a tutti i ruoli
  (verificato on-chain dagli assert dello script e dagli invariant test).
- **Guardian, treasury e marketing wallet** sono multisig distinti in
  produzione (su testnet coincidono col deployer, solo per test).
- La **community** monitora le proposte durante il delay di 7 giorni: è la
  difesa ultima contro un upgrade o un cambio parametri malevolo.
- Le **librerie OpenZeppelin v5.4.0** (AccessControl, UUPS, Initializable,
  ReentrancyGuard) sono considerate corrette e auditate.
- Il **router PancakeSwap V2** su BSC si comporta secondo interfaccia.

---

## 6. Copertura di test (sintesi)

- 60 test: unit (29), sequenze di governance (6), fuzz (6, 512 run/ciascuno),
  invariant handler-based (6, 256 run × 64 profondità), percorsi critici
  di copertura inclusi upgrade UUPS (13).
- Invarianti verificati: supply nei limiti, `totalVotingPower` = somma dei
  lock attivi e dei vp per-utente, conservazione della migrazione, saldo
  reward = versato − riscosso, nessun ruolo admin non autorizzato.

Dettaglio dei finding e delle proposte di correzione: vedi il report di
hardening allegato alla PR / conversazione di review.
