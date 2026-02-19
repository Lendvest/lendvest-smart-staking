// SPDX-License-Identifier: BUSL-1.1
// Author: Lendvest

pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {IERC20Pool} from "../src/interfaces/pool/erc20/IERC20Pool.sol";
import {LVLidoVault} from "../src/LVLidoVault.sol";
import {IPoolInfoUtils} from "../src/interfaces/IPoolInfoUtils.sol";
import {ILidoWithdrawal} from "../src/interfaces/vault/ILidoWithdrawal.sol";
import {IWsteth} from "../src/interfaces/vault/IWsteth.sol";
import {VaultLib} from "../src/libraries/VaultLib.sol";
import {ILVLidoVault} from "../src/interfaces/ILVLidoVault.sol";

contract TestHelpers is Test {
    // Ethereum Mainnet Addresses
    address public constant WETH_ADDRESS = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant WSTETH_ADDRESS = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address public constant POOL_INFO_UTILS = 0x30c5eF2997d6a882DE52c4ec01B6D0a5e5B4fAAE;
    IPoolInfoUtils public poolInfoUtils = IPoolInfoUtils(POOL_INFO_UTILS);
    IWsteth private wsteth = IWsteth(WSTETH_ADDRESS);

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

    function printUtilization(address lvlidoAddress, address poolAddress) public view {
        // Get debt using pool info utils
        (uint256 debt,,,) = poolInfoUtils.borrowerInfo(poolAddress, lvlidoAddress);
        uint256 utilization = (debt * 1e18) / IERC20Pool(poolAddress).depositSize();
        console.log(string.concat("Utilization: ", formatValue(utilization * 100), " %"));
    }

    function formatValue(uint256 someValue) public view returns (string memory) {
        // Convert to whole number and decimal parts
        uint256 whole = someValue / 1e18;
        uint256 decimal = someValue % 1e18;

        // Convert decimal to string and pad with leading zeros
        string memory decimalStr = vm.toString(decimal);
        uint256 zeros = 18 - bytes(decimalStr).length;
        string memory padding = "";
        for (uint256 i = 0; i < zeros; i++) {
            padding = string.concat(padding, "0");
        }
        decimalStr = string.concat(padding, decimalStr);

        // Combine whole and decimal parts
        return string.concat(vm.toString(whole), ".", decimalStr);
    }

    function printMatches(address lvlidoAddress, address[] memory lenders, address[] memory borrowers) public view {
        // Get debt using pool info utils
        uint256 epoch = ILVLidoVault(lvlidoAddress).epoch();

        VaultLib.MatchInfo[] memory matches = ILVLidoVault(lvlidoAddress).getEpochMatches(epoch);
        console.log("--------------------------------");
        console.log("Matches Info");
        console.log("--------------------------------");

        for (uint256 i = 0; i < matches.length; i++) {
            VaultLib.MatchInfo memory match_ = matches[i];
            address matchLender = match_.lender;
            address matchBorrower = match_.borrower;
            uint256 lenderIndex = 0;
            uint256 borrowerIndex = 0;
            for (uint256 j = 0; j < lenders.length; j++) {
                if (lenders[j] == matchLender) {
                    lenderIndex = j;
                }
            }
            for (uint256 j = 0; j < borrowers.length; j++) {
                if (borrowers[j] == matchBorrower) {
                    borrowerIndex = j;
                }
            }
            console.log(
                string.concat(
                    "Match ",
                    vm.toString(i),
                    " Lender Index: ",
                    vm.toString(lenderIndex),
                    " Borrower Index: ",
                    vm.toString(borrowerIndex),
                    " Quote Amount: ",
                    formatValue(match_.quoteAmount),
                    " Collateral Amount: ",
                    formatValue(match_.collateralAmount),
                    " Reserved Quote Amount: ",
                    formatValue(match_.reservedQuoteAmount)
                )
            );
        }

        console.log("--------------------------------");
    }

    function printOrders(address lvlidoAddress) public view {}

    /* function printLenderOrders(address lvlidoAddress) public view {
        uint256 lenderOrdersLength = ILVLidoVault(lvlidoAddress).lenderOrdersLength();
        for (uint256 i = 0; i < lenderOrdersLength; i++) {
            console.log("Lender Order", i);
            console.log("Lender", ILVLidoVault(lvlidoAddress).lenderOrders(i));
            console.log("Quote Amount", ILVLidoVault(lvlidoAddress).lenderOrdersQuoteAmount(i));
            console.log("Collateral Amount", ILVLidoVault(lvlidoAddress).lenderOrdersCollateralAmount(i));
        }
    }*/
}
