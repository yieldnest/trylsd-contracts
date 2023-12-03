// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";

import {TryLSDGateway} from "../../contracts/TryLSDGateway.sol";
import {ICurvePool2} from "../../interfaces/ICurvePool.sol";

import {MockERC20} from "../mocks/MockERC20.sol";

import "forge-std/console.sol";

contract TryLSDGatewayTest is Test {
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    // Event to be emitted when a user deposits through the Gateway
    event Deposit(
        address indexed sender,
        address indexed owner,
        uint256 ethAmount,
        uint256 shares
    );

    event Withdraw(
        address indexed sender,
        address indexed receiver,
        address indexed owner,
        uint256 ethAmount,
        uint256 shares
    );

    /*//////////////////////////////////////////////////////////////
                    VARIABLES & EXTERNAL CONTRACTS
    //////////////////////////////////////////////////////////////*/

    // Gateway variable
    TryLSDGateway internal _gateway;

    // curve tryLSD mainnet pool
    ICurvePool2 internal _tryLSD =
        ICurvePool2(0x2570f1bD5D2735314FC102eb12Fc1aFe9e6E7193);

    /*//////////////////////////////////////////////////////////////
                                SET UP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        _gateway = new TryLSDGateway();
    }

    /*//////////////////////////////////////////////////////////////
                            CONTRACT TESTS
    //////////////////////////////////////////////////////////////*/

//    function testDepositAndSwap() public {
//        // setup our deposit user
//        address userDeposit = vm.addr(0x200);
//        // give 100 eth
//        vm.deal(userDeposit, 100 ether);
//        // deposit 10 eth to the gateway
//
//        assertEq(_tryLSD.balanceOf(userDeposit), 0);
//
//        // estimate amount of shares user should get, for slippage
//        uint256 calculatedShares = _gateway.calculatePoolShares(10 ether);
//        // 0.1% slippage
//        uint256 minShares = (calculatedShares * 999) / 1000;
//
//        // Prepare to check deposit event
//        vm.expectEmit(true, true, false, false, address(_gateway));
//        // We emit the event we expect to see.
//        emit Deposit(userDeposit, userDeposit, 0, 0);
//
//        // deposit 0 eth to the gateway: TooLittleEthError
//        vm.expectRevert(0x4b1175db);
//        vm.prank(userDeposit);
//        _gateway.swapAndDeposit{value: 0 ether}(userDeposit, minShares);
//
//        // deposit 10 eth to the gateway but with too high slippage: MinSharesSlippageError
//        vm.expectRevert(0x8517304e);
//        vm.prank(userDeposit);
//        _gateway.swapAndDeposit{value: 10 ether}(userDeposit, minShares * 2);
//
//        // deposit 10 eth to the gateway
//        vm.prank(userDeposit);
//        uint256 shares = _gateway.swapAndDeposit{value: 10 ether}(
//            userDeposit,
//            minShares
//        );
//
//        // quick slippage check
//        assertGt(shares, minShares);
//        // check that the pool shares were minted
//        assertEq(_tryLSD.balanceOf(userDeposit), shares);
//        // check the pool shares amount
//        assertGt(_tryLSD.balanceOf(userDeposit), 3e18);
//    }

    function testDepositAndSwapLargeAmount() public {
        // setup our deposit user
        address userDeposit = vm.addr(0x200);

        uint depositAmount = 10000 ether;
        // give 100 eth
        vm.deal(userDeposit, 100000 ether);
        // deposit 10 eth to the gateway

        assertEq(_tryLSD.balanceOf(userDeposit), 0);

        // estimate amount of shares user should get, for slippage
        uint256 calculatedShares = _gateway.calculatePoolShares(depositAmount);
        // 0.1% slippage
        uint256 minShares = (calculatedShares * 999) / 1000;

        // Prepare to check deposit event
        vm.expectEmit(true, true, false, false, address(_gateway));
        // We emit the event we expect to see.
        emit Deposit(userDeposit, userDeposit, 0, 0);

        // deposit large deposit to the gateway
        vm.prank(userDeposit);
        uint256 shares = _gateway.swapAndDeposit{value: depositAmount}(
            userDeposit,
            minShares
        );

        console.log("shares", shares);
        console.log("minShares", minShares);

        // quick slippage check
        assertGt(shares, minShares);
        // check that the pool shares were minted
        assertEq(_tryLSD.balanceOf(userDeposit), shares);
        // check the pool shares amount
        assertGt(_tryLSD.balanceOf(userDeposit), 3e18);


        address userEthReceiver = vm.addr(0x202);

        vm.prank(userDeposit);
        _tryLSD.approve(address(_gateway), shares);

        console.log("vm.prank");
        vm.prank(userDeposit);
        console.log("withdrawAndSwap");
        uint256 ethReceived = _gateway.withdrawAndSwap(
            userEthReceiver,
            shares,
            0
        );

        console.log("ethReceived", ethReceived);


        uint256 minEthOnWithdrawal = (depositAmount * 995) / 1000;

        console.log("minEthOnWithdrawal", minEthOnWithdrawal);
        // quick slippage check of 1%
        assertGt(ethReceived, minEthOnWithdrawal);
    }

    function testWithdrawAndSwap() public {
        // setup our deposit user
        address userDeposit = vm.addr(0x200);
        address userEthReceiver = vm.addr(0x201);
        // give 100 eth
        vm.deal(userDeposit, 100 ether);
        // deposit 10 eth to the gateway
        // estimate amount of shares user should get, for slippage
        uint256 calculatedShares = _gateway.calculatePoolShares(10 ether);
        // 0.1% slippage
        uint256 minShares = (calculatedShares * 999) / 1000;
        // deposit 10 eth to the gateway
        vm.prank(userDeposit);
        uint256 shares = _gateway.swapAndDeposit{value: 10 ether}(
            userDeposit,
            minShares
        );

        // approve pool shares tokens transfer to the gateway
        vm.prank(userDeposit);
        _tryLSD.approve(address(_gateway), shares);

        // calculate amount of eth that user should receive
        uint256 calculatedEth = _gateway.calculateEth(shares);

        // 0.1% slippage
        uint256 minEth = (calculatedEth * 999) / 1000;

        // withdraw 0 shares from the gateway: TooLittleSharesError();
        vm.expectRevert(0xe8471aeb);
        vm.prank(userDeposit);
        _gateway.withdrawAndSwap(userEthReceiver, 0, minEth);

        // withdraw more shares than user has from the gateway
        vm.expectRevert();
        vm.prank(userDeposit);
        _gateway.withdrawAndSwap(userEthReceiver, shares + 1, minEth);

        // withdraw shares but set slippage too high: MinEthSlippageError
        vm.expectRevert(0xfe0d2edb);
        vm.prank(userDeposit);
        _gateway.withdrawAndSwap(userEthReceiver, shares, minEth * 2);

        // Prepare to check deposit event
        vm.expectEmit(true, true, true, false, address(_gateway));
        // We emit the event we expect to see.
        emit Withdraw(userDeposit, userEthReceiver, userDeposit, 0, 0);

        // withdraw
        vm.prank(userDeposit);
        uint256 ethReceived = _gateway.withdrawAndSwap(
            userEthReceiver,
            shares,
            minEth
        );
        // quick slippage check
        assertGt(ethReceived, minEth);
        // check that the eth was sent
        assertEq(userEthReceiver.balance, ethReceived);
        // check eth amount
        assertGt(userEthReceiver.balance, 999e16);
    }
}
