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
 * BEP-20 / ERC-20 COMPATIBILITY NOTES:
 *  - getOwner(), from the BEP-2 binding extension, is deliberately NOT
 *    implemented. This token has no owner: control belongs to the DAO Timelock
 *    through roles, and no single address can be named. Returning a
 *    placeholder — the Timelock, or the zero address — would misrepresent the
 *    trust model to any integrator that reads it as "the account in charge".
 *    The BEP-2 binding is therefore not supported, by design and not by
 *    omission.
 *  - Balances CANNOT be reconstructed from Transfer events alone. Reflection
 *    redistributes value by shifting a global index: a holder's balance grows
 *    with no event naming that holder, because no per-account movement takes
 *    place. ReflectionFeeApplied reports how much was redistributed and by
 *    whom, but not to whom — that is the nature of the mechanism, not a gap in
 *    the instrumentation. Integrations must read balanceOf() and must never
 *    derive balances by replaying the event log.
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

// Read-only views used to decide whether a mandatory fee exemption can be
// released (finding #32). Both are already public on the deployed contracts:
// no change to DaimonStaking — which is not upgradeable — is required.
interface IDaimonStakingLiabilities {
    function totalStakedAmount() external view returns (uint256);
}

interface IDaimonMigrationLiabilities {
    function migrationDeadline() external view returns (uint256);
    function sweepExecuted() external view returns (bool);
}

interface IUniswapV2PairReserves {
    // Only the selector is used (via staticcall in _buyBackAndBurn): the
    // probe must never itself become a revert path, see the comment there.
    function getReserves() external view returns (uint112, uint112, uint32);
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

    // ---- Storage appended by the audit remediation ----
    // APPENDED AT THE END OF STORAGE, deliberately: this contract is behind a
    // UUPS proxy, so new variables may only be added after the existing ones,
    // never inserted among them. The order below - #32's fields first, then
    // #28's budget block - is the DEFINITIVE proxy layout: every future
    // upgrade must respect it.

    // ---- Mandatory fee exemptions (finding #32) ----
    // Some fee exemptions are not a policy choice but a requirement of the
    // module that holds them: removing them would not merely change fees, it
    // would break accounting that other people's funds depend on. They are
    // flagged here and can only be lifted once that module can no longer have
    // liabilities.
    address public migrationContract;
    mapping(address => bool) public mandatoryFeeExempt;

    // ---- Per-block automation budgets (finding #28) ----
    // A 1-wei transfer to the pair is enough to trigger the automation, and
    // lockSwap/nonReentrant only prevent NESTING: they reset between calls,
    // so a loop of dust transfers re-ran the fee swap and the buyback once
    // per iteration. minimumTokensBeforeSwap, buyBackUpperLimit and the 5%
    // slice bounded the SINGLE execution, not the aggregate. These counters
    // bound the aggregate per block, independently of the caller.
    //
    // Two families, deliberately separate:
    //  - ATTEMPTS are consumed BEFORE the router interaction, so a failure
    //    caught by the try/catch still burns the block's attempt and cannot
    //    be retried within the block;
    //  - AMOUNTS record only SUCCESSFUL executions (measured, not assumed),
    //    and are what the per-block ceilings are checked against.
    //
    // Packed: 64+32+32+128 fill one slot exactly, the spent counter sits in
    // a second one. uint128 cannot overflow here (both amounts are bounded
    // by the respective total supplies, far below 2^128).
    uint64 private _autoBudgetBlock;
    uint32 private _blockFeeSwapAttempts;
    uint32 private _blockBuybackAttempts;
    uint128 private _blockDmnSwapped;
    uint128 private _blockBnbSpent;

    // One execution per family per block: the chunk/slice sizes already cap
    // the single execution, so "one per block" makes the per-block aggregate
    // coincide with the bound the existing parameters always intended.
    // Constants, not setters: no new governance surface.
    uint256 private constant MAX_FEE_SWAPS_PER_BLOCK = 1;
    uint256 private constant MAX_BUYBACKS_PER_BLOCK = 1;

