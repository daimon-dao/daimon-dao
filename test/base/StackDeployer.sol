// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {DaimonV2} from "../../src/DaimonV2.sol";
import {DaimonStaking} from "../../src/DaimonStaking.sol";
import {DaimonGovernor} from "../../src/DaimonGovernor.sol";
import {DaimonTimelock} from "../../src/DaimonTimelock.sol";
import {DaimonMigration} from "../../src/DaimonMigration.sol";
import {MockOldDaimon} from "../../src/mocks/MockOldDaimon.sol";
import {MockUniswapV2Factory, MockUniswapV2Router02, MockWETH} from "../../src/mocks/MockUniswap.sol";

/*
 * Base di deploy condivisa da fuzz e invariant test.
 * Replica il wiring completo dello script di deploy (governance al Timelock,
 * supply nella migration, deployer senza ruoli) in modo autosufficiente per
 * i test, senza dipendere dalla suite esistente.
 */
abstract contract StackDeployer is Test {
    DaimonV2 internal token;
    DaimonStaking internal staking;
    DaimonGovernor internal governor;
    DaimonTimelock internal timelock;
    DaimonMigration internal migration;
    MockOldDaimon internal oldToken;
    MockUniswapV2Router02 internal router;
    MockWETH internal weth;

    address internal deployer = address(0xD1);
    address internal guardian = address(0x6A);
    address internal marketingWallet = address(0x3A);
    address internal treasury = address(0x74);

    uint256 internal constant OLD_SUPPLY = 1_000_000_000_000 ether; // >= INITIAL_SUPPLY, per finanziare gli attori

    function deployStack() internal {
        vm.startPrank(deployer);

        weth = new MockWETH();
        MockUniswapV2Factory factory = new MockUniswapV2Factory();
        router = new MockUniswapV2Router02(address(factory), address(weth));
        vm.deal(address(router), 100_000 ether);

        oldToken = new MockOldDaimon(OLD_SUPPLY, deployer);
        // Il deployer e' la sorgente dei vecchi token nei test: escluderlo
        // dalla fee del vecchio contratto rende le distribuzioni verso gli
        // attori 1:1 (senza, subirebbero la tax 5% e riceverebbero meno di
        // quanto poi tentano di migrare).
        oldToken.excludeFromFee(deployer);

        DaimonV2 impl = new DaimonV2();
        bytes memory initData = abi.encodeCall(
            DaimonV2.initialize,
            ("Daimon", "DMN", deployer, address(router), deployer, guardian, marketingWallet)
        );
        token = DaimonV2(payable(address(new ERC1967Proxy(address(impl), initData))));

        staking = new DaimonStaking(address(token), deployer);
        timelock = new DaimonTimelock(7 days, deployer, deployer, guardian, deployer);
        governor = new DaimonGovernor(address(staking), address(timelock), guardian, 1000, 1000 ether);

        timelock.grantRole(timelock.PROPOSER_ROLE(), address(governor));
        timelock.grantRole(timelock.EXECUTOR_ROLE(), address(governor));
        timelock.revokeRole(timelock.PROPOSER_ROLE(), deployer);
        timelock.revokeRole(timelock.EXECUTOR_ROLE(), deployer);

        staking.setGovernance(address(timelock), true);
        staking.setGovernance(deployer, false);

        token.setStakingContract(address(staking));

        migration = new DaimonMigration(address(oldToken), address(token), treasury, address(timelock), 3650 days);
        token.setExcludedFromFee(address(migration), true);
        token.transfer(address(migration), token.balanceOf(deployer));

        token.grantRole(token.GOVERNANCE_ROLE(), address(timelock));
        token.revokeRole(token.GOVERNANCE_ROLE(), deployer);
        timelock.renounceRole(timelock.ADMIN_ROLE(), deployer);

        // La treasury azzera la fee del vecchio token verso di se' (passaggio
        // preparatorio della migrazione).
        vm.stopPrank();
        vm.prank(treasury);
        oldToken.excludeFromFee(treasury);
    }

    /// Dota `to` di `amount` DMN nuovi tramite il canale di migrazione:
    /// gli manda vecchi token, poi esegue claim per suo conto.
    function fundWithDmn(address to, uint256 amount) internal {
        if (amount == 0) return;
        vm.prank(deployer);
        oldToken.transfer(to, amount);
        vm.startPrank(to);
        oldToken.approve(address(migration), amount);
        migration.claim(amount);
        vm.stopPrank();
    }
}
