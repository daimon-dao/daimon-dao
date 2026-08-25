// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {DaimonV2} from "../../src/DaimonV2.sol";
import {DaimonStaking} from "../../src/DaimonStaking.sol";
import {DaimonGovernor} from "../../src/DaimonGovernor.sol";
import {DaimonTimelock} from "../../src/DaimonTimelock.sol";
import {DaimonMigration} from "../../src/DaimonMigration.sol";
import {MockOldDaimon} from "../../src/mocks/MockOldDaimon.sol";
import {MockUniswapV2Factory, MockUniswapV2Router02, MockWETH} from "../../src/mocks/MockUniswap.sol";

/*
 * Shared deploy base used by the fuzz and invariant tests.
 * Replicates the full wiring of the deploy script (governance to the Timelock,
 * supply in the migration, deployer with no roles) in a self-contained way for
 * the tests, without depending on the existing suite.
 */
abstract contract StackDeployer is Test {
    DaimonV2 internal token;
    DaimonStaking internal staking;
    DaimonGovernor internal governor;
    DaimonTimelock internal timelock;
    DaimonMigration internal migration;
    MockOldDaimon internal oldToken;
    MockUniswapV2Router02 internal router;
    MockWETH internal weth;

    address internal deployer = address(0xD1);
    address internal guardian = address(0x6A);
    address internal marketingWallet = address(0x3A);
    address internal treasury = address(0x74);

    uint256 internal constant OLD_SUPPLY = 1_000_000_000_000 ether; // >= INITIAL_SUPPLY, to fund the actors

    function deployStack() internal {
        vm.startPrank(deployer);

        weth = new MockWETH();
        MockUniswapV2Factory factory = new MockUniswapV2Factory();
        router = new MockUniswapV2Router02(address(factory), address(weth));
        vm.deal(address(router), 100_000 ether);

        oldToken = new MockOldDaimon(OLD_SUPPLY, deployer);
        // The deployer is the source of the old tokens in the tests:
        // excluding it from the old contract's fee makes the distributions to
        // the actors 1:1 (without it, they would suffer the 5% tax and receive
        // less than what they then try to migrate).
        oldToken.excludeFromFee(deployer);

        DaimonV2 impl = new DaimonV2();

        // Predict the migration address exactly as script/Deploy.s.sol does,
        // and pass the REAL one to initialize(). This fixture used to pass the
        // deployer as a placeholder _migrationContract and move the supply
        // afterwards — a shortcut that does not match production wiring, where
        // no EOA ever touches the supply. Anything the token records about the
        // migration at initialize() (finding #32) would otherwise be recorded
        // against the placeholder here and never exercised.
        //
        // Remaining CREATEs by the deployer from this point: proxy(+0),
        // staking(+1), timelock(+2), governor(+3), migration(+4).
        address predictedMigration = vm.computeCreateAddress(deployer, vm.getNonce(deployer) + 4);

        bytes memory initData = abi.encodeCall(
            DaimonV2.initialize,
            ("Daimon", "DMN", predictedMigration, address(router), deployer, guardian, marketingWallet)
        );
        token = DaimonV2(payable(address(new ERC1967Proxy(address(impl), initData))));

        staking = new DaimonStaking(address(token), deployer);
        timelock = new DaimonTimelock(7 days, deployer, deployer, guardian, deployer, token.guardianExpiry());
        governor = new DaimonGovernor(address(staking), address(timelock), guardian, 1000, 1000 ether, token.guardianExpiry());

        timelock.grantRole(timelock.PROPOSER_ROLE(), address(governor));
        timelock.grantRole(timelock.EXECUTOR_ROLE(), address(governor));
        // Come nello script di deploy (#26): il Governor cancella
        // atomicamente nel Timelock; il guardian conserva il suo CANCELLER.
        timelock.grantRole(timelock.CANCELLER_ROLE(), address(governor));
        timelock.revokeRole(timelock.PROPOSER_ROLE(), deployer);
        timelock.revokeRole(timelock.EXECUTOR_ROLE(), deployer);

        staking.setGovernance(address(timelock), true);
        staking.setGovernance(deployer, false);

        token.setStakingContract(address(staking));

        // 365 days = MAX_MIGRATION_DURATION (#13): the longest window the
        // contract accepts, so the migration stays open as long as possible
        // during the fuzz/invariant runs (the handler catches post-deadline
        // claims).
        migration = new DaimonMigration(address(oldToken), address(token), treasury, address(timelock), 365 days);
        require(address(migration) == predictedMigration, "StackDeployer: predicted migration mismatch");
        // No setExcludedFromFee and no supply transfer here any more: the
        // migration received the whole INITIAL_SUPPLY and its fee exemption
        // directly in initialize(), exactly as on mainnet (#32).

        token.grantRole(token.GOVERNANCE_ROLE(), address(timelock));
        token.revokeRole(token.GOVERNANCE_ROLE(), deployer);
        timelock.renounceRole(timelock.ADMIN_ROLE(), deployer);

        // The treasury zeroes the old token's fee towards itself (preparatory
        // migration step).
        vm.stopPrank();
        vm.prank(treasury);
        oldToken.excludeFromFee(treasury);
    }

    /// Endows `to` with `amount` of new DMN through the migration channel:
    /// sends it old tokens, then executes claim on its behalf.
    function fundWithDmn(address to, uint256 amount) internal {
        if (amount == 0) return;
        vm.prank(deployer);
        oldToken.transfer(to, amount);
        vm.startPrank(to);
        oldToken.approve(address(migration), amount);
        migration.claim(amount);
        vm.stopPrank();
    }
}
