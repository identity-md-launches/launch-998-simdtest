// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {SIMDTESTToken} from "../src/SIMDTESTToken.sol";
import {TestBase} from "./support/TestBase.sol";
import {PoolManager} from "v4-core/src/PoolManager.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {ModifyLiquidityParams, SwapParams} from "v4-core/src/types/PoolOperation.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {FullMath} from "v4-core/src/libraries/FullMath.sol";

interface Transferable {
    function transfer(address to, uint256 amount) external returns (bool);
}

/// @dev Test-only pair token; only SIMDTEST and the v4 settlement behavior are under test.
contract PairFixture {
    mapping(address => uint256) public balanceOf;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

/// @dev Test-only unlock caller that settles actual v4 deltas, without router-specific behavior.
contract PoolActor is IUnlockCallback {
    IPoolManager private immutable manager;
    PoolKey private key;

    constructor(IPoolManager manager_, PoolKey memory key_) {
        manager = manager_;
        key = key_;
    }

    function seed(int24 lower, int24 upper, uint128 liquidity) external returns (BalanceDelta) {
        bytes memory params = abi.encode(ModifyLiquidityParams(lower, upper, int256(uint256(liquidity)), bytes32(0)));
        return abi.decode(manager.unlock(abi.encode(false, params, false)), (BalanceDelta));
    }

    function swap(bool zeroForOne, int256 amount, bool underpay) external returns (BalanceDelta) {
        uint160 limit = zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1;
        bytes memory params = abi.encode(SwapParams(zeroForOne, amount, limit));
        return abi.decode(manager.unlock(abi.encode(true, params, underpay)), (BalanceDelta));
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        require(msg.sender == address(manager), "only manager");
        (bool isSwap, bytes memory params, bool underpay) = abi.decode(data, (bool, bytes, bool));
        BalanceDelta delta;
        if (isSwap) {
            delta = manager.swap(key, abi.decode(params, (SwapParams)), "");
        } else {
            (delta,) = manager.modifyLiquidity(key, abi.decode(params, (ModifyLiquidityParams)), "");
        }
        _settle(key.currency0, delta.amount0(), underpay);
        _settle(key.currency1, delta.amount1(), underpay);
        return abi.encode(delta);
    }

    function _settle(Currency currency, int128 delta, bool underpay) private {
        if (delta < 0) {
            uint256 owed = uint256(-int256(delta));
            uint256 payment = underpay ? owed - 1 : owed;
            manager.sync(currency);
            require(Transferable(Currency.unwrap(currency)).transfer(address(manager), payment), "payment failed");
            require(manager.settle() == payment, "inbound transfer arrived short");
        } else if (delta > 0) {
            manager.take(currency, address(this), uint256(int256(delta)));
        }
    }
}

contract UniswapV4Test is TestBase {
    address private constant PAIRED = 0xD34a99Bc0f67aE1bbd63C660e6d0b0dd03E263B7;
    uint160 private constant OPENING_PRICE = 125270724187523965593206900;
    uint256 private constant Q96 = 1 << 96;
    SIMDTESTToken private token;
    PairFixture private pair;
    PoolActor private trader;
    bool private tokenIsZero;

    function test_SeedBuyAndSellWithTokenAsCurrency0() public {
        _prepare(true);
        _roundTrip();
    }

    function test_SeedBuyAndSellWithTokenAsCurrency1() public {
        _prepare(false);
        _roundTrip();
    }

    function test_UnsettledBuyRevertsAndRollsBackBurn() public {
        _prepare(true);
        uint256 managerBefore = token.balanceOf(MANAGER);
        uint256 pairBefore = pair.balanceOf(address(trader));
        vm.expectRevert(abi.encodeWithSelector(IPoolManager.CurrencyNotSettled.selector));
        trader.swap(false, -0.01 ether, true);
        assertEq(token.balanceOf(address(trader)), 0);
        assertEq(token.balanceOf(MANAGER), managerBefore);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(pair.balanceOf(address(trader)), pairBefore);
    }

    function test_UnsettledSellRevertsAndPreservesBalances() public {
        _prepare(false);
        trader.swap(true, -0.01 ether, false);
        uint256 bought = token.balanceOf(address(trader));
        uint256 supplyBefore = token.totalSupply();
        uint256 managerBefore = token.balanceOf(MANAGER);
        uint256 pairBefore = pair.balanceOf(address(trader));
        vm.expectRevert(abi.encodeWithSelector(IPoolManager.CurrencyNotSettled.selector));
        trader.swap(false, -int256(bought), true);
        assertEq(token.balanceOf(address(trader)), bought);
        assertEq(token.balanceOf(MANAGER), managerBefore);
        assertEq(token.totalSupply(), supplyBefore);
        assertEq(pair.balanceOf(address(trader)), pairBefore);
    }

    function _prepare(bool tokenAsZero) private {
        vm.chainId(1);
        // Execute the manager constructor at the pinned address to preserve NoDelegateCall's immutable.
        vm.etch(MANAGER, abi.encodePacked(type(PoolManager).creationCode, abi.encode(address(this))));
        (bool built, bytes memory runtime) = MANAGER.call("");
        assertTrue(built && runtime.length != 0);
        vm.etch(MANAGER, runtime);
        IPoolManager manager = IPoolManager(MANAGER);
        vm.etch(PAIRED, address(new PairFixture()).code);
        pair = PairFixture(PAIRED);

        // Each test intentionally covers one deployed currency order.
        for (uint256 i; i < 100; ++i) {
            token = new SIMDTESTToken{salt: bytes32(i)}();
            if ((address(token) < PAIRED) == tokenAsZero) break;
        }
        tokenIsZero = address(token) < PAIRED;
        assertTrue(tokenIsZero == tokenAsZero);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        token.transfer(DISTRIBUTOR, SUPPLY / 10);

        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(tokenIsZero ? address(token) : PAIRED),
            currency1: Currency.wrap(tokenIsZero ? PAIRED : address(token)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });
        uint160 price = tokenIsZero ? OPENING_PRICE : uint160((uint256(1) << 192) / OPENING_PRICE);
        int24 tick = manager.initialize(key, price);
        (int24 lower, int24 upper, uint128 liquidity) = _singleSidedPosition(tick);
        PoolActor provider = new PoolActor(manager, key);
        uint256 allocation = SUPPLY * 9 / 10;
        token.transfer(address(provider), allocation);
        BalanceDelta seedDelta = provider.seed(lower, upper, liquidity);
        int128 tokenDelta = tokenIsZero ? seedDelta.amount0() : seedDelta.amount1();
        int128 pairDelta = tokenIsZero ? seedDelta.amount1() : seedDelta.amount0();
        assertTrue(tokenDelta < 0);
        assertEq(uint256(int256(pairDelta)), 0);
        uint256 seeded = uint256(-int256(tokenDelta));
        assertTrue(seeded <= allocation && allocation - seeded < 1e12);
        assertEq(token.balanceOf(MANAGER), seeded);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(DISTRIBUTOR), SUPPLY / 10);
        trader = new PoolActor(manager, key);
        pair.mint(address(trader), 10 ether);
    }

    function _singleSidedPosition(int24 tick) private view returns (int24 lower, int24 upper, uint128 liquidity) {
        int24 aligned = (tick / 60) * 60;
        if (aligned > tick) aligned -= 60;
        lower = tokenIsZero ? aligned + 60 : int24(-887220);
        upper = tokenIsZero ? int24(887220) : aligned;
        uint160 sqrtLower = TickMath.getSqrtPriceAtTick(lower);
        uint160 sqrtUpper = TickMath.getSqrtPriceAtTick(upper);
        uint256 allocation = SUPPLY * 9 / 10;
        uint256 computed = tokenIsZero
            ? FullMath.mulDiv(FullMath.mulDiv(allocation, sqrtLower, Q96), sqrtUpper, sqrtUpper - sqrtLower)
            : FullMath.mulDiv(allocation, Q96, sqrtUpper - sqrtLower);
        assertTrue(computed > 1 && computed <= type(uint128).max);
        liquidity = uint128(computed - 1);
    }

    function _roundTrip() private {
        uint256 managerBefore = token.balanceOf(MANAGER);
        BalanceDelta buy = trader.swap(!tokenIsZero, -0.01 ether, false);
        int128 output = tokenIsZero ? buy.amount0() : buy.amount1();
        assertTrue(output > 0);
        uint256 gross = uint256(int256(output));
        uint256 bought = token.balanceOf(address(trader));
        assertEq(bought, gross - gross / 100);
        assertEq(token.balanceOf(MANAGER), managerBefore - gross);
        assertEq(token.totalSupply(), SUPPLY - gross / 100);
        uint256 supplyAfterBuy = token.totalSupply();
        uint256 pairBeforeSell = pair.balanceOf(address(trader));
        uint256 managerBeforeSell = token.balanceOf(MANAGER);
        trader.swap(tokenIsZero, -int256(bought), false);
        assertEq(token.balanceOf(address(trader)), 0);
        assertEq(token.balanceOf(MANAGER), managerBeforeSell + bought);
        assertTrue(pair.balanceOf(address(trader)) > pairBeforeSell);
        assertEq(token.totalSupply(), supplyAfterBuy);
    }
}
