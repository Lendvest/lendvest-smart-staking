// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IAutomationRegistrar
 * @notice Interface for Chainlink Automation Registrar v2.1+
 * @dev Used to programmatically register upkeeps
 */
interface IAutomationRegistrar {
    /**
     * @notice Struct for registration parameters
     */
    struct RegistrationParams {
        string name;
        bytes encryptedEmail;
        address upkeepContract;
        uint32 gasLimit;
        address adminAddress;
        uint8 triggerType; // 0 = Conditional, 1 = Log trigger
        bytes checkData;
        bytes triggerConfig;
        bytes offchainConfig;
        uint96 amount; // LINK funding amount
    }

    /**
     * @notice Register a new upkeep
     * @param requestParams The registration parameters
     * @return upkeepId The ID of the newly registered upkeep
     */
    function registerUpkeep(RegistrationParams calldata requestParams) external returns (uint256 upkeepId);
}

