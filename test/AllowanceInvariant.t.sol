// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {SIMDTESTToken} from "../src/SIMDTESTToken.sol";
import {TestBase} from "./support/TestBase.sol";

/// @dev Approvals are separate actions: spending must use the allowance left by earlier calls.
/// The model never reads actual balances or allowances to decide the expected result.
contract AllowanceHandler is TestBase {
    SIMDTESTToken public immutable token;
    address[5] public actors;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;
    uint256 public burned;

    constructor() {
        token = new SIMDTESTToken();
        actors = [address(this), ALICE, BOB, DISTRIBUTOR, MANAGER];
        token.transfer(DISTRIBUTOR, SUPPLY / 10);
        token.transfer(MANAGER, SUPPLY * 9 / 10);
        expectedBalance[DISTRIBUTOR] = SUPPLY / 10;
        expectedBalance[MANAGER] = SUPPLY * 9 / 10;
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed, uint8 mode) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        uint256 amount = mode % 3 == 0 ? 0 : mode % 3 == 1 ? type(uint256).max : amountSeed % (SUPPLY + 1);
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 amount = _amount(amountSeed, expectedBalance[from]);
        uint256 previousSupply = token.totalSupply();
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        _recordTransfer(from, to, amount);
        assertTrue(token.totalSupply() <= previousSupply);
    }

    function transferFrom(uint256 fromSeed, uint256 toSeed, uint256 spenderSeed, uint256 amountSeed, uint8 mode)
        external
    {
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        address spender = _actor(spenderSeed);
        uint256 allowed = expectedAllowance[from][spender];
        uint256 held = expectedBalance[from];
        uint256 limit = held < allowed ? held : allowed;
        uint256 amount;
        if (mode % 4 == 0) amount = _amount(amountSeed, limit);
        else if (mode % 4 == 1) amount = held + 1;
        else if (mode % 4 == 2) amount = allowed == type(uint256).max ? type(uint256).max : allowed + 1;
        else amount = amountSeed % (SUPPLY + 1);

        bytes memory expectedError;
        if (allowed < amount) {
            expectedError =
                abi.encodeWithSelector(SIMDTESTToken.ERC20InsufficientAllowance.selector, spender, allowed, amount);
        } else if (held < amount) {
            expectedError = abi.encodeWithSelector(SIMDTESTToken.ERC20InsufficientBalance.selector, from, held, amount);
        }

        uint256 previousSupply = token.totalSupply();
        vm.prank(spender);
        (bool ok, bytes memory result) = address(token).call(abi.encodeCall(token.transferFrom, (from, to, amount)));
        if (expectedError.length != 0) {
            assertTrue(!ok);
            assertTrue(keccak256(result) == keccak256(expectedError));
        } else {
            assertTrue(ok && abi.decode(result, (bool)));
            if (allowed != type(uint256).max) expectedAllowance[from][spender] = allowed - amount;
            _recordTransfer(from, to, amount);
        }
        assertTrue(token.totalSupply() <= previousSupply);
    }

    function rejectZeroReceiver(uint256 fromSeed, uint256 spenderSeed, uint256 amountSeed) external {
        address from = _actor(fromSeed);
        address spender = _actor(spenderSeed);
        uint256 allowed = expectedAllowance[from][spender];
        uint256 held = expectedBalance[from];
        uint256 amount = _amount(amountSeed, held < allowed ? held : allowed);
        vm.prank(spender);
        (bool ok, bytes memory result) =
            address(token).call(abi.encodeCall(token.transferFrom, (from, address(0), amount)));
        assertTrue(!ok);
        assertTrue(
            keccak256(result)
                == keccak256(abi.encodeWithSelector(SIMDTESTToken.ERC20InvalidReceiver.selector, address(0)))
        );
        // No model changes: both the allowance debit and any burn must roll back.
    }

    function _recordTransfer(address from, address to, uint256 amount) private {
        uint256 fee = from == MANAGER ? amount / 100 : 0;
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount - fee;
        burned += fee;
    }

    function _actor(uint256 seed) private view returns (address) {
        return actors[seed % actors.length];
    }

    function _amount(uint256 seed, uint256 limit) private pure returns (uint256) {
        // Exercise depletion, dust and the first fee boundary frequently, including at zero balance.
        uint256 choice = seed % 8;
        if (choice == 0) return 0;
        if (choice == 1) return limit;
        if (choice < 6) {
            uint256 edge = choice == 2 ? 1 : choice == 3 ? 99 : choice == 4 ? 100 : 101;
            return edge < limit ? edge : limit;
        }
        return seed % (limit + 1);
    }
}

contract AllowanceInvariantTest is TestBase {
    AllowanceHandler private handler;

    function setUp() public {
        handler = new AllowanceHandler();
    }

    function targetContracts() public view returns (address[] memory targets) {
        targets = new address[](1);
        targets[0] = address(handler);
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 96
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_EveryBalanceAndAllowanceMatchesIndependentHistory() public view {
        SIMDTESTToken token = handler.token();
        uint256 sum;
        for (uint256 i; i < 5; ++i) {
            address owner = handler.actors(i);
            uint256 balance = token.balanceOf(owner);
            assertEq(balance, handler.expectedBalance(owner));
            sum += balance;
            for (uint256 j; j < 5; ++j) {
                address spender = handler.actors(j);
                assertEq(token.allowance(owner, spender), handler.expectedAllowance(owner, spender));
            }
        }
        assertEq(sum, token.totalSupply());
        assertEq(token.totalSupply() + handler.burned(), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertTrue(token.POOL_MANAGER() == MANAGER);
        assertEq(token.BUY_BURN_BPS(), 100);
    }
}
