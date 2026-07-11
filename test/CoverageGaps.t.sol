// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {StackDeployer} from "./base/StackDeployer.sol";
import {DaimonV2} from "../src/DaimonV2.sol";
import {DaimonStaking} from "../src/DaimonStaking.sol";
import {DaimonGovernor} from "../src/DaimonGovernor.sol";
import {DaimonTimelock} from "../src/DaimonTimelock.sol";

/*
 * Test dei percorsi critici non coperti dalla suite principale, individuati
 * dalla rassegna di copertura: upgrade UUPS, allowance/transferFrom, i setter
 * amministrativi di Governor/Timelock e la gestione delle lock option.
 */
contract CoverageGaps is StackDeployer {
    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);

    function setUp() public {
        deployStack();
    }

    // ============================================================
    // UUPS upgrade — il percorso piu' sensibile (upgradeabilita')
    // ============================================================
    function test_UpgradeOnlyByGovernance() public {
        DaimonV2 newImpl = new DaimonV2();

        // Un indirizzo qualsiasi non puo' aggiornare.
        vm.prank(alice);
        vm.expectRevert();
        token.upgradeToAndCall(address(newImpl), "");

        // Nemmeno il guardian (ha solo la pausa).
        vm.prank(guardian);
        vm.expectRevert();
        token.upgradeToAndCall(address(newImpl), "");
    }

    function test_UpgradeViaGovernancePreservesState() public {
        // Stato pre-upgrade
        uint256 supplyBefore = token.totalSupply();
        uint256 migBal = token.balanceOf(address(migration));

        DaimonV2 newImpl = new DaimonV2();

        // Solo la governance (Timelock) puo' autorizzare l'upgrade.
        vm.prank(address(timelock));
        token.upgradeToAndCall(address(newImpl), "");

        // Stato preservato: supply, saldi e ruoli invariati.
        assertEq(token.totalSupply(), supplyBefore, "supply cambiata dall'upgrade");
        assertEq(token.balanceOf(address(migration)), migBal, "saldo cambiato dall'upgrade");
        assertTrue(token.hasRole(token.GOVERNANCE_ROLE(), address(timelock)), "governance persa");
    }

    function test_UpgradeRejectsZeroImplementation() public {
        vm.prank(address(timelock));
        vm.expectRevert();
        token.upgradeToAndCall(address(0), "");
    }

    // ============================================================
    // ERC20 allowance / transferFrom
    // ============================================================
    function test_TransferFromConsumesAllowance() public {
        fundWithDmn(alice, 1_000_000 ether);

        vm.prank(alice);
        token.approve(bob, 100_000 ether);
        assertEq(token.allowance(alice, bob), 100_000 ether);

        vm.prank(bob);
        token.transferFrom(alice, bob, 40_000 ether);

        // L'allowance finita scende dell'importo speso.
        assertEq(token.allowance(alice, bob), 60_000 ether, "allowance non decrementata");
    }

    function test_InfiniteAllowanceNotDecremented() public {
        fundWithDmn(alice, 1_000_000 ether);

        vm.prank(alice);
        token.approve(bob, type(uint256).max);

        vm.prank(bob);
        token.transferFrom(alice, bob, 50_000 ether);

        assertEq(token.allowance(alice, bob), type(uint256).max, "allowance infinita decrementata");
    }

    function test_IncreaseAndDecreaseAllowance() public {
        vm.startPrank(alice);
        token.approve(bob, 100 ether);
        token.increaseAllowance(bob, 50 ether);
        assertEq(token.allowance(alice, bob), 150 ether);
        token.decreaseAllowance(bob, 120 ether);
        assertEq(token.allowance(alice, bob), 30 ether);
        vm.expectRevert("DaimonV2: allowance below zero");
        token.decreaseAllowance(bob, 100 ether);
        vm.stopPrank();
    }

    // ============================================================
    // Governor: setter solo-timelock e cancel del guardian
    // ============================================================
    function test_GovernorSettersOnlyTimelock() public {
        vm.prank(alice);
        vm.expectRevert("DaimonGovernor: only via timelock");
        governor.setQuorumBps(2000);

        vm.prank(address(timelock));
        governor.setQuorumBps(2000);
        assertEq(governor.quorumBps(), 2000);

        vm.prank(address(timelock));
        governor.setProposalThreshold(5000 ether);
        assertEq(governor.proposalThreshold(), 5000 ether);

        vm.prank(address(timelock));
        governor.setGuardian(bob);
        assertEq(governor.guardian(), bob);
    }

    function test_GovernorQuorumFloorEnforced() public {
        vm.prank(address(timelock));
        vm.expectRevert("DaimonGovernor: below MIN_QUORUM_BPS");
        governor.setQuorumBps(999); // sotto il 10% minimo
    }

    function test_GuardianCanCancelProposal() public {
        fundWithDmn(alice, 3_000_000 ether);
        vm.startPrank(alice);
        token.approve(address(staking), 3_000_000 ether);
        staking.stake(3_000_000 ether, 3);
        vm.stopPrank();

        bytes memory data = abi.encodeWithSelector(DaimonV2.setFees.selector, uint256(10), uint256(10), uint256(20));
        vm.prank(alice);
        uint256 id = governor.propose(address(token), 0, data, "x");

        vm.prank(guardian);
        governor.cancel(id);
        assertEq(uint8(governor.state(id)), uint8(DaimonGovernor.ProposalState.Canceled));

        // Un non-guardian non puo' cancellare.
        vm.prank(alice);
        vm.expectRevert(DaimonGovernor.NotGuardian.selector);
        governor.cancel(id);
    }

    // ============================================================
    // Timelock: cancel del canceller (guardian)
    // ============================================================
    function test_TimelockCancellerCanCancel() public {
        // Schedula un'operazione tramite un finto proposer per testare cancel.
        // Il PROPOSER e' il governor; qui usiamo un id calcolato e verifichiamo
        // che solo il CANCELLER (guardian) possa annullare.
        bytes32 fakeId = keccak256("op");
        vm.prank(alice);
        vm.expectRevert();
        timelock.cancel(fakeId); // alice non ha CANCELLER_ROLE

        vm.prank(guardian);
        timelock.cancel(fakeId); // guardian = canceller: non reverte
    }

    // ============================================================
    // Staking: gestione lock option (governance)
    // ============================================================
    function test_AddAndDisableLockOption() public {
        uint256 nBefore = staking.lockOptionsLength();

        vm.prank(address(timelock));
        staking.addLockOption(730 days, 8000); // 2 anni, 8x
        assertEq(staking.lockOptionsLength(), nBefore + 1);

        (uint256 dur, uint256 mult, bool active) = staking.lockOptions(nBefore);
        assertEq(dur, 730 days);
        assertEq(mult, 8000);
        assertTrue(active);

        vm.prank(address(timelock));
        staking.disableLockOption(nBefore);
        (,, bool activeAfter) = staking.lockOptions(nBefore);
        assertFalse(activeAfter);

        // Un non-governance non puo' aggiungere opzioni.
        vm.prank(alice);
        vm.expectRevert(DaimonStaking.NotGovernance.selector);
        staking.addLockOption(1 days, 1000);
    }

    // ============================================================
    // Token: setter parametrici con bound
    // ============================================================
    function test_ParametricSettersBounds() public {
        vm.startPrank(address(timelock));

        staking; // silence
        token.setStakingRewardShareBps(1000);
        assertEq(token.stakingRewardShareBps(), 1000);
        vm.expectRevert("DaimonV2: bps > 100%");
        token.setStakingRewardShareBps(1001);

        vm.expectRevert("DaimonV2: maxTx too low");
        token.setMaxTxAmount(1); // sotto lo 0.01% della supply

        token.setBuyBackUpperLimit(10 ether);
        assertEq(token.buyBackUpperLimit(), 10 ether);

        vm.stopPrank();
    }

    // ============================================================
    // Migration: sweep post-deadline verso la treasury
    // ============================================================
    function test_SweepSendsRemainderToTreasury() public {
        vm.warp(block.timestamp + 3651 days); // oltre la deadline (3650 giorni)
        uint256 remaining = token.balanceOf(address(migration));
        uint256 treasuryBefore = token.balanceOf(treasury);

        vm.prank(address(timelock));
        migration.sweepUnclaimed();

        assertEq(token.balanceOf(address(migration)), 0, "migration non svuotata");
        assertEq(token.balanceOf(treasury), treasuryBefore + remaining, "treasury non ha ricevuto il residuo");
    }
}
