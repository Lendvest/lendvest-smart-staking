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
 * @title Sequential Deployment Script (Versioned)
 * @notice Deploys contracts ONE AT A TIME so each gets verified individually.
 *         Solves the Etherscan rate-limit issue where batch --verify fails
 *         intermittently when 7 contracts are submitted simultaneously.
 *
 * @dev USAGE: Run each step sequentially, passing prior addresses via env vars.
 *
 *      STEP 1 — Tokens (no deps):
 *      forge script script/deployEachAll.s.sol:DeployEachAll \
 *          --sig "step1_tokens()" \
 *          --rpc-url $RPC_URL --private-key $PRIVATE_KEY \
 *          --broadcast --verify -vvv
 *
 *      STEP 2 — Ajna Pool (no --verify, factory CREATE):
 *      LVWETH=0x... LVWSTETH=0x... \
 *      forge script script/deployEachAll.s.sol:DeployEachAll \
 *          --sig "step2_pool()" \
 *          --rpc-url $RPC_URL --private-key $PRIVATE_KEY \
 *          --broadcast -vvv
 *
 *      STEP 3 — LiquidationProxy:
 *      AJNA_POOL=0x... \
 *      forge script script/deployEachAll.s.sol:DeployEachAll \
 *          --sig "step3_proxy()" \
 *          --rpc-url $RPC_URL --private-key $PRIVATE_KEY \
 *          --broadcast --verify -vvv
 *
 *      STEP 4 — LVLidoVault:
 *      AJNA_POOL=0x... LIQUIDATION_PROXY=0x... \
 *      forge script script/deployEachAll.s.sol:DeployEachAll \
 *          --sig "step4_vault()" \
 *          --rpc-url $RPC_URL --private-key $PRIVATE_KEY \
 *          --broadcast --verify -vvv
 *
 *      STEP 5 — LVLidoVaultReader:
 *      forge script script/deployEachAll.s.sol:DeployEachAll \
 *          --sig "step5_reader()" \
 *          --rpc-url $RPC_URL --private-key $PRIVATE_KEY \
 *          --broadcast --verify -vvv
 *
 *      STEP 6 — LVLidoVaultUtil:
 *      LV_LIDO_VAULT=0x... \
 *      forge script script/deployEachAll.s.sol:DeployEachAll \
 *          --sig "step6_util()" \
 *          --rpc-url $RPC_URL --private-key $PRIVATE_KEY \
 *          --broadcast --verify -vvv
 *
 *      STEP 7 — LVLidoVaultUpkeeper:
 *      LV_LIDO_VAULT=0x... \
 *      forge script script/deployEachAll.s.sol:DeployEachAll \
 *          --sig "step7_upkeeper()" \
 *          --rpc-url $RPC_URL --private-key $PRIVATE_KEY \
 *          --broadcast --verify -vvv
 *
 *      STEP 8 — Configure (no --verify, just CALLs):
 *      LVWETH=0x... LVWSTETH=0x... AJNA_POOL=0x... LIQUIDATION_PROXY=0x... \
 *      LV_LIDO_VAULT=0x... LV_LIDO_VAULT_READER=0x... LV_LIDO_VAULT_UTIL=0x... \
 *      LV_LIDO_VAULT_UPKEEPER=0x... \
 *      forge script script/deployEachAll.s.sol:DeployEachAll \
 *          --sig "step8_configure()" \
 *          --rpc-url $RPC_URL --private-key $PRIVATE_KEY \
 *          --broadcast -vvv
 */
