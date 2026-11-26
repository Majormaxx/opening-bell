// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";
import {SqrtPriceMath} from "@uniswap/v4-core/src/libraries/SqrtPriceMath.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";

/// @notice Uniform clearing price for an opening cross, with the vault's liquidity absorbing the imbalance.
/// @dev Pool orientation throughout: prices are currency1 per currency0, as sqrt Q64.96.
/// X is currency0 offered (orders paying currency0, wanting currency1), Y is currency1 offered.
/// The vault posts L liquidity starting at the reference sqrt price r. At clearing sqrt price s, the
/// currency0 the Y side buys (Y / s^2) equals what the X side offers plus what the vault sells
/// moving along its curve from r to s:
///     Y / s^2 = X + L (1/r - 1/s)
/// With a = X r / L, b = Y / (L r) and t = s / r this becomes (a+1) t^2 - t - b = 0, so
///     t = (1 + sqrt(1 + 4 (a+1) b)) / (2 (a+1)).
/// The vault fills the whole imbalance at s itself, not along its curve, so it earns
/// L (s-r)^2 / r in currency1 over the curve price when unclamped.
library CrossMath {
    uint256 internal constant Q96 = 1 << 96;
    /// Fill fractions are scaled by 1e36 so their quantum stays at or below one wei for books up to 1e36.
    uint256 internal constant ONE = 1e36;
    /// Above this the vault's depth is negligible against the book, and the normalized terms could overflow.
    uint256 internal constant NORM_LIMIT = 1 << 120;
    /// Fills within 1e-12 of 100% snap to 100%, absorbing mulDiv dust.
    uint256 internal constant SNAP = 1e24;

    error RatioOutOfRange();

    struct Result {
        uint160 sqrtPriceX96; // clearing sqrt price
        uint128 fill0; // filled fraction of currency0 offered, ONE = 100%
        uint128 fill1; // filled fraction of currency1 offered, ONE = 100%
        uint128 liquidity; // vault liquidity used for the cross (zero if ignored)
    }

    /// @param r96 Reference sqrt price.
    /// @param L Vault liquidity committed to the cross.
    /// @param X Currency0 offered.
    /// @param Y Currency1 offered.
    /// @param sLo Lowest allowed clearing sqrt price (collar and range).
    /// @param sHi Highest allowed clearing sqrt price.
    function clear(uint160 r96, uint128 L, uint256 X, uint256 Y, uint160 sLo, uint160 sHi)
        internal
        pure
        returns (Result memory res)
    {
        if (X == 0 && Y == 0) return Result(r96, 0, 0, 0);

        uint256 s;
        uint256 a96;
        uint256 b96;
        if (L > 0) {
            a96 = FullMath.mulDiv(X, r96, L);
            b96 = FullMath.mulDiv(FullMath.mulDiv(Y, Q96, r96), Q96, L);
        }
        if (L == 0 || a96 >= NORM_LIMIT || b96 >= NORM_LIMIT) {
            // Order against order only.
            if (X == 0 || Y == 0) return Result(r96, 0, 0, 0);
            if (Y / X >= (1 << 64)) revert RatioOutOfRange();
            s = FixedPointMathLib.sqrt(FullMath.mulDiv(Y, 1 << 192, X));
            L = 0;
        } else {
            uint256 aq = a96 + Q96;
            uint256 d96 = Q96 + 4 * FullMath.mulDiv(aq, b96, Q96);
            uint256 sqrtD96 = FixedPointMathLib.sqrt(d96 * Q96);
            uint256 t96 = FullMath.mulDiv(Q96 + sqrtD96, Q96, 2 * aq);
            s = FullMath.mulDiv(r96, t96, Q96);
        }
        if (s < sLo) s = sLo;
        if (s > sHi) s = sHi;
        res.sqrtPriceX96 = uint160(s);
        res.liquidity = L;

        uint256 dem0 = FullMath.mulDiv(FullMath.mulDiv(Y, Q96, s), Q96, s);
        uint256 v0;
        if (L != 0 && s != r96) {
            (uint160 lo, uint160 hi) = s < r96 ? (uint160(s), r96) : (r96, uint160(s));
            v0 = SqrtPriceMath.getAmount0Delta(lo, hi, L, false);
        }

        // Fill fractions are quantized, so the vault absorbs a small residual at s. Rounding the rationed
        // side toward the price move keeps that residual on the vault's side of the trade: it sells
        // currency0 only above the reference and buys it only below.
        uint256 f0 = ONE;
        uint256 f1 = ONE;
        if (dem0 > X) {
            // Demand for currency0 exceeds supply; the vault sells currency0 only if price rose.
            bool up = s > r96;
            uint256 cover = up ? FixedPointMathLib.min(dem0 - X, v0) : 0;
            f1 = up ? FullMath.mulDivRoundingUp(X + cover, ONE, dem0) : FullMath.mulDiv(X + cover, ONE, dem0);
            if (up && f1 >= ONE - SNAP) f1 = ONE;
        } else if (dem0 < X) {
            // Supply of currency0 exceeds demand; the vault buys currency0 only if price fell.
            bool down = s < r96;
            uint256 absorb = down ? FixedPointMathLib.min(X - dem0, v0) : 0;
            f0 = down ? FullMath.mulDivRoundingUp(dem0 + absorb, ONE, X) : FullMath.mulDiv(dem0 + absorb, ONE, X);
            if (down && f0 >= ONE - SNAP) f0 = ONE;
        }
        res.fill0 = uint128(f0);
        res.fill1 = uint128(f1);
    }

    /// @notice Currency1 paid for `amount0` currency0 at sqrt price `s96`, rounded down.
    function toAmount1(uint256 amount0, uint160 s96) internal pure returns (uint256) {
        return FullMath.mulDiv(FullMath.mulDiv(amount0, s96, Q96), s96, Q96);
    }

    /// @notice Currency0 paid for `amount1` currency1 at sqrt price `s96`, rounded down.
    function toAmount0(uint256 amount1, uint160 s96) internal pure returns (uint256) {
        return FullMath.mulDiv(FullMath.mulDiv(amount1, Q96, s96), Q96, s96);
    }

    /// @notice Vault surplus over its curve in currency1, exact when unclamped: L (s-r)^2 / r.
    function surplus1(uint160 r96, uint160 s96, uint128 L) internal pure returns (uint256) {
        uint256 d = s96 > r96 ? s96 - r96 : r96 - s96;
        return FullMath.mulDiv(FullMath.mulDiv(L, d, Q96), d, r96);
    }
}
