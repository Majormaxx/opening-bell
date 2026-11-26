// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Print} from "../types/Types.sol";

/// @notice Source of reference prints for a feed.
interface IReferenceOracle {
    function latest(bytes32 feedId) external view returns (Print memory);
}
