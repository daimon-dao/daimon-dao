# DAIMON (DMN)
## Un protocollo deflazionario senza proprietario, governato da una DAO, su BNB Chain

**Protocol paper — v0.3**
*Versione mainnet. Pubblicato in precedenza come "Protocol paper — v0.2"
(versione post-audit, 11 settembre 2026) e, prima ancora, come "Whitepaper —
Bozza v0.1". Traduzione italiana: la versione inglese è quella di
riferimento.*

---

# 1. Abstract

Daimon è un token deflazionario governato interamente da chi lo possiede,
deployato su BNB Chain. Non ha proprietario, non ha amministratore, e non ha
funzione di emissione. La sua supply totale può solo diminuire — da un valore
iniziale di 1.000 miliardi di token verso un floor immutabile di 21 miliardi,
sotto il quale il codice rende ogni ulteriore burn matematicamente impossibile.

Ogni parametro che governa il protocollo — le fee sulle transazioni, il
funzionamento dello staking, l'allocazione della tesoreria, e il codice stesso
— può essere modificato soltanto attraverso un voto on-chain seguito da un
timelock pubblico obbligatorio di sette giorni. Nessun individuo, inclusi
coloro che lo hanno costruito, detiene il potere di alterare, accelerare o
aggirare quel processo. Esiste un solo account di salvaguardia — il guardian,
un multisig 2-di-3 — e i suoi poteri sono puramente negativi: può mettere in
pausa il token in finestre di al massimo quattordici giorni che decadono da
sole, e può annullare una decisione in corso prima dell'esecuzione,
attraverso il governor o direttamente nel timelock. Ognuno di quei poteri
termina a una scadenza inamovibile, 36 mesi dopo il lancio; nulla di ciò
che ha armato sopravvive a quell'istante. Non è un impegno che chiediamo di
credere sulla parola: è una proprietà dei contratti deployati, verificabile
da chiunque in qualsiasi momento.

Chi blocca i propri token riceve potere di voto proporzionale sia alla
quantità sia alla durata del proprio impegno, insieme a reward pagati in BNB —
finanziati dall'attività di scambio reale, mai da token di nuova emissione.
Non esiste inflazione, perché non esiste alcun meccanismo in grado di
produrla.

Daimon è la migrazione di un token esistente verso la completa
decentralizzazione. Dove la versione precedente aveva un proprietario con
controllo discrezionale e una fee dell'11% sulle transazioni, il nuovo
protocollo non ha proprietario, ha una fee del 4% che solo un voto pubblico
può cambiare, e un tetto massimo scritto nel codice che nessun voto futuro
potrà superare.

I contratti sono stati auditati in modo indipendente. Il report è pubblico,
e ognuno dei suoi finding è stato corretto nel codice oppure accettato con
motivazione scritta (Sezione 10.7). Il codice auditato è stato provato
altre quattro volte con gli script di mainnet, due delle quali su una chain
pubblica in tempo reale, ed è stato deployato intatto sulla mainnet di BNB
Smart Chain il 29 settembre 2026 (Sezione 10.6). La finestra di migrazione è
aperta fino al 28 dicembre 2026 (Sezione 4.3).

Il protocollo non promette rendimenti. Garantisce regole: una scarsità che non
può essere diluita, decisioni che non possono essere prese in privato, e un
sistema che continua a funzionare esattamente come specificato, che qualcuno
lo stia sorvegliando o meno.

---

# 2. Il nome

Nella Grecia antica il *daimon* non era un demone. Era uno spirito guida — una
forza divina inferiore che abitava lo spazio tra gli dèi e i mortali, né sopra
l'umanità né sotto di essa, ma accanto.

La parola deriva da un verbo che significa *dividere*, *spartire*, *assegnare
una parte*. Il daimon era colui che assegnava il destino: non un sovrano che
lo imponeva, ma un custode che lo accompagnava.

Per i greci la felicità stessa prendeva il nome da questa relazione.
*Eudaimonia* — letteralmente, *avere un buon daimon accanto*. La vita
realizzata non era qualcosa concesso dall'alto; era il risultato di una buona
guida, ben seguita.

I filosofi lo intesero ciascuno a modo proprio, e ogni lettura conta qui:

**Socrate** descriveva il suo *daimonion* come una voce interiore che non gli
diceva mai cosa fare — solo quando fermarsi. Un freno, non un comando.
Interveniva unicamente per impedire l'errore.

**Platone**, nel Mito di Er, scrisse che sono le anime a scegliere il proprio
daimon prima di nascere. La guida non è assegnata dall'alto: è selezionata da
chi verrà guidato.

**Eraclito** lo disse nel modo più netto: *il carattere è destino* — l'indole
di una persona è il suo stesso daimon. Nulla di esterno. La guida e il guidato
sono la stessa cosa.

## 2.1 Il concetto viene prima

Questo protocollo non è stato costruito e poi battezzato. Il nome non è
un'etichetta applicata a posteriori a un sistema finito, e la corrispondenza
descritta qui sotto non è una coincidenza notata in retrospettiva.

Il concetto di daimon è ciò che ha prodotto il progetto. Ogni decisione
architetturale — cosa il protocollo può fare, cosa deve rifiutarsi di fare,
dove è collocata l'autorità e dove è deliberatamente assente — è stata presa
contro quell'idea. Il codice è il concetto scritto in Solidity.

Le tre letture sopra non sono decorazione. Ciascuna corrisponde a una
proprietà specifica dei contratti deployati.

## 2.2 Socrate — la guida che trattiene invece di comandare

Il *daimonion* non diceva mai a Socrate cosa fare. Interveniva solo per
fermarlo. Un segnale negativo: non direzione, ma freno.

```solidity
if (block.timestamp < op.readyTimestamp) revert TooEarly();
```

Il timelock non contiene alcuna logica su cosa costituisca una buona
decisione. Non approva, non consiglia, non valuta, non migliora. Non ha
opinioni sulla proposta che gli passa attraverso. Il suo intero contributo è
un rifiuto condizionato dal tempo.

La governance decide. Il timelock impedisce soltanto che qualcosa accada più
in fretta di quanto possa essere esaminato. È un freno, e nient'altro — che è
l'unica forma di autorità nel sistema a operare senza un voto.

## 2.3 Platone — la guida è scelta, prima che sorga la questione

Nel Mito di Er le anime scelgono il proprio daimon *prima* di nascere. La
guida non è assegnata da un potere superiore; è scelta da chi verrà guidato, e
scelta in anticipo.

```solidity
votingPowerAt(voter, proposal.snapshotBlock)
```

Il potere di voto è valutato all'ultimo blocco sigillato *prima* che la
proposta fosse creata, non nel momento del voto. L'influenza su una decisione
deriva da un impegno preso prima che quella decisione esistesse come
questione.

L'effetto pratico è che il potere non può essere acquisito in reazione a
qualcosa che è già on-chain: quando una proposta atterra, il blocco di
snapshot alle sue spalle è già sigillato, e l'influenza comprata dopo — anche
nello stesso identico blocco — non conta nulla. La scelta precede la
questione — che è precisamente ciò che Platone descriveva, e precisamente ciò
che uno snapshot impone.

## 2.4 Eraclito — la guida e il guidato sono la stessa cosa

*Il carattere è destino.* Per Eraclito il daimon non era affatto esterno:
l'indole di una persona è il suo stesso daimon. Non esiste un'entità separata.

```
GOVERNANCE_ROLE  →  DaimonTimelock
                    (nessun altro detentore, in nessun contratto)
```

Non esiste alcuna autorità sopra il protocollo. Nessun proprietario, nessun
amministratore, nessun consiglio, nessuna fondazione, nessun indirizzo che
possa agire sul sistema dall'esterno. L'unico ruolo che esiste è detenuto da
un contratto che non fa nulla se non eseguire ciò che la community ha già
deciso.

Ciò che chi detiene sceglie è ciò che il protocollo diventa. Non perché
promettiamo di rispettare le sue decisioni, ma perché non esiste alcun
meccanismo attraverso cui qualcuno potrebbe non rispettarle. Il carattere
della community è il destino del sistema — e l'assenza di qualsiasi altra
autorità è ciò che rende quell'affermazione strutturale invece che
aspirazionale.

## 2.5 Cosa ne consegue

Tre proprietà, tre letture, un concetto: un'autorità che spartisce invece di
accumulare, trattiene invece di comandare, ed è scelta invece che imposta.

Tutto il resto di questo documento è l'elaborazione di quell'idea in
meccanismi specifici. Dove i due sono mai entrati in conflitto durante lo
sviluppo, ha vinto il concetto — anche quando ha reso il lavoro
considerevolmente più difficile, come descrive la Sezione 4.5.

---

# 3. Il problema

## 3.1 Un token con un proprietario è una promessa, non un sistema

La maggior parte dei token viene deployata con un account amministrativo — il
*proprietario* — che mantiene funzioni privilegiate. A seconda
dell'implementazione, il proprietario può cambiare le fee, congelare i
trasferimenti, escludere indirizzi dai limiti, prelevare fondi accumulati e in
molti casi emettere nuovi token. Queste capacità non sono nascoste: sono
scritte nel contratto, visibili a chiunque lo legga.

La questione non è se tali poteri esistano. È cosa si frappone tra quei poteri
e il loro abuso.

In quasi ogni caso, la risposta è: le intenzioni del proprietario. Nient'altro.
Nessuna procedura, nessun ritardo, nessun obbligo di annuncio, nessun modo per
chi detiene di obiettare prima che accada. Il modello di sicurezza si riduce a
una frase che compare, in qualche forma, in migliaia di progetti: *fidatevi di
noi*.

Non è una critica all'onestà di un team in particolare. È un'osservazione
sulla struttura. Un sistema la cui sicurezza dipende dalla buona fede
continuativa di una singola chiave privata non è un sistema sicuro — è una
scommessa su una persona. Le chiavi si perdono. Gli account vengono
compromessi. Le persone cambiano idea, subiscono pressioni, o commettono
errori alle tre di notte. E una scommessa che paga in modo affidabile per due
anni resta una scommessa.

## 3.2 La stessa struttura, su scala più grande

Il modello non è esclusivo del crypto. È il modello del sistema finanziario in
cui la maggior parte delle persone già vive.

Decisioni che determinano il valore dei risparmi delle persone comuni —
quanta valuta emettere, quali commissioni applicare, quali condizioni
modificare e quando — vengono prese da istituzioni che non consultano chi ne è
colpito, non annunciano i cambiamenti in anticipo, e li spiegano dopo in un
linguaggio costruito per scoraggiare l'esame. I depositanti non sono
partecipanti; sono la materia trattata. L'asimmetria informativa non è un
effetto collaterale del sistema: ne è una caratteristica.

L'inflazione è l'esempio più chiaro. Non è un fenomeno naturale. È una
decisione, presa da un numero ristretto di persone, il cui effetto è ridurre
il valore dei risparmi detenuti da tutti gli altri. Non richiede consenso, non
offre possibilità di sottrarsi, e raramente viene descritta per ciò che è.

Il crypto avrebbe dovuto essere l'alternativa. Eppure un token il cui
proprietario può cambiare le regole a piacimento ha semplicemente riprodotto
la stessa struttura con un budget più piccolo: un'autorità opaca, decisioni
discrezionali, e partecipanti che lo scoprono dopo.

## 3.3 Cosa richiede l'alternativa

Un'alternativa autentica non può basarsi su intenzioni migliori. Deve rendere
le azioni problematiche strutturalmente impossibili.

Concretamente significa:

- **Nessuna funzione di emissione.** Non disattivata — assente. La diluizione
  non può essere votata, non può essere abilitata da un aggiornamento, non può
  essere introdotta da nessuno in nessuna circostanza, perché il codice per
  eseguirla non esiste.

- **Nessun account privilegiato.** Dopo il deploy, nessun wallet esterno
  detiene diritti amministrativi sul protocollo. Non chi ha fatto il deploy,
  non il team, non alcun individuo.

- **Nessun cambiamento silenzioso.** Ogni modifica passa da una proposta
  pubblica, un voto con una soglia minima di partecipazione, e un ritardo
  obbligatorio abbastanza lungo perché chiunque possa leggere cosa sta per
  accadere e agire di conseguenza.

- **Nessun parametro illimitato.** Persino la community, votando all'unanimità,
  non può alzare le fee sopra un tetto fissato nel codice, né bruciare la
  supply sotto il floor. Il sistema limita la propria stessa governance.

- **Nessuna fiducia richiesta.** Ogni affermazione in questo documento
  corrisponde a codice pubblico, deployato e verificabile. Nulla di ciò che è
  scritto qui chiede di essere creduto.

Daimon è un tentativo di costruire esattamente questo, e di farlo per una
community esistente: non come un nuovo lancio, ma come la migrazione di un
token che aveva già un proprietario verso un sistema che non ne ha.

## 3.4 Una nota sul metodo

Questo documento contiene una critica al potere finanziario concentrato. Non
contiene alcuna chiamata all'azione oltre una: leggete il codice.

Esiste una forma di dissenso che consiste nel chiedere a chi comanda di
comportarsi diversamente. Ne esiste un'altra che consiste nel costruire
qualcosa che non ne abbia bisogno. Questo progetto appartiene alla seconda.
Non perché la prima sia illegittima, ma perché un'alternativa funzionante è un
argomento più duraturo di una protesta — e perché un sistema che elimina il
bisogno di fiducia non può essere convinto a cambiare idea.

Il resto di questo documento descrive come, e — altrettanto importante — dove
sono i limiti.

---

# 4. Da DMX a DMN

## 4.1 Cosa c'era prima

Daimon non è nato come protocollo decentralizzato. È nato come DMX
(`0x36EbA94407B53c631eE822C219e94580fadd67c7`), un reflection token su BNB
Chain con la struttura comune a quella categoria: un account proprietario con
diciassette funzioni amministrative, e una fee dell'11% sulle transazioni.

| | DMX (precedente) |
|---|---|
| Fee reflection | 4% |
| Fee marketing | 5% |
| Fee buyback | 2% |
| **Fee totale** | **11%** |
| Tetto massimo fee | **nessuno** |
| Proprietario | sì, ownership mai rinunciata |
| Chi decide | il proprietario, con effetto immediato |
| Floor di supply | nessuno |
| Riduzione della supply | nessuna — vedi 4.1.2 |
| Staking | nessuno |
| Governance | nessuna |

Questa sezione non è scritta come un'accusa. DMX è il nostro lavoro
precedente, e la struttura descritta qui era il pattern standard della sua
generazione. È documentata precisamente perché la community che possiede quei
token merita di sapere esattamente da cosa sta migrando — e perché diverse di
queste proprietà non sono visibili senza leggere il sorgente.

### 4.1.1 Parametri senza limiti

I valori delle fee non erano fissati nel codice. Erano parametri del
costruttore, modificabili in seguito da tre funzioni setter:

```solidity
function setTaxFee(uint256 taxFee) external onlyOwner() {
    _taxFee = taxFee;
}
```

Un'assegnazione secca. Nessun `require`, nessun limite superiore, nessun
ritardo, nessun annuncio. Il proprietario poteva impostare qualsiasi fee a
qualsiasi valore, incluso il 100%, con effetto dalla transazione successiva.

Lo stesso vale per la dimensione massima delle transazioni. Deployata allo
0,3% della supply, era allo 0,15% — 1,5 miliardi di DMX — quando è stata
letta on-chain l'11 settembre 2026: il proprietario l'aveva dimezzata a un
certo punto usando un setter senza limite inferiore. Il 29 settembre 2026,
perché qualsiasi posizione potesse migrare in una sola transazione, il
proprietario l'ha portata all'intera supply (transazione
`0xfaef2123e54dd4d5054b9195284d43576e35c5161e178ae5e8b810f9b620b47b`,
18:53:34 UTC; valore riletto al blocco 127.195.880 il 12 ottobre 2026). Lo
stesso setter avrebbe potuto portarla a un wei, il che avrebbe reso il token
di fatto intrasferibile. Nulla nel codice impediva né l'una né l'altra cosa.

