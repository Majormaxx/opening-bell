// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {MockToken} from "./MockToken.sol";

/// @notice Demo tokenized stock, 18 decimals.
contract MockStock is MockToken {
    constructor() MockToken("Test Stock", "tSTK", 18, 1_000e18) {}
}
