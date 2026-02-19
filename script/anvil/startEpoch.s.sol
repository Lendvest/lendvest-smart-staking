// SPDX-License-Identifier: MIT
/*
  forge script script/anvil/startEpoch.s.sol:StartEpoch --rpc-url http://127.0.0.1:8545 --broadcast --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
*/
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {LVLidoVault} from "../../src/LVLidoVault.sol";

contract StartEpoch is Script {
    // Ethereum Mainnet Addresses
    address public constant LVLIDOVAULT_ADDRESS = 0xE951fe9a680E1249dBE463Dd14a6d7061442bc9F;

    function run() public {
        vm.startBroadcast();

        LVLidoVault lvLidoVault = LVLidoVault(payable(LVLIDOVAULT_ADDRESS));
        lvLidoVault.startEpoch();
        vm.stopBroadcast();
    }
}
