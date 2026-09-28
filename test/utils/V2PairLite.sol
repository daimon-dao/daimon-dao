// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/*
 * Test-only AMM pieces with the UniswapV2/PancakeSwap semantics the
 * LiquiditySeeder depends on -- unlike src/mocks/MockUniswap.sol, whose
 * factory hands out a codeless pair address.
 *
 *  - PairLite: mint (sqrt(a0*a1) - MINIMUM_LIQUIDITY at the first mint,
 *    MINIMUM_LIQUIDITY locked to address(0); amounts = balance - reserve),
 *    sync, skim, getReserves, an ERC20 LP token. Ported from
 *    UniswapV2Pair.sol (no swap, burn or protocol fee: the seeder never
 *    reaches them, and the first mint takes no protocol fee on the real
 *    pair either since kLast is zero).
 *  - FactoryLite: createPair deploys a PairLite; reverts on an existing pair
 *    like the canonical factory.
 *  - WBNBLite: deposit / withdraw / ERC20.
 */

interface IBalanceOf {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
}

contract WBNBLite {
    string public name = "Wrapped BNB (test)";
    string public symbol = "WBNB";
    uint8 public decimals = 18;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function deposit() external payable {
        balanceOf[msg.sender] += msg.value;
    }

    function withdraw(uint256 amount) external {
        balanceOf[msg.sender] -= amount;
        (bool ok, ) = msg.sender.call{value: amount}("");
        require(ok, "WBNB: send failed");
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        if (allowance[from][msg.sender] != type(uint256).max) allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

contract PairLite {
    uint256 public constant MINIMUM_LIQUIDITY = 1000;
    address public factory;
    address public token0;
    address public token1;
    uint112 private reserve0;
    uint112 private reserve1;
    uint32 private blockTimestampLast;

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Sync(uint112 reserve0, uint112 reserve1);

    constructor() {
        factory = msg.sender;
    }

    function initialize(address _token0, address _token1) external {
        require(msg.sender == factory, "Pair: FORBIDDEN");
        token0 = _token0;
        token1 = _token1;
    }

    function getReserves() public view returns (uint112, uint112, uint32) {
        return (reserve0, reserve1, blockTimestampLast);
    }

    function transfer(address to, uint256 value) external returns (bool) {
        balanceOf[msg.sender] -= value;
        balanceOf[to] += value;
        emit Transfer(msg.sender, to, value);
        return true;
    }

    function allowance(address, address) external pure returns (uint256) {
        return 0;
    }

    function transferFrom(address, address, uint256) external pure returns (bool) {
        revert("Pair: not needed");
    }

    function _mint(address to, uint256 value) private {
        totalSupply += value;
        balanceOf[to] += value;
        emit Transfer(address(0), to, value);
    }

    function _update(uint256 balance0, uint256 balance1) private {
        require(balance0 <= type(uint112).max && balance1 <= type(uint112).max, "Pair: OVERFLOW");
        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);
        blockTimestampLast = uint32(block.timestamp);
        emit Sync(reserve0, reserve1);
    }

    function mint(address to) external returns (uint256 liquidity) {
        (uint112 _reserve0, uint112 _reserve1, ) = getReserves();
        uint256 balance0 = IBalanceOf(token0).balanceOf(address(this));
        uint256 balance1 = IBalanceOf(token1).balanceOf(address(this));
        uint256 amount0 = balance0 - _reserve0;
        uint256 amount1 = balance1 - _reserve1;
        if (totalSupply == 0) {
            liquidity = _sqrt(amount0 * amount1) - MINIMUM_LIQUIDITY;
            _mint(address(0), MINIMUM_LIQUIDITY);
        } else {
            uint256 l0 = (amount0 * totalSupply) / _reserve0;
            uint256 l1 = (amount1 * totalSupply) / _reserve1;
            liquidity = l0 < l1 ? l0 : l1;
        }
        require(liquidity > 0, "Pancake: INSUFFICIENT_LIQUIDITY_MINTED");
        _mint(to, liquidity);
        _update(balance0, balance1);
    }

    function skim(address to) external {
        IBalanceOf(token0).transfer(to, IBalanceOf(token0).balanceOf(address(this)) - reserve0);
        IBalanceOf(token1).transfer(to, IBalanceOf(token1).balanceOf(address(this)) - reserve1);
    }

    function sync() external {
        _update(IBalanceOf(token0).balanceOf(address(this)), IBalanceOf(token1).balanceOf(address(this)));
    }

    function _sqrt(uint256 y) private pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }
}

contract FactoryLite {
    mapping(address => mapping(address => address)) public getPair;

    function createPair(address tokenA, address tokenB) external returns (address pair) {
        require(getPair[tokenA][tokenB] == address(0), "Pancake: PAIR_EXISTS");
        (address t0, address t1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        PairLite p = new PairLite();
        p.initialize(t0, t1);
        pair = address(p);
        getPair[tokenA][tokenB] = pair;
        getPair[tokenB][tokenA] = pair;
    }
}
