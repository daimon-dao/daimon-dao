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
 * Full deploy of the Daimon DAO stack on BSC testnet (chain id 97).
 *
 * Constraints respected (emerged from the security fixes):
 *  1. The REAL DaimonMigration is the _migrationContract passed to the
 *     token's initialize(): it receives the entire supply and is excluded
 *     from fees from the very first block. The circular dependency
 *     (token -> migration -> token) is resolved by precomputing the
 *     migration address from the deployer's CREATE nonce.
 *  2. The Timelock self-administers; the deployer uses the bootstrap roles
 *     only for the wiring and RENOUNCES them all at the end.
 *  3. At the end of the script, on-chain asserts that no EOA still holds any
 *     administrative role (token governance, timelock
 *     admin/proposer/executor, staking governance).
 *
 * Environment variables (all optional on testnet, see DEPLOY.md):
 *  ROUTER              default: PancakeSwap V2 router BSC testnet
 *  GUARDIAN_ADDRESS    default: deployer (testnet ONLY; multisig in production)
 *  MARKETING_WALLET    default: deployer (testnet ONLY)
 *  TREASURY_ADDRESS    default: deployer (testnet ONLY)
 *  OLD_DAIMON          default: empty -> deploys MockOldDaimon
 *  OLD_SUPPLY          default: 1_000_000_000 * 1e18 (for the mock)
 *  MIGRATION_DURATION  default: 30 days (in seconds)
 */
