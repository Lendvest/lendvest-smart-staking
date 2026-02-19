// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {UpkeepAdmin} from "../src/UpkeepAdmin.sol";

contract DeployUpkeepAdmin is Script {
    // Ethereum SEPOLIA Addresses
    address public constant UPKEEP_REGISTRY_ADDRESS = 0x6593c7De001fC8542bB1703532EE1E5aA0D458fD;
    address public constant LINK_TOKEN_ADDRESS = 0x514910771AF9Ca656af840dff83E8264EcF986CA;

    function run() public {
        vm.startBroadcast();

        IERC20 linkToken = IERC20(LINK_TOKEN_ADDRESS);
        UpkeepAdmin upkeepAdmin = new UpkeepAdmin(UPKEEP_REGISTRY_ADDRESS, LINK_TOKEN_ADDRESS);

        console.log("Upkeep Admin deployed at:", address(upkeepAdmin));
        vm.stopBroadcast();
    }
}
