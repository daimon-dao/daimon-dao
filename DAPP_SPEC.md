# DAPP_SPEC.md — Specifica dApp Daimon (DMN)

Specifica completa per la costruzione della dApp. Da leggere insieme al
repository dei contratti (già deployati e verificati su BSC testnet) e a
TESTNET_RESULTS.md per gli indirizzi.

---

## 1. Stack tecnico

```
Framework:        Next.js 14+ (App Router) + TypeScript
Styling:          TailwindCSS
Wallet/chain:     wagmi v2 + viem (NO web3.js, NO ethers)
Wallet supportati: MetaMask, WalletConnect, Trust Wallet (via connectors wagmi)
Chain:            BSC testnet (97) ora, BSC mainnet (56) predisposto
                  → config chain e indirizzi contratti in un unico file
                    src/config/contracts.ts con switch per chainId
Deploy frontend:  build statica compatibile con Vercel
```

Gli indirizzi dei contratti testnet sono nel repo (TESTNET_RESULTS.md /
broadcast JSON del deploy). Gli ABI vanno generati dagli artifact Foundry
(out/) — non ricopiarli a mano.

## 2. Design system

```
TEMA: dark mode di default (blu notte), light mode disponibile via toggle.

Colori brand:
  Blu notte (bg principale):    #0a1128
  Blu notte chiaro (card):      #111b3a
  Bordi:                        #2a3655
  Oro (accent, CTA, valori):    #c9a227
  Oro chiaro (testi titolo):    #f5e9c8
  Testo secondario:             #8a94ad
  Verde (successo/governance):  #5dcaa5
  Rosso (solo errori):          #e24b4a

Light mode: stessi accenti oro, superfici bianche/grigio caldo chiaro,
testo blu notte.

Font: sans-serif pulito (Inter o simile). Numeri importanti: 500 weight.
NO gradienti pesanti, NO effetti neon. Sobrio, professionale, "banca svizzera crypto".

LOGO: non ancora disponibile. Predisporre un componente <Logo /> usato in
header e favicon che ora mostra un cerchio con bordo oro tratteggiato e
testo "LOGO"; verrà sostituito con il file definitivo (PNG/SVG) quando
fornito. Prevedere che il file finale andrà in /public/logo.svg.
```

## 3. Struttura pagine

```
/            Dashboard (home)
/migrazione  Migrazione 1:1 dal vecchio Daimon
/staking     Stake, posizioni, reward
/governance  Proposte, voto, queue/execute
```

Header persistente: logo + nome DAIMON, nav (Dashboard, Migrazione,
Staking, Governance), pulsante Connetti wallet (oro). Footer sobrio con
link ai contratti su BscScan.

## 4. Dashboard (home) — priorità del progetto

Funziona ANCHE senza wallet connesso (tutte letture pubbliche on-chain).

**Metric cards (griglia 4):**
1. Supply attuale (totalSupply, formattata es. "987.4B DMN")
2. Token bruciati (INITIAL_SUPPLY - totalSupply) con sottotitolo "verso il floor 21B"
3. Totale stakato (totalStakedAmount dallo staking) con % della supply
4. Prezzo DMN + market cap — NUMERO SOBRIO:
   - solo il valore attuale, NIENTE variazione % 24h, NIENTE frecce
     verdi/rosse, NIENTE grafici (decisione esplicita del proprietario)
   - fonte primaria: lettura on-chain delle reserve della pair PancakeSwap
     (getReserves → prezzo in BNB → USD via prezzo BNB da API pubblica)
   - fallback: API DexScreener
   - su testnet: mostrare "n/d (testnet)" se la pool non ha liquidità sensata

**Barra di deflazione (elemento centrale, full width):**
- Progresso da 1000B verso 21B, riempimento oro
- Etichette: "1000B → 21B", quantità bruciata
- Sotto, la frase chiave sempre visibile:
  "Quando il floor sarà raggiunto, il 100% della revenue andrà agli staker"

**Card di accesso rapido (2):**
- "Il tuo staking" → se wallet non connesso: "Connetti il wallet per
  vedere posizioni e reward" (MAI mostrare zeri finti)
- Proposta di governance più recente con stato e countdown → link a /governance

**Verificabilità:** ogni metric card ha una piccola icona/link che apre il
contratto relativo su BscScan (testnet.bscscan.com per chain 97).

## 5. Migrazione — percorso guidato, non form

Wizard in 3 passi visivi:

