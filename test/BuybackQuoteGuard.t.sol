// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {StackDeployer} from "./base/StackDeployer.sol";
import {DaimonV2} from "../src/DaimonV2.sol";
import {MockUniswapV2Factory, MockWETH} from "../src/mocks/MockUniswap.sol";

/*
 * Finding #27, BNB half.
 *
 * _buyBackAndBurn quoted getAmountsOut OUTSIDE the try/catch that guards the
 * swap. On a pair with no reserves the real UniswapV2Library reverts, and
 * that revert propagated out of _transfer: donating >1 BNB to the token was
 * enough to block the transfer seeding the initial liquidity. (The DMN half
 * of the finding goes through _swapTokensForEth and is closed by the #15
 * fix, which wrapped that quote.)
 */

/*
 * Same reserve-aware router as the reproduction suite: getAmountsOut REVERTS
 * when the pair has no reserves, like the real UniswapV2Library. The mock in
 * src/mocks is a fixed-rate stub that can never reproduce the finding.
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
        require(hasReserves, "UniswapV2Library: INSUFFICIENT_LIQUIDITY");
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        amounts[1] = amountIn;
    }
}

/// Pair double with code and zero reserves, etched onto the pair address to
/// exercise the reserve probe (the mock factory registers a codeless one).
contract ZeroReservesPair {
    function getReserves() external pure returns (uint112, uint112, uint32) {
        return (0, 0, 0);
    }
}

contract BuybackQuoteGuardTest is StackDeployer {
    address internal alice = address(0xA11CE);

    function setUp() public {
        deployStack();
    }

    function _freshStackWithReserveAwareRouter() internal returns (DaimonV2 t, address pair) {
        MockWETH w = new MockWETH();
        MockUniswapV2Factory f = new MockUniswapV2Factory();
        ReserveAwareRouter r = new ReserveAwareRouter(address(f), address(w));

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

    /// The reproduction scenario, asserted as fixed: a BNB donation above the
    /// 1 ether trigger no longer blocks the transfer that seeds the pool, and
    /// the skipped buyback is observable instead of silent.
    function test_DonatedBnbDoesNotBlockInitialLiquidity() public {
        (DaimonV2 t, address pair) = _freshStackWithReserveAwareRouter();

        vm.deal(address(t), 1.1 ether);

        // The mock pair has no code, so the reserve probe yields no verdict
        // and it is the WRAPPED QUOTE that absorbs the router revert.
        uint256 expectedSpend = 1.1 ether / 20;
        vm.expectEmit(false, false, false, true);
        emit DaimonV2.BuyBackSkipped(expectedSpend, DaimonV2.BuyBackSkipReason.QuoteUnavailable);

        t.transfer(pair, 1_000 ether);

        assertGt(t.balanceOf(pair), 0, "BNB donation blocked the initial liquidity transfer");
        assertEq(address(t).balance, 1.1 ether, "skipped buyback must not spend anything");
    }

    /// On a pair that answers getReserves with an empty pool, the probe skips
    /// BEFORE quoting: the reason distinguishes the path (a quote failure
    /// would report QuoteUnavailable, see the test above).
    function test_EmptyReservesSkipBeforeQuoting() public {
        (DaimonV2 t, address pair) = _freshStackWithReserveAwareRouter();

        ZeroReservesPair zp = new ZeroReservesPair();
        vm.etch(pair, address(zp).code);

        vm.deal(address(t), 1.1 ether);

        vm.expectEmit(false, false, false, true);
        emit DaimonV2.BuyBackSkipped(1.1 ether / 20, DaimonV2.BuyBackSkipReason.EmptyReserves);

        t.transfer(pair, 1_000 ether);

        assertGt(t.balanceOf(pair), 0, "empty-reserves skip still blocked the transfer");
    }

    /// A swap that fails downstream (here: the router cannot deliver the
    /// tokens) is reported as SwapFailed, and still never reverts the user
    /// transfer that triggered it.
    function test_SwapFailureIsReportedAndHarmless() public {
        // Standard stack: fixed-rate router, but NOT funded with DMN, so the
        // buyback's swap leg reverts inside the router.
        fundWithDmn(alice, 1_000 ether);
        vm.deal(address(token), 2 ether);

        address pair = token.uniswapV2Pair();
        uint256 expectedSpend = 2 ether / 20;

        vm.expectEmit(false, false, false, true);
        emit DaimonV2.BuyBackSkipped(expectedSpend, DaimonV2.BuyBackSkipReason.SwapFailed);

        vm.prank(alice);
        token.transfer(pair, 100 ether);

        assertEq(token.balanceOf(pair) > 0, true, "failed buyback reverted the user transfer");
        assertEq(address(token).balance, 2 ether, "failed buyback must not spend anything");
    }

    /// Happy path untouched: with reserves, a valid quote and a solvent
    /// router, the buyback executes and burns as before.
    function test_HealthyBuybackStillExecutes() public {
        fundWithDmn(alice, 1_000 ether);
        vm.deal(address(token), 2 ether);
        // Solvent router: it can deliver the bought tokens.
        vm.prank(address(migration));
        token.transfer(address(router), 100_000 ether);

        address pair = token.uniswapV2Pair();
        address dead = token.deadAddress();
        uint256 deadBefore = token.balanceOf(dead);

        vm.prank(alice);
        token.transfer(pair, 100 ether);

        assertLt(address(token).balance, 2 ether, "buyback spent nothing");
        assertGt(token.balanceOf(dead), deadBefore, "nothing reached the dead address");
    }
}
