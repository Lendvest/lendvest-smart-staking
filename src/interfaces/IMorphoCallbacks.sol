// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title IMorphoFlashLoanCallback
/// @notice Interface for contracts that want to receive Morpho Blue flash loans
interface IMorphoFlashLoanCallback {
    /// @notice Callback function called by Morpho during a flash loan
    /// @param assets The amount of assets that were flash loaned
    /// @param data Arbitrary data passed from the flash loan initiator
    /// @dev The contract must approve Morpho to spend `assets` amount of the borrowed token
    /// @dev Morpho will pull the funds after this callback completes
    function onMorphoFlashLoan(uint256 assets, bytes calldata data) external;
}

