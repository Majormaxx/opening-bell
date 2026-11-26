// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";

/// @notice Converts between a human price (quote per base, 18-decimal) and a pool sqrt price.
library PriceLib {
    uint256 internal constant Q96 = 1 << 96;

    error PriceOutOfRange();

    struct Pair {
        bool baseIsCurrency0;
        uint8 baseDec;
        uint8 quoteDec;
    }

    function toSqrtPriceX96(Pair memory p, uint256 priceX18) internal pure returns (uint160) {
        if (priceX18 == 0) revert PriceOutOfRange();
        uint256 num;
        uint256 den;
        if (p.baseIsCurrency0) {
            num = priceX18 * 10 ** p.quoteDec;
            den = 1e18 * 10 ** p.baseDec;
        } else {
            num = 1e18 * 10 ** p.baseDec;
            den = priceX18 * 10 ** p.quoteDec;
        }
        // Raw price must stay below 2^64 for the Q192 ratio to fit in 256 bits.
        if (num / den >= (1 << 64)) revert PriceOutOfRange();
        uint256 s = FixedPointMathLib.sqrt(FullMath.mulDiv(num, 1 << 192, den));
        if (s < TickMath.MIN_SQRT_PRICE || s >= TickMath.MAX_SQRT_PRICE) revert PriceOutOfRange();
        return uint160(s);
    }

    function toPriceX18(Pair memory p, uint160 s96) internal pure returns (uint256) {
        if (p.baseIsCurrency0) {
            // raw c1/c0 = s^2 / 2^192, then scale by base and quote decimals.
            uint256 raw96 = FullMath.mulDiv(s96, s96, Q96);
            return FullMath.mulDiv(raw96, 1e18 * 10 ** p.baseDec, Q96 * 10 ** p.quoteDec);
        }
        // Base is currency1: quote per base is the inverse of the raw price.
        uint256 x = FullMath.mulDiv(1e18 * 10 ** p.baseDec, Q96, s96);
        return FullMath.mulDiv(x, Q96, uint256(s96) * 10 ** p.quoteDec);
    }

    /// @notice Quote value of `baseAmt` base at `priceX18`.
    function baseToQuote(Pair memory p, uint256 baseAmt, uint256 priceX18) internal pure returns (uint256) {
        return FullMath.mulDiv(baseAmt, priceX18 * 10 ** p.quoteDec, 1e18 * 10 ** p.baseDec);
    }
}
