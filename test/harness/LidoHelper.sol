// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {IWsteth} from "../../src/interfaces/vault/IWsteth.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title LidoHelper
 * @notice Test utilities for Lido stETH/wstETH operations
 * @dev Provides:
 *      1. Conversion calculations
 *      2. Rate simulation
 *      3. Withdrawal queue helpers
 */
contract LidoHelper {

    IWsteth public constant WSTETH = IWsteth(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
    IERC20 public constant STETH = IERC20(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);

    /**
     * @notice Get current stETH per wstETH exchange rate
     * @return rate The amount of stETH per 1 wstETH (in 1e18)
     */
    function getStethPerWsteth() public view returns (uint256) {
        return WSTETH.stEthPerToken();
    }

    /**
     * @notice Convert wstETH amount to stETH
     * @param wstethAmount Amount of wstETH
     * @return stethAmount Equivalent stETH amount
     */
    function wstethToSteth(uint256 wstethAmount) public view returns (uint256) {
        // stEthPerToken returns how much stETH 1 wstETH is worth
        return (wstethAmount * WSTETH.stEthPerToken()) / 1e18;
    }

    /**
     * @notice Convert stETH amount to wstETH
     * @param stethAmount Amount of stETH
     * @return wstethAmount Equivalent wstETH amount
     */
    function stethToWsteth(uint256 stethAmount) public view returns (uint256) {
        // tokensPerStEth returns how much wstETH 1 stETH is worth
        return (stethAmount * WSTETH.tokensPerStEth()) / 1e18;
    }

    /**
     * @notice Calculate expected wstETH value in ETH
     * @param wstethAmount Amount of wstETH
     * @return ethValue Approximate ETH value
     */
    function wstethToEth(uint256 wstethAmount) public view returns (uint256) {
        // wstETH → stETH → ETH (stETH ≈ ETH with small discount)
        uint256 stethAmount = wstethToSteth(wstethAmount);
        // Assume 1:1 for simplicity (in reality there's a small discount)
        return stethAmount;
    }

    /**
     * @notice Calculate collateralization ratio
     * @param collateralWsteth wstETH collateral amount
     * @param debtWeth WETH debt amount
     * @return ratio Collateralization ratio (1e18 = 100%)
     */
    function calculateCollateralRatio(
        uint256 collateralWsteth,
        uint256 debtWeth
    ) public view returns (uint256) {
        if (debtWeth == 0) return type(uint256).max;

        uint256 collateralValue = wstethToEth(collateralWsteth);
        return (collateralValue * 1e18) / debtWeth;
    }

    /**
     * @notice Check if position would be liquidatable
     * @param collateralWsteth wstETH collateral
     * @param debtWeth WETH debt
     * @param threshold Liquidation threshold (e.g., 1.1e18 = 110%)
     * @return isLiquidatable Whether position is under threshold
     */
    function isLiquidatable(
        uint256 collateralWsteth,
        uint256 debtWeth,
        uint256 threshold
    ) public view returns (bool) {
        uint256 ratio = calculateCollateralRatio(collateralWsteth, debtWeth);
        return ratio < threshold;
    }

    /**
     * @notice Lido withdrawal claim delay
     */
    function getLidoClaimDelay() public pure returns (uint256) {
        return 7 days;
    }
}
