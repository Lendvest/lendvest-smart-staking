// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {LVLidoVault} from "../src/LVLidoVault.sol";
import {LVLidoVaultUtil} from "../src/LVLidoVaultUtil.sol";

contract OwnershipTransfer2 is Script {
    function run() public {
        vm.startBroadcast();

        address payable lvlidoAddress = payable(0xE951fe9a680E1249dBE463Dd14a6d7061442bc9F);
        LVLidoVault lvlido = LVLidoVault(lvlidoAddress);
        address lvlidoVaultUtilAddress = 0x33129398782e26D2f3aCEc28D88b5500cA0cea0a;
        LVLidoVaultUtil lvlidoVaultUtil = LVLidoVaultUtil(lvlidoVaultUtilAddress);
        lvlido.renounceOwnership();
        lvlidoVaultUtil.renounceOwnership();
        vm.stopBroadcast();
    }
}
