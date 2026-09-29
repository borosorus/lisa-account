// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";

import {LisaAccount} from "../src/LisaAccount.sol";

contract DeployLisaAccount is Script {
    function run() external returns (LisaAccount account) {
        address runtime = vm.envAddress("LISA_RUNTIME");

        vm.startBroadcast();
        account = new LisaAccount(runtime);
        vm.stopBroadcast();
    }
}
