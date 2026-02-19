// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {AutomationCompatibleInterface} from "@chainlink/contracts/src/v0.8/automation/interfaces/AutomationCompatibleInterface.sol";

/**
 * @title MockChainlinkAutomation
 * @notice Simulates Chainlink Automation for testing
 * @dev Allows tests to:
 *      1. Check upkeep conditions
 *      2. Execute performUpkeep as the forwarder
 *      3. Simulate time-based triggers
 */
contract MockChainlinkAutomation {

    address public forwarderAddress;

    event UpkeepChecked(address indexed target, bool needed, bytes performData);
    event UpkeepPerformed(address indexed target, bytes performData);

    constructor(address _forwarder) {
        forwarderAddress = _forwarder;
    }

    /**
     * @notice Check if upkeep is needed on target contract
     * @param target The AutomationCompatible contract
     * @param checkData Optional check data
     * @return upkeepNeeded Whether upkeep should be performed
     * @return performData Data to pass to performUpkeep
     */
    function checkUpkeep(
        address target,
        bytes calldata checkData
    ) external returns (bool upkeepNeeded, bytes memory performData) {
        (upkeepNeeded, performData) = AutomationCompatibleInterface(target).checkUpkeep(checkData);
        emit UpkeepChecked(target, upkeepNeeded, performData);
    }

    /**
     * @notice Execute performUpkeep on target contract
     * @dev Note: In tests, you must vm.prank(forwarder) before calling the target directly
     *      This function is mainly for logging/tracking in tests
     * @param target The AutomationCompatible contract
     * @param performData Data from checkUpkeep
     */
    function performUpkeep(
        address target,
        bytes calldata performData
    ) external {
        // Call target's performUpkeep
        // Note: This won't work if target checks msg.sender == forwarder
        // In that case, use vm.prank(forwarder) in tests
        (bool success, bytes memory returnData) = target.call(
            abi.encodeWithSelector(
                AutomationCompatibleInterface.performUpkeep.selector,
                performData
            )
        );

        if (!success) {
            // Bubble up the revert reason
            if (returnData.length > 0) {
                assembly {
                    revert(add(returnData, 32), mload(returnData))
                }
            }
            revert("performUpkeep failed");
        }

        emit UpkeepPerformed(target, performData);
    }

    /**
     * @notice Simulate a full automation cycle
     * @param target The AutomationCompatible contract
     * @return executed Whether upkeep was executed
     * @return performData The data that would be used for performUpkeep
     */
    function simulateCycle(address target) external returns (bool executed, bytes memory performData) {
        bool needed;
        (needed, performData) = this.checkUpkeep(target, "");

        if (needed) {
            // Note: In real tests, caller should vm.prank(forwarder) and call target directly
            executed = true;
        }
    }

    function setForwarder(address _forwarder) external {
        forwarderAddress = _forwarder;
    }
}
