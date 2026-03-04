// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAutomationRegistrar} from "../src/interfaces/IAutomationRegistrar.sol";

/**
 * @title RegisterChainlinkAutomation
 * @notice Script to programmatically register a Chainlink Automation upkeep
 * @dev This bypasses the dashboard entirely - register upkeeps via contract calls
 *
 * Usage:
 *   # Sepolia testnet
 *   forge script script/RegisterChainlinkAutomation.s.sol:RegisterChainlinkAutomation \
 *     --rpc-url $SEPOLIA_RPC_URL \
 *     --broadcast \
 *     --private-key $PRIVATE_KEY \
 *     -vvvv
 *
 *   # Mainnet
 *   forge script script/RegisterChainlinkAutomation.s.sol:RegisterChainlinkAutomation \
 *     --rpc-url $MAINNET_RPC_URL \
 *     --broadcast \
 *     --private-key $PRIVATE_KEY \
 *     -vvvv
 */
contract RegisterChainlinkAutomation is Script {
    // ============ NETWORK ADDRESSES ============

    // Sepolia Addresses (Automation v2.1)
    address public constant SEPOLIA_REGISTRAR = 0xb0E49c5D0d05cbc241d68c05BC5BA1d1B7B72976;
    address public constant SEPOLIA_REGISTRY = 0x86EFBD0b6736Bed994962f9797049422A3A8E8Ad;
    address public constant SEPOLIA_LINK = 0x779877A7B0D9E8603169DdbD7836e478b4624789;

    // Mainnet Addresses (Automation v2.1)
    address public constant MAINNET_REGISTRAR = 0x6B0B234fB2f380309D47A7E9391E29E9a179395a;
    address public constant MAINNET_REGISTRY = 0x6593c7De001fC8542bB1703532EE1E5aA0D458fD;
    address public constant MAINNET_LINK = 0x514910771AF9Ca656af840dff83E8264EcF986CA;

    // ============ CONFIGURATION ============

    // Set your upkeep contract address here (LVLidoVaultUtil)
    address public upkeepContract;

    // Funding amount (in LINK tokens, 18 decimals)
    uint96 public constant INITIAL_FUNDING = 5 ether; // 5 LINK

    // Gas limit for performUpkeep execution
    uint32 public constant GAS_LIMIT = 2000000;

    function run() public {
        // Detect network and set addresses
        uint256 chainId = block.chainid;
        address registrar;
        address linkToken;
        address registry;

        if (chainId == 11155111) {
            // Sepolia
            registrar = SEPOLIA_REGISTRAR;
            linkToken = SEPOLIA_LINK;
            registry = SEPOLIA_REGISTRY;
            console.log("Network: Sepolia Testnet");
        } else if (chainId == 1) {
            // Mainnet
            registrar = MAINNET_REGISTRAR;
            linkToken = MAINNET_LINK;
            registry = MAINNET_REGISTRY;
            console.log("Network: Ethereum Mainnet");
        } else {
            revert("Unsupported network. Use Sepolia or Mainnet.");
        }

        // Get upkeep contract from environment or use default
        upkeepContract = vm.envOr("UPKEEP_CONTRACT", address(0));
        require(upkeepContract != address(0), "Set UPKEEP_CONTRACT env var to your LVLidoVaultUtil address");

        console.log("Registrar:", registrar);
        console.log("LINK Token:", linkToken);
        console.log("Upkeep Contract:", upkeepContract);
        console.log("Initial Funding:", INITIAL_FUNDING / 1e18, "LINK");
        console.log("Gas Limit:", GAS_LIMIT);

        vm.startBroadcast();

        // 1. Approve LINK tokens for the registrar
        IERC20 link = IERC20(linkToken);
        uint256 balance = link.balanceOf(msg.sender);
        console.log("Your LINK balance:", balance / 1e18, "LINK");
        require(balance >= INITIAL_FUNDING, "Insufficient LINK balance");

        link.approve(registrar, INITIAL_FUNDING);
        console.log("Approved LINK for registrar");

        // 2. Prepare registration parameters
        IAutomationRegistrar.RegistrationParams memory params = IAutomationRegistrar.RegistrationParams({
            name: "LVLidoVault Automation",
            encryptedEmail: "", // Optional: encrypted email for notifications
            upkeepContract: upkeepContract,
            gasLimit: GAS_LIMIT,
            adminAddress: msg.sender, // You will be the admin
            triggerType: 0, // 0 = Conditional (checkUpkeep/performUpkeep)
            checkData: "", // Optional: data passed to checkUpkeep
            triggerConfig: "", // Empty for conditional upkeeps
            offchainConfig: "", // Optional: off-chain config
            amount: INITIAL_FUNDING // LINK funding
        });

        // 3. Register the upkeep
        IAutomationRegistrar registrarContract = IAutomationRegistrar(registrar);
        uint256 upkeepId = registrarContract.registerUpkeep(params);

        console.log("========================================");
        console.log("SUCCESS! Upkeep registered!");
        console.log("Upkeep ID:", upkeepId);
        console.log("========================================");
        console.log("");
        console.log("IMPORTANT: Set the forwarder address on your LVLidoVaultUtil:");
        console.log("The forwarder address will be assigned by the registry.");
        console.log("Check the upkeep details on automation.chain.link to get it.");
        console.log("");
        console.log("View your upkeep at:");
        if (chainId == 11155111) {
            console.log("https://automation.chain.link/sepolia/", upkeepId);
        } else {
            console.log("https://automation.chain.link/mainnet/", upkeepId);
        }

        vm.stopBroadcast();
    }
}