    // ---- Events ----
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event SwapAndLiquify(uint256 tokensSwapped, uint256 ethReceived);
    event BuyBackAndBurn(uint256 ethSpent, uint256 tokensBurned);
    // Emitted when an armed buyback is skipped instead of executed (#27):
    // monitoring can distinguish "did not start" from "failed", and a burst
    // of skips is the observable signature of an empty pool or a manipulated
    // quote. The reasons mirror the three abnormal exit paths below.
    event BuyBackSkipped(uint256 ethAmount, BuyBackSkipReason reason);

    enum BuyBackSkipReason {
        EmptyReserves,
        QuoteUnavailable,
        SwapFailed
    }
    event FeesUpdated(uint256 taxFee, uint256 buybackFee, uint256 marketingFee);
    event ParamsUpdated(string param, uint256 value);
    event PausedSet(bool paused);
    event StakingContractSet(address indexed staking);
    event MarketingWalletSet(address indexed wallet);
    event ExcludedFromFeeSet(address indexed account, bool excluded);
    event SwapAndLiquifyEnabledSet(bool enabled);
    event BuyBackEnabledSet(bool enabled);
    /// Reflection applied on a transfer: `amount` was removed from the sender
    /// and redistributed to every reward-eligible holder by shifting the
    /// global index. It is deliberately NOT a Transfer event: no single
    /// account receives it.
    event ReflectionFeeApplied(address indexed sender, uint256 amount);
    event TerminalBuybackSettled(address indexed to, uint256 amount);

    error BelowMinSupply();
    error ZeroAddress();
    error FeeTooHigh();
    error TransferAmountExceedsMaxTx();
    error ContractIsPaused();
    error GuardianExpired();
    error MandatoryFeeExemption();
    error FloorNotReached();
    error InvalidRecipient();
    error NothingToSettle();
    error SettlementTransferFailed();

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
        // The migration must stay fee-exempt while it still owes 1:1 claims:
        // taxing it would make claim() revert with AmountMismatch and freeze
        // every migration while the immutable deadline keeps running.
        migrationContract = _migrationContract;
        mandatoryFeeExempt[_migrationContract] = true;
        isExcludedFromFee[address(this)] = true;

        // The dead address is excluded from reflection: this way its balance
        // reflects ONLY the tokens actually sent (buyback), not accrued
        // reflection, and burnDeadBalanceToFloor() burns net, real supply.
        _isExcludedFromReward[deadAddress] = true;
        _excluded.push(deadAddress);

        uniswapV2Router = IUniswapV2Router02(_router);
        uniswapV2Pair = IUniswapV2Factory(uniswapV2Router.factory()).createPair(address(this), uniswapV2Router.WETH());

        // The pair is excluded from reflection as well. A pair that accrues
        // reflection sees its token balance grow while its recorded reserve
        // stays unchanged: anyone can then pocket the difference by calling
        // skim() on the pair — value taken from the holders the reflection was
        // meant for. Excluding it needs no balance conversion here, because
        // createPair() has just returned a brand-new pair: both _rOwned and
        // _tOwned are zero.
        //
        // NOTE: this ADDS a second entry to the fixed exclusion set; it does
        // NOT make that set mutable. There is deliberately no runtime setter
        // for reward exclusion — the immutability of this set is what removes
        // the whole class of RFI-fork exclusion-toggle bugs, and it is stated
        // as a design property. _getCurrentSupply() already loops over
        // _excluded, so it handles two entries with no change.
        _isExcludedFromReward[uniswapV2Pair] = true;
        _excluded.push(uniswapV2Pair);

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

        // ERC-20/BEP-20 require zero-value transfers to succeed and to emit a
        // Transfer event. Returning here — BEFORE the swap and buyback
        // automation below — also keeps a zero-amount transfer from being used
        // as a free trigger for those swaps. The whenNotPaused guard still
        // applies: a paused token transfers nothing, not even zero.
        if (amount == 0) {
            emit Transfer(from, to, 0);
            return;
        }

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
        // The liquidity fee is a real balance movement to this contract, so it
        // must be observable as a Transfer like any other credit.
        if (tLiquidity > 0) emit Transfer(sender, address(this), tLiquidity);
        // Reflection has no ERC-20 representation: it is a shift of the global
        // index, not a movement between two accounts. A dedicated event makes
        // it observable without pretending it is a transfer to someone.
        if (tFee > 0) emit ReflectionFeeApplied(sender, tFee);

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
    /// @dev Resets the per-block budget counters when the block changes.
    /// Called at the entry of both automation paths, BEFORE their budget
    /// checks, so the counters always refer to the current block.
    function _rollAutomationBudget() private {
        if (_autoBudgetBlock != uint64(block.number)) {
            _autoBudgetBlock = uint64(block.number);
            _blockFeeSwapAttempts = 0;
            _blockBuybackAttempts = 0;
            _blockDmnSwapped = 0;
            _blockBnbSpent = 0;
        }
    }

