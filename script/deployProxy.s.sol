// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {LiquidationProxy} from "../src/LiquidationProxy.sol";

contract DeployLiquidationProxy is Script {
    function run() public {
        vm.startBroadcast();
        address ajnaPoolAddress = 0x6F96a8dF4a22A4Cc6a323755Cb0463C45946BC61;
        LiquidationProxy liquidationProxy = new LiquidationProxy(ajnaPoolAddress);
        console.log("LiquidationProxy deployed at:", address(liquidationProxy));

        vm.stopBroadcast();
    }
}
