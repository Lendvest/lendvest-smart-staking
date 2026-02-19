// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {LiquidationProxy} from "../src/LiquidationProxy.sol";

contract ConfigureLiquidationProxy is Script {
    function run() public {
        vm.startBroadcast();

        // REPLACE WITH YOUR LIQUIDATION PROXY ADDRESS
        address payable proxyAddress = payable(0xc48A0491a1A08975885B6949dfddFd49C4BFB13B);
        LiquidationProxy liquidationProxy = LiquidationProxy(proxyAddress);

        // REPLACE WITH YOUR LVLIDO VAULT ADDRESS
        liquidationProxy.setLVLidoVault(0xC4c52D111d1CFd0D7Fc4a336C931F41EeF1f1456);

        vm.stopBroadcast();
    }
}
