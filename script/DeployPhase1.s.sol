// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {DaimonV2} from "../src/DaimonV2.sol";
import {DaimonMigration} from "../src/DaimonMigration.sol";
import {MockOldDaimon} from "../src/mocks/MockOldDaimon.sol";

/*
 * PHASE 1 of the two-phase Daimon DAO deploy: Migration + token only.
 *
 * Why two phases (Level 1 campaign, deviation A1.8): the token's
 * guardianExpiry is computed by initialize() from the block the proxy is
 * MINED in, while a single-broadcast script fixes the value it passes to the
 * Timelock/Governor constructors during SIMULATION. On a live chain the two
 * differ by however long simulation-to-inclusion takes (4 seconds observed),
 * so "one expiry, three contracts" held only in simulation. Splitting the
 * deploy makes it true by construction: phase 2 starts AFTER the token is
 * mined and reads the expiry from live chain state.
 *
 * What this phase deploys, in strict order (the nonces matter):
 *   n+0  DaimonV2 implementation
 *   n+1  ERC1967 proxy (initialize: the REAL migration address, precomputed
 *        at n+2, is fee-exempt and receives the entire supply from block one)
 *   n+2  DaimonMigration -- the LAST transaction of phase 1
 *
 * The migration's `governance` is immutable and must be the Timelock, which
 * only exists in phase 2. It is therefore bound to the PREDICTED timelock
 * address: the deployer's next CREATE after this phase, i.e. nonce n+3.
 * Phase 2 refuses to run unless its first CREATE lands exactly there (see
 * DeployPhase2.s.sol preflight). Operationally: NOTHING must be sent from
 * the deployer between the two phases. If anything goes wrong between them,
 * the recovery is to abandon these contracts and redeploy phase 1 fresh --
 * nothing public has happened yet, the only cost is gas.
 *
 * Environment variables: as the single-phase script (see DEPLOY.md), with
 * two deliberate exceptions. TREASURY_ADDRESS no longer exists: the
 * migration's immutable treasury IS the Timelock, derived from the same
 * predicted address its governance is bound to (a hand-typed treasury is a
 * launch-day input nobody should be able to get wrong). Local/testnet
 * rehearsals may set TESTNET_TREASURY_OVERRIDE instead -- loudly logged,
 * refused on BSC mainnet. And the predecessor fee exemption is NOT
 * performed here any more: it is the act that opens the migration window,
 * so it belongs AFTER the post-broadcast verification (see the launch
 * order in CHECKLIST_MAINNET.md).
 * Output: deployments/two-phase-<chainid>.json, consumed by phase 2.
 */
