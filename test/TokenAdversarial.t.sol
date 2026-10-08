// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {SIMDTESTToken} from "../src/SIMDTESTToken.sol";
import {TestBase} from "./support/TestBase.sol";

contract TokenAdversarialTest is TestBase {
    SIMDTESTToken private token;

    function setUp() public {
        vm.chainId(1);
        token = new SIMDTESTToken();
    }

    function test_AdminSelectorsRejectWellFormedArgumentsFromEveryLaunchRole() public {
        // In particular, encode bool arguments as true/false, so a hypothetical setter
        // cannot pass this test just because its ABI decoder rejects a noncanonical bool.
        bytes[] memory calls = new bytes[](33);
        calls[0] = abi.encodeWithSignature("owner()");
        calls[1] = abi.encodeWithSignature("admin()");
        calls[2] = abi.encodeWithSignature("mint(address,uint256)", ALICE, 1e18);
        calls[3] = abi.encodeWithSignature("mint(uint256)", 1e18);
        calls[4] = abi.encodeWithSignature("mint()");
        calls[5] = abi.encodeWithSignature("initialize(address)", ALICE);
        calls[6] = abi.encodeWithSignature("transferOwnership(address)", ALICE);
        calls[7] = abi.encodeWithSignature("renounceOwnership()");
        calls[8] = abi.encodeWithSignature("setOwner(address)", ALICE);
        calls[9] = abi.encodeWithSignature("setMinter(address)", ALICE);
        calls[10] = abi.encodeWithSignature("upgradeTo(address)", ALICE);
        calls[11] = abi.encodeWithSignature("pause()");
        calls[12] = abi.encodeWithSignature("unpause()");
        calls[13] = abi.encodeWithSignature("blacklist(address)", ALICE);
        calls[14] = abi.encodeWithSignature("freeze(address)", ALICE);
        calls[15] = abi.encodeWithSignature("burn(uint256)", 1);
        calls[16] = abi.encodeWithSignature("burnFrom(address,uint256)", ALICE, 1);
        calls[17] = abi.encodeWithSignature("seize(address)", ALICE);
        calls[18] = abi.encodeWithSignature("setPoolManager(address)", BOB);
        calls[19] = abi.encodeWithSignature("setFee(uint256)", 0);
        calls[20] = abi.encodeWithSignature("setBuyBurnBps(uint256)", 0);
        calls[21] = abi.encodeWithSignature("setExempt(address,bool)", ALICE, true);
        calls[22] = abi.encodeWithSignature("setBlacklist(address,bool)", ALICE, true);
        calls[23] = abi.encodeWithSignature("setBlocked(address,bool)", ALICE, true);
        calls[24] = abi.encodeWithSignature("setTransfersEnabled(bool)", false);
        calls[25] = abi.encodeWithSignature("setFeeExempt(address,bool)", ALICE, true);
        calls[26] = abi.encodeWithSignature("grantRole(bytes32,address)", bytes32(0), ALICE);
        calls[27] = abi.encodeWithSignature("setBurnRate(uint256)", 0);
        calls[28] = abi.encodeWithSignature("setAdmin(address)", ALICE);
        calls[29] = abi.encodeWithSignature("issue(uint256)", 1e18);
        calls[30] = abi.encodeWithSignature("disableTransfers()");
        calls[31] = abi.encodeWithSignature("lock(address)", ALICE);
        calls[32] = abi.encodeWithSignature("freezeAccount(address)", ALICE);

        token.transfer(MANAGER, 10_000);
        vm.prank(MANAGER);
        token.transfer(ALICE, 10_000);
        uint256 supplyAfterBurn = token.totalSupply();
        address[4] memory callers = [address(this), MANAGER, DISTRIBUTOR, BOB];
        for (uint256 i; i < callers.length; ++i) {
            for (uint256 j; j < calls.length; ++j) {
                vm.prank(callers[i]);
                (bool ok,) = address(token).call(calls[j]);
                assertTrue(!ok);
                assertEq(token.totalSupply(), supplyAfterBurn);
                assertEq(token.balanceOf(ALICE), 9_900);
            }
        }
        assertTrue(token.POOL_MANAGER() == MANAGER);
        assertEq(token.BUY_BURN_BPS(), 100);
        vm.prank(ALICE);
        token.transfer(BOB, 9_900);
        assertEq(token.balanceOf(BOB), 9_900);
        token.transfer(MANAGER, 100);
        vm.prank(MANAGER);
        token.transfer(ALICE, 100);
        assertEq(token.balanceOf(ALICE), 99);
        assertEq(token.totalSupply(), supplyAfterBurn - 1);
    }

    function test_ExhaustedBuyAllowanceCannotBeReplayedAndOtherSpenderIsUnaffected() public {
        token.transfer(MANAGER, 10_000);
        vm.prank(MANAGER);
        token.approve(SPENDER, 10_000);
        vm.prank(MANAGER);
        token.approve(BOB, type(uint256).max);

        vm.prank(SPENDER);
        token.transferFrom(MANAGER, ALICE, 6_000);
        assertEq(token.allowance(MANAGER, SPENDER), 4_000);
        assertEq(token.balanceOf(ALICE), 5_940);
        vm.prank(SPENDER);
        token.transferFrom(MANAGER, ALICE, 4_000);
        assertEq(token.allowance(MANAGER, SPENDER), 0);
        assertEq(token.balanceOf(ALICE), 9_900);
        assertEq(token.totalSupply(), SUPPLY - 100);

        // Replenishing the pool does not replenish an exhausted approval.
        token.transfer(MANAGER, 100);
        vm.expectRevert(abi.encodeWithSelector(SIMDTESTToken.ERC20InsufficientAllowance.selector, SPENDER, 0, 100));
        vm.prank(SPENDER);
        token.transferFrom(MANAGER, ALICE, 100);
        assertEq(token.balanceOf(MANAGER), 100);
        assertEq(token.allowance(MANAGER, BOB), type(uint256).max);
        vm.prank(BOB);
        token.transferFrom(MANAGER, ALICE, 100);
        assertEq(token.balanceOf(ALICE), 9_999);
        assertEq(token.totalSupply(), SUPPLY - 101);
        assertEq(token.allowance(MANAGER, BOB), type(uint256).max);
    }

    function test_OnlyExactManagerAddressIsTaxedAndRecipientsHaveNoExemptions() public {
        address[2] memory neighbors = [address(uint160(MANAGER) - 1), address(uint160(MANAGER) + 1)];
        for (uint256 i; i < neighbors.length; ++i) {
            token.transfer(neighbors[i], 100);
            vm.prank(neighbors[i]);
            token.transfer(ALICE, 100);
        }
        assertEq(token.balanceOf(ALICE), 200);
        assertEq(token.totalSupply(), SUPPLY);

        address[4] memory recipients = [address(this), DISTRIBUTOR, address(token), ALICE];
        token.transfer(MANAGER, 400);
        for (uint256 i; i < recipients.length; ++i) {
            uint256 beforeBalance = token.balanceOf(recipients[i]);
            vm.prank(MANAGER);
            token.transfer(recipients[i], 100);
            assertEq(token.balanceOf(recipients[i]), beforeBalance + 99);
            assertEq(token.totalSupply(), SUPPLY - i - 1);
        }
        assertEq(token.balanceOf(MANAGER), 0);
        assertEq(token.balanceOf(address(0)), 0);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_ArbitraryWalletsTransferWithoutFees(address from, address to, uint256 seed) public {
        if (from == address(0) || from == MANAGER || from == address(this)) from = ALICE;
        if (to == address(0)) to = BOB;
        uint256 amount = seed % (SUPPLY + 1);
        token.transfer(from, amount);
        uint256 recipientBefore = token.balanceOf(to);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        assertEq(token.balanceOf(from), from == to ? amount : 0);
        assertEq(token.balanceOf(to), recipientBefore + (from == to ? 0 : amount));
        assertEq(token.totalSupply(), SUPPLY);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_FailedDelegatedBuyPreservesEveryBalanceAndAllowance(uint256 seed, bool insufficientBalance)
        public
    {
        uint256 gross = 100 + seed % (SUPPLY - 99);
        uint256 held = insufficientBalance ? gross - 1 : gross;
        uint256 approved = insufficientBalance ? gross : gross - gross / 100;
        token.transfer(MANAGER, held);
        vm.prank(MANAGER);
        token.approve(SPENDER, approved);
        bytes memory reason = insufficientBalance
            ? abi.encodeWithSelector(SIMDTESTToken.ERC20InsufficientBalance.selector, MANAGER, held, gross)
            : abi.encodeWithSelector(SIMDTESTToken.ERC20InsufficientAllowance.selector, SPENDER, approved, gross);
        vm.expectRevert(reason);
        vm.prank(SPENDER);
        token.transferFrom(MANAGER, ALICE, gross);
        assertEq(token.balanceOf(MANAGER), held);
        assertEq(token.balanceOf(address(this)), SUPPLY - held);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(SPENDER), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.allowance(MANAGER, SPENDER), approved);
        assertEq(token.totalSupply(), SUPPLY);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_DelegatedSelfTransferSpendsGrossAllowance(uint256 seed, bool fromManager, bool unlimited) public {
        uint256 amount = seed % (SUPPLY + 1);
        address holder = fromManager ? MANAGER : ALICE;
        token.transfer(holder, amount);
        vm.prank(holder);
        token.approve(SPENDER, unlimited ? type(uint256).max : amount);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(holder, holder, amount));
        uint256 fee = fromManager ? amount / 100 : 0;
        assertEq(token.balanceOf(holder), amount - fee);
        assertEq(token.balanceOf(SPENDER), 0);
        assertEq(token.allowance(holder, SPENDER), unlimited ? type(uint256).max : 0);
        assertEq(token.totalSupply(), SUPPLY - fee);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_DelegatedZeroTransferCannotSpendOrBurn(uint256 allowanceSeed, bool fromManager) public {
        address holder = fromManager ? MANAGER : ALICE;
        token.transfer(holder, 100);
        vm.prank(holder);
        token.approve(SPENDER, allowanceSeed);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(holder, BOB, 0));
        assertEq(token.allowance(holder, SPENDER), allowanceSeed);
        assertEq(token.balanceOf(holder), 100);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
