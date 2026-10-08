// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @title SIMDTEST
/// @notice Fixed issuance ERC-20 with a 1% burn on transfers from Ethereum's v4 PoolManager.
/// @dev The launch factory receives the entire issuance and handles all distribution externally.
contract SIMDTESTToken {
    string public constant name = "SIMDTEST";
    string public constant symbol = "SIMDTEST";
    uint8 public constant decimals = 18;
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;
    address public constant POOL_MANAGER = 0x000000000004444c5dc75cB358380D2e3dE08A90;
    uint256 public constant BUY_BURN_BPS = 100;
    uint256 public constant BPS_DENOMINATOR = 10_000;

    uint256 public totalSupply;
    mapping(address account => uint256 balance) public balanceOf;
    mapping(address account => mapping(address spender => uint256 amount)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed account, address indexed spender, uint256 value);

    error ERC20InvalidSender(address sender);
    error ERC20InvalidReceiver(address receiver);
    error ERC20InvalidSpender(address spender);
    error ERC20InsufficientBalance(address sender, uint256 balance, uint256 needed);
    error ERC20InsufficientAllowance(address spender, uint256 allowance, uint256 needed);

    constructor() {
        totalSupply = INITIAL_SUPPLY;
        balanceOf[msg.sender] = INITIAL_SUPPLY;
        emit Transfer(address(0), msg.sender, INITIAL_SUPPLY);
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        if (spender == address(0)) revert ERC20InvalidSpender(spender);
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    /// @notice Spends allowance for the gross amount, including any buy burn.
    /// @dev An allowance of type(uint256).max is treated as unlimited.
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 permitted = allowance[from][msg.sender];
        if (permitted != type(uint256).max) {
            if (permitted < amount) revert ERC20InsufficientAllowance(msg.sender, permitted, amount);
            allowance[from][msg.sender] = permitted - amount;
        }
        _transfer(from, to, amount);
        return true;
    }

    function _transfer(address from, address to, uint256 amount) private {
        if (from == address(0)) revert ERC20InvalidSender(from);
        if (to == address(0)) revert ERC20InvalidReceiver(to);
        uint256 available = balanceOf[from];
        if (available < amount) revert ERC20InsufficientBalance(from, available, amount);

        // All balances are at most INITIAL_SUPPLY, so this multiplication cannot overflow.
        // Round down to whole minor units: transfers below 100 units burn zero.
        uint256 burned = from == POOL_MANAGER ? amount * BUY_BURN_BPS / BPS_DENOMINATOR : 0;
        balanceOf[from] = available - amount;
        // Read the recipient after debiting the sender so self-transfers remain correct.
        balanceOf[to] += amount - burned;
        if (burned != 0) {
            totalSupply -= burned;
            emit Transfer(from, address(0), burned);
        }
        emit Transfer(from, to, amount - burned);
    }
}
