// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";
import {IReactive} from "@reactive/src/interfaces/IReactive.sol";
import {ISystemContract} from "@reactive/src/interfaces/ISystemContract.sol";
import {IPayable} from "@reactive/src/interfaces/IPayable.sol";
import {AbstractCallback} from "@reactive/src/base/AbstractCallback.sol";
import {AbstractPayer} from "@reactive/src/base/AbstractPayer.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {BellReactive} from "../../src/reactive/BellReactive.sol";
import {BellTower} from "../../src/reactive/BellTower.sol";
import {MockMarketFeed} from "../../src/reactive/MockMarketFeed.sol";
import {Print as PrintData, MarketStatus} from "../../src/types/Types.sol";

/// Records subscriptions and callback requests the way Reactive Network's system contract receives them.
contract MockSystem {
    struct Sub {
        uint256 chainId;
        address target;
        uint256 t0;
        uint256 t1;
        uint256 t2;
        uint256 t3;
    }

    Sub[] public subs;
    Sub[] public unsubs;
    ISystemContract.CallbackConfiguration_V_1_0[] internal cbs;
    mapping(address => uint256) public debt;

    receive() external payable {}

    function subscribe(uint256 c, address a, uint256 t0, uint256 t1, uint256 t2, uint256 t3) external {
        subs.push(Sub(c, a, t0, t1, t2, t3));
    }

    function unsubscribe(uint256 c, address a, uint256 t0, uint256 t1, uint256 t2, uint256 t3) external {
        unsubs.push(Sub(c, a, t0, t1, t2, t3));
    }

    function requestCallbackV_1_0(ISystemContract.CallbackConfiguration_V_1_0 memory c) external {
        cbs.push(c);
    }

    function setDebt(address who, uint256 amt) external {
        debt[who] = amt;
    }

    function subCount() external view returns (uint256) {
        return subs.length;
    }

    function unsubCount() external view returns (uint256) {
        return unsubs.length;
    }

    function cbCount() external view returns (uint256) {
        return cbs.length;
    }

    function cb(uint256 i) external view returns (ISystemContract.CallbackConfiguration_V_1_0 memory) {
        return cbs[i];
    }
}

contract MockBellHook {
    uint256 public pokes;
    uint256 public rings;
    bool public revertRing;

    function setRevertRing(bool r) external {
        revertRing = r;
    }

    function poke() external returns (bool) {
        pokes++;
        return true;
    }

    function ringBell() external {
        if (revertRing) revert("not due");
        rings++;
    }
}

contract MockProxy {
    mapping(address => uint256) public debt;

    receive() external payable {}

    function setDebt(address who, uint256 amt) external {
        debt[who] = amt;
    }
}

