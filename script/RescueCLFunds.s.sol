// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title RescueCLFunds
/// @notice Rescue contract to recover stuck CL funds from old vault
/// @dev This contract gets set as LVLidoVaultUtil to call transferForProxy
contract CLRescuer {
    address public immutable oldVault;
    address public immutable recipient;
    address public constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;

    constructor(address _oldVault, address _recipient) {
        oldVault = _oldVault;
        recipient = _recipient;
    }

    /// @notice Rescue all wstETH from the old vault
    function rescue() external {
        uint256 balance = IERC20(WSTETH).balanceOf(oldVault);
        require(balance > 0, "No wstETH to rescue");

        // Call transferForProxy on old vault (we are the LVLidoVaultUtil)
        (bool success,) = oldVault.call(
            abi.encodeWithSignature(
                "transferForProxy(address,address,uint256)",
                WSTETH,
                recipient,
                balance
            )
        );
        require(success, "Transfer failed");

        console.log("Rescued wstETH:", balance);
        console.log("Sent to:", recipient);
    }
}

/// @title DeployRescue
/// @notice Deployment script for CL funds rescue
contract DeployRescue is Script {
    // Old vault with stuck funds
    address constant OLD_VAULT = 0x8EAc1f7a48600f04294519b579ac63Fffa920e64;
    // User wallet to receive rescued funds
    address constant RECIPIENT = 0x439dEAD08d45811d9eE380e58161BAA87F7e8757;
    // wstETH token
    address constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        // Check current state
        uint256 stuckBalance = IERC20(WSTETH).balanceOf(OLD_VAULT);
        console.log("=== RESCUE CL FUNDS ===");
        console.log("Old Vault:", OLD_VAULT);
        console.log("Stuck wstETH balance:", stuckBalance);
        console.log("Recipient:", RECIPIENT);

        vm.startBroadcast(deployerPrivateKey);

        // Step 1: Deploy rescuer contract
        CLRescuer rescuer = new CLRescuer(OLD_VAULT, RECIPIENT);
        console.log("Rescuer deployed at:", address(rescuer));

        // Step 2: Set rescuer as LVLidoVaultUtil on old vault
        // This requires the caller to be the vault owner
        (bool setSuccess,) = OLD_VAULT.call(
            abi.encodeWithSignature(
                "setLVLidoVaultUtilAddress(address)",
                address(rescuer)
            )
        );
        require(setSuccess, "Failed to set LVLidoVaultUtil");
        console.log("Set rescuer as LVLidoVaultUtil");

        // Step 3: Execute rescue
        rescuer.rescue();

        vm.stopBroadcast();

        // Verify
        uint256 newVaultBalance = IERC20(WSTETH).balanceOf(OLD_VAULT);
        uint256 recipientBalance = IERC20(WSTETH).balanceOf(RECIPIENT);
        console.log("=== RESCUE COMPLETE ===");
        console.log("Old vault wstETH balance:", newVaultBalance);
        console.log("Recipient wstETH balance:", recipientBalance);
    }
}
