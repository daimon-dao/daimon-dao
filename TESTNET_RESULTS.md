# Test manuali su BSC Testnet — Daimon DAO

Eseguiti il 2026-07-08 (notte, ora italiana). Explorer: https://testnet.bscscan.com

Deploy di riferimento (2026-07-08, tutti verificati su BscScan):

| Contratto | Indirizzo |
|---|---|
| DaimonV2 (proxy) | `0xf9a4d8b6ae6e37f198443e9855e3788119c94202` |
| DaimonStaking | `0x2f2135885617cd226214cf8fd3b945fddaea3606` |
| DaimonTimelock | `0x6a98fd0c0306672e4abfbe90fc303726022427f5` |
| DaimonGovernor | `0xe2445551f1d6c487e6cfb48f8621ccfb4d919c52` |
| DaimonMigration | `0x4c6f45b0148534296d8f9660eba5cc3598855bb2` |
| MockOldDaimon | `0xf5de50ae742df53b5b6a6bf5189f64a9d16157cc` |

Wallet coinvolti:

| Ruolo | Indirizzo |
|---|---|
| Deployer / guardian / treasury (testnet) | `0x3863962B17F322a8bbF8427f14D85094Db623A50` |
| Wallet B (test, usa-e-getta) | `0x59B1AB91c8c85D01CcC3bf16A14fA7549F98DA35` |
| Wallet C (test, usa-e-getta) | `0x0BD5122544515f2f9051f172BA9F74E290a1F984` |

Nota di design: su questa testnet deployer = treasury, quindi la migrazione
va testata da un wallet terzo — un claim del deployer avrebbe delta-treasury
pari a zero e reverterebbe con `AmountMismatch` (protezione voluta).

Setup (funding dal deployer):
- 0.05 tBNB a B — `0x5445b78b0cdf78b68b55634227a1e659073bd34b2afe86eb4e0b1b3832816077`
- 0.03 tBNB a C — `0x0911ea08fc0c0d004af8bf51ab864c047bfcc1cf68fff6f9f99747b108a1e2ff`
- 20.000.000 vecchi DMN a B — `0xce14cc06f5551639abbd7d0f4b407e7db4f128ee4f88095dc33111de6598004e`
  (nessuna fee: il mittente/treasury è escluso nel mock)

---

## Test 1 — Migrazione 1:1 ✅

**Cosa testato**: approve del vecchio token + `claim(20M)` dal wallet B;
verifica del rapporto 1:1 sui nuovi DMN e dell'arrivo dei vecchi token in
treasury.

| Passo | Tx |
|---|---|
| `approve(migration, 20M)` su MockOldDaimon (da B) | `0x96ea721f36b9392b2562e4daad7254c36d32660c68fd416eca46a3cf7fe678a6` |
| `claim(20M)` su DaimonMigration (da B) | `0xf1e5c9b117fe938de721a25dc0e003f50f121e4dbffadaa022bc6e126eb9d594` |

**Esito**: PASS.
- DMN ricevuti da B: `20.000.000,000000000000000000` — **esattamente 1:1**, zero fee (migration esclusa).
- Vecchi token in treasury: da 980M a **1.000M** (+20M esatti).
- `totalMigrated` = 20M.

**Anomalie**: nessuna.

---

## Test 2 — Transfer con fee 5% e reflection ai holder fermi ✅

**Cosa testato**: transfer B→C da 1.000.000 DMN (fee attesa 5%: 1% reflection
+ 4% al contratto), poi transfer C→deployer da 400.000 DMN con B fermo, per
verificare che il saldo di B cresca da solo (reflection).

| Passo | Tx |
|---|---|
| B→C 1.000.000 DMN | `0x22511bdc5afed8ceff8d505ffee9ec0d51ce1625cf681fd280baafaf71021a71` |
| C→deployer 400.000 DMN (B fermo) | `0x130db1697dc6d187a9c0c7d37ab3d66cacd11a4429b65803c51a816c7ffbb4d1` |

**Esito**: PASS.
- C ha ricevuto `950.000,0095…` = 95% esatto + quota reflection della sua stessa tx.
- Il contratto token ha accumulato `40.000,0004…` = 4% di liquidity fee.
- Deployer ha ricevuto `380.000,0015…` = 95% di 400k.
- **Reflection a B fermo**: saldo da `19.000.000,190000001900000019`
  a `19.000.000,266000002964000030` → **+0,076 DMN**, che coincide con la
  teoria: 4.000 DMN di tax × (19M di B / 1T di supply) = 0,076.

**Anomalie**: 1 (non del contratto). La prima rilettura del saldo di B subito
dopo la tx di C risultava invariata: era **stato stantio del nodo RPC**
`data-seed-prebsc-1`. Rilettura pochi secondi dopo su due nodi diversi ha
dato lo stesso valore aggiornato. Lezione: dopo una tx, attendere un blocco
o interrogare due nodi prima di concludere.

---

## Test 3 — Staking: voting power 1x vs 4x, lock vincolante ✅

**Cosa testato**: stake da 1.000.000 DMN a 30gg (moltiplicatore 1x, lockId 0)
e da 500.000 DMN a 365gg (4x, lockId 1); withdraw anticipato del lock 0.