contract Deploy is Script {
    // PancakeSwap V2 Router — BSC TESTNET (chain id 97)
    address internal constant PANCAKE_V2_ROUTER_TESTNET = 0xD99D1c33F9fC3444f8101754aBC46c52416550D1;

    uint256 internal constant TIMELOCK_MIN_DELAY = 7 days;      // = MIN_DELAY hardcoded in the timelock
    uint256 internal constant QUORUM_BPS = 1000;                // 10%
    uint256 internal constant PROPOSAL_THRESHOLD = 1000 ether;  // 1000 DMN of voting power to propose

    function run() external {
        vm.startBroadcast();

        // REAL broadcaster (from --account/--private-key): msg.sender is not
        // reliable here — with --account and no --sender it would stay
        // Foundry's DefaultSender and the nonce prediction would fail.
        (, address deployer,) = vm.readCallers();

        address router = vm.envOr("ROUTER", PANCAKE_V2_ROUTER_TESTNET);
        address guardian = vm.envOr("GUARDIAN_ADDRESS", deployer);
        address marketingWallet = vm.envOr("MARKETING_WALLET", deployer);
        address treasury = vm.envOr("TREASURY_ADDRESS", deployer);
        address oldDaimonAddr = vm.envOr("OLD_DAIMON", address(0));
        uint256 oldSupply = vm.envOr("OLD_SUPPLY", uint256(1_000_000_000 ether));
        uint256 migrationDuration = vm.envOr("MIGRATION_DURATION", uint256(30 days));

        if (guardian == deployer) {
            console2.log("WARNING: GUARDIAN_ADDRESS = deployer. Acceptable on testnet ONLY.");
        }
        if (treasury == deployer || marketingWallet == deployer) {
            console2.log("WARNING: treasury/marketing = deployer. Acceptable on testnet ONLY.");
        }

        // ---- 1. Old Daimon: mock on testnet if not provided ----
        if (oldDaimonAddr == address(0)) {
            MockOldDaimon oldMock = new MockOldDaimon(oldSupply, deployer);
            oldDaimonAddr = address(oldMock);
            // Preparatory migration step: without excluding the treasury from
            // the old token's fees, claim() reverts with AmountMismatch (by
            // design, to protect users).
            oldMock.excludeFromFee(treasury);
        }

        // ---- 2. Token implementation (initialize disabled by the constructor) ----
        DaimonV2 impl = new DaimonV2();

        // ---- 3. Precompute the DaimonMigration address ----
        // From here on the deployer will create, with consecutive nonces:
        //   +0 token proxy, +1 staking, +2 timelock, +3 governor, +4 migration
        uint256 nonce = vm.getNonce(deployer);
        address predictedMigration = vm.computeCreateAddress(deployer, nonce + 4);

        // ---- 4. UUPS proxy with atomic initialize ----
        // The REAL migration is the _migrationContract: it receives the entire
        // INITIAL_SUPPLY and is excluded from fees already in initialize().
        // No "bridge" EOA ever touches the supply.
        DaimonV2 token = DaimonV2(payable(address(new ERC1967Proxy(
            address(impl),
            abi.encodeCall(DaimonV2.initialize, (
                "Daimon",
                "DMN",
                predictedMigration,
                router,
                deployer,        // temporary governance for the wiring, revoked at step 9
                guardian,
                marketingWallet
            ))
        ))));

        // ---- 5. Staking (temporary governance: deployer) ----
        DaimonStaking staking = new DaimonStaking(address(token), deployer);

        // ---- 6. Timelock: deployer as proposer/executor/admin for bootstrap ONLY ----
        DaimonTimelock timelock = new DaimonTimelock(TIMELOCK_MIN_DELAY, deployer, deployer, guardian, deployer);

        // ---- 7. Governor ----
        DaimonGovernor governor =
            new DaimonGovernor(address(staking), address(timelock), guardian, QUORUM_BPS, PROPOSAL_THRESHOLD);

        // ---- 8. Migration: MUST land on the precomputed address ----
        DaimonMigration migration =
            new DaimonMigration(oldDaimonAddr, address(token), treasury, address(timelock), migrationDuration);
        require(address(migration) == predictedMigration, "Deploy: predicted migration address mismatch");

        // ---- 9. Role wiring ----
        // Governor: proposer (queue) and executor (execute calls the timelock
        // with msg.sender = governor).
        timelock.grantRole(timelock.PROPOSER_ROLE(), address(governor));
        timelock.grantRole(timelock.EXECUTOR_ROLE(), address(governor));
        timelock.revokeRole(timelock.PROPOSER_ROLE(), deployer);
        timelock.revokeRole(timelock.EXECUTOR_ROLE(), deployer);

        staking.setGovernance(address(timelock), true);
        staking.setGovernance(deployer, false);

        token.setStakingContract(address(staking));
        token.grantRole(token.GOVERNANCE_ROLE(), address(timelock));
        token.revokeRole(token.GOVERNANCE_ROLE(), deployer);

        // ---- 10. Final renounce: the deployer loses the last bootstrap role ----
        // From here the timelock administers only itself (role rotations go
        // through governance proposals).
        timelock.renounceRole(timelock.ADMIN_ROLE(), deployer);

        vm.stopBroadcast();

        _assertDecentralized(token, staking, timelock, governor, migration, deployer, guardian);
        _logDeployment(token, impl, staking, timelock, governor, migration, oldDaimonAddr);
    }

    /// On-chain assert: no EOA still holds administrative roles.
    /// (The guardian keeps ONLY pause/cancel, by design; in production it must
    /// be a multisig.)
    function _assertDecentralized(
        DaimonV2 token,
        DaimonStaking staking,
        DaimonTimelock timelock,
        DaimonGovernor governor,
        DaimonMigration migration,
        address deployer,
        address guardian
    ) internal view {
        // Token: governed only by the timelock, no DEFAULT_ADMIN assigned.
        require(token.hasRole(token.GOVERNANCE_ROLE(), address(timelock)), "assert: timelock does not govern the token");
        require(!token.hasRole(token.GOVERNANCE_ROLE(), deployer), "assert: deployer still governs the token");
        require(!token.hasRole(token.DEFAULT_ADMIN_ROLE(), deployer), "assert: deployer is token admin");
        require(token.hasRole(token.GUARDIAN_ROLE(), guardian), "assert: guardian has no pause role");

        // Timelock: self-administers, the deployer has no role.
        require(timelock.hasRole(timelock.ADMIN_ROLE(), address(timelock)), "assert: timelock does not self-administer");
        require(!timelock.hasRole(timelock.ADMIN_ROLE(), deployer), "assert: deployer is timelock admin");
        require(!timelock.hasRole(timelock.PROPOSER_ROLE(), deployer), "assert: deployer is proposer");
        require(!timelock.hasRole(timelock.EXECUTOR_ROLE(), deployer), "assert: deployer is executor");
        require(timelock.hasRole(timelock.PROPOSER_ROLE(), address(governor)), "assert: governor is not proposer");
        require(timelock.hasRole(timelock.EXECUTOR_ROLE(), address(governor)), "assert: governor is not executor");

        // Staking: governed only by the timelock.
        require(staking.isGovernance(address(timelock)), "assert: timelock does not govern staking");
        require(!staking.isGovernance(deployer), "assert: deployer still governs staking");

        // Supply: entirely in the migration, never passed through an EOA.
        require(token.balanceOf(address(migration)) == token.INITIAL_SUPPLY(), "assert: supply not in migration");
        require(token.totalSupply() == token.INITIAL_SUPPLY(), "assert: unexpected total supply");
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
        console2.log("=== Daimon DAO - deploy complete ===");
        console2.log("DaimonV2 (proxy):        ", address(token));
        console2.log("DaimonV2 (implementation):", address(impl));
        console2.log("PancakeSwap V2 pair:     ", token.uniswapV2Pair());
        console2.log("DaimonStaking:           ", address(staking));
        console2.log("DaimonTimelock:          ", address(timelock));
        console2.log("DaimonGovernor:          ", address(governor));
        console2.log("DaimonMigration:         ", address(migration));
        console2.log("Old Daimon:              ", oldDaimonAddr);
        console2.log("All decentralization asserts passed.");
    }
}
