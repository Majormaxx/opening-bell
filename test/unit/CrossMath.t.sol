// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {SqrtPriceMath} from "@uniswap/v4-core/src/libraries/SqrtPriceMath.sol";
import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";
import {CrossMath} from "../../src/libraries/CrossMath.sol";

contract CrossMathHarness {
    function clear(uint160 r, uint128 L, uint256 X, uint256 Y, uint160 lo, uint160 hi)
        external
        pure
        returns (CrossMath.Result memory)
    {
        return CrossMath.clear(r, L, X, Y, lo, hi);
    }
}

contract CrossMathTest is Test {
    uint160 constant R = uint160(1 << 96);
    uint256 constant Q96 = 1 << 96;
    uint160 constant LO = TickMath.MIN_SQRT_PRICE;
    uint160 constant HI = TickMath.MAX_SQRT_PRICE - 1;
    uint256 constant TOL = 1e12; // 1e-6 relative, in assertApproxEqRel units
    /// Expected values below are exact to 18 digits (50-digit Decimal reference); the spec's table rounds to 6.
    uint256 constant EXACT = 1e6; // 1e-12 relative
    uint256 constant ONE = 1e36; // full fill
    CrossMathHarness h;

    function setUp() public {
        h = new CrossMathHarness();
    }

    function _t(CrossMath.Result memory res) internal pure returns (uint256) {
        return FullMath.mulDiv(res.sqrtPriceX96, 1e18, R);
    }

    function _p(CrossMath.Result memory res) internal pure returns (uint256) {
        return FullMath.mulDiv(FullMath.mulDiv(res.sqrtPriceX96, res.sqrtPriceX96, Q96), 1e18, Q96);
    }

    // ---------------------------------------------------------------- Appendix C vectors

    function test_balanced() public view {
        CrossMath.Result memory r = h.clear(R, 1e18, 1e18, 1e18, LO, HI);
        assertApproxEqRel(_t(r), 1e18, TOL);
        assertEq(r.fill0, ONE);
        assertEq(r.fill1, ONE);
        // At the reference the vault trades nothing.
        assertEq(CrossMath.surplus1(R, r.sqrtPriceX96, r.liquidity) < 1e6, true);
    }

    function test_buysOnly() public view {
        CrossMath.Result memory r = h.clear(R, 1e18, 0, 0.21e18, LO, HI);
        assertApproxEqRel(_t(r), 1.178232998312526813e18, EXACT);
        assertApproxEqRel(_p(r), 1.388232998312526813e18, EXACT);
        assertEq(r.fill1, ONE);
        assertApproxEqRel(CrossMath.toAmount0(0.21e18, r.sqrtPriceX96), 0.151271436607015171e18, EXACT);
        assertApproxEqRel(CrossMath.surplus1(R, r.sqrtPriceX96, r.liquidity), 0.031767001687473186e18, EXACT);
    }

    function test_mixed() public view {
        CrossMath.Result memory r = h.clear(R, 2e18, 0.1e18, 0.3e18, LO, HI);
        assertApproxEqRel(_t(r), 1.084149777847795460e18, EXACT);
        assertApproxEqRel(_p(r), 1.175380740807424247e18, EXACT);
        assertApproxEqRel(CrossMath.toAmount0(0.3e18, r.sqrtPriceX96), 0.255236443464196892e18, EXACT);
        assertEq(r.fill0, ONE);
        assertEq(r.fill1, ONE);
    }

    function test_sellsOnly() public view {
        CrossMath.Result memory r = h.clear(R, 1e18, 0.2e18, 0, LO, HI);
        assertApproxEqRel(_t(r), 0.833333333333333333e18, EXACT);
        assertApproxEqRel(_p(r), 0.694444444444444444e18, EXACT);
        assertEq(r.fill0, ONE);
        assertApproxEqRel(CrossMath.toAmount1(0.2e18, r.sqrtPriceX96), 0.138888888888888888e18, EXACT);
        assertApproxEqRel(CrossMath.surplus1(R, r.sqrtPriceX96, r.liquidity), 0.027777777777777777e18, EXACT);
    }

    function test_noVault() public view {
        CrossMath.Result memory r = h.clear(R, 0, 1e18, 4e18, LO, HI);
        assertApproxEqRel(_t(r), 2e18, TOL);
        assertApproxEqRel(_p(r), 4e18, TOL);
        assertEq(r.liquidity, 0);
        assertEq(r.fill0, ONE);
        assertEq(r.fill1, ONE);
    }

    function test_empty() public view {
        CrossMath.Result memory r = h.clear(R, 1e18, 0, 0, LO, HI);
        assertEq(r.sqrtPriceX96, R);
        assertEq(r.fill0, 0);
        assertEq(r.fill1, 0);
    }

    // ---------------------------------------------------------------- edges

    function test_oneSidedNoVaultFillsNothing() public view {
        CrossMath.Result memory r = h.clear(R, 0, 0, 1e18, LO, HI);
        assertEq(r.sqrtPriceX96, R);
        assertEq(r.fill1, 0);
        r = h.clear(R, 0, 1e18, 0, LO, HI);
        assertEq(r.fill0, 0);
    }

    function test_clampHighFillsBuyersProRata() public view {
        uint160 hi = TickMath.getSqrtPriceAtTick(200); // about +2%
        CrossMath.Result memory r = h.clear(R, 1e18, 0, 1e18, LO, hi);
        assertEq(r.sqrtPriceX96, hi);
        // Vault sells only what its curve holds between r and the collar.
        uint256 v0 = SqrtPriceMath.getAmount0Delta(R, hi, 1e18, false);
        uint256 dem0 = CrossMath.toAmount0(1e18, hi);
        assertApproxEqRel(r.fill1, FullMath.mulDiv(v0, ONE, dem0), 1e9);
        assertLt(r.fill1, ONE);
        assertEq(r.fill0, ONE);
    }

    function test_clampLowFillsSellersProRata() public view {
        uint160 lo = TickMath.getSqrtPriceAtTick(-200);
        CrossMath.Result memory r = h.clear(R, 1e18, 1e18, 0, lo, HI);
        assertEq(r.sqrtPriceX96, lo);
        uint256 v0 = SqrtPriceMath.getAmount0Delta(lo, R, 1e18, false);
        assertApproxEqRel(r.fill0, FullMath.mulDiv(v0, ONE, 1e18), 1e9);
        assertEq(r.fill1, ONE);
    }

    function test_hugeBookIgnoresVault() public view {
        CrossMath.Result memory r = h.clear(R, 1, 1e30, 4e30, LO, HI);
        assertEq(r.liquidity, 0);
        assertApproxEqRel(_p(r), 4e18, TOL);
    }

    function test_ratioOutOfRangeReverts() public {
        vm.expectRevert(CrossMath.RatioOutOfRange.selector);
        h.clear(R, 0, 1, 1 << 70, LO, HI);
    }

    // ---------------------------------------------------------------- fuzz

    struct Case {
        uint160 r;
        uint128 L;
        uint256 X;
        uint256 Y;
        uint160 lo;
        uint160 hi;
    }

    function _case(int24 tick, uint128 L, uint256 X, uint256 Y, uint16 collar) internal pure returns (Case memory c) {
        tick = int24(bound(tick, -400_000, 400_000));
        c.r = TickMath.getSqrtPriceAtTick(tick);
        c.L = uint128(bound(L, 1e9, 1e30));
        c.X = bound(X, 0, 1e30);
        c.Y = bound(Y, 0, 1e30);
        collar = uint16(bound(collar, 1, 5000));
        c.lo = TickMath.getSqrtPriceAtTick(tick - int24(uint24(collar)));
        c.hi = TickMath.getSqrtPriceAtTick(tick + int24(uint24(collar)));
    }

    /// Collar containment, fills in range, and the vault trades only in the direction the price moved.
    function testFuzz_bounds(int24 tick, uint128 L, uint256 X, uint256 Y, uint16 collar) public view {
        Case memory c = _case(tick, L, X, Y, collar);
        vm.assume(c.X == 0 || c.Y / c.X < (1 << 64));
        CrossMath.Result memory r = h.clear(c.r, c.L, c.X, c.Y, c.lo, c.hi);
        if (c.X == 0 && c.Y == 0) return;
        assertGe(r.sqrtPriceX96, c.lo);
        assertLe(r.sqrtPriceX96, c.hi);
        assertLe(r.fill0, ONE);
        assertLe(r.fill1, ONE);
        uint256 in0 = FullMath.mulDiv(c.X, r.fill0, ONE);
        uint256 in1 = FullMath.mulDiv(c.Y, r.fill1, ONE);
        uint256 out0 = CrossMath.toAmount0(in1, r.sqrtPriceX96);
        // Vault sells currency0 (out0 > in0) only when the price rose, buys only when it fell. The
        // slack is integer flooring: a few wei of currency0 plus one wei of currency1 at the clearing price.
        uint256 slack = 3 + CrossMath.toAmount0(2, r.sqrtPriceX96);
        if (out0 > in0 + slack) assertGe(r.sqrtPriceX96, c.r);
        if (in0 > out0 + slack) assertLe(r.sqrtPriceX96, c.r);
    }

    /// Unclamped: the clearing identity Y/s^2 = X + L(1/r - 1/s) holds, and both sides fill.
    function testFuzz_identity(int24 tick, uint128 L, uint256 X, uint256 Y) public view {
        tick = int24(bound(tick, -200_000, 200_000));
        uint160 r96 = TickMath.getSqrtPriceAtTick(tick);
        L = uint128(bound(L, 1e15, 1e27));
        // Book sizes comparable to the curve's depth, large enough that wei rounding is negligible.
        uint256 depth0 = FullMath.mulDiv(L, Q96, r96);
        uint256 depth1 = FullMath.mulDiv(L, r96, Q96);
        vm.assume(depth0 > 1e12 && depth1 > 1e12);
        X = bound(X, 0, depth0 / 2);
        Y = bound(Y, 0, depth1 / 2);
        vm.assume(X > 1e9 || Y > 1e9);
        CrossMath.Result memory r = h.clear(r96, L, X, Y, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE - 1);
        uint160 s = r.sqrtPriceX96;
        uint256 lhs = CrossMath.toAmount0(Y, s);
        uint256 vault0 = s >= r96 ? SqrtPriceMath.getAmount0Delta(r96, s, L, false) : 0;
        uint256 vaultBuy0 = s < r96 ? SqrtPriceMath.getAmount0Delta(s, r96, L, false) : 0;
        // Error is a few wei from floors plus a relative term from the Q96 sqrt.
        assertApproxEqAbs(
            lhs + vaultBuy0, X + vault0, (X + vault0 + vaultBuy0) / 1e12 + 8 + CrossMath.toAmount0(4, s)
        );
        // Unclamped, both sides fill except for the resolution of sqrtPriceX96: the vault's capacity
        // is only known to within two sqrt-price steps of currency0 (plus wei floors).
        uint256 step0 = SqrtPriceMath.getAmount0Delta(s, s + 2, L, true) + CrossMath.toAmount0(4, s) + 8;
        if (X > 1e13) assertGe(r.fill0, ONE - FullMath.mulDiv(step0, ONE, X) - 1e24);
        if (lhs > 1e13) assertGe(r.fill1, ONE - FullMath.mulDiv(step0, ONE, lhs) - 1e24);
    }

    /// Wei flooring in currency1, plus the value of two Q96 steps of sqrt price at liquidity L (the
    /// resolution limit of sqrtPriceX96 itself, about L / 2^96 currency1 per step).
    function _slack1(uint160 s, uint128 L) internal pure returns (uint256) {
        return 4 + CrossMath.toAmount1(4, s) + FullMath.mulDiv(L, 2, Q96);
    }

    /// The vault's cross trade at P* is never worse than walking its own curve for the same amount, up to
    /// wei flooring (a few wei of currency0 valued at the clearing price).
    function testFuzz_vaultBeatsCurve(int24 tick, uint128 L, uint256 X, uint256 Y, uint16 collar) public view {
        Case memory c = _case(tick, L, X, Y, collar);
        vm.assume(c.X == 0 || c.Y / c.X < (1 << 64));
        CrossMath.Result memory r = h.clear(c.r, c.L, c.X, c.Y, c.lo, c.hi);
        if (r.liquidity == 0) return;
        uint160 s = r.sqrtPriceX96;
        uint256 in0 = FullMath.mulDiv(c.X, r.fill0, ONE);
        uint256 in1 = FullMath.mulDiv(c.Y, r.fill1, ONE);
        uint256 out0 = CrossMath.toAmount0(in1, s);
        // Signed: on wei-sized books a floor can put either leg a wei past the other.
        int256 d1 = int256(in1) - int256(CrossMath.toAmount1(in0, s)); // currency1 the vault receives
        uint256 slack = _slack1(s, r.liquidity);
        if (out0 > in0) {
            // Vault sold currency0 and must receive at least what its curve gives for that amount.
            uint256 sold = out0 - in0;
            uint160 sc = SqrtPriceMath.getNextSqrtPriceFromAmount0RoundingUp(c.r, r.liquidity, sold, false);
            uint256 curve = SqrtPriceMath.getAmount1Delta(c.r, sc, r.liquidity, false);
            assertGe(d1 + int256(slack), int256(curve));
        } else if (in0 > out0) {
            // Vault bought currency0 and must pay no more than its curve would.
            uint256 bought = in0 - out0;
            uint160 sc = SqrtPriceMath.getNextSqrtPriceFromAmount0RoundingUp(c.r, r.liquidity, bought, true);
            uint256 curve = SqrtPriceMath.getAmount1Delta(sc, c.r, r.liquidity, true);
            assertLe(-d1, int256(curve + slack));
        }
    }
}