    function _swapAccumulatedFees(uint256 contractTokenBalance) private lockSwap nonReentrant {
        _rollAutomationBudget();
        // Budget gate (#28): skipping is silent, like the other pacing
        // conditions in _transfer — being over budget is the designed steady
        // state under repeated triggers, not an anomaly worth an event.
        if (_blockFeeSwapAttempts >= MAX_FEE_SWAPS_PER_BLOCK) return;
        if (uint256(_blockDmnSwapped) + contractTokenBalance > minimumTokensBeforeSwap * MAX_FEE_SWAPS_PER_BLOCK) return;
        // Consumed before any router interaction: a caught failure below
        // still burns this block's attempt (see the budget storage note).
        _blockFeeSwapAttempts++;

        uint256 dmnBefore = balanceOf(address(this));
        uint256 initialEth = address(this).balance;
        _swapTokensForEth(contractTokenBalance);
        // The contract is fee-exempt, so on success the delta is exactly the
        // amount sold; on a caught failure it is zero and only the attempt
        // was consumed.
        uint256 dmnSold = dmnBefore - balanceOf(address(this));
        if (dmnSold > 0) {
            _blockDmnSwapped += uint128(dmnSold);
        }
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

        // Clean slate before quoting: no allowance may survive from an earlier
        // attempt, whatever happened to it.
        _approve(address(this), address(uniswapV2Router), 0);

        // amountOutMin from the current quote minus the governed tolerance.
        // NOTE: the quote is read in the same block as the swap, so it limits
        // the impact of intra-block manipulation up to the tolerance, it does
        // not eliminate it (a TWAP would be needed for that). The contract is
        // excluded from the fee, so the quote does not need correcting for the
        // transfer fee.
        //
        // The quote is wrapped like the swap below: getAmountsOut reverts on a
        // pair with no reserves, and an unwrapped revert here would propagate
        // out of _swapAccumulatedFees and take down the user transfer that
        // triggered it. A quote we cannot obtain simply means "do not swap now".
        uint256 minOut;
        try uniswapV2Router.getAmountsOut(tokenAmount, path) returns (uint256[] memory quote) {
            if (quote.length < 2 || quote[1] == 0) return;
            minOut = (quote[1] * (10000 - maxSwapSlippageBps)) / 10000;
        } catch {
            return;
        }

        // Approve exactly what the swap consumes, and only once the quote is known.
        _approve(address(this), address(uniswapV2Router), tokenAmount);
        // try/catch: if slippage exceeds the tolerance the swap fails, but it
        // must NOT revert the transfer of the user who triggered it (that
        // would be a DoS vector on sells: just push the price beyond the
        // tolerance). The tokens stay for the next round.
        try uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount, minOut, path, address(this), block.timestamp
        ) {} catch {}
        // Revoke on ANY outcome. On success the router has already pulled the
        // tokens and the allowance is spent; on failure it would otherwise
        // stay written in this frame and remain callable later.
        _approve(address(this), address(uniswapV2Router), 0);
    }

    function _buyBackAndBurn(uint256 ethAmount) private lockSwap nonReentrant {
        if (ethAmount == 0) return;
        if (_tTotal <= MIN_SUPPLY) return; // floor: no further buyback/burn

        _rollAutomationBudget();
        if (_blockBuybackAttempts >= MAX_BUYBACKS_PER_BLOCK) return;
        // The budget binds the CUMULATIVE spend, not the single slice: each
        // call spends 5% of the RESIDUAL balance, so per-slice limits decay
        // geometrically while the aggregate keeps growing (5 dust triggers
        // drained ~2.26 ETH from a 10 ETH balance, not 5 x 0.5). The ceiling
        // is the largest single slice the parameters allow.
        if (uint256(_blockBnbSpent) + ethAmount > (buyBackUpperLimit / 20) * MAX_BUYBACKS_PER_BLOCK) return;
        // Consumed before any router interaction (the reserve probe below
        // included): a caught failure still burns this block's attempt (see
        // the budget storage note).
        _blockBuybackAttempts++;

        // #27 (BNB half): on a pair with no reserves the quote below can only
        // revert, and before this fix that revert propagated out of _transfer
        // — a donation of >1 BNB to the contract was enough to block the
        // transfer seeding the initial liquidity. Probe the reserves first
        // and skip outright on an empty pool.
        //
        // Raw staticcall + tolerant decode, deliberately: the probe must
        // never itself become a revert path. A high-level try/catch call is
        // NOT enough — since solc 0.8.10 the call to an address without code
        // "succeeds" with empty returndata and the decode failure raises in
        // the CALLER, outside the catch. A pair we cannot read (codeless
        // test double, unexpected ABI) simply yields no verdict here and
        // falls through to the wrapped quote, which is the actual guard.
        (bool probeOk, bytes memory reservesData) =
            uniswapV2Pair.staticcall(abi.encodeWithSelector(IUniswapV2PairReserves.getReserves.selector));
        if (probeOk && reservesData.length >= 96) {
            // Decoded as uint256 so the decode itself cannot revert: any
            // 32-byte word is a valid uint256, and only the zero-comparison
            // matters here.
            (uint256 reserve0, uint256 reserve1, ) = abi.decode(reservesData, (uint256, uint256, uint256));
            if (reserve0 == 0 || reserve1 == 0) {
                emit BuyBackSkipped(ethAmount, BuyBackSkipReason.EmptyReserves);
                return;
            }
        }

        address[] memory path = new address[](2);
        path[0] = uniswapV2Router.WETH();
        path[1] = address(this);

        // amountOutMin: current quote, corrected for the token's transfer fee
        // (the dead address is not excluded from the fee: it receives the
        // net), minus the governed slippage tolerance.
        //
        // The quote is wrapped like the swap below (same structure as the
        // #15 fix in _swapTokensForEth): getAmountsOut reverts on a pair
        // with no reserves, and an unwrapped revert here would propagate out
        // of _transfer and take down the user transfer that triggered it. A
        // quote we cannot obtain simply means "do not buy back now".
        uint256 minOut;
        try uniswapV2Router.getAmountsOut(ethAmount, path) returns (uint256[] memory quote) {
            if (quote.length < 2 || quote[1] == 0) {
                emit BuyBackSkipped(ethAmount, BuyBackSkipReason.QuoteUnavailable);
                return;
            }
            uint256 expectedAfterFee = (quote[1] * (1000 - taxFee - liquidityFee)) / 1000;
            minOut = (expectedAfterFee * (10000 - maxSwapSlippageBps)) / 10000;
        } catch {
            emit BuyBackSkipped(ethAmount, BuyBackSkipReason.QuoteUnavailable);
            return;
        }

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
            emit BuyBackSkipped(ethAmount, BuyBackSkipReason.SwapFailed);
            return;
        }

        // Only a successful buyback counts against the amount budget: the
        // msg.value above has actually left the contract at this point.
        _blockBnbSpent += uint128(ethAmount);

        uint256 balanceAfter = balanceOf(deadAddress);
        emit BuyBackAndBurn(ethAmount, balanceAfter - balanceBefore);
    }

    /// @notice REALLY burns supply (reduces _tTotal) by drawing from the
    /// tokens already accumulated in the dead address, never going below
    /// MIN_SUPPLY. Anyone can call it while the token is not paused: it does
    /// not move anyone's funds, it just "cancels" from the supply accounting
    /// what is already unrecoverable in the dead address.
    /// @dev whenNotPaused is deliberate. This function writes _rTotal and
    /// _tTotal — the reflection accounting itself. If the guardian pauses
    /// because that accounting is suspect, leaving open a permissionless
    /// function that mutates it would defeat the purpose of the pause.
    function burnDeadBalanceToFloor() external nonReentrant whenNotPaused {
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

        // Conventional burn signature: tokens leaving circulation are reported
        // as a Transfer to the zero address, which is what indexers and
        // explorers look for.
        emit Transfer(deadAddress, address(0), toBurn);
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
        // Staking must stay fee-exempt while it holds anyone's principal:
        // withdraw() returns the exact staked amount, so a taxed transfer out
        // would leave it short and corrupt its accounting. A previous staking
        // contract keeps its flag: it may still hold stakes of its own.
        mandatoryFeeExempt[staking] = true;
        emit StakingContractSet(staking);
    }

    /// @notice Governance can grant or revoke fee exemptions freely, EXCEPT
    /// for the ones flagged as mandatory: those can only be revoked once the
    /// module that holds them can no longer have liabilities. Granting is
    /// never restricted.
    function setExcludedFromFee(address account, bool excluded) external onlyRole(GOVERNANCE_ROLE) {
        if (!excluded && mandatoryFeeExempt[account] && !_mandatoryExemptionReleasable(account)) {
            revert MandatoryFeeExemption();
        }
        isExcludedFromFee[account] = excluded;
        emit ExcludedFromFeeSet(account, excluded);
    }

    /// @dev A mandatory exemption becomes releasable when the module behind it
    /// can no longer owe anyone anything:
    ///  - staking: no principal left to return (totalStakedAmount == 0);
    ///  - migration: the window is closed AND the sweep has been executed, so
    ///    no claim can still arrive and nothing is left to send.
    /// Both reads already exist as public views on the deployed contracts, so
    /// this needs no change to DaimonStaking, which is not upgradeable.
    function _mandatoryExemptionReleasable(address account) private view returns (bool) {
        if (account == migrationContract) {
            return block.timestamp > IDaimonMigrationLiabilities(account).migrationDeadline()
                && IDaimonMigrationLiabilities(account).sweepExecuted();
        }
        return IDaimonStakingLiabilities(account).totalStakedAmount() == 0;
    }

    function setSwapAndLiquifyEnabled(bool enabled) external onlyRole(GOVERNANCE_ROLE) {
        swapAndLiquifyEnabled = enabled;
        emit SwapAndLiquifyEnabledSet(enabled);
    }

    function setBuyBackEnabled(bool enabled) external onlyRole(GOVERNANCE_ROLE) {
        buyBackEnabled = enabled;
        emit BuyBackEnabledSet(enabled);
    }

    /// @notice Once the supply has reached MIN_SUPPLY, sends the BNB still
    /// held for the buyback to `to`. Governance only.
    /// @dev At the floor `_buyBackAndBurn()` returns immediately, so the BNB
    /// accumulated from the marketing/buyback split has no spending path left
    /// and would sit here forever. This is the only way out, and it opens ONLY
    /// in that terminal state: while `_tTotal > MIN_SUPPLY` the buyback is
    /// still the intended use of those funds and this reverts.
    ///
    /// WHY THE RECIPIENT IS NOT FIXED — this is deliberate, not an omission.
    /// A hardcoded or stored address would be written years before it is ever
    /// read, in a state that may never be reached, and could not be corrected
    /// if that wallet were lost or superseded; a stored one would also add a
    /// setter and a misconfiguration surface for a value used at most once.
    /// Passing it per call is strictly more constrained in practice: the call
    /// is governance-only, so it can only arrive through propose -> vote ->
    /// 7-day timelock, and the destination is public for those seven days
    /// before it can execute. The DAO decides where the residue goes at the
    /// moment it becomes real, with the community watching.
    /// The guards below exclude the destinations that would destroy the funds
    /// or return them to this same dead end.
    function settleTerminalBuyback(address to) external onlyRole(GOVERNANCE_ROLE) nonReentrant {
        if (_tTotal > MIN_SUPPLY) revert FloorNotReached();
        // Not the zero address (burns it), not this contract (returns it to
        // the same dead end), not the dead address (unrecoverable).
        if (to == address(0) || to == address(this) || to == deadAddress) revert InvalidRecipient();

        uint256 amount = address(this).balance;
        if (amount == 0) revert NothingToSettle();

        (bool ok, ) = to.call{value: amount}("");
        if (!ok) revert SettlementTransferFailed();

        emit TerminalBuybackSettled(to, amount);
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
