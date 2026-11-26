// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";

/// @notice Tick range around a strike, aligned to the pool's tick spacing.
library RangeLib {
    error EmptyRange();

    /// @return lower floor((tick - width) / spacing) * spacing, clamped to the usable range.
    /// @return upper ceil((tick + width) / spacing) * spacing, clamped to the usable range.
    function around(int24 tick, uint16 width, int24 spacing) internal pure returns (int24 lower, int24 upper) {
        int24 minT = minUsable(spacing);
        int24 maxT = maxUsable(spacing);
        int256 lo = floorDiv(int256(tick) - int256(uint256(width)), spacing) * spacing;
        int256 hi = ceilDiv(int256(tick) + int256(uint256(width)), spacing) * spacing;
        if (lo < minT) lo = minT;
        if (hi > maxT) hi = maxT;
        if (lo >= hi) {
            // width 0 on an aligned tick: widen to one spacing above.
            hi = lo + spacing;
            if (hi > maxT) (lo, hi) = (maxT - spacing, maxT);
        }
        if (lo >= hi) revert EmptyRange();
        lower = int24(lo);
        upper = int24(hi);
    }

    function minUsable(int24 spacing) internal pure returns (int24) {
        return (TickMath.MIN_TICK / spacing) * spacing;
    }

    function maxUsable(int24 spacing) internal pure returns (int24) {
        return (TickMath.MAX_TICK / spacing) * spacing;
    }

    function floorDiv(int256 a, int256 b) internal pure returns (int256 q) {
        q = a / b;
        if (a % b != 0 && (a < 0) != (b < 0)) q -= 1;
    }

    function ceilDiv(int256 a, int256 b) internal pure returns (int256 q) {
        q = a / b;
        if (a % b != 0 && (a < 0) == (b < 0)) q += 1;
    }
}
