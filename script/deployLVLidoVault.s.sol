// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {LVLidoVault} from "../src/LVLidoVault.sol";

contract DeployLVLidoVault is Script {
    // Ethereum Mainnet Addresses

    // LVLidoVault Variables
    address public constant AJNA_POOL_ADDRESS = 0x6F96a8dF4a22A4Cc6a323755Cb0463C45946BC61;
    address public constant LIQUIDATION_PROXY_ADDRESS = 0xc48A0491a1A08975885B6949dfddFd49C4BFB13B;

    function run() public {
        vm.startBroadcast();
        LVLidoVault lvlido = new LVLidoVault(AJNA_POOL_ADDRESS, LIQUIDATION_PROXY_ADDRESS);
        console.log("LVLidoVault deployed at:", address(lvlido));

        vm.stopBroadcast();
    }
}
