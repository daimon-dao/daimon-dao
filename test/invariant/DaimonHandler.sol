// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {DaimonV2} from "../../src/DaimonV2.sol";
import {DaimonStaking} from "../../src/DaimonStaking.sol";
import {DaimonMigration} from "../../src/DaimonMigration.sol";
import {MockOldDaimon} from "../../src/mocks/MockOldDaimon.sol";

/*
 * Handler per l'invariant testing: espone azioni "utente" che il fuzzer
 * invoca in sequenze casuali. Le azioni che il contratto rifiuterebbe per
 * stato (lock attivo, maxTx, saldo) sono racchiuse in try/catch: un revert
 * atteso non deve interrompere la sequenza, ma nessuna azione deve poter
 * violare gli invarianti verificati in InvariantDaimon.
 *
 * Ghost variables: BNB totali versati allo staking e totali riscossi, per
 * l'invariante "il contratto trattiene sempre esattamente la differenza".
 */
contract DaimonHandler is Test {
    DaimonV2 public token;
    DaimonStaking public staking;
    DaimonMigration public migration;
    MockOldDaimon public oldToken;

    address[] public actors;
    address internal treasury;

    uint256 public ghostBnbFunded;
    uint256 public ghostBnbClaimed;

    constructor(
        DaimonV2 _token,
        DaimonStaking _staking,
        DaimonMigration _migration,
        MockOldDaimon _oldToken,
        address _treasury,
        address[] memory _actors
    ) {
        token = _token;
        staking = _staking;
        migration = _migration;
        oldToken = _oldToken;
        treasury = _treasury;
        actors = _actors;
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    // --- Trasferimento tra attori (fee applicata) ---
    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 bal = token.balanceOf(from);
        if (bal == 0) return;
        amount = bound(amount, 1, _min(bal, token.maxTxAmount()));
        vm.prank(from);
        try token.transfer(to, amount) {} catch {}
    }

    // --- Stake ---
    function stake(uint256 actorSeed, uint256 amount, uint256 optSeed) external {
        address a = _actor(actorSeed);
        uint256 bal = token.balanceOf(a);
        if (bal < 1 ether) return;
        uint256 nOpt = staking.lockOptionsLength();
        uint256 idx = optSeed % nOpt;
        amount = bound(amount, 1 ether, bal);
        vm.startPrank(a);
        token.approve(address(staking), amount);
        try staking.stake(amount, idx) {} catch {}
        vm.stopPrank();
    }

    // --- Withdraw (solo lock scaduti; altrimenti revert catturato) ---
    function withdraw(uint256 lockSeed) external {
        uint256 n = staking.nextLockId();
        if (n == 0) return;
        uint256 lockId = lockSeed % n;
        (address owner,,,,,, bool withdrawn) = staking.locks(lockId);
        if (owner == address(0) || withdrawn) return;
        vm.prank(owner);
        try staking.withdraw(lockId) {} catch {}
    }

    // --- Migrazione ---
    function migrate(uint256 actorSeed, uint256 amount) external {
        address a = _actor(actorSeed);
        uint256 oldBal = oldToken.balanceOf(a);
        if (oldBal == 0) return;
        amount = bound(amount, 1, oldBal);
        vm.startPrank(a);
        oldToken.approve(address(migration), amount);
        try migration.claim(amount) {} catch {}
        vm.stopPrank();
    }

    // --- Finanziamento reward pool ---
    function notifyReward(uint256 amount) external {
        amount = bound(amount, 1, 100 ether);
        vm.deal(address(this), amount);
        try staking.notifyRewardAmount{value: amount}(amount) {
            ghostBnbFunded += amount;
        } catch {}
    }

    // --- Riscossione reward ---
    function claimReward(uint256 actorSeed) external {
        address a = _actor(actorSeed);
        uint256 before = a.balance;
        vm.prank(a);
        try staking.claimReward() {
            ghostBnbClaimed += a.balance - before;
        } catch {}
    }

    // --- Avanzamento del tempo (per sbloccare i lock) ---
    function warp(uint256 secs) external {
        secs = bound(secs, 1 hours, 400 days);
        vm.warp(block.timestamp + secs);
    }

    function actorsLength() external view returns (uint256) {
        return actors.length;
    }

    function _min(uint256 a, uint256 b) private pure returns (uint256) {
        return a < b ? a : b;
    }
}
