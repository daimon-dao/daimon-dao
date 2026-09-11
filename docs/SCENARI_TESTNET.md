# SCENARI TESTNET — Daimon
*25 agosto 2026. Cosa provare quando il codice corretto gira su una
chain per la prima volta. Non sostituisce i 180 test unitari: quelli
provano che le funzioni funzionano. Questo prova che le SEQUENZE
reggono.*

*Nota dell'11 settembre 2026: il livello 1 (31 scenari, 162 step) e
il livello 2 su Chapel (giorni 1-5, chiusura la notte del 10/11) sono
stati eseguiti — vedi TESTNET_L1_RESULTS.md, TWO_PHASE_RESULTS.md e
CHAPEL_L2_RESULTS.md. Il documento è conservato come piano originale.*

---

## Perché questo documento esiste

Tre dei finding dell'audit non erano funzioni difettose. Erano
composizioni di funzioni singolarmente legittime:

```
#12   propose() + stake(), stesso blocco
#35   stake() + notifyRewardAmount() + claim()
#28   transfer() alla pair, ripetuto
```

Nessuna di quelle chiamate è vulnerabile da sola. Il problema esisteva
nella sequenza — ed è per questo che i test unitari non li vedevano:
verificano ogni funzione isolata, e ogni funzione era corretta.

Checkpoint dello Staking, ciclo completo di una proposta attraverso il
Timelock, e le tre autorità del guardian con la scadenza a 36 mesi:
**nessuno di questi era mai girato su una chain.** Questo documento
serve a scoprirne il comportamento reale prima del mainnet.

---

## Due livelli, due scopi diversi

```
LIVELLO 1 — Anvil locale, con salto temporale
   Scopo: le sequenze LOGICHE. Il tempo si manipola (warp).
   In un pomeriggio si girano cicli che sulla chain vera
   richiederebbero settimane.
   Qui si trovano i bug di logica di stato.
   Esecutore: Claude Code, in autonomia, contro questi scenari.

LIVELLO 2 — BSC Testnet (Chapel), tempo reale
   Scopo: la PROVA GENERALE. Timelock di 7 giorni VERI, latenze,
   nonce, gas, comportamento su chain pubblica.
   Non si cercano bug di logica (già presi al livello 1): si cerca
   ciò che Anvil non può dare.
   Qui debutta anche la Fase 1 del monitor (vedi SPEC_MONITOR.md).
```

Regola di passaggio: **non si va su Chapel finché il livello 1 non è
interamente verde.**

---
---

# PARTE 0 — ALLINEAMENTO (prima di qualsiasi scenario)

Una campagna testnet completa è già stata fatta (luglio, pre-audit):
10/10 test documentati, tre proposte di governance nei tre esiti
possibili (Executed / Defeated / Executed time-gated), sweep dei non
riscattati verificato al wei, tutti gli hash pubblici. **La
metodologia di quella campagna si riusa integralmente** — registro
pubblico, hash per ogni passaggio, esiti diversificati.

**Il codice invece no.** Quella campagna girava sul codice pre-audit:
checkpoint, guardian con scadenza e cancel atomica, modello poke,
parametro a 1000 — tutto questo è nato dopo, e non è mai stato su una
chain. Nel repo restano lo script di deploy testnet, il
`MockOldDaimon` e la guida `DEPLOY.md` di quell'era: prima di
riusarli, vanno verificati contro il `master` consolidato:

```
□ Lo script di deploy testnet compila e gira sul codice attuale?
□ Rispetta l'ORDINE DI DEPLOY corretto?
   → DaimonMigration PRIMA del token (o indirizzo precalcolato),
     così è escluso dalle fee fin da initialize() — avvertenza
     esplicita del report
□ Imposta stakingRewardShareBps = 1000?
   → il default in initialize() è 600; se lo script non lo forza,
     il testnet gira col modello sbagliato e non prova nulla di
     utile sul punto legale
□ Il MockOldDaimon riflette la distribuzione DMX reale?
   → serve per dare alla migrazione qualcosa di realistico da
     migrare (vedi sotto)
□ Il contratto Migration è finanziato con abbastanza DMN?
   → se migrassero tutti i detentori terzi servono ~966,52 mld DMN.
     VERIFICARE il conto nello script di deploy: è la voce che, se
     sbagliata, blocca la migrazione a metà
```