contract BellReactiveTest is Test {
    address constant SYSTEM = 0x8888888888888888888888888888888888888888;
    address constant CRON = 0x0000000000000000000000000000000000fffFfF;
    uint256 constant CRON100 = 0xb49937fb8970e19fd46d48f7e3fb00d659deac0347f79cd7cb542f0fc1503c70;
    uint256 constant IGNORE = 0xa65f96fc951c35ead38878e0f0b7a3c744a6f5ccc1476b313353ce31712313ad;
    uint256 constant ORIGIN = 84532;
    uint256 constant DEST = 1301;
    address constant FEED = address(0xFEED);
    bytes32 constant FEED_ID = keccak256("tSTK/USD");
    address constant TOWER = address(0x7011);

    MockSystem sys;
    BellReactive rc;

    function setUp() public {
        vm.etch(SYSTEM, address(new MockSystem()).code);
        sys = MockSystem(payable(SYSTEM));
        rc = new BellReactive(ORIGIN, FEED, FEED_ID, DEST, CRON100);
    }

    function _printLog(uint256 chainId, address src, bytes32 fid, uint256 price, uint8 st, uint64 ts)
        internal
        pure
        returns (IReactive.LogRecord memory l)
    {
        l.chainId = chainId;
        l.contractAddress = src;
        l.topic0 = uint256(keccak256("Print(bytes32,uint256,uint8,uint64)"));
        l.topic1 = uint256(fid);
        l.data = abi.encode(price, st, ts);
    }

    function _cronLog() internal view returns (IReactive.LogRecord memory l) {
        l.chainId = block.chainid;
        l.contractAddress = CRON;
        l.topic0 = CRON100;
    }

    function test_constructorSubscribes() public view {
        assertEq(sys.subCount(), 2);
        (uint256 c, address a, uint256 t0, uint256 t1, uint256 t2, uint256 t3) = sys.subs(0);
        assertEq(c, ORIGIN);
        assertEq(a, FEED);
        assertEq(t0, uint256(keccak256("Print(bytes32,uint256,uint8,uint64)")));
        assertEq(t1, uint256(FEED_ID));
        assertEq(t2, IGNORE);
        assertEq(t3, IGNORE);
        (c, a, t0, t1,,) = sys.subs(1);
        assertEq(c, block.chainid);
        assertEq(a, CRON);
        assertEq(t0, CRON100);
        assertEq(t1, IGNORE);
    }

    function test_printTopicMatchesFeedEvent() public pure {
        assertEq(MockMarketFeed.Print.selector, bytes32(uint256(keccak256("Print(bytes32,uint256,uint8,uint64)"))));
    }

    function test_noRecipientNoCallback() public {
        vm.prank(SYSTEM);
        rc.react(_printLog(ORIGIN, FEED, FEED_ID, 200e18, 2, 123));
        assertEq(sys.cbCount(), 0);
    }

    function test_printRoutesToOnPrint() public {
        rc.setRecipient(TOWER);
        vm.prank(SYSTEM);
        rc.react(_printLog(ORIGIN, FEED, FEED_ID, 200e18, 2, 123));
        assertEq(sys.cbCount(), 1);
        ISystemContract.CallbackConfiguration_V_1_0 memory c = sys.cb(0);
        assertEq(c.chainId, DEST);
        assertEq(c.recipient, TOWER);
        assertGe(c.gasLimit, 100_000);
        assertLe(c.gasLimit, 5_000_000);
        assertEq(
            c.payload,
            abi.encodeWithSignature(
                "onPrint(address,bytes32,uint256,uint8,uint64)", address(0), FEED_ID, 200e18, uint8(2), uint64(123)
            )
        );
    }

    function test_cronRoutesToOnTick() public {
        rc.setRecipient(TOWER);
        vm.prank(SYSTEM);
        rc.react(_cronLog());
        assertEq(sys.cbCount(), 1);
        assertEq(sys.cb(0).payload, abi.encodeWithSignature("onTick(address)", address(0)));
    }

    function test_foreignLogsFallThrough() public {
        rc.setRecipient(TOWER);
        vm.startPrank(SYSTEM);
        rc.react(_printLog(1, FEED, FEED_ID, 1, 2, 1)); // wrong chain
        rc.react(_printLog(ORIGIN, address(0xBAD), FEED_ID, 1, 2, 1)); // wrong source
        rc.react(_printLog(ORIGIN, FEED, bytes32(uint256(7)), 1, 2, 1)); // wrong feed
        IReactive.LogRecord memory l;
        l.topic0 = 42;
        rc.react(l); // unknown topic
        vm.stopPrank();
        assertEq(sys.cbCount(), 0);
    }

    function test_reactOnlySystem() public {
        vm.expectRevert(abi.encodeWithSelector(AbstractPayer.NotAuthorized.selector, address(this), SYSTEM));
        rc.react(_cronLog());
    }

    function test_ownerOnly() public {
        vm.startPrank(address(0xBEEF));
        vm.expectRevert(BellReactive.NotOwner.selector);
        rc.setRecipient(TOWER);
        vm.expectRevert(BellReactive.NotOwner.selector);
        rc.pauseCron();
        vm.expectRevert(BellReactive.NotOwner.selector);
        rc.resumeCron();
        vm.stopPrank();
    }

    function test_pauseUsesIdenticalArgs() public {
        rc.pauseCron();
        assertEq(sys.unsubCount(), 1);
        (uint256 c, address a, uint256 t0, uint256 t1, uint256 t2, uint256 t3) = sys.unsubs(0);
        (uint256 c2, address a2, uint256 u0, uint256 u1, uint256 u2, uint256 u3) = sys.subs(1);
        assertEq(c, c2);
        assertEq(a, a2);
        assertEq(t0, u0);
        assertEq(t1, u1);
        assertEq(t2, u2);
        assertEq(t3, u3);
        rc.resumeCron();
        assertEq(sys.subCount(), 3);
    }

    function test_coverDebt() public {
        vm.deal(address(rc), 1 ether);
        sys.setDebt(address(rc), 0.25 ether);
        rc.coverDebt();
        assertEq(address(rc).balance, 0.75 ether);
        assertEq(SYSTEM.balance, 0.25 ether);
    }
}

