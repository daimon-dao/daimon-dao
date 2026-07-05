// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/*
 * Mock del VECCHIO contratto Daimon.
 * Usato nei test e nel deploy su BSC testnet per provare la migrazione 1:1
 * end-to-end. Replica il comportamento essenziale del contratto originale:
 * fee-on-transfer del 5% di default, azzerabile per address con
 * excludeFromFee (nel contratto reale e' onlyOwner; qui e' permissionless
 * perche' e' un mock di test).
 */
contract MockOldDaimon {
    string public name = "Daimon";
    string public symbol = "DMN-OLD";
    uint8 public constant decimals = 18;

    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    mapping(address => bool) public excludedFromFee;
    uint256 public taxFeeBps = 50; // 5%, simula la fee del vecchio contratto
    uint256 public totalSupply;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor(uint256 initialSupply, address holder) {
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

    function allowance(address owner, address spender) external view returns (uint256) {
        return _allowances[owner][spender];
    }

    function excludeFromFee(address account) external {
        excludedFromFee[account] = true;
    }

    // transfer diretta: utile su testnet per distribuire vecchi token ai tester
    function transfer(address recipient, uint256 amount) external returns (bool) {
        _transfer(msg.sender, recipient, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool) {
        require(_allowances[sender][msg.sender] >= amount, "allowance");
        _allowances[sender][msg.sender] -= amount;
        _transfer(sender, recipient, amount);
        return true;
    }

    function _transfer(address sender, address recipient, uint256 amount) private {
        uint256 fee = excludedFromFee[recipient] || excludedFromFee[sender] ? 0 : (amount * taxFeeBps) / 1000;
        uint256 net = amount - fee;

        _balances[sender] -= amount;
        _balances[recipient] += net;

        emit Transfer(sender, recipient, net);
    }
}
