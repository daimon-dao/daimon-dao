// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {StackDeployer} from "./base/StackDeployer.sol";
import {DaimonV2} from "../src/DaimonV2.sol";
import {DaimonStaking} from "../src/DaimonStaking.sol";
import {DaimonGovernor} from "../src/DaimonGovernor.sol";
import {MockUniswapV2Factory, MockWETH} from "../src/mocks/MockUniswap.sol";

/*
 * Reproduction tests for the Zenith audit findings.
 *
 * EVERY TEST IN THIS FILE IS EXPECTED TO FAIL until the corresponding fix
 * lands. Each one asserts the SECURE (post-fix) behaviour, so a failure here
 * is the reproduction of the finding, and a pass is the proof that the fix
 * works. No test asserts the exploit succeeding: an "exploit succeeds" test
 * would pass today and start failing after the fix, which is the wrong way
 * round for a regression suite.
 *
 * src/ is untouched (frozen at tag audit-scope-v2); the helper contracts and
 * the reserve-aware router mock below live in test/ for that reason.
 */

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/*
 * Router mock that behaves like the real UniswapV2Library on an empty pool:
 * getAmountsOut REVERTS when the pair has no reserves. The mock in src/mocks
 * is a fixed-rate stub with no reserves at all, so it can never reproduce
 * finding #27 — hence this one.
 */
contract ReserveAwareRouter {
    address public immutable factory;
    address public immutable WETH;
    bool public hasReserves;

    constructor(address _factory, address _weth) {
        factory = _factory;
        WETH = _weth;
    }

    function setHasReserves(bool v) external {
        hasReserves = v;
    }

    function getAmountsOut(uint256 amountIn, address[] calldata path)
        external
        view
        returns (uint256[] memory amounts)
    {
        // UniswapV2Library.getAmountsOut -> getReserves -> INSUFFICIENT_LIQUIDITY
        require(hasReserves, "UniswapV2Library: INSUFFICIENT_LIQUIDITY");
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        amounts[1] = amountIn;
    }

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256,
        uint256,
        address[] calldata,
        address,
        uint256
    ) external {}

    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint256,
        address[] calldata,
        address,
        uint256
    ) external payable {}

    receive() external payable {}
}

/// Sends N dust transfers to the pair inside ONE transaction (finding #28).
contract DustTrigger {
    DaimonV2 private immutable dmn;
    address private immutable pair;

    constructor(DaimonV2 _dmn, address _pair) {
        dmn = _dmn;
        pair = _pair;
    }

    function spam(uint256 n) external {
        for (uint256 i = 0; i < n; i++) {
            dmn.transfer(pair, 1);
        }
    }
}

