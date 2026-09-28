// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/*
 * LiquiditySeeder -- single-use opener of the DMN/WBNB pool (launch step 5b,
 * with step 6 merged into it).
 *
 * Why it exists (mainnet-fork rehearsal, 2026-09-28, journal row F5b.P1):
 * between phase 1 (the pair is created by DaimonV2.initialize) and the
 * initial liquidity, anyone can send 1 wei of WBNB to the EMPTY pair and
 * call sync(). The router's addLiquidityETH then quotes against reserves
 * (0, 1) and reverts with PancakeLibrary: INSUFFICIENT_LIQUIDITY. Adding
 * the two legs to the pair directly and calling mint() still works, but as
 * separate transactions it leaves both legs in the pair above its reserves,
 * where anyone can take them with skim(). This contract does the direct
 * path ATOMICALLY: DMN (owner -> pair), BNB wrapped and sent, pair.mint --
 * one transaction, nothing ever parked in the pair between calls.
 *
 * And it mints the LP tokens DIRECTLY to the Timelock: no project wallet
 * ever holds them, which is what launch step 6 used to do with a separate
 * transfer.
 *
 * Deliberately outside src/: it is launch tooling, not protocol code, and
 * the audit gate `git diff audit-final -- src/` stays empty. It has no
 * admin, no withdraw, no upgrade path and no receive(): after its one call
 * it is inert forever (`used`).
 *
 * Price sanity: the opening price the owner intends is exactly the ratio of
 * what it puts in -- msg.value BNB against the DMN the pair RECEIVES (net of
 * the token's transfer fee, measured, #17). After mint the pool must sit
 * within PRICE_TOLERANCE_BPS of that ratio, or the whole call reverts: a
 * donation of WBNB (or DMN) large enough to skew the opening price is
 * refused, while the 1-wei grief above is absorbed (it moves the price by
 * 1 part in 2.26e18).
 */

interface ISeederERC20 {
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

interface ISeederWBNB is ISeederERC20 {
    function deposit() external payable;
}

interface ISeederPair is ISeederERC20 {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function totalSupply() external view returns (uint256);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function mint(address to) external returns (uint256 liquidity);
}

interface ISeederToken {
    function uniswapV2Pair() external view returns (address);
}

contract LiquiditySeeder {
    /// The opening price may differ from the intended one by at most this
    /// much (basis points), in either direction.
    uint256 public constant PRICE_TOLERANCE_BPS = 10; // 0.10 %
    /// Locked forever by the pair at the first mint (UniswapV2/PancakeSwap).
    uint256 public constant MINIMUM_LIQUIDITY = 1000;

    address public immutable owner;        // the DMX owner: the only caller
    ISeederERC20 public immutable dmn;     // DaimonV2 proxy
    ISeederPair public immutable pair;     // DMN/WBNB, the token's own uniswapV2Pair
    ISeederWBNB public immutable wbnb;
    address public immutable timelock;     // receives every LP token
    bool public immutable dmnIsToken0;

    bool public used;

    event Seeded(uint256 dmnGross, uint256 dmnNet, uint256 bnb, uint256 liquidity, uint256 reserveDmn, uint256 reserveWbnb);

    error NotOwner();
    error AlreadyUsed();
    error ZeroAmount();
    error BadConfig();
    error TransferFailed();
    error ApprovalNotExact();
    error PriceOutOfTolerance(uint256 reserveDmn, uint256 reserveWbnb, uint256 dmnNet, uint256 bnb);
    error LpNotAllInTimelock();
    error DustLeft();

    constructor(address owner_, address dmn_, address pair_, address wbnb_, address timelock_) {
        if (owner_ == address(0) || timelock_.code.length == 0 || dmn_.code.length == 0 || wbnb_.code.length == 0) revert BadConfig();
        // The pair must be the token's own pair and hold exactly DMN and WBNB.
        if (ISeederToken(dmn_).uniswapV2Pair() != pair_) revert BadConfig();
        address t0 = ISeederPair(pair_).token0();
        address t1 = ISeederPair(pair_).token1();
        if (!((t0 == dmn_ && t1 == wbnb_) || (t0 == wbnb_ && t1 == dmn_))) revert BadConfig();
        owner = owner_;
        dmn = ISeederERC20(dmn_);
        pair = ISeederPair(pair_);
        wbnb = ISeederWBNB(wbnb_);
        timelock = timelock_;
        dmnIsToken0 = (t0 == dmn_);
    }

    /// @notice Opens the pool: `dmnGross` DMN from the owner (exactly
    /// approved to this contract beforehand) and msg.value BNB, LP minted to
    /// the Timelock. Callable once, by the owner only.
    function seed(uint256 dmnGross) external payable returns (uint256 liquidity) {
        if (msg.sender != owner) revert NotOwner();
        if (used) revert AlreadyUsed();
        used = true;
        if (dmnGross == 0 || msg.value == 0) revert ZeroAmount();

        // DMN leg: owner -> pair directly (never through this contract),
        // measuring what the pair RECEIVES after the token's fee (#17).
        uint256 pairDmnBefore = dmn.balanceOf(address(pair));
        if (!dmn.transferFrom(owner, address(pair), dmnGross)) revert TransferFailed();
        uint256 dmnNet = dmn.balanceOf(address(pair)) - pairDmnBefore;
        // The approval was exact: nothing of it survives the call.
        if (dmn.allowance(owner, address(this)) != 0) revert ApprovalNotExact();

        // BNB leg: wrap everything this contract holds -- msg.value plus any
        // dust forced into it beforehand -- and send it all to the pair.
        wbnb.deposit{value: address(this).balance}();
        if (!wbnb.transfer(address(pair), wbnb.balanceOf(address(this)))) revert TransferFailed();

        liquidity = pair.mint(timelock);

        // Price sanity, cross-multiplied (no rounding): the pool's ratio
        // reserveWbnb / reserveDmn against the intended msg.value / dmnNet.
        (uint112 r0, uint112 r1, ) = pair.getReserves();
        (uint256 rDmn, uint256 rWbnb) = dmnIsToken0 ? (uint256(r0), uint256(r1)) : (uint256(r1), uint256(r0));
        uint256 actual = rWbnb * dmnNet;
        uint256 intended = msg.value * rDmn;
        uint256 diff = actual > intended ? actual - intended : intended - actual;
        if (diff * 10_000 > intended * PRICE_TOLERANCE_BPS) revert PriceOutOfTolerance(rDmn, rWbnb, dmnNet, msg.value);

        // Step 6, merged: every LP token that exists is the Timelock's,
        // except the MINIMUM_LIQUIDITY the pair locks at the first mint.
        if (pair.balanceOf(timelock) != pair.totalSupply() - MINIMUM_LIQUIDITY) revert LpNotAllInTimelock();

        // Nothing stays behind: no BNB, WBNB, DMN or LP in this contract.
        if (
            address(this).balance != 0 || wbnb.balanceOf(address(this)) != 0 || dmn.balanceOf(address(this)) != 0
                || pair.balanceOf(address(this)) != 0
        ) revert DustLeft();

        emit Seeded(dmnGross, dmnNet, msg.value, liquidity, rDmn, rWbnb);
    }
}
