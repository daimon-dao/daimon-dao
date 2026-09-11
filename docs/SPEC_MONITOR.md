# DAIMON MONITOR — Specifica
v2 — 25 agosto 2026.

Da usare in una sessione separata, in una cartella fuori dal
repository dei contratti (suggerita: ~/daimon-monitor).

> Nota di collocazione: nel repository dei contratti vive SOLO questo
> documento. Il bot è un progetto separato, in una cartella propria,
> in sola lettura e senza chiavi private.

## COSA COSTRUIRE

Un bot che osserva i contratti di Daimon su BNB Chain e manda messaggi
su Telegram quando succede qualcosa che vale la pena sapere.

Non è un keeper: non firma transazioni, non ha chiavi private, non può
muovere nulla. Legge e basta.
Non è una dashboard: manda alert, non mostra grafici.

## PRINCIPI

SOLA LETTURA   nessuna chiave privata nel codice, mai. Se il server
               viene compromesso, si possono solo leggere dati
               pubblici.
MODULARE       aggiungere un controllo = aggiungere una funzione, non
               riscrivere il ciclo.
POCHI ALERT    l'assuefazione è il rischio maggiore: se suona dieci
               volte al giorno, la volta che conta viene ignorata.
HEARTBEAT      il bot dice "sono vivo" ogni 6 ore. Senza, non si
               distingue "tutto tranquillo" da "il bot è morto tre
               giorni fa".

## FASE 1 — SICUREZZA

Debutta sul testnet Chapel con gli indirizzi di prova. Al mainnet si
cambiano solo RPC e indirizzi.

Indirizzi da osservare: DaimonV2 (token), DaimonStaking,
DaimonGovernor, DaimonTimelock (è anche la treasury),
DaimonMigration, pair DMN/WBNB. Il marketingWallet È il Timelock dal
deploy (impostato in fase 1 all'indirizzo predetto del Timelock): non
è un indirizzo in più da osservare, è un ramo in più da osservare sul
Timelock.

### Alert urgenti

L'INVARIANTE DI LANCIO: finché `stakingRewardShareBps == 1000`,
nessun BNB deve arrivare al Timelock DAL CONTRATTO TOKEN -- il ramo
marketing non deve eseguire. Il Timelock riceve legittimamente altro
(DMX in custodia dalla migrazione, LP token al lancio, DMN dallo
sweep): quelle entrate non c'entrano. L'entrata che non deve esistere
è una sola: BNB con `from == DaimonV2`. Se compare, la configurazione
del deploy è sbagliata (stakingRewardShareBps != 1000) o sta
accadendo qualcosa di non previsto: URGENT. L'heartbeat riporta lo
stato a ogni battito: "ramo marketing: 0 esecuzioni da sempre".

L'INVARIANTE SI INVERTE dopo la proposta 60/40 (G1 del
CALENDARIO_GOVERNANCE_Q1: UNA proposta, `setStakingRewardShareBps(600)`;
nessun `MarketingWalletSet` viene emesso, la destinazione è il
Timelock da sempre). Da quel momento i BNB dal token al Timelock sono
ATTESI (il 40% della quota marketing a ogni poke): un alert URGENT su
ogni entrata suonerebbe di continuo e ucciderebbe l'attenzione. Dopo
G1 la regola diventa: BNB dal token al Timelock = NOTIFICATION con
l'importo; resta URGENT qualsiasi USCITA dal Timelock non abbinata a
un'operazione eseguita (`CallExecuted` con lo stesso id nello stesso
ciclo). L'invariante deve quindi essere CONFIGURABILE (verso: "mai
BNB dal token" prima di G1, "mai in uscita senza proposta" dopo), e
il cambio di configurazione va fatto il giorno stesso dell'esecuzione
di G1 -- il bot vede `ParamsUpdated("stakingRewardShareBps", 600)` e
può proporlo, ma non deve auto-riconfigurarsi.

DRENAGGIO DELLA POOL: leggere getReserves() della pair a ogni ciclo e
confrontare con la lettura precedente. -20% in un blocco → urgente;
-30% cumulativo in un'ora → urgente (copre il drenaggio graduale);
-10% in un blocco → notifica.

**Chiamate a funzioni sensibili**

