// File: script/anvil/mockFulfill.s.sol
// SPDX-License-Identifier: MIT
/*
  forge script script/anvil/mockFulfill.s.sol:MockFulfill --rpc-url http://127.0.0.1:8545 --broadcast --private-key YOUR_PRIVATE_KEY
*/
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {LVLidoVaultUtil} from "../../src/LVLidoVaultUtil.sol";
import {VaultLib} from "../../src/libraries/VaultLib.sol";

// This helper contract inherits from LVLidoVaultUtil to gain access to its internal functions.
// We will use its bytecode to temporarily replace the code of the deployed contract.
contract Fulfiller is LVLidoVaultUtil {
    // The constructor must match the base contract's to ensure state layout compatibility.
    constructor(address _LVLidoVault) LVLidoVaultUtil(_LVLidoVault) {}

    // This public function simply calls the internal `fulfillRequest` function.
    function call_fulfillRequest(bytes32 requestId, bytes memory response, bytes memory err) external {
        fulfillRequest(requestId, response, err);
    }
}

contract MockFulfill is Script {
    // Address of the deployed LVLidoVaultUtil contract on your fork
    address public constant LVLIDOVAULTUTIL_ADDRESS = 0x33129398782e26D2f3aCEc28D88b5500cA0cea0a;

    // Address of the main LVLidoVault contract, needed for the Fulfiller constructor
    address public constant LVLIDOVAULT_ADDRESS = 0xE951fe9a680E1249dBE463Dd14a6d7061442bc9F;

    function run() public {
        // We need the requestId that was generated when the `endEpoch` script called `getRate()`.
        // We can read it directly from the public state variable `s_lastRequestId`.
        LVLidoVaultUtil util = LVLidoVaultUtil(LVLIDOVAULTUTIL_ADDRESS);
        bytes32 requestId = util.s_lastRequestId();
        console.log("Fulfilling request for ID");

        // Prepare the mock response data that `fulfillRequest` expects.
        // It decodes: (uint256 sumLiquidityRates_1e27, uint256 sumVariableBorrowRates_1e27, uint256 numRates)
        uint256 sumLiquidityRates = 200e27; // 200%
        uint256 sumBorrowRates = 220e27; // 220%
        uint256 numRates = 10;
        bytes memory mockResponse = abi.encode(sumLiquidityRates, sumBorrowRates, numRates);
        bytes memory mockErr = ""; // No error

        vm.startBroadcast();

        // 1. Deploy our Fulfiller contract to get its bytecode.
        //    It needs the vault address for its own constructor.
        Fulfiller fulfiller = new Fulfiller(LVLIDOVAULT_ADDRESS);

        // 2. Use vm.etch to replace the code at the target address with our Fulfiller's code.
        //    The state at LVLIDOVAULTUTIL_ADDRESS remains, but the code is now our helper's.
        vm.etch(LVLIDOVAULTUTIL_ADDRESS, address(fulfiller).code);

        // 3. Now we can call our new public function on the contract at LVLIDOVAULTUTIL_ADDRESS,
        //    because we've temporarily given it that function.
        Fulfiller(LVLIDOVAULTUTIL_ADDRESS).call_fulfillRequest(requestId, mockResponse, mockErr);

        vm.stopBroadcast();

        // --- Verification (Optional) ---
        // Let's check if the state was updated as expected.
        // uint256 newRate = _LVLidoVault.rate();
        bool isRateNeeded = util.updateRateNeeded();

        // The expected rate is (200e27 + 220e27) / (2 * 10 * 1e9) = 21e18 (or 2.1%)
        console.log("Fulfillment successful!");
        // console.log("New Rate:", newRate);
        console.log("Update Rate Needed?", isRateNeeded);
    }
}