contract DeployPhase1 is Script {
    address internal constant PANCAKE_V2_ROUTER_TESTNET = 0xD99D1c33F9fC3444f8101754aBC46c52416550D1;

    function run() external {
        vm.startBroadcast();
        (, address deployer,) = vm.readCallers();

        address router = vm.envOr("ROUTER", PANCAKE_V2_ROUTER_TESTNET);
        address guardian = vm.envOr("GUARDIAN_ADDRESS", deployer);
        address marketingWallet = vm.envOr("MARKETING_WALLET", deployer);
        address oldDaimonAddr = vm.envOr("OLD_DAIMON", address(0));
        uint256 oldSupply = vm.envOr("OLD_SUPPLY", uint256(1_000_000_000 ether));
        uint256 migrationDuration = vm.envOr("MIGRATION_DURATION", uint256(30 days));

        // The migration's treasury is NOT an input: it is DERIVED below (the
        // treasury IS the Timelock). A separate treasury exists only for
        // local/testnet rehearsals, as an explicit and loudly logged opt-in
        // that refuses to run on BSC mainnet. The guard sits HERE, before any
        // transaction, so a production run with the override set fails in
        // simulation with nothing broadcast.
        address treasuryOverride = vm.envOr("TESTNET_TREASURY_OVERRIDE", address(0));
        bool treasuryOverridden = treasuryOverride != address(0);
        if (treasuryOverridden) {
            require(
                block.chainid != 56,
                "Phase1: TESTNET_TREASURY_OVERRIDE is not available on BSC mainnet (chain 56). The treasury IS the Timelock."
            );
            console2.log("!!! TESTNET-ONLY treasury override active - NOT a mainnet configuration:");
            console2.log("    migration treasury =", treasuryOverride);
        }

        // The migration deadline is immutable and arms the sweep: hard-stop
        // on an out-of-range duration BEFORE anything reaches the chain.
        // Mirrors DaimonMigration.MIN/MAX_MIGRATION_DURATION (the constructor
        // remains the authoritative enforcement; this only fails earlier).
        console2.log("Migration duration (days):", migrationDuration / 1 days);
        require(
            migrationDuration >= 30 days && migrationDuration <= 365 days,
            "Phase1: MIGRATION_DURATION out of range (30-365 days)"
        );

        if (guardian == deployer) {
            console2.log("WARNING: GUARDIAN_ADDRESS = deployer. Acceptable on testnet ONLY.");
        }
        if (marketingWallet == deployer) {
            console2.log("WARNING: marketing = deployer. Acceptable on testnet ONLY.");
        }

        // ---- 1. Old Daimon: mock on testnet if not provided ----
        // NOTE: the mock's fee exemption for the treasury is NOT set here any
        // more. Without it, claim() reverts with AmountMismatch (#29) -- and
        // that is now the point: the exemption is the act that makes claims
        // possible, so it happens LAST in the launch order, after both phases
        // AND the post-broadcast verification are green. Between the phases
        // no claim can occur.
        if (oldDaimonAddr == address(0)) {
            MockOldDaimon oldMock = new MockOldDaimon(oldSupply, deployer);
            oldDaimonAddr = address(oldMock);
        }

        // ---- 2. Token implementation ----
        DaimonV2 impl = new DaimonV2();

        // ---- 3. Precompute the two forward references ----
        // From here the deployer creates, with consecutive nonces:
        //   n+0 token proxy, n+1 migration     (this phase)
        //   n+2 timelock                       (FIRST create of phase 2)
        uint256 nonce = vm.getNonce(deployer);
        address predictedMigration = vm.computeCreateAddress(deployer, nonce + 1);
        address predictedTimelock = vm.computeCreateAddress(deployer, nonce + 2);

        // ---- 3b. The treasury IS the Timelock: derived, never typed ----
        // DaimonMigration.treasury is immutable and receives every migrating
        // holder's old tokens plus the post-deadline sweep. A hand-typed
        // value is exactly the class of launch-day input this design exists
        // to remove: it is the predicted timelock address, the same one the
        // migration's governance is bound to, and phase 2 verifies the
        // prediction came true for both fields.
        address treasury = treasuryOverridden ? treasuryOverride : predictedTimelock;

        // ---- 4. UUPS proxy with atomic initialize ----
        // The REAL migration is the _migrationContract: it receives the
        // entire INITIAL_SUPPLY and is fee-exempt already in initialize().
        DaimonV2 token = DaimonV2(payable(address(new ERC1967Proxy(
            address(impl),
            abi.encodeCall(DaimonV2.initialize, (
                "Daimon",
                "DMN",
                predictedMigration,
                router,
                deployer,        // temporary governance for the phase-2 wiring
                guardian,
                marketingWallet
            ))
        ))));

        // ---- 5. Migration: MUST land on the precomputed address ----
        // Its immutable governance is the PREDICTED timelock; phase 2 makes
        // the prediction come true or refuses to run. LAST tx of phase 1.
        DaimonMigration migration =
            new DaimonMigration(oldDaimonAddr, address(token), treasury, predictedTimelock, migrationDuration);
        require(address(migration) == predictedMigration, "Phase1: predicted migration address mismatch");

        vm.stopBroadcast();

        _assertPhase1(
            token, migration, deployer, guardian, marketingWallet, treasury, oldDaimonAddr, predictedTimelock, treasuryOverridden
        );

        // ---- 6. Persist what phase 2 needs ----
        // Addresses and the expected nonce only -- deliberately NO expiry
        // value: the only value phase 1 could write is the simulated one,
        // which is exactly the value the two-phase design exists to discard.
        // Phase 2's sole source for the expiry is the live token.
        string memory json = "phase1";
        vm.serializeUint(json, "chainId", block.chainid);
        vm.serializeAddress(json, "deployer", deployer);
        vm.serializeAddress(json, "guardian", guardian);
        vm.serializeAddress(json, "marketingWallet", marketingWallet);
        vm.serializeAddress(json, "treasury", treasury);
        vm.serializeAddress(json, "router", router);
        vm.serializeAddress(json, "oldDaimon", oldDaimonAddr);
        vm.serializeAddress(json, "tokenImplementation", address(impl));
        vm.serializeAddress(json, "token", address(token));
        vm.serializeAddress(json, "migration", address(migration));
        vm.serializeAddress(json, "predictedTimelock", predictedTimelock);
        vm.serializeBool(json, "treasuryOverridden", treasuryOverridden);
        string memory out = vm.serializeUint(json, "expectedPhase2Nonce", nonce + 2);
        string memory path = string.concat("deployments/two-phase-", vm.toString(block.chainid), ".json");
        vm.writeJson(out, path);

        console2.log("=== PHASE 1 complete ===");
        console2.log("DaimonV2 (proxy):     ", address(token));
        console2.log("DaimonMigration:      ", address(migration));
        console2.log("Timelock (predicted): ", predictedTimelock);
        console2.log("Migration treasury:   ", treasury, treasuryOverridden ? "(TESTNET OVERRIDE)" : "(= predicted timelock)");
        console2.log("State file:           ", path);
        console2.log("");
        console2.log("NEXT: wait for mining, then run DeployPhase2 IMMEDIATELY.");
        console2.log("Do NOT send ANY transaction from the deployer in between:");
        console2.log("a nonce change makes the predicted timelock address");
        console2.log("unreachable and phase 2 will refuse to run.");
    }

    /// Phase-1 asserts: everything checkable before the Timelock exists.
    /// 10 asserts. Note these still run in the simulation context -- the
    /// authoritative gate is script/verify-deploy.ps1 after phase 2.
    function _assertPhase1(
        DaimonV2 token,
        DaimonMigration migration,
        address deployer,
        address guardian,
        address marketingWallet,
        address treasury,
        address oldDaimonAddr,
        address predictedTimelock,
        bool treasuryOverridden
    ) internal view {
        // Supply: entirely in the migration, never through an EOA.
        require(token.totalSupply() == token.INITIAL_SUPPLY(), "assert-p1: unexpected total supply");
        require(token.balanceOf(address(migration)) == token.INITIAL_SUPPLY(), "assert-p1: supply not in migration");
        require(token.isExcludedFromFee(address(migration)), "assert-p1: migration not fee-exempt");
        // Roles as phase 2 expects to find them.
        require(token.hasRole(token.GUARDIAN_ROLE(), guardian), "assert-p1: guardian has no pause role");
        require(token.hasRole(token.GOVERNANCE_ROLE(), deployer), "assert-p1: deployer lost temporary governance");
        require(token.marketingWallet() == marketingWallet, "assert-p1: wrong marketing wallet");
        // Migration wiring (all immutable -- wrong here is wrong forever).
        require(address(migration.newDaimon()) == address(token), "assert-p1: migration.newDaimon mismatch");
        require(address(migration.oldDaimon()) == oldDaimonAddr, "assert-p1: migration.oldDaimon mismatch");
        // The treasury check is REAL now, not an echo of an input: on the
        // mainnet path it must be the predicted timelock; only the loud
        // testnet override compares against a supplied value.
        if (treasuryOverridden) {
            require(migration.treasury() == treasury, "assert-p1: migration.treasury != testnet override");
        } else {
            require(migration.treasury() == predictedTimelock, "assert-p1: migration.treasury != predicted timelock");
        }
        require(migration.governance() == predictedTimelock, "assert-p1: migration.governance != predicted timelock");
    }
}