### 4.1.2 Il burn che non bruciava

DMX non aveva una funzione di burn. Aveva un buyback che comprava token sul
mercato e li inviava all'indirizzo morto `0x…dEaD`.

La distinzione non è semantica. I token inviati a un indirizzo non spendibile
sono economicamente distrutti ma restano nella contabilità:

| | DMX, on-chain (26 luglio 2026) | DMX, on-chain (12 ottobre 2026, blocco 127.195.880) |
|---|---|---|
| `totalSupply()` | 1.000.000.000.000 — invariata dal deploy | 1.000.000.000.000 — ancora invariata |
| Detenuti dall'indirizzo morto | 30.058.718.442 (3,0058%) | 30.961.537.947 (3,0962%) |
| Circolante | 969.941.281.557 | 969.038.462.053 |

Il saldo dell'indirizzo morto continua a crescere, perché il meccanismo di
buyback è tuttora attivo; entrambe le letture sono fotografie. La supply totale
non è una fotografia — non è mai diminuita di un solo wei. Qualsiasi metrica derivata da
`totalSupply()` — la capitalizzazione di mercato tra queste — era calcolata su
una cifra che sovrastimava i token esistenti.

Non è una peculiarità di DMX; è il modo in cui la maggior parte dei reflection
token di quella generazione gestiva il burn. DMN separa i due passaggi: i
token vengono inviati all'indirizzo morto, e una seconda funzione
permissionless rimuove davvero quel saldo da `totalSupply()`, limitata dal
floor.

### 4.1.3 Rinuncia all'ownership, reversibile

Il contratto include una funzione che vale la pena descrivere per intero,
perché il suo aspetto e il suo effetto divergono:

```solidity
function lock(uint256 time) public virtual onlyOwner {
    _previousOwner = _owner;
    _owner = address(0);              // sembra rinunciata
    _lockTime = block.timestamp + time;
}

function unlock() public virtual {
    require(_previousOwner == msg.sender, ...);
    require(block.timestamp > _lockTime, ...);
    _owner = _previousOwner;          // se la riprende
}
```

Dopo aver chiamato `lock()`, `owner()` restituisce l'indirizzo zero. Su
qualsiasi block explorer questo è indistinguibile da una rinuncia permanente —
il segnale più comunemente citato come prova che un progetto non possa essere
alterato dai suoi creatori. È temporaneo, e il proprietario precedente può
riprendersi il controllo alla scadenza del timer.

Questa funzione non è mai stata usata su DMX (`getUnlockTime()` restituisce
zero, e l'ownership non è mai stata rinunciata). È documentata qui perché il
pattern è diffuso, e perché chi valuta un qualsiasi token dovrebbe sapere che
`owner() == 0x0` non è, di per sé, prova di nulla.

### 4.1.4 Cosa DMX non aveva — detto con equità

Diversi poteri comunemente presenti in token di questo tipo sono assenti da
DMX, e la precisione richiede di dirlo:

- **Nessuna funzione di emissione.** Nessuna. La supply era fissata al deploy
  e non poteva essere espansa da nessuno. Su questo punto il contratto era già
  solido.
- **Nessuna pausa e nessuna blacklist.** Il proprietario non poteva congelare
  i trasferimenti né bloccare indirizzi specifici.
- **Nessuna funzione di prelievo o recupero.** Il proprietario non poteva
  estrarre fondi arbitrari detenuti dal contratto.

Il problema di DMX non è mai stato che potesse essere svuotato. Era che la sua
economia dipendeva interamente dalla discrezione di un account, senza limiti,
senza ritardo, e senza obbligo di informare nessuno.

Un ultimo dettaglio completa il quadro. DMX invia la fee marketing a **due**
wallet. `marketingAddress1` è il proprietario stesso:
`0xF8EC459CAEaF1052b64B38BDD67290B0c132B0Ae`, un account esterno senza
codice, la cui ownership non è mai stata rinunciata — `owner()` lo
restituisce ancora, letto l'11 settembre 2026 al blocco 121.166.526 e di
nuovo il 12 ottobre 2026 al blocco 127.195.880.
`marketingAddress2` è `0x41B533AF0Db427dc97988B47f86383f42372f395`. Il 7%
di ogni trasferimento che non va in reflection è diviso in settantesimi: 25
a ciascun wallet marketing e 20 al buyback — il 2,5% a ciascun wallet, il 2%
al buyback. Chi controlla i parametri è quindi anche un destinatario diretto
delle entrate che controlla. Nulla di questo era nascosto — è visibile
on-chain a chiunque guardi — ma è esattamente la concentrazione che la nuova
architettura è progettata per eliminare. Entrambi i wallet detengono DMX;
cosa ne sarà di quei token è dichiarato nella Sezione 11.5.

Il 29 settembre 2026 il proprietario ha usato due di queste funzioni
amministrative un'ultima volta, per aprire la migrazione: ha alzato il
limite per transazione all'intera supply (4.1.1), e ha escluso la tesoreria
della migrazione — il timelock, Sezione 11 — dalla fee di DMX (transazione
`0x8aaac289174a13a61040a68503550d79b31cdc25e1884686e8a42632f04cd54d`,
20:06:24 UTC), le due impostazioni senza le quali un claim 1:1 non può
essere esatto (Sezione 4.3). Per l'intera finestra di migrazione il
proprietario è vincolato a non revocare nessuna delle due, né a bloccare,
rinunciare o trasferire l'ownership che le tiene in vigore; il registro di
lancio dichiara la regola.

### 4.1.5 Su come si è arrivati a questo

DMX è stato il nostro apprendistato. L'abbiamo costruito con le conoscenze che
avevamo allora, seguendo i pattern che erano standard per quella generazione
di token — pattern condivisi da centinaia di progetti, inclusi molti con team
finanziati e audit pubblicati.

Quello che è seguito è stato un periodo di studio, e questo protocollo è ciò
che ne è uscito. La migrazione esiste perché la risposta onesta a comprendere
un limite non è difenderlo.

Vale la pena notare cosa DMX *non* ha ereditato da quei template: nessuna
funzione di emissione, nessuna pausa, nessuna blacklist, nessun meccanismo di
prelievo. Le quattro capacità più spesso usate per estrarre valore da chi
detiene erano assenti già dalla prima versione. Il giudizio c'era prima del
vocabolario.

La nuova versione non tenta di difendere quella struttura. La sostituisce con
una migliore.

## 4.2 Cosa la sostituisce

| | DMX (precedente) | DMN (nuovo) |
|---|---|---|
| Fee reflection | 4% | 1% |
| Fee marketing | 5% | 2% — ripartita tra staker e tesoreria da una quota stabilita dalla governance: 100% agli staker al lancio, 60/40 dopo il primo voto su mainnet (Sezione 11) |
| Fee buyback | 2% | 1% |
| **Fee totale** | **11%** | **4%** |
| **Tetto massimo fee** | **nessuno** | **10%, imposto nel codice** |
| Proprietario | sì, mai rinunciato | **nessuno, strutturalmente** |
| Chi decide | il proprietario, subito | voto on-chain + timelock 7 giorni |
| Modifica parametri | istantanea, non annunciata | 13 giorni minimo, interamente pubblica |
| Emissione | non possibile | non possibile |
| Riduzione supply | token spostati, supply invariata | **supply realmente ridotta** |
| Floor di supply | nessuno | **21B, immutabile** |
| Esclusione da reflection | modificabile dal proprietario | **insieme immutabile, fissato al deploy: dead address e pair di liquidità** |
| Protezione slippage | nessuna — accetta qualsiasi output | limitata rispetto al quote del router stesso — non un limite alla perdita MEV |
| Destinatario marketing | due wallet, uno dei quali è il proprietario | impostato dalla governance — il timelock stesso, cioè la tesoreria (Sezione 11) |
| Staking | nessuno | vote-escrow, reward in BNB |
| Governance | nessuna | governance on-chain completa |

Tre punti meritano enfasi.

**La riduzione delle fee non è la parte importante.** Le fee possono essere
modificate da qualsiasi progetto in qualsiasi momento; un numero più basso non
dimostra nulla su come ci si sia arrivati. Ciò che conta è dove vive il
numero e chi può toccarlo. Il codice auditato inizializza le fee a 10/20/20
— reflection 1%, buyback 2%, marketing 2%, un totale del 5%. La
configurazione di lancio le ha portate a 10/10/20 — il 4% qui sopra — nella
fase 2 del deploy su mainnet, il 29 settembre 2026 (transazione
`0x0e486b53cf9f2b65f34ec78a150e9f814e32c8e2044b1849943e336af102bcca`),
attraverso il ruolo di governance temporaneo che il deployer deteneva
durante la configurazione, prima che quel ruolo venisse consegnato al
timelock e revocato; la verifica post-broadcast ha riletto i tre valori
dalla chain minata, e al blocco 127.195.880, il 12 ottobre 2026, leggevano
lo stesso. Nessuno scambio era ancora avvenuto: la pool ha ricevuto la sua
liquidità due ore e mezza più tardi.
Da quel momento nessun singolo account può cambiarle di nuovo:
l'unica via è un voto pubblico seguito da un timelock di sette giorni. La
prima volta che quella via è stata percorsa — la proposta #0, su testnet,
che ha portato le fee dal 5% al 4% — è documentata con ogni hash di
transazione nella Sezione 9.

**Il tetto conta più del valore attuale.** Il codice rifiuta qualsiasi fee
totale superiore al 10%. Non è una politica che la governance possa rivedere:
è un'istruzione `require` nel contratto. Anche se ogni possessore di token
votasse a favore, la transazione fallirebbe. La conseguenza pratica è che DMN
non potrà mai diventare costoso da scambiare quanto DMX lo è oggi,
indipendentemente da chi controllerà il protocollo tra dieci anni.

**La riga sulla riduzione della supply è la meno ovvia e la più
consequenziale.** In DMX i token del buyback si accumulavano all'indirizzo
morto mentre `totalSupply()` restava per sempre al valore di deploy. In DMN
una funzione permissionless rimuove davvero quel saldo dal totale — fino al
floor e non oltre. La supply riportata è la supply.

## 4.3 Come funziona la migrazione

La migrazione è uno scambio 1:1 senza fee e senza pressione temporale oltre
una finestra prefissata. Su mainnet la finestra è di 90 giorni dal deploy
del contratto di migrazione: `migrationDeadline` è 1798420124 — il 28
dicembre 2026 alle 01:08:44 UTC — un valore immutabile letto dal contratto.
I claim sono diventati possibili il 29 settembre 2026 alle 20:06:24 UTC,
quando il proprietario di DMX ha escluso la tesoreria della migrazione dalla
fee di DMX (Sezione 4.1.4), quindi la finestra effettiva è di poche ore
inferiore ai 90 giorni. Una pausa del guardian, se mai avverrà, estende la
scadenza esattamente del tempo di pausa (Sezione 8.6).

Al deploy, l'intera supply iniziale di 1.000 miliardi di DMN viene creata
dentro il contratto di migrazione. Non in un wallet del team, non in una
tesoreria, non in un contratto di distribuzione — dentro il contratto che
esiste unicamente per scambiare vecchi token con nuovi. Nessuna allocazione è
riservata a fondatori, advisor o investitori privati, perché non esiste alcuna
allocazione da riservare.

Il processo per chi detiene è in tre passaggi:

1. **Approvazione** — si autorizza il contratto di migrazione a ricevere una
   quantità specificata di token legacy.
2. **Claim** — il contratto prende i token legacy e restituisce esattamente lo
   stesso numero di DMN. Nessuna fee viene applicata in nessuna delle due
   direzioni.
3. **Fatto** — i token legacy vengono trasferiti alla tesoreria della DAO, non
   distrutti.

Ogni claim è un trasferimento di token che esistevano già. Nulla viene
emesso. La supply totale di DMN non cambia di un solo wei durante l'intera
migrazione, e questo è verificabile on-chain in qualsiasi momento. Al
blocco 127.195.880 (12 ottobre 2026), al tredicesimo giorno della finestra,
`totalMigrated` leggeva 341.306.088.146,86 DMX — il 34,1% della vecchia
supply, inclusa la quota della liquidità iniziale della Sezione 11.5 — e la
supply totale di DMN leggeva esattamente 1.000.000.000.000.

## 4.4 Cosa succede ai token mai riscattati

Non tutti migreranno. I wallet vengono abbandonati, le chiavi si perdono, gli
annunci non vengono letti. Una porzione della supply resterà nel contratto di
migrazione alla chiusura della finestra.

Quei token non vengono bruciati automaticamente, e non diventano proprietà di
nessuno. Restano bloccati nel contratto di migrazione finché la DAO non decide
diversamente — e quella decisione richiede il ciclo di governance completo:
una proposta, un voto, un timelock di sette giorni, e un'esecuzione che
chiunque può innescare.

La funzione che esegue questo trasferimento, `sweepUnclaimed()`, ha tre
vincoli scritti dentro di sé:

- può essere chiamata solo dal timelock, ovvero solo come risultato di un voto
  approvato;
- fallisce se chiamata prima che la scadenza della migrazione sia passata;
- può inviare i token a un solo indirizzo — la tesoreria — il cui indirizzo è
  `immutable`, fissato al deploy e immodificabile da chiunque, governance
  inclusa.

C'è un dettaglio che vale la pena dichiarare apertamente, perché altrimenti
verrebbe scoperto e contestato: il contratto di migrazione è un possessore di
token come gli altri, e quindi accumula reflection dai normali trasferimenti
durante la finestra di migrazione. Il saldo trasferito alla tesoreria sarà
leggermente superiore alla quantità non riscattata. È il meccanismo di
reflection che funziona come progettato, e il surplus segue lo stesso percorso
del resto — alla DAO, deciso dal voto.

Due posizioni resteranno quasi per intero non riscattate, per decisione e non
per caso: i token legacy del progetto stesso, detenuti nei due wallet
marketing di DMX descritti in 4.1.4 — circa il 42% della vecchia supply
prima del lancio, il 39,7% dopo l'unico claim che hanno fatto (11.5 dà le
cifre datate). I wallet del progetto hanno riscattato solo la quota della
liquidità iniziale, prima che si aprisse la finestra di migrazione, e i
token LP di quella liquidità sono andati al timelock in una transazione
pubblicata. Tutto il resto resta non riscattato: i DMN corrispondenti
raggiungono la tesoreria attraverso `sweepUnclaimed()` come ogni altro token
non riscattato, e non votano. La Sezione 11.5 dichiara l'impegno, e ciò che
è stato fatto, per intero.

## 4.5 Perché una migrazione invece di rinunciare all'ownership

Una domanda ragionevole: se l'obiettivo era rimuovere il proprietario, perché
non chiamare semplicemente `renounceOwnership()` sul contratto esistente?

Perché rinunciare all'ownership su DMX avrebbe prodotto un token che nessuno
poteva cambiare — incluso un token che nessuno poteva correggere, migliorare o
governare. La fee sarebbe rimasta congelata all'11% per sempre. Non ci
sarebbe stato staking, né voto, né alcun modo per chi detiene di decidere
alcunché. Il risultato non è decentralizzazione; è abbandono.

Decentralizzazione significa che le decisioni vengono prese collettivamente,
non che le decisioni diventano impossibili. Questo richiede un sistema di
governance, un timelock, un meccanismo di staking per pesare la
partecipazione, e contratti progettati attorno all'assenza di un
amministratore dalla prima riga. Nulla di tutto ciò poteva essere aggiunto a
posteriori al contratto esistente.

