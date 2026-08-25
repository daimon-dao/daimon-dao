// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {DaimonV2} from "../src/DaimonV2.sol";
import {DaimonStaking} from "../src/DaimonStaking.sol";
import {DaimonGovernor} from "../src/DaimonGovernor.sol";
import {DaimonTimelock} from "../src/DaimonTimelock.sol";
import {DaimonMigration} from "../src/DaimonMigration.sol";

/*
 * PHASE 2 of the two-phase Daimon DAO deploy: Timelock + Staking + Governor,
 * wiring, role transfers, final renounce.
 *
 * The guardian expiry passed to the Timelock and Governor constructors is
 * READ FROM THE LIVE TOKEN at line (A) below. The token was mined in phase 1,
 * so token.guardianExpiry() here is real chain state, identical in simulation
 * and broadcast -- and since the constructors copy the argument verbatim into
 * an immutable, the three contracts carry the SAME value by construction.
 * No file and no human ever carries the expiry: a stale or hand-typed value
 * is not "detected", it is impossible, because there is no input to type.
 *
 * The preflight refuses to broadcast anything unless the world is exactly as
 * phase 1 left it: right chain, right deployer, deployer nonce untouched,
 * code where phase 1 deployed it, no code where the timelock must land, the
 * supply still in the migration, and the migration's immutable governance
 * pointing at the address this phase's FIRST create will occupy.
 *
 * If the preflight fails: do NOT work around it. Nothing public has happened
 * between the phases; the safe recovery is to abandon the phase-1 contracts
 * and rerun phase 1 fresh. If phase 2 itself is interrupted mid-broadcast,
 * resume it with --resume (a fresh rerun would shift nonces and refuse).
 */
