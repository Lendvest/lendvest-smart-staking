// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20PoolFactory} from "../src/interfaces/pool/erc20/IERC20PoolFactory.sol";
import {LVToken} from "../src/LVToken.sol";
import {LiquidationProxy} from "../src/LiquidationProxy.sol";
import {LVLidoVault} from "../src/LVLidoVault.sol";
import {LVLidoVaultUtil} from "../src/LVLidoVaultUtil.sol";
import {LVLidoVaultReader} from "../src/LVLidoVaultReader.sol";
import {LVLidoVaultUpkeeper} from "../src/LVLidoVaultUpkeeper.sol";

/**
 * @title Complete Deployment Script (Versioned)
 * @notice Deploys and configures all contracts in a single transaction.
 *         Each run creates UNIQUE tokens with versioned names to prevent
 *         ownership conflicts from prior deployments.
 *
 * @dev DEPLOYMENT CHECKLIST (read before --broadcast):
 *      1. Increment DEPLOYMENT_VERSION below
 *      2. Verify ADMIN_WALLET is correct
 *      3. Ensure no user funds remain in old vault
 *      4. Have sufficient ETH for gas (~0.2 ETH)
 *      5. After deployment: update frontend lvLidoVault.ts with new addresses
 *      6. After deployment: create new Chainlink subscriptions
 *
 * @dev DEPLOY COMMAND (with auto-verification):
 *      forge script script/deployAll.s.sol:DeployAll \
 *          --rpc-url $RPC_URL \
 *          --private-key $PRIVATE_KEY \
 *          --broadcast --verify -vvv
 */
