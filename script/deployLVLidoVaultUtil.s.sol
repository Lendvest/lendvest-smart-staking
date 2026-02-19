// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {LVLidoVaultUtil} from "../src/LVLidoVaultUtil.sol";

contract DeployLVLidoVaultUtil is Script {
    // Ethereum Mainnet Addresses

    // LVLidoVault Variables
    address public constant LVLIDOVAULT_ADDRESS = 0xC4c52D111d1CFd0D7Fc4a336C931F41EeF1f1456;

    function run() public {
        vm.startBroadcast();
        LVLidoVaultUtil lvlidoUtil = new LVLidoVaultUtil(LVLIDOVAULT_ADDRESS);
        console.log("LVLidoVaultUtil deployed at:", address(lvlidoUtil));

        vm.stopBroadcast();
    }
}
