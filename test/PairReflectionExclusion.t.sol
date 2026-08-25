// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {StackDeployer} from "./base/StackDeployer.sol";

/*
 * Finding #30: the pair was not excluded from reflection. Its token balance
 * grew passively while its recorded reserve stayed unchanged, and anyone
 * could pocket the surplus by calling skim() on the pair — value taken from
 * the holders the reflection was meant for.
 *
 * The exclusion mapping is private and has no getter, so these tests assert
 * the BEHAVIOUR rather than the flag: a stronger proof, and it does not
 * require adding a getter that the fix itself does not need.
 */
contract PairReflectionExclusionTest is StackDeployer {
    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);
    address internal carol = address(0xCA401);

    /// Taxed traffic between two third parties, enough to generate reflection.
    function _generateReflection() internal {
        fundWithDmn(alice, 50_000_000 ether);
        vm.startPrank(alice);
        for (uint256 i = 0; i < 5; i++) {
            token.transfer(bob, 1_000_000 ether);
        }
        vm.stopPrank();
    }

    function setUp() public {
        deployStack();
    }

    /// The pair holds tokens and stays completely still while taxed transfers
    /// happen elsewhere: its balance must not move by a single wei.
    function test_PairBalanceDoesNotGrowWithReflection() public {
        address pair = token.uniswapV2Pair();

        // Seed the pair with liquidity (migration is fee-exempt: exact amount).
        vm.prank(address(migration));
        token.transfer(pair, 10_000_000 ether);
        uint256 pairBalance = token.balanceOf(pair);
        assertEq(pairBalance, 10_000_000 ether, "pair did not receive the exact amount");

        _generateReflection();

        assertEq(
            token.balanceOf(pair),
            pairBalance,
            "#30: the pair accrued reflection, skim() would let anyone take it"
        );
    }

    /// Control: an ordinary holder DOES accrue reflection over the same
    /// traffic. Without this, the test above could pass simply because no
    /// reflection was generated at all.
    function test_OrdinaryHolderStillAccruesReflection() public {
        fundWithDmn(carol, 5_000_000 ether);
        uint256 carolBefore = token.balanceOf(carol);

        _generateReflection();

        assertGt(
            token.balanceOf(carol),
            carolBefore,
            "no reflection was generated, the exclusion test would be vacuous"
        );
    }

    /// The dead address keeps its own exclusion: adding the pair must not
    /// have displaced the entry that was already there.
    function test_DeadAddressStillExcluded() public {
        // Read the address BEFORE the prank: a staticcall used as an argument
        // consumes it, and the transfer would originate from the test contract
        // (same caution already documented in DaimonDAO.t.sol).
        address dead = token.deadAddress();

        vm.prank(address(migration));
        token.transfer(dead, 5_000_000 ether);
        uint256 deadBalance = token.balanceOf(dead);
        assertGt(deadBalance, 0, "dead address received nothing");

        _generateReflection();

        assertEq(token.balanceOf(dead), deadBalance, "dead address accrued reflection");
    }

    /// The exclusion set stays FIXED: the fix adds an entry, it does not make
    /// the set mutable. No runtime reward-exclusion setter may exist, under
    /// any of the conventional names used by RFI forks.
    function test_NoRuntimeRewardExclusionSetter() public {
        (bool a,) = address(token).call(abi.encodeWithSignature("excludeFromReward(address)", alice));
        (bool b,) = address(token).call(abi.encodeWithSignature("includeInReward(address)", alice));
        (bool c,) = address(token).call(abi.encodeWithSignature("setExcludedFromReward(address,bool)", alice, true));

        assertFalse(a, "#30: excludeFromReward() exists");
        assertFalse(b, "#30: includeInReward() exists");
        assertFalse(c, "#30: setExcludedFromReward() exists");
    }
}
