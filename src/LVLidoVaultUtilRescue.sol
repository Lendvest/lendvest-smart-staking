// SPDX-License-Identifier: BUSL-1.1
// Author: Lendvest
// Purpose: Rescue contract to close epoch 1 — bypasses wethToWsteth auth bug
//          by running as LVLidoVaultUtil (authorized caller).

pragma solidity ^0.8.20;

import {ILVLidoVault} from "./interfaces/ILVLidoVault.sol";
import {VaultLib} from "./libraries/VaultLib.sol";
import {IPoolInfoUtils} from "./interfaces/IPoolInfoUtils.sol";
import {IERC20Pool} from "./interfaces/pool/erc20/IERC20Pool.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title LVLidoVaultUtilRescue
 * @notice Minimal rescue contract that inlines closeEpoch logic from LVLidoVaultUpkeeper.
 * @dev Deploy, set as LVLidoVaultUtil via owner, call performTask(), then restore original VaultUtil.
 *      This contract IS the LVLidoVaultUtil from the vault's perspective, so wethToWsteth accepts it.
 */
contract LVLidoVaultUtilRescue {
    ILVLidoVault public immutable LVLidoVault;
    IPoolInfoUtils public constant poolInfoUtils = IPoolInfoUtils(0x30c5eF2997d6a882DE52c4ec01B6D0a5e5B4fAAE);

    error OnlyOwner();
    error DebtGreaterThanAvailableFunds();
    error UpkeepFailed();

    constructor(address _LVLidoVault) {
        LVLidoVault = ILVLidoVault(_LVLidoVault);
    }

    /**
     * @notice Executes the full closeEpoch flow. Only callable by vault owner.
     * @dev Replicates LVLidoVaultUpkeeper.closeEpoch() exactly, but called from
     *      a contract that IS the LVLidoVaultUtil address → wethToWsteth authorized.
     */
    function performTask() external {
        if (msg.sender != LVLidoVault.owner()) revert OnlyOwner();

        IERC20Pool pool = LVLidoVault.pool();
        (uint256 t1Debt,,,) = poolInfoUtils.borrowerInfo(address(pool), address(LVLidoVault));
        (, uint256 collateral,) = pool.borrowerInfo(address(LVLidoVault));

        // Determine actual debt based on elapsed time
        uint256 timeElapsed = block.timestamp - LVLidoVault.epochStart();
        uint256 actualDebt;
        if (t1Debt > 0) {
            actualDebt = (LVLidoVault.totalBorrowAmount() * (1e18 + ((LVLidoVault.rate() * timeElapsed) / 365 days))) / 1e18;
        } else {
            actualDebt = 0;
        }

        uint256 claimAmount = 0;
        if (LVLidoVault.fundsQueued()) {
            claimAmount = _processLidoWithdrawal(t1Debt);
        }

        // Process debt and calculate amounts owed
        uint256 matchedLendersOwed = _processDebtAndCalculateOwed(
            t1Debt,
            actualDebt,
            claimAmount,
            pool
        );

        // Repay debt if needed
        if (t1Debt > 0 || collateral > 0) {
            LVLidoVault.repayDebtForProxy(t1Debt, collateral);
        }

        // Calculate collateral lenders owed (0.14% APY)
        uint256 matchedCollateralLendersOwed = _calculateCollateralLendersOwed(timeElapsed);

        // Calculate borrowers owed
        uint256 matchedBorrowersOwed = _calculateBorrowersOwed(matchedCollateralLendersOwed);

        emit VaultLib.AmountsOwed(matchedLendersOwed, matchedBorrowersOwed, matchedCollateralLendersOwed);

        // Clear Ajna deposits and burn tokens
        _clearDepositsAndBurnTokens(pool);

        // Process matches and create new orders
        _processMatchesAndCreateOrders(matchedLendersOwed, matchedBorrowersOwed, matchedCollateralLendersOwed);

        // Final cleanup
        LVLidoVault.end_epoch();
        LVLidoVault.setAllowKick(false);
    }

    function _processLidoWithdrawal(uint256 t1Debt) internal returns (uint256 claimAmount) {
        uint256 firstIndex = 1;
        uint256 lastIndex = VaultLib.LIDO_WITHDRAWAL.getLastCheckpointIndex();
        uint256[] memory requestIds = new uint256[](1);
        requestIds[0] = LVLidoVault.requestId();
        uint256[] memory hints = VaultLib.LIDO_WITHDRAWAL.findCheckpointHints(requestIds, firstIndex, lastIndex);
        uint256[] memory claimableEthValues = VaultLib.LIDO_WITHDRAWAL.getClaimableEther(requestIds, hints);
        claimAmount = claimableEthValues[0];

        if (claimAmount > 0) {
            LVLidoVault.claimWithdrawal();
            emit VaultLib.FundsClaimed(LVLidoVault.requestId(), claimAmount);
            LVLidoVault.depositEthForWeth(claimAmount);
        } else {
            if (t1Debt != 0) {
                revert VaultLib.NoETHToClaim();
            }
        }
    }

    function _processDebtAndCalculateOwed(
        uint256 t1Debt,
        uint256 actualDebt,
        uint256 claimAmount,
        IERC20Pool pool
    ) internal returns (uint256 matchedLendersOwed) {
        if (actualDebt > claimAmount + LVLidoVault.totalManualRepay()) {
            revert DebtGreaterThanAvailableFunds();
        } else {
            if (actualDebt < claimAmount) {
                // THIS is the call that was failing from the Upkeeper.
                // Now it works because THIS contract IS the LVLidoVaultUtil.
                LVLidoVault.wethToWsteth(claimAmount - actualDebt);
            } else {
                LVLidoVault.setTotalManualRepay(LVLidoVault.totalManualRepay() - (actualDebt - claimAmount));
            }
        }

        if (actualDebt > 0) {
            bool mintSuccess = LVLidoVault.mintForProxy(address(LVLidoVault.testQuoteToken()), address(LVLidoVault), t1Debt);
            bool approveSuccess = LVLidoVault.approveForProxy(address(LVLidoVault.testQuoteToken()), address(pool), t1Debt);
            if (!mintSuccess || !approveSuccess) revert UpkeepFailed();

            matchedLendersOwed = LVLidoVault.totalLenderQTUtilized() - LVLidoVault.totalBorrowAmount() + actualDebt;
        } else {
            matchedLendersOwed = IERC20(VaultLib.QUOTE_TOKEN).balanceOf(address(LVLidoVault))
                - LVLidoVault.totalLenderQTUnutilized();
        }
    }

    function _calculateCollateralLendersOwed(uint256 timeElapsed) internal view returns (uint256 matchedCollateralLendersOwed) {
        matchedCollateralLendersOwed = (
            (LVLidoVault.totalCLDepositsUnutilized() + LVLidoVault.totalCLDepositsUtilized())
                * (1e18 + ((timeElapsed * 14e14) / 365 days))
        ) / 1e18;

        uint256 totalEpochCollateral = IERC20(VaultLib.COLLATERAL_TOKEN).balanceOf(address(LVLidoVault))
            - LVLidoVault.totalBorrowerCTUnutilized() - LVLidoVault.totalCollateralLenderCT();

        if (matchedCollateralLendersOwed > totalEpochCollateral) {
            matchedCollateralLendersOwed = totalEpochCollateral;
        }
    }

    function _calculateBorrowersOwed(uint256 matchedCollateralLendersOwed) internal view returns (uint256 matchedBorrowersOwed) {
        uint256 totalEpochCollateral = IERC20(VaultLib.COLLATERAL_TOKEN).balanceOf(address(LVLidoVault))
            - LVLidoVault.totalBorrowerCTUnutilized() - LVLidoVault.totalCollateralLenderCT();

        if (matchedCollateralLendersOwed > totalEpochCollateral) {
            matchedBorrowersOwed = 0;
        } else {
            matchedBorrowersOwed = totalEpochCollateral - matchedCollateralLendersOwed;
        }
    }

    function _clearDepositsAndBurnTokens(IERC20Pool pool) internal {
        uint256 depositSize = pool.depositSize();
        LVLidoVault.clearAjnaDeposits(depositSize);

        bool burnCTSuccess = LVLidoVault.burnForProxy(
            address(LVLidoVault.testCollateralToken()),
            address(LVLidoVault),
            LVLidoVault.testCollateralToken().balanceOf(address(LVLidoVault))
        );
        bool burnQTSuccess = LVLidoVault.burnForProxy(
            address(LVLidoVault.testQuoteToken()),
            address(LVLidoVault),
            IERC20(address(LVLidoVault.testQuoteToken())).balanceOf(address(LVLidoVault))
        );

        if (!burnCTSuccess || !burnQTSuccess) revert UpkeepFailed();
    }

    function _processMatchesAndCreateOrders(
        uint256 matchedLendersOwed,
        uint256 matchedBorrowersOwed,
        uint256 matchedCollateralLendersOwed
    ) internal {
        uint256 totalLenderQTUnutilizedToAdjust;
        uint256 newTotalBorrowerCT = LVLidoVault.totalBorrowerCT();
        uint256 newTotalBorrowerCTUnutilized = LVLidoVault.totalBorrowerCTUnutilized();
        uint256 currentEpoch = LVLidoVault.epoch();

        // Process lender and borrower matches
        VaultLib.MatchInfo[] memory matches = LVLidoVault.getEpochMatches(currentEpoch);
        for (uint256 i = 0; i < matches.length; i++) {
            VaultLib.MatchInfo memory match_ = matches[i];

            uint256 newLenderQuoteAmount = (
                (match_.quoteAmount + match_.reservedQuoteAmount) * matchedLendersOwed
            ) / LVLidoVault.totalLenderQTUtilized();

            uint256 newBorrowerCTAmount = (match_.collateralAmount * matchedBorrowersOwed)
                / (LVLidoVault.totalBorrowerCT() - LVLidoVault.totalBorrowerCTUnutilized());

            LVLidoVault.lenderOrdersPush(VaultLib.LenderOrder(match_.lender, newLenderQuoteAmount, 0));
            LVLidoVault.borrowerOrdersPush(VaultLib.BorrowerOrder(match_.borrower, newBorrowerCTAmount));

            totalLenderQTUnutilizedToAdjust += newLenderQuoteAmount;
            newTotalBorrowerCTUnutilized += newBorrowerCTAmount;
            newTotalBorrowerCT = newTotalBorrowerCT - match_.collateralAmount + newBorrowerCTAmount;
        }

        // Emit interest earned event
        emit VaultLib.EpochInterestEarned(
            currentEpoch,
            (LVLidoVault.totalLenderQTUnutilized() + totalLenderQTUnutilizedToAdjust) > LVLidoVault.totalLenderQTUtilized()
                ? (LVLidoVault.totalLenderQTUnutilized() + totalLenderQTUnutilizedToAdjust) - LVLidoVault.totalLenderQTUtilized()
                : 0,
            newTotalBorrowerCT > LVLidoVault.totalBorrowerCT()
                ? newTotalBorrowerCT - LVLidoVault.totalBorrowerCT()
                : 0,
            matchedCollateralLendersOwed > (LVLidoVault.totalCLDepositsUnutilized() + LVLidoVault.totalCLDepositsUtilized())
                ? matchedCollateralLendersOwed - (LVLidoVault.totalCLDepositsUnutilized() + LVLidoVault.totalCLDepositsUtilized())
                : 0
        );

        // Update lender totals
        LVLidoVault.setTotalLenderQTUnutilized(LVLidoVault.totalLenderQTUnutilized() + totalLenderQTUnutilizedToAdjust);
        LVLidoVault.setTotalLenderQTUtilized(0);

        // Update borrower totals
        LVLidoVault.setTotalBorrowerCT(newTotalBorrowerCT);
        LVLidoVault.setTotalBorrowerCTUnutilized(newTotalBorrowerCTUnutilized);

        // Delete epoch matches
        LVLidoVault.deleteEpochMatches(currentEpoch);

        // Process collateral lender orders
        VaultLib.CollateralLenderOrder[] memory clOrders = LVLidoVault.getEpochCollateralLenderOrders(currentEpoch);
        uint256 totalCLDeposits = LVLidoVault.totalCLDepositsUnutilized() + LVLidoVault.totalCLDepositsUtilized();

        for (uint256 i = 0; i < clOrders.length; i++) {
            VaultLib.CollateralLenderOrder memory clOrder = clOrders[i];
            uint256 newCLCollateralAmount = (clOrder.collateralAmount * matchedCollateralLendersOwed) / totalCLDeposits;

            LVLidoVault.collateralLenderOrdersPush(
                VaultLib.CollateralLenderOrder(clOrder.collateralLender, newCLCollateralAmount)
            );
            LVLidoVault.setTotalCollateralLenderCT(LVLidoVault.totalCollateralLenderCT() + newCLCollateralAmount);
        }

        // Cleanup collateral lender epoch data
        LVLidoVault.deleteEpochCollateralLenderOrders(currentEpoch);
        LVLidoVault.setTotalCLDepositsUnutilized(0);
        LVLidoVault.setTotalCLDepositsUtilized(0);
    }
}
