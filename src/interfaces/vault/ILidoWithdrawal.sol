// SPDX-License-Identifier: BUSL-1.1
// Author: Lendvest

pragma solidity ^0.8.20;

interface ILidoWithdrawal {
    // @notice Handles withdrawal request finalization and ETH locking. Requests can be nominal (1:1) or discounted based on share rate.
    struct BatchesCalculationState {
        uint256 remainingEthBudget;
        bool finished;
        uint256[36] batches;
        uint256 batchesLength;
    }

    function requestWithdrawalsWstETH(uint256[] calldata _amounts, address _owner)
        external
        returns (uint256[] memory requestIds);

    function claimWithdrawal(uint256 _requestId) external;

    function getClaimableEther(uint256[] calldata _requestIds, uint256[] calldata _hints)
        external
        view
        returns (uint256[] memory claimableEthValues);

    function getLastCheckpointIndex() external view returns (uint256);

    function findCheckpointHints(uint256[] calldata _requestIds, uint256 _firstIndex, uint256 _lastIndex)
        external
        view
        returns (uint256[] memory hintIds);

    function finalize(uint256 _lastRequestIdToBeFinalized, uint256 _maxShareRate) external payable;

    function prefinalize(uint256[] calldata _batches, uint256 _maxShareRate)
        external
        view
        returns (uint256 ethToLock, uint256 sharesToBurn);

    function calculateFinalizationBatches(
        uint256 _maxShareRate,
        uint256 _maxTimestamp,
        uint256 _maxRequestsPerCall,
        BatchesCalculationState memory _state
    ) external view returns (BatchesCalculationState memory);
}
