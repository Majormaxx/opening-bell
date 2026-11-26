// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @notice Keeper entry points of the Opening Bell hook, as seen by the callback receiver.
interface IBellHook {
    function poke() external returns (bool acted);
    function ringBell() external;
}
