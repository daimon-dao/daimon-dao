// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {DaimonV2} from "../src/DaimonV2.sol";
import {DaimonMigration} from "../src/DaimonMigration.sol";
import {MockUniswapV2Factory, MockUniswapV2Router02, MockWETH} from "../src/mocks/MockUniswap.sol";
import {CampaignOldDaimon} from "../script/campaign/CampaignOldDaimon.sol";

/*
 * Level 2b, H0.5/H0.6: the predecessor's transfer cap against claim().
 *
 * The real DMX carries _maxTxAmount = 1.5B, applied to every transfer unless
 * `from` or `to` is the owner, and a fee exemption does NOT lift it (verified
 * on-chain 2026-09-10/11, CHECKLIST_MAINNET.md). A claim is a DMX transfer
 * claimant -> treasury, so any holder above 1.5B cannot migrate until the
 * DMX owner raises the cap: launch order step 11a, BEFORE the exemption
 * (11b) opens the window.
 *
 * The predecessor under test is script/campaign/CampaignOldDaimon.sol, the
 * DMX-faithful mock the fork and Chapel campaigns deploy (src/mocks/
 * MockOldDaimon.sol is frozen with the audited range and deliberately keeps
 * the unit-test conveniences its header describes). The stack around it is
 * the production wiring: the migration is the initialize() recipient of the
 * whole supply, at its predicted address.
 */
contract OldDaimonMaxTxTest is Test {
    CampaignOldDaimon internal old;
    DaimonV2 internal token;
    DaimonMigration internal migration;

    address internal dmxOwner = address(0xD0);   // deploys the predecessor: its owner
    address internal deployer = address(0xD1);   // deploys the new stack
    address internal treasury = address(0x7E);   // stands in for the Timelock
    address internal holder = address(0xA1);     // a non-owner DMX holder
    address internal other = address(0xB1);

    uint256 internal constant OLD_SUPPLY = 1_000_000_000_000 ether; // 1000B
    uint256 internal constant CAP = 1_500_000_000 ether;            // the real 1.5B

    function setUp() public {
        vm.prank(dmxOwner);
        old = new CampaignOldDaimon(OLD_SUPPLY, dmxOwner);

        vm.startPrank(deployer);
        MockWETH weth = new MockWETH();
        MockUniswapV2Factory factory = new MockUniswapV2Factory();
        MockUniswapV2Router02 router = new MockUniswapV2Router02(address(factory), address(weth));
        DaimonV2 impl = new DaimonV2();
        // CREATEs left from here: proxy (+0), migration (+1).
        address predictedMigration = vm.computeCreateAddress(deployer, vm.getNonce(deployer) + 1);
        token = DaimonV2(payable(address(new ERC1967Proxy(
            address(impl),
            abi.encodeCall(DaimonV2.initialize, ("Daimon", "DMN", predictedMigration, address(router), deployer, deployer, treasury))
        ))));
        migration = new DaimonMigration(address(old), address(token), treasury, treasury, 30 days);
        require(address(migration) == predictedMigration, "predicted migration mismatch");
        vm.stopPrank();

        // The owner's own transfers are cap-exempt: the model distribution
        // (holders far above 1.5B) lands in one transfer each, as on the fork.
        vm.startPrank(dmxOwner);
        old.transfer(holder, 10_000_000_000 ether); // 10B, taxed 11% -> 8.9B, above the cap
        // Launch order step 11b (the window is open, fee-wise): the TREASURY
        // is exempt. Deliberately WITHOUT step 11a, so the cap is the only
        // thing standing between a large holder and its claim.
        old.excludeFromFee(treasury);
        vm.stopPrank();
    }

    function test_DefaultCapIsTheRealDmxValue() public view {
        assertEq(old.maxTxAmount(), CAP);
        assertEq(old.maxTxAmount(), 1_500_000_000 * 1e18);
    }

    function test_OwnerTransfersIgnoreTheCap() public {
        // Set up already moved 10B from the owner; the reverse direction is
        // exempt too (to == owner), whatever the sender's exemption status.
        vm.prank(holder);
        old.transfer(dmxOwner, 3_000_000_000 ether);
        assertEq(old.balanceOf(holder), 8_900_000_000 ether - 3_000_000_000 ether);
    }

    function test_ClaimAboveCapRevertsBeforeSetMaxTxAmount() public {
        uint256 amount = 3_000_000_000 ether; // 3B, twice the cap
        vm.startPrank(holder);
        old.approve(address(migration), amount);
        vm.expectRevert(bytes("Transfer amount exceeds the maxTxAmount."));
        migration.claim(amount);
        vm.stopPrank();
        // Nothing moved, nothing credited.
        assertEq(old.balanceOf(treasury), 0);
        assertEq(token.balanceOf(holder), 0);
        assertEq(migration.migratedAmount(holder), 0);
    }

    function test_ClaimExactlyAtCapPasses() public {
        vm.startPrank(holder);
        old.approve(address(migration), CAP);
        migration.claim(CAP);
        vm.stopPrank();
        assertEq(token.balanceOf(holder), CAP);
        assertEq(old.balanceOf(treasury), CAP);
    }

    function test_ClaimAboveCapPassesAfterSetMaxTxAmount() public {
        uint256 amount = 3_000_000_000 ether;
        // Launch order step 11a: the DMX owner raises the cap.
        vm.prank(dmxOwner);
        old.setMaxTxAmount(OLD_SUPPLY);
        assertEq(old.maxTxAmount(), OLD_SUPPLY);

        uint256 holderOldBefore = old.balanceOf(holder);
        vm.startPrank(holder);
        old.approve(address(migration), amount);
        migration.claim(amount);
        vm.stopPrank();

        // 1:1, no fee on either leg: the treasury holds EXACTLY the mock DMX
        // the holder declared, and the holder EXACTLY as much DMN.
        assertEq(old.balanceOf(treasury), amount, "treasury did not receive the exact amount");
        assertEq(old.balanceOf(holder), holderOldBefore - amount);
        assertEq(token.balanceOf(holder), amount, "holder did not receive 1:1");
        assertEq(migration.migratedAmount(holder), amount);
        assertEq(migration.totalMigrated(), amount);
    }

    function test_SetMaxTxAmountIsOwnerOnly() public {
        vm.prank(holder);
        vm.expectRevert(bytes("DMX: only owner"));
        old.setMaxTxAmount(OLD_SUPPLY);
        vm.prank(treasury);
        vm.expectRevert(bytes("DMX: only owner"));
        old.setMaxTxAmount(OLD_SUPPLY);
        assertEq(old.maxTxAmount(), CAP, "cap moved without the owner");
    }

    function test_FeeExemptionDoesNotLiftTheCap() public {
        // Both endpoints exempt from the FEE, neither the owner: the cap
        // still binds. This is the exact shape of a claim (exempt treasury
        // as recipient) and of an exempt sender, which the fork harness
        // relies on for the deployer's own liquidity claim.
        vm.startPrank(dmxOwner);
        old.excludeFromFee(holder);
        old.excludeFromFee(other);
        vm.stopPrank();
        vm.prank(holder);
        vm.expectRevert(bytes("Transfer amount exceeds the maxTxAmount."));
        old.transfer(other, CAP + 1);
        // At the cap it passes, and with both sides exempt it lands exact.
        vm.prank(holder);
        old.transfer(other, CAP);
        assertEq(old.balanceOf(other), CAP);
    }
}
