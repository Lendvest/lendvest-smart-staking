// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {LVToken} from "../src/LVToken.sol";

/**
 * @title Transfer Token Ownership to Admin
 * @notice Run this ONLY if deployer != ADMIN_WALLET
 * @dev After this, ADMIN_WALLET controls setAllowed() on both tokens.
 *      ADMIN_WALLET can later:
 *        - setAllowed(self, false) to revoke own mint/burn access
 *        - renounceOwnership() to lock the allowlist permanently
 */
contract TransferTokenOwnership is Script {
    // v5 deployment (Jan 23, 2026)
    address public constant LVWETH_ADDRESS = 0xd671bFEbc8906CeC9a9f072516719D95562165EA;
    address public constant LVWSTETH_ADDRESS = 0xCEEE4Cfa90E71B34eCD50F76D7BEB9669526c656;
    address public constant ADMIN_WALLET = 0x64ec61145EC91F2F6370AAbDF977cE359748e507;

    function run() public {
        require(LVWETH_ADDRESS != address(0), "Set LVWETH_ADDRESS first");
        require(LVWSTETH_ADDRESS != address(0), "Set LVWSTETH_ADDRESS first");

        console.log("Transferring token ownership to ADMIN_WALLET:", ADMIN_WALLET);

        vm.startBroadcast();

        LVToken(LVWETH_ADDRESS).transferOwnership(ADMIN_WALLET);
        console.log("  LVWETH ownership transferred");

        LVToken(LVWSTETH_ADDRESS).transferOwnership(ADMIN_WALLET);
        console.log("  LVWSTETH ownership transferred");

        vm.stopBroadcast();

        console.log("");
        console.log("Done. ADMIN_WALLET now controls setAllowed() on both tokens.");
        console.log("To revoke admin mint/burn access later:");
        console.log("  lvweth.setAllowed(ADMIN_WALLET, false)");
        console.log("  lvwsteth.setAllowed(ADMIN_WALLET, false)");
        console.log("To lock config permanently:");
        console.log("  lvweth.renounceOwnership()");
        console.log("  lvwsteth.renounceOwnership()");
    }
}
