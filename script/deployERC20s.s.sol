// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {LVToken} from "../src/LVToken.sol";

contract DeployERC20s is Script {
    // Ethereum Mainnet Addresses
    address public constant WSTETH_ADDRESS = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address public constant WETH_ADDRESS = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    IERC20 public weth;
    IERC20 public wsteth;

    function run() public {
        vm.startBroadcast();

        // 1. Deploy LVWETH
        weth = IERC20(WETH_ADDRESS);
        LVToken lvweth = new LVToken("LVE WETH", "LVWETH");
        console.log("LVWETH deployed at:", address(lvweth));

        // 2. Deploy LVToken
        LVToken lvwsteth = new LVToken("LVE WSTETH", "LVWSTETH");
        console.log("LVWSTETH deployed at:", address(lvwsteth));

        vm.stopBroadcast();
    }
}
