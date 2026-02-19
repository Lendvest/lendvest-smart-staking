// SPDX-License-Identifier: MIT
/*
  forge script script/anvil/endEpoch.s.sol:EndEpoch --rpc-url http://127.0.0.1:8545 --broadcast --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
*/
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {LVLidoVaultUtil} from "../../src/LVLidoVaultUtil.sol";
import {IWsteth} from "../../src/interfaces/vault/IWsteth.sol";
import {ILidoWithdrawal} from "../../src/interfaces/vault/ILidoWithdrawal.sol";
import {LVLidoVault} from "../../src/LVLidoVault.sol";

contract EndEpoch is Script {
    // Ethereum Mainnet Addresses
    address public constant LVLIDOVAULTUTIL_ADDRESS = 0x33129398782e26D2f3aCEc28D88b5500cA0cea0a;
    address public constant WSTETH_ADDRESS = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address public constant LVLIDOVAULT_ADDRESS = 0xE951fe9a680E1249dBE463Dd14a6d7061442bc9F;
    IWsteth public wsteth;

    function run() public {
        LVLidoVaultUtil lvlidoVaultUtil = LVLidoVaultUtil(LVLIDOVAULTUTIL_ADDRESS);
        LVLidoVault lvLidoVault = LVLidoVault(payable(LVLIDOVAULT_ADDRESS));
        wsteth = IWsteth(WSTETH_ADDRESS);

        // --- Setup Phase (No Broadcast) ---
        // Set up time and advance the block
        vm.warp(lvLidoVault.epochStart() + lvLidoVault.termDuration() + 1);
        vm.roll(block.number + 1);
        console.log(
            "Time warped. Term ended? ", (lvLidoVault.epochStart() + lvLidoVault.termDuration()) < block.timestamp
        );
        bytes32 raw = vm.load(LVLIDOVAULTUTIL_ADDRESS, bytes32(uint256(6)));

        // 1. 32-byte word interpreted as a uint256
        uint256 asUint = uint256(raw);
        console.log("uint256 =", asUint);

        // 2. Lower 20 bytes interpreted as an address
        address asAddr = address(uint160(uint256(raw)));
        console.log("address =", asAddr);

        // 3. Boolean flag (non-zero?)
        bool asBool = raw != bytes32(0);
        console.log("bool =", asBool);

        // 4. Using abi.decode (needs a bytes array)
        uint256 viaDecode = abi.decode(abi.encodePacked(raw), (uint256));

        console.log("Slot 6 value before:", viaDecode);

        // 5. Overwrite to false
        vm.store(LVLIDOVAULTUTIL_ADDRESS, bytes32(uint256(6)), bytes32(uint256(0)));

        // Check if upkeep is needed now that time has passed
        (bool upkeepNeeded, bytes memory performData) = lvlidoVaultUtil.checkUpkeep(bytes(""));
        if (!upkeepNeeded) {
            console.log("No upkeep needed after warping time. Exiting.");
            return;
        }
        (uint256 taskId) = abi.decode(performData, (uint256));
        console.log("Task ID found: ", taskId);

        console.log("updateRateNeeded", lvlidoVaultUtil.updateRateNeeded());
        console.log("Transaction broadcast complete.");
    }

    /**
     * @notice Processes the Lido withdrawal queue by finalizing pending withdrawal requests
     * @dev Simulates the Lido withdrawal process by:
     *      1. Using the provided share rate to calculate finalization batches
     *      2. Determining required ETH to lock for finalization
     *      3. Funding the Lido contract with required ETH
     *      4. Finalizing the withdrawal requests
     * @param shareRateToUse The stETH/ETH share rate to use for processing (in 1e18 precision)
     */
    function processLidoQueue(uint256 shareRateToUse) public {
        ILidoWithdrawal withdrawal = ILidoWithdrawal(0x889edC2eDab5f40e902b864aD4d7AdE8E412F9B1);
        // Note: The share rate is expressed with 1e27 precision.
        //uint256 maxShareRate = 1e27;
        // 1. Fetch the current share rate from the wstETH token
        uint256 actualShareRate = shareRateToUse * 1e9;

        // Get the current share rate
        uint256 maxTimestamp = block.timestamp + 200;
        uint256 maxRequestsPerCall = 1e27;

        // 3. Initialize the batches calculation state.
        ILidoWithdrawal.BatchesCalculationState memory state;
        state.remainingEthBudget = 100000000000 ether; // Set an arbitrary (but sufficient) ETH budget.
        state.finished = false;
        state.batchesLength = 0; // Start with 0, let the contract set the actual length

        // 4. Calculate batches off-chain (simulated via a call).
        state = withdrawal.calculateFinalizationBatches(actualShareRate, maxTimestamp, maxRequestsPerCall, state);

        // 5. Extract the batches array from the state.
        uint256[] memory batches = new uint256[](state.batchesLength);
        for (uint256 i = 0; i < state.batchesLength; i++) {
            batches[i] = state.batches[i];
        }
        // The batches array now contains the ending request IDs for each batch that should be finalized.

        // 6. Calculate the ETH required for finalization using prefinalize.
        (uint256 ethToLock,) = withdrawal.prefinalize(batches, actualShareRate);
        //console.log("--------------------------------");
        //console.log("ethToLock", ethToLock);

        // 7. Fund the caller with the required ETH.
        vm.deal(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84, ethToLock);
        vm.prank(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);
        // 8. Finalize the requests by passing in the last request ID from the batches array.
        uint256 lastFinalizableRequestId = batches[batches.length - 1];
        withdrawal.finalize{value: ethToLock}(lastFinalizableRequestId, actualShareRate);
        //console.log("--------------------------------");
        //console.log("actualShareRate", actualShareRate);
    }
}