⚠️ Uno script di deploy vecchio che "gira" è più pericoloso di uno
che non compila: il secondo si nota, il primo no.

---
---

# LIVELLO 1 — SEQUENZE LOGICHE (Anvil)

## Invariante globale — vale in OGNI scenario

```
IN QUALSIASI MOMENTO, IN QUALSIASI SCENARIO:
   il marketing wallet non ha MAI ricevuto nulla.

Da verificare come ASSERT dopo ogni passo di ogni scenario, non a
occhio. È l'invariante legale del progetto (stakingRewardShareBps =
1000). Se un solo assert fallisce, tutto il resto è secondario.
```

Altri invarianti da asserire di continuo:
```
□ totalSupply >= floor (21 mld) — sempre
□ i due contratti guardian/timelock non sono mai in disaccordo
   sullo stato di un'operazione
□ nessun token esce dal Timelock se non via proposta eseguita
```

---

## Scenario A — Migrazione (il primo che deve girare)

```
A0  IL PREDECESSORE — configurazione DMX (finding #29, BLOCCANTE)
    Il contratto Migration è solo lo spender dell'allowance: il
    trasferimento vero è claimant → treasury. DMX disattiva le fee
    solo se from O to è esente: esentare Migration NON serve a nulla.
    PROVA (il MockOldDaimon deve riprodurre questa semantica):
    - excludeFromFee(TREASURY) sul vecchio token — la treasury,
      NON il contratto Migration
    - claim() da un holder NON esente → la treasury riceve
      l'importo ESATTO, nessuna fee dedotta
    CONTROPROVA: esentare solo Migration e verificare che la fee
    venga dedotta comunque — così l'errore è visto prima del giorno
    in cui la deadline immutabile lo renderebbe irreparabile.
    (Su mainnet, in più: verificare che l'owner DMX abbia ancora
    l'autorità di impostare esenzioni — mai rinunciata, da
    confermare.)

A1  Deploy completo, ordine corretto, parametro a 1000
    ATTESO: _assertDecentralized passa (20 assert), marketing wallet
    a zero, Migration finanziato

A2  Un holder del mock migra una quota parziale
    ATTESO: riceve DMN 1:1, il DMX versato è tolto dalla circolazione

A3  Lo stesso holder migra il resto
    ATTESO: seconda migrazione ok, nessun doppio conteggio

A4  Un holder migra il 100% in una volta
    ATTESO: 1:1 esatto

A5  "Cosa succede se" — tutti i detentori migrano
    ATTESO: il DMN nel Migration basta (verifica del conto 966,52 mld);
    se NON basta, è il bug più importante da trovare qui
```

## Scenario B — Token: fee, reflection, e il modello POKE

⚠️ Il punto più controintuitivo di tutto il sistema. Dopo il fix #1,
**le vendite via router NON innescano più la conversione fee.** La
conversione parte solo con un transfer diretto alla pair (il "poke").

```
B0  LA POOL INIZIALE — il prezzo di partenza (finding #17)
    La pair NON è fee-exempt (e non deve diventarlo): la gamba DMN
    dell'aggiunta di liquidità arriva alla pair AL NETTO della fee,
    mentre il router calcola sul lordo.
    PROVA: creare la pool iniziale calcolando il BNB sul DMN
    EFFETTIVAMENTE RICEVUTO dalla pair, non su quello inviato.
    ATTESO: il prezzo di inizializzazione è quello voluto.
    CONTROPROVA: crearla (su un fork usa-e-getta) col BNB sul lordo
    e verificare che il prezzo nasca sbagliato — così il giorno del
    mainnet l'errore è già stato visto e non si può fare.

B1  Due transfer ordinari tra wallet
    ATTESO: fee applicata; la reflection arriva (il saldo di un
    holder fermo cresce dopo transfer altrui)

B2  Una vendita via router, sopra minimumTokensBeforeSwap
    ATTESO: la vendita passa, MA l'automazione NON parte.
    L'inventario fee resta come DMN nel contratto. Questo è
    CORRETTO, non un bug.

B3  Il poke — transfer diretto di 1 wei alla pair
    ATTESO: ORA parte la conversione, limitata dai budget del #28
    (un chunk fee-swap + una slice buyback per blocco)

B4  Il poke ripetuto nello stesso blocco (#28)
    ATTESO: il budget per blocco NON viene superato — le iterazioni
    ripetute non aggregano oltre il tetto

B5  "Cosa succede se" — nessuno pokes mai
    ATTESO: le fee si accumulano come DMN, il BNB buyback resta
    fermo, niente si rompe, nessuna perdita. Solo la cadenza
    degrada. (È lo stato che il monitor deve saper distinguere da
    un guasto.)
```