La migrazione è il costo di farlo come si deve.

---

# 5. Architettura

## 5.1 Cinque contratti

Il protocollo è composto da cinque contratti, ciascuno con una responsabilità
circoscritta.

**DaimonV2** — il token. Implementa l'interfaccia ERC-20 con ridistribuzione
delle fee basata su reflection, il ciclo di buyback e burn, e il floor
immutabile di supply. Deployato dietro un proxy UUPS, aggiornabile solo
attraverso la governance.

**DaimonStaking** — lo staking vote-escrow. Detiene i token bloccati, calcola
il potere di voto in funzione di quantità e durata del lock, mantiene i
checkpoint storici di quel potere, e distribuisce i reward in BNB in modo
proporzionale.

**DaimonGovernor** — il motore di governance. Accetta proposte da chi detiene
oltre una soglia, gestisce il periodo di voto, valuta il quorum contro uno
snapshot preso alla creazione della proposta, e mette in coda nel timelock le
proposte approvate.

**DaimonTimelock** — il ritardo obbligatorio. Trattiene ogni decisione
approvata per sette giorni prima che possa essere eseguita, ed è l'unico
account con l'autorità di chiamare le funzioni privilegiate sugli altri
contratti. Si amministra da sé: nessun account esterno può modificarne i
parametri o i ruoli.

**DaimonMigration** — lo scambio 1:1. Detiene la supply iniziale, converte i
token legacy su richiesta, e può trasferire l'eventuale residuo non riscattato
alla tesoreria dopo la scadenza, solo su istruzione del timelock.

## 5.2 Dove sta l'autorità

La distribuzione dell'autorità è la proprietà che più vale la pena verificare
in modo indipendente, quindi è dichiarata qui per intero.

**Nessun contratto ha un proprietario.** Non c'è ereditarietà da `Ownable`,
non c'è `owner()`, non c'è alcun modificatore `onlyOwner` in nessun punto del
protocollo. Il controllo degli accessi è basato su ruoli, e dopo il deploy
esiste esattamente un detentore di ruolo:

```
GOVERNANCE_ROLE  →  detenuto da DaimonTimelock, e da nient'altro
```

Chi ha fatto il deploy non detiene alcun ruolo. Non è una questione di
intenzioni: il deploy è avvenuto in due fasi il 29 settembre 2026, e i suoi
script hanno rinunciato a ogni ruolo detenuto temporaneamente durante la
configurazione, poi hanno verificato — con trenta controlli separati
distribuiti sulle due fasi, ognuno dei quali avrebbe interrotto il deploy —
che nessun account esterno mantenesse autorità su alcun contratto. Poiché
un'asserzione dentro uno script di deploy prova lo stato simulato e non
quello minato, una verifica autonoma ha poi riletto trentasei invarianti
dalla chain viva: 36 su 36 superati al blocco 124.627.634, prima che
esistesse qualsiasi liquidità (Sezione 10.6). Lo stesso script, in una
modalità post-lancio con un trentasettesimo controllo per la finestra
aperta, può essere rieseguito da chiunque contro la chain viva; i ruoli del
deployer sono stati riletti il 12 ottobre 2026 al blocco 127.224.280 —
nessuno, su alcun contratto.

Di conseguenza, cambiare le fee, cambiare il wallet marketing, cambiare il
contratto di staking, aggiungere un'opzione di lock, trasferire i token di
migrazione non riscattati, o aggiornare l'implementazione del token sono tutte
operazioni che possono avvenire solo al termine di questa sequenza:

```
proposta → 1 giorno di attesa → 5 giorni di voto → quorum raggiunto
         → coda → 7 giorni di timelock → esecuzione
```

L'esecuzione stessa è permissionless: una volta trascorso il timelock,
qualsiasi indirizzo può innescarla. La decisione l'ha presa il voto;
l'esecuzione è meccanica.

## 5.3 Le due eccezioni

Due elementi si collocano fuori da questa struttura, ed entrambi sono
deliberati.

**Indirizzi immutabili.** L'indirizzo morto (destinazione dei token bruciati)
e la tesoreria della migrazione — il timelock stesso, legato nel costruttore
del contratto di migrazione — sono fissati al deploy e non possono essere
cambiati da nessuno — né da chi ha fatto il deploy, né dalla governance, né da
un aggiornamento. Alcune destinazioni non dovrebbero essere reindirizzabili,
nemmeno da una maggioranza.

**Il guardian.** Un account — su mainnet un multisig Safe,
`0x37F45839765AD3418E29c97d5D92407Ddbf5c7a8`, con tre firmatari e una
soglia di due, le chiavi detenute da persone diverse — detiene un insieme
ristretto di poteri difensivi, fuori dal ciclo di governance. Tre,
precisamente. Può mettere in
pausa il token in caso di emergenza, per al massimo quattordici giorni per
attivazione, dopo i quali la pausa decade da sola. Può annullare una
proposta di governance in corso attraverso il governor, il che annulla
atomicamente anche l'operazione già programmata nel timelock che ne deriva.
E può annullare un'operazione programmata direttamente nel timelock — una
seconda via che non dipende dall'integrità del governor. Non può cambiare
le fee, muovere fondi, alterare i parametri di governance, emettere token o
aggiornare alcunché, e non può eseguire: ognuno dei suoi poteri è un freno,
mai un motore. Esiste perché nella prima fase di vita di un protocollo
sette giorni di timelock sono una risposta troppo lenta a un exploit in
corso.

Ogni potere del guardian scade nello stesso istante, 36 mesi dopo il lancio:
timestamp 1885252112, il 28 settembre 2029 alle 01:08:32 UTC. Non è un
impegno a rinunciarvi; è un unico valore, calcolato dal token al momento del
deploy e copiato tale e quale nel governor e nel timelock nella seconda fase
del deploy — letto identico dai tre contratti al blocco 127.195.880 — che
nessuno, governance inclusa, può rimuovere o posticipare. Dopo quella data
la pausa ed entrambe le vie di
annullamento del guardian smettono di funzionare, e qualsiasi pausa ancora
armata è già decaduta. Resta esattamente un modo per annullare
un'operazione in coda: il timelock che annulla una propria operazione, e
solo una chiamata a sé stesso può innescarlo — cioè una proposta di
governance eseguita, mai una singola parte. La decentralizzazione si
completa senza la collaborazione di nessuno.

La Sezione 8.6 descrive i vincoli del guardian per intero.

## 5.4 I contratti deployati

BNB Smart Chain, chain id 56. I contratti sono stati deployati il 29
settembre 2026 da un deployer che non detiene alcun ruolo; ogni transazione
di deploy, con il suo blocco e la sua rilettura, è nel registro di lancio
(Sezione 10.6). Verificate un indirizzo on-chain prima di interagirvi: un
documento si può copiare, un contratto no.

| Contratto | Indirizzo |
|---|---|
| DMN — il token (`DaimonV2`, proxy UUPS) | `0x160864F9945C52063A7c9f5dcd57C0C89eacbE6a` |
| Implementazione di DMN dietro il proxy | `0xA7bC2D4D35e49bdfC8329e3673d7De520832941c` |
| `DaimonMigration` — da DMX a DMN, 1:1 | `0x76368b60514b145617385847aCFF7b7EA9764725` |
| `DaimonStaking` | `0xBb596e7308D6C5AED55cEC597D372840Cbe575b1` |
| `DaimonGovernor` | `0x1397a7d25595B718BE6FEEDd42ed5E60F66E16De` |
| `DaimonTimelock` — la tesoreria; detiene i token LP | `0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891` |
| Pair PancakeSwap v2 DMN/WBNB — la pool di lancio | `0x40A97Ae210a44057603186B4BE92BAe719342AFA` |
| Guardian — multisig Safe, 2 di 3, fino al 28 settembre 2029 | `0x37F45839765AD3418E29c97d5D92407Ddbf5c7a8` |
| DMX — il predecessore (Sezione 4.1) | `0x36EbA94407B53c631eE822C219e94580fadd67c7` |
| Indirizzo morto — destinazione dei token bruciati | `0x000000000000000000000000000000000000dEaD` |

I sette contratti del deploy — il proxy del token, la sua implementazione,
il contratto di migrazione, il contratto di staking, il governor, il
timelock, e il seeder di liquidità monouso della Sezione 11.3 — sono stati
verificati su Sourcify e BscScan il giorno del lancio, corrispondenza esatta
del bytecode di creazione e di runtime; l'intervallo auditato `audit-final`
e il sorgente deployato sono lo stesso codice (Sezione 10.7).

---

# 6. Tokenomics

## 6.1 Supply

La supply iniziale è di 1.000.000.000.000 DMN — mille miliardi di token, con
18 decimali. Questo numero è stato fissato al deploy e non può mai aumentare.

La ragione per cui non può mai aumentare non è una politica. **Non esiste una
funzione di emissione nel contratto.** Non disattivata, non protetta da
permessi, non riservata alla governance: assente. Nessuna sequenza di voti,
nessun aggiornamento, nessuna chiave compromessa e nessuna decisione futura
può produrre un singolo token aggiuntivo, perché il codice in grado di
produrlo non esiste.

La supply può muoversi in una sola direzione: verso il basso.

## 6.2 Il floor

Il burn è limitato. Il contratto definisce una supply minima immutabile di
21.000.000.000 DMN — ventuno miliardi — sotto la quale bruciare è
matematicamente impossibile.

```
SUPPLY INIZIALE   1.000.000.000.000 DMN
                          │
                          ▼  (burn, una sola direzione)
                          │
FLOOR                21.000.000.000 DMN   ← non attraversabile
```

La funzione di burn verifica questo limite prima di eseguire e si ferma
esattamente al floor: se un burn portasse la supply sotto i 21 miliardi, viene
bruciata solo la porzione che raggiunge il floor, e il resto no. Chiamata
nuovamente in seguito, la funzione non esegue alcuna operazione.

Questo tetto alla deflazione esiste per una ragione pratica. Una supply che
può avvicinarsi a zero prima o poi si rompe: i limiti di divisibilità, il
comportamento degli arrotondamenti e la liquidità degradano tutti man mano che
il conteggio dei token collassa. Il floor è il punto in cui il protocollo
smette di ridursi e inizia a operare in una modalità diversa — descritta in
6.6.

**Il floor è un limite, non una destinazione.** Nulla garantisce che la
supply raggiungerà mai i 21 miliardi, e una forza lavora in silenzio contro:
i wallet perduti. I token le cui chiavi sono andate perse restano parte
della supply totale. Continuano ad accumulare reflection, quindi il loro
saldo cresce; non possono mai essere venduti, quindi il buyback non può mai
comprarli; non possono mai essere mossi, quindi nessuno può bruciarli. Col
tempo la quota di supply che il burn può davvero raggiungere si riduce
mentre quella irraggiungibile si accumula — e se abbastanza token finissero
in wallet inaccessibili, il burn si fermerebbe da qualche parte sopra i 21
miliardi, permanentemente al di qua del floor.

Nessuna funzione esiste per intervenire, e nessuna potrebbe essere aggiunta,
per costruzione: un contratto capace di togliere token a un indirizzo che
non controlla non sarebbe più senza padrone — deterrebbe esattamente il
potere che questo progetto esiste per rimuovere. Bitcoin convive con la
stessa asimmetria: milioni di BTC giacciono in wallet perduti, quello di
Satoshi incluso, e nessuno ha mai seriamente proposto di recuperarli, perché
il rimedio sarebbe peggiore della perdita. Ciò che il floor garantisce
resta intatto in ogni caso: il burn non può mai portare la supply sotto i 21
miliardi. Quanto ci si avvicini è una questione di storia del mercato, non
di codice.

## 6.3 Fee sulle transazioni

Ogni trasferimento applica una fee, il 4% dell'importo trasferito dal lancio,
suddivisa in tre componenti:

| Componente | Quota | Destinazione |
|---|---|---|
| Reflection | 1% | ridistribuita a tutti i possessori |
| Buyback & burn | 1% | accumulata, poi usata per comprare e bruciare |
| Marketing / tesoreria | 2% | convertita in BNB; ripartita tra il pool reward dello staking e la tesoreria da una quota stabilita dalla governance — 100% agli staker al lancio, 60/40 dopo il primo voto su mainnet |
| **Totale** | **4%** | |

Tre proprietà strutturali contano più dei numeri attuali.

**Il tetto.** Il contratto rifiuta qualsiasi configurazione in cui la fee
totale superi il 10%. È imposto da un'istruzione `require`, non da una
politica. Una proposta che impostasse le fee all'11% supererebbe il voto,
aspetterebbe il timelock, e poi fallirebbe all'esecuzione. La governance è
limitata dal codice che governa.

**Chi può cambiarle.** Solo il timelock, ovvero solo l'esito di un ciclo di
governance completato. Il 4% è la configurazione di lancio, impostata il
29 settembre 2026 nella seconda fase del deploy, prima che il ruolo
temporaneo del deployer venisse revocato (Sezione 4.2), e in vigore dal
primo scambio: il registro di lancio la verifica al wei sul primo acquisto e
sulla prima vendita che la pool abbia mai visto. Il primo ciclo di
governance nella storia di Daimon ha portato le fee dal 5% del codice
auditato a questo stesso 4%, su testnet, e il suo registro completo compare
nella Sezione 9. Su mainnet nessuna proposta era stata creata al blocco
127.195.880 (12 ottobre 2026).

**Zero è legale — ed è un cambio di modello, non una regolazione.**
L'intervallo ha un tetto e nessun minimo: la governance può portare ogni fee
a zero. Farlo spegne quasi tutto ciò che le fee alimentano. La reflection si
ferma; nessun nuovo BNB si accumula; buyback, burn, reward di staking ed
entrate della tesoreria si esauriscono una volta speso l'inventario già
raccolto; e finché le fee restano a zero, il floor dei 21 miliardi della 6.2
è fuori portata per sempre. Ciò che resterebbe è un token liberamente
trasferibile con una governance funzionante e uno staking ridotto a puro
peso di voto. La decisione è reversibile per la stessa via che l'ha presa —
un voto successivo può ripristinare qualsiasi totale fino al 10% — e tredici
giorni di processo pubblico separano la proposta dal suo effetto: tempo
sufficiente per accorgersene, se qualcuno guarda. Esiste una configurazione
in cui lo zero ha senso: un protocollo che abbia già un'altra fonte di
entrate può azzerare le fee di trasferimento per rimuovere attrito senza
spegnere nulla. Quella fonte deve esistere prima — azzerare le fee non la
crea.

## 6.4 Reflection

La componente reflection ridistribuisce l'1% di ogni trasferimento a tutti i
possessori, proporzionalmente al loro saldo, senza che sia necessaria alcuna
transazione per riscuoterla.

Meccanicamente, i saldi sono memorizzati in un'unità di conto interna invece
che direttamente in token. Ogni trasferimento tassato riduce il totale di
quell'unità interna, il che aumenta il numero di token che ciascuna unità
rappresenta. Il saldo di ogni possessore cresce senza che avvenga alcun
trasferimento — la ridistribuzione è un cambiamento nel tasso di conversione,
applicato simultaneamente a tutti.

La conseguenza pratica è che detenere token produce un lento accumulo
finanziato dall'attività di scambio, senza alcuna azione richiesta e senza
pagare gas.

