// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @notice Stand-in for a reference market's price print on an origin chain. A script posts prints;
/// the reactive contract on Reactive Network subscribes to the Print event.
contract MockMarketFeed {
    error NotPoster();

    event Print(bytes32 indexed feedId, uint256 priceX18, uint8 status, uint64 observedAt);

    address public immutable poster;

    constructor(address poster_) {
        poster = poster_;
    }

    function post(bytes32 feedId, uint256 priceX18, uint8 status) external {
        if (msg.sender != poster) revert NotPoster();
        emit Print(feedId, priceX18, status, uint64(block.timestamp));
    }
}