## Scenario C — Staking e checkpoint (mai girato su chain)

```
C1  Stake con lock 30gg e stake con lock 365gg
    ATTESO: voting power secondo i moltiplicatori (1x vs 4x)

C2  Withdraw prima della scadenza del lock
    ATTESO: reverte

C3  Ciclo di checkpoint attraverso più epoche
    ATTESO: il voting power storico a un blocco passato è coerente;
    lo snapshot regge

C4  #35 riprodotto — stake(1 wei) + notifyRewardAmount(0) + claim()
    in una transazione, con reward accumulati a staking vuoto
    ATTESO: il chiamante NON cattura il backlog. Il backlog è nella
    riserva separata, sbloccabile solo da governance. (Questo test
    esisteva come repro FAIL→PASS: qui si verifica sulla chain.)

C5  notifyRewardAmount con importo anomalo
    ATTESO: distribuzione corretta pro-quota agli staker presenti
```

## Scenario D — Governance end-to-end (il ciclo completo)

```
D1  propose() — cambio di un parametro (es. una fee)
    ATTESO: proposta creata, snapshotTotalVotingPower congelato al
    momento della creazione

D2  #12 riprodotto — stake() nello stesso blocco della propose()
    ATTESO: lo stake successivo NON conta per quella proposta (lo
    snapshot è già sigillato)

D3  vote() → fine periodo di voto → quorum calcolato sullo SNAPSHOT
    ATTESO: qualcuno che staka dopo la fine del voto non altera il
    quorum

D4  queue() → warp 7 giorni → execute()
    ATTESO: execute reverte se queue() non è stata chiamata (campo
    queued); dopo il timelock, il parametro cambia davvero

D5  "Cosa succede se" — execute() senza passare da queue()
    ATTESO: reverte
```

## Scenario E — Guardian, le tre autorità e la scadenza

Il blocco mai girato su chain, e quello con più bordi temporali.

```
E1  setPaused(true) dal guardian → transfer bloccati
    setPaused(false) → riprendono

E2  La pausa si auto-termina
    setPaused(true), poi warp oltre pauseUntil (max 14gg) SENZA
    unpause esplicito
    ATTESO: isPaused() è già falso dopo il warp, senza alcuna
    chiamata

E3  Cancellazione atomica — op in coda + guardian la cancella
    direttamente, poi Governor.cancel sulla stessa op
    ATTESO: Governor.cancel NON chiama timelock.cancel (i flag
    convergono, nessun revert su OperationAlreadyCanceled)

E4  op già eseguita + Governor.cancel
    ATTESO: reverte su AlreadyExecuted

E5  LA SCADENZA — warp oltre guardianExpiry (36 mesi)
    ATTESO: tutte e tre le autorità scadono insieme; una pausa
    messa prima non sopravvive alla scadenza; i cancel del guardian
    sono morti; il sistema si auto-risana senza alcuna azione

E6  #36 — contabilità pausa→deadline nella Migration
    Guardian pausa durante la finestra di migrazione, poi unpause
    ATTESO: effectiveMigrationDeadline = base + credito pausa; lo
    sweep del residuo NON scatta finché il credito tiene aperta la
    finestra di claim

E7  "Cosa succede se" — guardian compromesso pausa il giorno prima
    di scadere e rifiuta l'unpause
    ATTESO: alla scadenza la pausa lapsa da sola; il recupero via
    governance non è cancellabile dopo la scadenza
```

## Scenario F — La treasury (Timelock multi-asset)