Due indirizzi sono esclusi dalla reflection, entrambi fissati
all'inizializzazione del token. Il primo è l'indirizzo morto che riceve i
token bruciati: escluderlo impedisce che la supply bruciata accumuli
ridistribuzione, il che gonfierebbe la cifra apparente del burn. I token
contati come bruciati sono bruciati; nulla viene aggiunto a quel numero dal
meccanismo stesso. Il secondo è la pair di liquidità: una pair il cui saldo
cresce passivamente mentre le riserve registrate restano ferme è una pair il
cui surplus chiunque può intascare chiamando `skim()` — valore sottratto ai
possessori a cui la reflection era destinata (finding #30 dell'audit).

Non esistono altre esclusioni, e non esiste alcuna funzione per crearne. È una
scelta strutturale deliberata: la capacità di inserire e togliere indirizzi
dalla reflection a runtime è stata storicamente la fonte dei più gravi
fallimenti contabili nei reflection token. Quell'intera classe di fallimenti è
assente qui perché la capacità è assente.

## 6.5 Il ciclo di burn

Il burn non è programmato, annunciato, o innescato da qualcuno in
particolare. È una conseguenza dell'attività di scambio.

```
1.  Avvengono scambi → le fee si accumulano come DMN nel contratto

2.  Quando le fee accumulate superano una soglia, un qualsiasi
    trasferimento diretto di DMN alla pair di liquidità — basta un
    wei, inviato da chiunque — fa vendere al contratto una tranche
    pari alla soglia, al massimo una per blocco → riceve BNB

3.  Il BNB viene suddiviso:
        quota marketing  →  pool reward dello staking / tesoreria,
                            per una quota stabilita dalla governance
                            (100% agli staker al lancio, 60/40 dopo
                            il primo voto)
        quota buyback    →  trattenuta nel contratto

4.  Sullo stesso innesco, quando il BNB trattenuto supera una
    soglia, il contratto compra DMN sul mercato aperto e li invia
    all'indirizzo morto — al massimo una fetta per blocco

5.  burnDeadBalanceToFloor() rimuove quel saldo dalla supply totale
    — permanentemente, e al massimo fino al floor
```

Il passaggio 5 è **permissionless**: qualsiasi indirizzo può chiamarlo,
senza alcun ruolo speciale. Nessuno può forzarlo oltre il floor, ed
esattamente una cosa può ritardarlo: la funzione rispetta la pausa di
emergenza del guardian — una scelta deliberata, perché scrive la stessa
contabilità della supply che chi risponde a un incidente vorrebbe congelata.
Durante una finestra di pausa armata il burn attende, al massimo quattordici
giorni per finestra; altrimenti nessuno può impedirlo, e una volta terminato
il mandato di 36 mesi del guardian, niente potrà più metterlo in pausa. La
funzione non ha un chiamante privilegiato perché non ne ha bisogno — il suo
unico effetto possibile è
ridurre la supply verso un limite fissato nel codice.

I passaggi 2 e 4 scattano su un innesco permissionless e usano la pool di
liquidità pubblica. Le vendite ordinarie attraverso il router,
deliberatamente, **non** li innescano: il router calcola i propri importi da
un'istantanea delle riserve della pool, e far girare gli swap del protocollo
dentro quella finestra permetterebbe di prezzare male un deposito di
liquidità (finding #1 dell'audit). L'innesco è quindi un semplice
trasferimento di DMN alla pair — chiunque può inviare un wei per far
avanzare il ciclo, e budget per blocco limitano l'aggregato indipendentemente
da chi chiama e quanto spesso. Se nessuno innesca, le fee si accumulano
finché qualcuno non lo fa: nulla si perde e nulla si blocca. Gli swap sono
protetti da un limite di slippage e incapsulati in modo che uno swap fallito
non possa bloccare i trasferimenti: se le condizioni di mercato rendono uno
swap sfavorevole, viene saltato e ritentato all'innesco successivo invece di
far fallire la transazione del chiamante.

Su mainnet i passaggi da 1 a 3 sono girati per la prima volta il 29
settembre 2026, alle 05:04:08 UTC, dentro la transazione descritta nella
Sezione 10.4: 200.000.000 DMN di inventario di fee sono stati venduti per
0,081248 BNB, due terzi notificati al contratto di staking e un terzo
trattenuto per il buyback. Il passaggio 4 attende che i BNB trattenuti
superino 1 BNB, e ogni innesco ne spende poi il 5%; al blocco 127.195.880
(12 ottobre 2026) non era ancora scattato, e l'indirizzo morto deteneva
0 DMN. Il passaggio 5 non ha quindi avuto finora nulla da rimuovere.

## 6.6 Cosa succede al floor

Se il burn portasse mai la supply totale a 21 miliardi, lì si fermerebbe
permanentemente. Non riprende, e nessun voto può riavviarlo.

A quel punto la componente buyback non ha più una destinazione che riduca la
supply. Il progetto del protocollo specifica che le entrate precedentemente
destinate al burn vengono reindirizzate interamente agli staker — il
meccanismo passa dal ridurre la supply al distribuire rendimento, in modo
automatico, sulla base di un controllo sulla supply e non di una decisione.

È uno scenario lontano e — come spiega la 6.2 — non garantito. È descritto
qui perché un protocollo dovrebbe specificare il proprio stato terminale,
non perché quello stato sia promesso.

---

# 7. Staking

## 7.1 Lock e peso

Lo staking in Daimon è vote-escrow: i token vengono bloccati per una durata
scelta, ed entrambi — potere di voto e quota di reward — sono pesati da quella
durata.

| Periodo di lock | Moltiplicatore |
|---|---|
| 30 giorni | 1× |
| 90 giorni | 1,5× |
| 180 giorni | 2,2× |
| 365 giorni | 4× |

Il potere di voto è l'importo bloccato moltiplicato per il peso del periodo.
Un milione di DMN bloccati per un anno pesa quanto quattro milioni bloccati
per un mese.

L'intenzione è esplicita: **l'influenza dovrebbe seguire l'impegno, non solo
il capitale.** Chi accetta un anno di illiquidità ha dimostrabilmente più in
gioco nel futuro del protocollo di chi può uscire in trenta giorni, e la
pesatura lo riflette.

I token bloccati non possono essere ritirati prima della scadenza del lock.
Non esiste uscita anticipata, né opzione con penale, né override
amministrativo. L'impegno è il meccanismo; renderlo reversibile ne
cancellerebbe il significato.

## 7.2 Reward in BNB

I reward dello staking sono pagati in **BNB**, mai in DMN.

È una conseguenza del design della supply più che una preferenza. Senza
funzione di emissione, reward denominati in DMN potrebbero provenire soltanto
da una riserva pre-allocata — che prima o poi si esaurirebbe, e che avrebbe
richiesto di detenere un grosso saldo controllato dal team fin dal primo
giorno. Nessuna delle due cose era accettabile.

I reward provengono quindi dalla quota marketing delle fee sulle
transazioni. Il protocollo converte quella quota in BNB e ne deposita una
parte stabilita dalla governance nel pool reward dello staking — tutta al
lancio, il 60% da quando il primo voto su mainnet indirizza il restante 40%
alla tesoreria (Sezione 11) — dove viene distribuita tra gli staker in
proporzione al potere di voto.

Ne derivano tre proprietà:

- **Nessuna inflazione.** Nessun token viene creato per pagare nessuno. Il
  pool reward è finanziato da attività di scambio già avvenuta.
- **Nessuna pressione di vendita.** Uno staker che riscuote riceve BNB, non
  DMN. Riscuotere non mette mai token sul mercato.
- **Valore esterno.** I reward sono denominati nell'asset nativo della chain,
  il cui valore non dipende da Daimon.

L'effetto combinato è che lo staking rimuove token dalla circolazione
restituendo valore che non deve essere rivenduto sullo stesso mercato.

I reward maturano continuamente e si riscuotono su richiesta. Se dei reward
arrivano in un momento in cui nessun token è in staking, vengono accantonati
in una riserva dedicata invece di andare persi — recuperabile solo con una
decisione esplicita della governance, e mai ripiegata silenziosamente in una
distribuzione successiva, dove il primo staker ad arrivare avrebbe potuto
catturarli.

## 7.3 Checkpoint del potere di voto

Il contratto di staking non registra solo il potere di voto attuale. Ne
registra la storia.

Ogni cambiamento — un nuovo lock, un ritiro — scrive un checkpoint indicizzato
per numero di blocco. Questo permette al contratto di governance di porre una
domanda specifica: *qual era il potere di voto di questo indirizzo al blocco
sigillato appena prima che la proposta N fosse creata?*

È ciò che impedisce l'attacco alla governance più evidente. Senza checkpoint
storici, un attore potrebbe osservare una proposta che non gli piace,
acquisire e mettere in staking una posizione ingente, e votarla contro con
potere acquistato dopo che la questione è stata sollevata. Con i checkpoint,
il voto viene risolto contro lo snapshot di un blocco già sigillato: il
potere acquisito in seguito — anche nello stesso blocco della proposta — non
conta nulla.

Lo abbiamo testato specificamente, con un attaccante simulato che deteneva una
posizione schiacciante messa in staking subito dopo la creazione di una
proposta. Il suo potere di voto allo snapshot era zero, e il voto è stato
rifiutato — come progettato.

## 7.4 Una scelta di design: il potere di voto non decade

Nel modello vote-escrow introdotto da Curve Finance, il potere di voto decade
linearmente man mano che il lock si avvicina alla scadenza. Un lock di quattro
anni conferisce peso pieno il primo giorno e peso zero a maturità; mantenere
influenza richiede di ri-bloccare continuamente.

**Daimon non implementa il decadimento.** Il potere di voto è fissato al
momento dello staking e resta costante fino al ritiro, anche dopo la scadenza
del lock.

È una divergenza deliberata, e ha una conseguenza reale che va dichiarata
apertamente: chi blocca a 4×, aspetta la fine dell'anno e non ritira mai
mantiene peso di voto pieno a tempo indefinito pur avendo la possibilità di
uscire in qualsiasi momento. L'influenza può concentrarsi tra gli staker
storici di lungo periodo invece di seguire l'impegno presente.

Accettiamo questo compromesso per tre ragioni. È più semplice e prevedibile —
il potere di voto è un numero che chi detiene può comprendere senza
ricalcolarlo a ogni blocco. Premia la fedeltà dimostrata invece di richiedere
un re-impegno perpetuo. Ed evita l'attrito di un meccanismo che penalizza chi
detiene proprio mentre si avvicina alla fine di un impegno che ha onorato.

Un modello con decadimento non è escluso per sempre. Sarebbe una riprogettazione
significativa, e se la community concludesse che è preferibile, può essere
introdotto attraverso lo stesso processo di governance che regola tutto il
resto. La scelta è documentata qui invece di essere scoperta dopo.

## 7.5 Limiti

Due vincoli si applicano allo staking e sono dichiarati per completezza.

Una singola transazione di staking è limitata dalla dimensione massima di
transazione del token (0,5% della supply), un limite anti-dump che si applica
a tutti i trasferimenti. Posizioni molto grandi devono essere messe in staking
in più transazioni.

Il contratto di staking è escluso automaticamente dalle fee quando viene
registrato, quindi mettere e togliere dallo staking non comporta la fee del
4%. Questa esclusione si applica al contratto stesso, non a un individuo, ed è
impostata dalla stessa funzione riservata alla governance che registra il
contratto.

---

# 8. Governance

## 8.1 Il ciclo

Ogni modifica al protocollo segue lo stesso percorso. Non ci sono scorciatoie,
non ci sono procedure d'emergenza che lo aggirino, e non ci sono account
esenti.

```
PROPOSTA          chiunque detenga sopra la soglia di proposta
     │            invia un contratto target e una chiamata codificata
     ▼
1 GIORNO          nulla può essere votato immediatamente
     │            il potere di voto viene fotografato alla creazione
     ▼
5 GIORNI DI VOTO  Sì / No / Astensione, pesati dal potere di voto
     │            detenuto allo snapshot
     ▼
QUORUM            deve partecipare almeno il 10% del potere di voto
     │            totale (Sì + Astensioni — vedi 8.3)
     ▼
CODA              la chiamata approvata entra nel timelock
     ▼
7 GIORNI          ritardo pubblico obbligatorio, 604.800 secondi esatti
     │            nessuno può accorciarlo
     ▼
ESECUZIONE        permissionless — qualsiasi indirizzo può innescarla
```

Tempo minimo dalla proposta all'effetto: **tredici giorni**. Non è una
comodità. È la finestra in cui chiunque — un possessore, un ricercatore, un
giornalista, un avversario — può leggere cosa sta per accadere e agire prima
che accada.

## 8.2 Il potere di voto allo snapshot

I voti sono pesati dal potere di voto detenuto **nel momento in cui la
proposta è stata creata**, non nel momento del voto.

Questa singola proprietà chiude l'attacco più diretto a qualsiasi governance
pesata sui token: osservare una proposta, acquisire una posizione ingente, e
votare con influenza acquistata specificamente per decidere quella questione.
Con il voto su snapshot, i token messi in staking dopo che una proposta esiste
hanno peso zero su di essa.

Il meccanismo è un checkpoint storico scritto a ogni modifica della posizione
in staking di un possessore. Il contratto di governance interroga quella
storia invece dello stato presente.

## 8.3 Cosa conta per il quorum

Il quorum è misurato come somma dei voti **a favore e di astensione**, contro
il 10% del potere di voto totale allo snapshot. I voti contrari contano nel
determinare l'esito, ma non nel raggiungere il quorum.

Questa distinzione non è estetica, e non era nella nostra implementazione
originale. Durante i test avversariali abbiamo scoperto che conteggiare i voti
contrari nel quorum produceva un incentivo perverso: una minoranza contraria a
una proposta poteva, votando contro, fornire la partecipazione necessaria a
validare il voto — e quindi far passare la proposta. Restare in silenzio era
strettamente più efficace che votare no.

Abbiamo riprodotto lo scenario in un test, lo abbiamo confermato, e abbiamo
cambiato il calcolo per allinearlo allo standard OpenZeppelin, che esclude i
voti contrari dal quorum esattamente per questa ragione. Il finding, la
correzione e il test che dimostra il comportamento corretto sono tutti nel
repository pubblico.

Una proposta che nessuno sostiene ora fallisce per mancato raggiungimento del
quorum — che è l'esito corretto, e non richiede a nessuno di sconfiggerla
attivamente.

## 8.4 Limiti alla governance stessa

Un sistema in cui la maggioranza può fare qualsiasi cosa non è più sicuro di
un sistema in cui una persona può fare qualsiasi cosa; è solo più lento.
Diversi vincoli sono quindi posti al di sopra della governance, nel codice,
dove nessun voto può raggiungerli:

| Vincolo | Valore | Chi può cambiarlo |
|---|---|---|
| Fee totale massima | 10% | **nessuno** |
| Supply minima (floor) | 21 miliardi | **nessuno** |
| Quorum minimo | 10% | **nessuno** |
| Ritardo minimo del timelock | 7 giorni | **nessuno** |
| Indirizzo morto | fissato al deploy | **nessuno** |
| Tesoreria della migrazione (il timelock) | fissata al deploy | **nessuno** |
| Capacità di emissione | non esiste | **nessuno** |

Una proposta che violasse uno di questi supererebbe il voto, aspetterebbe il
timelock, e fallirebbe all'esecuzione. Il protocollo rifiuta le istruzioni che
è stato costruito per rifiutare.

## 8.5 Cosa può fare la governance

Entro quei limiti, la DAO controlla completamente il protocollo:

- modificare la ripartizione e il totale delle fee (fino al tetto)
- cambiare il destinatario della quota di fee destinata alla tesoreria, e
  la ripartizione tra staker e tesoreria
- cambiare il contratto di staking
- aggiungere o disabilitare opzioni di lock dello staking
- modificare le soglie operative (innesco degli swap, tolleranza allo
  slippage, dimensione massima delle transazioni)
- trasferire alla tesoreria i token di migrazione non riscattati dopo la
  scadenza
- **aggiornare l'implementazione del token stesso**

L'ultimo punto merita enfasi. Il token è deployato dietro un proxy UUPS, e la
funzione di autorizzazione dell'aggiornamento è riservata al timelock. Questo
significa che il protocollo può evolvere — ma solo attraverso il ciclo
pubblico completo, e mai a discrezione di un individuo. Significa anche che la
community porta una responsabilità reale: un aggiornamento è lo strumento più
potente del sistema, e il ritardo di sette giorni esiste perché uno cattivo
possa essere visto arrivare.

## 8.6 Il guardian

Un account detiene un piccolo insieme di poteri fuori dal ciclo di
governance, tutti difensivi. Il guardian è un multisig 2-di-3 — su mainnet
il Safe della Sezione 5.4: tre chiavi detenute da persone diverse, due delle
quali devono firmare. Detiene esattamente tre autorità. Può **mettere in
pausa il contratto**. Può
**annullare una proposta di governance attraverso il governor** — un
annullamento incrociato atomico che invalida anche l'operazione nel
timelock di una proposta già in coda. E può **annullare un'operazione
programmata direttamente nel timelock**, una seconda via che non dipende
dall'integrità del governor. Questo è l'intero raggio della sua autorità:
freni, mai un motore.

Non può cambiare le fee, muovere fondi, alterare i parametri di governance,
emettere token, aggiornare, proporre o votare. Può fermare i trasferimenti
per una finestra limitata e può impedire l'esecuzione di una specifica
azione di governance; nient'altro.

Esiste per una ragione precisa: nella prima fase di vita di un protocollo,
sette giorni di timelock non sono un tempo di risposta praticabile a un
exploit in corso — e una proposta malevola colta in volo ha bisogno di un
interruttore più rapido di una contro-proposta. Il guardian è l'allarme
antincendio, non un posto al tavolo.

Quattro vincoli lo definiscono:

**Una pausa è una finestra, non un interruttore.** Attivare la pausa la arma
per al massimo quattordici giorni — abbastanza da coprire un intero ciclo di
risposta della governance — e poi decade da sola, senza bisogno di alcuna
transazione. Tenere il token in pausa richiede di rinnovare attivamente la
finestra, e ogni rinnovo è un atto pubblico e visibile. Una chiave persa o
un guardian silente non possono lasciare il protocollo congelato.

**Tutto scade, in un solo istante.** Tutte e tre le autorità — la pausa ed
entrambi i percorsi di annullamento — terminano 36 mesi dopo il lancio: il
28 settembre 2029 alle 01:08:32 UTC, timestamp 1885252112. La scadenza è un
timestamp che il token ha calcolato al deploy; il governor e il timelock,
deployati in una seconda fase, hanno ricevuto quello stesso valore riletto
dalla chain, quindi le tre copie sono identiche per costruzione —
riverificate on-chain dopo il deploy, lette di nuovo identiche al blocco
127.195.880, e modificabili da nessuno, governance inclusa. Dopo di essa,
nuove pause ed entrambi i percorsi di annullamento
del guardian vengono rifiutati, e qualsiasi pausa ancora armata è già
decaduta. Da quel momento una sola cosa può annullare un'operazione in
coda: il timelock stesso, con una chiamata a sé stesso — vale a dire una
proposta di governance eseguita, tredici giorni pubblici e un voto di
maggioranza, mai una singola parte. Ciò che supera il voto e il timelock,
viene eseguito.

**Non può costare agli holder la migrazione.** Ogni secondo di pausa è
accreditato alla scadenza della migrazione: se una pausa blocca i claim, la
finestra di claim si estende esattamente del tempo bloccato. La censura può
ritardare lo scambio; non può consumarlo.

**È visibile.** Mettere in pausa, rinnovare una pausa e annullare sono
eventi on-chain. Non c'è modo di usare questi poteri in silenzio.

Il guardian è un compromesso temporaneo con la realtà, limitato nel raggio,
limitato nel tempo, e progettato per scomparire senza richiedere la
collaborazione di nessuno.

---

# 9. Caso di studio: Proposta #0

Ogni affermazione della Sezione 8 descrive un comportamento previsto. Questa
sezione descrive cosa è realmente accaduto quando il sistema è stato usato.

Quello che segue è il registro completo della prima decisione presa dalla DAO
di Daimon, eseguita su BSC testnet. Ogni passaggio è una transazione pubblica.

## 9.1 La decisione

**Proposta #0 — ridurre le fee totali dal 5% al 4%** (reflection 1%, buyback
1%, marketing 2%).

La proposta è stata creata da un possessore, ha come target il contratto del
token, e codifica una chiamata a `setFees(10, 10, 20)`. Nulla nella sua
creazione ha richiesto un permesso.

La sua descrizione on-chain recita:

> *"Riduzione fee totale al 4% (tax 1%, buyback 1%, marketing 2%)"*

Il testo è in italiano e compare non tradotto in tutta l'interfaccia, inclusa
la versione inglese. Le descrizioni delle proposte sono contenuto on-chain
scritto dal proponente e immutabile una volta inviato; tradurle
nell'interfaccia romperebbe la corrispondenza tra ciò che un utente legge e
ciò che la blockchain contiene. Ciò che viene mostrato è byte per byte ciò che
è stato registrato.

## 9.2 La cronologia

Tutti gli orari in UTC. Ogni valore qui sotto è letto dallo stato del
contratto, non dalla documentazione di progetto.

| Fase | Timestamp | UTC |
|---|---|---|
| Creata — potere di voto fotografato | `1783467501` | 7 lug 2026, 23:38:21 |
| Voto aperto (dopo 1 giorno di attesa) | `1783553901` | 8 lug 2026, 23:38:21 |
| Voto espresso — 3.000.000 a favore | | 9 lug 2026, 22:36:42 |
| Voto chiuso (dopo 5 giorni) | `1783985901` | 13 lug 2026, 23:38:21 |
| Messa in coda nel timelock | `1783991100` | 14 lug 2026, 01:05:00 |
| **Eseguibile da** | `1784595900` | **21 lug 2026, 01:05:00** |
| **Eseguita** | | **21 lug 2026, 01:11:09** |

Risultato: 3.000.000 di potere di voto a favore, 0 contrari, 0 astenuti,
contro un quorum richiesto di 300.000. Stato finale: **Eseguita**.

L'intervallo tra la messa in coda e l'eseguibilità è di 604.800 secondi —
sette giorni, al secondo.

Transazioni:

| Azione | Hash |
|---|---|
| Proposta | `0xa6e465fb70da2b587f8ab7795a22cfc7c29bc984d571020260178b6af2cb5035` |
| Voto | `0x90e22db141f83b1b9fb004faaabde852da721b55856594122c1f0cf9564e1480` |
| Coda | `0x3d5adeac84a205edd963af483de98bd0f40be0491532ed4dc9b0f2418fee2920` |
| Esecuzione | `0x5aa519a9884d24037f0cb903f3565f1a9e5e87529e5d4c1baa3f0c054302fe5f` |

Il ciclo completo è pubblico. Nulla di questa decisione è avvenuto fuori dalla
catena.

Tutte e quattro sono state inviate dallo stesso indirizzo. Le transazioni di
proposta, voto e coda occupano i nonce 6, 8 e 9 nella sequenza di quel wallet
— l'ordine che il protocollo richiede, con il voto correttamente collocato tra
le altre due.

## 9.3 La parte che conta di più

Il 17 luglio — quattro giorni prima che l'esecuzione fosse possibile —
abbiamo tentato di eseguire la proposta.

È stato un errore umano: uno sbaglio sulla data, commesso da persone che
avevano costruito il sistema e ne conoscevano precisamente il funzionamento.
Abbiamo eseguito un controllo di coerenza prima di firmare, e ha restituito la
ragione per cui il tentativo sarebbe fallito:

```
readyTimestamp   21 lug 2026, 01:05:00 UTC
ora attuale      17 lug 2026, 08:34:44 UTC
mancano          318.613 secondi  (3 giorni, 16,5 ore)
```

Se avessimo proceduto comunque, la transazione sarebbe fallita con `TooEarly`.
Il contratto non distingue tra un'esecuzione anticipata malevola e una
confusa; le rifiuta identicamente.

Questo è l'intero argomento a favore di un timelock, dimostrato invece che
affermato. Non esiste perché diffidiamo delle cattive intenzioni. Esiste
perché le buone intenzioni non bastano — le persone perdono il filo delle
date, lavorano alle tre di notte, e sono certe di cose sbagliate. Il sistema
no.

Quattro giorni dopo, l'esecuzione è riuscita sei minuti dopo l'apertura della
finestra. Non un secondo prima, perché non era possibile.

## 9.4 Verifica del risultato

Il cambiamento delle fee è stato confermato su due livelli indipendenti.

**Stato del contratto**, letto direttamente:
```
taxFee        = 10   →  1%   (reflection)
buybackFee    = 10   →  1%   (buyback & burn)
marketingFee  = 20   →  2%   (marketing / operativo)
                        ────
                        4%
```

**Comportamento economico**, misurato su un trasferimento reale di 1.000.000
DMN:

| | Importo |
|---|---|
| Inviati | 1.000.000,000000 DMN |
| Fee applicata | **40.000,000000 DMN — esattamente il 4,00%** |
| Ricevuti | 960.000,000000 DMN |
| Variazione della supply totale | zero |

Prima dell'esecuzione lo stesso trasferimento avrebbe comportato una fee di
50.000 DMN. Il ciclo di governance non ha semplicemente aggiornato un valore
memorizzato: ha cambiato il modo in cui il token si comporta, ed è misurabile
al wei.

## 9.5 La proposta non può essere eseguita due volte

Chiamare `execute(0)` di nuovo restituisce:

```
execution reverted: 0x0dc10197   →   AlreadyExecuted()
```

Il controllo è la prima istruzione della funzione, prima di qualsiasi altra
logica. Una transazione firmata e pagata fallirebbe identicamente.
L'interfaccia non offre alcun pulsante per farlo, perché lo stato "eseguita"
non ha azioni disponibili.

## 9.6 Una proposta fallita

La proposta #1 è stata creata deliberatamente come test e deliberatamente non
votata da nessuno.

Al termine del suo periodo di voto di cinque giorni aveva zero voti, non ha
raggiunto il quorum, e il suo stato è diventato **Bocciata** —
automaticamente, senza alcuna transazione richiesta e senza che nessuno
agisse per respingerla.

È l'esito che volevamo osservare on-chain. In un sistema senza potere di veto,
una proposta senza sostegno non ha bisogno di essere fermata. Scade.

## 9.7 Cosa dimostra questo registro

Tra queste due proposte, ogni stato della macchina di governance è stato
osservato con transazioni reali: In attesa, In votazione, Approvata, In coda,
Eseguita, e Bocciata. I percorsi di rifiuto — esecuzione prima della scadenza
del timelock, ed esecuzione di una proposta già eseguita — sono stati
entrambi innescati ed entrambi respinti.

Il registro completo, inclusi gli hash di ogni passaggio, è pubblicato in
`TESTNET_RESULTS.md` nel repository del progetto.

---

# 10. Sicurezza

## 10.1 Modello di minaccia

La sicurezza comincia dal nominare gli avversari. Sono considerati i seguenti
attori, con ciò che ciascuno può e non può fare.

**Un attaccante esterno.** Può chiamare qualsiasi funzione pubblica, in
qualsiasi ordine, in qualsiasi momento, con qualsiasi importo. Non può
acquisire un ruolo amministrativo, perché nessuno è assegnabile:
`GOVERNANCE_ROLE` amministra sé stesso e non esiste un `DEFAULT_ADMIN_ROLE`
attraverso cui potrebbe essere concesso.

**Una whale.** Può accumulare una posizione ingente e metterla in staking per
il peso massimo. Non può votare su alcuna proposta creata prima del suo
staking, perché il potere di voto è valutato contro uno snapshot storico. Non
può superare la dimensione massima di transazione in un singolo trasferimento.

**La governance stessa.** Può cambiare ogni parametro operativo e aggiornare
l'implementazione del token. Non può emettere, non può bruciare sotto il
floor, non può alzare le fee sopra il 10%, non può abbassare il quorum sotto
il 10% o il timelock sotto i sette giorni, non può reindirizzare l'indirizzo
morto o la tesoreria della migrazione. Il protocollo limita la propria stessa
governance.

**Il guardian** — un multisig 2-di-3 (Sezione 5.4). Può mettere in pausa il contratto in
finestre di quattordici giorni che decadono da sole, annullare una proposta
attraverso il governor, e annullare un'operazione in coda direttamente nel
timelock. Non può toccare fondi, parametri o esecuzione — e ognuno di questi
poteri termina alla stessa scadenza di 36 mesi, dopo la quale qualsiasi
pausa ancora armata è già decaduta e solo una chiamata della governance a sé
stessa può annullare.

**Chi ha fatto il deploy.** Poteva deployare i contratti e pagare il gas.
Ha detenuto un ruolo di governance temporaneo durante la seconda fase del
deploy, usato per la configurazione di lancio e revocato nello stesso
broadcast. Non detiene alcun ruolo in seguito: gli script di deploy hanno
rinunciato a ogni permesso temporaneo e poi verificato, con trenta
asserzioni distribuite sulle due fasi del deploy e una verifica di
trentasei controlli riletti dalla chain viva, che nessun account esterno
mantenesse autorità in alcun punto del sistema. Su mainnet l'ultima
transazione del deployer è stata il contratto monouso di seeding della
liquidità della Sezione 11.3; da allora non ha firmato nulla, e al blocco
127.224.280 (12 ottobre 2026) non deteneva alcun ruolo su alcun contratto.

Il modello di minaccia completo, incluso il ragionamento dietro ogni
conclusione, è pubblicato come `THREAT_MODEL.md` nel repository.

## 10.2 Cosa è stato testato

Il protocollo porta 203 test automatici, tutti superati: i 180
dell'intervallo auditato `audit-final`, nelle sei categorie qui sotto, e 23
aggiunti dopo l'audit per gli strumenti di lancio fuori da quell'intervallo
— il contratto monouso di seeding della liquidità della Sezione 11.3 e il
limite per transazione del predecessore come lo incontra la migrazione.

**I test unitari** coprono le singole funzioni e i loro limiti.

**I test di sequenza di governance** verificano che nessun ordinamento di
operazioni produca un'esecuzione senza un voto approvato, una coda completata
e un timelock trascorso.

**I test di fuzzing** eseguono ogni proprietà contro 512 input casuali: che i
trasferimenti non creino mai token, che lo staking conceda esattamente il
potere di voto pesato, che il ritiro restituisca il capitale 1:1, che la
migrazione sia esattamente 1:1, che i reward non superino mai i BNB
depositati, che le fee non possano mai essere impostate sopra il tetto.

**I test di invarianza** sono basati su handler: un driver martella il sistema
con sequenze casuali di azioni — 16.384 chiamate per invariante — mentre le
seguenti condizioni devono valere a ogni passo:

- la supply totale non supera mai quella iniziale e non scende mai sotto il
  floor
- il potere di voto totale eguaglia la somma dei lock attivi, ed eguaglia la
  somma dei poteri di voto individuali
- la contabilità della migrazione è conservata
- il saldo dei reward eguaglia i depositi meno le riscossioni
- nessun ruolo amministrativo è acquisibile da alcun attore

**I test avversariali** attaccano il sistema come farebbe un avversario:
manipolazione dello snapshot, valori limite estremi (un wei, l'intera supply,
il floor esatto, un secondo prima della scadenza del timelock), e incentivi di
teoria dei giochi.

**I test di regressione dell'audit** riproducono i finding dell'audit
corretti nel codice. Ciascuno asserisce il comportamento sicuro, quindi
falliva sul codice pre-correzione e passa sull'intervallo auditato: una
regressione verrebbe colta dal test che ha riprodotto il finding originale.

L'analisi statica viene eseguita con Slither. Ogni finding di severità alta e
media è stato esaminato e documentato — con il relativo ragionamento — come
falso positivo in questo contesto oppure come condizione già mitigata; la
classificazione è pubblicata in `THREAT_MODEL.md`. I suggerimenti di hardening
a bassa severità sono stati applicati al codice.

## 10.3 Cosa abbiamo trovato noi stessi

Due finding sono emersi dal nostro giro avversariale, quando il codice era per
il resto completo. Entrambi sono documentati qui perché una sezione sulla
sicurezza che riporta solo successi non è una sezione sulla sicurezza.

**Finding 1 — I voti contrari contavano nel quorum.** Come descritto in 8.3,
questo creava un incentivo perverso: opporsi a una proposta poteva aiutarla a
passare. Lo abbiamo riprodotto in un test, poi abbiamo cambiato il calcolo del
quorum per contare solo Sì + Astensioni, allineandolo allo standard
OpenZeppelin. Corretto prima che lo scope dell'audit fosse congelato.

**Finding 2 — Il potere di voto non decade dopo la scadenza del lock.**
Descritto in 7.4. È una conseguenza di design più che un difetto: l'influenza
può concentrarsi tra gli staker storici di lungo periodo. Lo abbiamo accettato
e documentato invece di correggerlo, perché un meccanismo di decadimento è una
riprogettazione e non una correzione. Resta aperto a una futura decisione di
governance.

## 10.4 Limiti noti

I seguenti sono proprietà del sistema che consideriamo accettabili ma che chi
legge dovrebbe conoscere. Nessuna di esse è nascosta nel codice.

**Esposizione residua al MEV.** Gli swap automatici sono protetti da un limite
di slippage, che riduce ma non elimina gli attacchi sandwich. Eliminare
completamente l'esposizione richiederebbe un oracolo di prezzo ponderato nel
tempo; il limite è il compromesso scelto.

**Aggiornabilità.** Il token può essere aggiornato dalla governance. È una
capacità, e le capacità comportano rischi: un aggiornamento dannoso approvato
da una maggioranza è possibile in linea di principio. Il timelock di sette
giorni esiste perché una proposta simile sia visibile per una settimana prima
di poter avere effetto.

**Polvere di arrotondamento.** I calcoli di reflection e reward usano
divisioni intere, lasciando importi di pochi wei non attribuiti. Lo abbiamo
misurato precisamente durante la distribuzione dei reward su testnet: su tre
riscossioni, il residuo era di due wei, ciascuno attribuibile a una divisione
con troncamento. È contabilizzato, non ignorato.

**Dipendenza dal router.** Gli swap automatici dipendono dal router
PancakeSwap. Se quel contratto fosse compromesso o la pool di liquidità
prosciugata, il meccanismo di swap degraderebbe. Gli swap sono incapsulati in
modo che un fallimento non possa bloccare i trasferimenti ordinari.

**Il percorso meno provato.** La sequenza accumulo fee → swap in BNB →
distribuzione → buyback automatico è stata esercitata, fino al lancio, solo
su testnet: nella campagna di luglio su una pool con liquidità minima, nella
prova di livello 2 di agosto–settembre su un router reale con gas reale,
dove le prime conversioni hanno mosso pesantemente una pool di dimensioni
da testnet, e nella campagna di settembre sulla configurazione di lancio. La
consideravamo la superficie meno provata del protocollo; è stata segnalata
come tale all'auditor, e due finding dell'audit (#1 e #28) ne hanno cambiato
l'innesco — la Sezione 6.5 descrive il risultato. Su mainnet i primi tre
passaggi sono girati il 29 settembre 2026, in condizioni avversariali dal
primo minuto: la transazione descritta qui sotto ha convertito i primi
200.000.000 DMN di inventario di fee in 0,081248 BNB e la ripartizione li ha
distribuiti come progettato. Il buyback automatico non era scattato al
blocco 127.195.880 (12 ottobre 2026); attende che i BNB trattenuti superino
la sua soglia. Da qui in avanti il registro di questo percorso è la chain,
non un test.

**Uno stake minuscolo piazzato subito prima di una notifica di reward.**
Trovato il giorno del lancio, 29 settembre 2026: quando il runbook di lancio
è ripreso alle 17:12 UTC, i valori che si aspettava non reggevano più, e la
sentinella del protocollo (Sezione 10.5) ne ha identificato la causa. Una
transazione,
`0xa1238092425b7c1cc0840568d1ce9fe7534f842e584555049df353363f2ed048`
(blocco 124.657.486, 05:04:08 UTC — un'ora e diciotto minuti dopo l'aggiunta
della liquidità, prima che chiunque avesse messo in staking), ha fatto
quanto segue in un'unica sequenza atomica: ha preso in prestito 0,022 BNB
con un flash loan; ha comprato DMN dalla pool di lancio; ne ha messo in
staking un wei per trenta giorni, il che ha reso il suo potere di voto
l'intero `totalVotingPower`, fino ad allora zero; ha donato 48.438.526,78
DMN al contratto del token, portando l'inventario di fee oltre la soglia di
swap di 200.000.000; ha venduto i DMN che ancora deteneva; poi ha inviato un
wei di DMN alla pair, l'innesco pubblico della Sezione 6.5. Il contratto ha
venduto 200.000.000 DMN per 0,081248 BNB e ha notificato la quota dello
staking — due terzi, 0,054165 BNB — al contratto di staking, dove un unico
staker con un wei di potere di voto ne deteneva il 100%; la stessa
transazione l'ha riscossa. Di questo evento circolano due cifre ed entrambe
sono giuste: 0,054165 BNB è la quota dello staking catturata, letta dagli
eventi `RewardNotified` e `RewardClaimed` della ricevuta; circa 0,033 BNB è
ciò che il mittente ha tenuto dopo aver restituito il flash loan (0,022055
BNB) e aggiunto la sua piccola vendita (0,000699 BNB) — la differenza sono
i DMN che ha comprato e regalato per armare l'innesco.

Cos'è, esattamente. La correzione #35 dell'audit (Sezione 7.2) protegge i
BNB che arrivano mentre nessuno è in staking: vanno in una riserva che solo
la governance può muovere. Non protegge i BNB che arrivano quando il potere
di voto totale è quasi zero invece che zero: una volta che esiste un
qualsiasi potere, una notifica è distribuita pro quota, e un wei contro un
wei è tutto. L'innesco è pubblico per progetto, e una donazione al contratto
del token può armarlo. Non avevamo previsto la combinazione. L'esposizione è
strutturale al periodo di staking vuoto e si chiude da sola non appena
esistono posizioni reali, perché uno stake non può uscire per trenta giorni
e una posizione minuscola riceve una quota minuscola di qualsiasi cosa
notificata in seguito. Quel periodo è finito: al blocco 127.195.880 (12
ottobre 2026) il contratto di staking deteneva 255,23 miliardi di DMN in
circa 170 lock, con un potere di voto totale di 1,0028 × 10^30. Ciò che la
transazione ha preso è stata la quota dello staking della prima
conversione, in un momento in cui nessun altro era in staking per
riceverla. La transazione non ha toccato né la custodia della migrazione né
i token LP della pool, e non ha dato al mittente alcun potere di governance:
un wei è molto al di sotto della soglia di proposta, che il governor legge
come 1.000 × 10^18 unità di potere di voto — il potere di 1.000 DMN
bloccati per trenta giorni al moltiplicatore 1× (letto al blocco
127.226.547, 12 ottobre 2026). La fee del 4% della Sezione 6.3 è stata
verificata al wei sull'acquisto e sulla vendita di questa stessa
transazione. La ricostruzione dai quaranta log della ricevuta è nel registro
di lancio (Sezione 10.6).

## 10.5 L'interfaccia non è il protocollo

Una domanda che merita una risposta esplicita: cosa succede se il sito viene
compromesso?

L'interfaccia web è un frontend pubblico stateless. Non detiene chiavi, non
custodisce fondi, non mantiene database né sessioni autenticate, e non firma
mai nulla. Ogni interazione con la catena avviene nel browser dell'utente, con
il wallet dell'utente, richiedendo la firma dell'utente.

L'interfaccia non è mai nel percorso di custodia né in quello di firma. La sua
superficie d'attacco è quindi la **disponibilità, non i fondi** — un frontend
compromesso o non disponibile non può muovere i token di nessuno, perché non
ha mai avuto la capacità di muoverli.

Il caso peggiore realistico è che la pagina smetta di funzionare. I contratti
restano pienamente utilizzabili attraverso un block explorer o uno strumento
da riga di comando, come lo sono stati durante mesi di test prima che
l'interfaccia esistesse.

È una conseguenza deliberata dell'architettura, non un caso fortunato: il
protocollo sono i contratti, e l'interfaccia è una comodità posta davanti a
essi. Qualsiasi cosa si possa fare attraverso l'interfaccia si può fare senza.

L'interfaccia è pubblicata su `app.daimon.money`; il sito del progetto è
`daimon.money`. Dall'8 ottobre 2026 (versione corrente dal 9 ottobre)
l'interfaccia ha una seconda casa, indirizzata dal contenuto: una build
statica su IPFS, raggiungibile attraverso il nome `daimon.blockchain` (un
nome Unstoppable Domains i cui record vivono su Polygon) e identificata dal
suo hash di contenuto —
`bafybeidmjrqs56gw4vqlnqptv4fungoayec6do7oojstfmoxjzidd6kvyq` per la
versione corrente, tag `mirror-v2`. La build è riproducibile: una ricetta
container fissata nel repository produce lo stesso hash dal commit taggato,
così chiunque può ricostruirla e confrontare. Un hash diverso è un sito
diverso, chiunque lo serva. La procedura, i pin e il record del nome sono
in `docs/IPFS_MIRROR.md`.

Un servizio separato, la sentinella, osserva i contratti e riporta ciò che
vede su un canale di allerta privato del progetto. È in sola lettura: non
detiene alcuna chiave che possa muovere fondi o firmare una transazione; i
suoi unici segreti sono le proprie credenziali di allerta e dei fornitori di
dati. La sua specifica è `docs/SPEC_MONITOR.md`. Gira su mainnet dal giorno
del lancio; quando, quel giorno, lo stato non corrispondeva più alle attese
del runbook, è ciò che ha identificato come causa la transazione della
Sezione 10.4.

Lo stesso ragionamento vale per le dipendenze software dell'interfaccia. Le
vulnerabilità note che le riguardano sono documentate in `SECURITY.md`,
insieme a una valutazione di se le condizioni necessarie a sfruttarle esistano
o meno in questa applicazione. I contratti stessi non hanno dipendenze di
questo tipo a runtime.

## 10.6 Cosa è stato dimostrato on-chain

Oltre ai test automatici, i seguenti cicli funzionali sono stati eseguiti e
documentati su BSC testnet, ciascuno con gli hash delle transazioni:

- migrazione 1:1, verificata al wei
- applicazione delle fee e distribuzione della reflection, verificate al wei
- staking vote-escrow con potere di voto pesato, e rifiuto del ritiro
  anticipato
- il ciclo di governance completo descritto nella Sezione 9
- swap autonomo delle fee su una pool di liquidità reale, con BNB
  effettivamente ricevuti dal wallet marketing e dal pool reward dello staking
- il primo burn reale: 44.785.811 DMN rimossi dalla supply totale
- riscossione dei reward su più wallet, quadrata al wei su tre indirizzi
- pausa e riattivazione del guardian
- rifiuto dell'esecuzione anticipata (`TooEarly`) e della doppia esecuzione
  (`AlreadyExecuted`)
- verifica economica della fee post-esecuzione: esattamente 4,00%

L'ultima funzione del sistema — il trasferimento in tesoreria, deciso dalla
governance, dei token di migrazione non riscattati — è stata eseguita in
seguito, il 7 agosto 2026, come proposta #2: 999.121.813.473 DMN spostati dal
contratto di migrazione alla tesoreria da un voto approvato, dopo i suoi
sette giorni, con la supply totale invariata al wei.

Il registro completo è pubblicato come
[`TESTNET_RESULTS.md`](https://github.com/daimon-dao/daimon-dao/blob/master/TESTNET_RESULTS.md).

**Quattro prove generali del lancio stesso.** Dopo l'audit, il codice
auditato è stato deployato altre quattro volte con gli script di mainnet, a
fedeltà crescente. Il livello 1, su un fork locale dove il tempo può essere
spostato, ha
provato le sequenze logiche: l'ordine di lancio, i percorsi di
annullamento, la pausa e la sua scadenza, e la deviazione che ha
trasformato il deploy in due fasi (uno script a broadcast singolo fissa la
scadenza del guardian durante la simulazione, mentre il token calcola la
propria dal blocco in cui viene minato). Il livello 2, sulla testnet
pubblica di BSC in tempo reale dal 28 agosto al 10 settembre 2026, ha
provato ciò che un nodo locale non può: nonce reali, gas reale, 34 controlli
post-broadcast su 34 letti dallo stato minato, la scadenza del guardian
identica nei tre contratti, e un ciclo di governance completo su un orologio
reale — proposta, voto, coda, sette giorni reali di timelock, esecuzione —
con ogni transazione firmata da un keystore cifrato e registrata. Una terza
campagna, sulla stessa testnet dal 14 al 28 settembre 2026, ha provato la
configurazione di lancio come infine decisa — il 4% impostato al deploy, il
timelock come destinazione delle fee, il passaggio di seeding della
liquidità, due ulteriori controlli di verifica (da 34 a 36) — e ha eseguito
la prima proposta di mainnet, la ripartizione 60/40 della Sezione 11.3, da
cima a fondo su un orologio reale come sua proposta 0. La quarta prova
generale ha eseguito il giorno del lancio passo per passo su un fork locale
della mainnet di BNB Smart Chain contro il contratto DMX reale, la pool DMX
reale e il router reale, al prezzo del gas reale, così che le cifre di
finanziamento del lancio fossero le cifre della prova. Tutti i diari sono
pubblici:
[`TESTNET_L1_RESULTS.md`](https://github.com/daimon-dao/daimon-dao/blob/master/TESTNET_L1_RESULTS.md)
(con il seguito
[`TWO_PHASE_RESULTS.md`](https://github.com/daimon-dao/daimon-dao/blob/master/TWO_PHASE_RESULTS.md)),
[`CHAPEL_L2_RESULTS.md`](https://github.com/daimon-dao/daimon-dao/blob/master/CHAPEL_L2_RESULTS.md),
[`CHAPEL_2B_RESULTS.md`](https://github.com/daimon-dao/daimon-dao/blob/master/docs/CHAPEL_2B_RESULTS.md)
e
[`MAINNET_FORK_RESULTS.md`](https://github.com/daimon-dao/daimon-dao/blob/master/docs/MAINNET_FORK_RESULTS.md).

**Mainnet.** Il 29 settembre 2026 il codice auditato è stato deployato su
BNB Smart Chain, chain id 56, intatto: `src/` al commit del deploy non
differiva da `audit-final` di nulla, e non ne differisce al commit che
rilascia questo documento. La sequenza, tutti gli orari in UTC:

| Passo | Blocco | Ora | Cosa è successo |
|---|---|---|---|
| Fase 1 | 124.626.062 – 124.626.108 | 01:08:24 – 01:08:44 | deployati l'implementazione del token, il proxy del token (DMN) e il contratto di migrazione; la scadenza della migrazione fissata, immutabilmente, a 1798420124 |
| Fase 2 | 124.626.867 – 124.627.202 | 01:14:26 – 01:16:57 | deployati timelock, staking e governor; ruoli concessi al timelock e al guardian; fee impostate a 10/10/20 e quota degli staker a 1000; ogni ruolo temporaneo revocato — sedici transazioni, `All decentralization asserts passed` |
| Verifica | 124.627.634 | | 36 invarianti su 36 riletti dallo stato minato |
| Verifica dei sorgenti | | | i sette contratti del deploy verificati su Sourcify e BscScan, corrispondenza esatta |
| Liquidità iniziale | 124.642.589 → 124.647.068 | 03:12:23 → 03:45:59 | il proprietario di DMX ha scambiato 4.999.548.574,36 DMX in DMN 1:1 (`0x39b44eab12057cd2396cbc1200e45bc89f9b2bd9623cc717a4c5557af4889549`); un contratto di seeding monouso ha poi aggiunto 4.799.566.631,39 DMN e 1,994 BNB alla pair e inviato i 97.828,093 token LP al timelock, in una sola transazione (`0xdc8dd206e10e5293e7380163d13d3f4bb5575662d0eddef99f9bddd7f7b8dfa4`; Sezione 11.3) |
| Prima conversione | 124.657.486 | 05:04:08 | il ciclo delle fee della Sezione 6.5 è girato per la prima volta, dentro la transazione della Sezione 10.4 |
| Finestra aperta | 124.767.991 → 124.777.699 | 18:53:34 → 20:06:24 | il proprietario di DMX ha alzato il limite per transazione di DMX all'intera supply (`0xfaef2123e54dd4d5054b9195284d43576e35c5161e178ae5e8b810f9b620b47b`), poi ha escluso la tesoreria della migrazione dalla fee di DMX (`0x8aaac289174a13a61040a68503550d79b31cdc25e1884686e8a42632f04cd54d`); da quel blocco qualsiasi possessore di DMX può fare il claim |

Due passi del runbook sono stati saltati per decisione: uno swap di prova
del proprietario, perché la fee del 4% era già stata verificata al wei
sull'acquisto e sulla vendita della transazione della prima conversione, e
un primo innesco manuale dello swap delle fee, perché la prima conversione
era già avvenuta. Ogni transazione, ogni rilettura, le otto deviazioni dal
runbook e la ricostruzione dell'incidente sono nel registro di lancio,
[`docs/MAINNET_LAUNCH_RECORD.md`](https://github.com/daimon-dao/daimon-dao/blob/master/docs/MAINNET_LAUNCH_RECORD.md).

Letto al blocco 127.195.880, 12 ottobre 2026: 341.306.088.146,86 DMX
migrati (il 34,1% della vecchia supply, inclusa la quota della liquidità
iniziale); 255,23 miliardi di DMN in staking; nessuna proposta ancora nel
governor; il token mai messo in pausa; il timelock che detiene esattamente i
97.828,093 token LP emessi al seed, nessun BNB, e 341.401.083.142,59 DMX in
custodia; il deployer senza alcun ruolo in alcun punto; i tre valori di
scadenza del guardian identici.

## 10.7 Audit esterno

Tutto quanto sopra è stato prodotto dalle stesse persone che hanno scritto il
codice. È utile e insufficiente.

I contratti sono stati congelati al tag `audit-scope-v2` e revisionati in
modo indipendente da Zenith. L'audit è completo. Il report è pubblicato
integralmente — non una sintesi, non un certificato, non estratti
selezionati:
[Daimon DAO — Zenith Audit Report](https://github.com/zenith-security/reports/blob/main/reports/Daimon%20DAO%20-%20Zenith%20Audit%20Report.pdf).

Registra 37 finding: 1 critico, 1 alto, 7 medi, 12 bassi e 16 informativi.
29 sono stati corretti nel codice; 8 sono stati accettati, ciascuno con
motivazione scritta. L'esatto intervallo di codice che il report descrive è
congelato per sempre al tag `audit-final`. Ogni prova generale da allora ha
eseguito quel codice intatto, e così ha fatto il deploy su mainnet del 29
settembre 2026: `src/` non differiva da `audit-final` di nulla al commit del
deploy, e non ne differisce al commit che rilascia questo documento.

Tre impegni erano stati presi prima dell'audit. Il loro stato:

**Il report è pubblicato integralmente** — mantenuto, al link qui sopra.

**Non faremo il deploy su mainnet prima che sia completato** — mantenuto.
L'audit era completo e il suo report pubblico nell'agosto 2026; il deploy su
mainnet è seguito il 29 settembre, dopo le quattro prove generali della
Sezione 10.6 e la checklist di mainnet pubblicata, che segna come tali le
voci lasciate aperte al lancio.

**L'auditor ha ricevuto la nostra stessa lista di preoccupazioni**, incluso
il percorso meno provato descritto in 10.4. Due finding (#1 e #28) sono
usciti da quella superficie. Un audit serve a trovare quello che ci è
sfuggito, non a confermare quello che già sappiamo.

Un bug bounty finanziato dalla tesoreria sarà proposto alla governance, così
che l'incentivo a segnalare una vulnerabilità superi permanentemente
l'incentivo a sfruttarla. Fino ad allora, la divulgazione responsabile è
benvenuta e sarà riconosciuta pubblicamente (`SECURITY.md`).

---

# 11. Fondi e tesoreria

## 11.1 Una sola tesoreria, ed è un contratto

I fondi del protocollo hanno una sola casa: il timelock. Il contratto
DaimonTimelock *è* la tesoreria — non un wallet che vi punta, non un multisig
che la gestisce per suo conto. Non ha proprietario e non ha chiavi. Nulla ne
esce se non attraverso una proposta di governance pubblica: cinque giorni di
voto, sette giorni allo scoperto, poi un'esecuzione che chiunque può
innescare. Il guardian, durante il suo mandato di 36 mesi, può annullare
un'uscita in coda; non può mai reindirizzarne una, e dopo il mandato solo un
voto può annullare.

Il puntatore `treasury` del contratto di migrazione è l'indirizzo del
timelock, legato come `immutable` nel suo costruttore e derivato al deploy
invece che digitato: la fase 1 lo ha legato all'indirizzo del timelock che
la fase 2 avrebbe creato, la fase 2 ha verificato che la previsione si fosse
avverata, e la verifica post-broadcast lo ha riletto dalla chain viva; al
blocco 127.195.880 legge `0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891`
(Sezione 5.4). I token legacy raccolti da ogni claim, e i DMN non riscattati
trasferiti dopo la scadenza, atterrano quindi nello stesso contratto
governato di tutto il resto.

## 11.2 Perché non esiste un wallet operativo

La bozza v0.1 di questo documento descriveva due luoghi: una tesoreria
governata, e un multisig operativo che riceveva in BNB la quota marketing
delle fee, con firmatari noti, per le piccole spese ricorrenti. Quel modello
è ritirato, e la ragione merita di essere detta invece che nascosta.

Una parte delle entrate del protocollo, versata in un wallet gestito da
persone, è — per un progetto senza entità giuridica — reddito di quelle
persone. Un contratto governato da voto pubblico non lo è, finché non
distribuisce. Quindi c'è una sola tesoreria e nessun wallet operativo, e
nessun firmatario in alcun punto del flusso dei fondi. La flessibilità che
il wallet operativo doveva fornire — spese piccole e frequenti senza un
voto per ciascuna — verrà dall'entità giuridica che il protocollo è
destinato a finanziare, quando esisterà, attraverso budget periodici
approvati per proposta e rendicontati in pubblico. Fino ad allora, un
pagamento per lavoro svolto per il protocollo è una proposta come le altre.

## 11.3 Cosa entra, e quando

**Al lancio, nulla dalle fee.** `marketingWallet` è stato impostato al
timelock al deploy, e la quota della fee marketing indirizzata agli staker è
stata impostata a 1000 punti base — tutta — nella seconda fase del deploy.
L'aritmetica rende l'importo che raggiungerebbe la tesoreria esattamente
zero, e nessuna transazione verso quell'indirizzo parte. La verifica
post-broadcast ha asserito la quota dallo stato minato; al blocco
127.195.880 (12 ottobre 2026) la quota leggeva ancora 1000 e il timelock non
deteneva BNB.

**Dal primo voto, il 40%.** La prima proposta su mainnet imposta la
ripartizione a 60% staker / 40% tesoreria — il 60/40 con cui il codice è
stato scritto, ora puntato a un contratto invece che a un wallet. Da quel
voto in poi la quota della tesoreria si accumula in BNB, intoccata da
chiunque, finché un ulteriore voto non la spende. La proposta è scritta:
`docs/G1_PROPOSAL.md` ne dà la calldata esatta, la cronologia e la prova su
un fork di mainnet, e la stessa chiamata è stata eseguita da cima a fondo
sulla testnet pubblica come proposta 0 della campagna sulla configurazione
di lancio (Sezione 10.6). Al blocco 127.195.880 non era stata creata: il
contatore delle proposte del governor leggeva zero. L'ordine dei primi voti
— la ripartizione; l'esenzione dalla fee della tesoreria; un primo, piccolo
deposito; dopo la chiusura della finestra, lo sweep e il burn di continuità
di 11.6; il primo budget di un'entità legale, se ne verrà costituita una — è
pubblicato nella politica della tesoreria (sezione 7) e, proposta per
proposta, in `docs/CALENDARIO_GOVERNANCE_Q1.md`.

**Tre entrate che il codice fornisce da solo.**

- *I token legacy.* I DMX di ogni possessore che migra vengono trasferiti
  alla tesoreria, dove restano in custodia non circolante finché lo sweep
  dei DMN non riscattati non è stato eseguito — la scadenza effettiva,
  credito di pausa incluso — un requisito dell'audit (finding #6), ora
  proprietà di un contratto e non promessa di firmatari: nulla può muoverli
  prima di un voto. Al blocco 127.195.880 il timelock deteneva
  341.401.083.142,59 DMX.
- *I DMN non riscattati.* Dopo la scadenza, la governance trasferisce alla
  tesoreria tutti i DMN rimasti nel contratto di migrazione (Sezione 4.4).
- *La pool stessa.* I token LP della liquidità iniziale DMN/WBNB sono stati
  emessi direttamente al timelock. Il 29 settembre 2026 chi ha fornito la
  liquidità — il proprietario di DMX, che ha riscattato solo quella quota
  (11.5) — ha approvato un contratto di seeding monouso, `LiquiditySeeder`
  all'indirizzo `0x21ab79825b86137CF1b04884FCFC4e4b717ce062`, e il contratto
  ha aggiunto 4.799.566.631,39 DMN e 1,994 BNB alla pair e ha inviato i
  97.828,093 token LP ricevuti al timelock nella stessa transazione
  (`0xdc8dd206e10e5293e7380163d13d3f4bb5575662d0eddef99f9bddd7f7b8dfa4`,
  blocco 124.647.068, 03:45:59 UTC). I 4.999.548.574,36 DMN che il
  proprietario aveva riscattato sono diventati 4.799.566.631,39 nella pool
  perché il trasferimento di seeding ha pagato la fee del 4% come ogni
  altro; la sua parte non riflessa del 3%, circa 150 milioni di DMN, è stata
  il primo inventario di fee del protocollo. Il registro di lancio asserisce
  dallo stato minato che né il proprietario né il deployer detenevano alcun
  token LP in seguito; al blocco 127.195.880 il saldo del timelock era
  ancora pari all'intera supply emessa meno la liquidità minima della pair
  stessa. La pool non può essere ritirata se non per voto, e la posizione
  della tesoreria in essa cresce con la fee di ogni swap.

**E, in futuro, le fee di qualsiasi modulo di servizio che la DAO aggiunga.**

## 11.4 Cosa la governance controlla qui

Il destinatario della quota di fee e la ripartizione tra staker e tesoreria
sono impostati da funzioni riservate alla governance: la DAO può
reindirizzare quel flusso in qualsiasi momento, con un voto. Ogni uscita è
una proposta; non esiste un budget permanente dentro il protocollo e nessuno
è autorizzato a spendere senza un voto.

Il timelock non è esente dalla fee di trasferimento. Al lancio è stato
lasciato deliberatamente un possessore ordinario, quindi qualsiasi DMN che
ne esca — per il burn di continuità, per la liquidità, per un pagamento —
paga il 4% come chiunque altro finché un voto non lo esenta, la seconda
proposta dell'ordine pubblicato (11.3). Al blocco 127.195.880 non era
esente; il contratto di staking, al contrario, lo è (Sezione 7.5).

Due *destinazioni* sono fissate permanentemente, oltre il potere di
reindirizzo persino della governance: l'indirizzo morto che riceve i token
bruciati, e la tesoreria della migrazione. Entrambi i puntatori sono
`immutable`, impostati al deploy. I token all'indirizzo morto sono fuori
dalla portata di chiunque, per sempre. La tesoreria della migrazione è il
timelock: il suo indirizzo non può essere cambiato da nessuno, e ciò che
detiene si muove solo per voto. Ciò che nessuna maggioranza può fare è
puntare in silenzio uno dei due flussi altrove.

## 11.5 I token del progetto stesso

I due wallet marketing di DMX descritti in 4.1.4 — quello del proprietario e
il secondo — detenevano circa il 42% della vecchia supply prima del lancio,
e 396.610.400.010,00 DMX al blocco 127.195.880 (12 ottobre 2026): il 39,7%
della supply totale, circa il 41% della supply fuori dall'indirizzo morto.
Hanno riscattato solo la quota della liquidità iniziale, prima che si
aprisse la finestra di migrazione: il 29 settembre 2026 il proprietario ha
scambiato 4.999.548.574,36 DMX nello stesso numero di DMN
(`0x39b44eab12057cd2396cbc1200e45bc89f9b2bd9623cc717a4c5557af4889549`,
blocco 124.642.589, 03:12:23 UTC), e tutti sono finiti nella pool, con i
token LP di quella liquidità nel timelock (11.3); il saldo di DMN del
proprietario era zero alla fine del giorno del lancio, e il registro di
lancio lo asserisce. Tutto il resto resta nel contratto di migrazione e
raggiunge la tesoreria attraverso `sweepUnclaimed()` dopo la scadenza, senza
un trasferimento, senza una fee, e senza passare per le mani di alcuna
persona, e non vota. I token del progetto diventano del protocollo: la
governance è decisa da chi i propri token li ha comprati, team incluso. A
cosa servono è deciso uso per uso, con un voto pubblico; a cosa non servono
è scritto nella politica della tesoreria (versione 1.2, tag
`treasury-policy-v1.2`) — nessun burn per decisione, nessuna distribuzione
a possessori, staker o chiunque non abbia svolto lavoro per il protocollo,
nessuna lotteria.

Le posizioni personali delle persone che costruiscono il protocollo sono
una questione separata, dichiarata in `docs/TEAM_HOLDINGS.md`: DMX comprati
con fondi propri dal 2022, o ricevuti come pagamento per lavoro svolto; un
impegno di condotta — nessuna vendita senza trenta giorni di preavviso
pubblico e una versione emendata di quel documento prima committata nel
repository — datato dalla storia del repository e che non vincola nessuno
per legge. Migrano come chiunque altro, 1:1.

## 11.6 Il burn di continuità

I DMX inviati all'indirizzo morto nel corso degli anni non possono migrare:
non esiste una chiave che possa riscattarli. I DMN che corrispondono loro
vengono trasferiti alla tesoreria con il resto e poi inviati, per voto della
governance, all'indirizzo morto — lo stesso importo che l'indirizzo morto di
DMX detiene a un blocco dichiarato. Una volta lì, chiunque può chiamare
`burnDeadBalanceToFloor()` e rimuoverli dalla supply per sempre. La supply
di DMN riprende così esattamente da dove il burn di DMX si era fermato — e
questa volta la supply diminuisce davvero, cosa che la contabilità del
predecessore non ha mai fatto (4.1.2).

## 11.7 Impegni

L'indirizzo della tesoreria, i suoi saldi e ogni proposta sono pubblici. Le
sue spese sono rendicontabili on-chain perché ogni transazione che effettua è
visibile per costruzione. La sua politica — cosa detiene, cosa può fare,
cosa non farà mai — è pubblicata come
[`docs/TREASURY_POLICY_v1.0.md`](https://github.com/daimon-dao/daimon-dao/blob/master/docs/TREASURY_POLICY_v1.0.md)
— versione 1.2 al momento di questo rilascio, congelata al tag
`treasury-policy-v1.2` e in vigore dall'esecuzione della prima proposta; il
nome del file conserva "v1.0" perché i link restino stabili — e può essere
modificata solo con lo stesso processo che muove i fondi. Non ci
sono firmatari da nominare, perché non c'è nessuno di cui fidarsi.

---

# 12. Roadmap

Questa roadmap distingue tra ciò che esiste, ciò che è previsto, e ciò che è
una possibilità a lungo termine. Non vengono date date oltre la fase attuale,
e nulla di quanto segue costituisce un impegno a realizzare.

Ed è anche, per costruzione, incompleta. La Sezione 12.4 spiega perché.

## 12.1 Fase 1 — Ora

Il protocollo descritto in questo documento: token, staking, governance,
timelock, migrazione. Auditato, con il report pubblicato e l'intervallo
auditato congelato al tag `audit-final`; provato cinque volte — la campagna
di luglio su testnet, poi le quattro prove generali post-audit dell'ordine
di lancio con gli script di mainnet (Sezione 10.6); in funzione sulla
mainnet di BNB Smart Chain dal 29 settembre 2026 (Sezione 5.4), con la
finestra di migrazione aperta fino al 28 dicembre 2026 alle 01:08:44 UTC, la
liquidità iniziale predisposta con i suoi token LP in tesoreria, e
l'interfaccia pubblicata con un mirror riproducibile (Sezione 10.5).

Cosa resta di questa fase: le prime proposte di governance della politica
della tesoreria, nell'ordine pubblicato (Sezione 11.3), a cominciare dalla
ripartizione 60/40; poi, una volta chiusa la finestra, lo sweep dei token
non riscattati e il burn di continuità (Sezione 11.6). Nessuna data viene
data.

## 12.2 Fase 2 — Daimon come protocollo DeFi

Il protocollo attuale è un token con una governance. L'intenzione è che
diventi un ecosistema di primitive finanziarie, posseduto e diretto dalle
persone che lo usano.

La direzione è deliberata: gli strumenti che determinano cosa accade ai
risparmi delle persone comuni — credito, rendimento, liquidità — sono detenuti
quasi interamente da istituzioni che ne stabiliscono i termini senza
consultazione. Ricostruirli come contratti open source e permissionless
governati da chi li usa è la forma pratica dell'argomento esposto nella
Sezione 3.

Le primitive che intendiamo perseguire:

**Lending e borrowing.** Fornire asset per guadagnare interessi, e prendere in
prestito contro collaterale. Tassi determinati algoritmicamente dall'utilizzo
invece che dalla politica di un'istituzione, requisiti di collaterale visibili
nel codice, regole di liquidazione identiche per tutti.

**Fornitura di liquidità.** Meccanismi per fornire liquidità e guadagnare una
quota dell'attività di scambio, con i termini — ripartizione delle fee,
struttura degli incentivi, coppie supportate — stabiliti dalla governance
invece che da un operatore.

**Strategie di rendimento.** Prodotti strutturati che indirizzano capitale
verso protocolli consolidati, con il profilo di rischio di ciascuna strategia
dichiarato esplicitamente invece che sepolto, e la selezione delle strategie
decisa dal voto.

**Ulteriori primitive man mano che maturano.** Derivati, credito strutturato,
meccanismi assicurativi, integrazione di asset del mondo reale, liquidità
cross-chain — la superficie della DeFi si espande di continuo, e qualsiasi
primitiva costruibile come contratto permissionless è una candidata.

**Come questo si collega al token.** Ciascuna di queste genera entrate per il
protocollo. Quelle entrate entrano nel ciclo che il token già implementa: una
quota a buyback e burn, una quota agli staker, una quota alla tesoreria. Il
motore economico del protocollo è già costruito; la Fase 2 riguarda il dargli
più carburante.

L'ambizione dichiarata è che una persona con pochissimo capitale e nessuna
formazione finanziaria possa accedere agli stessi strumenti di chiunque
altro, alle stesse condizioni, con le regole visibili e la governance aperta.
Questo è l'obiettivo. Se e fino a che punto verrà raggiunto dipende
dall'esecuzione, dalle risorse e dal tempo.

**Vincoli che si applicheranno.** Ogni modulo sarà auditato indipendentemente
prima del deploy. Ogni modulo sarà introdotto attraverso la governance invece
che annunciato. I moduli che gestiscono fondi degli utenti saranno costruiti
con gli stessi vincoli del protocollo principale: nessun proprietario, nessun
prelievo privilegiato, nessun parametro senza limite.

**Il modulo tesoreria.** La tesoreria esiste dal lancio — è il timelock,
Sezione 11 — e finché non esiste un modulo dedicato opera per proposte ad
hoc: poche, piccole, una alla volta. Un modulo tesoreria — una allowlist di
asset e protocolli approvati, limiti per operazione, un audit proprio —
arriva dopo il lancio e dopo il primo modulo di servizio, quando la
tesoreria potrà pagarlo. Una tesoreria in grado di interagire con contratti
esterni è la più grande e più attraente superficie d'attacco che un
protocollo possa creare, e non si costruisce a credito.

Cosa la tesoreria è destinata a detenere è già deciso, e verrà raggiunto per
proposte nel tempo: **20% BNB, 40% BTCB, 40% XAUt** — l'asset della chain
stessa per operazioni, gas e depositi, e le due premesse da cui il progetto
è partito, Bitcoin e oro. **Mai stablecoin**: non come riserva, non come
parcheggio, non come eccezione. Ciò che può essere stampato non è denaro per
la definizione di questa tesoreria.

**Detto chiaramente: BTCB e XAUt sono wrapper custodial.** Il Bitcoin nativo
non esiste su BNB Chain, e l'oro non esiste su nessuna chain se non come
diritto su lingotti nel caveau di qualcuno. Detenerli significa accettare il
rischio di un emittente. La tesoreria lo accetta, lo dichiara, e persegue
l'unica mitigazione che esiste: gli emittenti più profondi e più auditati
disponibili su questa chain, e la diversificazione tra emittenti man mano
che ne diventano disponibili altri. La scelta di XAUt è una scelta di chain,
non di fede.

**Su cosa questo non è.** Il capitale che rende è capitale che rischia:
fallimento di contratti di terze parti, impermanent loss, condizioni di
mercato. I rendimenti possono essere positivi, nulli o negativi. Nulla qui
promette rendimento; ogni strategia viene proposta con i suoi rischi scritti
nella proposta stessa, e ciò che la tesoreria non farà mai — leva, derivati,
trading, oracoli, stablecoin, distribuzioni a individui — è scritto nella
sua politica.

## 12.3 Fase 3 — Infrastruttura

Una possibilità lontana, inclusa perché una roadmap che si ferma all'orizzonte
comodo non è una roadmap.

Se l'ecosistema crescesse fino al punto in cui una chain generalista
diventasse un vincolo reale — throughput, costi di transazione, funzionalità a
livello di protocollo non disponibili su BNB Chain — la community potrebbe
valutare il passaggio a un'infrastruttura dedicata.

La forma realistica non è costruire una blockchain da zero. Una chain nuova
parte senza validatori e senza sicurezza economica, il che la rende
attaccabile indipendentemente da quanto bene sia progettata. La strada
percorribile è una chain applicativa o un layer-2 che **eredita** la sicurezza
da una rete consolidata invece di tentare di costruire la propria.

Questo è esplicitamente condizionale. Accade solo se una crescita reale lo
giustifica, e solo per decisione della community.

**Cosa sopravvivrebbe.** La tokenomics, il modello di governance, il design
dello staking, il principio dell'assenza di proprietario — sono logica, e la
logica è portabile. Una chain diversa cambierebbe dove il protocollo gira, non
cosa fa.

## 12.4 La roadmap non è fissa

Tutto quanto sopra sarà sbagliato sotto qualche aspetto, ed è previsto che lo
sia.

La DeFi non sta ferma. Primitive che oggi non esistono esisteranno fra tre
anni; approcci che ora sembrano essenziali verranno superati; rischi non
ancora identificati emergeranno. Una roadmap scritta come sequenza fissa di
consegne sarebbe obsoleta prima della prima consegna — e, peggio,
impegnerebbe il protocollo a un piano invece che a una direzione.

Daimon è costruito per cambiare. Il percorso di aggiornamento esiste, la
governance può estendere il sistema, e i vincoli che non possono essere
alterati sono deliberatamente pochi e scelti con precisione: nessuna
emissione, un floor di supply, un tetto alle fee, un ritardo obbligatorio.
Tutto il resto è aperto, perché tutto il resto dovrebbe poter migliorare.

Non è una cautela aggiunta per sicurezza. È il concetto da cui il protocollo
prende il nome.

Eraclito — la cui lettura del daimon compare nella Sezione 2 — è anche il
filosofo del divenire: *tutto scorre*, nulla resta ciò che era, e ciò che
permane lo fa precisamente cambiando. Il fiume persiste perché l'acqua non lo
fa. Un sistema progettato per restare identico a sé stesso non sarebbe
un'implementazione fedele di quell'idea; ne sarebbe l'opposto.

Quindi la roadmap si muoverà. Nuove frontiere verranno aggiunte man mano che
appaiono, e direzioni prese qui verranno abbandonate quando se ne troveranno
di migliori. Ciò che non cambierà è il piccolo insieme di vincoli che rendono
il protocollo ciò che è — e il requisito che ogni cambiamento passi da un voto
pubblico e sette giorni allo scoperto.

La destinazione non è fissa. Il metodo sì.

---

# 13. Cosa Daimon non è

La maggior parte dei whitepaper finisce con l'ambizione. Questo finisce con i
limiti, perché chi legge per decidere se partecipare è servito meglio sapendo
cosa può andare storto che da un altro paragrafo su cosa potrebbe andare bene.

**Daimon non è un prodotto d'investimento e non promette rendimenti.** Non c'è
un obiettivo di rendimento, non c'è una proiezione, non c'è alcuna aspettativa
di apprezzamento dichiarata in alcun punto di questo documento. Il protocollo
garantisce regole — una supply che non può essere inflazionata, parametri che
non possono essere cambiati in privato, un floor che non può essere
attraversato. Non garantisce nulla riguardo al prezzo, che è determinato da un
mercato che nessun codice controlla.

**La deflazione non è un meccanismo di prezzo.** Una supply che si riduce non
aumenta meccanicamente il valore. La domanda può calare più velocemente
dell'offerta. Il floor garantisce scarsità; non garantisce nient'altro.

**Non c'è un team che vi proteggerà.** È il senso del design, e taglia in
entrambe le direzioni. Nessuno può cambiare le regole contro di voi, e nessuno
può intervenire per aiutarvi. Non esiste un supporto che possa annullare una
transazione, recuperare una chiave persa, o compensare una perdita. Assenza di
proprietario significa esattamente quello che dice.

**La governance può sbagliare.** Una maggioranza può approvare una proposta
cattiva. I vincoli nel codice limitano il danno — le fee non possono superare
il 10%, la supply non può essere emessa né bruciata sotto il floor, i fondi
non possono essere reindirizzati verso indirizzi arbitrari — ma entro quei
limiti, la community può decidere male. Il timelock di sette giorni esiste
perché un errore sia visibile prima di avere effetto, non perché diventi
impossibile.

**Il codice può contenere difetti.** È stato testato estesamente, analizzato
staticamente, attaccato deliberatamente dai suoi stessi autori, e auditato
in modo indipendente, con il report pubblico. Niente di tutto ciò lo rende perfetto. Contratti
auditati dalle migliori società del settore sono stati sfruttati.
L'affermazione onesta è che abbiamo ridotto la probabilità di fallimento per
quanto sappiamo fare, non che l'abbiamo eliminata.

**La partecipazione è volontaria e comporta rischi.** I token possono perdere
valore. I token bloccati non possono essere ritirati in anticipo. Gli smart
contract possono fallire. Nulla di quanto scritto qui dovrebbe essere inteso
come un consiglio ad acquisire, detenere o mettere in staking alcunché.

**Non siamo neutrali.** Questo documento è stato scritto dalle persone che
hanno costruito il protocollo. Ci crediamo, il che è una ragione per leggere
le nostre affermazioni criticamente invece di accettarle. Tutto ciò che viene
qui affermato corrisponde a codice pubblico e deployato, agli indirizzi
della Sezione 5.4. La risposta appropriata a questo documento non è
fidarsi. È verificare.

---

# 14. Avvertenze legali

Questo documento è fornito a scopo puramente informativo. Non costituisce
un'offerta di vendita, una sollecitazione all'acquisto, né una raccomandazione
riguardante alcun asset digitale, strumento finanziario o titolo.

Nulla in questo documento costituisce consulenza di investimento,
finanziaria, legale, fiscale o contabile. Chi legge dovrebbe condurre le
proprie ricerche e consultare professionisti qualificati prima di prendere
qualsiasi decisione.

Gli asset digitali comportano rischi sostanziali, inclusa la perdita totale
dell'importo coinvolto. Le performance passate, i risultati su testnet e le
caratteristiche tecniche non indicano né garantiscono esiti futuri. Gli smart
contract possono contenere vulnerabilità nonostante i test e la revisione
indipendente.

Daimon è un protocollo decentralizzato senza proprietario, senza
amministratore e senza alcuna entità giuridica che lo operi. Nessuna parte
garantisce il suo funzionamento continuativo, mantiene un obbligo di
supportarlo, o è in grado di annullare, modificare o compensare transazioni
eseguite dai suoi contratti.

Le affermazioni contenute in questo documento riguardanti sviluppi futuri
rappresentano intenzioni e possibilità, non impegni. Qualsiasi fase futura
dipende da decisioni di governance della community, fattibilità tecnica e
risorse disponibili.

Il trattamento normativo degli asset digitali varia da giurisdizione a
giurisdizione e continua a evolvere. Chi legge è responsabile di determinare
se la propria partecipazione sia lecita nel luogo in cui risiede.

Le informazioni contenute in questo documento sono accurate al meglio delle
conoscenze degli autori alla data di pubblicazione. Indirizzi dei contratti,
parametri e dettagli tecnici dovrebbero essere verificati direttamente
on-chain, che resta in ogni caso la fonte autorevole.

Le avvertenze legali complete e i termini d'uso sono pubblicati nel
repository come `DISCLAIMER_TERMS` (versione 0.3,
`docs/DISCLAIMER_TERMS_v0.3_EN.md`); il testo inglese è quello autorevole.

---

**Repository:** `github.com/daimon-dao/daimon-dao`
**Riferimento auditato:** tag `audit-final` (scope consegnato al tag `audit-scope-v2`)
**Report dell'audit:** [Zenith, agosto 2026](https://github.com/zenith-security/reports/blob/main/reports/Daimon%20DAO%20-%20Zenith%20Audit%20Report.pdf)
**Mainnet:** BNB Smart Chain, chain id 56, dal 29 settembre 2026 — indirizzi nella Sezione 5.4, registro di lancio in `docs/MAINNET_LAUNCH_RECORD.md`

*v0.3 — versione mainnet.*
