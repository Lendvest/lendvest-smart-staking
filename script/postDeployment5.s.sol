// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {UpkeepAdmin} from "../src/UpkeepAdmin.sol";

contract UpkeepAdminTransfer is Script {
    function run() public {
        vm.startBroadcast();

        // First cast to payable address, then to contract
        address upkeepAdminAddress = 0x17C5B8550989ca3593827a0f335BD213F2C57C01;
        UpkeepAdmin upkeepAdmin = UpkeepAdmin(upkeepAdminAddress);
        upkeepAdmin.acceptUpkeepAdmin(36653741063921031869740428403356924300134765658190440492019233757663320393334);

        vm.stopBroadcast();
    }
}
