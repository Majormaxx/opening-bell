// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {NYSEClock} from "../../src/clock/NYSEClock.sol";
import {DemoClock} from "../../src/clock/DemoClock.sol";
import {Ownable} from "solady/auth/Ownable.sol";

contract NYSEClockTest is Test {
    NYSEClock clock;

    function setUp() public {
        clock = new NYSEClock(address(this));
        uint256[] memory holidays = new uint256[](3);
        holidays[0] = clock.easternDayOf(2026, 11, 26);
        holidays[1] = clock.easternDayOf(2026, 12, 25);
        holidays[2] = clock.easternDayOf(2027, 1, 1);
        clock.setDayKinds(holidays, clock.HOLIDAY());
        uint256[] memory early = new uint256[](2);
        early[0] = clock.easternDayOf(2026, 11, 27);
        early[1] = clock.easternDayOf(2026, 12, 24);
        clock.setDayKinds(early, clock.EARLY_CLOSE());
    }

    function test_thanksgiving() public view {
        uint256 t = 1795651200; // Thu Nov 26 2026 00:00 UTC
        assertFalse(clock.isOpen(t));
        assertEq(clock.nextOpen(t), 1795789800);
        assertEq(clock.nextClose(t), 1795802400);
    }

    function test_blackFridayOpenAndEarlyClose() public view {
        uint256 t = 1795789800; // Fri Nov 27 14:30 UTC
        assertTrue(clock.isOpen(t));
        assertFalse(clock.isOpen(t - 1));
        assertEq(clock.nextClose(t), 1795802400);
        assertEq(clock.nextOpen(t), 1796049000);

        uint256 c = 1795802400; // 13:00 Eastern early close
        assertFalse(clock.isOpen(c));
        assertTrue(clock.isOpen(c - 1));
        assertEq(clock.nextOpen(c), 1796049000);
        // nextClose is "at or after", so a close instant returns itself.
        assertEq(clock.nextClose(c), c);
    }

    function test_mondayNov30() public view {
        uint256 t = 1796049000;
        assertTrue(clock.isOpen(t));
        assertEq(clock.nextClose(t), 1796072400);
        assertEq(clock.nextOpen(t), 1796135400);
    }

    function test_deadlineDayOpen() public view {
        assertTrue(clock.isOpen(1796308200)); // Thu Dec 3 14:30 UTC
        assertFalse(clock.isOpen(1796371140)); // Fri Dec 4 07:59 UTC
    }

    function test_christmasRun() public view {
        (,, uint256 close) = clock.session(clock.easternDayOf(2026, 12, 24));
        assertEq(close, 1798135200); // Thu Dec 24 18:00 UTC = 13:00 EST early close
        assertEq(clock.nextOpen(close), 1798468200); // Mon Dec 28 14:30 UTC
        (bool trades,,) = clock.session(clock.easternDayOf(2026, 12, 25));
        assertFalse(trades);
    }

    function test_firstOpenAfterDstStart() public view {
        uint256 t = 1805117400; // Mon Mar 15 2027 13:30 UTC = 09:30 EDT
        assertTrue(clock.isOpen(t));
        assertFalse(clock.isOpen(t - 1));
        assertEq(clock.utcOffsetSecs(t), 4 hours);
    }

    function test_dstEdges() public view {
        assertEq(clock.utcOffsetSecs(1793512800 - 1), 4 hours); // Nov 1 2026 05:59:59 UTC
        assertEq(clock.utcOffsetSecs(1793512800), 5 hours);
        assertEq(clock.utcOffsetSecs(1805007600 - 1), 5 hours); // Mar 14 2027 06:59:59 UTC
        assertEq(clock.utcOffsetSecs(1805007600), 4 hours);
    }

    function test_weekendClosed() public view {
        (bool trades,,) = clock.session(clock.easternDayOf(2026, 11, 28));
        assertFalse(trades);
        (trades,,) = clock.session(clock.easternDayOf(2026, 11, 29));
        assertFalse(trades);
    }

    /// Every vector from the independent Python zoneinfo generator.
    function test_generatedVectors() public view {
        string memory json = vm.readFile("test/vectors/nyse_clock.json");
        uint256[] memory ts = vm.parseJsonUintArray(json, ".ts");
        bool[] memory open = vm.parseJsonBoolArray(json, ".isOpen");
        uint256[] memory nOpen = vm.parseJsonUintArray(json, ".nextOpen");
        uint256[] memory nClose = vm.parseJsonUintArray(json, ".nextClose");
        assertGt(ts.length, 7000);
        for (uint256 i; i < ts.length; ++i) {
            assertEq(clock.isOpen(ts[i]), open[i], vm.toString(ts[i]));
            assertEq(clock.nextOpen(ts[i]), nOpen[i], vm.toString(ts[i]));
            assertEq(clock.nextClose(ts[i]), nClose[i], vm.toString(ts[i]));
        }
    }

    function test_onlyOwnerSetsDays() public {
        uint256[] memory d = new uint256[](1);
        vm.prank(address(0xBEEF));
        vm.expectRevert(Ownable.Unauthorized.selector);
        clock.setDayKinds(d, 1);
    }

    function test_badDayKind() public {
        uint256[] memory d = new uint256[](1);
        vm.expectRevert(NYSEClock.BadDayKind.selector);
        clock.setDayKinds(d, 3);
    }

    function test_scanLimitReverts() public {
        uint256 start = clock.easternDayOf(2027, 2, 1);
        uint256[] memory d = new uint256[](12);
        for (uint256 i; i < 12; ++i) d[i] = start + i;
        clock.setDayKinds(d, clock.HOLIDAY());
        vm.expectRevert(NYSEClock.NoSessionWithinScan.selector);
        clock.nextOpen(start * 1 days);
    }
}

contract DemoClockTest is Test {
    DemoClock clock;
    uint256 constant A = 1_000_000;

    function setUp() public {
        clock = new DemoClock(A, 600, 240);
    }

    function test_cycle() public view {
        assertFalse(clock.isOpen(A - 1));
        assertTrue(clock.isOpen(A));
        assertTrue(clock.isOpen(A + 239));
        assertFalse(clock.isOpen(A + 240));
        assertTrue(clock.isOpen(A + 600));
    }

    function test_nextOpen() public view {
        assertEq(clock.nextOpen(0), A);
        assertEq(clock.nextOpen(A), A + 600); // strictly after
        assertEq(clock.nextOpen(A + 599), A + 600);
        assertEq(clock.nextOpen(A + 600), A + 1200);
    }

    function test_nextClose() public view {
        assertEq(clock.nextClose(0), A + 240);
        assertEq(clock.nextClose(A + 240), A + 240); // at or after
        assertEq(clock.nextClose(A + 241), A + 840);
        assertEq(clock.nextClose(A + 600), A + 840);
    }

    function test_badSchedule() public {
        vm.expectRevert(DemoClock.BadSchedule.selector);
        new DemoClock(A, 600, 600);
        vm.expectRevert(DemoClock.BadSchedule.selector);
        new DemoClock(A, 0, 0);
    }

    function testFuzz_consistent(uint256 t) public view {
        t = bound(t, A, A + 365 days);
        uint256 o = clock.nextOpen(t);
        uint256 c = clock.nextClose(t);
        assertGt(o, t);
        assertGe(c, t);
        assertTrue(clock.isOpen(o));
        assertFalse(clock.isOpen(c));
        assertTrue(clock.isOpen(c - 1));
        // Open now iff the next close comes before the next open.
        assertEq(clock.isOpen(t), c < o && c > t);
    }
}
