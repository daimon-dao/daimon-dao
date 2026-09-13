# SCENARI 2b — mini-campagna su Chapel
*12 settembre 2026. Un solo giro su BSC testnet per tutte le modifiche
allo script di lancio decise dopo la campagna di livello 2, più il
drill del guardian. Stesso metodo: scenari scritti prima, esiti attesi
dichiarati, riporto scenario per scenario, mai aggiustare in silenzio.
Il codice in src/ non si tocca: cambiano SOLO script/, test/mock e
verify-deploy.*

**Prerequisito di partenza**: master a e1e0df2 o successivo, gate
verde (src/ identico ad audit-final, 180 test).

---

## H0 — Cosa cambia nello script (le modifiche da provare)

```
H0.1  DeployPhase1.s.sol   marketingWallet: default = predictedTimelock
                           (stessa predizione già usata per la treasury
                           della Migration), non più il deployer.
                           MARKETING_WALLET in env resta come override
                           esplicito; se coincide col deployer → warning
                           "testnet only" come oggi.
H0.2  DeployPhase2.s.sol   PRIMA di cedere GOVERNANCE_ROLE al Timelock:
                           token.setFees(10, 10, 20). Poi grant al
                           timelock e revoke al deployer come oggi.
H0.3  verify-deploy.ps1    due controlli nuovi (34 → 36):
                           - token.taxFee/buybackFee/marketingFee ==
                             (10, 10, 20)
                           - token.marketingWallet() == timelock
                             DEPLOYATO (letto dalla chain, non dallo
                             state-file)
H0.4  Passo LP             dopo la liquidità iniziale: transfer di TUTTI
                           i token LP dal deployer al Timelock, tx
                           registrata; assert post-broadcast:
                           pair.balanceOf(deployer) == 0 e
                           pair.balanceOf(timelock) == totalSupply −
                           MINIMUM_LIQUIDITY (i 1000 wei bloccati da
                           PancakeSwap alla creazione)
H0.5  Mock del predecessore  MockOldDaimon / CampaignOldDaimon modellano
                           _maxTxAmount (default 1,5 mld, esente solo
                           from/to owner) e setMaxTxAmount(onlyOwner),
                           con la stessa semantica del DMX reale
                           (verificata il 10/9: cap applicato ai claim,
                           esenzione fee NON lo toglie)
H0.6  Test unitari         i test esistenti restano 180 verdi; nuovi test
                           per H0.5 (claim > cap reverte; dopo
                           setMaxTxAmount passa) — sono test, non src/
```

**Cosa succede se** una modifica allo script rompe un assert esistente
→ è un finding: si riporta, non si adatta l'assert.

---

## H1 — Deploy 2b su Chapel (contratti nuovi, paralleli ai vecchi)

```
H1.1  Fase 1 con le modifiche H0.1 → marketingWallet == predictedTimelock
      nello stato minato (assert p1)
H1.2  Fase 2 con H0.2 → fee (10,10,20) DOPO la revoca del ruolo al
      deployer; guardianExpiry identico sui tre contratti (come L2)
H1.3  GUARDIAN_ADDRESS = Safe di prova 0x4253f80666E48a04CAbE4966Aa63035Dbb4f104F
      (multisig.bnbchain.org, 2 su 3, F1·F2·F3 con tBNB)
H1.4  Verifica post-broadcast 36/36 — GATE OBBLIGATORIO
H1.5  Ordine di lancio completo (G6 rinumerato):
        1 pair non pre-esistente
        2 deploy due fasi, quota 1000
        3 36/36
        4 automazione inerte finché la pair non ha riserve
        5 liquidità iniziale col BNB sul NETTO
        6 LP → Timelock (H0.4), tx registrata, assert
        7 una pool sola, pair memorizzata == pair creata
        8 riserve non-zero → automazione attiva
        9 swap piccolo → fee 4% applicata (non più 5%)
       10 primo poke → conversione; con quota 1000 NESSUN BNB
          dal token al Timelock (invariante di lancio)
       11a mock DMX: setMaxTxAmount alzato dall'owner di test
       11b mock DMX: excludeFromFee(TIMELOCK) — apre la finestra
H1.6  Sentinella: seconda istanza in dry-run (o config alternativa)
      puntata sui contratti 2b — la produzione resta sui vecchi.
      Deve leggere all'avvio: marketingWallet == Timelock, quota 1000,
      fee (10,10,20), le tre esenzioni, LP nel Timelock
```

**Cosa succede se** la predizione del Timelock non torna (nonce
diverso) → fase 2 deve FERMARSI all'assert, non correggere: è il
comportamento già provato in L2.

---

## H2 — Migrazione con il cap (il finding maxTx)

