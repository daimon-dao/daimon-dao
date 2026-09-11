# CALENDARIO DI GOVERNANCE — primo trimestre di mainnet
*Bozza del 8 settembre 2026. Ogni proposta è scritta come SCENARIO
prima di esistere: target, calldata, esito atteso, cosa vede la
sentinella, cosa succede se. Nessuna proposta parte prima che quella
che la abilita sia eseguita. Ciclo per proposta: 5 giorni di voto +
7 di timelock = ~13 giorni (queue ed execute manuali, da chiunque).*

Legenda indirizzi (mainnet, da compilare al deploy):
```
TOKEN     DaimonV2 proxy        0x…
TIMELOCK  treasury              0x…
GOVERNOR                        0x…
STAKING                         0x…
MIGRATION                       0x…
DEAD      0x000000000000000000000000000000000000dEaD
```

---

## G1 — Destinazione e quota (DUE proposte in parallelo)

**Perché**: da questo momento il 40% della quota marketing delle fee
si accumula nel Timelock. Prima nulla entra nella treasury dalle fee.

```
G1a  target TOKEN   setMarketingWallet(TIMELOCK)
G1b  target TOKEN   setStakingRewardShareBps(600)
```

**Ordine di esecuzione — VINCOLANTE**: G1a PRIMA di G1b. Se G1b fosse
eseguita per prima, il 40% partirebbe verso il marketing wallet
attuale (segnaposto del deploy), non verso la treasury. Si votano in
parallelo, si mettono in coda insieme, si eseguono nello stesso
giorno in quest'ordine, con verifica di `marketingWallet()` ==
TIMELOCK tra le due.

**Esito atteso**: `marketingWallet() == TIMELOCK`;
`stakingRewardShareBps() == 600`; al primo poke successivo, il ramo
marketing versa 60% allo staking e 40% al Timelock (evento Transfer
BNB interno / saldo del Timelock che sale).

**Sentinella**: due `ProposalCreated` (NOTIFICATION, calldata
decodificata); G1b è URGENT alla creazione per costruzione (tocca
`stakingRewardShareBps`) — atteso, si conferma a mano;
`MarketingWalletSet(TIMELOCK)` e `ParamsUpdated("stakingRewardShareBps",
600)` all'esecuzione. DOPO G1: l'invariante "marketing wallet inbound
= URGENT" si INVERTE (entrate attese sul Timelock); resta URGENT
qualsiasi uscita dal Timelock non abbinata a proposta eseguita.
→ aggiornare config del bot lo stesso giorno.

**Cosa succede se**: G1b eseguita prima di G1a → fee verso il
segnaposto: la procedura lo impedisce, e il bot lo segnalerebbe come
entrata sul marketing wallet. Guardian può cancellare entrambe entro
i 7 giorni se il pubblico solleva un'obiezione fondata.

---

## G2 — Esenzione fee della treasury

**Perché**: il Timelock non è fee-exempt; ogni DMN che ne esce
(burn di continuità, liquidità, pagamenti) pagherebbe il 4%.
Prerequisito di qualsiasi uscita di DMN.

```
G2   target TOKEN   excludeFromFee(TIMELOCK, true)
```

**Esito atteso**: `isExcludedFromFee(TIMELOCK) == true`.
**Sentinella**: `ExcludedFromFeeSet(TIMELOCK, true)` — URGENT per
tassonomia (cambio esenzioni): atteso, si conferma.
**Cosa succede se**: nessun rischio di fondi; unica conseguenza di
un'omissione è un burn inesatto in G4.

---

## G3 — Primo deposito (piccolo, in un posto solo)

**Perché**: il capitale comincia a lavorare; si prova la meccanica
con un importo che non conta.

```
G3   target vBNB (Venus)   mint()   value = X BNB   (X piccolo)
     oppure
G3'  target StakeHub       delegate(VALIDATORE, false)   value = X BNB
```

DECISO (8/9): Venus per primo — reversibile in un ciclo, senza
unbonding, una chiamata sola: è il collaudo del metodo. La delega ai
validatori come seconda tranche, per diversificare. Nessun approve
necessario (BNB nativo). Importo: una frazione del saldo, definita
nella proposta.

**Esito atteso**: saldo BNB del Timelock −X; vBNB (o credito di
delega) nel Timelock +X.
**Sentinella**: `CallScheduled` con `value` (NOTIFICATION + ETA);
all'esecuzione, USCITA dal Timelock abbinata alla proposta →
NOTIFICATION (non URGENT).
**Cosa succede se**: mercato Venus al tetto di deposito → revert,
si rifà; validatore in slashing → perdita parziale: per questo
piccolo e diversificato dopo.