/// Stakes 1 wei, forces a distribution and claims — all in ONE tx (finding #35).
contract BacklogCaptor {
    DaimonStaking private immutable staking;
    DaimonV2 private immutable dmn;

    constructor(DaimonStaking _staking, DaimonV2 _dmn) {
        staking = _staking;
        dmn = _dmn;
    }

    function attack() external {
        dmn.approve(address(staking), type(uint256).max);
        staking.stake(1, 0); // 1 wei of principal
        staking.notifyRewardAmount{value: 0}(0); // flushes the backlog onto 1 wei of vp
        staking.claimReward();
    }

    receive() external payable {}
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

contract AuditFindings is StackDeployer {
    uint8 constant DEFEATED = 2;
    uint8 constant SUCCEEDED = 3;

    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);

    function setUp() public {
        deployStack();
    }

    function _stake(address who, uint256 amount, uint256 opt) internal returns (uint256 lockId) {
        fundWithDmn(who, amount);
        vm.startPrank(who);
        token.approve(address(staking), amount);
        lockId = staking.stake(amount, opt);
        vm.stopPrank();
    }

    function _state(uint256 id) internal view returns (uint8) {
        return uint8(governor.state(id));
    }

    // =======================================================================
    // #12 CRITICAL — same-block staking bypasses the proposal snapshot
    // =======================================================================
    /*
     * DaimonStaking._writeCheckpoint OVERWRITES the checkpoint when a stake
     * lands on a timestamp that already has one, and DaimonGovernor.castVote
     * reads votingPowerAt(voter, snapshotTimestamp). Staking in the same block
     * as propose() therefore back-dates the new voting power into the
     * snapshot the proposal is judged against.
     *
     * Secure behaviour asserted here: only the voting power held BEFORE the
     * proposal existed may count towards it.
     */
    function test_Finding12_sameBlockStakeMustNotCountAtSnapshot() public {
        address ally = address(0xBEEF);
        address attacker = address(0xBAD);

        _stake(ally, 99_000 ether, 0);
        _stake(attacker, 1_000 ether, 0);
        fundWithDmn(attacker, 9_000 ether);
        assertEq(staking.totalVotingPower(), 100_000 ether, "setup: total voting power");
        // Post-fix alignment: the snapshot is now block.number - 1, so the
        // legitimate pre-existing power must sit in a sealed block.
        vm.roll(block.number + 1);
        uint256 t0 = block.timestamp;

        vm.startPrank(attacker);
        token.approve(address(staking), 9_000 ether);
        uint256 id = governor.propose(address(token), 0, "", "p");
        uint256 snapshot = block.number - 1;
        staking.stake(9_000 ether, 0); // same block as propose, no roll
        vm.stopPrank();

        // The stake happened after the proposal existed: it must not be
        // visible at the snapshot.
        assertEq(
            staking.votingPowerAt(attacker, snapshot),
            1_000 ether,
            "#12: voting power staked in the proposal's own block counted at the snapshot"
        );

        vm.warp(t0 + governor.VOTING_DELAY());
        vm.prank(attacker);
        governor.castVote(id, 1);

        vm.warp(t0 + governor.VOTING_DELAY() + governor.VOTING_PERIOD() + 1);
        // 1,000 vp against a 10% quorum of 100,000 vp = 10,000 needed.
        assertEq(_state(id), DEFEATED, "#12: proposal reached quorum with back-dated voting power");
    }

    // =======================================================================
    // #27 MEDIUM — a donation blocks the launch (quote outside try/catch)
    // =======================================================================
    /*
     * _swapTokensForEth and _buyBackAndBurn call getAmountsOut BEFORE the
     * try/catch that guards the swap. On a pair with no reserves the real
     * UniswapV2Library reverts, and that revert propagates out of _transfer:
     * the transfer seeding the initial liquidity fails.
     *
     * Secure behaviour asserted here: seeding the pair succeeds regardless of
     * what an attacker donated to the token contract beforehand.
     */
    function _freshStackWithReserveAwareRouter()
        internal
        returns (DaimonV2 t, ReserveAwareRouter r, address pair)
    {
        MockWETH w = new MockWETH();
        MockUniswapV2Factory f = new MockUniswapV2Factory();
        r = new ReserveAwareRouter(address(f), address(w));

        DaimonV2 impl = new DaimonV2();
        bytes memory initData = abi.encodeCall(
            DaimonV2.initialize,
            (
                "Daimon",
                "DMN",
                address(this), // migration contract: holds the whole supply, fee-exempt
                address(r),
                address(this), // governance
                guardian,
                marketingWallet
            )
        );
        t = DaimonV2(payable(address(new ERC1967Proxy(address(impl), initData))));
        pair = t.uniswapV2Pair();
        // The pair exists but has no reserves yet: this is the launch state.
    }

    function test_Finding27_donatedBnbMustNotBlockInitialLiquidity() public {
        (DaimonV2 t,, address pair) = _freshStackWithReserveAwareRouter();

        // Attacker donates just above the 1 ether threshold that arms the buyback.
        vm.deal(address(t), 1.1 ether);

        // Seeding the pair with the initial DMN must not revert.
        t.transfer(pair, 1_000 ether);

        assertGt(t.balanceOf(pair), 0, "#27: BNB donation blocked the initial liquidity transfer");
    }

    function test_Finding27_donatedDmnMustNotBlockInitialLiquidity() public {
        (DaimonV2 t,, address pair) = _freshStackWithReserveAwareRouter();

        // Attacker pushes the contract's fee inventory over the swap threshold.
        t.transfer(address(t), t.minimumTokensBeforeSwap());

        t.transfer(pair, 1_000 ether);

        assertGt(t.balanceOf(pair), 0, "#27: DMN donation blocked the initial liquidity transfer");
    }

    // =======================================================================
    // #28 MEDIUM — dust transfers repeat the automation chunk within one tx
    // =======================================================================
    /*
     * _transfer runs _swapAccumulatedFees(minimumTokensBeforeSwap) on every
     * transfer to the pair once the inventory is over the threshold, and
     * _buyBackAndBurn(spend/20) on every transfer to the pair once the ETH
     * balance is over 1 ether. Neither is rate-limited per transaction, so a
     * loop of 1-wei transfers drains several chunks in a single tx.
     *
     * Secure behaviour asserted here: one transaction consumes at most one
     * chunk, whatever the number of dust transfers inside it.
     */
    function _armFeeInventory(uint256 chunks) internal returns (uint256 minSwap) {
        // The threshold is read BEFORE the prank: a staticcall used as an
        // argument would consume it and the setter would run as the test
        // contract, which holds no role.
        uint256 floorAmount = token.totalSupply() / 1_000_000;
        vm.prank(address(timelock));
        token.setMinimumTokensBeforeSwap(floorAmount);
        minSwap = token.minimumTokensBeforeSwap();

        // liquidityFee is 4% at initialize: move enough to bank `chunks` chunks.
        uint256 gross = (minSwap * chunks * 1000) / token.liquidityFee() + 1 ether;
        fundWithDmn(alice, gross + 10 ether);
        vm.prank(alice);
        token.transfer(bob, gross);

        assertGe(token.balanceOf(address(token)), minSwap * chunks, "setup: inventory not armed");
    }

    function _newDustTrigger() internal returns (DustTrigger d) {
        d = new DustTrigger(token, token.uniswapV2Pair());
        fundWithDmn(address(this), 10 ether);
        token.transfer(address(d), 5 ether);
    }

    function test_Finding28_feeSwapMustNotExceedOneChunkPerTx() public {
        uint256 minSwap = _armFeeInventory(5);

        // Isolate the fee-swap branch.
        vm.prank(address(timelock));
        token.setBuyBackEnabled(false);

        DustTrigger d = _newDustTrigger();

        uint256 invBefore = token.balanceOf(address(token));
        d.spam(5);
        uint256 consumed = invBefore - token.balanceOf(address(token));

        assertLe(consumed, minSwap, "#28: repeated dust transfers swapped more than one chunk in one tx");
    }

    function test_Finding28_buybackMustNotExceedOneChunkPerTx() public {
        _armFeeInventory(1);

        // Isolate the buyback branch.
        vm.prank(address(timelock));
        token.setSwapAndLiquifyEnabled(false);

        // Arm the buyback: ETH in the contract and DMN in the router to sell back.
        vm.deal(address(token), 10 ether);
        vm.prank(address(migration));
        token.transfer(address(router), 100_000 ether);

        DustTrigger d = _newDustTrigger();

        uint256 ethBefore = address(token).balance;
        uint256 expectedOneChunk = ethBefore / 20; // _buyBackAndBurn(spendAmount / 20)

        d.spam(5);
        uint256 spent = ethBefore - address(token).balance;

        assertLe(spent, expectedOneChunk, "#28: repeated dust transfers ran more than one buyback in one tx");
    }

    // =======================================================================
    // #35 MEDIUM — 1 wei of stake captures the whole reward backlog
    // =======================================================================
    /*
     * notifyRewardAmount queues BNB in undistributedRewards while
     * totalVotingPower is zero, then releases the entire backlog onto whatever
     * voting power exists at the next notify. Staking 1 wei and calling
     * notifyRewardAmount(0) in the same transaction makes that "whatever" be
     * the attacker alone.
     *
     * Secure behaviour asserted here: a dust stake cannot take the backlog
     * accrued before it existed.
     */
    function test_Finding35_dustStakeMustNotCaptureBacklog() public {
        uint256 backlog = 10 ether;

        // Rewards accrue while nobody is staking.
        vm.deal(address(this), backlog);
        staking.notifyRewardAmount{value: backlog}(backlog);
        assertEq(staking.zeroStakerReserve(), backlog, "setup: backlog not reserved");

        BacklogCaptor captor = new BacklogCaptor(staking, token);
        fundWithDmn(address(captor), 1_000 ether);

        captor.attack();

        assertLt(
            address(captor).balance,
            backlog,
            "#35: a 1 wei stake captured the entire reward backlog"
        );
    }

    receive() external payable {}
}