contract DeployEachAll is Script {
    // =============================================================
    //                    DEPLOYMENT VERSION
    // =============================================================
    uint256 public constant DEPLOYMENT_VERSION = 12;

    // =============================================================
    //                    ACCESS CONTROL
    // =============================================================
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
    //                    STEP 1: DEPLOY TOKENS
    // =============================================================
    function step1_tokens() public {
        console.log("=== STEP 1: Deploying LVTokens (v%s) ===", DEPLOYMENT_VERSION);

        string memory wethName = string(abi.encodePacked("LVWETH-v", _uint2str(DEPLOYMENT_VERSION)));
        string memory wethSymbol = string(abi.encodePacked("LVWETH", _uint2str(DEPLOYMENT_VERSION)));
        string memory wstethName = string(abi.encodePacked("LVWSTETH-v", _uint2str(DEPLOYMENT_VERSION)));
        string memory wstethSymbol = string(abi.encodePacked("LVWSTETH", _uint2str(DEPLOYMENT_VERSION)));

        vm.startBroadcast();
        LVToken lvweth = new LVToken(wethName, wethSymbol);
        LVToken lvwsteth = new LVToken(wstethName, wstethSymbol);
        vm.stopBroadcast();

        console.log("LVWETH deployed at:", address(lvweth));
        console.log("LVWSTETH deployed at:", address(lvwsteth));
        console.log("");
        console.log("NEXT: Run step2_pool() with env vars:");
        console.log("  LVWETH=%s LVWSTETH=%s", address(lvweth), address(lvwsteth));
    }

    // =============================================================
    //                    STEP 2: DEPLOY AJNA POOL
    // =============================================================
    // NOTE: No --verify flag. Factory-deployed via internal CREATE.
    function step2_pool() public {
        address lvwsteth = vm.envAddress("LVWSTETH");
        address lvweth = vm.envAddress("LVWETH");

        console.log("=== STEP 2: Deploying Ajna Pool ===");
        console.log("  LVWSTETH:", lvwsteth);
        console.log("  LVWETH:", lvweth);

        IERC20PoolFactory poolFactory = IERC20PoolFactory(POOL_FACTORY_ADDRESS);

        vm.startBroadcast();
        address ajnaPool = poolFactory.deployPool(lvwsteth, lvweth, POOL_RATE);
        vm.stopBroadcast();

        console.log("Ajna Pool deployed at:", ajnaPool);
        console.log("");
        console.log("NEXT: Run step3_proxy() with env var:");
        console.log("  AJNA_POOL=%s", ajnaPool);
    }

    // =============================================================
    //                    STEP 3: DEPLOY LIQUIDATION PROXY
    // =============================================================
    function step3_proxy() public {
        address ajnaPool = vm.envAddress("AJNA_POOL");

        console.log("=== STEP 3: Deploying LiquidationProxy ===");
        console.log("  Ajna Pool:", ajnaPool);

        vm.startBroadcast();
        LiquidationProxy proxy = new LiquidationProxy(ajnaPool);
        vm.stopBroadcast();

        console.log("LiquidationProxy deployed at:", address(proxy));
        console.log("");
        console.log("NEXT: Run step4_vault() with env vars:");
        console.log("  AJNA_POOL=%s LIQUIDATION_PROXY=%s", ajnaPool, address(proxy));
    }

    // =============================================================
    //                    STEP 4: DEPLOY VAULT
    // =============================================================
    function step4_vault() public {
        address ajnaPool = vm.envAddress("AJNA_POOL");
        address liquidationProxy = vm.envAddress("LIQUIDATION_PROXY");

        console.log("=== STEP 4: Deploying LVLidoVault ===");
        console.log("  Ajna Pool:", ajnaPool);
        console.log("  LiquidationProxy:", liquidationProxy);

        vm.startBroadcast();
        LVLidoVault vault = new LVLidoVault(ajnaPool, liquidationProxy);
        vm.stopBroadcast();

        console.log("LVLidoVault deployed at:", address(vault));
        console.log("");
        console.log("=================================================================");
        console.log("  CHECKPOINT: VERIFY BEFORE CONTINUING");
        console.log("=================================================================");
        console.log("  LVLidoVault is the hardest contract to verify.");
        console.log("  DO NOT proceed to step5 until verification is confirmed.");
        console.log("");
        console.log("  Check: https://etherscan.io/address/%s#code", address(vault));
        console.log("");
        console.log("  If verification FAILED:");
        console.log("    - Do NOT continue. Redeploy step4 from a clean build.");
        console.log("    - Run: forge clean && forge build");
        console.log("    - Then re-run step4_vault() with the same env vars.");
        console.log("=================================================================");
        console.log("");
        console.log("NEXT (only after verified): Run step5_reader()");
        console.log("  LV_LIDO_VAULT=%s", address(vault));
    }

    // =============================================================
    //                    STEP 5: DEPLOY READER
    // =============================================================
    function step5_reader() public {
        console.log("=== STEP 5: Deploying LVLidoVaultReader ===");

        vm.startBroadcast();
        LVLidoVaultReader reader = new LVLidoVaultReader();
        vm.stopBroadcast();

        console.log("LVLidoVaultReader deployed at:", address(reader));
        console.log("");
        console.log("NEXT: Run step6_util() with env var:");
        console.log("  LV_LIDO_VAULT=0x...");
    }

    // =============================================================
    //                    STEP 6: DEPLOY UTIL
    // =============================================================
    function step6_util() public {
        address vault = vm.envAddress("LV_LIDO_VAULT");

        console.log("=== STEP 6: Deploying LVLidoVaultUtil ===");
        console.log("  LVLidoVault:", vault);

        vm.startBroadcast();
        LVLidoVaultUtil util = new LVLidoVaultUtil(vault);
        vm.stopBroadcast();

        console.log("LVLidoVaultUtil deployed at:", address(util));
        console.log("");
        console.log("NEXT: Run step7_upkeeper() with env var:");
        console.log("  LV_LIDO_VAULT=%s", vault);
    }

    // =============================================================
    //                    STEP 7: DEPLOY UPKEEPER
    // =============================================================
    function step7_upkeeper() public {
        address vault = vm.envAddress("LV_LIDO_VAULT");

        console.log("=== STEP 7: Deploying LVLidoVaultUpkeeper ===");
        console.log("  LVLidoVault:", vault);

        vm.startBroadcast();
        LVLidoVaultUpkeeper upkeeper = new LVLidoVaultUpkeeper(vault);
        vm.stopBroadcast();

        console.log("LVLidoVaultUpkeeper deployed at:", address(upkeeper));
        console.log("");
        console.log("NEXT: Run step8_configure() with ALL env vars");
    }

    // =============================================================
    //                    STEP 8: CONFIGURE ALL CONTRACTS
    // =============================================================
    // NOTE: No --verify flag. These are CALL transactions, not CREATEs.
    function step8_configure() public {
        address lvweth = vm.envAddress("LVWETH");
        address lvwsteth = vm.envAddress("LVWSTETH");
        address ajnaPool = vm.envAddress("AJNA_POOL");
        address liquidationProxy = vm.envAddress("LIQUIDATION_PROXY");
        address payable vault = payable(vm.envAddress("LV_LIDO_VAULT"));
        address reader = vm.envAddress("LV_LIDO_VAULT_READER");
        address util = vm.envAddress("LV_LIDO_VAULT_UTIL");
        address upkeeper = vm.envAddress("LV_LIDO_VAULT_UPKEEPER");

        console.log("=== STEP 8: Configuring Contracts ===");
        console.log("  LVWETH:", lvweth);
        console.log("  LVWSTETH:", lvwsteth);
        console.log("  Ajna Pool:", ajnaPool);
        console.log("  LiquidationProxy:", liquidationProxy);
        console.log("  LVLidoVault:", vault);
        console.log("  LVLidoVaultReader:", reader);
        console.log("  LVLidoVaultUtil:", util);
        console.log("  LVLidoVaultUpkeeper:", upkeeper);

        vm.startBroadcast();

        // Wire contract references
        LVLidoVault(vault).setLVLidoVaultUtilAddress(util);
        console.log("  Vault -> Util: set");

        LVLidoVault(vault).setLVLidoVaultUpkeeperAddress(upkeeper);
        console.log("  Vault -> Upkeeper: set");

        LVLidoVaultUtil(util).setLVLidoVaultUpkeeper(upkeeper);
        console.log("  Util -> Upkeeper: set");

        LVLidoVaultUpkeeper(upkeeper).setLVLidoVaultUtil(util);
        console.log("  Upkeeper -> Util: set");

        LiquidationProxy(liquidationProxy).setLVLidoVault(vault);
        console.log("  Proxy -> Vault: set");

        // Configure allowlist
        LVToken(lvweth).setAllowed(vault, true);
        LVToken(lvwsteth).setAllowed(vault, true);
        console.log("  Tokens -> Vault allowed: true");

        LVToken(lvweth).setAllowed(ADMIN_WALLET, true);
        LVToken(lvwsteth).setAllowed(ADMIN_WALLET, true);
        console.log("  Tokens -> Admin allowed: true");

        // Transfer LiquidationProxy ownership to vault
        LiquidationProxy(liquidationProxy).transferOwnership(vault);
        console.log("  LiquidationProxy ownership -> Vault");

        vm.stopBroadcast();

        // Print final summary
        console.log("\n");
        console.log("=================================================================");
        console.log("         DEPLOYMENT v%s COMPLETE", DEPLOYMENT_VERSION);
        console.log("=================================================================");
        console.log("LVWETH:              ", lvweth);
        console.log("LVWSTETH:            ", lvwsteth);
        console.log("Ajna Pool:           ", ajnaPool);
        console.log("LiquidationProxy:    ", liquidationProxy);
        console.log("LVLidoVault:         ", vault);
        console.log("LVLidoVaultReader:   ", reader);
        console.log("LVLidoVaultUtil:     ", util);
        console.log("LVLidoVaultUpkeeper: ", upkeeper);
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
        console.log("  5. OWNERSHIP: Revoke at start of epoch 3");
        console.log("=================================================================");
    }

    // =============================================================
    //                    DEFAULT: PRINT USAGE
    // =============================================================
    function run() public pure {
        console.log("=================================================================");
        console.log("  DeployEachAll - Sequential Deployment with Per-Contract Verify");
        console.log("=================================================================");
        console.log("");
        console.log("This script deploys contracts one at a time so each gets");
        console.log("verified individually, avoiding Etherscan rate-limit failures.");
        console.log("");
        console.log("Run steps in order:");
        console.log("  --sig 'step1_tokens()'     Deploy LVWETH + LVWSTETH");
        console.log("  --sig 'step2_pool()'       Deploy Ajna Pool (no --verify)");
        console.log("  --sig 'step3_proxy()'      Deploy LiquidationProxy");
        console.log("  --sig 'step4_vault()'      Deploy LVLidoVault");
        console.log("  >>> CHECKPOINT: Verify LVLidoVault on Etherscan before continuing <<<");
        console.log("  --sig 'step5_reader()'     Deploy LVLidoVaultReader");
        console.log("  --sig 'step6_util()'       Deploy LVLidoVaultUtil");
        console.log("  --sig 'step7_upkeeper()'   Deploy LVLidoVaultUpkeeper");
        console.log("  --sig 'step8_configure()'  Wire + allowlist (no --verify)");
        console.log("");
        console.log("Each step prints the env vars needed for the next step.");
        console.log("Steps 2 and 8 do NOT use --verify (factory CREATE / CALLs only).");
        console.log("STOP after step4 -- do not continue unless LVLidoVault is verified.");
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
