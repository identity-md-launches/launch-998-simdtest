// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {SIMDTESTToken} from "../src/SIMDTESTToken.sol";
import {TestBase} from "./support/TestBase.sol";

contract TokenDeployer {
    function deploy() external returns (SIMDTESTToken) {
        return new SIMDTESTToken();
    }
}

contract SIMDTESTTokenTest is TestBase {
    SIMDTESTToken internal token;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed account, address indexed spender, uint256 value);

    function setUp() public {
        token = new SIMDTESTToken();
    }

    function test_InitialSupplyAndConstants() public view {
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(MANAGER), 0);
        assertEq(token.balanceOf(DISTRIBUTOR), 0);
        assertEq(token.decimals(), 18);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
        assertEq(token.BUY_BURN_BPS(), 100);
        assertEq(token.BPS_DENOMINATOR(), 10_000);
        assertTrue(token.POOL_MANAGER() == MANAGER);
        assertTrue(keccak256(bytes(token.name())) == keccak256("SIMDTEST"));
        assertTrue(keccak256(bytes(token.symbol())) == keccak256("SIMDTEST"));
    }

    function test_ContractDeployerReceivesEverythingRatherThanTransactionOrigin() public {
        TokenDeployer factory = new TokenDeployer();
        SIMDTESTToken deployed = factory.deploy();
        assertEq(deployed.balanceOf(address(factory)), SUPPLY);
        assertEq(deployed.balanceOf(address(this)), 0);
        assertEq(deployed.totalSupply(), SUPPLY);
    }

    function test_FactoryDistributionAndSwarmClaimAreUntaxed() public {
        uint256 swarm = SUPPLY / 10;
        assertTrue(token.transfer(DISTRIBUTOR, swarm));
        assertEq(token.balanceOf(address(this)), 900_000_000e18);
        assertTrue(token.transfer(MANAGER, SUPPLY - swarm));
        vm.prank(DISTRIBUTOR);
        assertTrue(token.transfer(ALICE, swarm));
        assertEq(token.balanceOf(MANAGER), 900_000_000e18);
        assertEq(token.balanceOf(ALICE), 100_000_000e18);
        assertEq(token.balanceOf(DISTRIBUTOR), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_BuyBurnsOnePercentAndEmitsSeparateBurnAndDelivery() public {
        token.transfer(MANAGER, 1000e18);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(MANAGER, address(0), 10e18);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(MANAGER, ALICE, 990e18);
        vm.prank(MANAGER);
        assertTrue(token.transfer(ALICE, 1000e18));
        assertEq(token.balanceOf(MANAGER), 0);
        assertEq(token.balanceOf(ALICE), 990e18);
        assertEq(token.totalSupply(), SUPPLY - 10e18);
        assertEq(token.balanceOf(address(0)), 0);
    }

    function test_WalletTransfersAndSellsHaveNoFee() public {
        token.transfer(ALICE, 1000e18);
        vm.prank(ALICE);
        token.transfer(BOB, 700e18);
        vm.prank(BOB);
        token.transfer(MANAGER, 700e18);
        assertEq(token.balanceOf(ALICE), 300e18);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.balanceOf(MANAGER), 700e18);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_BurnRoundingAndZeroTransfers() public {
        token.transfer(MANAGER, 1000);
        uint256[7] memory amounts = [uint256(0), 1, 99, 100, 101, 199, 200];
        uint256[7] memory burns = [uint256(0), 0, 0, 1, 1, 1, 2];
        for (uint256 i; i < amounts.length; ++i) {
            uint256 beforeSupply = token.totalSupply();
            uint256 beforeBalance = token.balanceOf(ALICE);
            vm.prank(MANAGER);
            token.transfer(ALICE, amounts[i]);
            assertEq(beforeSupply - token.totalSupply(), burns[i]);
            assertEq(token.balanceOf(ALICE) - beforeBalance, amounts[i] - burns[i]);
        }
    }

    function test_ZeroTransferFromUnfundedWalletEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(ALICE, BOB, 0);
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 0));
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_WalletSelfTransferDoesNotChangeBalanceOrSupply() public {
        token.transfer(ALICE, 1000e18);
        vm.prank(ALICE);
        token.transfer(ALICE, 1000e18);
        assertEq(token.balanceOf(ALICE), 1000e18);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_PoolManagerSelfTransferStillBurns() public {
        token.transfer(MANAGER, 1000e18);
        vm.prank(MANAGER);
        token.transfer(MANAGER, 1000e18);
        assertEq(token.balanceOf(MANAGER), 990e18);
        assertEq(token.totalSupply(), SUPPLY - 10e18);
    }

    function test_BuyHasNoDeployerExemption() public {
        token.transfer(MANAGER, 1000e18);
        vm.prank(MANAGER);
        token.transfer(address(this), 1000e18);
        assertEq(token.balanceOf(address(this)), SUPPLY - 10e18);
        assertEq(token.totalSupply(), SUPPLY - 10e18);
    }

    function test_ApproveOverwriteAndRevoke() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), SPENDER, 100);
        assertTrue(token.approve(SPENDER, 100));
        token.approve(SPENDER, 30);
        assertEq(token.allowance(address(this), SPENDER), 30);
        token.approve(SPENDER, 0);
        vm.expectRevert(abi.encodeWithSelector(SIMDTESTToken.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 1);
    }

    function test_TransferFromBuyConsumesGrossAllowance() public {
        token.transfer(MANAGER, 1000e18);
        vm.prank(MANAGER);
        token.approve(SPENDER, 1000e18);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(MANAGER, ALICE, 1000e18));
        assertEq(token.allowance(MANAGER, SPENDER), 0);
        assertEq(token.balanceOf(MANAGER), 0);
        assertEq(token.balanceOf(ALICE), 990e18);
        assertEq(token.totalSupply(), SUPPLY - 10e18);
    }

    function test_TransferFromWalletAndSellAreUntaxed() public {
        token.transfer(ALICE, 1000e18);
        vm.prank(ALICE);
        token.approve(SPENDER, 1000e18);
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, 400e18);
        assertEq(token.allowance(ALICE, SPENDER), 600e18);
        vm.prank(SPENDER);
        token.transferFrom(ALICE, MANAGER, 600e18);
        assertEq(token.allowance(ALICE, SPENDER), 0);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 400e18);
        assertEq(token.balanceOf(MANAGER), 600e18);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ManagerAsSpenderDoesNotTaxWalletSource() public {
        token.transfer(ALICE, 1000e18);
        vm.prank(ALICE);
        token.approve(MANAGER, 1000e18);
        vm.prank(MANAGER);
        token.transferFrom(ALICE, BOB, 1000e18);
        assertEq(token.balanceOf(BOB), 1000e18);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_UnlimitedAllowanceRemainsUnlimited() public {
        token.transfer(MANAGER, 1000e18);
        vm.prank(MANAGER);
        token.approve(SPENDER, type(uint256).max);
        vm.prank(SPENDER);
        token.transferFrom(MANAGER, ALICE, 1000e18);
        assertEq(token.allowance(MANAGER, SPENDER), type(uint256).max);
        assertEq(token.balanceOf(ALICE), 990e18);
    }

    function test_BuyCannotUseOnlyNetAllowance() public {
        token.transfer(MANAGER, 1000e18);
        vm.prank(MANAGER);
        token.approve(SPENDER, 990e18);
        vm.expectRevert(
            abi.encodeWithSelector(SIMDTESTToken.ERC20InsufficientAllowance.selector, SPENDER, 990e18, 1000e18)
        );
        vm.prank(SPENDER);
        token.transferFrom(MANAGER, ALICE, 1000e18);
        assertEq(token.allowance(MANAGER, SPENDER), 990e18);
        assertEq(token.balanceOf(MANAGER), 1000e18);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_FailedBuyRollsBackAllowanceAndBurn() public {
        token.transfer(MANAGER, 990e18);
        vm.prank(MANAGER);
        token.approve(SPENDER, 1000e18);
        vm.expectRevert(
            abi.encodeWithSelector(SIMDTESTToken.ERC20InsufficientBalance.selector, MANAGER, 990e18, 1000e18)
        );
        vm.prank(SPENDER);
        token.transferFrom(MANAGER, ALICE, 1000e18);
        assertEq(token.allowance(MANAGER, SPENDER), 1000e18);
        assertEq(token.balanceOf(MANAGER), 990e18);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ZeroReceiverRevertsWithoutBurnOrAllowanceLoss() public {
        token.transfer(MANAGER, 1000e18);
        vm.prank(MANAGER);
        token.approve(SPENDER, 1000e18);
        vm.expectRevert(abi.encodeWithSelector(SIMDTESTToken.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(SPENDER);
        token.transferFrom(MANAGER, address(0), 1000e18);
        assertEq(token.balanceOf(MANAGER), 1000e18);
        assertEq(token.allowance(MANAGER, SPENDER), 1000e18);
        assertEq(token.totalSupply(), SUPPLY);
        vm.expectRevert(abi.encodeWithSelector(SIMDTESTToken.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 0);
    }

    function test_ZeroSourceCannotTransferEvenZero() public {
        vm.expectRevert(abi.encodeWithSelector(SIMDTESTToken.ERC20InvalidSender.selector, address(0)));
        token.transferFrom(address(0), ALICE, 0);
    }

    function test_ZeroSpenderReverts() public {
        vm.expectRevert(abi.encodeWithSelector(SIMDTESTToken.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 1);
    }

    function test_UnauthorizedTransferFromCannotMoveHolderBalance() public {
        token.transfer(ALICE, 1000e18);
        vm.expectRevert(abi.encodeWithSelector(SIMDTESTToken.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(ALICE, address(this), 1);
        assertEq(token.balanceOf(ALICE), 1000e18);
    }

    function test_InsufficientBalanceAndMaxAmountRevert() public {
        vm.expectRevert(abi.encodeWithSelector(SIMDTESTToken.ERC20InsufficientBalance.selector, ALICE, 0, 1));
        vm.prank(ALICE);
        token.transfer(BOB, 1);
        token.transfer(MANAGER, SUPPLY);
        vm.expectRevert(
            abi.encodeWithSelector(SIMDTESTToken.ERC20InsufficientBalance.selector, MANAGER, SUPPLY, type(uint256).max)
        );
        vm.prank(MANAGER);
        token.transfer(ALICE, type(uint256).max);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_NoAdminMintOrPrivilegedBalanceFunctions() public {
        string[23] memory signatures = [
            "owner()",
            "admin()",
            "mint(address,uint256)",
            "mint(uint256)",
            "mint()",
            "issue(uint256)",
            "transferOwnership(address)",
            "renounceOwnership()",
            "setOwner(address)",
            "setMinter(address)",
            "initialize(address)",
            "upgradeTo(address)",
            "pause()",
            "unpause()",
            "blacklist(address)",
            "freeze(address)",
            "burn(uint256)",
            "burnFrom(address,uint256)",
            "seize(address)",
            "setPoolManager(address)",
            "setFee(uint256)",
            "setBuyBurnBps(uint256)",
            "setExempt(address,bool)"
        ];
        token.transfer(ALICE, 1000e18);
        for (uint256 i; i < signatures.length; ++i) {
            bytes memory data = abi.encodeWithSignature(signatures[i], ALICE, type(uint256).max);
            (bool ok,) = address(token).call(data);
            assertTrue(!ok);
            vm.prank(BOB);
            (ok,) = address(token).call(data);
            assertTrue(!ok);
        }
        assertEq(token.balanceOf(ALICE), 1000e18);
        assertEq(token.totalSupply(), SUPPLY);
        assertTrue(token.POOL_MANAGER() == MANAGER);
        vm.prank(ALICE);
        token.transfer(BOB, 1000e18);
        assertEq(token.balanceOf(BOB), 1000e18);
    }

    function test_RuntimeHasNoForbiddenOpcodes() public view {
        bytes memory runtime = address(token).code;
        assertTrue(runtime.length != 0 && runtime.length <= 24_576);
        for (uint256 i; i < runtime.length; ++i) {
            uint8 op = uint8(runtime[i]);
            if (op >= 0x60 && op <= 0x7f) {
                i += op - 0x5f;
            } else {
                assertTrue(op != 0xf2 && op != 0xf4 && op != 0xff);
            }
        }
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_BuyConservesGrossAmountAndBurn(uint256 rawAmount, bool delegated) public {
        uint256 amount = rawAmount % (SUPPLY + 1);
        token.transfer(MANAGER, SUPPLY);
        if (delegated) {
            vm.prank(MANAGER);
            token.approve(SPENDER, amount);
            vm.prank(SPENDER);
            token.transferFrom(MANAGER, ALICE, amount);
            assertEq(token.allowance(MANAGER, SPENDER), 0);
        } else {
            vm.prank(MANAGER);
            token.transfer(ALICE, amount);
        }
        uint256 burned = SUPPLY - token.totalSupply();
        assertEq(token.balanceOf(MANAGER), SUPPLY - amount);
        assertEq(token.balanceOf(ALICE) + burned, amount);
        assertTrue(burned * 100 <= amount && amount - burned * 100 < 100);
        assertEq(token.balanceOf(ALICE) + token.balanceOf(MANAGER), token.totalSupply());
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_WalletAndSellPreserveFullSupply(uint256 rawAmount, bool sell) public {
        uint256 amount = rawAmount % (SUPPLY + 1);
        address recipient = sell ? MANAGER : BOB;
        token.transfer(ALICE, amount);
        vm.prank(ALICE);
        token.transfer(recipient, amount);
        assertEq(token.balanceOf(recipient), amount);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
