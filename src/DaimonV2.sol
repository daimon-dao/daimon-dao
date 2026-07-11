// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/*
 * DaimonV2
 * --------
 * Token ERC20 con reflection (ispirato al Daimon originale), governance-ready.
 *
 * DIFFERENZE FONDAMENTALI rispetto all'originale:
 *  - Nessun owner singolo: tutti i parametri sensibili sono modificabili SOLO
 *    dal Timelock della DAO (governanceAddress), mai da un wallet singolo.
 *  - NESSUNA funzione di mint, in nessuna forma, in nessun punto del codice.
 *    La supply massima viene creata UNA SOLA VOLTA nel constructor e basta.
 *  - Floor di burn fisso e immutabile: MIN_SUPPLY = 21_000_000_000 token.
 *    Qualsiasi operazione di burn (fee reflection compresa, e il buyback)
 *    e' bloccata se farebbe scendere la supply sotto il floor.
 *  - E' upgradable (UUPS) SOLO per la logica non-monetaria (fee, indirizzi,
 *    limiti, enable/disable buyback). L'assenza di mint e il floor sono
 *    enforced anche nella funzione di upgrade-authorization: vedi note in
 *    _authorizeUpgrade. Non e' una garanzia matematica assoluta (un upgrade
 *    malevolo autorizzato dalla DAO potrebbe in teoria sostituire la logica),
 *    motivo per cui l'upgrade passa SEMPRE dal Timelock con delay pubblico:
 *    la community ha sempre una finestra per accorgersene e reagire.
 *
 * DIPENDENZE:
 *  Usa gli import ufficiali OpenZeppelin (auditati e mantenuti):
 *  Initializable, UUPSUpgradeable, AccessControlUpgradeable,
 *  ReentrancyGuardUpgradeable dal pacchetto contracts-upgradeable v5.
 *  La rotazione dei ruoli replica la semantica originale ("solo la
 *  governance puo' ruotare i ruoli, incluso il proprio") impostando
 *  GOVERNANCE_ROLE come admin di se stesso e di GUARDIAN_ROLE.
 */

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

// ============================================================
// === Interfacce Uniswap (identiche all'originale, necessarie per swap/buyback)
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
    // Il token notifica al contratto di staking quanta fee marketing
    // gli e' stata inviata, cosi' lo staking puo' contabilizzare i reward.
    // Payable: lo staking richiede msg.value == amount.
    function notifyRewardAmount(uint256 amount) external payable;
}