---

## G4 — Il burn di continuità (dopo lo sweep)

**Prerequisiti**: finestra di migrazione chiusa (scadenza effettiva,
credito di pausa incluso) → `sweepUnclaimed()` eseguito (proposta a
sé, governance-only) → G2 eseguita.

```
G4a  target MIGRATION  sweepUnclaimed()            porta in treasury i DMN
                                                    non riscattati: i 427 mld
                                                    del progetto (mai claimati,
                                                    per scelta), l'equivalente
                                                    del dead di DMX, e quelli
                                                    dei non-migranti
G4b  target TOKEN      transfer(DEAD, X)           X = saldo del dead
                                                    address di DMX al
                                                    blocco N dichiarato
                                                    (DECISO 8/9: saldo
                                                    al blocco, reflection
                                                    incluse — verificabile
                                                    in 10 secondi)
poi, permissionless, chiunque: burnDeadBalanceToFloor()
```

**Esito atteso**: `balanceOf(DEAD)` +X, poi `totalSupply()` −X
(fino al floor). La supply di DMN riparte da dove DMX si era fermato.
**Sentinella**: uscita DMN dal Timelock abbinata a proposta →
NOTIFICATION; nessun evento di fee (G2 attiva).
**Cosa succede se**: pausa d'emergenza attiva → `burnDeadBalanceToFloor`
sospesa fino a 14 giorni, poi si chiama; X sopra il burnable → brucia
fino al floor, il resto resta al dead (esplicito nel codice).

---

## G5 — Il primo budget dell'entità

**Prerequisito**: entità costituita, indirizzo pubblicato.

```
G5   target ENTITÀ   (trasferimento BNB)   value = budget votato
     oppure BTCB.transfer(ENTITÀ, X)
```

**Esito atteso**: pagamento per lavoro svolto (opinion, audit del
modulo). Rendicontato dall'entità in pubblico.
**Sentinella**: uscita abbinata a proposta → NOTIFICATION.
**Cosa succede se**: destinatario diverso dall'indirizzo pubblicato →
il pubblico e il guardian hanno 7 giorni per fermarla.

---

## G6+ — Conversioni verso 20/40/40 (a tranche)

Ogni conversione BNB→BTCB o BNB→XAUt è una proposta con importo,
pool, e limite di slippage dichiarati; approve per l'importo esatto
nella stessa sequenza (pattern F2). Prima le pool più profonde
(BTCB/WBNB), XAUt a tranche piccole finché la liquidità su BSC resta
sottile. Nessuna conversione prima che il modulo Fase 2 esista, salvo
tranche di prova.

---

## Scenario W — la proposta che non abbiamo fatto noi

Numeri (relativi): team ~140 mld DMX personali vs top holder terzo
76,9 mld → 1,8:1 a favore del team a parità di lock; resto dei terzi
~237 mld, community unita; i 427 mld del progetto vanno in treasury
via sweep e non votano. Da solo non batte il team, ma raggiunge il
quorum (10% del potere stakato) da solo: una sua proposta PASSA se
nessuno vota No.

```
Difesa 1  il team vota su OGNI proposta, sempre, esplicitamente
          (la NOTIFICATION di ProposalCreated avvia il voto entro
          le 24 ore; scadenza: 5 giorni)
Difesa 2  se passa comunque: il guardian cancella l'operazione in
          coda (7 giorni di finestra, 36 mesi di mandato)
Difesa 3  il team staka al lancio a 365 giorni per intero: il potere
          non decade, il peso resta
```

**Cosa succede se**: proposte in serie per stancare → ciascuna va
votata No; il guardian resta l'ultima rete. Coalizione di terzi
sopra il team → l'unica difesa strutturale è il vantaggio temporale
dello staking; da monitorare ogni trimestre (quota di voto del team
vs resto, dallo snapshot delle proposte).
Da provare nel drill su Chapel: proposta "ostile" da staker3 che
passa perché nessuno vota → guardian cancella in coda.

## Regole trasversali

- Ogni proposta pubblicata con: perché, calldata decodificata,
  esito atteso, rischi. Mai una calldata che nessuno ha letto.
- Deadline e minimi dentro le calldata scritti per sopravvivere
  ai 13 giorni di attesa.
- Una proposta per ciclo salvo coppie inscindibili (G1, G4).
- La sentinella conferma ogni esito; il journal registra ogni
  proposta come la campagna Chapel.
- La politica della treasury va pubblicata PRIMA di G1.
