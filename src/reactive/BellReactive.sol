// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {AbstractReactive} from "@reactive/src/base/AbstractReactive.sol";
import {ISystemContract} from "@reactive/src/interfaces/ISystemContract.sol";

/// @notice Reactive Network contract that rings the bell. It watches the origin chain's Print events
/// and a cron, and requests callbacks to the BellTower on the pool's chain.
contract BellReactive is AbstractReactive {
    error NotOwner();

    event RecipientSet(address tower);
    event CronPaused();
    event CronResumed();

    /// keccak256("Print(bytes32,uint256,uint8,uint64)")
    uint256 public constant PRINT_TOPIC0 = uint256(keccak256("Print(bytes32,uint256,uint8,uint64)"));
    /// Legacy system contract that emits the Cron events on Reactive Network.
    address public constant CRON_SOURCE = 0x0000000000000000000000000000000000fffFfF;
    /// Above the 100,000 minimum; sized from the measured ringBell gas.
    uint64 public constant CALLBACK_GAS = 2_500_000;

    address public immutable owner;
    uint256 public immutable originChainId;
    address public immutable originFeed;
    bytes32 public immutable feedId;
    uint256 public immutable destChainId;
    uint256 public immutable cronTopic0;
    address public recipient;

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor(uint256 originChainId_, address originFeed_, bytes32 feedId_, uint256 destChainId_, uint256 cronTopic0_)
        payable
    {
        owner = msg.sender;
        originChainId = originChainId_;
        originFeed = originFeed_;
        feedId = feedId_;
        destChainId = destChainId_;
        cronTopic0 = cronTopic0_;
        SYSTEM.subscribe(originChainId_, originFeed_, PRINT_TOPIC0, uint256(feedId_), REACTIVE_IGNORE, REACTIVE_IGNORE);
        _subscribeCron();
    }

    function setRecipient(address tower) external onlyOwner {
        recipient = tower;
        emit RecipientSet(tower);
    }

    function pauseCron() external onlyOwner {
        SYSTEM.unsubscribe(block.chainid, CRON_SOURCE, cronTopic0, REACTIVE_IGNORE, REACTIVE_IGNORE, REACTIVE_IGNORE);
        emit CronPaused();
    }

    function resumeCron() external onlyOwner {
        _subscribeCron();
        emit CronResumed();
    }

    function coverDebt() external {
        _coverDebt();
    }

    /// @dev Never reverts to filter: reverted reactive transactions are still billed.
    function react(LogRecord calldata log_) external onlySystem {
        if (recipient == address(0)) return;
        if (
            log_.topic0 == PRINT_TOPIC0 && log_.chainId == originChainId && log_.contractAddress == originFeed
                && bytes32(log_.topic1) == feedId
        ) {
            (uint256 priceX18, uint8 status, uint64 observedAt) = abi.decode(log_.data, (uint256, uint8, uint64));
            _callback(
                abi.encodeWithSignature(
                    "onPrint(address,bytes32,uint256,uint8,uint64)",
                    address(0),
                    bytes32(log_.topic1),
                    priceX18,
                    status,
                    observedAt
                )
            );
        } else if (log_.topic0 == cronTopic0) {
            _callback(abi.encodeWithSignature("onTick(address)", address(0)));
        }
    }

    function _subscribeCron() internal {
        SYSTEM.subscribe(block.chainid, CRON_SOURCE, cronTopic0, REACTIVE_IGNORE, REACTIVE_IGNORE, REACTIVE_IGNORE);
    }

    /// @dev The first payload argument is a placeholder the network overwrites with this contract's address.
    function _callback(bytes memory payload) internal {
        SYSTEM.requestCallbackV_1_0(
            ISystemContract.CallbackConfiguration_V_1_0({
                chainId: destChainId, recipient: recipient, gasLimit: CALLBACK_GAS, payload: payload
            })
        );
    }
}
