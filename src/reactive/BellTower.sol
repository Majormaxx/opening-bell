// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {AbstractCallback} from "@reactive/src/base/AbstractCallback.sol";
import {IPayable} from "@reactive/src/interfaces/IPayable.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {IReferenceOracle} from "../oracle/IReferenceOracle.sol";
import {Print, MarketStatus} from "../types/Types.sol";
import {IBellHook} from "./IBellHook.sol";

/// @notice Receives Reactive Network callbacks on the pool's chain. Stores the latest reference print
/// for the hook to read, and drives the hook's permissionless keeper entry points.
/// @dev Both guards are required on callbacks: onlyServiceProvider proves the caller is the callback
/// proxy; onlyCallbackSender proves the request came from our reactive contract (the proxy writes the
/// requesting reactive contract's address into the first payload argument).
contract BellTower is AbstractCallback, IReferenceOracle, Ownable {
    error AlreadySet();
    error UnknownFeed();

    event PrintStored(bytes32 indexed feedId, uint256 priceX18, uint8 status, uint64 observedAt);
    event PrintIgnored(bytes32 indexed feedId, uint256 priceX18, uint8 status, uint64 observedAt);
    event HookCall(bytes4 indexed selector, bool ok);

    bytes32 public immutable feedId;
    IBellHook public hook;
    Print internal _latest;

    constructor(IPayable callbackProxy, address reactive, bytes32 feedId_)
        payable
        AbstractCallback(callbackProxy, reactive)
    {
        feedId = feedId_;
        _initializeOwner(msg.sender);
    }

    function setHook(address hook_) external onlyOwner {
        if (address(hook) != address(0)) revert AlreadySet();
        hook = IBellHook(hook_);
    }

    function onPrint(address reactive_, bytes32 feedId_, uint256 priceX18, uint8 status, uint64 observedAt)
        external
        onlyServiceProvider
        onlyCallbackSender(reactive_)
    {
        // Ignore rather than revert: a reverted callback is still billed.
        if (feedId_ != feedId || status > uint8(MarketStatus.CLOSED) || observedAt <= _latest.observedAt) {
            emit PrintIgnored(feedId_, priceX18, status, observedAt);
            return;
        }
        _latest = Print(priceX18, observedAt, MarketStatus(status));
        emit PrintStored(feedId_, priceX18, status, observedAt);
        _ring();
    }

    function onTick(address reactive_) external onlyServiceProvider onlyCallbackSender(reactive_) {
        IBellHook h = hook;
        if (address(h) == address(0)) return;
        try h.poke() {
            emit HookCall(IBellHook.poke.selector, true);
        } catch {
            emit HookCall(IBellHook.poke.selector, false);
        }
        _ring();
    }

    function latest(bytes32 feedId_) external view returns (Print memory) {
        if (feedId_ != feedId) revert UnknownFeed();
        return _latest;
    }

    function coverDebt() external {
        _coverDebt();
    }

    function _ring() internal {
        IBellHook h = hook;
        if (address(h) == address(0)) return;
        try h.ringBell() {
            emit HookCall(IBellHook.ringBell.selector, true);
        } catch {
            emit HookCall(IBellHook.ringBell.selector, false);
        }
    }
}