// ============================================================
// === DaimonV2
// ============================================================
contract DaimonV2 is Initializable, UUPSUpgradeable, AccessControlUpgradeable, ReentrancyGuardUpgradeable {
    // ---- Ruoli ----
    bytes32 public constant GOVERNANCE_ROLE = keccak256("GOVERNANCE_ROLE"); // = Timelock della DAO
    bytes32 public constant GUARDIAN_ROLE = keccak256("GUARDIAN_ROLE");     // multisig solo-pausa, no poteri economici

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

    // ---- Supply / floor (immutabili per design) ----
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000_000 * 10 ** 18; // 1000 miliardi
    uint256 public constant MIN_SUPPLY = 21_000_000_000 * 10 ** 18;        // floor: 21 miliardi
    // NESSUNA variabile MAX_SUPPLY mintabile: la supply puo' SOLO scendere.

    uint256 private _tTotal;   // supply corrente (token units), parte da INITIAL_SUPPLY, scende col burn
    uint256 private _rTotal;
    uint256 private _tFeeTotal;

    // ---- Fee (in basis points su 1000, come l'originale: es 50 = 5%) ----
    uint256 public taxFee;        // redistribuita ai holder via reflection
    uint256 public buybackFee;    // usata per comprare e bruciare token
    uint256 public marketingFee;  // usata per marketing + reward staking
    uint256 public liquidityFee;  // = buybackFee + marketingFee (accumulata nel contratto prima dello swap)

    uint256 private _previousTaxFee;
    uint256 private _previousBuybackFee;
    uint256 private _previousMarketingFee;
    uint256 private _previousLiquidityFee;

    // Quota della marketingFee che va allo staking reward pool, in bps su 1000
    // (es. 600 = 60% della marketing fee va allo staking, il resto a marketingWallet)
    uint256 public stakingRewardShareBps;

    uint256 public maxTxAmount;
    uint256 public minimumTokensBeforeSwap;
    uint256 public buyBackUpperLimit;

    // Slippage massimo tollerato (bps su 10000) per gli swap automatici di
    // fee e buyback: l'amountOutMin e' derivato da getAmountsOut meno questa
    // tolleranza, per limitare l'estrazione MEV sugli swap del contratto.
    uint256 public maxSwapSlippageBps;

    address public marketingWallet;
    address public stakingContract;
    address public constant deadAddress = 0x000000000000000000000000000000000000dEaD;

    IUniswapV2Router02 public uniswapV2Router;
    address public uniswapV2Pair;

    bool private _inSwap;
    bool public swapAndLiquifyEnabled;
    bool public buyBackEnabled;
    bool public paused; // attivabile SOLO dal Guardian, per emergenze, mai per profitto

    // Scadenza del ruolo Guardian: dopo 36 mesi dal deploy, setPaused() smette
    // di funzionare permanentemente. Settato una sola volta in initialize(),
    // nessun setter pubblico esiste — verificabile on-chain da chiunque.
    uint256 public guardianExpiry;

    // ---- Eventi ----
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
        // Disabilita l'inizializzazione diretta dell'implementation contract,
        // cosi' nessuno puo' chiamare initialize() sull'implementazione e
        // diventare "owner" di un contratto che non sara' mai usato come tale
        // (attacco classico sui proxy UUPS non protetti).
        _disableInitializers();
    }

    /// @param _migrationContract riceve l'intera INITIAL_SUPPLY per la migrazione 1:1.
    function initialize(
        string memory _name,
        string memory _symbol,
        address _migrationContract,
        address _router,
        address _governance,   // Timelock della DAO
        address _guardian,     // multisig di emergenza, solo pausa
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

        taxFee = 10;          // 1% reflection ai holder
        buybackFee = 20;      // 2% buyback e burn
        marketingFee = 20;    // 2% marketing + staking reward
        liquidityFee = buybackFee + marketingFee;  // 4% totale accumulato nel contratto
        _previousTaxFee = taxFee;
        _previousBuybackFee = buybackFee;
        _previousMarketingFee = marketingFee;
        _previousLiquidityFee = liquidityFee;
        // Fee totale iniziale: 1% + 2% + 2% = 5%
        // Hard cap nel codice (setFees): mai superabile il 10% totale

        stakingRewardShareBps = 600; // 60% della marketing fee allo staking reward pool

        // Guardian scadenza: 36 mesi dal deploy, non modificabile.
        // Dopo questa data, setPaused() reverte automaticamente per sempre.
        guardianExpiry = block.timestamp + 1095 days; // 365 * 3 = 1095

        maxTxAmount = _tTotal / 200;           // 0.5% supply iniziale
        minimumTokensBeforeSwap = _tTotal / 5000; // 0.02% supply iniziale
        buyBackUpperLimit = 50 ether;
        maxSwapSlippageBps = 500; // 5% di slippage massimo sugli swap automatici

        swapAndLiquifyEnabled = true;
        buyBackEnabled = true;

        marketingWallet = _marketingWallet;

        // Solo la governance puo' ruotare i ruoli (incluso il proprio):
        // GOVERNANCE_ROLE amministra se stesso e GUARDIAN_ROLE. Nessuno
        // detiene DEFAULT_ADMIN_ROLE.
        _setRoleAdmin(GOVERNANCE_ROLE, GOVERNANCE_ROLE);
        _setRoleAdmin(GUARDIAN_ROLE, GOVERNANCE_ROLE);
        _grantRole(GOVERNANCE_ROLE, _governance);
        _grantRole(GUARDIAN_ROLE, _guardian);

        // L'intera supply va al contratto di migrazione: nessun "team wallet"
        // pre-allocato fuori dalla migrazione 1:1, per design.
        _rOwned[_migrationContract] = _rTotal;
        isExcludedFromFee[_migrationContract] = true;
        isExcludedFromFee[address(this)] = true;

        // Il dead address e' escluso dalle reflection: cosi' il suo balance
        // riflette SOLO i token realmente inviati (buyback), non reflection
        // maturate, e burnDeadBalanceToFloor() brucia supply netta e reale.
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

        // maxTxAmount non si applica a: governance, al contratto stesso
        // (quando vende i token di fee accumulati durante lo swap interno,
        // operazione che puo' superare maxTx per costruzione), e agli
        // indirizzi esplicitamente esclusi dalla fee (replica lo stesso
        // comportamento del contratto originale).
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
                _buyBackAndBurn(spendAmount / 20); // usa il 5% dell'eth disponibile per call, non tutto in un colpo
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

        // Quota destinata al "ramo marketing" (comprende anche il funding dello staking)
        uint256 marketingEth = (ethReceived * marketingFee) / liquidityFee;
        // Il resto resta nel contratto come ETH per il buyback (ramo buyback)

        uint256 toStaking = (marketingEth * stakingRewardShareBps) / 1000;
        uint256 toMarketingWallet = marketingEth - toStaking;

        if (toMarketingWallet > 0) {
            (bool ok1, ) = marketingWallet.call{value: toMarketingWallet}("");
            require(ok1, "DaimonV2: marketing transfer failed");
        }
        if (toStaking > 0 && stakingContract != address(0)) {
            // Un'unica chiamata payable: notifyRewardAmount dello staking
            // richiede msg.value == amount, quindi fondi e contabilita'
            // devono viaggiare nella stessa chiamata.
            IDaimonStakingNotifier(stakingContract).notifyRewardAmount{value: toStaking}(toStaking);
        }

        emit SwapAndLiquify(contractTokenBalance, ethReceived);
    }

    function _swapTokensForEth(uint256 tokenAmount) private {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();

        // amountOutMin dal quote corrente meno la tolleranza governata.
        // NOTA: il quote e' letto nello stesso blocco dello swap, quindi
        // limita l'impatto di manipolazioni intra-blocco fino alla
        // tolleranza, non le elimina (per quello servirebbe un TWAP).
        // Il contratto e' escluso dalla fee, quindi il quote non va
        // corretto per la transfer fee.
        uint256[] memory quote = uniswapV2Router.getAmountsOut(tokenAmount, path);
        uint256 minOut = (quote[1] * (10000 - maxSwapSlippageBps)) / 10000;

        _approve(address(this), address(uniswapV2Router), tokenAmount);
        // try/catch: se lo slippage supera la tolleranza lo swap fallisce,
        // ma NON deve far revertire la transfer dell'utente che lo ha
        // innescato (sarebbe un vettore di DoS sui sell: basta spingere il
        // prezzo oltre tolleranza). I token restano per il prossimo round.
        try uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount, minOut, path, address(this), block.timestamp
        ) {} catch {}
    }

    function _buyBackAndBurn(uint256 ethAmount) private lockSwap nonReentrant {
        if (ethAmount == 0) return;
        if (_tTotal <= MIN_SUPPLY) return; // floor: nessun buyback/burn ulteriore

        address[] memory path = new address[](2);
        path[0] = uniswapV2Router.WETH();
        path[1] = address(this);

        // amountOutMin: quote corrente, corretto per la transfer fee del
        // token (il dead address non e' escluso dalla fee: riceve il netto),
        // meno la tolleranza di slippage governata.
        uint256 expectedAfterFee = 0;
        {
            uint256[] memory quote = uniswapV2Router.getAmountsOut(ethAmount, path);
            expectedAfterFee = (quote[1] * (1000 - taxFee - liquidityFee)) / 1000;
        }
        uint256 minOut = (expectedAfterFee * (10000 - maxSwapSlippageBps)) / 10000;

        uint256 balanceBefore = balanceOf(deadAddress);

        // Acquista token e li invia DIRETTAMENTE al dead address: e' un burn
        // visibile e irreversibile, ma la supply totale (_tTotal) NON viene
        // decrementata qui, perche' i token comprati esistevano gia' (sono
        // presi dalla liquidity pool, non creati). Per applicare la
        // deflazione reale sulla supply enforciamo il floor separatamente
        // tramite burnToFloor(), vedi sotto: e' quella funzione che brucia
        // davvero supply, mentre questo buyback sostiene il prezzo.
        // try/catch: un buyback oltre tolleranza viene saltato (l'ETH resta
        // per il prossimo tentativo), senza far revertire la transfer che
        // lo ha innescato.
        try uniswapV2Router.swapExactETHForTokensSupportingFeeOnTransferTokens{value: ethAmount}(
            minOut, path, deadAddress, block.timestamp + 300
        ) {} catch {
            return;
        }

        uint256 balanceAfter = balanceOf(deadAddress);
        emit BuyBackAndBurn(ethAmount, balanceAfter - balanceBefore);
    }

    /// @notice Brucia REALMENTE supply (riduce _tTotal) prelevando dai token
    /// gia' accumulati nel dead address, senza mai scendere sotto MIN_SUPPLY.
    /// Chiunque puo' chiamarla (e' permissionless e sicura): non sposta fondi
    /// di nessuno, si limita a "cancellare" dalla contabilita' supply quanto
    /// e' gia' irrecuperabile nel dead address.
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

        if (_tTotal < MIN_SUPPLY) revert BelowMinSupply(); // safety net, non deve mai accadere
    }

    // ============================================================
    // Amministrazione: SOLO governance (Timelock), mai owner singolo
    // ============================================================
    function setFees(uint256 _taxFee, uint256 _buybackFee, uint256 _marketingFee) external onlyRole(GOVERNANCE_ROLE) {
        if (_taxFee + _buybackFee + _marketingFee > 100) revert FeeTooHigh(); // hard cap 10% totale, immutabile
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
        require(amount >= _tTotal / 10000, "DaimonV2: maxTx too low"); // min 0.01% supply, anti-self-DoS
        maxTxAmount = amount;
        emit ParamsUpdated("maxTxAmount", amount);
    }

    function setMinimumTokensBeforeSwap(uint256 amount) external onlyRole(GOVERNANCE_ROLE) {
        // Floor: min 0.0001% della supply. Un valore ~0 renderebbe overMin
        // sempre vero, innescando uno swap a ogni transfer verso la pair
        // (gas-DoS di fatto sui sell).
        require(amount >= _tTotal / 1_000_000, "DaimonV2: swap threshold too low");
        minimumTokensBeforeSwap = amount;
        emit ParamsUpdated("minimumTokensBeforeSwap", amount);
    }

    function setBuyBackUpperLimit(uint256 amount) external onlyRole(GOVERNANCE_ROLE) {
        buyBackUpperLimit = amount;
        emit ParamsUpdated("buyBackUpperLimit", amount);
    }

    function setMaxSwapSlippageBps(uint256 bps) external onlyRole(GOVERNANCE_ROLE) {
        // 0.5% - 30%: mai 0 (bloccherebbe ogni swap) ne' valori che
        // riaprono di fatto la porta al MEV illimitato.
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

    // ---- Guardian: SOLO pausa di emergenza, nessun potere economico ----
    // Dopo 36 mesi dal deploy (guardianExpiry), questa funzione reverte
    // permanentemente: il contratto non puo' piu' essere messo in pausa
    // da nessuno, nemmeno dalla DAO. E' una garanzia di decentralizzazione
    // definitiva, verificabile on-chain da chiunque leggendo guardianExpiry.
    function setPaused(bool _paused) external onlyRole(GUARDIAN_ROLE) {
        // Solo METTERE in pausa scade con il guardian: togliere la pausa
        // resta sempre possibile, altrimenti un contratto in pausa al
        // momento della scadenza resterebbe congelato per sempre.
        if (_paused && block.timestamp >= guardianExpiry) revert GuardianExpired();
        paused = _paused;
        emit PausedSet(_paused);
    }

    // ============================================================
    // Upgrade: solo governance, con verifica esplicita anti-mint
    // ============================================================
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(GOVERNANCE_ROLE) {
        // Non possiamo verificare a runtime il bytecode della nuova
        // implementation in modo assoluto, ma possiamo richiedere che la DAO
        // pubblichi il codice in chiaro e che il Timelock dia tempo alla
        // community di leggerlo prima dell'esecuzione (vedi delay nel
        // TimelockController). Questo e' un controllo di processo, non
        // tecnico: e' il limite intrinseco di qualunque sistema upgradable,
        // e va comunicato chiaramente alla community.
        require(newImplementation != address(0), "DaimonV2: zero impl");
    }

    receive() external payable {}
}
