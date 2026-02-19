// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {IERC20PoolFactory} from "../src/interfaces/pool/erc20/IERC20PoolFactory.sol";

contract DeployPool is Script {
    // Ethereum Mainnet Addresses
    address public constant POOL_FACTORY_ADDRESS = 0x6146DD43C5622bB6D12A5240ab9CF4de14eDC625;
    address public constant LVWETH_ADDRESS = 0x2a6C668E0daBcbf7579b06d8955315A8B48494D5;
    address public constant LVWSTETH_ADDRESS = 0x87394fdE469B13B04706EaB79c0AE2B25DE63345;
    uint256 public POOL_RATE = 1e16; // 0.01 or 1%

    function run() public {
        vm.startBroadcast();

        IERC20PoolFactory poolFactory = IERC20PoolFactory(POOL_FACTORY_ADDRESS);
        address ajnaPoolAddress = poolFactory.deployPool(LVWSTETH_ADDRESS, LVWETH_ADDRESS, POOL_RATE);

        console.log("Ajna Pool deployed at:", ajnaPoolAddress);
        vm.stopBroadcast();
    }
}