```
F1  Il Timelock riceve BNB e un BEP-20
    ATTESO: li custodisce

F2  Una proposta che deposita e approva in parallelo (una call)
    ATTESO: approve e deposit nella stessa proposta funzionano

F3  Il Timelock NON è fee-exempt di default
    ATTESO: un trasferimento DMN verso/da esso sconta la fee finché
    una proposta non lo esenta; le uscite di DMN sono già esenti da
    maxTxAmount (GOVERNANCE_ROLE)
```

---
---

# LIVELLO 2 — PROVA GENERALE (Chapel)

Solo dopo che il livello 1 è interamente verde.

```
G1  Deploy su Chapel con la configurazione ESATTA del mainnet
    (timelock 7 giorni veri, non ridotti)

G2  Il monitor Fase 1 puntato su questi contratti
    → gira in parallelo a tutti gli scenari sotto
    → verifica che gli alert scattino quando devono e TACCIANO
      quando non devono (test dell'assuefazione)
    → l'alert "marketing wallet ha ricevuto" non deve suonare MAI

G3  Un ciclo di governance completo in tempo reale
    propose → vote → queue → 7 giorni VERI → execute
    → mentre si aspettano i 7 giorni, il tempo è produttivo:
      è la finestra per rodare il monitor e (se si vuole) la dApp

G4  Una migrazione reale con più wallet di test in ruoli distinti
    (deployer, guardian, staker, holder che migra) — parte di ciò
    che si verifica è che i RUOLI non si confondano

G5  Il poke in condizioni reali
    → una vendita che non innesca, un transfer da 1 wei che innesca
    → verifica gas, budget per blocco, e che il monitor veda
      l'inventario fee crescere e poi convertirsi

G6  LA PROVA DEL GIORNO DEL LANCIO — l'ordine esatto, provato una
    volta per intero prima che conti (dalla CHECKLIST_MAINNET):
    1. Esenzione fee della TREASURY sul predecessore (A0), verificata
    2. Verifica che la pair DMN/WBNB NON esista già sulla factory
       (#25: un osservatore può pre-crearla per bloccare il deploy —
       il fix getPair() deve essere nell'implementation deployata)
    3. Deploy nell'ordine corretto, parametro a 1000
    4. AUTOMAZIONE SPENTA (o fix fail-open verificato) finché la
       pair non ha riserve (#27: una donazione di ~1 BNB al token
       prima della liquidità iniziale può bloccare il lancio —
       PROVARE anche questo caso)
    5. Liquidità iniziale col BNB calcolato sul NETTO (B0),
       rapporto riserve = prezzo voluto, verificato
    6. UNA pool sola (DMN/WBNB); l'indirizzo pair memorizzato nei
       contratti = quello creato (un indirizzo sbagliato rompe
       fee-swap e buyback IN SILENZIO)
    7. Riserve entrambe non-zero → automazione attivata
    8. Uno swap piccolo di prova → fee 4% applicata
    9. Il primo poke → conversione parte, budget rispettati
    10. Il monitor ha visto tutto e l'alert marketing wallet non ha
        mai suonato
```

---
---

# PREREQUISITI PRATICI

```
□ Wallet di test DEDICATI, uno per ruolo (mai wallet con fondi veri)
□ tBNB dal faucet: https://www.bnbchain.org/en/testnet-faucet
□ Chiave nel keystore cifrato (cast wallet import --interactive),
   mai in chiaro nel codice o nei file
□ Endpoint RPC Chapel, con fallback
□ Il MockOldDaimon con distribuzione DMX realistica
```

---

# NOTE PER CHI ESEGUE (Claude Code)

- Livello 1 in autonomia contro questi scenari; riportare i risultati
  **scenario per scenario**, non un riassunto.
- Ogni scenario con "Cosa succede se" è più importante degli altri:
  è il metodo che ha trovato le cose migliori dell'audit.
- Se uno scenario NON si comporta come atteso, **riportarlo, non
  aggiustarlo in silenzio.** Un atteso sbagliato è un'informazione;
  un fix non richiesto durante il test è un problema.
- Nessuna nuova funzionalità. Il codice è quello di master
  consolidato, si testa, non si estende.
- forge clean prima di ogni verifica.
