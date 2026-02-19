// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title IMorpho
/// @notice Interface for Morpho Blue flash loan functionality
interface IMorpho {
    /// @notice Executes a flash loan
    /// @param token The address of the token to borrow
    /// @param assets The amount of assets to borrow
    /// @param data Arbitrary data to pass to the callback
    function flashLoan(address token, uint256 assets, bytes calldata data) external;
}

