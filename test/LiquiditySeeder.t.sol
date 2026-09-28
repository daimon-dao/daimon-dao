// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {DaimonV2} from "../src/DaimonV2.sol";
import {MockUniswapV2Router02} from "../src/mocks/MockUniswap.sol";
import {LiquiditySeeder} from "../script/launch/LiquiditySeeder.sol";
import {WBNBLite, PairLite, FactoryLite} from "./utils/V2PairLite.sol";

/// Stands in for the Timelock: the seeder only needs an address with code.
contract TimelockStub {}

/*
 * Launch step 5b through the LiquiditySeeder (script/launch/), against the
 * REAL DaimonV2 (proxy, launch fees 10/10/20) and a pair with the real
 * UniswapV2 mint/sync/skim semantics (test/utils/V2PairLite.sol).
 *
 * The amounts are the launch-day numbers the mainnet fork produced on
 * 2026-09-28 (docs/MAINNET_FORK_RESULTS.md, F5a.3): 4998406600825315109208480483
 * DMN gross against 2.261 BNB at the DMX price of 471191826 wei per token.
 */
contract LiquiditySeederTest is Test {
    uint256 internal constant GROSS = 4_998_406_600_825_315_109_208_480_483;
    uint256 internal constant BNB = 2.261 ether;

    DaimonV2 internal token;
    WBNBLite internal wbnb;
    PairLite internal pair;
    LiquiditySeeder internal seeder;
    address internal timelock;

    address internal deployer = address(0xD1);
    address internal owner = address(0x0DD);        // the DMX owner
    address internal migration = address(0x316);   // holds the supply, fee-exempt
    address internal guardian = address(0x6A);
    address internal stranger = address(0xBAD);

    function setUp() public {
        wbnb = new WBNBLite();
        FactoryLite factory = new FactoryLite();
        MockUniswapV2Router02 router = new MockUniswapV2Router02(address(factory), address(wbnb));
        timelock = address(new TimelockStub());

        vm.startPrank(deployer);
        DaimonV2 impl = new DaimonV2();
        token = DaimonV2(payable(address(new ERC1967Proxy(
            address(impl),
            abi.encodeCall(DaimonV2.initialize, ("Daimon", "DMN", migration, address(router), deployer, guardian, timelock))
        ))));
        token.setFees(10, 10, 20); // the launch model, as phase 2 sets it
        vm.stopPrank();

        // Step 5a: the owner holds exactly the gross (the migration is
        // fee-exempt, so the transfer is exact, like the claim).
        vm.prank(migration);
        token.transfer(owner, GROSS);
        assertEq(token.balanceOf(owner), GROSS);

        pair = PairLite(token.uniswapV2Pair());
        seeder = new LiquiditySeeder(owner, address(token), address(pair), address(wbnb), timelock);
        vm.deal(owner, 3 ether);
        vm.deal(stranger, 10 ether);
    }

    // ---- helpers ------------------------------------------------------------

    function _net(uint256 gross) internal pure returns (uint256) {
        return gross - (gross * 10) / 1000 - (gross * 30) / 1000;
    }

    function _reserves() internal view returns (uint256 rDmn, uint256 rWbnb) {
        (uint112 r0, uint112 r1, ) = pair.getReserves();
        (rDmn, rWbnb) = pair.token0() == address(token) ? (uint256(r0), uint256(r1)) : (uint256(r1), uint256(r0));
    }

    function _seed() internal returns (uint256 liquidity) {
        vm.startPrank(owner);
        token.approve(address(seeder), GROSS);
        liquidity = seeder.seed{value: BNB}(GROSS);
        vm.stopPrank();
    }

    /// The 5b grief: 1 wei of WBNB into the empty pair, then sync().
    function _grief(uint256 wei_) internal {
        vm.startPrank(stranger);
        wbnb.deposit{value: wei_}();
        wbnb.transfer(address(pair), wei_);
        pair.sync();
        vm.stopPrank();
    }

    function _assertNothingLeft() internal view {
        assertEq(address(seeder).balance, 0, "BNB left in the seeder");
        assertEq(wbnb.balanceOf(address(seeder)), 0, "WBNB left in the seeder");
        assertEq(token.balanceOf(address(seeder)), 0, "DMN left in the seeder");
        assertEq(pair.balanceOf(address(seeder)), 0, "LP left in the seeder");
        assertEq(token.allowance(owner, address(seeder)), 0, "allowance left");
    }

    // ---- the normal seed ------------------------------------------------------

    function test_SeedOpensThePoolAndMintsEveryLpTokenToTheTimelock() public {
        uint256 liquidity = _seed();
        (uint256 rDmn, uint256 rWbnb) = _reserves();
        assertEq(rDmn, _net(GROSS), "the pair holds the net of the gross");
        assertEq(rDmn, 4_798_470_336_792_302_504_840_141_265, "the fork's launch-day net");
        assertEq(rWbnb, BNB, "the pair holds the BNB leg, wrapped");
        // Step 6 merged: all LP in the Timelock, minted there directly.
        assertEq(pair.balanceOf(timelock), liquidity);
        assertEq(pair.balanceOf(timelock), pair.totalSupply() - 1000);
        assertEq(pair.balanceOf(owner), 0);
        assertEq(pair.balanceOf(deployer), 0);
        // The owner put in exactly the gross and the leg.
        assertEq(token.balanceOf(owner), 0);
        assertEq(owner.balance, 3 ether - BNB);
        assertTrue(seeder.used());
        _assertNothingLeft();
        // The opening price: the DMX price of the fork run, 471191826 wei per
        // token, rounded down by the net being rounded up.
        assertEq((rWbnb * 1e18) / rDmn, 471_191_825);
    }

    function test_SeedEmitsTheNumbers() public {
        vm.startPrank(owner);
        token.approve(address(seeder), GROSS);
        vm.expectEmit(false, false, false, false, address(seeder));
        emit LiquiditySeeder.Seeded(0, 0, 0, 0, 0, 0);
        seeder.seed{value: BNB}(GROSS);
        vm.stopPrank();
    }

    // ---- single use, owner only -------------------------------------------------

    function test_SecondCallReverts() public {
        _seed();
        vm.prank(migration);
        token.transfer(owner, 1e18);
        vm.startPrank(owner);
        token.approve(address(seeder), 1e18);
        vm.expectRevert(LiquiditySeeder.AlreadyUsed.selector);
        seeder.seed{value: 0.001 ether}(1e18);
        vm.stopPrank();
    }

    function test_NonOwnerReverts() public {
        vm.prank(owner);
        token.approve(address(seeder), GROSS);
        vm.prank(stranger);
        vm.expectRevert(LiquiditySeeder.NotOwner.selector);
        seeder.seed{value: BNB}(GROSS);
        assertFalse(seeder.used());
        // The owner can still seed afterwards.
        vm.prank(owner);
        seeder.seed{value: BNB}(GROSS);
        assertTrue(seeder.used());
    }

    function test_ZeroAmountsRevert() public {
        vm.startPrank(owner);
        token.approve(address(seeder), GROSS);
        vm.expectRevert(LiquiditySeeder.ZeroAmount.selector);
        seeder.seed{value: 0}(GROSS);
        vm.expectRevert(LiquiditySeeder.ZeroAmount.selector);
        seeder.seed{value: BNB}(0);
        vm.stopPrank();
        assertFalse(seeder.used());
    }

    // ---- the grief it exists for ---------------------------------------------------

    function test_GriefedPairStillSeedsCorrectly() public {
        _grief(1);
        (uint256 r0Dmn, uint256 r0Wbnb) = _reserves();
        assertEq(r0Dmn, 0);
        assertEq(r0Wbnb, 1, "the grief: reserves (0, 1 wei)");
        uint256 liquidity = _seed();
        (uint256 rDmn, uint256 rWbnb) = _reserves();
        assertEq(rDmn, _net(GROSS));
        assertEq(rWbnb, BNB + 1, "the donated wei joins the pool");
        assertEq(pair.balanceOf(timelock), liquidity);
        assertEq(pair.balanceOf(timelock), pair.totalSupply() - 1000);
        _assertNothingLeft();
    }

    function test_UnsyncedDustDonationStillSeeds() public {
        vm.startPrank(stranger);
        wbnb.deposit{value: 1000}();
        wbnb.transfer(address(pair), 1000); // no sync: it sits above the (0,0) reserves
        vm.stopPrank();
        _seed();
        (, uint256 rWbnb) = _reserves();
        assertEq(rWbnb, BNB + 1000);
        assertEq(pair.balanceOf(timelock), pair.totalSupply() - 1000);
        _assertNothingLeft();
    }

    // ---- price sanity ------------------------------------------------------------------

    function test_SkewingWbnbDonationBeyondToleranceReverts() public {
        _grief(BNB / 500); // +0.2 % of the leg: twice the 0.10 % tolerance
        vm.startPrank(owner);
        token.approve(address(seeder), GROSS);
        vm.expectPartialRevert(LiquiditySeeder.PriceOutOfTolerance.selector);
        seeder.seed{value: BNB}(GROSS);
        vm.stopPrank();
        // Reverted as a whole: nothing moved, the seeder is still unused.
        assertFalse(seeder.used());
        assertEq(token.balanceOf(owner), GROSS);
        assertEq(pair.totalSupply(), 0);
    }

    function test_SkewingDmnDonationBeyondToleranceReverts() public {
        // Someone holding DMN (here the fee-exempt supply holder) parks 1 %
        // of the net in the pair: the opening price would sit 1 % low.
        vm.prank(migration);
        token.transfer(address(pair), _net(GROSS) / 100);
        vm.startPrank(owner);
        token.approve(address(seeder), GROSS);
        vm.expectPartialRevert(LiquiditySeeder.PriceOutOfTolerance.selector);
        seeder.seed{value: BNB}(GROSS);
        vm.stopPrank();
        assertFalse(seeder.used());
    }

    function test_DonationWithinToleranceSeeds() public {
        _grief(BNB / 2000); // +0.05 %: inside the 0.10 % tolerance
        _seed();
        (, uint256 rWbnb) = _reserves();
        assertEq(rWbnb, BNB + BNB / 2000);
        assertEq(pair.balanceOf(timelock), pair.totalSupply() - 1000);
        _assertNothingLeft();
    }

    // ---- nothing left, whatever was forced in ---------------------------------------------

    function test_NothingLeftEvenWithDustForcedIntoTheSeeder() public {
        // BNB can be forced into any address (selfdestruct, coinbase), and
        // WBNB can be sent to it: both are swept into the pool by the seed.
        vm.deal(address(seeder), 12_345);
        vm.startPrank(stranger);
        wbnb.deposit{value: 777}();
        wbnb.transfer(address(seeder), 777);
        vm.stopPrank();
        _seed();
        (, uint256 rWbnb) = _reserves();
        assertEq(rWbnb, BNB + 12_345 + 777);
        _assertNothingLeft();
    }

    function test_NoReceive() public {
        vm.prank(stranger);
        (bool ok, ) = address(seeder).call{value: 1 ether}("");
        assertFalse(ok, "the seeder accepts no plain BNB");
    }

    // ---- exact approval --------------------------------------------------------------------

    function test_OverApprovalReverts() public {
        vm.startPrank(owner);
        token.approve(address(seeder), GROSS + 1);
        vm.expectRevert(LiquiditySeeder.ApprovalNotExact.selector);
        seeder.seed{value: BNB}(GROSS);
        token.approve(address(seeder), type(uint256).max);
        vm.expectRevert(LiquiditySeeder.ApprovalNotExact.selector);
        seeder.seed{value: BNB}(GROSS);
        vm.stopPrank();
        assertFalse(seeder.used());
    }

    function test_UnderApprovalReverts() public {
        vm.startPrank(owner);
        token.approve(address(seeder), GROSS - 1);
        vm.expectRevert(bytes("DaimonV2: insufficient allowance"));
        seeder.seed{value: BNB}(GROSS);
        vm.stopPrank();
    }

    // ---- configuration ---------------------------------------------------------------------

    function test_ConstructorRejectsABadConfiguration() public {
        vm.expectRevert(LiquiditySeeder.BadConfig.selector);
        new LiquiditySeeder(owner, address(token), address(0x1234), address(wbnb), timelock); // not the token's pair
        vm.expectRevert(LiquiditySeeder.BadConfig.selector);
        new LiquiditySeeder(owner, address(token), address(pair), address(wbnb), address(0x7E)); // codeless timelock
        vm.expectRevert(LiquiditySeeder.BadConfig.selector);
        new LiquiditySeeder(address(0), address(token), address(pair), address(wbnb), timelock);
        WBNBLite otherWbnb = new WBNBLite();
        vm.expectRevert(LiquiditySeeder.BadConfig.selector);
        new LiquiditySeeder(owner, address(token), address(pair), address(otherWbnb), timelock); // pair is not DMN/that WBNB
    }

    // ---- #27: BNB donated to the token cannot block the seed ---------------------------------

    function test_BnbDonatedToTheTokenDoesNotBlockTheSeed() public {
        vm.deal(address(token), 5 ether); // > 1 BNB: the buyback branch is armed
        _grief(1);                         // and the pair is (0, 1): not empty for a naive check
        _seed();
        assertEq(pair.balanceOf(timelock), pair.totalSupply() - 1000);
        assertEq(address(token).balance, 5 ether, "buyback skipped on a one-sided pool");
        _assertNothingLeft();
    }
}
