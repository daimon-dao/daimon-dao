# Security Policy — Daimon DAO

Questa pagina spiega come segnalare vulnerabilità in modo responsabile.
Per il modello di minaccia tecnico completo (attori, difese, limiti noti,
assunzioni di fiducia) vedi [THREAT_MODEL.md](THREAT_MODEL.md).

## Come segnalare una vulnerabilità

Se pensi di aver trovato una vulnerabilità nei contratti, negli script di
deploy o nella dApp, **non aprire una issue pubblica e non pubblicarla**:
una vulnerabilità resa pubblica prima della correzione mette a rischio i
fondi degli utenti.

Usa il canale privato di GitHub, direttamente da questo repository:

> **Security → Report a vulnerability** (Private Vulnerability Reporting)

La segnalazione arriva solo ai maintainer, che possono discuterla con te
in privato. Una volta risolta, pubblichiamo un advisory coordinato e — se
lo desideri — il tuo contributo viene accreditato pubblicamente.

### Cosa includere

- descrizione del problema e contratto/file interessato;
- impatto stimato (fondi a rischio? governance? DoS?);
- passi per riprodurre — una PoC in Foundry (`forge test`) è l'ideale;
- eventuale proposta di fix, se ne hai una.

## Tempi di risposta

Progetto mantenuto attivamente ma da un team piccolo; tempi *best effort*:

| Passo | Entro |
|---|---|
| Conferma di ricezione | 72 ore |
| Prima valutazione (severità, piano) | 7 giorni |
| Fix o mitigazione per problemi critici | il prima possibile, con priorità assoluta |

Ti terremo aggiornato nel thread privato ad ogni passaggio. Chiediamo in
cambio disclosure coordinata: nessuna pubblicazione prima del fix e
dell'advisory (concordiamo insieme i tempi).

## Scope

**In scope:** i contratti in `src/` (`DaimonV2`, `DaimonStaking`,
`DaimonGovernor`, `DaimonTimelock`, `DaimonMigration`), gli script di
deploy in `script/` e la dApp (`daimon-dapp/`).

**Fuori scope:** siti terzi, RPC pubblici, dipendenze upstream (segnalale
ai rispettivi progetti — es. OpenZeppelin ha un proprio programma su
Immunefi), social engineering, e tutto ciò che riguarda esclusivamente
la rete di test.

## Bug bounty

Al momento **non esiste un programma di bug bounty formale**: arriverà
con il lancio su mainnet. Le segnalazioni responsabili ricevute prima del
lancio verranno comunque riconosciute pubblicamente nell'advisory e — a
discrezione del progetto — potranno essere premiate retroattivamente
all'avvio del programma.

## Stato del progetto

Contratti deployati e verificati su BSC **testnet**; suite di test
(unit + fuzz + invariant) e analisi statica Slither eseguite. **Non
ancora sottoposti ad audit professionale esterno.** Il deploy mainnet
avverrà solo dopo l'audit.
