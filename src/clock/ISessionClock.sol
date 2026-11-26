// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @notice Regular-session schedule of a reference market.
interface ISessionClock {
    /// @notice True if the regular session is open at `t` (open inclusive, close exclusive).
    function isOpen(uint256 t) external view returns (bool);

    /// @notice Earliest regular-session open strictly after `t`.
    function nextOpen(uint256 t) external view returns (uint256);

    /// @notice Earliest regular-session close at or after `t`.
    function nextClose(uint256 t) external view returns (uint256);
}
