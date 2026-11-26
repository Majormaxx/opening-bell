// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IReferenceOracle} from "./IReferenceOracle.sol";
import {Print, MarketStatus} from "../types/Types.sol";

/// @notice Settable oracle for tests and local demos.
contract MockReferenceOracle is IReferenceOracle {
    mapping(bytes32 => Print) internal prints;

    function set(bytes32 feedId, uint256 priceX18, uint64 observedAt, MarketStatus status) external {
        prints[feedId] = Print(priceX18, observedAt, status);
    }

    function latest(bytes32 feedId) external view returns (Print memory) {
        return prints[feedId];
    }
}
