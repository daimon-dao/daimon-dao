// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {StackDeployer} from "../base/StackDeployer.sol";
import {DaimonV2} from "../../src/DaimonV2.sol";
import {DaimonStaking} from "../../src/DaimonStaking.sol";
import {DaimonGovernor} from "../../src/DaimonGovernor.sol";

/*
 * Fuzz test (parametri campionati da Foundry) sulle funzioni critiche.
 * Ogni test verifica un invariante locale a valle di un'azione fuzzata.
 */
contract FuzzDaimon is StackDeployer {
    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);

    function setUp() public {
        deployStack();
    }

    // --- Transfer / reflection ---
    // Nessun mint (totalSupply costante) e la somma dei saldi dei holder
    // noti non supera mai la supply (le reflection ridistribuiscono, non
    // creano; il rounding intero puo' solo far perdere polvere).
    function testFuzz_TransferNeverMintsAndConservesSupply(uint256 fund, uint256 amount) public {
        fund = bound(fund, 1 ether, 10_000_000 ether);
        fundWithDmn(alice, fund);

        uint256 supply = token.totalSupply();
        uint256 aBal = token.balanceOf(alice);
        amount = bound(amount, 1, _min(aBal, token.maxTxAmount()));

        vm.prank(alice);
        token.transfer(bob, amount);

        // Nessun mint.
        assertEq(token.totalSupply(), supply, "supply cambiata da un transfer");
        // Somma dei holder noti <= supply.
        uint256 sum = token.balanceOf(alice) + token.balanceOf(bob) + token.balanceOf(address(token))
            + token.balanceOf(address(migration)) + token.balanceOf(token.deadAddress());
        assertLe(sum, supply, "somma saldi > supply (accounting rotto)");
        // Bob riceve un netto positivo e mai piu' del lordo inviato.
        assertGt(token.balanceOf(bob), 0, "bob non ha ricevuto nulla");
        assertLe(token.balanceOf(bob), amount, "bob ha ricevuto piu' del lordo");
    }

    // --- Staking: voting power pesato coerente ---
    function testFuzz_StakeGrantsExactWeightedPower(uint256 amount, uint256 optRaw) public {
        uint256 nOpt = staking.lockOptionsLength();
        uint256 idx = bound(optRaw, 0, nOpt - 1);
        (, uint256 mult,) = staking.lockOptions(idx);

        fundWithDmn(alice, 20_000_000 ether);
        amount = bound(amount, 1 ether, token.balanceOf(alice));

        uint256 vpBefore = staking.totalVotingPower();

        vm.startPrank(alice);
        token.approve(address(staking), amount);
        uint256 lockId = staking.stake(amount, idx);
        vm.stopPrank();

        uint256 expectedVp = (amount * mult) / 1000;
        assertEq(staking.votingPower(alice), expectedVp, "vp utente errato");
        assertEq(staking.totalVotingPower(), vpBefore + expectedVp, "totalVotingPower incoerente");

        (, uint256 lockedAmount,,,, uint256 vpGranted,) = staking.locks(lockId);
        assertEq(lockedAmount, amount, "amount del lock errato");
        assertEq(vpGranted, expectedVp, "vpGranted memorizzato errato");
    }

    // --- Staking: withdraw a scadenza restituisce esattamente il capitale ---
    function testFuzz_WithdrawReturnsPrincipal(uint256 amount, uint256 optRaw) public {
        uint256 nOpt = staking.lockOptionsLength();
        uint256 idx = bound(optRaw, 0, nOpt - 1);
        (uint256 duration,,) = staking.lockOptions(idx);

        fundWithDmn(alice, 20_000_000 ether);
        amount = bound(amount, 1 ether, token.balanceOf(alice));

        vm.startPrank(alice);
        token.approve(address(staking), amount);
        uint256 lockId = staking.stake(amount, idx);
        vm.stopPrank();

        uint256 balBefore = token.balanceOf(alice);
        vm.warp(block.timestamp + duration + 1);
        vm.prank(alice);
        staking.withdraw(lockId);

        // Staking escluso dalle fee: restituzione netta esatta.
        assertEq(token.balanceOf(alice), balBefore + amount, "capitale non restituito 1:1");
        assertEq(staking.votingPower(alice), 0, "vp non azzerato dopo withdraw");
        assertEq(staking.totalVotingPower(), 0, "totalVotingPower non azzerato");
    }

    // --- Migrazione 1:1 esatta ---
    function testFuzz_MigrationIsOneToOne(uint256 amount) public {
        amount = bound(amount, 1, 500_000_000 ether);
        vm.prank(deployer);
        oldToken.transfer(alice, amount);

        uint256 treasuryBefore = oldToken.balanceOf(treasury);
        uint256 migBefore = token.balanceOf(address(migration));
        uint256 migratedBefore = migration.totalMigrated();

        vm.startPrank(alice);
        oldToken.approve(address(migration), amount);
        migration.claim(amount);
        vm.stopPrank();

        assertEq(token.balanceOf(alice), amount, "DMN ricevuti != vecchi token");
        assertEq(oldToken.balanceOf(treasury), treasuryBefore + amount, "treasury non ha ricevuto i vecchi token");
        assertEq(migration.totalMigrated(), migratedBefore + amount, "totalMigrated incoerente");
        assertEq(token.balanceOf(address(migration)), migBefore - amount, "DMN distribuiti != migrati");
    }

    // --- Reward: mai piu' BNB di quanti ricevuti ---
    function testFuzz_RewardsNeverExceedFunded(uint256 stakeAmt, uint256 reward) public {
        fundWithDmn(alice, 20_000_000 ether);
        stakeAmt = bound(stakeAmt, 1 ether, token.balanceOf(alice));
        reward = bound(reward, 1, 1000 ether);

        vm.startPrank(alice);
        token.approve(address(staking), stakeAmt);
        staking.stake(stakeAmt, 0);
        vm.stopPrank();

        vm.deal(address(this), reward);
        staking.notifyRewardAmount{value: reward}(reward);

        // Un unico staker: il pending non puo' superare i BNB versati.
        assertLe(staking.pendingReward(alice), reward, "reward pending > fondi versati");
    }

    // --- Governance: setFees non supera mai il cap del 10% ---
    function testFuzz_SetFeesRespectsCap(uint256 tax, uint256 buy, uint256 mkt) public {
        tax = bound(tax, 0, 200);
        buy = bound(buy, 0, 200);
        mkt = bound(mkt, 0, 200);

        vm.prank(address(timelock));
        if (tax + buy + mkt > 100) {
            vm.expectRevert(DaimonV2.FeeTooHigh.selector);
            token.setFees(tax, buy, mkt);
        } else {
            token.setFees(tax, buy, mkt);
            assertLe(token.taxFee() + token.buybackFee() + token.marketingFee(), 100, "fee totale > cap");
        }
    }

    function _min(uint256 a, uint256 b) private pure returns (uint256) {
        return a < b ? a : b;
    }
}
