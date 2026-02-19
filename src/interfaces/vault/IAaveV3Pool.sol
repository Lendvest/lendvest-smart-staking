// SPDX-License-Identifier: BUSL-1.1
// Author: Lendvest

pragma solidity ^0.8.20;

/**
 * @title IAaveV3Pool
 * @notice Interface for Aave V3 Pool contract for supply and withdraw operations
 */
interface IAaveV3Pool {
    /**
     * @notice Supplies an `amount` of underlying asset into the reserve, receiving in return overlying aTokens.
     * @param asset The address of the underlying asset to supply
     * @param amount The amount to be supplied
     * @param onBehalfOf The address that will receive the aTokens, same as msg.sender if the user
     *   wants to receive them on his own wallet, or a different address if the beneficiary of aTokens
     *   is a different wallet
     * @param referralCode Code used to register the integrator originating the operation, for potential rewards.
     *   0 if the action is executed directly by the user, without any middle-man
     */
    function supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;

    /**
     * @notice Withdraws an `amount` of underlying asset from the reserve, burning the equivalent aTokens owned
     * @param asset The address of the underlying asset to withdraw
     * @param amount The underlying amount to be withdrawn
     *   - Send the value type(uint256).max in order to withdraw the whole aToken balance
     * @param to The address that will receive the underlying, same as msg.sender if the user
     *   wants to receive it on his own wallet, or a different address if the beneficiary is a
     *   different wallet
     * @return The final amount withdrawn
     */
    function withdraw(address asset, uint256 amount, address to) external returns (uint256);

    /**
     * @notice Returns the reserve data for a given asset
     * @param asset The address of the underlying asset
     * @return configuration The reserve configuration bitmap
     * @return liquidityIndex The liquidity index of the reserve
     * @return currentLiquidityRate The current liquidity rate
     * @return variableBorrowIndex The variable borrow index
     * @return currentVariableBorrowRate The current variable borrow rate
     * @return currentStableBorrowRate The current stable borrow rate
     * @return lastUpdateTimestamp The timestamp of the last update
     * @return id The reserve id
     * @return aTokenAddress The address of the aToken
     * @return stableDebtTokenAddress The address of the stable debt token
     * @return variableDebtTokenAddress The address of the variable debt token
     * @return interestRateStrategyAddress The address of the interest rate strategy
     * @return accruedToTreasury The amount accrued to treasury
     * @return unbacked The unbacked amount
     * @return isolationModeTotalDebt The total debt in isolation mode
     */
    function getReserveData(address asset) external view returns (
        uint256 configuration,
        uint128 liquidityIndex,
        uint128 currentLiquidityRate,
        uint128 variableBorrowIndex,
        uint128 currentVariableBorrowRate,
        uint128 currentStableBorrowRate,
        uint40 lastUpdateTimestamp,
        uint16 id,
        address aTokenAddress,
        address stableDebtTokenAddress,
        address variableDebtTokenAddress,
        address interestRateStrategyAddress,
        uint128 accruedToTreasury,
        uint128 unbacked,
        uint128 isolationModeTotalDebt
    );
}

/**
 * @title IAToken
 * @notice Interface for Aave aToken to check balances including interest
 */
interface IAToken {
    /**
     * @notice Returns the balance of the user including accrued interest
     * @param user The address of the user
     * @return The balance of the user
     */
    function balanceOf(address user) external view returns (uint256);
}
