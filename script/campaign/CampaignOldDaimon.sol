// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/*
 * Campaign-only mock of the OLD Daimon (DMX) — Level-1 harness, new file.
 *
 * Faithful to the predecessor semantics that matter for the #29 preflight:
 *  - fee-on-transfer applied unless sender OR recipient is exempt;
 *  - exemptions settable ONLY by the owner (the real DMX gates them with
 *    onlyOwner; src/mocks/MockOldDaimon deliberately keeps them
 *    permissionless for unit-test convenience, as its own header states —
 *    src/ is untouchable, so the campaign uses this owner-gated twin);
 *  - 11% total transfer fee, the real DMX figure (the src mock uses 5%).
 *
 * Interface-compatible with everything DaimonMigration and Deploy.s.sol
 * need from OLD_DAIMON: balanceOf, transfer, transferFrom, approve,
 * excludeFromFee.
 */
contract CampaignOldDaimon {
    string public name = "Daimon";
    string public symbol = "DMX";
    uint8 public constant decimals = 18;

    address public immutable owner;
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    mapping(address => bool) public excludedFromFee;
    uint256 public constant taxFeeBps = 110; // 11% out of 1000, the real DMX total fee
    uint256 public totalSupply;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor(uint256 initialSupply, address holder) {
        owner = msg.sender;
        totalSupply = initialSupply;
        _balances[holder] = initialSupply;
        emit Transfer(address(0), holder, initialSupply);
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function allowance(address owner_, address spender) external view returns (uint256) {
        return _allowances[owner_][spender];
    }

    /// Owner-only, like the real predecessor: the #29 preflight explicitly
    /// requires confirming the DMX owner still holds this authority.
    function excludeFromFee(address account) external {
        require(msg.sender == owner, "DMX: only owner");
        excludedFromFee[account] = true;
    }

    function transfer(address recipient, uint256 amount) external returns (bool) {
        _transfer(msg.sender, recipient, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool) {
        require(_allowances[sender][msg.sender] >= amount, "DMX: allowance");
        _allowances[sender][msg.sender] -= amount;
        _transfer(sender, recipient, amount);
        return true;
    }

    function _transfer(address sender, address recipient, uint256 amount) private {
        uint256 fee = excludedFromFee[recipient] || excludedFromFee[sender] ? 0 : (amount * taxFeeBps) / 1000;
        uint256 net = amount - fee;

        _balances[sender] -= amount;
        _balances[recipient] += net;
        // The fee share stays out of both balances, like value sunk into the
        // predecessor's reflection pool: enough fidelity for the preflight.

        emit Transfer(sender, recipient, net);
    }
}
