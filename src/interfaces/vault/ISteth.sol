// SPDX-License-Identifier: BUSL-1.1
// Author: Lendvest

pragma solidity 0.8.20;

interface ISteth {
    /**
     * @notice Allows a user to deposit Ether and receive stETH in return.
     * @param _referral The address of the referral (if any) for the deposit.
     * @return The amount of stETH minted for the deposited Ether.
     */
    function submit(address _referral) external payable returns (uint256);

    /**
     * @return the amount of Ether that corresponds to `_sharesAmount` token shares.
     */
    function getPooledEthByShares(uint256 _sharesAmount) external view returns (uint256);
}