contract DeployAll is Script {
    // =============================================================
    //                    DEPLOYMENT VERSION
    // =============================================================
    // INCREMENT THIS FOR EVERY NEW DEPLOYMENT
    // This ensures unique token names and prevents address confusion
    uint256 public constant DEPLOYMENT_VERSION = 10;

    // =============================================================
    //                    ACCESS CONTROL
    // =============================================================
    // Admin wallet that retains mint/burn access for rescue operations.
    // This wallet can later revoke its own access via setAllowed(self, false)
    // or renounce token ownership entirely via renounceOwnership().
    address public constant ADMIN_WALLET = 0x3F0976C7007F50b0BA5EFe00764fCFB251656D4f;

    // =============================================================
    //                    ETHEREUM MAINNET ADDRESSES
    // =============================================================
    address public constant WSTETH_ADDRESS = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address public constant WETH_ADDRESS = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant POOL_FACTORY_ADDRESS = 0x6146DD43C5622bB6D12A5240ab9CF4de14eDC625;

    // =============================================================
    //                    DEPLOYMENT PARAMETERS
    // =============================================================
    uint256 public constant POOL_RATE = 1e16; // 0.01 or 1%

    // =============================================================
    //                    DEPLOYED CONTRACTS
    // =============================================================
    LVToken public lvweth;
    LVToken public lvwsteth;
    address public ajnaPool;
    LiquidationProxy public liquidationProxy;
    LVLidoVault public lvLidoVault;
    LVLidoVaultReader public lvLidoVaultReader;
    LVLidoVaultUtil public lvLidoVaultUtil;
    LVLidoVaultUpkeeper public lvLidoVaultUpkeeper;

    function run() public {
        // =============================================================
        //                    PRE-DEPLOYMENT CHECKS
        // =============================================================
        console.log("=================================================================");
        console.log("       LENDVEST DEPLOYMENT v%s", DEPLOYMENT_VERSION);
        console.log("=================================================================");
        console.log("");
        console.log("ADMIN WALLET:", ADMIN_WALLET);
        console.log("POOL RATE:", POOL_RATE);
        console.log("");
        console.log("Token names will be:");
        console.log("  LVWETH-v%s", DEPLOYMENT_VERSION);
        console.log("  LVWSTETH-v%s", DEPLOYMENT_VERSION);
        console.log("");
        console.log("IMPORTANT: Ensure no user funds remain in previous vault!");
        console.log("=================================================================");
        console.log("");

        vm.startBroadcast();

        // =============================================================
        //                    STEP 1: DEPLOY TOKENS (Unique per version)
        // =============================================================
        console.log("=== STEP 1: Deploying LVTokens (v%s) ===", DEPLOYMENT_VERSION);

        string memory wethName = string(abi.encodePacked("LVWETH-v", _uint2str(DEPLOYMENT_VERSION)));
        string memory wethSymbol = string(abi.encodePacked("LVWETH", _uint2str(DEPLOYMENT_VERSION)));
        string memory wstethName = string(abi.encodePacked("LVWSTETH-v", _uint2str(DEPLOYMENT_VERSION)));
        string memory wstethSymbol = string(abi.encodePacked("LVWSTETH", _uint2str(DEPLOYMENT_VERSION)));

        lvweth = new LVToken(wethName, wethSymbol);
        console.log("LVWETH deployed at:", address(lvweth));

        lvwsteth = new LVToken(wstethName, wstethSymbol);
        console.log("LVWSTETH deployed at:", address(lvwsteth));

        // =============================================================
        //                    STEP 2: DEPLOY AJNA POOL
        // =============================================================
        console.log("\n=== STEP 2: Deploying Ajna Pool ===");
        IERC20PoolFactory poolFactory = IERC20PoolFactory(POOL_FACTORY_ADDRESS);
        ajnaPool = poolFactory.deployPool(address(lvwsteth), address(lvweth), POOL_RATE);
        console.log("Ajna Pool deployed at:", ajnaPool);

        // =============================================================
        //                    STEP 3: DEPLOY LIQUIDATION PROXY
        // =============================================================
        console.log("\n=== STEP 3: Deploying LiquidationProxy ===");
        liquidationProxy = new LiquidationProxy(ajnaPool);
        console.log("LiquidationProxy deployed at:", address(liquidationProxy));

        // =============================================================
        //                    STEP 4: DEPLOY VAULT
        // =============================================================
        console.log("\n=== STEP 4: Deploying LVLidoVault ===");
        lvLidoVault = new LVLidoVault(ajnaPool, address(liquidationProxy));
        console.log("LVLidoVault deployed at:", address(lvLidoVault));

        // =============================================================
        //                    STEP 5: DEPLOY READER
        // =============================================================
        console.log("\n=== STEP 5: Deploying LVLidoVaultReader ===");
        lvLidoVaultReader = new LVLidoVaultReader();
        console.log("LVLidoVaultReader deployed at:", address(lvLidoVaultReader));

        // =============================================================
        //                    STEP 6: DEPLOY UTIL
        // =============================================================
        console.log("\n=== STEP 6: Deploying LVLidoVaultUtil ===");
        lvLidoVaultUtil = new LVLidoVaultUtil(address(lvLidoVault));
        console.log("LVLidoVaultUtil deployed at:", address(lvLidoVaultUtil));

        // =============================================================
        //                    STEP 7: DEPLOY UPKEEPER
        // =============================================================
        console.log("\n=== STEP 7: Deploying LVLidoVaultUpkeeper ===");
        lvLidoVaultUpkeeper = new LVLidoVaultUpkeeper(address(lvLidoVault));
        console.log("LVLidoVaultUpkeeper deployed at:", address(lvLidoVaultUpkeeper));

        // =============================================================
        //                    STEP 8: CONFIGURE CONTRACTS
        // =============================================================
        console.log("\n=== STEP 8: Configuring Contracts ===");

        lvLidoVault.setLVLidoVaultUtilAddress(address(lvLidoVaultUtil));
        console.log("  Vault -> Util: set");

        lvLidoVault.setLVLidoVaultUpkeeperAddress(address(lvLidoVaultUpkeeper));
        console.log("  Vault -> Upkeeper: set");

        lvLidoVaultUtil.setLVLidoVaultUpkeeper(address(lvLidoVaultUpkeeper));
        console.log("  Util -> Upkeeper: set");

        lvLidoVaultUpkeeper.setLVLidoVaultUtil(address(lvLidoVaultUtil));
        console.log("  Upkeeper -> Util: set");

        liquidationProxy.setLVLidoVault(address(lvLidoVault));
        console.log("  Proxy -> Vault: set");

        // =============================================================
        //                    STEP 9: CONFIGURE ALLOWLIST (NOT transferOwnership)
        // =============================================================
        console.log("\n=== STEP 9: Configuring Token Allowlist ===");
        console.log("  Granting mint/burn access to vault AND admin...");

        // Grant vault mint/burn access
        lvweth.setAllowed(address(lvLidoVault), true);
        lvwsteth.setAllowed(address(lvLidoVault), true);
        console.log("  LVWETH  -> Vault allowed: true");
        console.log("  LVWSTETH -> Vault allowed: true");

        // Grant admin wallet mint/burn access (for rescue operations)
        lvweth.setAllowed(ADMIN_WALLET, true);
        lvwsteth.setAllowed(ADMIN_WALLET, true);
        console.log("  LVWETH  -> Admin allowed: true");
        console.log("  LVWSTETH -> Admin allowed: true");

        // Transfer LiquidationProxy ownership to vault (proxy pattern unchanged)
        liquidationProxy.transferOwnership(address(lvLidoVault));
        console.log("  LiquidationProxy ownership -> Vault");

        // NOTE: Token ownership stays with deployer (ADMIN_WALLET should
        // call transferOwnership to itself if deployer != admin)
        console.log("");
        console.log("  Token owner (deployer) retains:");
        console.log("    - setAllowed() to add/remove minters");
        console.log("    - renounceOwnership() to lock config permanently");
        console.log("    - Admin can self-revoke via setAllowed(self, false)");

        vm.stopBroadcast();

        // =============================================================
        //                    DEPLOYMENT SUMMARY
        // =============================================================
        printDeploymentSummary();
    }

    function printDeploymentSummary() internal view {
        console.log("\n");
        console.log("=================================================================");
        console.log("         DEPLOYMENT v%s COMPLETE", DEPLOYMENT_VERSION);
        console.log("=================================================================");
        console.log("LVWETH:              ", address(lvweth));
        console.log("LVWSTETH:            ", address(lvwsteth));
        console.log("Ajna Pool:           ", ajnaPool);
        console.log("LiquidationProxy:    ", address(liquidationProxy));
        console.log("LVLidoVault:         ", address(lvLidoVault));
        console.log("LVLidoVaultReader:   ", address(lvLidoVaultReader));
        console.log("LVLidoVaultUtil:     ", address(lvLidoVaultUtil));
        console.log("LVLidoVaultUpkeeper: ", address(lvLidoVaultUpkeeper));
        console.log("=================================================================");
        console.log("");
        console.log("NEXT STEPS:");
        console.log("  1. Update frontend src/lib/lvLidoVault.ts with addresses above");
        console.log("  2. Create Chainlink Functions subscription");
        console.log("     - Add LVLidoVaultUtil as consumer");
        console.log("  3. Create Chainlink Automation subscription");
        console.log("     - Target: LVLidoVaultUtil");
        console.log("     - Get forwarder address");
        console.log("     - Call lvLidoVaultUtil.setForwarderAddress(forwarder)");
        console.log("  4. If deployer != ADMIN_WALLET:");
        console.log("     - Call lvweth.transferOwnership(ADMIN_WALLET)");
        console.log("     - Call lvwsteth.transferOwnership(ADMIN_WALLET)");
        console.log("  5. Verify on Etherscan");
        console.log("  6. OWNERSHIP: Revoke ownership at the start of epoch 3 (admin manual action)");
        console.log("=================================================================");
    }

    /// @dev Convert uint to string for token naming
    function _uint2str(uint256 _i) internal pure returns (string memory) {
        if (_i == 0) return "0";
        uint256 j = _i;
        uint256 len;
        while (j != 0) { len++; j /= 10; }
        bytes memory bstr = new bytes(len);
        uint256 k = len;
        while (_i != 0) {
            k--;
            bstr[k] = bytes1(uint8(48 + _i % 10));
            _i /= 10;
        }
        return string(bstr);
    }
}
