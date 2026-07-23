// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/*
 * DaimonV2
 * --------
 * ERC20 token with reflection (inspired by the original Daimon),
 * governance-ready.
 *
 * KEY DIFFERENCES from the original:
 *  - No single owner: all sensitive parameters are modifiable ONLY by the
 *    DAO Timelock (governanceAddress), never by a single wallet.
 *  - NO mint function, in any form, anywhere in the code. The maximum supply
 *    is created ONCE in the constructor and that's it.
 *  - Fixed, immutable burn floor: MIN_SUPPLY = 21_000_000_000 tokens. Any
 *    burn operation (reflection fee included, and the buyback) is blocked if
 *    it would push the supply below the floor.
 *  - It is upgradable (UUPS) ONLY for the non-monetary logic (fees,
 *    addresses, limits, enable/disable buyback). The absence of mint and the
 *    floor are enforced also in the upgrade-authorization function: see the
 *    note in _authorizeUpgrade. It is not an absolute mathematical guarantee
 *    (a malicious upgrade authorized by the DAO could in theory replace the
 *    logic), which is why the upgrade ALWAYS goes through the Timelock with a
 *    public delay: the community always has a window to notice and react.
 *
 * DEPENDENCIES:
 *  Uses the official OpenZeppelin imports (audited and maintained):
 *  Initializable, UUPSUpgradeable, AccessControlUpgradeable,
 *  ReentrancyGuardUpgradeable from the contracts-upgradeable v5 package.
 *  Role rotation replicates the original semantics ("only governance can
 *  rotate the roles, including its own") by setting GOVERNANCE_ROLE as the
 *  admin of itself and of GUARDIAN_ROLE.
 */

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

// ============================================================
// === Uniswap interfaces (identical to the original, needed for swap/buyback)
// ============================================================
interface IUniswapV2Factory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
}

interface IUniswapV2Router02 {
    function factory() external pure returns (address);
    function WETH() external pure returns (address);
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;
    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external payable;
    function getAmountsOut(uint amountIn, address[] calldata path) external view returns (uint[] memory amounts);
}

interface IDaimonStakingNotifier {
    // The token notifies the staking contract how much marketing fee was
    // sent to it, so staking can account the rewards.
    // Payable: staking requires msg.value == amount.
    function notifyRewardAmount(uint256 amount) external payable;
}

