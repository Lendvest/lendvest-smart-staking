// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {IFunctionsClient} from "@chainlink/contracts/src/v0.8/functions/v1_0_0/interfaces/IFunctionsClient.sol";

/**
 * @title MockChainlinkFunctions
 * @notice Simulates Chainlink Functions router for testing
 * @dev Allows tests to:
 *      1. Trigger rate requests
 *      2. Simulate successful responses with custom rates
 *      3. Simulate failures to test fallback behavior
 */
contract MockChainlinkFunctions {

    // Track pending requests
    mapping(bytes32 => address) public pendingRequests;
    uint256 public requestCounter;

    // Configurable response
    uint256 public mockRate = 3e16; // Default 3% APR
    bool public shouldFail = false;
    bytes public failureError = "Oracle unavailable";

    event RequestSent(bytes32 indexed requestId, address indexed client);
    event RequestFulfilled(bytes32 indexed requestId, uint256 rate);
    event RequestFailed(bytes32 indexed requestId, bytes error);

    /**
     * @notice Simulate sending a Functions request
     * @param client The contract that will receive the callback
     * @return requestId The mock request ID
     */
    function sendRequest(address client) external returns (bytes32 requestId) {
        requestId = keccak256(abi.encodePacked(block.timestamp, requestCounter++));
        pendingRequests[requestId] = client;
        emit RequestSent(requestId, client);
    }

    /**
     * @notice Fulfill a pending request with the mock rate
     * @param requestId The request to fulfill
     */
    function fulfillRequest(bytes32 requestId) external {
        address client = pendingRequests[requestId];
        require(client != address(0), "Request not found");

        delete pendingRequests[requestId];

        if (shouldFail) {
            // Simulate failure - triggers Aave fallback
            IFunctionsClient(client).handleOracleFulfillment(
                requestId,
                "", // empty response
                failureError
            );
            emit RequestFailed(requestId, failureError);
        } else {
            // Simulate success with mock rate
            bytes memory response = abi.encode(mockRate);
            IFunctionsClient(client).handleOracleFulfillment(
                requestId,
                response,
                "" // no error
            );
            emit RequestFulfilled(requestId, mockRate);
        }
    }

    // ============ Configuration Functions ============

    function setMockRate(uint256 _rate) external {
        mockRate = _rate;
    }

    function setShouldFail(bool _shouldFail) external {
        shouldFail = _shouldFail;
    }

    function setFailureError(bytes memory _error) external {
        failureError = _error;
    }
}