contract DeployPhase2 is Script {
    uint256 internal constant TIMELOCK_MIN_DELAY = 7 days;      // = MIN_DELAY hardcoded in the timelock
    uint256 internal constant QUORUM_BPS = 1000;                // 10%
    uint256 internal constant PROPOSAL_THRESHOLD = 1000 ether;  // 1000 DMN of voting power to propose

    function run() external {
        // ---- 0. Load the phase-1 state file ----
        string memory path = string.concat("deployments/two-phase-", vm.toString(block.chainid), ".json");
        string memory json = vm.readFile(path);
        uint256 fileChainId = vm.parseJsonUint(json, ".chainId");
        address fileDeployer = vm.parseJsonAddress(json, ".deployer");
        address guardian = vm.parseJsonAddress(json, ".guardian");
        DaimonV2 token = DaimonV2(payable(vm.parseJsonAddress(json, ".token")));
        DaimonMigration migration = DaimonMigration(vm.parseJsonAddress(json, ".migration"));
        address predictedTimelock = vm.parseJsonAddress(json, ".predictedTimelock");
        uint256 expectedNonce = vm.parseJsonUint(json, ".expectedPhase2Nonce");
        address fileTreasury = vm.parseJsonAddress(json, ".treasury");
        bool treasuryOverridden = vm.parseJsonBool(json, ".treasuryOverridden");

        vm.startBroadcast();
        (, address deployer,) = vm.readCallers();

        // ---- 1. Preflight: refuse loudly before broadcasting anything ----
        // Every check reads LIVE chain state; the file is never trusted on
        // its own. A failure here has broadcast nothing.
        require(fileChainId == block.chainid, "Phase2: state file is for another chain");
        require(fileDeployer == deployer, "Phase2: broadcaster differs from the phase-1 deployer");
        require(address(token).code.length > 0, "Phase2: no code at the token address");
        require(address(migration).code.length > 0, "Phase2: no code at the migration address");
        require(predictedTimelock.code.length == 0, "Phase2: predicted timelock address already has code");
        require(
            vm.getNonce(deployer) == expectedNonce,
            "Phase2: deployer nonce moved since phase 1 - the predicted timelock is unreachable. Abandon and redeploy phase 1."
        );
        require(
            migration.governance() == predictedTimelock,
            "Phase2: migration.governance does not match the predicted timelock"
        );
        // The treasury IS the Timelock (derived in phase 1). The testnet
        // override is re-guarded here too: a state file produced with the
        // override can never drive a mainnet phase 2.
        require(migration.treasury() == fileTreasury, "Phase2: migration.treasury does not match the state file");
        if (treasuryOverridden) {
            require(block.chainid != 56, "Phase2: the state file carries a testnet treasury override - not valid on BSC mainnet");
            console2.log("!!! TESTNET-ONLY treasury override active on this deploy:", fileTreasury);
        } else {
            require(fileTreasury == predictedTimelock, "Phase2: state file treasury is not the predicted timelock");
        }
        require(address(migration.newDaimon()) == address(token), "Phase2: migration is not bound to this token");
        require(
            token.balanceOf(address(migration)) == token.INITIAL_SUPPLY(),
            "Phase2: supply is not sitting in the migration"
        );
        require(token.hasRole(token.GUARDIAN_ROLE(), guardian), "Phase2: guardian mismatch with the live token");
        require(token.hasRole(token.GOVERNANCE_ROLE(), deployer), "Phase2: deployer lacks the temporary governance role");

        // ---- (A) The guardian expiry, from the LIVE token ----
        // This is the entire point of the two-phase deploy: the value below
        // was computed by initialize() in the block phase 1 was MINED in.
        // Reading it now -- after mining -- makes it the same in simulation
        // and in the broadcast, so the three contracts cannot diverge.
        uint256 guardianAuthorityExpiry = token.guardianExpiry();
        require(guardianAuthorityExpiry > block.timestamp, "Phase2: token guardian expiry is not in the future");
        console2.log("Guardian expiry read from live token:", guardianAuthorityExpiry);

        // ---- 2. Timelock: MUST land on the address phase 1 predicted ----
        // First create of this phase. Deployer as proposer/executor/admin
        // for bootstrap ONLY.
        DaimonTimelock timelock =
            new DaimonTimelock(TIMELOCK_MIN_DELAY, deployer, deployer, guardian, deployer, guardianAuthorityExpiry);
        require(address(timelock) == predictedTimelock, "Phase2: timelock missed the predicted address");

        // ---- 3. Staking (temporary governance: deployer) ----
        DaimonStaking staking = new DaimonStaking(address(token), deployer);

        // ---- 4. Governor ----
        DaimonGovernor governor =
            new DaimonGovernor(address(staking), address(timelock), guardian, QUORUM_BPS, PROPOSAL_THRESHOLD, guardianAuthorityExpiry);

        // ---- 5. Role wiring (unchanged from the single-phase script) ----
        // Governor: proposer (queue) and executor (execute calls the timelock
        // with msg.sender = governor).
        timelock.grantRole(timelock.PROPOSER_ROLE(), address(governor));
        timelock.grantRole(timelock.EXECUTOR_ROLE(), address(governor));
        // Canceller (#26): il Governor cancella atomicamente nel Timelock
        // l'operazione di una proposta in coda che il guardian annulla. Il
        // guardian CONSERVA il suo CANCELLER diretto (percorso d'emergenza
        // se il Governor fosse compromesso), entrambi scadono con
        // guardianAuthorityExpiry.
        timelock.grantRole(timelock.CANCELLER_ROLE(), address(governor));
        timelock.revokeRole(timelock.PROPOSER_ROLE(), deployer);
        timelock.revokeRole(timelock.EXECUTOR_ROLE(), deployer);

        staking.setGovernance(address(timelock), true);
        staking.setGovernance(deployer, false);

        token.setStakingContract(address(staking));

        // Quota operativa a ZERO dal primo blocco: decisione di compliance
        // legale, non di tokenomics. Il 100% della quota marketing dei fee
        // swap va agli staker finche' non esiste un'entita' giuridica che
        // possa ricevere la parte operativa. Senza questa riga, tra il
        // deploy e la prima proposta eseguita (minimo 13 giorni) il 40%
        // fluirebbe al marketingWallet. Con share = 1000 il calcolo
        // (marketingEth * 1000) / 1000 e' esatto: toMarketingWallet e' zero
        // per qualsiasi importo e la call verso il wallet non parte proprio.
        // Il ripristino di una quota operativa, quando l'entita' esistera',
        // passa da una proposta di governance (setStakingRewardShareBps).
        token.setStakingRewardShareBps(1000);

        token.grantRole(token.GOVERNANCE_ROLE(), address(timelock));
        token.revokeRole(token.GOVERNANCE_ROLE(), deployer);

        // ---- 6. Final renounce: the deployer loses the last bootstrap role ----
        timelock.renounceRole(timelock.ADMIN_ROLE(), deployer);

        vm.stopBroadcast();

        _assertPhase2(token, staking, timelock, governor, migration, deployer, guardian, fileTreasury, treasuryOverridden);

        // ---- 7. Rewrite the state file, complete: phase 1 + phase 2 ----
        // (three-arg writeJson replaces a key, it does not merge objects;
        // re-serializing everything keeps one authoritative record)
        string memory j2 = "complete";
        vm.serializeUint(j2, "chainId", block.chainid);
        vm.serializeAddress(j2, "deployer", deployer);
        vm.serializeAddress(j2, "guardian", guardian);
        vm.serializeAddress(j2, "marketingWallet", vm.parseJsonAddress(json, ".marketingWallet"));
        vm.serializeAddress(j2, "treasury", vm.parseJsonAddress(json, ".treasury"));
        vm.serializeAddress(j2, "router", vm.parseJsonAddress(json, ".router"));
        vm.serializeAddress(j2, "oldDaimon", vm.parseJsonAddress(json, ".oldDaimon"));
        vm.serializeAddress(j2, "tokenImplementation", vm.parseJsonAddress(json, ".tokenImplementation"));
        vm.serializeAddress(j2, "token", address(token));
        vm.serializeAddress(j2, "migration", address(migration));
        vm.serializeAddress(j2, "timelock", address(timelock));
        vm.serializeAddress(j2, "staking", address(staking));
        vm.serializeAddress(j2, "governor", address(governor));
        vm.serializeBool(j2, "treasuryOverridden", treasuryOverridden);
        string memory out = vm.serializeUint(j2, "guardianAuthorityExpiry", token.guardianExpiry());
        vm.writeJson(out, path);
        _logDeployment(token, staking, timelock, governor, migration);
    }

    /// Phase-2 asserts: the 17 original decentralization asserts that need
    /// the governance contracts, plus 3 linkage asserts (20 total). Note the
    /// expiry-parity ones are now meaningful even here: all three values are
    /// either live chain state or a constructor argument copied verbatim.
    /// The authoritative gate remains script/verify-deploy.ps1.
    function _assertPhase2(
        DaimonV2 token,
        DaimonStaking staking,
        DaimonTimelock timelock,
        DaimonGovernor governor,
        DaimonMigration migration,
        address deployer,
        address guardian,
        address expectedTreasury,
        bool treasuryOverridden
    ) internal view {
        // Token: governed only by the timelock, no DEFAULT_ADMIN assigned.
        require(token.hasRole(token.GOVERNANCE_ROLE(), address(timelock)), "assert: timelock does not govern the token");
        require(!token.hasRole(token.GOVERNANCE_ROLE(), deployer), "assert: deployer still governs the token");
        require(!token.hasRole(token.DEFAULT_ADMIN_ROLE(), deployer), "assert: deployer is token admin");
        // Launch compliance: operational share at zero; the deploy fails if
        // the configuration line is ever dropped.
        require(token.stakingRewardShareBps() == 1000, "assert: operational share not zero (stakingRewardShareBps != 1000)");

        // Timelock: self-administers, the deployer has no role.
        require(timelock.hasRole(timelock.ADMIN_ROLE(), address(timelock)), "assert: timelock does not self-administer");
        require(!timelock.hasRole(timelock.ADMIN_ROLE(), deployer), "assert: deployer is timelock admin");
        require(!timelock.hasRole(timelock.PROPOSER_ROLE(), deployer), "assert: deployer is proposer");
        require(!timelock.hasRole(timelock.EXECUTOR_ROLE(), deployer), "assert: deployer is executor");
        require(timelock.hasRole(timelock.PROPOSER_ROLE(), address(governor)), "assert: governor is not proposer");
        require(timelock.hasRole(timelock.EXECUTOR_ROLE(), address(governor)), "assert: governor is not executor");

        // Cancellations (#26/#36): guardian and governor can cancel while
        // the mandate lasts; the timelock can self-cancel via proposal even
        // after it. The expiry is ONE, identical across the three contracts.
        require(timelock.hasRole(timelock.CANCELLER_ROLE(), guardian), "assert: guardian is not canceller");
        require(timelock.hasRole(timelock.CANCELLER_ROLE(), address(governor)), "assert: governor is not canceller");
        require(timelock.hasRole(timelock.CANCELLER_ROLE(), address(timelock)), "assert: timelock lacks self-cancel");
        require(timelock.guardianAuthorityExpiry() == token.guardianExpiry(), "assert: timelock expiry != token");
        require(governor.guardianAuthorityExpiry() == token.guardianExpiry(), "assert: governor expiry != token");

        // Staking: governed only by the timelock.
        require(staking.isGovernance(address(timelock)), "assert: timelock does not govern staking");
        require(!staking.isGovernance(deployer), "assert: deployer still governs staking");

        // Linkage (new): the phase-1 predictions came true -- governance AND
        // treasury both resolve to the timelock deployed this phase -- and
        // the token knows its staking contract.
        require(migration.governance() == address(timelock), "assert: migration governance is not the timelock");
        if (treasuryOverridden) {
            require(migration.treasury() == expectedTreasury, "assert: migration treasury != testnet override");
        } else {
            require(migration.treasury() == address(timelock), "assert: migration treasury is not the timelock");
        }
        require(token.stakingContract() == address(staking), "assert: token staking contract mismatch");
    }

    function _logDeployment(
        DaimonV2 token,
        DaimonStaking staking,
        DaimonTimelock timelock,
        DaimonGovernor governor,
        DaimonMigration migration
    ) internal view {
        console2.log("=== PHASE 2 complete - Daimon DAO deploy done ===");
        console2.log("DaimonV2 (proxy):        ", address(token));
        console2.log("PancakeSwap V2 pair:     ", token.uniswapV2Pair());
        console2.log("DaimonStaking:           ", address(staking));
        console2.log("DaimonTimelock:          ", address(timelock));
        console2.log("DaimonGovernor:          ", address(governor));
        console2.log("DaimonMigration:         ", address(migration));
        console2.log("Guardian expiry (all 3): ", token.guardianExpiry());
        console2.log("All decentralization asserts passed.");
        console2.log("");
        console2.log("NEXT (mandatory launch gate): script/verify-deploy.ps1");
        console2.log("against a normal RPC - the asserts above still ran in");
        console2.log("the simulation context; the verification reads only");
        console2.log("mined state.");
    }
}
