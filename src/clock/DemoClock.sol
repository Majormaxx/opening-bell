// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ISessionClock} from "./ISessionClock.sol";

/// @notice Short-cycle clock for demos: open for `openLen` seconds at the start of every `period`,
/// counting from `anchor`. Closed before `anchor`.
contract DemoClock is ISessionClock {
    error BadSchedule();

    uint256 public immutable anchor;
    uint256 public immutable period;
    uint256 public immutable openLen;

    constructor(uint256 anchor_, uint256 period_, uint256 openLen_) {
        if (period_ == 0 || openLen_ == 0 || openLen_ >= period_) revert BadSchedule();
        anchor = anchor_;
        period = period_;
        openLen = openLen_;
    }

    function isOpen(uint256 t) external view returns (bool) {
        return t >= anchor && (t - anchor) % period < openLen;
    }

    function nextOpen(uint256 t) external view returns (uint256) {
        if (t < anchor) return anchor;
        return anchor + ((t - anchor) / period + 1) * period;
    }

    function nextClose(uint256 t) external view returns (uint256) {
        if (t < anchor) return anchor + openLen;
        uint256 close = anchor + ((t - anchor) / period) * period + openLen;
        return close >= t ? close : close + period;
    }
}
