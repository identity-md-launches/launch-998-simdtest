// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @dev Only the built-in Foundry cheatcodes used by this self-contained suite.
interface Vm {
    function prank(address sender) external;
    function expectRevert(bytes calldata revertData) external;
    function expectEmit(bool topic1, bool topic2, bool topic3, bool data, address emitter) external;
    function etch(address target, bytes calldata code) external;
    function chainId(uint256 newChainId) external;
}

abstract contract TestBase {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    address internal constant ALICE = address(uint160(uint256(keccak256("test.alice"))));
    address internal constant BOB = address(uint160(uint256(keccak256("test.bob"))));
    address internal constant SPENDER = address(uint160(uint256(keccak256("test.spender"))));
    address internal constant DISTRIBUTOR = address(uint160(uint256(keccak256("test.distributor"))));
    address internal constant MANAGER = 0x000000000004444c5dc75cB358380D2e3dE08A90;
    uint256 internal constant SUPPLY = 1e27;

    error NotEqual(uint256 actual, uint256 expected);

    function assertEq(uint256 actual, uint256 expected) internal pure {
        if (actual != expected) revert NotEqual(actual, expected);
    }

    function assertTrue(bool condition) internal pure {
        require(condition, "assertion failed");
    }
}