```
1. CONNETTI    → wallet connect; rileva automaticamente il balance di
                 vecchi Daimon dell'utente e lo mostra
2. APPROVA     → bottone "Approva la migrazione" (approve sul vecchio
                 token verso DaimonMigration, importo = balance rilevato,
                 modificabile). Stato tx visibile (pending/confermata).
3. RICEVI DMN  → bottone "Migra ora" (claim). A successo: schermata di
                 conferma con importo DMN ricevuto 1:1 e link alla tx.
```

- Mostrare deadline della migrazione (migrationDeadline) con countdown.
- Se deadline passata: messaggio chiaro, wizard disabilitato.
- Errori tradotti in italiano comprensibile (es. AmountMismatch →
  "Il contratto ha rilevato una discrepanza negli importi. Riprova o
  contatta il supporto — i tuoi fondi non sono stati toccati.")
- Zero gergo tecnico nelle etichette.

## 6. Staking — con simulatore

**Simulatore (parte alta, funziona anche senza wallet):**
- Slider importo + selezione lock (30/90/180/365 gg dalle lockOptions
  on-chain, con i multiplier reali 1x/1.5x/2.2x/4x)
- Anteprima live: "Otterrai X voting power" + controvalore ≈ $ dell'importo
- Data di sblocco calcolata e mostrata in chiaro

**Azione stake:** approve (se serve) + stake, con stati tx chiari.

**Le tue posizioni (wallet connesso):**
- Lista dei lock: importo, multiplier, voting power, data sblocco,
  countdown, bottone "Ritira" attivo solo a scadenza (altrimenti
  disabilitato con tooltip "Sbloccabile il …")
- Reward maturati in BNB con controvalore ≈ $ e bottone "Riscuoti"

## 7. Governance — con countdown visibili

**Lista proposte** (leggere da eventi ProposalCreated + stato da state()):
ogni card mostra: id, descrizione, proponente (troncato), fase corrente
con countdown:

```
In attesa      → "Il voto apre tra …"
In votazione   → barre Sì/No/Astenuti con pesi, "termina tra …", bottoni
                 di voto (attivi solo con voting power allo snapshot > 0)
Approvata      → bottone "Metti in coda" (queue)
In timelock    → countdown 7 giorni, poi bottone "Esegui" (execute)
Eseguita/Bocciata/Annullata → badge di stato
```

- Mostrare il quorum: "Quorum: X / Y richiesto (10%)" con barra.
- Il voting power dell'utente mostrato in alto: quello ALLO SNAPSHOT
  della proposta selezionata (votingPowerAt), non quello live — con
  tooltip che spiega perché ("il potere di voto è fotografato alla
  creazione della proposta per impedire manipolazioni").
- Creazione proposta: form avanzato (target, value, calldata, descrizione)
  dietro un toggle "Modalità avanzata" — i più la useranno da multisig/
  strumenti esterni, ma deve esserci.
- Il flusso queue → execute della proposta #0 testnet è il TEST END-TO-END
  della dApp: deve funzionare per il 21 luglio.

## 8. Regole trasversali (non negoziabili)

1. NIENTE dati finti: wallet non connesso → invito a connettere, non zeri.
2. Ogni transazione: stato visibile (in attesa di firma → pending →
   confermata/fallita) con link alla tx su BscScan.
3. Errori dei contratti mappati su messaggi italiani comprensibili
   (LockStillActive, VotingClosed, ContractIsPaused, AmountMismatch,
   GuardianExpired, ecc.). Mai mostrare stringhe raw di revert.
4. Se paused() è true: banner globale "Il contratto è temporaneamente in
   pausa di emergenza" e azioni disabilitate.
5. Tutti gli importi formattati leggibili (1.5M, 20B) con valore esatto
   in tooltip.
6. Responsive: mobile-first, la maggioranza degli utenti BSC è da mobile.
7. Nessun tracker/analytics di terze parti. Coerenza con la filosofia.
8. Testo interfaccia in ITALIANO (inglese predisposto come i18n futuro,
   ma non richiesto ora).

## 9. Cosa NON includere (decisioni esplicite)

- NIENTE grafici del prezzo (né candele né sparkline) — deciso.
- NIENTE variazione % 24h o indicatori rossi/verdi sul prezzo — deciso.
- NIENTE sezione lending/borrowing — arriverà in fase 2, non predisporre UI.
- NIENTE localStorage per dati sensibili.

## 10. Consegna

- Repo separato (cartella daimon-dapp) o sottocartella del monorepo, a
  tua scelta motivata.
- README con: setup locale, variabili d'ambiente, come cambiare chain
  testnet→mainnet (un solo file di config), come sostituire il logo.
- Verifica finale: connessione a BSC testnet reale, lettura dashboard,
  e simulazione completa del flusso di voto sulla proposta #0.