⚠️ Due lezioni dalla campagna Chapel, verificate sui contratti veri:

1. Le esenzioni fee impostate in initialize() sono SILENZIOSE — non
   emettono ExcludedFromFeeSet. Un monitor che si basa solo sugli
   eventi non saprà mai chi è esente al lancio. Quindi: all'avvio il
   bot legge lo STATO (chi è esente adesso) e usa l'evento solo per
   rilevare i cambi successivi. Vale come principio generale: per ogni
   cosa che conta, stato all'avvio + eventi per le variazioni.
2. Le firme degli eventi vanno prese dall'ABI compilato, mai assunte.
   ProposalCreated qui è la firma compatta a 4 campi, non quella
   standard di OpenZeppelin: un filtro costruito sulla firma sbagliata
   non produce errori, produce silenzio — che è il modo peggiore in
   cui un monitor può fallire.
3. Le vie SILENZIOSE verso l'esenzione fee sono TRE, non una:
   `initialize()` (esenzioni di deploy), `setStakingContract()` (esenta
   il suo argomento -- e lo marca mandatoryFeeExempt -- senza emettere
   ExcludedFromFeeSet: emette solo `StakingContractSet(staking)`,
   src/DaimonV2.sol:954-963) e -- l'unica con evento --
   `setExcludedFromFee()`. La regola "stato all'avvio, eventi per i
   cambi" copre anche la seconda via: su ogni `StakingContractSet` il
   bot rilegge `isExcludedFromFee` del nuovo indirizzo invece di
   aspettare un evento che non arriverà.

