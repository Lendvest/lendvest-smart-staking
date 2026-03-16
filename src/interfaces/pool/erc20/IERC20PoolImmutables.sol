// SPDX-License-Identifier: BUSL-1.1
// Author: Lendvest

pragma solidity ^0.8.20;

/**
 * @title ERC20 Pool Immutables
 */
interface IERC20PoolImmutables {
    /**
     *  @notice Returns the `collateralScale` immutable.
     *  @return The precision of the collateral `ERC20` token based on decimals.
     */
    function collateralScale() external view returns (uint256);
}
