// SPDX-License-Identifier: BUSL-1.1
// Author: Lendvest

pragma solidity ^0.8.20;

import {ILidoWithdrawal} from "../interfaces/vault/ILidoWithdrawal.sol";

/**
 * @title VaultLib
 */
library VaultLib {
    struct LenderOrder {
        address lender;
        uint256 quoteAmount;
        uint256 vaultShares;
    }

    struct BorrowerOrder {
        address borrower;
        uint256 collateralAmount;
    }

    struct CollateralLenderOrder {
        address collateralLender;
        uint256 collateralAmount;
    }

    struct MatchInfo {
        address lender;
        address borrower;
        uint256 quoteAmount; // 97%
        uint256 collateralAmount;
        uint256 reservedQuoteAmount; // 3%
    }

    address public constant QUOTE_TOKEN = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant COLLATERAL_TOKEN = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address public constant STETH_ADDRESS = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    ILidoWithdrawal public constant LIDO_WITHDRAWAL = ILidoWithdrawal(0x889edC2eDab5f40e902b864aD4d7AdE8E412F9B1);
    address public constant router = 0x65Dcc24F8ff9e51F10DCc7Ed1e4e2A61e6E14bd6;
    bytes32 public constant donId = 0x66756e2d657468657265756d2d6d61696e6e65742d3100000000000000000000;
    uint256 public constant leverageFactor = 80;

    /* EVENTS */
    event EndEpoch(uint256 time);
    event TermEnded(uint256 time);
    event FundsQueued(uint256 requestId, uint256 collateralAmount);
    event FundsClaimed(uint256 requestId, uint256 amount);
    event FundsAdded(uint256 ethAmount, uint256 contractBalance, address sender);
    event ForwarderAddressUpdated(address oldAddress, address newAddress);
    event AvoidLiquidation(uint256 collateralAmount);
    event EpochStarted(uint256 epoch, uint256 epochStart, uint256 termEnd);
    event RedemptionRateUpdated(uint256 redemptionRate);
    event OCRResponse(bytes32 indexed requestId, bytes response, uint256 rate, bytes err);
    event RequestRevertedWithErrorMsg(string reason);
    event RequestRevertedWithoutErrorMsg(bytes data);
    event LVLidoVaultUtilAddressUpdated(address oldAddress, address newAddress);
    event LoanComposition(
        uint256 baseCollateral, uint256 leveragedCollateral, uint256 totalCollateral, uint256 quoteToBorrow
    );
    event AmountsOwed(uint256 lendersOwed, uint256 borrowersOwed, uint256 collateralLendersOwed);
    // ------------------------------------------------------------
    // Confirmed to be used
    event LenderOrderAdded(address lender, uint256 quoteAmount);
    event BorrowerOrderAdded(address borrower, uint256 collateralAmount);
    event CollateralLenderDeposit(address collateralLender, uint256 collateralAmount);
    event WithdrawLender(address lender, uint256 quoteAmount);
    event WithdrawBorrower(address borrower, uint256 collateralAmount);
    event WithdrawCollateralLender(address collateralLender, uint256 collateralAmount);
    event EpochInterestEarned(
        uint256 epochNumber,
        uint256 lendersInterestAccrued,
        uint256 borrowersInterestAccrued,
        uint256 collateralLendersInterestAccrued
    );

    /* Errors */
    error InsufficientFunds();
    error Unauthorized();
    error OnlyForwarder();
    error OnlyProxy();
    error ReentrantCall();
    error InvalidInput();
    error NoETHToClaim();
    error NoUnfilledOrdersFound();
    error MaxFundsExceeded();
    error TokenOperationFailed();
    error LockedBonds();
    error InvalidEpoch();
    error EpochNotEnded();
    error EmergencyWithdrawalTooEarly();
    error NoEmergencyClaim();

    // ------------------------------------------------------------
}
