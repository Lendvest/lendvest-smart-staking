// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {LVLidoVaultUtilRescue} from "../src/LVLidoVaultUtilRescue.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ILVLidoVault} from "../src/interfaces/ILVLidoVault.sol";

/**
 * @title DeployRescueEpoch
 * @notice Deploys rescue VaultUtil, sets it, closes epoch 1, and restores original VaultUtil
 *
 * @dev Usage:
 *   Fork test:  forge script script/DeployRescueEpoch.s.sol --rpc-url $ALCHEMY_RPC_URL --via-ir -vvvv
 *   Mainnet:    forge script script/DeployRescueEpoch.s.sol --rpc-url $ALCHEMY_RPC_URL --private-key $PRIVATE_KEY --broadcast --via-ir -vvvv
 */
contract DeployRescueEpoch is Script {
    // Current v7 vault
    address constant VAULT = 0x44A3EaBCb0Fd127C840924f955B50dd210424ccB;
    // Current VaultUtil to restore after rescue
    address constant ORIGINAL_VAULT_UTIL = 0x3bD82613faC6470eFfC44739Be37d2768E30850b;
    // wstETH and WETH for balance checks
    address constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    function run() external {
        ILVLidoVault vault = ILVLidoVault(VAULT);

        // --- Pre-flight checks ---
        console.log("=== PRE-FLIGHT CHECKS ===");
        console.log("Vault:", VAULT);
        console.log("Epoch started:", vault.epochStarted());
        console.log("Funds queued:", vault.fundsQueued());
        console.log("Request ID:", vault.requestId());
        console.log("Total borrow amount:", vault.totalBorrowAmount());
        console.log("Total lender QT utilized:", vault.totalLenderQTUtilized());
        console.log("Total lender QT unutilized:", vault.totalLenderQTUnutilized());
        console.log("Total borrower CT:", vault.totalBorrowerCT());
        console.log("Total CL deposits utilized:", vault.totalCLDepositsUtilized());
        console.log("Total CL deposits unutilized:", vault.totalCLDepositsUnutilized());
        console.log("wstETH balance:", IERC20(WSTETH).balanceOf(VAULT));
        console.log("WETH balance:", IERC20(WETH).balanceOf(VAULT));
        console.log("ETH balance:", VAULT.balance);

        require(vault.epochStarted(), "Epoch not started - nothing to rescue");
        require(vault.fundsQueued(), "Funds not queued - epoch not ready to close");

        vm.startBroadcast();

        // Step 1: Deploy rescue contract
        LVLidoVaultUtilRescue rescue = new LVLidoVaultUtilRescue(VAULT);
        console.log("=== RESCUE DEPLOYED ===");
        console.log("Rescue contract:", address(rescue));

        // Step 2: Set rescue contract as VaultUtil (owner only)
        (bool setSuccess,) = VAULT.call(
            abi.encodeWithSignature("setLVLidoVaultUtilAddress(address)", address(rescue))
        );
        require(setSuccess, "Failed to set rescue as VaultUtil");
        console.log("Set rescue as LVLidoVaultUtil");

        // Step 3: Execute closeEpoch via rescue contract
        rescue.performTask();
        console.log("=== EPOCH CLOSED ===");

        // Step 4: Restore original VaultUtil
        (bool restoreSuccess,) = VAULT.call(
            abi.encodeWithSignature("setLVLidoVaultUtilAddress(address)", ORIGINAL_VAULT_UTIL)
        );
        require(restoreSuccess, "Failed to restore original VaultUtil");
        console.log("Restored original LVLidoVaultUtil:", ORIGINAL_VAULT_UTIL);

        vm.stopBroadcast();

        // --- Post-flight verification ---
        console.log("=== POST-FLIGHT VERIFICATION ===");
        console.log("Epoch started:", vault.epochStarted());
        console.log("Funds queued:", vault.fundsQueued());
        console.log("Total lender QT utilized:", vault.totalLenderQTUtilized());
        console.log("Total lender QT unutilized:", vault.totalLenderQTUnutilized());
        console.log("Total borrower CT:", vault.totalBorrowerCT());
        console.log("Total borrower CT unutilized:", vault.totalBorrowerCTUnutilized());
        console.log("Total CL deposits utilized:", vault.totalCLDepositsUtilized());
        console.log("Total CL deposits unutilized:", vault.totalCLDepositsUnutilized());
        console.log("wstETH balance:", IERC20(WSTETH).balanceOf(VAULT));
        console.log("WETH balance:", IERC20(WETH).balanceOf(VAULT));

        require(!vault.epochStarted(), "FAIL: epoch still started");
        require(!vault.fundsQueued(), "FAIL: funds still queued");
        require(vault.totalLenderQTUtilized() == 0, "FAIL: lender QT utilized not zero");
        require(vault.totalCLDepositsUtilized() == 0, "FAIL: CL utilized not zero");
        require(vault.totalCLDepositsUnutilized() == 0, "FAIL: CL unutilized not zero");

        console.log("=== ALL CHECKS PASSED ===");
    }
}