Osservare gli eventi emessi dal token (nomi verificati sul sorgente e
riletti da Chapel; le firme esatte dall'ABI):
   PausedSet / PauseScheduled  → pausa messa o programmata
   FeesUpdated                 → cambio delle commissioni
   ExcludedFromFeeSet          → cambio delle esenzioni (solo i CAMBI:
                                 lo stato iniziale si legge, vedi sopra)
   MarketingWalletSet          → cambio del destinatario operativo
   Upgraded                    → il proxy è stato aggiornato (ERC-1967)

   ParamsUpdated con param == "stakingRewardShareBps"
   → il ripristino della quota al marketing wallet è un atto legittimo
     previsto (governance + timelock), ma il team deve vederlo quando
     viene PROPOSTO, non quando viene eseguito. Qualsiasi variazione
     di questo parametro: URGENTE.
   (ParamsUpdated copre anche maxTxAmount e minimumTokensBeforeSwap:
    variazioni di questi → notifica, non urgente.)

MOVIMENTI DALLA TREASURY: qualsiasi uscita di BNB o token dal Timelock.

### Notifiche (si leggono con calma)

Nuova proposta nel Governor. Operazione schedulata nel Timelock, e
quando diventa eseguibile. Il saldo DMN del contratto token supera
minimumTokensBeforeSwap (c'è inventario da convertire, serve un poke).
notifyRewardAmount con importo fuori dall'ordinario. Un singolo stake
sopra il 5% del voting power totale.

APPROVAZIONI STANTIE (policy della issue #24: le operazioni approvate
NON scadono -- un'operazione in coda resta eseguibile finché non viene
eseguita o cancellata). Il bot tiene la lista delle operazioni con
`readyTimestamp` raggiunto e `executed == false` e `canceled == false`
(letta da STORAGE, `operations(id)`, non dai log) e la riporta con
l'ETÀ di ciascuna (ora - readyTimestamp) nell'heartbeat e in una
notifica giornaliera finché la lista non è vuota. Non è URGENT: è
l'informazione che permette al guardian di cancellare durante il
mandato e a chiunque di eseguire. "Pronta e non eseguita da 3 giorni"
è un fatto che nessuno deve scoprire per caso.

### Cosa NON osservare

Ogni transazione. Variazioni di prezzo. Ogni nuovo holder.

## FASE 2 — LA TREASURY

Da aggiungere quando la Fase 1 gira stabile. Saldo BNB del Timelock e
di ogni BEP-20 rilevante (BTCB 0x7130d2A12B9BCbFAe4f2634d864A1Ee1Ce3Ead9c,
XAUt 0x21cAef8A43163Eea865baeE23b9C2E327696A3bf -- Tether Gold, BEP-20,
6 decimali --, DMN). Nessuna stablecoin: la politica della treasury le
esclude (TREASURY_POLICY §4), quindi non c'è saldo da osservare.
Riepilogo giornaliero con saldi e variazioni: messaggio di servizio a
un'ora fissa, non un alert.

## FASE 3 — LE ENTRATE DEL PROTOCOLLO

Tutti eventi leggibili: fee raccolte (DMN entrato nel contratto),
conversioni (BNB usciti dal fee swap), buyback (speso e bruciato),
reward agli staker (BNB arrivato allo Staking), supply (totalSupply
nel tempo e distanza dal floor). Il dato che conta: quanto il
protocollo ha generato dall'inizio, e nell'ultimo periodo. Riepilogo
settimanale.

## FASE 4 — LE POSIZIONI DEFI

Solo se e quando la treasury impiegherà le riserve. Riconoscere i
token che rappresentano posizioni (es. vBTCB = BTCB su Venus),
convertirli nel valore sottostante, riportare dove sono i fondi e in
che forma. Richiede un'integrazione per protocollo, non
generalizzabile.

## FASE 5 — I RENDIMENTI

L'unica fase che richiede storico e prezzo. Conservare le letture nel
tempo (file o SQLite), calcolare la differenza tra depositato e valore
attuale. Per esprimere un valore in valuta serve una fonte di prezzo
esterna: è l'unica dipendenza da terzi dell'intero sistema, e va
dichiarata.

## ARCHITETTURA

VPS sempre acceso (Hetzner, Contabo, DigitalOcean — 4-6 euro al mese),
non un computer di casa. Processo in continuo con riavvio automatico
(systemd o pm2).

Ciclo: ogni N secondi legge lo stato dalla chain, confronta con la
lettura precedente, se una soglia è superata manda un messaggio, salva
lo stato. Intervallo suggerito per la Fase 1: 15-30 secondi.

RPC: nodi pubblici BSC per iniziare, con più endpoint e fallback. Se
tutti falliscono, il bot deve AVVISARE, non restare in silenzio — un
bot che non legge la chain è un bot cieco.

PRUNING DEI NODI PUBBLICI (verificato su Chapel, giorno 4 della
campagna: eth_getLogs risponde solo sugli ultimi ~45000 blocchi e
sotto restituisce "History has been pruned"; la finestra è rolling).
Conseguenze di progetto:
- l'AVVIO è basato sullo STATO: saldi, esenzioni, operazioni pendenti,
  fee, parametri -- tutto letto con eth_call al primo ciclo. Nessuna
  ricostruzione della storia dai log all'avvio, mai;
- la storia degli EVENTI è best-effort dentro la finestra leggibile:
  si segue live, a chunk di al più 50000 blocchi (cap del nodo), e un
  chunk che risponde "pruned" viene riportato come tale, non come
  "zero eventi";
- `toBlock` NON deve mai superare la testa dell'endpoint che si sta
  interrogando: con più endpoint le teste differiscono di qualche
  blocco, e chiedere a un nodo un intervallo che finisce oltre la sua
  testa produce risposte vuote o errori che il bot ha registrato come
  BLIND(1) (gara osservata in esercizio). La testa si legge dallo
  STESSO endpoint subito prima della query, e il cursore avanza solo
  fino a quella.

Telegram: bot creato con @BotFather, gruppo privato del team dedicato
SOLO agli alert (se ci si chiacchiera dentro, gli alert si perdono).
Il token del bot in variabile d'ambiente, mai nel codice.

Heartbeat ogni 6 ore: "Monitor attivo. Ultimo controllo: [ora]. Pool:
[riserve]. Ramo marketing: 0 esecuzioni da sempre. Nessuna anomalia."
Se smette di arrivare, il bot è caduto.

## NOTE PER CHI IMPLEMENTA

Cominciare dalla Fase 1 e basta; le successive quando la prima gira
stabile da qualche settimana. Le soglie sono un punto di partenza, non
un dogma: dopo qualche settimana si scopre cosa serve e cosa è rumore.
Ogni controllo è una funzione separata richiamata dal ciclo
principale. Nessuna chiave privata, mai: se in futuro servisse una
funzione che firma (es. il poke automatico), va in un processo
separato con un wallet dedicato che contiene solo il gas necessario.
