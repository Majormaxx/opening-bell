// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable} from "solady/auth/Ownable.sol";
import {DateTimeLib} from "solady/utils/DateTimeLib.sol";
import {ISessionClock} from "./ISessionClock.sol";

/// @notice NYSE regular session: 09:30 to 16:00 US Eastern, Monday to Friday, with US daylight
/// saving time computed by rule and holidays and early closes set by the owner.
/// @dev Days are keyed by "Eastern day": the epoch day number of the calendar date in New York.
/// The holiday table is owner-maintained. A production deployment should derive the calendar by rule.
contract NYSEClock is ISessionClock, Ownable {
    error NoSessionWithinScan();
    error BadDayKind();

    event DayKindSet(uint256 indexed easternDay, uint8 kind);

    uint8 public constant REGULAR = 0;
    uint8 public constant HOLIDAY = 1;
    uint8 public constant EARLY_CLOSE = 2;

    uint256 internal constant OPEN_SECS = 9 hours + 30 minutes;
    uint256 internal constant CLOSE_SECS = 16 hours;
    uint256 internal constant EARLY_CLOSE_SECS = 13 hours;
    uint256 internal constant MAX_SCAN_DAYS = 10;

    /// @notice Eastern day => REGULAR, HOLIDAY or EARLY_CLOSE.
    mapping(uint256 => uint8) public dayKind;

    constructor(address owner_) {
        _initializeOwner(owner_);
    }

    function setDayKinds(uint256[] calldata easternDays, uint8 kind) external onlyOwner {
        if (kind > EARLY_CLOSE) revert BadDayKind();
        for (uint256 i; i < easternDays.length; ++i) {
            dayKind[easternDays[i]] = kind;
            emit DayKindSet(easternDays[i], kind);
        }
    }

    /// @notice Eastern day for a calendar date, for building the holiday table.
    function easternDayOf(uint256 year, uint256 month, uint256 day) external pure returns (uint256) {
        return DateTimeLib.dateToEpochDay(year, month, day);
    }

    function isOpen(uint256 t) external view returns (bool) {
        (bool trades, uint256 open, uint256 close) = session(easternDay(t));
        return trades && t >= open && t < close;
    }

    function nextOpen(uint256 t) external view returns (uint256) {
        uint256 d = easternDay(t);
        for (uint256 i; i <= MAX_SCAN_DAYS; ++i) {
            (bool trades, uint256 open,) = session(d + i);
            if (trades && open > t) return open;
        }
        revert NoSessionWithinScan();
    }

    function nextClose(uint256 t) external view returns (uint256) {
        uint256 d = easternDay(t);
        for (uint256 i; i <= MAX_SCAN_DAYS; ++i) {
            (bool trades,, uint256 close) = session(d + i);
            if (trades && close >= t) return close;
        }
        revert NoSessionWithinScan();
    }

    /// @notice Regular session for an Eastern day, as UTC timestamps.
    function session(uint256 d) public view returns (bool trades, uint256 open, uint256 close) {
        uint256 kind = dayKind[d];
        uint256 midnight = d * 1 days;
        if (kind == HOLIDAY || DateTimeLib.isWeekEnd(midnight)) return (false, 0, 0);
        // US DST changes happen early on Sundays, so any instant inside a weekday has the day's offset.
        uint256 offset = utcOffsetSecs(midnight + 12 hours);
        open = midnight + OPEN_SECS + offset;
        close = midnight + (kind == EARLY_CLOSE ? EARLY_CLOSE_SECS : CLOSE_SECS) + offset;
        trades = true;
    }

    /// @notice Eastern day containing UTC instant `t`.
    function easternDay(uint256 t) public pure returns (uint256) {
        return (t - utcOffsetSecs(t)) / 1 days;
    }

    /// @notice Seconds New York is behind UTC at instant `t`: 4 hours during DST, else 5 hours.
    /// @dev DST runs from 07:00 UTC on the second Sunday of March to 06:00 UTC on the first Sunday of
    /// November (2:00 local in both cases).
    function utcOffsetSecs(uint256 t) public pure returns (uint256) {
        (uint256 year,,) = DateTimeLib.timestampToDate(t);
        uint256 start = DateTimeLib.nthWeekdayInMonthOfYearTimestamp(year, 3, 2, DateTimeLib.SUN) + 7 hours;
        uint256 end = DateTimeLib.nthWeekdayInMonthOfYearTimestamp(year, 11, 1, DateTimeLib.SUN) + 6 hours;
        return (t >= start && t < end) ? 4 hours : 5 hours;
    }
}
