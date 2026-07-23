// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {StackDeployer} from "../base/StackDeployer.sol";
import {DaimonHandler} from "./DaimonHandler.sol";

/*
 * Handler-based invariant testing: the fuzzer hammers the system with random
 * sequences of actions (transfer, stake, withdraw, migrate, notify, claim,
 * warp) and after EVERY sequence checks that the invariants hold.
 */
contract InvariantDaimon is StackDeployer {
    DaimonHandler internal handler;
    address[] internal actors;

    function setUp() public {
        deployStack();

        actors.push(address(0xA11CE));
        actors.push(address(0xB0B));
        actors.push(address(0xCA401));

        // Each actor starts with old tokens (to migrate) and some DMN.
        for (uint256 i = 0; i < actors.length; i++) {
            vm.prank(deployer);
            oldToken.transfer(actors[i], 50_000_000 ether);
            fundWithDmn(actors[i], 10_000_000 ether);
        }

        handler = new DaimonHandler(token, staking, migration, oldToken, treasury, actors);

        // Transfer the residual old tokens to the actors? No: they keep them.
        // The fuzzing target is only the handler.
        targetContract(address(handler));
    }

    // --- Supply within the immutable bounds ---
    function invariant_SupplyWithinBounds() public view {
        uint256 s = token.totalSupply();
        assertLe(s, token.INITIAL_SUPPLY(), "supply above INITIAL_SUPPLY (mint!)");
        assertGe(s, token.MIN_SUPPLY(), "supply below the MIN_SUPPLY floor");
    }

    // --- totalVotingPower == sum of the vp of the active locks ---
    function invariant_VotingPowerMatchesActiveLocks() public view {
        uint256 n = staking.nextLockId();
        uint256 sum;
        for (uint256 i = 0; i < n; i++) {
            (,,,,, uint256 vpGranted, bool withdrawn) = staking.locks(i);
            if (!withdrawn) sum += vpGranted;
        }
        assertEq(staking.totalVotingPower(), sum, "totalVotingPower != sum of active locks");
    }

    // --- Sum of per-user vp == totalVotingPower ---
    function invariant_PerUserVotingPowerSums() public view {
        uint256 sum;
        for (uint256 i = 0; i < actors.length; i++) {
            sum += staking.votingPower(actors[i]);
        }
        assertEq(sum, staking.totalVotingPower(), "sum of user vp != totalVotingPower");
    }

    // --- Migration: DMN distributed == old tokens received ---
    function invariant_MigrationConservation() public view {
        // Every migrated old token lands in the treasury 1:1 (the old token
        // has no reflection and the treasury starts from zero): the treasury's
        // old-token balance equals totalMigrated exactly, which in turn is the
        // sum of the DMN distributed (claim sends exactly `amount` and
        // increments totalMigrated by the same).
        assertEq(
            oldToken.balanceOf(treasury),
            migration.totalMigrated(),
            "old tokens in treasury != totalMigrated"
        );
        // The migration NEVER distributes more DMN than owed: it starts from
        // INITIAL_SUPPLY and can only gain reflection (never lose beyond the
        // claims), so the residual balance does not drop below the expected
        // amount.
        assertGe(
            token.balanceOf(address(migration)),
            token.INITIAL_SUPPLY() - migration.totalMigrated(),
            "the migration distributed more DMN than owed"
        );
    }

    // --- Reward: the contract retains exactly funded - claimed ---
    function invariant_StakingHoldsExactRewardBalance() public view {
        assertEq(
            address(staking).balance,
            handler.ghostBnbFunded() - handler.ghostBnbClaimed(),
            "staking BNB balance != funded - claimed"
        );
    }

    // --- No administrative role in unauthorized hands ---
    function invariant_NoUnauthorizedAdminRoles() public view {
        // Only the Timelock governs the token and staking; no actor/deployer.
        assertTrue(token.hasRole(token.GOVERNANCE_ROLE(), address(timelock)), "timelock loses governance");
        assertFalse(token.hasRole(token.GOVERNANCE_ROLE(), deployer), "deployer has governance");
        assertTrue(staking.isGovernance(address(timelock)), "timelock loses staking governance");
        assertFalse(staking.isGovernance(deployer), "deployer governs staking");
        assertFalse(timelock.hasRole(timelock.ADMIN_ROLE(), deployer), "deployer is timelock admin");
        assertFalse(timelock.hasRole(timelock.PROPOSER_ROLE(), deployer), "deployer is proposer");
        for (uint256 i = 0; i < actors.length; i++) {
            assertFalse(token.hasRole(token.GOVERNANCE_ROLE(), actors[i]), "actor has governance");
            assertFalse(timelock.hasRole(timelock.ADMIN_ROLE(), actors[i]), "actor is timelock admin");
            assertFalse(staking.isGovernance(actors[i]), "actor governs staking");
        }
    }
}
