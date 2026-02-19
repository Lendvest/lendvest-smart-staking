// SPDX-License-Identifier: BUSL-1.1
// Author: Lendvest

pragma solidity ^0.8.20;

interface IWsteth {
    /**
     * @notice Returns the amount of stETH that corresponds to one wstETH.
     * @dev The value increases over time as staking rewards accumulate.
     * @return The amount of stETH per one wstETH, scaled to 18 decimals.
     */
    function stEthPerToken() external view returns (uint256);

    /**
     * @notice Returns the amount of wstETH that corresponds to one stETH.
     * @dev This value decreases over time as staking rewards accumulate.
     * @return The amount of wstETH per one stETH, scaled to 18 decimals.
     */
    function tokensPerStEth() external view returns (uint256);

    /**
     * @notice Wraps stETH into wstETH.
     * @dev Transfers `stETH` from the caller and mints `wstETH` to the caller.
     * @param _stETHAmount The amount of stETH to wrap.
     * @return The amount of wstETH minted.
     */
    function wrap(uint256 _stETHAmount) external returns (uint256);

    /**
     * @notice Returns the balance of the account.
     * @param account The address of the account.
     * @return The balance of the account.
     */
    function balanceOf(address account) external view returns (uint256);
}
