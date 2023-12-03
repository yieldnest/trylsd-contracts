// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";

import {ICurvePool1} from "../interfaces/ICurvePool.sol";
import {ICurvePool2} from "../interfaces/ICurvePool.sol";

import {IsfrxETH} from "../interfaces/IsfrxETH.sol";
import {IWstETH} from "../interfaces/IWstETH.sol";

import "forge-std/console.sol";

contract TryLSDGateway {
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
                            CUSTOM ERRORS
    //////////////////////////////////////////////////////////////*/

    // should not send eth directly to this contract, use swapAndDeposit function
    error NotPayable();

    // Minimum amount of eth sent when deposit
    // 0x4b1175db
    error TooLittleEthError();

    // minimum amount of shares not met on swap and deposit
    // 0x8517304e
    error MinSharesSlippageError();

    // Minimum amount of shares sent on withdraw
    // 0xe8471aeb
    error TooLittleSharesError();

    // minimum amount of shares not met on withdraw and swap
    // 0xfe0d2edb
    error MinEthSlippageError();

    // transferFrom failed while withdrawing
    error TransferFromFailed();

    // failed to transfer eth back to user after withdraw and swap
    error FailedToSendEth();

    /*//////////////////////////////////////////////////////////////
                            EXTERNAL CONTRACTS
    //////////////////////////////////////////////////////////////*/

    // eth mainnet wsteth
    IWstETH internal immutable _wsteth =
        IWstETH(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
    // eth mainnet steth
    IERC20 internal _steth = IERC20(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);

    // eth mainnet reth
    IERC20 internal _reth = IERC20(0xae78736Cd615f374D3085123A210448E74Fc6393);

    // eth mainnet sfrxeth
    IsfrxETH internal _sfrxeth =
        IsfrxETH(0xac3E018457B222d93114458476f3E3416Abbe38F);
    // eth mainnet frxeth
    IERC20 internal _frxeth =
        IERC20(0x5E8422345238F34275888049021821E8E08CAa1f);

    // all the curve pools needed for swaps
    ICurvePool1 internal _ethToSteth =
        ICurvePool1(0xDC24316b9AE028F1497c275EB9192a3Ea0f67022);
    ICurvePool2 internal _ethToReth =
        ICurvePool2(0x0f3159811670c117c372428D4E69AC32325e4D0F);
    ICurvePool1 internal _ethToFrxeth =
        ICurvePool1(0xa1F8A6807c402E4A15ef4EBa36528A3FED24E577);

    // curve tryLSD mainnet pool
    ICurvePool2 internal _tryLSD =
        ICurvePool2(0x2570f1bD5D2735314FC102eb12Fc1aFe9e6E7193);

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor() {
        // unlimited approve will be used to add liquidity to the tryLSD pool
        _wsteth.approve(address(_tryLSD), type(uint256).max);
        _reth.approve(address(_tryLSD), type(uint256).max);
        _sfrxeth.approve(address(_tryLSD), type(uint256).max);

        // unlimited approve will be used to wrap steth to wsteth
        _steth.approve(address(_wsteth), type(uint256).max);
        // unlimited approve will be used to wrap frxeth to sfrxeth
        _frxeth.approve(address(_sfrxeth), type(uint256).max);

        // unlimited approve will be used to swap steth to eth
        _steth.approve(address(_ethToSteth), type(uint256).max);
        // unlimited approve will be used to swap reth to eth
        _reth.approve(address(_ethToReth), type(uint256).max);
        // unlimited approve will be used to swap frxeth to eth
        _frxeth.approve(address(_ethToFrxeth), type(uint256).max);
    }

    /*//////////////////////////////////////////////////////////////
                            PAYABLE LOGIC
    //////////////////////////////////////////////////////////////*/

    bool _startedWithdraw;

    fallback() external payable {
        // should not send eth directly to this contract, use swapAndDeposit function
        if (_startedWithdraw == false) revert NotPayable();

        return;
    }

    receive() external payable {
        // should not send eth directly to this contract, use swapAndDeposit function
        if (_startedWithdraw == false) revert NotPayable();

        return;
    }

    /*//////////////////////////////////////////////////////////////
                            DEPOSIT LOGIC
    //////////////////////////////////////////////////////////////*/

    function calculatePoolShares(
        uint256 depositAmount
    ) public view returns (uint256 shares) {
        uint256 singleSwapAmount = depositAmount / 3;

        // for get_dy asset 0 is eth, asset 1 is steth
        uint256 stethAmount = _ethToSteth.get_dy(0, 1, singleSwapAmount);
        // calculate the amount of wsteth we get for stethAmount of eth
        uint256 wstethAmount = _wsteth.getWstETHByStETH(stethAmount);
        // for get_dy asset 0 is eth, asset 1 is reth
        uint256 rethAmount = _ethToReth.get_dy(0, 1, singleSwapAmount);
        // for get_dy asset 0 is eth, asset 1 is frxeth
        uint256 frxethAmount = _ethToFrxeth.get_dy(0, 1, singleSwapAmount);
        // calculate the amount of sfrxeth we get for frxethAmount of eth
        uint256 sfrxethAmount = _sfrxeth.convertToShares(frxethAmount);

        // finally calculate the amount of pool shares we get for the 3 tokens
        shares = _tryLSD.calc_token_amount(
            [wstethAmount, rethAmount, sfrxethAmount],
            true
        );
    }

    function swapAndDeposit(
        address owner,
        uint256 minShares
    ) public payable returns (uint256 shares) {
        // should send more than 0 eth
        if (msg.value == 0) revert TooLittleEthError();

        uint256 singleSwapAmount = msg.value / 3;

        // exchange from eth to steth, target amount and minAmount (for slippage)
        uint256 stethAmount = _ethToSteth.exchange{value: singleSwapAmount}(
            0,
            1,
            singleSwapAmount,
            0 // min amount set to 0 because we check pool shares for slippage
        );
        // then wrap to wsteth
        uint256 wstethAmount = _wsteth.wrap(stethAmount);
        // exchange from eth to steth, target amount and minAmount (for slippage)
        uint256 rethAmount = _ethToReth.exchange_underlying{
            value: singleSwapAmount
        }(
            0,
            1,
            singleSwapAmount,
            0 // min amount set to 0 because we check pool shares for slippage
        );
        // exchange from eth to steth, target amount and minAmount (for slippage)
        uint256 frxethAmount = _ethToFrxeth.exchange{value: singleSwapAmount}(
            0,
            1,
            singleSwapAmount,
            0 // min amount set to 0 because we check pool shares for slippage
        );
        // then wrap to sfrxeth
        uint256 sfrxethAmount = _sfrxeth.deposit(frxethAmount, address(this));

        // add liquidity to pool
        shares = _tryLSD.add_liquidity(
            [wstethAmount, rethAmount, sfrxethAmount],
            0, // min shares set to 0 because I check myself for slippage
            false,
            owner
        );

        // Check slippage
        if (shares <= minShares) revert MinSharesSlippageError();

        // emit deposit event
        emit Deposit(msg.sender, owner, msg.value, shares);
    }

    function swapAndDepositREth(
        address owner,
        uint256 minShares
    ) public payable returns (uint256 shares) {
        // should send more than 0 eth
        if (msg.value == 0) revert TooLittleEthError();

        uint256 singleSwapAmount = msg.value;

        // exchange from eth to steth, target amount and minAmount (for slippage)
        uint256 rethAmount = _ethToReth.exchange_underlying{
                value: singleSwapAmount
            }(
            0,
            1,
            singleSwapAmount,
            0 // min amount set to 0 because we check pool shares for slippage
        );

        // add liquidity to pool
        shares = _tryLSD.add_liquidity(
            [0, rethAmount, 0],
            0, // min shares set to 0 because I check myself for slippage
            false,
            owner
        );

        // Check slippage
        if (shares <= minShares) revert MinSharesSlippageError();

        // emit deposit event
        emit Deposit(msg.sender, owner, msg.value, shares);
    }

    /*//////////////////////////////////////////////////////////////
                            WITHDRAW LOGIC
    //////////////////////////////////////////////////////////////*/

    function calculateEth(
        uint256 shares
    ) public view returns (uint256 ethAmount) {
        uint256 totalSupply = _tryLSD.totalSupply();

        uint256 wstethAmount = (_tryLSD.balances(0) * shares) / totalSupply;
        uint256 rethAmount = (_tryLSD.balances(1) * shares) / totalSupply;
        uint256 sfrxethAmount = (_tryLSD.balances(2) * shares) / totalSupply;

        // calculate the amount of eth we get for singleSwapAmount of wsteth
        // for get_dy asset 0 is eth, asset 1 is frxeth
        ethAmount = _ethToSteth.get_dy(
            1,
            0,
            _wsteth.getStETHByWstETH(wstethAmount)
        );
        // calculate the amount of eth we get for singleSwapAmount of reth
        // for get_dy asset 0 is eth, asset 1 is frxeth
        ethAmount += _ethToReth.get_dy(1, 0, rethAmount);
        // calculate the amount of eth we get for singleSwapAmount of sfrxeth
        // for get_dy asset 0 is eth, asset 1 is frxeth
        ethAmount += _ethToFrxeth.get_dy(
            1,
            0,
            _sfrxeth.convertToAssets(sfrxethAmount)
        );
    }

    function withdrawAndSwap(
        address receiver,
        uint256 shares,
        uint256 minEth
    ) public payable returns (uint256 ethAmount) {
        // this variable is to prevent a loop where pool would send eth to the gateway and trigger a deposit
        _startedWithdraw = true;

        // should send more than 0 shares
        if (shares == 0) revert TooLittleSharesError();

        bool success = _tryLSD.transferFrom(msg.sender, address(this), shares);

        // this might be useless as transferFrom will revert itself if it fails
        if (success == false) revert TransferFromFailed();


        console.log("Debug 1");

        uint256[3] memory amounts = _tryLSD.remove_liquidity(
            shares,
            [uint256(0), uint256(0), uint256(0)],
            false,
            address(this)
        );

        // unwrap wsteth to steth
        uint256 stethAmount = _wsteth.unwrap(amounts[0]);
        // exchange steth to eth
        uint256 stethToEthAmount = _ethToSteth.exchange(
            1, // from steth
            0, // to eth
            stethAmount, // amount we got from unwrapping wsteth
            0 // min amount set to 0 because we check final eth amount for slippage
        );

        // exchange reth to eth
        uint256 rethToEthAmount = _ethToReth.exchange_underlying(
            1, // from reth
            0, // to eth
            amounts[1],
            0 // min amount set to 0 because we check final eth amount for slippage
        );

        // redeem frxeth from sfrxeth
        uint256 frxethAmount = _sfrxeth.redeem(
            amounts[2],
            address(this),
            address(this)
        );
        // exchange frxeth to eth
        uint256 frxethToEthAmount = _ethToFrxeth.exchange(
            1, // from frxeth
            0, // to eth
            frxethAmount,
            0 // min amount set to 0 because we check final eth amount for slippage
        );

        ethAmount = stethToEthAmount + rethToEthAmount + frxethToEthAmount;

        // Check slippage
        if (ethAmount <= minEth) revert MinEthSlippageError();

        (bool sent, ) = receiver.call{value: ethAmount}("");

        if (sent == false) revert FailedToSendEth();

        // emit withdraw event
        emit Withdraw(msg.sender, receiver, msg.sender, ethAmount, shares);

        // this variable is to prevent a loop where pool would send eth to the gateway and trigger a deposit
        _startedWithdraw = false;
    }
}
