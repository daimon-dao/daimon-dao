// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {StackDeployer} from "./base/StackDeployer.sol";
import {IUniswapV2Router02} from "../src/DaimonV2.sol";

/*
 * Finding #15: the token must never leave a standing ERC-20 allowance to the
 * router. _swapTokensForEth approves right before the swap; the swap is
 * wrapped in try/catch by design (a failed swap must not revert the user
 * transfer that triggered it), so on failure the approval used to stay
 * written in the outer frame. A later successful attempt overwrote it, but if
 * no attempt ever succeeded again it persisted indefinitely.
 */
contract RouterAllowanceTest is StackDeployer {
    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);

    function setUp() public {
        deployStack();
    }

    /// Fills the token contract with fee inventory above the swap threshold,
    /// so that a transfer to the pair triggers the automatic fee swap.
    function _armFeeSwap() internal returns (address pair) {
        vm.prank(address(timelock));
        token.setMinimumTokensBeforeSwap(1_000_000 ether);
        vm.deal(address(router), 5_000 ether);

        fundWithDmn(alice, 100_000_000 ether);
        vm.prank(alice);
        token.transfer(bob, 50_000_000 ether); // the 3% liquidity fee accrues to the contract

        assertGe(token.balanceOf(address(token)), 1_000_000 ether, "fee inventory not armed");
        return token.uniswapV2Pair();
    }

    /// The swap fails: the allowance granted immediately before it must not
    /// survive the call.
    function test_NoAllowanceLeftAfterFailedSwap() public {
        address pair = _armFeeSwap();

        vm.mockCallRevert(
            address(router),
            abi.encodeWithSelector(IUniswapV2Router02.swapExactTokensForETHSupportingFeeOnTransferTokens.selector),
            "router down"
        );

        vm.prank(alice);
        token.transfer(pair, 1_000 ether); // triggers the fee swap, which fails

        // The user transfer still went through — the swap failure is contained.
        assertGt(token.balanceOf(pair), 0, "user transfer reverted on a failed swap");
        assertEq(
            token.allowance(address(token), address(router)),
            0,
            "#15: allowance survived a failed swap"
        );
    }

    /// The quote is unavailable (this is what a reserveless pair does):
    /// no approval may be granted, and the user transfer must still go through.
    function test_NoAllowanceAndNoRevertWhenQuoteFails() public {
        address pair = _armFeeSwap();

        vm.mockCallRevert(
            address(router),
            abi.encodeWithSelector(IUniswapV2Router02.getAmountsOut.selector),
            "no reserves"
        );

        vm.prank(alice);
        token.transfer(pair, 1_000 ether);

        assertGt(token.balanceOf(pair), 0, "transfer blocked by an unavailable quote");
        assertEq(
            token.allowance(address(token), address(router)),
            0,
            "#15: allowance granted despite an unavailable quote"
        );
    }

    /// The happy path must leave the same clean state: the revoke applies to
    /// ANY outcome, not just failures.
    function test_NoAllowanceLeftAfterSuccessfulSwap() public {
        address pair = _armFeeSwap();

        vm.prank(alice);
        token.transfer(pair, 1_000 ether);

        assertEq(
            token.allowance(address(token), address(router)),
            0,
            "#15: allowance survived a successful swap"
        );
    }
}
