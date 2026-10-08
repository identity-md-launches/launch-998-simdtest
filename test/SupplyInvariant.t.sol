// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {SIMDTESTToken} from "../src/SIMDTESTToken.sol";
import {TestBase} from "./support/TestBase.sol";

contract SupplyHandler is TestBase {
    SIMDTESTToken public immutable token;
    address[4] public actors;
    uint256 public burned;

    constructor() {
        token = new SIMDTESTToken();
        actors = [address(this), ALICE, BOB, MANAGER];
        for (uint256 i = 1; i < actors.length; ++i) {
            token.transfer(actors[i], SUPPLY / 4);
        }
    }

    function move(uint256 fromSeed, uint256 toSeed, uint256 amountSeed, bool delegated, bool unlimited) public {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 amount = amountSeed % (token.balanceOf(from) + 1);
        uint256 previousSupply = token.totalSupply();
        if (delegated) {
            vm.prank(from);
            token.approve(SPENDER, unlimited ? type(uint256).max : amount);
            vm.prank(SPENDER);
            assertTrue(token.transferFrom(from, to, amount));
            assertEq(token.allowance(from, SPENDER), unlimited ? type(uint256).max : 0);
        } else {
            vm.prank(from);
            assertTrue(token.transfer(to, amount));
        }
        uint256 expectedBurn = from == MANAGER ? amount / 100 : 0;
        burned += expectedBurn;
        assertEq(token.totalSupply(), previousSupply - expectedBurn);
    }

    function rejectedOverspend(uint256 fromSeed, bool delegated) public {
        address from = actors[fromSeed % actors.length];
        uint256 held = token.balanceOf(from);
        uint256 previousSupply = token.totalSupply();
        if (delegated) {
            vm.prank(from);
            token.approve(SPENDER, held + 1);
            vm.prank(SPENDER);
            (bool ok,) = address(token).call(abi.encodeCall(token.transferFrom, (from, ALICE, held + 1)));
            assertTrue(!ok);
            assertEq(token.allowance(from, SPENDER), held + 1);
        } else {
            vm.prank(from);
            (bool ok,) = address(token).call(abi.encodeCall(token.transfer, (ALICE, held + 1)));
            assertTrue(!ok);
        }
        assertEq(token.balanceOf(from), held);
        assertEq(token.totalSupply(), previousSupply);
    }
}

contract SupplyInvariantTest is TestBase {
    SupplyHandler internal handler;

    function setUp() public {
        handler = new SupplyHandler();
    }

    /// @dev Foundry discovers this targeting hook without requiring forge-std.
    function targetContracts() public view returns (address[] memory targets) {
        targets = new address[](1);
        targets[0] = address(handler);
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_SupplyIsConservedAndNeverReminted() public view {
        SIMDTESTToken token = handler.token();
        uint256 balances;
        for (uint256 i; i < 4; ++i) {
            balances += token.balanceOf(handler.actors(i));
        }
        assertEq(balances, token.totalSupply());
        assertEq(token.totalSupply() + handler.burned(), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
    }
}
