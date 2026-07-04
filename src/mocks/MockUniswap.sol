// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/*
 * Mock di Uniswap V2 Router/Factory per i test.
 * Simula in modo semplificato (non un vero AMM con curva x*y=k) lo
 * scambio token<->ETH a un rate fisso configurabile, abbastanza per
 * verificare la logica di fee/buyback/burn del token. Per test di
 * integrazione completi su mainnet-fork, sostituire con il vero
 * Uniswap V2 (UniswapV2Router02 + UniswapV2Factory + UniswapV2Pair reali).
 */

interface IERC20Mock {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

contract MockWETH {
    string public name = "Wrapped Ether Mock";
    string public symbol = "WETH";
    uint8 public decimals = 18;
}

contract MockUniswapV2Factory {
    mapping(address => mapping(address => address)) public getPair;

    function createPair(address tokenA, address tokenB) external returns (address pair) {
        pair = address(uint160(uint256(keccak256(abi.encodePacked(tokenA, tokenB, block.timestamp)))));
        getPair[tokenA][tokenB] = pair;
        getPair[tokenB][tokenA] = pair;
    }
}

contract MockUniswapV2Router02 {
    address public immutable factory;
    address public immutable WETH;

    // rate: quanti wei di ETH per 1 token (scalato 1e18), configurabile per i test
    uint256 public ethPerTokenRate = 1e15; // default: 1000 token = 1 ETH

    constructor(address _factory, address _weth) {
        factory = _factory;
        WETH = _weth;
    }

    function setRate(uint256 _rate) external {
        ethPerTokenRate = _rate;
    }

    // Quote al rate corrente, coerente con i due swap qui sotto. Permette
    // al token di derivare amountOutMin come farebbe col router reale.
    function getAmountsOut(uint amountIn, address[] calldata path) external view returns (uint[] memory amounts) {
        amounts = new uint[](path.length);
        amounts[0] = amountIn;
        if (path[0] == WETH) {
            amounts[1] = (amountIn * 1e18) / ethPerTokenRate; // ETH -> token
        } else {
            amounts[1] = (amountIn * ethPerTokenRate) / 1e18; // token -> ETH
        }
    }

    // Simula: prende tokenAmount di token dal caller, manda ETH equivalente a `to`.
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint /*deadline*/
    ) external {
        address token = path[0];
        bool ok = IERC20Mock(token).transferFrom(msg.sender, address(this), amountIn);
        require(ok, "MockRouter: transferFrom failed");

        uint256 ethOut = (amountIn * ethPerTokenRate) / 1e18;
        require(ethOut >= amountOutMin, "MockRouter: INSUFFICIENT_OUTPUT_AMOUNT");
        require(address(this).balance >= ethOut, "MockRouter: insufficient ETH liquidity");
        (bool sent, ) = to.call{value: ethOut}("");
        require(sent, "MockRouter: ETH send failed");
    }

    // Simula: prende ETH dal caller (msg.value), manda token equivalente a `to`.
    // Come il router reale (variante SupportingFeeOnTransfer), amountOutMin
    // e' verificato sul RICEVUTO effettivo dal destinatario, dopo la
    // eventuale transfer fee del token.
    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint /*deadline*/
    ) external payable {
        address token = path[1];
        uint256 tokenOut = (msg.value * 1e18) / ethPerTokenRate;
        uint256 balBefore = IERC20Mock(token).balanceOf(to);
        bool ok = IERC20Mock(token).transfer(to, tokenOut);
        require(ok, "MockRouter: token send failed (fund the router with tokens first)");
        uint256 received = IERC20Mock(token).balanceOf(to) - balBefore;
        require(received >= amountOutMin, "MockRouter: INSUFFICIENT_OUTPUT_AMOUNT");
    }

    receive() external payable {}
}
