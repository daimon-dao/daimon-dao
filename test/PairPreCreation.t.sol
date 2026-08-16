// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {DaimonV2} from "../src/DaimonV2.sol";
import {MockUniswapV2Factory, MockUniswapV2Router02, MockWETH} from "../src/mocks/MockUniswap.sol";

/*
 * Finding #25.
 *
 * The proxy is deployed with CREATE, so its address is predictable from the
 * deployer and nonce. The canonical factory reverts on createPair() when the
 * pair already exists, so an observer could pre-create the DMN/WBNB pair for
 * the predicted address and make initialize() — and with it the whole proxy
 * deployment — revert. The fix asks the factory for an existing pair first
 * and reuses it: a pre-created canonical pair is the same trusted factory
 * artifact createPair() would have produced.
 */
contract PairPreCreationTest is Test {
    address internal deployer = address(0xD1);
    address internal guardian = address(0x6A);
    address internal marketingWallet = address(0x3A);

    MockWETH internal weth;
    MockUniswapV2Factory internal factory;
    MockUniswapV2Router02 internal router;

    function setUp() public {
        weth = new MockWETH();
        factory = new MockUniswapV2Factory();
        router = new MockUniswapV2Router02(address(factory), address(weth));
    }

    /// Deploys implementation + proxy exactly like the deploy script: the
    /// implementation first, the initializing proxy right after.
    function _deployToken() internal returns (DaimonV2) {
        DaimonV2 impl = new DaimonV2();
        bytes memory initData = abi.encodeCall(
            DaimonV2.initialize,
            ("Daimon", "DMN", deployer, address(router), deployer, guardian, marketingWallet)
        );
        return DaimonV2(payable(address(new ERC1967Proxy(address(impl), initData))));
    }

    function test_PreCreatedPairDoesNotBlockInitialize() public {
        // The attacker's move: predict the proxy address and create its pair
        // first. _deployToken() deploys the implementation and then the
        // proxy, so the proxy lands on this contract's nonce + 1.
        address predicted = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 1);
        address preCreated = factory.createPair(predicted, address(weth));

        DaimonV2 token = _deployToken();

        assertEq(address(token), predicted, "prediction drifted: fix the nonce offset in this test");
        assertEq(token.uniswapV2Pair(), preCreated, "existing canonical pair was not reused");
    }

    function test_FreshDeployStillCreatesThePair() public {
        DaimonV2 token = _deployToken();

        address pair = token.uniswapV2Pair();
        assertTrue(pair != address(0), "no pair was created");
        assertEq(factory.getPair(address(token), address(weth)), pair, "pair not registered in the factory");
    }

    /// Guards the mock's fidelity: without the PAIR_EXISTS revert the
    /// pre-creation test above would pass even against unfixed code.
    function test_MockFactoryMirrorsCanonicalPairExistsRevert() public {
        factory.createPair(address(0x1), address(0x2));
        vm.expectRevert(bytes("Pancake: PAIR_EXISTS"));
        factory.createPair(address(0x1), address(0x2));
    }
}
