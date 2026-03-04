// SPDX-License-Identifier: BUSL-1.1
// Author: Lendvest

pragma solidity ^0.8.20;

import {ILVLidoVault} from "./interfaces/ILVLidoVault.sol";
import {VaultLib} from "./libraries/VaultLib.sol";
import {IPoolInfoUtils} from "./interfaces/IPoolInfoUtils.sol";
import {IERC20Pool} from "./interfaces/pool/erc20/IERC20Pool.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title LVLidoVaultUpkeeper
 * @notice Handles epoch closing logic extracted from LVLidoVaultUtil to reduce contract size
 * @dev This contract is called by LVLidoVaultUtil.performUpkeep() for task 2 (close epoch)
 *      It processes Lido withdrawals, calculates debts, and distributes funds to participants
 */
contract LVLidoVaultUpkeeper {
    ILVLidoVault public immutable LVLidoVault;
    IPoolInfoUtils public constant poolInfoUtils = IPoolInfoUtils(0x30c5eF2997d6a882DE52c4ec01B6D0a5e5B4fAAE);

    address public lvLidoVaultUtil;

    error OnlyLVLidoVaultUtil();
    error DebtGreaterThanAvailableFunds();
    error UpkeepFailed();

    modifier onlyUtil() {
        if (msg.sender != lvLidoVaultUtil) revert OnlyLVLidoVaultUtil();
        _;
    }

    constructor(address _LVLidoVault) {
        LVLidoVault = ILVLidoVault(_LVLidoVault);
    }

    /**
     * @notice Sets the LVLidoVaultUtil address that is authorized to call this contract
     * @dev Can only be called by the LVLidoVault owner
     * @param _util The address of the LVLidoVaultUtil contract
     */
    function setLVLidoVaultUtil(address _util) external {
        require(msg.sender == LVLidoVault.owner(), "Only owner");
        require(_util != address(0), "Invalid address");
        lvLidoVaultUtil = _util;
    }

    /**
     * @notice Closes the current epoch by processing withdrawals, calculating debts, and distributing funds
     * @dev This function handles the entire epoch closing process:
     *      1. Claims Lido withdrawals if available
     *      2. Calculates actual debt based on elapsed time and rate
     *      3. Processes debt repayment
     *      4. Calculates amounts owed to lenders, borrowers, and collateral lenders
     *      5. Creates new orders for the next epoch
     *      6. Cleans up epoch data
     * @param t1Debt The current debt from pool info (t1 debt)
     * @param collateral The current collateral amount from pool
     */
    function closeEpoch(uint256 t1Debt, uint256 collateral) external onlyUtil {
        IERC20Pool pool = LVLidoVault.pool();

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

        // Withdraw all Aave deposits (lender + CL) back to vault before processing matches.
        // This ensures Aave funds are scoped to a single epoch and restores order amounts
        // with principal + interest so they carry over correctly to the next epoch.
        _withdrawAaveDepositsForEpochClose();

        // Process matches and create new orders
        _processMatchesAndCreateOrders(matchedLendersOwed, matchedBorrowersOwed, matchedCollateralLendersOwed);

        // Final cleanup
        LVLidoVault.end_epoch();
        LVLidoVault.setAllowKick(false);
    }

    /**
     * @notice Withdraws all Aave deposits (lender + CL) back to the vault at epoch close.
     * @dev Extracted from LVLidoVault to reduce vault bytecode below EIP-170 limit.
     * @dev For lenders: restores quoteAmount (was zeroed during deposit) with principal + proportional interest.
     * @dev For CLs: restores collateralAmount with proportional share (principal + interest).
     */
    function _withdrawAaveDepositsForEpochClose() internal {
        uint256 currentEpoch = LVLidoVault.epoch();

        // === Lender Aave Deposits ===
        uint256 totalLenderDeposits = LVLidoVault.totalAaveLenderDeposits();
        if (totalLenderDeposits > 0) {
            uint256 aaveBalance = LVLidoVault.getAaveBalanceQuote();
            uint256 withdrawn = LVLidoVault.executeAaveWithdraw(VaultLib.QUOTE_TOKEN, aaveBalance);

            VaultLib.LenderOrder[] memory orders = LVLidoVault.getLenderOrders();
            for (uint256 i = 0; i < orders.length; i++) {
                address user = orders[i].lender;
                uint256 userDeposit = LVLidoVault.userAaveLenderDeposits(user, currentEpoch);
                if (userDeposit > 0) {
                    uint256 userShare = (userDeposit * withdrawn) / totalLenderDeposits;
                    LVLidoVault.setLenderOrderQuoteAmount(i, userShare);
                    LVLidoVault.setUserAaveLenderDeposit(user, currentEpoch, 0);
                }
            }

            LVLidoVault.setTotalLenderQTUnutilized(LVLidoVault.totalLenderQTUnutilized() + withdrawn);
            LVLidoVault.setAaveLenderState(currentEpoch, 0, 0);

            emit VaultLib.AaveLenderEpochCloseWithdrawn(currentEpoch, withdrawn);
        }

        // === CL Aave Deposits ===
        uint256 totalCLDeposits = LVLidoVault.totalAaveCLDeposits();
        if (totalCLDeposits > 0) {
            uint256 aaveBalance = LVLidoVault.getAaveBalance();
            uint256 withdrawn = LVLidoVault.executeAaveWithdraw(VaultLib.COLLATERAL_TOKEN, aaveBalance);
            uint256 totalInterest = withdrawn > totalCLDeposits ? withdrawn - totalCLDeposits : 0;

            VaultLib.CollateralLenderOrder[] memory clOrders = LVLidoVault.getCollateralLenderOrders();
            for (uint256 i = 0; i < clOrders.length; i++) {
                address user = clOrders[i].collateralLender;
                uint256 userDeposit = LVLidoVault.userAaveCLDeposits(user, currentEpoch);
                if (userDeposit > 0) {
                    uint256 userShare = (userDeposit * withdrawn) / totalCLDeposits;
                    LVLidoVault.setCLOrderCollateralAmount(i, userShare);
                    LVLidoVault.setUserAaveCLDeposit(user, currentEpoch, 0);
                }
            }

            LVLidoVault.setTotalCollateralLenderCT(LVLidoVault.totalCollateralLenderCT() + totalInterest);
            LVLidoVault.setAaveCLState(currentEpoch, 0, 0);

            emit VaultLib.AaveCLEpochCloseWithdrawn(currentEpoch, withdrawn);
        }
    }

    /**
     * @notice Processes Lido withdrawal claims
     * @param t1Debt Current debt amount
     * @return claimAmount Amount claimed from Lido
     */
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

    /**
     * @notice Processes debt repayment and calculates lenders owed
     * @param t1Debt Current t1 debt
     * @param actualDebt Calculated actual debt with interest
     * @param claimAmount Amount claimed from Lido
     * @param pool The Ajna pool
     * @return matchedLendersOwed Amount owed to matched lenders
     */
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

    /**
     * @notice Calculates amount owed to collateral lenders (0.14% APY)
     * @param timeElapsed Time elapsed since epoch start
     * @return matchedCollateralLendersOwed Amount owed to collateral lenders
     */
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

    /**
     * @notice Calculates amount owed to borrowers
     * @param matchedCollateralLendersOwed Amount already allocated to collateral lenders
     * @return matchedBorrowersOwed Remaining collateral owed to borrowers
     */
    function _calculateBorrowersOwed(uint256 matchedCollateralLendersOwed) internal view returns (uint256 matchedBorrowersOwed) {
        uint256 totalEpochCollateral = IERC20(VaultLib.COLLATERAL_TOKEN).balanceOf(address(LVLidoVault))
            - LVLidoVault.totalBorrowerCTUnutilized() - LVLidoVault.totalCollateralLenderCT();

        if (matchedCollateralLendersOwed > totalEpochCollateral) {
            matchedBorrowersOwed = 0;
        } else {
            matchedBorrowersOwed = totalEpochCollateral - matchedCollateralLendersOwed;
        }
    }

    /**
     * @notice Clears Ajna deposits and burns tokens
     * @param pool The Ajna pool
     */
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

    /**
     * @notice Processes epoch matches and creates new orders for participants
     * @param matchedLendersOwed Amount owed to lenders
     * @param matchedBorrowersOwed Amount owed to borrowers
     * @param matchedCollateralLendersOwed Amount owed to collateral lenders
     */
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
