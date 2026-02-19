// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {LVLidoVaultUtil} from "../src/LVLidoVaultUtil.sol";

contract SetForwarderAddress is Script {
    function run() public {
        vm.startBroadcast();

        // REPLACE WITH YOUR LVLIDO VAULT UTIL (AUTOMATION CONTRACT) ADDRESS
        address payable proxyAddress = payable(0x700b75181F8168C6533D85FDA776f50850a9Db31);
        LVLidoVaultUtil lvlidoVaultUtil = LVLidoVaultUtil(proxyAddress);

        // REPLACE WITH YOUR FORWARDER ADDRESS
        lvlidoVaultUtil.setForwarderAddress(0x29E01F0d36874e343e603C25F54be4D4074e36A9);

        vm.stopBroadcast();
    }
}
