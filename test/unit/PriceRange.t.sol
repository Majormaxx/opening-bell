// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {PriceLib} from "../../src/libraries/PriceLib.sol";
import {RangeLib} from "../../src/libraries/RangeLib.sol";

contract PriceLibTest is Test {
    function _pair(bool baseIs0, uint8 bd, uint8 qd) internal pure returns (PriceLib.Pair memory) {
        return PriceLib.Pair(baseIs0, bd, qd);
    }

    function test_specValues() public pure {
        // base 18 decimals, quote 6 decimals, price 200
        uint160 s0 = PriceLib.toSqrtPriceX96(_pair(true, 18, 6), 200e18);
        assertApproxEqRel(uint256(s0), 1.120455e24, 1e12);
        uint160 s1 = PriceLib.toSqrtPriceX96(_pair(false, 18, 6), 200e18);
        assertApproxEqRel(uint256(s1), 5.602277e33, 1e12);
    }

    function test_roundTripBothOrders() public pure {
        uint8[2] memory decs = [uint8(18), uint8(6)];
        for (uint256 i; i < 2; ++i) {
            for (uint256 j; j < 2; ++j) {
                for (uint256 o; o < 2; ++o) {
                    PriceLib.Pair memory p = _pair(o == 0, decs[i], decs[j]);
                    uint256 price = 187.25e18;
                    uint256 back = PriceLib.toPriceX18(p, PriceLib.toSqrtPriceX96(p, price));
                    assertApproxEqRel(back, price, 1e9);
                }
            }
        }
    }

    function testFuzz_roundTripWithinOneTick(uint256 price, bool baseIs0, bool bd18, bool qd18) public pure {
        price = bound(price, 1e12, 1e24); // 0.000001 to 1,000,000 quote per base
        PriceLib.Pair memory p = _pair(baseIs0, bd18 ? 18 : 6, qd18 ? 18 : 6);
        uint160 s = PriceLib.toSqrtPriceX96(p, price);
        uint256 back = PriceLib.toPriceX18(p, s);
        // One tick is 1 bp.
        assertApproxEqRel(back, price, 1e14);
        // And the tick of the strike maps back near the same price.
        int24 tick = TickMath.getTickAtSqrtPrice(s);
        uint256 atTick = PriceLib.toPriceX18(p, TickMath.getSqrtPriceAtTick(tick));
        assertApproxEqRel(atTick, price, 1.0001e14);
    }

    function test_baseToQuote() public pure {
        assertEq(PriceLib.baseToQuote(_pair(true, 18, 6), 2e18, 200e18), 400e6);
        assertEq(PriceLib.baseToQuote(_pair(false, 6, 18), 2e6, 200e18), 400e18);
    }

    function test_zeroPriceReverts() public {
        PriceLibHarness hp = new PriceLibHarness();
        vm.expectRevert(PriceLib.PriceOutOfRange.selector);
        hp.toSqrt(_pair(true, 18, 6), 0);
    }
}

contract PriceLibHarness {
    function toSqrt(PriceLib.Pair memory p, uint256 x) external pure returns (uint160) {
        return PriceLib.toSqrtPriceX96(p, x);
    }
}

contract RangeLibTest is Test {
    function test_positiveTick() public pure {
        (int24 lo, int24 hi) = RangeLib.around(1234, 300, 10);
        assertEq(lo, 930);
        assertEq(hi, 1540);
    }

    function test_negativeTick() public pure {
        (int24 lo, int24 hi) = RangeLib.around(-1234, 300, 10);
        assertEq(lo, -1540);
        assertEq(hi, -930);
    }

    function test_alignedTick() public pure {
        (int24 lo, int24 hi) = RangeLib.around(-1000, 300, 10);
        assertEq(lo, -1300);
        assertEq(hi, -700);
    }

    function test_zeroWidthWidens() public pure {
        (int24 lo, int24 hi) = RangeLib.around(-1000, 0, 10);
        assertEq(lo, -1000);
        assertEq(hi, -990);
    }

    function test_clampsToUsable() public pure {
        (int24 lo, int24 hi) = RangeLib.around(TickMath.MAX_TICK - 5, 300, 10);
        assertEq(hi, RangeLib.maxUsable(10));
        assertLt(lo, hi);
        (lo, hi) = RangeLib.around(TickMath.MIN_TICK + 5, 300, 10);
        assertEq(lo, RangeLib.minUsable(10));
    }

    function testFuzz_around(int24 tick, uint16 width, int24 spacing) public pure {
        spacing = int24(bound(spacing, 1, 200));
        tick = int24(bound(tick, TickMath.MIN_TICK, TickMath.MAX_TICK - 1));
        width = uint16(bound(width, 0, 5000));
        (int24 lo, int24 hi) = RangeLib.around(tick, width, spacing);
        assertLt(lo, hi);
        assertEq(lo % spacing, 0);
        assertEq(hi % spacing, 0);
        assertGe(lo, RangeLib.minUsable(spacing));
        assertLe(hi, RangeLib.maxUsable(spacing));
        // The strike sits inside the range unless it is pinned at a usable edge.
        if (tick > RangeLib.minUsable(spacing) + int24(uint24(width)) + spacing && tick < RangeLib.maxUsable(spacing) - int24(uint24(width)) - spacing) {
            assertLe(lo, tick - int24(uint24(width)));
            assertGe(hi, tick + int24(uint24(width)));
        }
    }

    function test_floorCeilNegative() public pure {
        assertEq(RangeLib.floorDiv(-7, 2), -4);
        assertEq(RangeLib.ceilDiv(-7, 2), -3);
        assertEq(RangeLib.floorDiv(7, 2), 3);
        assertEq(RangeLib.ceilDiv(7, 2), 4);
        assertEq(RangeLib.floorDiv(-8, 2), -4);
    }
}
