// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {LVLidoVaultUpkeeper} from "../src/LVLidoVaultUpkeeper.sol";

contract DeployUpkeeper is Script {
    address public constant NEW_VAULT = 0x4fF9747C334bF2dfE3773Bb1Ca9Cc46fc55B6369;

    function run() public {
        vm.startBroadcast();
        LVLidoVaultUpkeeper upkeeper = new LVLidoVaultUpkeeper(NEW_VAULT);
        console.log("LVLidoVaultUpkeeper deployed at:", address(upkeeper));
        vm.stopBroadcast();
    }
}
