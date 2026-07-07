// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {DaimonV2} from "../src/DaimonV2.sol";
import {DaimonStaking} from "../src/DaimonStaking.sol";
import {DaimonGovernor} from "../src/DaimonGovernor.sol";
import {DaimonTimelock} from "../src/DaimonTimelock.sol";
import {DaimonMigration} from "../src/DaimonMigration.sol";
import {MockOldDaimon} from "../src/mocks/MockOldDaimon.sol";

/*
 * Deploy completo dello stack Daimon DAO su BSC testnet (chain id 97).
 *
 * Vincoli rispettati (emersi dai fix di sicurezza):
 *  1. La VERA DaimonMigration e' il _migrationContract passato a
 *     initialize() del token: riceve l'intera supply ed e' esclusa dalle
 *     fee fin dal primo blocco. La dipendenza circolare
 *     (token -> migration -> token) e' risolta precalcolando l'indirizzo
 *     della migration dal nonce CREATE del deployer.
 *  2. Il Timelock si auto-amministra; il deployer usa i ruoli bootstrap
 *     solo per il wiring e vi RINUNCIA tutti alla fine.
 *  3. A fine script, assert on-chain che nessun EOA detenga piu' alcun
 *     ruolo amministrativo (governance token, admin/proposer/executor
 *     timelock, governance staking).
 *
 * Variabili d'ambiente (tutte opzionali su testnet, vedi DEPLOY.md):
 *  ROUTER              default: PancakeSwap V2 router BSC testnet
 *  GUARDIAN_ADDRESS    default: deployer (SOLO testnet; in produzione multisig)
 *  MARKETING_WALLET    default: deployer (SOLO testnet)
 *  TREASURY_ADDRESS    default: deployer (SOLO testnet)
 *  OLD_DAIMON          default: vuoto -> deploya MockOldDaimon
 *  OLD_SUPPLY          default: 1_000_000_000 * 1e18 (per il mock)
 *  MIGRATION_DURATION  default: 30 giorni (in secondi)
 */