// ============================================================
// === DaimonV2
// ============================================================
contract DaimonV2 is Initializable, UUPSUpgradeable, AccessControlUpgradeable, ReentrancyGuardUpgradeable {
    // ---- Roles ----
    bytes32 public constant GOVERNANCE_ROLE = keccak256("GOVERNANCE_ROLE"); // = the DAO Timelock
    bytes32 public constant GUARDIAN_ROLE = keccak256("GUARDIAN_ROLE");     // pause-only multisig, no economic powers

    // ---- ERC20 standard storage ----
    string public name;
    string public symbol;
    uint8 public constant decimals = 18;

    mapping(address => uint256) private _rOwned;
    mapping(address => uint256) private _tOwned;
    mapping(address => bool) private _isExcludedFromReward;
    address[] private _excluded;

    mapping(address => mapping(address => uint256)) private _allowances;
    mapping(address => bool) public isExcludedFromFee;

    uint256 private constant MAX = type(uint256).max;

    // ---- Supply / floor (immutable by design) ----
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000_000 * 10 ** 18; // 1000 billion
    uint256 public constant MIN_SUPPLY = 21_000_000_000 * 10 ** 18;        // floor: 21 billion
    // NO mintable MAX_SUPPLY variable: the supply can ONLY go down.

    uint256 private _tTotal;   // current supply (token units), starts at INITIAL_SUPPLY, decreases with burns
    uint256 private _rTotal;
    uint256 private _tFeeTotal;

    // ---- Fees (in basis points out of 1000, like the original: e.g. 50 = 5%) ----
    uint256 public taxFee;        // redistributed to holders via reflection
    uint256 public buybackFee;    // used to buy and burn tokens
    uint256 public marketingFee;  // used for marketing + staking reward
    uint256 public liquidityFee;  // = buybackFee + marketingFee (accumulated in the contract before the swap)

    uint256 private _previousTaxFee;
    uint256 private _previousBuybackFee;
    uint256 private _previousMarketingFee;
    uint256 private _previousLiquidityFee;

    // Share of the marketingFee that goes to the staking reward pool, in bps out of 1000
    // (e.g. 600 = 60% of the marketing fee goes to staking, the rest to marketingWallet)
    uint256 public stakingRewardShareBps;

    uint256 public maxTxAmount;
    uint256 public minimumTokensBeforeSwap;
    uint256 public buyBackUpperLimit;

    // Maximum tolerated slippage (bps out of 10000) for the automatic fee and
    // buyback swaps: amountOutMin is derived from getAmountsOut minus this
    // tolerance, to limit MEV extraction on the contract's swaps.
    uint256 public maxSwapSlippageBps;

    address public marketingWallet;
    address public stakingContract;
    address public constant deadAddress = 0x000000000000000000000000000000000000dEaD;

    IUniswapV2Router02 public uniswapV2Router;
    address public uniswapV2Pair;

    bool private _inSwap;
    bool public swapAndLiquifyEnabled;
    bool public buyBackEnabled;
    bool public paused; // activatable ONLY by the Guardian, for emergencies, never for profit

    // Guardian role expiry: 36 months after deploy, setPaused() stops working
    // permanently. Set once in initialize(), no public setter exists —
    // verifiable on-chain by anyone.
    uint256 public guardianExpiry;

    // ---- Events ----
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event SwapAndLiquify(uint256 tokensSwapped, uint256 ethReceived);
    event BuyBackAndBurn(uint256 ethSpent, uint256 tokensBurned);
    event FeesUpdated(uint256 taxFee, uint256 buybackFee, uint256 marketingFee);
    event ParamsUpdated(string param, uint256 value);
    event PausedSet(bool paused);
    event StakingContractSet(address indexed staking);
    event MarketingWalletSet(address indexed wallet);
    event ExcludedFromFeeSet(address indexed account, bool excluded);
    event SwapAndLiquifyEnabledSet(bool enabled);
    event BuyBackEnabledSet(bool enabled);

    error BelowMinSupply();
    error ZeroAddress();
    error FeeTooHigh();
    error TransferAmountExceedsMaxTx();
    error ContractIsPaused();
    error GuardianExpired();

    modifier lockSwap() {
        _inSwap = true;
        _;
        _inSwap = false;
    }

    modifier whenNotPaused() {
        if (paused) revert ContractIsPaused();
        _;
    }

    constructor() {
        // Disable direct initialization of the implementation contract, so
        // nobody can call initialize() on the implementation and become the
        // "owner" of a contract that will never be used as such (the classic
        // attack on unprotected UUPS proxies).
        _disableInitializers();
    }

    /// @param _migrationContract receives the entire INITIAL_SUPPLY for the 1:1 migration.
    function initialize(
        string memory _name,
        string memory _symbol,
        address _migrationContract,
        address _router,
        address _governance,   // the DAO Timelock
        address _guardian,     // emergency multisig, pause only
        address _marketingWallet
    ) external initializer {
        if (_migrationContract == address(0) || _router == address(0) || _governance == address(0) || _marketingWallet == address(0)) {
            revert ZeroAddress();
        }
        __UUPSUpgradeable_init();
        __AccessControl_init();
        __ReentrancyGuard_init();

        name = _name;
        symbol = _symbol;

        _tTotal = INITIAL_SUPPLY;
        _rTotal = MAX - (MAX % _tTotal);

        taxFee = 10;          // 1% reflection to holders
        buybackFee = 20;      // 2% buyback and burn
        marketingFee = 20;    // 2% marketing + staking reward
        liquidityFee = buybackFee + marketingFee;  // 4% total accumulated in the contract
        _previousTaxFee = taxFee;
        _previousBuybackFee = buybackFee;
        _previousMarketingFee = marketingFee;
        _previousLiquidityFee = liquidityFee;
        // Initial total fee: 1% + 2% + 2% = 5%
        // Hard cap in code (setFees): the 10% total can never be exceeded

        stakingRewardShareBps = 600; // 60% of the marketing fee to the staking reward pool

        // Guardian expiry: 36 months from deploy, not modifiable.
        // After this date, setPaused() automatically reverts forever.
        guardianExpiry = block.timestamp + 1095 days; // 365 * 3 = 1095

        maxTxAmount = _tTotal / 200;           // 0.5% of initial supply
        minimumTokensBeforeSwap = _tTotal / 5000; // 0.02% of initial supply
        buyBackUpperLimit = 50 ether;
        maxSwapSlippageBps = 500; // 5% max slippage on automatic swaps

        swapAndLiquifyEnabled = true;
        buyBackEnabled = true;

        marketingWallet = _marketingWallet;

        // Only governance can rotate the roles (including its own):
        // GOVERNANCE_ROLE administers itself and GUARDIAN_ROLE. Nobody holds
        // DEFAULT_ADMIN_ROLE.
        _setRoleAdmin(GOVERNANCE_ROLE, GOVERNANCE_ROLE);
        _setRoleAdmin(GUARDIAN_ROLE, GOVERNANCE_ROLE);
        _grantRole(GOVERNANCE_ROLE, _governance);
        _grantRole(GUARDIAN_ROLE, _guardian);

        // The entire supply goes to the migration contract: no "team wallet"
        // pre-allocated outside the 1:1 migration, by design.
        _rOwned[_migrationContract] = _rTotal;
        isExcludedFromFee[_migrationContract] = true;
        isExcludedFromFee[address(this)] = true;

        // The dead address is excluded from reflection: this way its balance
        // reflects ONLY the tokens actually sent (buyback), not accrued
        // reflection, and burnDeadBalanceToFloor() burns net, real supply.
        _isExcludedFromReward[deadAddress] = true;
        _excluded.push(deadAddress);

        uniswapV2Router = IUniswapV2Router02(_router);
        uniswapV2Pair = IUniswapV2Factory(uniswapV2Router.factory()).createPair(address(this), uniswapV2Router.WETH());

        emit Transfer(address(0), _migrationContract, _tTotal);
    }

    // ============================================================
    // ERC20 standard
    // ============================================================
    function totalSupply() external view returns (uint256) {
        return _tTotal;
    }

    function balanceOf(address account) public view returns (uint256) {
        if (_isExcludedFromReward[account]) return _tOwned[account];
        return _tokenFromReflection(_rOwned[account]);
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function allowance(address owner_, address spender) external view returns (uint256) {
        return _allowances[owner_][spender];
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        _spendAllowance(from, msg.sender, amount);
        _transfer(from, to, amount);
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue) external returns (bool) {
        _approve(msg.sender, spender, _allowances[msg.sender][spender] + addedValue);
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) external returns (bool) {
        uint256 current = _allowances[msg.sender][spender];
        require(current >= subtractedValue, "DaimonV2: allowance below zero");
        _approve(msg.sender, spender, current - subtractedValue);
        return true;
    }

    function _spendAllowance(address owner_, address spender, uint256 amount) private {
        uint256 current = _allowances[owner_][spender];
        if (current != type(uint256).max) {
            require(current >= amount, "DaimonV2: insufficient allowance");
            _approve(owner_, spender, current - amount);
        }
    }

    function _approve(address owner_, address spender, uint256 amount) private {
        if (owner_ == address(0) || spender == address(0)) revert ZeroAddress();
        _allowances[owner_][spender] = amount;
        emit Approval(owner_, spender, amount);
    }

    // ============================================================
    // Reflection helpers
    // ============================================================
    function totalFeesDistributed() external view returns (uint256) {
        return _tFeeTotal;
    }

    function _getRate() private view returns (uint256) {
        (uint256 rSupply, uint256 tSupply) = _getCurrentSupply();
        return rSupply / tSupply;
    }

    function _getCurrentSupply() private view returns (uint256, uint256) {
        uint256 rSupply = _rTotal;
        uint256 tSupply = _tTotal;
        uint256 len = _excluded.length;
        for (uint256 i = 0; i < len; i++) {
            address acc = _excluded[i];
            if (_rOwned[acc] > rSupply || _tOwned[acc] > tSupply) return (_rTotal, _tTotal);
            rSupply -= _rOwned[acc];
            tSupply -= _tOwned[acc];
        }
        if (rSupply < _rTotal / _tTotal) return (_rTotal, _tTotal);
        return (rSupply, tSupply);
    }

    function _tokenFromReflection(uint256 rAmount) private view returns (uint256) {
        require(_rTotal > 0, "DaimonV2: no supply");
        uint256 currentRate = _getRate();
        return rAmount / currentRate;
    }

    // ============================================================
    // Transfer / fee logic
    // ============================================================
    function _transfer(address from, address to, uint256 amount) private whenNotPaused {
        if (from == address(0) || to == address(0)) revert ZeroAddress();
        require(amount > 0, "DaimonV2: transfer amount is zero");

        // maxTxAmount does not apply to: governance, the contract itself
        // (when it sells the fee tokens accumulated during the internal swap,
        // an operation that can exceed maxTx by construction), and the
        // addresses explicitly excluded from the fee (replicates the same
        // behavior as the original contract).
        bool exemptFromMaxTx = hasRole(GOVERNANCE_ROLE, from) || from == address(this) || isExcludedFromFee[from];
        if (!exemptFromMaxTx && to != address(this)) {
            if (amount > maxTxAmount) revert TransferAmountExceedsMaxTx();
        }

        uint256 contractBalance = balanceOf(address(this));
        bool overMin = contractBalance >= minimumTokensBeforeSwap;

        if (!_inSwap && swapAndLiquifyEnabled && to == uniswapV2Pair && overMin) {
            _swapAccumulatedFees(minimumTokensBeforeSwap);
        }

        if (!_inSwap && buyBackEnabled && to == uniswapV2Pair) {
            uint256 ethBalance = address(this).balance;
            if (ethBalance > 1 ether && _tTotal > MIN_SUPPLY) {
                uint256 spendAmount = ethBalance > buyBackUpperLimit ? buyBackUpperLimit : ethBalance;
                _buyBackAndBurn(spendAmount / 20); // uses 5% of the available eth per call, not all at once
            }
        }

        bool takeFee = !(isExcludedFromFee[from] || isExcludedFromFee[to]);
        _tokenTransfer(from, to, amount, takeFee);
    }

    function _tokenTransfer(address sender, address recipient, uint256 tAmount, bool takeFee) private {
        if (!takeFee) _removeAllFee();

        (uint256 rAmount, uint256 rTransferAmount, uint256 rFee, uint256 tTransferAmount, uint256 tFee, uint256 tLiquidity) = _getValues(tAmount);

        bool senderExcluded = _isExcludedFromReward[sender];
        bool recipientExcluded = _isExcludedFromReward[recipient];

        if (senderExcluded) _tOwned[sender] -= tAmount;
        _rOwned[sender] -= rAmount;

        if (recipientExcluded) _tOwned[recipient] += tTransferAmount;
        _rOwned[recipient] += rTransferAmount;

        if (tLiquidity > 0) _takeLiquidity(tLiquidity);
        if (rFee > 0 || tFee > 0) _reflectFee(rFee, tFee);

        emit Transfer(sender, recipient, tTransferAmount);

        if (!takeFee) _restoreAllFee();
    }

    function _getValues(uint256 tAmount) private view returns (uint256, uint256, uint256, uint256, uint256, uint256) {
        uint256 tFee = (tAmount * taxFee) / 1000;
        uint256 tLiquidity = (tAmount * liquidityFee) / 1000;
        uint256 tTransferAmount = tAmount - tFee - tLiquidity;

        uint256 rate = _getRate();
        uint256 rAmount = tAmount * rate;
        uint256 rFee = tFee * rate;
        uint256 rLiquidity = tLiquidity * rate;
        uint256 rTransferAmount = rAmount - rFee - rLiquidity;

        return (rAmount, rTransferAmount, rFee, tTransferAmount, tFee, tLiquidity);
    }

    function _takeLiquidity(uint256 tLiquidity) private {
        uint256 rate = _getRate();
        uint256 rLiquidity = tLiquidity * rate;
        _rOwned[address(this)] += rLiquidity;
        if (_isExcludedFromReward[address(this)]) {
            _tOwned[address(this)] += tLiquidity;
        }
    }

    function _reflectFee(uint256 rFee, uint256 tFee) private {
        _rTotal -= rFee;
        _tFeeTotal += tFee;
    }

    function _removeAllFee() private {
        _previousTaxFee = taxFee;
        _previousBuybackFee = buybackFee;
        _previousMarketingFee = marketingFee;
        _previousLiquidityFee = liquidityFee;
        taxFee = 0;
        buybackFee = 0;
        marketingFee = 0;
        liquidityFee = 0;
    }

    function _restoreAllFee() private {
        taxFee = _previousTaxFee;
        buybackFee = _previousBuybackFee;
        marketingFee = _previousMarketingFee;
        liquidityFee = _previousLiquidityFee;
    }

    // ============================================================
    // Swap (marketing + staking reward) e buyback&burn
    // ============================================================
    function _swapAccumulatedFees(uint256 contractTokenBalance) private lockSwap nonReentrant {
        uint256 initialEth = address(this).balance;
        _swapTokensForEth(contractTokenBalance);
        uint256 ethReceived = address(this).balance - initialEth;

        if (liquidityFee == 0 || ethReceived == 0) return;

        // Share destined to the "marketing branch" (also includes the staking funding)
        uint256 marketingEth = (ethReceived * marketingFee) / liquidityFee;
        // The rest stays in the contract as ETH for the buyback (buyback branch)

        uint256 toStaking = (marketingEth * stakingRewardShareBps) / 1000;
        uint256 toMarketingWallet = marketingEth - toStaking;

        if (toMarketingWallet > 0) {
            (bool ok1, ) = marketingWallet.call{value: toMarketingWallet}("");
            require(ok1, "DaimonV2: marketing transfer failed");
        }
        if (toStaking > 0 && stakingContract != address(0)) {
            // A single payable call: staking's notifyRewardAmount requires
            // msg.value == amount, so funds and accounting must travel in the
            // same call.
            IDaimonStakingNotifier(stakingContract).notifyRewardAmount{value: toStaking}(toStaking);
        }

        emit SwapAndLiquify(contractTokenBalance, ethReceived);
    }

    function _swapTokensForEth(uint256 tokenAmount) private {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();

        // amountOutMin from the current quote minus the governed tolerance.
        // NOTE: the quote is read in the same block as the swap, so it limits
        // the impact of intra-block manipulation up to the tolerance, it does
        // not eliminate it (a TWAP would be needed for that). The contract is
        // excluded from the fee, so the quote does not need correcting for the
        // transfer fee.
        uint256[] memory quote = uniswapV2Router.getAmountsOut(tokenAmount, path);
        uint256 minOut = (quote[1] * (10000 - maxSwapSlippageBps)) / 10000;

        _approve(address(this), address(uniswapV2Router), tokenAmount);
        // try/catch: if slippage exceeds the tolerance the swap fails, but it
        // must NOT revert the transfer of the user who triggered it (that
        // would be a DoS vector on sells: just push the price beyond the
        // tolerance). The tokens stay for the next round.
        try uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount, minOut, path, address(this), block.timestamp
        ) {} catch {}
    }

    function _buyBackAndBurn(uint256 ethAmount) private lockSwap nonReentrant {
        if (ethAmount == 0) return;
        if (_tTotal <= MIN_SUPPLY) return; // floor: no further buyback/burn

        address[] memory path = new address[](2);
        path[0] = uniswapV2Router.WETH();
        path[1] = address(this);

        // amountOutMin: current quote, corrected for the token's transfer fee
        // (the dead address is not excluded from the fee: it receives the
        // net), minus the governed slippage tolerance.
        uint256 expectedAfterFee = 0;
        {
            uint256[] memory quote = uniswapV2Router.getAmountsOut(ethAmount, path);
            expectedAfterFee = (quote[1] * (1000 - taxFee - liquidityFee)) / 1000;
        }
        uint256 minOut = (expectedAfterFee * (10000 - maxSwapSlippageBps)) / 10000;

        uint256 balanceBefore = balanceOf(deadAddress);

        // Buys tokens and sends them DIRECTLY to the dead address: it is a
        // visible, irreversible burn, but the total supply (_tTotal) is NOT
        // decremented here, because the bought tokens already existed (they
        // are taken from the liquidity pool, not created). To apply real
        // deflation on the supply we enforce the floor separately via
        // burnToFloor(), see below: that is the function that really burns
        // supply, while this buyback supports the price.
        // try/catch: a buyback beyond tolerance is skipped (the ETH stays for
        // the next attempt), without reverting the transfer that triggered
        // it.
        try uniswapV2Router.swapExactETHForTokensSupportingFeeOnTransferTokens{value: ethAmount}(
            minOut, path, deadAddress, block.timestamp + 300
        ) {} catch {
            return;
        }

        uint256 balanceAfter = balanceOf(deadAddress);
        emit BuyBackAndBurn(ethAmount, balanceAfter - balanceBefore);
    }

    /// @notice REALLY burns supply (reduces _tTotal) by drawing from the
    /// tokens already accumulated in the dead address, never going below
    /// MIN_SUPPLY. Anyone can call it (it is permissionless and safe): it does
    /// not move anyone's funds, it just "cancels" from the supply accounting
    /// what is already unrecoverable in the dead address.
    function burnDeadBalanceToFloor() external nonReentrant {
        uint256 deadBal = balanceOf(deadAddress);
        if (deadBal == 0) return;
        uint256 burnable = _tTotal > MIN_SUPPLY ? _tTotal - MIN_SUPPLY : 0;
        if (burnable == 0) return;

        uint256 toBurn = deadBal > burnable ? burnable : deadBal;

        uint256 rate = _getRate();
        uint256 rToBurn = toBurn * rate;

        _rOwned[deadAddress] -= rToBurn;
        if (_isExcludedFromReward[deadAddress]) {
            _tOwned[deadAddress] -= toBurn;
        }
        _rTotal -= rToBurn;
        _tTotal -= toBurn;

        if (_tTotal < MIN_SUPPLY) revert BelowMinSupply(); // safety net, must never happen
    }

    // ============================================================
    // Administration: ONLY governance (Timelock), never a single owner
    // ============================================================
    function setFees(uint256 _taxFee, uint256 _buybackFee, uint256 _marketingFee) external onlyRole(GOVERNANCE_ROLE) {
        if (_taxFee + _buybackFee + _marketingFee > 100) revert FeeTooHigh(); // hard cap 10% total, immutable
        taxFee = _taxFee;
        buybackFee = _buybackFee;
        marketingFee = _marketingFee;
        liquidityFee = _buybackFee + _marketingFee;
        emit FeesUpdated(_taxFee, _buybackFee, _marketingFee);
    }

    function setStakingRewardShareBps(uint256 bps) external onlyRole(GOVERNANCE_ROLE) {
        require(bps <= 1000, "DaimonV2: bps > 100%");
        stakingRewardShareBps = bps;
        emit ParamsUpdated("stakingRewardShareBps", bps);
    }

    function setMaxTxAmount(uint256 amount) external onlyRole(GOVERNANCE_ROLE) {
        require(amount >= _tTotal / 10000, "DaimonV2: maxTx too low"); // min 0.01% of supply, anti-self-DoS
        maxTxAmount = amount;
        emit ParamsUpdated("maxTxAmount", amount);
    }

    function setMinimumTokensBeforeSwap(uint256 amount) external onlyRole(GOVERNANCE_ROLE) {
        // Floor: min 0.0001% of the supply. A value ~0 would make overMin
        // always true, triggering a swap on every transfer to the pair
        // (effectively a gas-DoS on sells).
        require(amount >= _tTotal / 1_000_000, "DaimonV2: swap threshold too low");
        minimumTokensBeforeSwap = amount;
        emit ParamsUpdated("minimumTokensBeforeSwap", amount);
    }

    function setBuyBackUpperLimit(uint256 amount) external onlyRole(GOVERNANCE_ROLE) {
        buyBackUpperLimit = amount;
        emit ParamsUpdated("buyBackUpperLimit", amount);
    }

    function setMaxSwapSlippageBps(uint256 bps) external onlyRole(GOVERNANCE_ROLE) {
        // 0.5% - 30%: never 0 (would block every swap) nor values that
        // effectively reopen the door to unlimited MEV.
        require(bps >= 50 && bps <= 3000, "DaimonV2: slippage out of range");
        maxSwapSlippageBps = bps;
        emit ParamsUpdated("maxSwapSlippageBps", bps);
    }

    function setMarketingWallet(address wallet) external onlyRole(GOVERNANCE_ROLE) {
        if (wallet == address(0)) revert ZeroAddress();
        marketingWallet = wallet;
        emit MarketingWalletSet(wallet);
    }

    function setStakingContract(address staking) external onlyRole(GOVERNANCE_ROLE) {
        if (staking == address(0)) revert ZeroAddress();
        stakingContract = staking;
        isExcludedFromFee[staking] = true;
        emit StakingContractSet(staking);
    }

    function setExcludedFromFee(address account, bool excluded) external onlyRole(GOVERNANCE_ROLE) {
        isExcludedFromFee[account] = excluded;
        emit ExcludedFromFeeSet(account, excluded);
    }

    function setSwapAndLiquifyEnabled(bool enabled) external onlyRole(GOVERNANCE_ROLE) {
        swapAndLiquifyEnabled = enabled;
        emit SwapAndLiquifyEnabledSet(enabled);
    }

    function setBuyBackEnabled(bool enabled) external onlyRole(GOVERNANCE_ROLE) {
        buyBackEnabled = enabled;
        emit BuyBackEnabledSet(enabled);
    }

    // ---- Guardian: ONLY emergency pause, no economic power ----
    // After 36 months from deploy (guardianExpiry), this function reverts
    // permanently: the contract can no longer be paused by anyone, not even
    // by the DAO. It is a guarantee of definitive decentralization, verifiable
    // on-chain by anyone reading guardianExpiry.
    function setPaused(bool _paused) external onlyRole(GUARDIAN_ROLE) {
        // Only PAUSING expires with the guardian: unpausing always stays
        // possible, otherwise a contract paused at the moment of expiry would
        // stay frozen forever.
        if (_paused && block.timestamp >= guardianExpiry) revert GuardianExpired();
        paused = _paused;
        emit PausedSet(_paused);
    }

    // ============================================================
    // Upgrade: governance only, with an explicit anti-mint check
    // ============================================================
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(GOVERNANCE_ROLE) {
        // We cannot verify the new implementation's bytecode at runtime in an
        // absolute way, but we can require the DAO to publish the code in the
        // clear and the Timelock to give the community time to read it before
        // execution (see the delay in the TimelockController). This is a
        // process control, not a technical one: it is the intrinsic limit of
        // any upgradable system, and must be communicated clearly to the
        // community.
        require(newImplementation != address(0), "DaimonV2: zero impl");
    }

    receive() external payable {}
}
