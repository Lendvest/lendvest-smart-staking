// SPDX-License-Identifier: BUSL-1.1
// Author: Lendvest

pragma solidity ^0.8.20;

import {IERC20Pool} from "./pool/erc20/IERC20Pool.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {VaultLib} from "../libraries/VaultLib.sol";

interface ILVLidoVault {
    function pool() external view returns (IERC20Pool);
    function totalBorrowAmount() external view returns (uint256);
    function totalCLDepositsUnutilized() external view returns (uint256);
    function totalCLDepositsUtilized() external view returns (uint256);
    function epochStartRedemptionRate() external view returns (uint256);
    function epochStart() external view returns (uint256);
    function termDuration() external view returns (uint256);
    function currentRedemptionRate() external view returns (uint256);
    function priceDifferencethreshold() external view returns (int256);
    function collateralLenderTraunche() external view returns (uint256);
    function epochStarted() external view returns (bool);
    function getInverseInitialCollateralLenderDebtRatio() external view returns (uint256);
    function fundsQueued() external view returns (bool);
    function requestId() external view returns (uint256);
    function getRate() external;
    function avoidLiquidation(uint256 collateralToAdd) external;
    function setCollateralLenderTraunche(uint256 newTraunche) external;
    function setCurrentRedemptionRate(uint256 newRate) external;
    function setAllowKick(bool allow) external;
    function rate() external view returns (uint256);
    function approveForProxy(address token, address spender, uint256 amount) external returns (bool);
    function requestWithdrawalsWstETH(uint256[] calldata amounts) external returns (uint256);
    function claimWithdrawal() external;
    function depositEthForWeth(uint256 amount) external;
    function totalManualRepay() external view returns (uint256);
    function lockedDebt() external view returns (uint256);
    function wethToWsteth(uint256 amount) external returns (uint256);
    function setTotalManualRepay(uint256 newTotal) external;
    function setLockedDebt(uint256 amount) external;
    function testQuoteToken() external view returns (address);
    function mintForProxy(address token, address to, uint256 amount) external returns (bool);
    function totalLenderQTUtilized() external view returns (uint256);
    function totalLenderQTUnutilized() external view returns (uint256);
    function repayDebtForProxy(uint256 debtAmount, uint256 collateralAmount) external;
    function totalBorrowerCTUnutilized() external view returns (uint256);
    function totalCollateralLenderCT() external view returns (uint256);
    function getLenderOrders() external view returns (VaultLib.LenderOrder[] memory);
    function getLenderOrdersLength() external view returns (uint256);
    function getBorrowerOrders() external view returns (VaultLib.BorrowerOrder[] memory);
    function getBorrowerOrdersLength() external view returns (uint256);
    function getCollateralLenderOrders() external view returns (VaultLib.CollateralLenderOrder[] memory);
    function getCollateralLenderOrdersLength() external view returns (uint256);
    function clearAjnaDeposits(uint256 depositSize) external;
    function testCollateralToken() external view returns (IERC20);
    function burnForProxy(address token, address from, uint256 amount) external returns (bool);
    function totalBorrowerCT() external view returns (uint256);
    function epoch() external view returns (uint256);
    function getEpochMatches(uint256 epoch) external view returns (VaultLib.MatchInfo[] memory);
    function lenderOrdersPush(VaultLib.LenderOrder memory order) external;
    function borrowerOrdersPush(VaultLib.BorrowerOrder memory order) external;
    function setTotalLenderQTUnutilized(uint256 amount) external;
    function setTotalLenderQTUtilized(uint256 amount) external;
    function setTotalBorrowerCT(uint256 amount) external;
    function setTotalBorrowerCTUnutilized(uint256 amount) external;
    function deleteEpochMatches(uint256 epoch) external;
    function getEpochCollateralLenderOrders(uint256 epoch)
        external
        view
        returns (VaultLib.CollateralLenderOrder[] memory);
    function collateralLenderOrdersPush(VaultLib.CollateralLenderOrder memory order) external;
    function setTotalCollateralLenderCT(uint256 amount) external;
    function deleteEpochCollateralLenderOrders(uint256 epoch) external;
    function setTotalCLDepositsUnutilized(uint256 amount) external;
    function setTotalCLDepositsUtilized(uint256 amount) external;
    function end_epoch() external;
    function owner() external view returns (address);
    function getAllowKick() external view returns (bool);
    function updateRate(uint256 _rate) external;
    function transferForProxy(address token, address recipient, uint256 amount) external returns (bool);

    // Aave read-only (auto-generated from public state)
    function getAaveBalance() external view returns (uint256);
    function getAaveBalanceQuote() external view returns (uint256);
    function totalAaveLenderDeposits() external view returns (uint256);
    function totalAaveCLDeposits() external view returns (uint256);
    function epochToAaveLenderDeposits(uint256 _epoch) external view returns (uint256);
    function epochToAaveCLDeposits(uint256 _epoch) external view returns (uint256);
    function userAaveLenderDeposits(address user, uint256 _epoch) external view returns (uint256);
    function userAaveCLDeposits(address user, uint256 _epoch) external view returns (uint256);
    function emergencyAaveWithdrawDelay() external view returns (uint256);

    // Emergency recovery state (auto-generated from public mappings)
    function epochEmergencyLenderWithdrawn(uint256 _epoch) external view returns (bool);
    function epochEmergencyCLWithdrawn(uint256 _epoch) external view returns (bool);
    function epochEmergencyLenderPrincipalRemaining(uint256 _epoch) external view returns (uint256);
    function epochEmergencyLenderClaimableRemaining(uint256 _epoch) external view returns (uint256);
    function epochEmergencyCLPrincipalRemaining(uint256 _epoch) external view returns (uint256);
    function epochEmergencyCLClaimableRemaining(uint256 _epoch) external view returns (uint256);

    // Execution wrappers (called by Util and Upkeeper)
    function executeAaveWithdraw(address token, uint256 amount) external returns (uint256);
    function setLenderOrderQuoteAmount(uint256 index, uint256 amount) external;
    function setCLOrderCollateralAmount(uint256 index, uint256 amount) external;
    function setUserAaveLenderDeposit(address user, uint256 _epoch, uint256 amount) external;
    function setUserAaveCLDeposit(address user, uint256 _epoch, uint256 amount) external;
    function setAaveLenderState(uint256 _epoch, uint256 _totalDeposits, uint256 _epochDeposits) external;
    function setAaveCLState(uint256 _epoch, uint256 _totalDeposits, uint256 _epochDeposits) external;
    function setEmergencyLenderState(uint256 _epoch, bool _withdrawn, uint256 _principal, uint256 _claimable) external;
    function setEmergencyCLState(uint256 _epoch, bool _withdrawn, uint256 _principal, uint256 _claimable) external;

    // Admin proxy setters (called by Util)
    function setMaxFlashLoanFeeThresholdProxy(uint256 _maxFeeBps, uint256 _flashLoanFeeBps) external;
}
