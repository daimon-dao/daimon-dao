// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/*
 * Main Foundry (forge-std) test suite.
 *
 * HOW TO RUN:
 *   forge test -vvv
 *
 * Covers the full stack: token parameters and supply floor, 1:1 migration,
 * vote-escrow staking, the complete governance cycle (propose â†’ vote â†’ queue
 * â†’ execute), the burn floor, the guardian expiry, and the fixes from the
 * security review (snapshot voting power, timelock role hand-off, fee-swap
 * slippage protection, reward queueing, etc.).
 */

import "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../src/DaimonV2.sol";
import "../src/DaimonStaking.sol";
import "../src/DaimonGovernor.sol";
import "../src/DaimonTimelock.sol";
import "../src/DaimonMigration.sol";
import "../src/mocks/MockUniswap.sol";
// Mock of the old Daimon contract: shared with the testnet deploy script
// (script/Deploy.s.sol), lives in src/mocks.
import {MockOldDaimon} from "../src/mocks/MockOldDaimon.sol";

contract DaimonDAOTest is Test {
    DaimonV2 public tokenImpl;
    DaimonV2 public token; // proxy cast as DaimonV2
    DaimonStaking public staking;
    DaimonGovernor public governor;
    DaimonTimelock public timelock;
    DaimonMigration public migration;
    MockOldDaimon public oldToken;

    MockUniswapV2Factory public factory;
    MockUniswapV2Router02 public router;
    MockWETH public weth;

    address public deployer = address(0x1);
    address public guardian = address(0x2);
    address public marketingWallet = address(0x3);
    address public treasury = address(0x4);
    address public alice = address(0x10);
    address public bob = address(0x11);

    uint256 public constant OLD_SUPPLY = 1_000_000_000 * 1e18;

    // NOTE: given the multi-contract deploy with circular dependencies
    // (token/staking/governor/timelock/migration reference each other), the
    // full setup lives in _deployFullStack(), called explicitly on the first
    // line of every test (a more readable pattern than an opaque setUp() when
    // the contracts are this interdependent).

    function _deployFullStack() internal {
        vm.startPrank(deployer);

        weth = new MockWETH();
        factory = new MockUniswapV2Factory();
        router = new MockUniswapV2Router02(address(factory), address(weth));
        vm.deal(address(router), 1000 ether); // ETH liquidity for the mock swaps

        oldToken = new MockOldDaimon(OLD_SUPPLY, alice); // alice starts with the entire old supply

        // 1. Deploy the token implementation + proxy. We use the deployer as a
        // temporary "migrationContract" to receive the initial supply: it is a
        // simple pass-through EOA that immediately afterwards transfers
        // everything to the real DaimonMigration once deployed (at line ~170).
        tokenImpl = new DaimonV2();

        bytes memory initData = abi.encodeWithSelector(
            DaimonV2.initialize.selector,
            "Daimon",
            "DMN",
            deployer,           // temporary migrationContract = the deployer itself
            address(router),
            deployer,           // temporary governance
            guardian,
            marketingWallet
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(tokenImpl), initData);
        token = DaimonV2(payable(address(proxy)));

        // 2. Deploy staking (uses the deployer as temporary governance)
        staking = new DaimonStaking(address(token), deployer);

        // 3. Deploy timelock: proposer/executor/canceller settati dopo aver
        // il governor (bootstrap), per ora deployer ha tutti i ruoli admin
        timelock = new DaimonTimelock(7 days, deployer, deployer, guardian, deployer, token.guardianExpiry());

        // 4. Deploy governor (quorum 10% = 1000 bps su 10000)
        governor = new DaimonGovernor(address(staking), address(timelock), guardian, 1000, 1000 * 1e18, token.guardianExpiry());

        // 5. Wiring dei ruoli del Timelock: il Governor deve essere sia
        // PROPOSER (per queue) sia EXECUTOR (execute() del Governor chiama
        // timelock.execute() con msg.sender = governor), oltre che CANCELLER
        // per la cancellazione atomica (#26).
        timelock.grantRole(timelock.PROPOSER_ROLE(), address(governor));
        timelock.grantRole(timelock.EXECUTOR_ROLE(), address(governor));
        timelock.grantRole(timelock.CANCELLER_ROLE(), address(governor));
        timelock.revokeRole(timelock.PROPOSER_ROLE(), deployer);

        staking.setGovernance(address(timelock), true);
        staking.setGovernance(deployer, false);

        token.setStakingContract(address(staking)); // called while the deployer still has GOVERNANCE_ROLE

        // 6. Deploy the migration and transfer the entire initial supply, which
        // the token had credited to "deployer" as the temporary migrationContract
        // during initialize(). This must happen BEFORE handing GOVERNANCE_ROLE
        // to the timelock: the real DaimonMigration must be fee-excluded (in
        // production it is automatically, because it is the _migrationContract
        // passed to initialize(); here the role was held temporarily by the
        // deployer).
        migration = new DaimonMigration(address(oldToken), address(token), treasury, address(timelock), 30 days);
        token.setExcludedFromFee(address(migration), true);

        uint256 deployerBal = token.balanceOf(deployer);
        token.transfer(address(migration), deployerBal);

        // 7. Final hand-off of the token governance to the Timelock.
        token.grantRole(token.GOVERNANCE_ROLE(), address(timelock));
        token.revokeRole(token.GOVERNANCE_ROLE(), deployer);

        // 8. The deployer renounces the Timelock's bootstrap ADMIN_ROLE: from
        // here on the timelock administers only itself (role rotations go
        // through governance proposals).
        timelock.renounceRole(timelock.ADMIN_ROLE(), deployer);

        vm.stopPrank();
    }

    // ============================================================
    // Test 1: deploy and base token parameters
    // ============================================================
    function test_TokenInitialSupplyAndFloor() public {
        _deployFullStack();
        assertEq(token.totalSupply(), tokenImpl.INITIAL_SUPPLY());
        assertEq(token.MIN_SUPPLY(), 21_000_000_000 * 1e18);
        assertTrue(token.totalSupply() > token.MIN_SUPPLY());
    }

    function test_TokenHasNoMintFunction() public {
        // Direct check: the selector of any potential mint(address,uint256)
        // function does not exist in the contract. A raw call to that selector
        // must fail (no matching function, no fallback that mints).
        _deployFullStack();
        uint256 supplyBefore = token.totalSupply();

        (bool success, ) = address(token).call(
            abi.encodeWithSignature("mint(address,uint256)", alice, 1_000_000 * 1e18)
        );
        assertFalse(success);
        assertEq(token.totalSupply(), supplyBefore);

        // Also check after a real transfer: the supply never rises.
        _giveAliceSomeNewTokens(1000 * 1e18);

        assertEq(token.totalSupply(), supplyBefore);
    }

    // ============================================================
    // Test 2: 1:1 migration
    // ============================================================
    function test_MigrationOneToOne() public {
        _deployFullStack();

        vm.prank(alice);
        oldToken.excludeFromFee(address(treasury)); // simulates the preparatory step in the mock

        uint256 aliceOldBalance = oldToken.balanceOf(alice);
        assertGt(aliceOldBalance, 0);

        vm.startPrank(alice);
        oldToken.approve(address(migration), aliceOldBalance);
        migration.claim(aliceOldBalance);
        vm.stopPrank();

        assertEq(token.balanceOf(alice), aliceOldBalance);
        assertEq(oldToken.balanceOf(treasury), aliceOldBalance);
        assertEq(migration.totalMigrated(), aliceOldBalance);
    }

    function test_MigrationRevertsOnFeeMismatch() public {
        _deployFullStack();
        // We do NOT call excludeFromFee(treasury): the mock will apply the 5%
        // fee, causing a mismatch that must make claim() revert.
        uint256 aliceOldBalance = oldToken.balanceOf(alice);

        vm.startPrank(alice);
        oldToken.approve(address(migration), aliceOldBalance);
        vm.expectRevert(DaimonMigration.AmountMismatch.selector);
        migration.claim(aliceOldBalance);
        vm.stopPrank();
    }

    function test_MigrationSweepOnlyAfterDeadlineAndOnlyGovernance() public {
        _deployFullStack();

        vm.expectRevert(DaimonMigration.MigrationStillOpen.selector);
        vm.prank(address(timelock));
        migration.sweepUnclaimed();

        vm.warp(block.timestamp + 31 days);

        vm.expectRevert(DaimonMigration.OnlyGovernance.selector);
        vm.prank(alice);
        migration.sweepUnclaimed();

        vm.prank(address(timelock));
        migration.sweepUnclaimed();
    }

    // ============================================================
    // Test 3: staking and vote-escrow voting power
    // ============================================================
    function test_StakingGrantsWeightedVotingPower() public {
        _deployFullStack();
        _giveAliceSomeNewTokens(1000 * 1e18);

        vm.startPrank(alice);
        token.approve(address(staking), 1000 * 1e18);
        staking.stake(1000 * 1e18, 0); // lockOption 0 = 30d, 1.0x
        vm.stopPrank();

        assertEq(staking.votingPower(alice), 1000 * 1e18); // 1.0x

        _giveAliceSomeNewTokens(500 * 1e18);
        vm.startPrank(alice);
        token.approve(address(staking), 500 * 1e18);
        staking.stake(500 * 1e18, 3); // lockOption 3 = 365d, 4.0x
        vm.stopPrank();

        assertEq(staking.votingPower(alice), 1000 * 1e18 + 2000 * 1e18); // 500*4 = 2000
    }

    function test_CannotWithdrawBeforeLockEnds() public {
        _deployFullStack();
        _giveAliceSomeNewTokens(1000 * 1e18);

        vm.startPrank(alice);
        token.approve(address(staking), 1000 * 1e18);
        uint256 lockId = staking.stake(1000 * 1e18, 1); // 90d

        vm.expectRevert(DaimonStaking.LockStillActive.selector);
        staking.withdraw(lockId);
        vm.stopPrank();

        vm.warp(block.timestamp + 91 days);
        vm.prank(alice);
        staking.withdraw(lockId);

        assertEq(staking.votingPower(alice), 0);
        assertEq(token.balanceOf(alice), 1000 * 1e18);
    }

    // ============================================================
    // Test 4: full governance cycle (propose -> vote -> queue -> execute)
    // ============================================================
    function test_FullGovernanceCycle_ChangeFees() public {
        _deployFullStack();

        _giveAliceSomeNewTokens(2_000_000 * 1e18);
        vm.startPrank(alice);
        token.approve(address(staking), 2_000_000 * 1e18);
        staking.stake(2_000_000 * 1e18, 3); // long lock, high voting power
        vm.stopPrank();

        bytes memory data = abi.encodeWithSelector(DaimonV2.setFees.selector, uint256(10), uint256(10), uint256(20));

        vm.roll(block.number + 1); // lo snapshot e' block - 1 (#12): lo stake deve stare in un blocco gia' sigillato
        vm.prank(alice);
        uint256 proposalId = governor.propose(address(token), 0, data, "Reduce fees");

        vm.warp(block.timestamp + governor.VOTING_DELAY() + 1);

        vm.prank(alice);
        governor.castVote(proposalId, 1); // for

        vm.warp(block.timestamp + governor.VOTING_PERIOD() + 1);

        assertEq(uint8(governor.state(proposalId)), uint8(DaimonGovernor.ProposalState.Succeeded));

        governor.queue(proposalId);

        vm.warp(block.timestamp + timelock.getMinDelay() + 1); // 7 days + 1 second

        governor.execute(proposalId);

        assertEq(token.taxFee(), 10);
        assertEq(token.buybackFee(), 10);
        assertEq(token.marketingFee(), 20);
    }

    function test_ProposalDefeatedIfQuorumNotMet() public {
        _deployFullStack();

        // Quorum is 10% of totalVotingPower: for it NOT to be reached we need a
        // lot of voting power sitting on the sidelines. Bob stakes en masse and
        // does not vote; alice stakes the minimum needed to propose
        // (proposalThreshold) and votes alone: her votes stay below 10% of the
        // total.
        _giveAliceSomeNewTokens(200_000 * 1e18);

        vm.prank(alice);
        token.transfer(bob, 100_000 * 1e18); // transfer with 5% fee: bob receives ~95k

        vm.startPrank(bob);
        token.approve(address(staking), 90_000 * 1e18);
        staking.stake(90_000 * 1e18, 0); // bob vp = 90_000e18, will not vote
        vm.stopPrank();

        vm.startPrank(alice);
        token.approve(address(staking), 1000 * 1e18);
        staking.stake(1000 * 1e18, 0); // alice vp = 1000e18 = proposalThreshold
        vm.stopPrank();

        bytes memory data = abi.encodeWithSelector(DaimonV2.setFees.selector, uint256(0), uint256(0), uint256(0));

        vm.roll(block.number + 1); // snapshot a block - 1 (#12)
        vm.prank(alice);
        uint256 proposalId = governor.propose(address(token), 0, data, "Zero fees");

        vm.warp(block.timestamp + governor.VOTING_DELAY() + 1);
        vm.prank(alice);
        governor.castVote(proposalId, 1);

        vm.warp(block.timestamp + governor.VOTING_PERIOD() + 1);

        // totalVotes = 1000e18 < quorum = 10% of 91_000e18 = 9_100e18
        assertEq(uint8(governor.state(proposalId)), uint8(DaimonGovernor.ProposalState.Defeated));
    }

    function test_QuorumUsesSnapshotNotLiveVotingPower() public {
        _deployFullStack();

        _giveAliceSomeNewTokens(500_000 * 1e18);
        vm.prank(alice);
        token.transfer(bob, 200_000 * 1e18); // 5% fee: bob receives ~190k

        // Snapshot: at proposal time the only voting power is alice's (5000e18).
        // She votes with 100% of the snapshot: quorum widely reached relative to
        // the snapshot.
        vm.startPrank(alice);
        token.approve(address(staking), 5000 * 1e18);
        staking.stake(5000 * 1e18, 0);
        vm.stopPrank();

        bytes memory data = abi.encodeWithSelector(DaimonV2.setFees.selector, uint256(10), uint256(10), uint256(20));
        vm.roll(block.number + 1); // snapshot a block - 1 (#12)
        vm.prank(alice);
        uint256 proposalId = governor.propose(address(token), 0, data, "Snapshot quorum");

        vm.warp(block.timestamp + governor.VOTING_DELAY() + 1);
        vm.prank(alice);
        governor.castVote(proposalId, 1);

        vm.warp(block.timestamp + governor.VOTING_PERIOD() + 1);
        assertEq(uint8(governor.state(proposalId)), uint8(DaimonGovernor.ProposalState.Succeeded));

        // AFTER voting ends bob stakes a huge amount: the live totalVotingPower
        // rises to ~185_000e18, whose 10% (18_500e18) would be above the 5000e18
        // voted. If quorum used the live value the proposal would retroactively
        // become Defeated; with the snapshot it stays Succeeded.
        vm.startPrank(bob);
        token.approve(address(staking), 180_000 * 1e18);
        staking.stake(180_000 * 1e18, 0);
        vm.stopPrank();

        assertGt(staking.totalVotingPower(), 100_000 * 1e18); // the live value really did grow
        assertEq(uint8(governor.state(proposalId)), uint8(DaimonGovernor.ProposalState.Succeeded));
    }

    function test_ExecuteRevertsIfNotQueued() public {
        _deployFullStack();

        _giveAliceSomeNewTokens(2_000_000 * 1e18);
        vm.startPrank(alice);
        token.approve(address(staking), 2_000_000 * 1e18);
        staking.stake(2_000_000 * 1e18, 3);
        vm.stopPrank();

        bytes memory data = abi.encodeWithSelector(DaimonV2.setFees.selector, uint256(10), uint256(10), uint256(20));
        vm.roll(block.number + 1); // snapshot a block - 1 (#12)
        vm.prank(alice);
        uint256 proposalId = governor.propose(address(token), 0, data, "Skip the queue");

        vm.warp(block.timestamp + governor.VOTING_DELAY() + 1);
        vm.prank(alice);
        governor.castVote(proposalId, 1);

        vm.warp(block.timestamp + governor.VOTING_PERIOD() + 1);
        assertEq(uint8(governor.state(proposalId)), uint8(DaimonGovernor.ProposalState.Succeeded));

        // Proposal approved but NEVER scheduled on the Timelock: execute() must
        // reject it, otherwise it would skip the public 7-day delay.
        vm.expectRevert(DaimonGovernor.ProposalNotQueued.selector);
        governor.execute(proposalId);

        // Correct path: queue -> wait for the delay -> execute.
        governor.queue(proposalId);
        vm.warp(block.timestamp + timelock.getMinDelay() + 1);
        governor.execute(proposalId);
        assertEq(token.taxFee(), 10);
    }

    // ============================================================
    // Test 5: burn floor never violated
    // ============================================================
    function test_BurnNeverGoesBelowFloor() public {
        _deployFullStack();

        // Give the mock router a large amount of DaimonV2 tokens so that
        // swapExactETHForTokensSupportingFeeOnTransferTokens can actually send
        // them to the dead address (the mock does a real, un-minted transfer:
        // it must have the balance).
        vm.prank(address(migration));
        token.transfer(address(router), 800_000_000_000 * 1e18);

        // Send ETH to the token and manually trigger multiple buy/burn rounds by
        // repeatedly calling the public accounting-cleanup function, after
        // getting tokens to the dead address via direct swaps on the router
        // (simulating what would happen inside _buyBackAndBurn in the normal
        // _transfer flow).
        vm.deal(address(this), 0);
        address[] memory path = new address[](2);
        path[0] = address(weth);
        path[1] = address(token);

        // Read the dead address BEFORE vm.prank: a staticcall used as an
        // argument would consume the prank, and the swap would originate from
        // the test contract (with no ETH) instead of alice.
        address dead = token.deadAddress();

        // Run many "buy and burn" rounds until the gap between the current
        // supply and MIN_SUPPLY is exhausted, checking at each step that _tTotal
        // never drops below the floor.
        uint256 floor = token.MIN_SUPPLY();
        for (uint256 i = 0; i < 50; i++) {
            vm.deal(alice, 10 ether);
            vm.prank(alice);
            router.swapExactETHForTokensSupportingFeeOnTransferTokens{value: 10 ether}(
                0, path, dead, block.timestamp + 300
            );

            token.burnDeadBalanceToFloor();

            assertGe(token.totalSupply(), floor);
            if (token.totalSupply() == floor) break;
        }
    }

    /// Finding #5: burnDeadBalanceToFloor() is permissionless and writes
    /// _rTotal and _tTotal â€” the reflection accounting itself. While the
    /// guardian holds the token paused, that accounting must stay frozen:
    /// pausing to investigate a suspected problem in it, while leaving a
    /// public function that mutates it open, would defeat the pause.
    function test_BurnToFloorBlockedWhilePaused() public {
        _deployFullStack();

        // Give the dead address something to burn.
        vm.prank(address(migration));
        token.transfer(address(0xdEaD), 5_000_000 * 1e18);
        uint256 supplyBefore = token.totalSupply();
        uint256 deadBefore = token.balanceOf(token.deadAddress());
        assertGt(deadBefore, 0, "nothing to burn");

        vm.prank(guardian);
        token.setPaused(true);

        // Anyone can call it, but not while paused.
        vm.expectRevert(DaimonV2.ContractIsPaused.selector);
        token.burnDeadBalanceToFloor();

        // The accounting is untouched by the rejected call.
        assertEq(token.totalSupply(), supplyBefore, "supply moved while paused");
        assertEq(token.balanceOf(token.deadAddress()), deadBefore, "dead balance moved while paused");

        // After the resume it works again, permissionless as before.
        vm.prank(guardian);
        token.setPaused(false);
        token.burnDeadBalanceToFloor();
        assertLt(token.totalSupply(), supplyBefore, "burn did not resume after unpause");
    }

    // ============================================================
    // Test 6: Guardian 36-month expiry
    // ============================================================
    function test_GuardianCanPauseBeforeExpiry() public {
        _deployFullStack();
        vm.prank(guardian);
        token.setPaused(true);
        assertTrue(token.paused());
        // #36: la pausa e' una FINESTRA di 14 giorni, non un latch.
        assertTrue(token.isPaused());
        assertEq(token.pauseUntil(), block.timestamp + token.MAX_PAUSE_DURATION());

        vm.prank(guardian);
        token.setPaused(false);
        assertFalse(token.paused());
        assertFalse(token.isPaused());
        assertEq(token.pauseUntil(), 0);
    }

    function test_GuardianCannotPauseAfter36Months() public {
        _deployFullStack();

        vm.warp(block.timestamp + 1096 days); // 36 months + 1 day

        vm.prank(guardian);
        vm.expectRevert(DaimonV2.GuardianExpired.selector);
        token.setPaused(true);
    }

    function test_TimelockCannotGoBelowMinDelay() public {
        _deployFullStack();
        vm.prank(address(timelock));
        vm.expectRevert("DaimonTimelock: below MIN_DELAY");
        timelock.updateDelay(1 days); // below the 7-day minimum
    }

    function test_FeesCannotExceedHardCap() public {
        _deployFullStack();
        vm.prank(address(timelock));
        vm.expectRevert(DaimonV2.FeeTooHigh.selector);
        token.setFees(50, 30, 30); // 11% total, above the 10% cap
    }

    // ============================================================
    // Test 7: security-review fixes
    // ============================================================

    // --- A1: castVote uses the snapshot, not the live voting power ---
    function test_CastVoteUsesSnapshotVotingPower() public {
        _deployFullStack();
        _giveAliceSomeNewTokens(200_000 * 1e18);

        // alice stakes BEFORE the proposal and passes tokens to bob
        vm.startPrank(alice);
        token.approve(address(staking), 2000 * 1e18);
        staking.stake(2000 * 1e18, 0);
        token.transfer(bob, 50_000 * 1e18);
        vm.stopPrank();

        bytes memory data = abi.encodeWithSelector(DaimonV2.setFees.selector, uint256(10), uint256(10), uint256(20));
        vm.roll(block.number + 1); // snapshot a block - 1 (#12)
        vm.prank(alice);
        uint256 proposalId = governor.propose(address(token), 0, data, "Snapshot votes");

        // bob stakes AFTER proposal creation (during the voting delay)
        vm.warp(block.timestamp + 12 hours);
        vm.startPrank(bob);
        token.approve(address(staking), 40_000 * 1e18);
        staking.stake(40_000 * 1e18, 0);
        vm.stopPrank();

        vm.warp(block.timestamp + 13 hours); // past voteStart, within the voting period

        // bob has live voting power but NONE at the snapshot: he cannot vote
        assertGt(staking.votingPower(bob), 0);
        vm.prank(bob);
        vm.expectRevert(DaimonGovernor.InsufficientVotingPower.selector);
        governor.castVote(proposalId, 1);

        // alice, instead, votes with the weight she had at the snapshot
        vm.prank(alice);
        governor.castVote(proposalId, 1);
    }

    function test_VotingPowerAtTracksCheckpoints() public {
        _deployFullStack();
        _giveAliceSomeNewTokens(1000 * 1e18);

        // Fixed literal block numbers: with via-ir the compiler treats
        // block.number as invariant within the transaction and may re-read
        // it after a vm.roll instead of reusing the value saved earlier â€”
        // so we never derive checkpoint keys from block.number here. (The
        // checkpoints are keyed by BLOCK since the #12 fix; the lock expiry
        // stays on wall-clock time, hence the warp before withdraw.)
        uint256 bStake = 1_000;
        vm.roll(bStake);

        vm.startPrank(alice);
        token.approve(address(staking), 1000 * 1e18);
        uint256 lockId = staking.stake(1000 * 1e18, 0); // 30d, 1x
        vm.stopPrank();

        assertEq(staking.votingPowerAt(alice, bStake), 1000 * 1e18);
        assertEq(staking.votingPowerAt(alice, bStake - 1), 0); // prima dello stake: zero

        vm.roll(bStake + 100);
        vm.warp(block.timestamp + 31 days);
        vm.prank(alice);
        staking.withdraw(lockId);

        assertEq(staking.votingPowerAt(alice, bStake + 100), 0);          // oggi: zero
        assertEq(staking.votingPowerAt(alice, bStake + 50), 1000 * 1e18); // lo storico resta interrogabile
    }

    // --- A2: no EOA holds the Timelock admin after wiring ---
    function test_NoEOAHoldsTimelockAdminAfterWiring() public {
        _deployFullStack();
        bytes32 adminRole = timelock.ADMIN_ROLE();
        bytes32 proposerRole = timelock.PROPOSER_ROLE();

        assertTrue(timelock.hasRole(adminRole, address(timelock))); // self-administered
        assertFalse(timelock.hasRole(adminRole, deployer));
        assertFalse(timelock.hasRole(adminRole, guardian));
        assertFalse(timelock.hasRole(adminRole, alice));

        // the deployer can no longer rotate roles
        vm.prank(deployer);
        vm.expectRevert();
        timelock.grantRole(proposerRole, deployer);
    }

    // --- A3 + M1: fee swap with slippage protection and fund split ---
    function test_FeeSwapSlippageProtectedAndFundsSplit() public {
        _deployFullStack();

        // lower the swap threshold to the minimum allowed (0.0001% = 1M tokens)
        vm.prank(address(timelock));
        token.setMinimumTokensBeforeSwap(1_000_000 * 1e18);

        vm.deal(address(router), 5000 ether);

        // accumulate fees in the contract: taxed transfer alice -> bob
        _giveAliceSomeNewTokens(100_000_000 * 1e18);
        vm.prank(alice);
        token.transfer(bob, 50_000_000 * 1e18); // 4% liquidity fee = 2M tokens to the contract

        assertGe(token.balanceOf(address(token)), 1_000_000 * 1e18);

        address pair = token.uniswapV2Pair();
        address dead = token.deadAddress();
        uint256 marketingBefore = marketingWallet.balance;

        // sell to the pair: triggers _swapAccumulatedFees (with minOut from the
        // router quote) and then the buyback (also with minOut)
        vm.prank(alice);
        token.transfer(pair, 1000 * 1e18);

        // 1M tokens swapped at rate 1e15 = 1000 ether received:
        // marketing branch = 20/40 = 500 ether, of which 60% staking / 40% wallet
        assertEq(marketingWallet.balance - marketingBefore, 200 ether);
        assertEq(address(staking).balance, 300 ether);
        assertEq(staking.zeroStakerReserve(), 300 ether); // nobody staking: reserved, never merged (#35)
        assertGt(token.balanceOf(dead), 0); // buyback eseguito nonostante minOut > 0
    }

    function test_MaxSwapSlippageGovernedAndBounded() public {
        _deployFullStack();
        assertEq(token.maxSwapSlippageBps(), 500); // default 5%

        vm.prank(alice);
        vm.expectRevert();
        token.setMaxSwapSlippageBps(1000); // not governance

        vm.prank(address(timelock));
        vm.expectRevert("DaimonV2: slippage out of range");
        token.setMaxSwapSlippageBps(3001);

        vm.prank(address(timelock));
        vm.expectRevert("DaimonV2: slippage out of range");
        token.setMaxSwapSlippageBps(49);

        vm.prank(address(timelock));
        token.setMaxSwapSlippageBps(1000);
        assertEq(token.maxSwapSlippageBps(), 1000);
    }

    // --- M3: withdraw subtracts exactly the credited voting power ---
    function test_WithdrawUsesStoredVotingPower() public {
        _deployFullStack();
        _giveAliceSomeNewTokens(1500 * 1e18);

        vm.startPrank(alice);
        token.approve(address(staking), 1500 * 1e18);
        uint256 lockA = staking.stake(1000 * 1e18, 0); // 1x -> 1000
        uint256 lockB = staking.stake(500 * 1e18, 3);  // 4x -> 2000
        vm.stopPrank();

        assertEq(staking.votingPower(alice), 3000 * 1e18);

        vm.warp(block.timestamp + 366 days);
        vm.prank(alice);
        staking.withdraw(lockB);
        assertEq(staking.votingPower(alice), 1000 * 1e18); // exactly -2000
        assertEq(staking.totalVotingPower(), 1000 * 1e18);

        vm.prank(alice);
        staking.withdraw(lockA);
        assertEq(staking.votingPower(alice), 0);
        assertEq(staking.totalVotingPower(), 0);
    }

    // --- M5: the dead address does not accrue reflection ---
    function test_DeadAddressDoesNotAccrueReflections() public {
        _deployFullStack();

        vm.prank(address(migration));
        token.transfer(address(router), 1_000_000 * 1e18);

        address dead = token.deadAddress();
        address[] memory path = new address[](2);
        path[0] = address(weth);
        path[1] = address(token);

        vm.deal(alice, 1 ether);
        vm.prank(alice);
        router.swapExactETHForTokensSupportingFeeOnTransferTokens{value: 1 ether}(
            0, path, dead, block.timestamp + 300
        );

        uint256 deadBal = token.balanceOf(dead);
        assertGt(deadBal, 0);

        // many taxed transfers: reflection must not grow the dead balance
        _giveAliceSomeNewTokens(10_000_000 * 1e18);
        vm.startPrank(alice);
        for (uint256 i = 0; i < 5; i++) {
            token.transfer(bob, 1_000_000 * 1e18);
        }
        vm.stopPrank();

        assertEq(token.balanceOf(dead), deadBal);
    }

    // --- M1 + M2, semantics changed by the #35 fix: rewards received with no
    // staker are RESERVED, never merged into later distributions. The old
    // behaviour this test asserted (backlog flowing to the first staker) was
    // exactly the finding: 1 wei staked at the right moment captured it all.
    function test_ZeroStakerRewardsAreReservedNotMerged() public {
        _deployFullStack();

        vm.deal(address(this), 10 ether);
        staking.notifyRewardAmount{value: 4 ether}(4 ether);
        assertEq(staking.zeroStakerReserve(), 4 ether);
        assertEq(staking.pendingReward(alice), 0);

        _giveAliceSomeNewTokens(1000 * 1e18);
        vm.startPrank(alice);
        token.approve(address(staking), 1000 * 1e18);
        staking.stake(1000 * 1e18, 0);
        vm.stopPrank();

        staking.notifyRewardAmount{value: 2 ether}(2 ether);
        assertEq(staking.zeroStakerReserve(), 4 ether); // untouched by the distribution
        assertEq(staking.pendingReward(alice), 2 ether); // only the new notify, exact at 1e27 scale

        uint256 balBefore = alice.balance;
        vm.prank(alice);
        staking.claimReward();
        assertEq(alice.balance - balBefore, 2 ether);
        assertEq(staking.zeroStakerReserve(), 4 ether); // claims cannot reach the reserve
    }

    // --- B7: dopo la scadenza il guardian puo' solo togliere la pausa ---
    // #36: la pausa non puo' piu' SOPRAVVIVERE alla scadenza â€” la finestra
    // lapsa da sola (qui gia' dopo 14 giorni, e comunque mai oltre
    // guardianExpiry), senza bisogno di alcuna chiamata. Prima del fix
    // questo test tollerava una pausa ancora effettiva dopo 36 mesi: era il
    // comportamento difettoso del finding.
    function test_GuardianCanUnpauseAfterExpiry() public {
        _deployFullStack();
        vm.prank(guardian);
        token.setPaused(true);
        assertTrue(token.isPaused());

        vm.warp(block.timestamp + 1096 days);

        // Auto-risanamento: NESSUNA chiamata, eppure il token non e' piu'
        // in pausa. Il flag grezzo resta armato ma senza effetto.
        assertTrue(token.paused());
        assertFalse(token.isPaused());

        vm.prank(guardian);
        vm.expectRevert(DaimonV2.GuardianExpired.selector);
        token.setPaused(true);

        // L'unpause residuo pulisce il flag, sempre possibile.
        vm.prank(guardian);
        token.setPaused(false);
        assertFalse(token.paused());
    }

    // --- B3: invalid support rejected ---
    function test_CastVoteRevertsOnInvalidSupport() public {
        _deployFullStack();
        _giveAliceSomeNewTokens(2000 * 1e18);
        vm.startPrank(alice);
        token.approve(address(staking), 2000 * 1e18);
        staking.stake(2000 * 1e18, 0);
        vm.stopPrank();

        bytes memory data = abi.encodeWithSelector(DaimonV2.setFees.selector, uint256(10), uint256(10), uint256(20));
        vm.prank(alice);
        uint256 proposalId = governor.propose(address(token), 0, data, "Invalid support");

        vm.warp(block.timestamp + governor.VOTING_DELAY() + 1);
        vm.prank(alice);
        vm.expectRevert(DaimonGovernor.InvalidSupport.selector);
        governor.castVote(proposalId, 3);
    }

    // --- B4: claim reverts if the NEW token applies a fee ---
    function test_MigrationRevertsIfNewTokenTakesFee() public {
        _deployFullStack();

        // simulated wiring error: the migration loses its fee exclusion
        vm.prank(address(timelock));
        token.setExcludedFromFee(address(migration), false);

        oldToken.excludeFromFee(treasury); // the old-token side is fine
        vm.startPrank(alice);
        oldToken.approve(address(migration), 1000 * 1e18);
        vm.expectRevert(DaimonMigration.AmountMismatch.selector);
        migration.claim(1000 * 1e18);
        vm.stopPrank();
    }

    // --- B6: events on sensitive setters ---
    function test_SetterEventsEmitted() public {
        _deployFullStack();

        vm.prank(address(timelock));
        vm.expectEmit(true, false, false, true, address(token));
        emit DaimonV2.ExcludedFromFeeSet(alice, true);
        token.setExcludedFromFee(alice, true);

        vm.prank(address(timelock));
        vm.expectEmit(true, false, false, true, address(token));
        emit DaimonV2.MarketingWalletSet(bob);
        token.setMarketingWallet(bob);

        vm.prank(address(timelock));
        vm.expectEmit(false, false, false, true, address(token));
        emit DaimonV2.SwapAndLiquifyEnabledSet(false);
        token.setSwapAndLiquifyEnabled(false);

        vm.prank(address(timelock));
        vm.expectEmit(false, false, false, true, address(token));
        emit DaimonV2.BuyBackEnabledSet(false);
        token.setBuyBackEnabled(false);
    }

    // --- M7: floor on the swap threshold ---
    function test_MinimumSwapThresholdHasFloor() public {
        _deployFullStack();
        uint256 floorAmt = token.totalSupply() / 1_000_000;

        vm.prank(address(timelock));
        vm.expectRevert("DaimonV2: swap threshold too low");
        token.setMinimumTokensBeforeSwap(floorAmt - 1);

        vm.prank(address(timelock));
        token.setMinimumTokensBeforeSwap(floorAmt);
        assertEq(token.minimumTokensBeforeSwap(), floorAmt);
    }

    // ============================================================
    // Helpers
    // ============================================================
    function _giveAliceSomeNewTokens(uint256 amount) internal {
        // For tests that do not go through the migration, the deployer (which
        // holds the rest of the initial supply before the transfer to migration)
        // may have no funds left after _deployFullStack. Here we simulate a
        // second channel: we use the migration directly to give alice new
        // tokens, assuming alice still has old Daimon to migrate (she holds the
        // entire OLD_SUPPLY in setUp). The preparatory step documented in
        // DaimonMigration (zeroing the old token's fee toward the treasury) is
        // replicated here: without it, claim() reverts with AmountMismatch by
        // design.
        oldToken.excludeFromFee(treasury);
        vm.startPrank(alice);
        oldToken.approve(address(migration), amount);
        migration.claim(amount);
        vm.stopPrank();
    }
}
