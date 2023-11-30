// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.21 <0.9.0;

import { TryLSDGateway } from "../src/contracts/TryLSDGateway.sol";

import { BaseScript } from "./Base.s.sol";

/// @dev See the Solidity Scripting tutorial: https://book.getfoundry.sh/tutorials/solidity-scripting
contract DeployTryLSDGateway is BaseScript {
    function run() public broadcast returns (TryLSDGateway _gateway) {
        _gateway = new TryLSDGateway();
    }
}