contract Deploy is Script {
    // PancakeSwap V2 Router — BSC TESTNET (chain id 97)
    address internal constant PANCAKE_V2_ROUTER_TESTNET = 0xD99D1c33F9fC3444f8101754aBC46c52416550D1;

    uint256 internal constant TIMELOCK_MIN_DELAY = 7 days;      // = MIN_DELAY hardcodato nel timelock
    uint256 internal constant QUORUM_BPS = 1000;                // 10%
    uint256 internal constant PROPOSAL_THRESHOLD = 1000 ether;  // 1000 DMN di voting power per proporre

    function run() external {
        vm.startBroadcast();

        // Broadcaster REALE (da --account/--private-key): msg.sender non e'
        // affidabile qui — con --account senza --sender resterebbe il
        // DefaultSender di Foundry e la predizione del nonce fallirebbe.
        (, address deployer,) = vm.readCallers();

        address router = vm.envOr("ROUTER", PANCAKE_V2_ROUTER_TESTNET);
        address guardian = vm.envOr("GUARDIAN_ADDRESS", deployer);
        address marketingWallet = vm.envOr("MARKETING_WALLET", deployer);
        address treasury = vm.envOr("TREASURY_ADDRESS", deployer);
        address oldDaimonAddr = vm.envOr("OLD_DAIMON", address(0));
        uint256 oldSupply = vm.envOr("OLD_SUPPLY", uint256(1_000_000_000 ether));
        uint256 migrationDuration = vm.envOr("MIGRATION_DURATION", uint256(30 days));

        if (guardian == deployer) {
            console2.log("ATTENZIONE: GUARDIAN_ADDRESS = deployer. Accettabile SOLO su testnet.");
        }
        if (treasury == deployer || marketingWallet == deployer) {
            console2.log("ATTENZIONE: treasury/marketing = deployer. Accettabile SOLO su testnet.");
        }

        // ---- 1. Vecchio Daimon: mock su testnet se non fornito ----
        if (oldDaimonAddr == address(0)) {
            MockOldDaimon oldMock = new MockOldDaimon(oldSupply, deployer);
            oldDaimonAddr = address(oldMock);
            // Passaggio preparatorio della migrazione: senza l'esclusione
            // della treasury dalle fee del vecchio token, claim() reverte
            // con AmountMismatch (per design, a protezione degli utenti).
            oldMock.excludeFromFee(treasury);
        }

        // ---- 2. Implementation del token (initialize disabilitata dal constructor) ----
        DaimonV2 impl = new DaimonV2();

        // ---- 3. Precalcolo dell'indirizzo della DaimonMigration ----
        // Da qui in poi il deployer creera', con nonce consecutivi:
        //   +0 proxy del token, +1 staking, +2 timelock, +3 governor, +4 migration
        uint256 nonce = vm.getNonce(deployer);
        address predictedMigration = vm.computeCreateAddress(deployer, nonce + 4);

        // ---- 4. Proxy UUPS con initialize atomica ----
        // La VERA migration e' il _migrationContract: riceve l'intera
        // INITIAL_SUPPLY ed e' esclusa dalle fee gia' in initialize().
        // Nessun EOA "ponte" tocca mai la supply.
        DaimonV2 token = DaimonV2(payable(address(new ERC1967Proxy(
            address(impl),
            abi.encodeCall(DaimonV2.initialize, (
                "Daimon",
                "DMN",
                predictedMigration,
                router,
                deployer,        // governance temporanea per il wiring, revocata al punto 9
                guardian,
                marketingWallet
            ))
        ))));

        // ---- 5. Staking (governance temporanea: deployer) ----
        DaimonStaking staking = new DaimonStaking(address(token), deployer);

        // ---- 6. Timelock: deployer proposer/executor/admin SOLO per bootstrap ----
        DaimonTimelock timelock = new DaimonTimelock(TIMELOCK_MIN_DELAY, deployer, deployer, guardian, deployer);

        // ---- 7. Governor ----
        DaimonGovernor governor =
            new DaimonGovernor(address(staking), address(timelock), guardian, QUORUM_BPS, PROPOSAL_THRESHOLD);

        // ---- 8. Migration: DEVE atterrare sull'indirizzo precalcolato ----
        DaimonMigration migration =
            new DaimonMigration(oldDaimonAddr, address(token), treasury, address(timelock), migrationDuration);
        require(address(migration) == predictedMigration, "Deploy: predicted migration address mismatch");

        // ---- 9. Wiring dei ruoli ----
        // Governor: proposer (queue) ed executor (execute chiama il timelock
        // con msg.sender = governor).
        timelock.grantRole(timelock.PROPOSER_ROLE(), address(governor));
        timelock.grantRole(timelock.EXECUTOR_ROLE(), address(governor));
        timelock.revokeRole(timelock.PROPOSER_ROLE(), deployer);
        timelock.revokeRole(timelock.EXECUTOR_ROLE(), deployer);

        staking.setGovernance(address(timelock), true);
        staking.setGovernance(deployer, false);

        token.setStakingContract(address(staking));
        token.grantRole(token.GOVERNANCE_ROLE(), address(timelock));
        token.revokeRole(token.GOVERNANCE_ROLE(), deployer);

        // ---- 10. Rinuncia finale: il deployer perde l'ultimo ruolo bootstrap ----
        // Da qui il timelock amministra solo se stesso (le rotazioni di
        // ruolo passano da proposte di governance).
        timelock.renounceRole(timelock.ADMIN_ROLE(), deployer);

        vm.stopBroadcast();

        _assertDecentralized(token, staking, timelock, governor, migration, deployer, guardian);
        _logDeployment(token, impl, staking, timelock, governor, migration, oldDaimonAddr);
    }

    /// Assert on-chain: nessun EOA detiene piu' ruoli amministrativi.
    /// (Il guardian conserva SOLO pausa/cancel, per design; in produzione
    /// deve essere un multisig.)
    function _assertDecentralized(
        DaimonV2 token,
        DaimonStaking staking,
        DaimonTimelock timelock,
        DaimonGovernor governor,
        DaimonMigration migration,
        address deployer,
        address guardian
    ) internal view {
        // Token: governa solo il timelock, nessun DEFAULT_ADMIN assegnato.
        require(token.hasRole(token.GOVERNANCE_ROLE(), address(timelock)), "assert: timelock non governa il token");
        require(!token.hasRole(token.GOVERNANCE_ROLE(), deployer), "assert: deployer governa ancora il token");
        require(!token.hasRole(token.DEFAULT_ADMIN_ROLE(), deployer), "assert: deployer admin del token");
        require(token.hasRole(token.GUARDIAN_ROLE(), guardian), "assert: guardian senza ruolo pausa");

        // Timelock: si auto-amministra, il deployer non ha alcun ruolo.
        require(timelock.hasRole(timelock.ADMIN_ROLE(), address(timelock)), "assert: timelock non si autoamministra");
        require(!timelock.hasRole(timelock.ADMIN_ROLE(), deployer), "assert: deployer admin del timelock");
        require(!timelock.hasRole(timelock.PROPOSER_ROLE(), deployer), "assert: deployer proposer");
        require(!timelock.hasRole(timelock.EXECUTOR_ROLE(), deployer), "assert: deployer executor");
        require(timelock.hasRole(timelock.PROPOSER_ROLE(), address(governor)), "assert: governor non proposer");
        require(timelock.hasRole(timelock.EXECUTOR_ROLE(), address(governor)), "assert: governor non executor");

        // Staking: governa solo il timelock.
        require(staking.isGovernance(address(timelock)), "assert: timelock non governa lo staking");
        require(!staking.isGovernance(deployer), "assert: deployer governa ancora lo staking");

        // Supply: interamente nella migration, mai transitata da un EOA.
        require(token.balanceOf(address(migration)) == token.INITIAL_SUPPLY(), "assert: supply non in migration");
        require(token.totalSupply() == token.INITIAL_SUPPLY(), "assert: supply totale inattesa");
    }

    function _logDeployment(
        DaimonV2 token,
        DaimonV2 impl,
        DaimonStaking staking,
        DaimonTimelock timelock,
        DaimonGovernor governor,
        DaimonMigration migration,
        address oldDaimonAddr
    ) internal view {
        console2.log("=== Daimon DAO - deploy completato ===");
        console2.log("DaimonV2 (proxy):        ", address(token));
        console2.log("DaimonV2 (implementation):", address(impl));
        console2.log("Pair PancakeSwap V2:     ", token.uniswapV2Pair());
        console2.log("DaimonStaking:           ", address(staking));
        console2.log("DaimonTimelock:          ", address(timelock));
        console2.log("DaimonGovernor:          ", address(governor));
        console2.log("DaimonMigration:         ", address(migration));
        console2.log("Vecchio Daimon:          ", oldDaimonAddr);
        console2.log("Tutti gli assert di decentralizzazione sono passati.");
    }
}