| Passo | Tx |
|---|---|
| `approve(staking, 2M)` | `0x421ca87e1209aaf60d0446f25629c1f5b98d97538f35251110263c84c652cc4a` |
| `stake(1M, opzione 0)` 30gg 1x | `0x9eadcaff58d61aceb8b5dafcb5cb4bd8d60af35ea0538833f6ca588b2d0e831d` |
| `stake(500k, opzione 3)` 365gg 4x | `0xa348f6ba29a29259937518466b5c92e8678b182e03e69f77b586349a68d86b7e` |
| `withdraw(0)` anticipato | nessuna tx: revert in fase di stima gas |

**Esito**: PASS.
- `votingPower(B)` = **3.000.000 DMN esatti** (1M×1 + 500k×4). Nessuna fee
  sugli stake (lo staking è escluso dalle fee): importi contabilizzati precisi.
- `totalVotingPower` = 3M.
- Withdraw anticipato: revert con selector `0xba8dbe4c` = **`LockStillActive()`**,
  come atteso. Il lock 0 sarà ritirabile dal **2026-08-07**, il lock 1 dal
  **2027-07-08**.

**Anomalie**: nessuna.

---

## Test 4 — Governance: propose ora, vote/queue/execute a calendario ⏳

**Cosa testato**: creazione immediata della proposta #0 —
`setFees(10, 10, 20)` sul token (fee totale dal 5% al 4%) — per far partire
il cronometro; tentativo di voto immediato (deve fallire per il voting delay).

| Passo | Tx |
|---|---|
| `propose(token, 0, setFees(10,10,20), "Riduzione fee…")` da B (vp 3M ≥ threshold 1000) | `0xa6e465fb70da2b587f8ab7795a22cfc7c29bc984d571020260178b6af2cb5035` |
| `castVote(0, 1)` immediato | nessuna tx: revert `0x66b6cb4a` = **`VotingClosed()`** ✅ (voting delay di 1 giorno rispettato) |

Proposta #0 creata al timestamp `1783467501` (2026-07-07 23:38:21 UTC).

**Calendario** (ora italiana = UTC+2):

| Fase | Da | Comando |
|---|---|---|
| **Voto** | 09 lug 01:38 → 14 lug 01:38 | `cast send 0xe2445551f1d6c487e6cfb48f8621ccfb4d919c52 "castVote(uint256,uint8)" 0 1 --private-key (Get-Content .testwallets\walletB.key) --rpc-url https://data-seed-prebsc-1-s1.binance.org:8545` |
| **Queue** (chiunque) | dopo il 14 lug 01:38 | `cast send 0xe2445551f1d6c487e6cfb48f8621ccfb4d919c52 "queue(uint256)" 0 --private-key (Get-Content .testwallets\walletB.key) --rpc-url https://data-seed-prebsc-1-s1.binance.org:8545` |
| **Execute** | 7 giorni dopo la queue (≈ 21 lug 01:38) | `cast send 0xe2445551f1d6c487e6cfb48f8621ccfb4d919c52 "execute(uint256)" 0 --private-key (Get-Content .testwallets\walletB.key) --rpc-url https://data-seed-prebsc-1-s1.binance.org:8545` |
| **Verifica finale** | dopo l'execute | `cast call 0xf9a4d8b6ae6e37f198443e9855e3788119c94202 "taxFee()(uint256)" --rpc-url https://data-seed-prebsc-1-s1.binance.org:8545` → atteso 10 (e buybackFee 10, marketingFee 20) |

Stato proposta interrogabile in ogni momento:
`cast call 0xe2445551f1d6c487e6cfb48f8621ccfb4d919c52 "state(uint256)(uint8)" 0 --rpc-url …`
(0 Pending, 1 Active, 2 Defeated, 3 Succeeded, 4 Queued, 5 Executed, 6 Canceled)

**Esito parziale**: PASS (propose + delay enforcement). Voto/queue/execute da
completare a calendario.

**Anomalie**: nessuna.

---

## Test 5 — Guardian: pausa e ripresa ✅

**Cosa testato**: `setPaused(true)` dal guardian (= deployer su testnet),
transfer bloccata durante la pausa, `setPaused(false)`, transfer ripristinata.

| Passo | Tx |
|---|---|
| `setPaused(true)` | `0x2ed41803dcbc82f342b98e60fe81df9f2bb9f5c7b6b9354ad3e53f6bd57e7765` |
| transfer B→C 1.000 DMN in pausa | nessuna tx: revert `0x6d39fcd0` = **`ContractIsPaused()`** ✅ |
| `setPaused(false)` | `0x7af6de32919e19b871590471a9c5eb5f10a53b39013785bf4c862fdb714e52fd` |
| transfer B→C 1.000 DMN post-ripresa | `0xe6ebcd06dc761c15510a2eb4f4cd0c4ec6b25e636c769aa65a252f485c989aa0` ✅ |

**Esito**: PASS. `paused()` risultava `true` durante il blocco e la stessa
identica transfer è passata dopo la ripresa.

**Anomalie**: nessuna.

---

## Riepilogo

| # | Test | Esito |
|---|---|---|
| 1 | Migrazione 1:1 con treasury | ✅ PASS |
| 2 | Fee 5% + reflection ai fermi | ✅ PASS (nota RPC stantio) |
| 3 | Voting power 1x/4x + lock | ✅ PASS |
| 4 | Governance propose + delay | ✅ PASS — vote/queue/execute a calendario (9→21 lug) |
| 5 | Pausa guardian | ✅ PASS |

Le chiavi dei wallet di test B e C sono in `.testwallets/` (escluso da git):
servono ancora per votare la proposta #0 — non cancellarle fino all'execute.
