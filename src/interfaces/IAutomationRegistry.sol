// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IAutomationRegistry
 * @notice Interface for Chainlink Automation Registry
 * @dev Used to query upkeep information including forwarder address
 */
interface IAutomationRegistry {
    /**
     * @notice Upkeep information struct
     */
    struct UpkeepInfoLegacy {
        address target;
        uint32 executeGas;
        bytes checkData;
        uint96 balance;
        address admin;
        uint64 maxValidBlocknumber;
        uint32 lastPerformedBlockNumber;
        uint96 amountSpent;
        bool paused;
        bytes offchainConfig;
    }

    /**
     * @notice Get upkeep information
     * @param id The upkeep ID
     * @return upkeepInfo The upkeep information
     */
    function getUpkeep(uint256 id) external view returns (UpkeepInfoLegacy memory upkeepInfo);

    /**
     * @notice Get the forwarder address for an upkeep (v2.1+)
     * @param upkeepId The upkeep ID
     * @return forwarder The forwarder contract address
     */
    function getForwarder(uint256 upkeepId) external view returns (address forwarder);
}

