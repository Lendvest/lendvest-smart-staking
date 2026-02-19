// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {LVLidoVault} from "../src/LVLidoVault.sol";

contract SetAutomationAddress is Script {
    function run() public {
        vm.startBroadcast();

        // REPLACE WITH YOUR LVLIDO ADDRESS
        address payable lvlidoAddress = payable(0xC4c52D111d1CFd0D7Fc4a336C931F41EeF1f1456);
        LVLidoVault lvlido = LVLidoVault(lvlidoAddress);

        // REPLACE WITH YOUR LVLIDO VAULT UTIL ADDRESS
        lvlido.setLVLidoVaultUtilAddress(0x700b75181F8168C6533D85FDA776f50850a9Db31);

        vm.stopBroadcast();
    }
}