```
H2.1  Holder di test con 3 mld di mock-DMX prova claim() PRIMA di 11a
      ATTESO: reverte "exceeds the maxTxAmount" (o messaggio del mock)
H2.2  Owner di test esegue setMaxTxAmount(supply intera) — 11a
H2.3  Stesso holder ripete claim() → ATTESO: riceve 3 mld DMN 1:1 esatti,
      la treasury riceve 3 mld di mock-DMX senza fee (11b attiva)
H2.4  Un holder migra un importo sotto il cap → identico a L2
H2.5  Cosa succede se: claim prima di 11b → reverte (finestra chiusa)
      come in L2 giorno 1
```

---

## H3 — G1 su Chapel: la prima proposta del mainnet, provata

```
H3.1  propose: target TOKEN, setStakingRewardShareBps(600)
      Sentinella: ProposalCreated → URGENT alla creazione (tocca il
      parametro) — atteso, si conferma a mano
H3.2  vote (5 giorni reali) → queue → 7 giorni reali → execute
      (calendario: ~13 giorni; nel frattempo H4)
H3.3  Dopo l'execute: ParamsUpdated("stakingRewardShareBps", 600);
      la sentinella INVERTE l'invariante (config manuale lo stesso
      giorno)
H3.4  POKE dopo l'execute, con inventario fee nel token:
      ATTESO: il ramo marketing si esegue per la prima volta; 60% allo
      Staking, 40% in BNB al Timelock — call{value} riuscita
      (receive() del Timelock); saldo BNB del Timelock sale;
      sentinella: NOTIFICATION "BNB dal token al Timelock: X"
H3.5  Cosa succede se: require(ok) fallisse → il fee-swap reverte e
      l'automazione si blocca: è il caso da NON scoprire sul mainnet.
      Se accade, fermarsi e riportare.
```

---

## H4 — Drill del guardian (durante l'attesa di H3)

Con la Safe di prova, i tre firmatari con tBNB, il runbook alla mano,
e il CRONOMETRO.

```
H4.1  Pausa: alert simulato nel gruppo → F1 propone setPaused(true) in
      Safe → F2 legge sul Ledger e conferma → esecuzione
      Misura: alert → tx minata. Obiettivo: < 60 minuti.
      Sentinella: PausedSet(true) URGENT
H4.2  Unpause: stessa coreografia, F3 propone, F1 conferma
H4.3  Pausa lasciata scadere: NON si prova sull'orologio reale (14
      giorni — decisione del 28/8); si documenta il riferimento a E2
H4.4  "Psy irraggiungibile": F2 propone, F3 conferma ed esegue — Psy
      non tocca nulla. Cronometro.
H4.5  Cancellazione via Governor: proposta di prova messa in coda →
      guardian (Safe) chiama Governor.cancel(id) → ATTESO: cancellazione
      atomica anche nel Timelock (flag convergono); sentinella:
      ProposalCanceled + Cancelled
H4.6  Cancellazione diretta nel Timelock: seconda proposta in coda →
      Safe chiama timelock.cancel(opId) direttamente → poi
      Governor.state(id) deve riflettere Canceled
H4.7  SCENARIO W: proposta "ostile" da staker3 (es. setMaxTxAmount a un
      valore assurdo) → NESSUNO vota → raggiunge il quorum da sola e
      passa → queue → il guardian la cancella in coda entro i 7 giorni.
      Sentinella: ProposalCreated NOTIFY → CallScheduled con ETA → la
      cancellazione. Cronometro dal CallScheduled alla Cancelled.
H4.8  Cosa succede se un firmatario firma senza leggere → il drill lo
      rende visibile: chi conferma deve dire ad alta voce nel gruppo
      contratto e funzione PRIMA di confermare
```

---

## H5 — Chiusura 2b

```
H5.1  Journal CHAPEL_2B_RESULTS.md nello stile di L2: tabella scenario per
      scenario, hash, tempi del cronometro, deviazioni
H5.2  Gate: src/ identico ad audit-final, test verdi (180 + i nuovi)
H5.3  Merge in master delle modifiche a script/test/verify
H5.4  DEPLOY.md e CHECKLIST: "36/36" da pianificato a effettivo
H5.5  Cancellazione del file password dei keystore 2b
H5.6  Sentinella di produzione: config pronta per il mainnet (RPC,
      indirizzi, invariante configurabile) — da attivare al lancio
```

---

## Tempi

```
Giorno 1     H0 (modifiche + test) → H1 deploy → H2 claim → H3.1 propose
Giorni 2-6   voto H3.2 · H4.1-H4.6 drill (con cronometro)
Giorno 6/7   queue · H4.7 scenario W (proposta ostile) in parallelo
Giorno 13/14 execute H3.2 → H3.4 poke → H5 chiusura
```

Due settimane, in parallelo alla preparazione del mainnet (dominio,
dApp, liquidità, entità). Il mainnet non parte prima di H5.
