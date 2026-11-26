// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {MockToken} from "./MockToken.sol";

/// @notice Demo stablecoin, 6 decimals.
contract MockUSD is MockToken {
    constructor() MockToken("Test USD", "tUSD", 6, 1_000_000e6) {}
}
