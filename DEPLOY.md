# Deploy su BSC Testnet — Daimon DAO

Guida passo passo per deployare l'intero stack (token DaimonV2 + staking +
governor + timelock + migration + mock del vecchio Daimon) su BSC testnet
(chain id 97) con Foundry.

## Cosa fa lo script

[script/Deploy.s.sol](script/Deploy.s.sol) deploya, in un'unica esecuzione:

1. **MockOldDaimon** — replica del vecchio token con fee 5%, l'intera
   old-supply al deployer (per testare la migrazione). Saltato se imposti
   `OLD_DAIMON` nell'ambiente.
2. **DaimonV2** implementation + **proxy ERC1967** con `initialize()`
   atomica. Il `_migrationContract` passato a initialize è la **vera
   DaimonMigration**, il cui indirizzo viene precalcolato dal nonce CREATE
   del deployer: l'intera supply nasce già nel contratto di migrazione,
   escluso dalle fee, senza mai transitare da un EOA.
3. **DaimonStaking**, **DaimonTimelock** (minDelay 7 giorni),
   **DaimonGovernor** (quorum 10%, threshold 1000 DMN), **DaimonMigration**
   (finestra 30 giorni, configurabile).
4. **Wiring completo**: governor = proposer + executor del timelock,
   timelock = governance di token e staking, e **rinuncia finale a tutti i
   ruoli bootstrap del deployer** (inclusa l'ADMIN_ROLE del timelock).
5. **Assert on-chain finali**: lo script fallisce se un EOA detiene ancora
   un ruolo amministrativo o se la supply non è interamente nella migration.

> Il guardian conserva solo pausa (token) e cancel (timelock/governor), per
> design. Su testnet può essere il deployer; **in produzione deve essere un
> multisig**, e treasury/marketing wallet indirizzi dedicati.

## 1. Prerequisiti

- Foundry installato (`forge --version`). Se manca:
  scarica `foundry_stable_win32_amd64.zip` dalle release di
  https://github.com/foundry-rs/foundry e metti i binari nel PATH,
  oppure su Linux/macOS: `curl -L https://foundry.paradigm.xyz | bash && foundryup`
- Dipendenze del progetto già in `lib/` (`forge build` deve passare).

## 2. BNB testnet dal faucet

1. Crea/usa un wallet **dedicato al deploy su testnet** (mai il wallet
   principale).
2. Vai al faucet ufficiale BNB Chain: **https://www.bnbchain.org/en/testnet-faucet**
   (richiede login GitHub o un piccolo saldo BNB su mainnet a seconda del
   periodo). In alternativa: https://faucet.quicknode.com/binance-smart-chain/bnb-testnet
3. Richiedi tBNB per l'indirizzo del deployer. Il deploy completo usa
   ~14.6M di gas (misurato in simulazione): da 0.0015 tBNB a 0.1 gwei
   fino a ~0.15 tBNB se la testnet gira a 10 gwei. Con **0.5 tBNB** sei
   ampiamente coperto.
4. Verifica il saldo:
   ```sh
   cast balance <INDIRIZZO_DEPLOYER> --rpc-url bsc_testnet
   ```

## 3. Chiave privata in modo sicuro

**La chiave non va MAI hardcodata in file versionati, né passata in chiaro
nella riga di comando** (finirebbe nella history della shell).

### Opzione A — keystore cifrato (raccomandata)

```sh
cast wallet import daimon-deployer --interactive
```

Ti chiede la chiave privata (input nascosto) e una password; la salva
cifrata in `~/.foundry/keystores/daimon-deployer`. Da qui in poi usi
`--account daimon-deployer` e Foundry chiede la password al momento
dell'uso. La chiave non tocca mai né file di progetto né history.

### Opzione B — variabile d'ambiente

Copia `.env.example` in `.env` (già in `.gitignore`), compila
`PRIVATE_KEY=0x...`, poi caricala nella shell **solo per la sessione**:

```powershell
# PowerShell
Get-Content .env | Where-Object {$_ -match '^\w+='} | ForEach-Object { $k,$v = $_ -split '=',2; Set-Item "env:$k" $v }
```
```sh
# bash
source .env
```

Poi userai `--private-key $env:PRIVATE_KEY` (PowerShell) o
`--private-key $PRIVATE_KEY` (bash) al posto di `--account`.

### Configurazione ruoli (opzionale su testnet)

Nella stessa `.env` (o come variabili d'ambiente) puoi impostare
`GUARDIAN_ADDRESS`, `MARKETING_WALLET`, `TREASURY_ADDRESS`,
`ETHERSCAN_API_KEY`, `OLD_DAIMON`, `MIGRATION_DURATION`. Se le lasci vuote
lo script usa il deployer e logga un warning (accettabile solo su testnet).

## 4. Simulazione (consigliata prima del deploy)

Il comando senza `--broadcast` esegue tutto in simulazione contro la chain
reale (incluse le chiamate al router PancakeSwap testnet e gli assert
finali), **senza inviare nulla**:

```sh
forge script script/Deploy.s.sol:Deploy --rpc-url bsc_testnet --account daimon-deployer -vvv
```

Controlla nel log gli indirizzi previsti e che compaia
"Tutti gli assert di decentralizzazione sono passati."

## 5. Deploy reale

```sh
forge script script/Deploy.s.sol:Deploy `
  --rpc-url bsc_testnet `
  --account daimon-deployer `
  --broadcast `
  --verify `
  -vvv
```

(In bash sostituisci i backtick con `\`. Con l'opzione B usa
`--private-key ...` al posto di `--account ...`.)

- `--broadcast` invia le transazioni.
- `--verify` verifica automaticamente tutti i contratti su BscScan testnet
  al termine (richiede `ETHERSCAN_API_KEY` nell'ambiente, vedi sotto).
- Gli indirizzi deployati vengono stampati a fine script e salvati in
  `broadcast/Deploy.s.sol/97/run-latest.json`.

## 6. Verifica su BscScan testnet

### Automatica

Con `--verify` nel comando di deploy non serve altro. La chiave API è
unica Etherscan V2 (vale anche per BscScan): creala su
https://etherscan.io/apis e impostala come `ETHERSCAN_API_KEY`.

### Manuale (se la verifica automatica fallisce)

Le impostazioni compiler (solc 0.8.26, optimizer, `via_ir`, `evm_version
shanghai`) vengono lette da foundry.toml automaticamente. Esempi:

```sh
# Implementation del token (nessun constructor arg)
forge verify-contract <IMPL_ADDRESS> src/DaimonV2.sol:DaimonV2 --chain 97 --watch

# Proxy (constructor: implementation + initData)
forge verify-contract <PROXY_ADDRESS> lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy `
  --chain 97 --watch `
  --constructor-args $(cast abi-encode "constructor(address,bytes)" <IMPL_ADDRESS> <INIT_DATA>)

# Staking (constructor: token, governance temporanea = deployer)
forge verify-contract <STAKING_ADDRESS> src/DaimonStaking.sol:DaimonStaking --chain 97 --watch `
  --constructor-args $(cast abi-encode "constructor(address,address)" <PROXY_ADDRESS> <DEPLOYER>)
```

`<INIT_DATA>` è la calldata di `initialize(...)`: la trovi nel campo
`arguments`/`transaction.input` del proxy dentro
`broadcast/Deploy.s.sol/97/run-latest.json`. Su BscScan, dopo la verifica
del proxy usa "More Options → Is this a proxy?" per collegare l'ABI
dell'implementation.

## 7. Smoke test post-deploy

```sh
# La supply e' tutta nella migration?
cast call <PROXY> "balanceOf(address)(uint256)" <MIGRATION> --rpc-url bsc_testnet
cast call <PROXY> "totalSupply()(uint256)" --rpc-url bsc_testnet

# Il deployer non ha piu' ruoli? (GOVERNANCE_ROLE)
cast call <PROXY> "hasRole(bytes32,address)(bool)" $(cast keccak "GOVERNANCE_ROLE") <DEPLOYER> --rpc-url bsc_testnet
```

### Test della migrazione completa

Il deployer detiene l'intera old-supply del MockOldDaimon:

```sh
# 1. (facoltativo) distribuisci vecchi token a un wallet di test
cast send <OLD_DAIMON> "transfer(address,uint256)" <TESTER> 1000000000000000000000 `
  --rpc-url bsc_testnet --account daimon-deployer

# 2. il tester approva la migration sul vecchio token
cast send <OLD_DAIMON> "approve(address,uint256)" <MIGRATION> 1000000000000000000000 `
  --rpc-url bsc_testnet --account <TESTER_ACCOUNT>

# 3. claim 1:1
cast send <MIGRATION> "claim(uint256)" 1000000000000000000000 `
  --rpc-url bsc_testnet --account <TESTER_ACCOUNT>

# 4. verifica il saldo DaimonV2 ricevuto (deve essere esattamente 1:1)
cast call <PROXY> "balanceOf(address)(uint256)" <TESTER> --rpc-url bsc_testnet
```

Nota: lo script ha già eseguito il passaggio preparatorio
`oldToken.excludeFromFee(treasury)`; senza, `claim()` reverterebbe con
`AmountMismatch` (protezione by-design contro fee inattese).

## Riferimenti rete

| | |
|---|---|
| Chain id | 97 |
| RPC | https://data-seed-prebsc-1-s1.binance.org:8545 (alias `bsc_testnet` in foundry.toml) |
| Explorer | https://testnet.bscscan.com |
| Router PancakeSwap V2 | `0xD99D1c33F9fC3444f8101754aBC46c52416550D1` |
| Faucet | https://www.bnbchain.org/en/testnet-faucet |
