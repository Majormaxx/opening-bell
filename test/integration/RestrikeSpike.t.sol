// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IUnlockCallback} from "@uniswap/v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {SwapParams, ModifyLiquidityParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";

/// Spike T0: with all liquidity removed, a price-limited swap moves spot to the limit exactly with a
/// zero balance delta. The hook's re-strike depends on this.
contract RestrikeSpikeTest is Test, Deployers, IUnlockCallback {
    using StateLibrary for *;

    function setUp() public {
        deployFreshManagerAndRouters();
        deployMintAndApprove2Currencies();
        (key,) = initPool(currency0, currency1, IHooks(address(0)), 3000, SQRT_PRICE_1_1);
        ModifyLiquidityParams memory p =
            ModifyLiquidityParams({tickLower: -600, tickUpper: 600, liquidityDelta: 1e18, salt: 0});
        modifyLiquidityRouter.modifyLiquidity(key, p, "");
        p.liquidityDelta = -1e18;
        modifyLiquidityRouter.modifyLiquidity(key, p, "");
        assertEq(manager.getLiquidity(key.toId()), 0);
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        uint160 target = abi.decode(data, (uint160));
        (uint160 cur,,,) = manager.getSlot0(key.toId());
        BalanceDelta d = manager.swap(
            key, SwapParams({zeroForOne: target < cur, amountSpecified: -1, sqrtPriceLimitX96: target}), ""
        );
        return abi.encode(d);
    }

    function _restrike(uint160 target) internal returns (BalanceDelta d) {
        d = abi.decode(manager.unlock(abi.encode(target)), (BalanceDelta));
    }

    function test_T0_upFivePercent() public {
        uint160 target = TickMath.getSqrtPriceAtTick(488); // about +5%
        BalanceDelta d = _restrike(target);
        (uint160 after_, int24 tick,,) = manager.getSlot0(key.toId());
        assertEq(BalanceDelta.unwrap(d), 0);
        assertEq(after_, target);
        assertEq(tick, 488);
    }

    function test_T0_downFivePercent() public {
        uint160 target = TickMath.getSqrtPriceAtTick(-513) + 12345; // off-tick target
        BalanceDelta d = _restrike(target);
        (uint160 after_,,,) = manager.getSlot0(key.toId());
        assertEq(BalanceDelta.unwrap(d), 0);
        assertEq(after_, target);
    }

    function test_T0_largeGapAcrossWords() public {
        uint160 target = TickMath.getSqrtPriceAtTick(60_000);
        BalanceDelta d = _restrike(target);
        (uint160 after_,,,) = manager.getSlot0(key.toId());
        assertEq(BalanceDelta.unwrap(d), 0);
        assertEq(after_, target);
        uint256 g = gasleft();
        _restrike(TickMath.getSqrtPriceAtTick(-60_000));
        assertLt(g - gasleft(), 500_000);
    }

    function test_T0_nonEmptyPoolTrades() public {
        modifyLiquidityRouter.modifyLiquidity(
            key, ModifyLiquidityParams({tickLower: -600, tickUpper: 600, liquidityDelta: 1e18, salt: 0}), ""
        );
        // With liquidity present the 1-wei swap trades, leaves a delta, and unlock fails to settle.
        try manager.unlock(abi.encode(TickMath.getSqrtPriceAtTick(488))) {
            fail();
        } catch (bytes memory err) {
            assertEq(bytes4(err), bytes4(keccak256("CurrencyNotSettled()")));
        }
    }
}