contract BellTowerTest is Test {
    address constant RC = address(0x5EAC7);
    bytes32 constant FEED_ID = keccak256("tSTK/USD");

    MockProxy proxy;
    MockBellHook hook;
    BellTower tower;

    function setUp() public {
        proxy = new MockProxy();
        hook = new MockBellHook();
        tower = new BellTower(IPayable(payable(address(proxy))), RC, FEED_ID);
        tower.setHook(address(hook));
    }

    function _print(uint256 price, uint8 st, uint64 ts) internal {
        vm.prank(address(proxy));
        tower.onPrint(RC, FEED_ID, price, st, ts);
    }

    function test_printStoresAndRings() public {
        _print(200e18, 2, 1000);
        PrintData memory p = tower.latest(FEED_ID);
        assertEq(p.priceX18, 200e18);
        assertEq(p.observedAt, 1000);
        assertEq(uint8(p.status), uint8(MarketStatus.REGULAR));
        assertEq(hook.rings(), 1);
    }

    function test_wrongCallerReverts() public {
        vm.expectRevert(abi.encodeWithSelector(AbstractPayer.NotAuthorized.selector, address(this), address(proxy)));
        tower.onPrint(RC, FEED_ID, 1, 2, 1);
        vm.expectRevert(abi.encodeWithSelector(AbstractPayer.NotAuthorized.selector, address(this), address(proxy)));
        tower.onTick(RC);
    }

    function test_wrongSenderReverts() public {
        vm.startPrank(address(proxy));
        vm.expectRevert(abi.encodeWithSelector(AbstractCallback.CallbackNotAuthorized.selector, address(0xBAD), RC));
        tower.onPrint(address(0xBAD), FEED_ID, 1, 2, 1);
        vm.expectRevert(abi.encodeWithSelector(AbstractCallback.CallbackNotAuthorized.selector, address(0xBAD), RC));
        tower.onTick(address(0xBAD));
        vm.stopPrank();
    }

    function test_stalePrintIgnored() public {
        _print(200e18, 2, 1000);
        _print(150e18, 2, 999);
        _print(150e18, 2, 1000);
        assertEq(tower.latest(FEED_ID).priceX18, 200e18);
        assertEq(hook.rings(), 1);
    }

    function test_badFeedOrStatusIgnored() public {
        vm.prank(address(proxy));
        tower.onPrint(RC, bytes32(uint256(1)), 1e18, 2, 5);
        _print(1e18, 6, 5);
        assertEq(tower.latest(FEED_ID).observedAt, 0);
        assertEq(hook.rings(), 0);
    }

    function test_ringRevertSwallowed() public {
        hook.setRevertRing(true);
        _print(200e18, 2, 1000);
        assertEq(tower.latest(FEED_ID).priceX18, 200e18);
    }

    function test_tickPokesAndRings() public {
        vm.prank(address(proxy));
        tower.onTick(RC);
        assertEq(hook.pokes(), 1);
        assertEq(hook.rings(), 1);
    }

    function test_noHookNoop() public {
        BellTower t2 = new BellTower(IPayable(payable(address(proxy))), RC, FEED_ID);
        vm.prank(address(proxy));
        t2.onTick(RC);
        vm.prank(address(proxy));
        t2.onPrint(RC, FEED_ID, 1e18, 2, 7);
        assertEq(t2.latest(FEED_ID).priceX18, 1e18);
    }

    function test_setHookOnceOwnerOnly() public {
        vm.expectRevert(BellTower.AlreadySet.selector);
        tower.setHook(address(1));
        BellTower t2 = new BellTower(IPayable(payable(address(proxy))), RC, FEED_ID);
        vm.prank(address(0xBEEF));
        vm.expectRevert(Ownable.Unauthorized.selector);
        t2.setHook(address(1));
    }

    function test_unknownFeedReverts() public {
        vm.expectRevert(BellTower.UnknownFeed.selector);
        tower.latest(bytes32(0));
    }

    function test_coverDebt() public {
        vm.deal(address(tower), 1 ether);
        proxy.setDebt(address(tower), 0.1 ether);
        tower.coverDebt();
        assertEq(address(proxy).balance, 0.1 ether);
    }
}

contract MockMarketFeedTest is Test {
    event Print(bytes32 indexed feedId, uint256 priceX18, uint8 status, uint64 observedAt); // mirrors MockMarketFeed

    function test_post() public {
        MockMarketFeed f = new MockMarketFeed(address(this));
        vm.warp(5000);
        vm.expectEmit(true, false, false, true);
        emit Print(bytes32(uint256(1)), 2e18, 2, 5000);
        f.post(bytes32(uint256(1)), 2e18, 2);
        vm.prank(address(0xBEEF));
        vm.expectRevert(MockMarketFeed.NotPoster.selector);
        f.post(bytes32(uint256(1)), 2e18, 2);
    }
}
