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
DaimonMigration, pair DMN/WBNB, e il marketingWallet — che si osserva
proprio perché non deve ricevere mai nulla.

### Alert urgenti

L'INVARIANTE: qualsiasi movimento IN ENTRATA verso il marketingWallet,
di qualsiasi importo, da qualsiasi origine. Questo alert non deve
suonare mai: se suona, la configurazione del deploy è sbagliata
(stakingRewardShareBps != 1000) o sta accadendo qualcosa di non
previsto. L'heartbeat riporta lo stato a ogni battito: "marketing
wallet: 0 movimenti da sempre".

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

### Cosa NON osservare

Ogni transazione. Variazioni di prezzo. Ogni nuovo holder.

## FASE 2 — LA TREASURY

Da aggiungere quando la Fase 1 gira stabile. Saldo BNB del Timelock e
di ogni BEP-20 rilevante (BTCB 0x7130d2A12B9BCbFAe4f2634d864A1Ee1Ce3Ead9c,
ETH 0x2170Ed0880ac9A755fd29B2688956BD959F933F8,
USDT 0x55d398326f99059fF775485246999027B3197955, DMN). Riepilogo
giornaliero con saldi e variazioni: messaggio di servizio a un'ora
fissa, non un alert.

## FASE 3 — LE ENTRATE DEL PROTOCOLLO

Tutti eventi leggibili: fee raccolte (DMN entrato nel contratto),
conversioni (BNB usciti dal fee swap), buyback (speso e bruciato),
reward agli staker (BNB arrivato allo Staking), supply (totalSupply
nel tempo e distanza dal floor). Il dato che conta: quanto il
protocollo ha generato dall'inizio, e nell'ultimo periodo. Riepilogo
settimanale.

## FASE 4 — LE POSIZIONI DEFI

Solo se e quando la treasury impiegherà le riserve. Riconoscere i
token che rappresentano posizioni (es. vUSDT = USDT su Venus),
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

Telegram: bot creato con @BotFather, gruppo privato del team dedicato
SOLO agli alert (se ci si chiacchiera dentro, gli alert si perdono).
Il token del bot in variabile d'ambiente, mai nel codice.

Heartbeat ogni 6 ore: "Monitor attivo. Ultimo controllo: [ora]. Pool:
[riserve]. Marketing wallet: 0 movimenti da sempre. Nessuna anomalia."
Se smette di arrivare, il bot è caduto.

## NOTE PER CHI IMPLEMENTA

Cominciare dalla Fase 1 e basta; le successive quando la prima gira
stabile da qualche settimana. Le soglie sono un punto di partenza, non
un dogma: dopo qualche settimana si scopre cosa serve e cosa è rumore.
Ogni controllo è una funzione separata richiamata dal ciclo
principale. Nessuna chiave privata, mai: se in futuro servisse una
funzione che firma (es. il poke automatico), va in un processo
separato con un wallet dedicato che contiene solo il gas necessario.
