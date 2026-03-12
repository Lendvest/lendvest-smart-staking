// SPDX-License-Identifier: BUSL-1.1
// Author: Lendvest
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Pool} from "./interfaces/pool/erc20/IERC20Pool.sol";
import {IPoolInfoUtils} from "./interfaces/IPoolInfoUtils.sol";
import {ILVToken} from "./interfaces/ILVToken.sol";
import {ILiquidationProxy} from "./interfaces/ILiquidationProxy.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {VaultLib} from "./libraries/VaultLib.sol";
import {IWsteth} from "./interfaces/vault/IWsteth.sol";
import {IWeth} from "./interfaces/vault/IWeth.sol";
import {ISteth} from "./interfaces/vault/ISteth.sol";
import {IMorpho} from "./interfaces/IMorpho.sol";
import {IMorphoFlashLoanCallback} from "./interfaces/IMorphoCallbacks.sol";
import {IPoolDataProvider} from "./interfaces/IPoolDataProvider.sol";
import {IAaveV3Pool, IAToken} from "./interfaces/vault/IAaveV3Pool.sol";

/// @author Lendvest Labs
contract LVLidoVault is IMorphoFlashLoanCallback, Ownable {
    ILVToken public testCollateralToken;
    ILVToken public testQuoteToken;

    IERC20Pool public pool;
    ILiquidationProxy public liquidationProxy;
    IMorpho public constant morpho = IMorpho(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb);
    ISteth public constant steth = ISteth(VaultLib.STETH_ADDRESS);
    IWsteth public constant wsteth = IWsteth(VaultLib.COLLATERAL_TOKEN);
    IPoolInfoUtils public constant poolInfoUtils = IPoolInfoUtils(0x30c5eF2997d6a882DE52c4ec01B6D0a5e5B4fAAE);
    IPoolDataProvider public constant poolDataProvider = IPoolDataProvider(0x497a1994c46d4f6C864904A9f1fac6328Cb7C8a6);
    IAaveV3Pool public constant aaveV3Pool = IAaveV3Pool(0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2);
    
    // Circuit breaker for flash loan fees
    uint256 public maxAcceptableFlashLoanFeeBps = 0; // 0 basis points = 0% fee (Morpho Blue standard)
    uint256 public flashLoanFeeBps = 0; // 0 basis points = 0% fee (Morpho Blue standard)

    address public LVLidoVaultUtil;
    address public LVLidoVaultUpkeeper;
    uint256 public totalBorrowAmount;
    uint256 public totalLenderQTUnutilized;
    uint256 public totalLenderQTUtilized;
    uint256 public totalBorrowerCT;
    uint256 public totalBorrowerCTUnutilized;
    uint256 public totalCollateralLenderCT;
    uint256 public totalCLDepositsUnutilized;
    uint256 public totalCLDepositsUtilized;
    uint256 public currentBucketIndex;
    uint256 public epochStartRedemptionRate;
    uint256 public currentRedemptionRate;
    uint256 public collateralLenderTraunche = 0;
    uint256 inverseBorrowCLAmount = 2;
    uint256 public epoch = 0;
    uint256 public epochStart;
    uint256 public termDuration = 14 days;
    uint256 public lastEpochEnd;
    uint256 public constant epochCoolDownPeriod = 1 days;
    uint256 public deploymentTimestamp;
    uint256 public rate = 0;
    int256 public constant priceDifferencethreshold = -1e16; // -1%
    uint256 public constant MIN_ORDER_SIZE = 1e16; // 0.01 ETH - prevents storage bloat DoS
    uint256 public constant MAX_ORDERS_PER_USER = 10; // Prevents single actor from bloating arrays
    uint256 public constant MAX_ORDERS_PER_EPOCH = 260; // Caps gas usage in epoch matching/close loops
    bool public epochStarted;
    bool private _borrowInitiated;
    bool public fundsQueued;

    VaultLib.LenderOrder[] public lenderOrders;
    VaultLib.BorrowerOrder[] public borrowerOrders;
    VaultLib.CollateralLenderOrder[] public collateralLenderOrders;
    mapping(uint256 => VaultLib.MatchInfo[]) public epochToMatches;
    mapping(uint256 => VaultLib.CollateralLenderOrder[]) public epochToCollateralLenderOrders;

    // Aave V3 integration for unmatched collateral lender deposits
    mapping(uint256 => uint256) public epochToAaveCLDeposits; // epoch => total CL deposits in Aave for that epoch
    mapping(address => mapping(uint256 => uint256)) public userAaveCLDeposits; // user => epoch => amount deposited in Aave
    uint256 public totalAaveCLDeposits; // Total CL deposits currently in Aave across all epochs
    
    // Aave V3 integration for unmatched lender deposits (quote token)
    mapping(uint256 => uint256) public epochToAaveLenderDeposits; // epoch => total lender deposits in Aave for that epoch
    mapping(address => mapping(uint256 => uint256)) public userAaveLenderDeposits; // user => epoch => amount deposited in Aave
    uint256 public totalAaveLenderDeposits; // Total lender deposits currently in Aave across all epochs

    // Emergency Aave recovery accounting (per epoch).
    uint256 public constant emergencyAaveWithdrawDelay = 3 days;
    mapping(uint256 => bool) public epochEmergencyLenderWithdrawn;
    mapping(uint256 => bool) public epochEmergencyCLWithdrawn;
    mapping(uint256 => uint256) public epochEmergencyLenderPrincipalRemaining;
    mapping(uint256 => uint256) public epochEmergencyLenderClaimableRemaining;
    mapping(uint256 => uint256) public epochEmergencyCLPrincipalRemaining;
    mapping(uint256 => uint256) public epochEmergencyCLClaimableRemaining;
    
    
    uint256 public requestId;
    uint256 public totalManualRepay;

    // Anti-DoS: track active orders per user
    mapping(address => uint256) public userActiveOrderCount;

    bool internal locked;

    event RateUpdated(uint256 rate);
    event FlashLoanFeeThresholdUpdated(uint256 oldThreshold, uint256 newThreshold);
    event EpochMatchingSkipped(uint256 epoch, string reason);
    event AaveCLDeposited(uint256 epoch, uint256 totalAmount, uint256 userCount);
    event AaveCLWithdrawn(address user, uint256 amount, uint256 epoch);
    event AaveLenderDeposited(uint256 epoch, uint256 totalAmount, uint256 userCount);
    event AaveLenderWithdrawn(address user, uint256 amount, uint256 epoch);
    event AccountingDrift(string field, uint256 expected, uint256 actual);

    error OrderBelowMinimum(uint256 amount, uint256 minimum);
    error MaxOrdersExceeded(address user, uint256 current, uint256 max);
    error EpochOrderCapReached();

    /**
     * @notice Constructor
     * @param _pool The address of the Ajna Pool contract
     * @param _liquidationProxy The address of the Liquidation Proxy contract
     */
    constructor(address _pool, address _liquidationProxy) Ownable(msg.sender) {
        pool = IERC20Pool(_pool);
        liquidationProxy = ILiquidationProxy(_liquidationProxy);
        testCollateralToken = ILVToken(pool.collateralAddress());
        testQuoteToken = ILVToken(pool.quoteTokenAddress());
        deploymentTimestamp = block.timestamp;
        (,,,,, uint256 liquidityRate, uint256 variableBorrowRate,,,,,) = poolDataProvider.getReserveData(VaultLib.QUOTE_TOKEN);
        rate = ((liquidityRate + variableBorrowRate) / 2);

    }

    receive() external payable {
        if (msg.sender != address(VaultLib.LIDO_WITHDRAWAL) && msg.sender != VaultLib.QUOTE_TOKEN) {
            revert VaultLib.Unauthorized();
        }
        emit VaultLib.FundsAdded(msg.value, address(this).balance, msg.sender);
    }

    fallback() external payable {
        revert VaultLib.Unauthorized();
    }

    modifier lock() {
        _lock();
        _;
        locked = false;
    }

    function _lock() internal {
        if (locked) revert VaultLib.ReentrantCall();
        locked = true;
    }

    /**
     * @notice Modifier to restrict access to trusted proxy contracts
     * @dev Authorized callers: LVLidoVaultUtil, LiquidationProxy, LVLidoVaultUpkeeper
     * @dev IMPORTANT: When adding new proxy callers here, also review functions with
     *      custom authorization (e.g., wethToWsteth) to determine if they need the same update
     */
    modifier onlyProxy() {
        _onlyProxy();
        _;
    }

    function _onlyProxy() internal view {
        if (msg.sender != LVLidoVaultUtil && msg.sender != address(liquidationProxy) && msg.sender != LVLidoVaultUpkeeper) {
            revert VaultLib.OnlyProxy();
        }
    }


    /**
     * @notice Converts WETH to WSTETH through a series of token conversions
     * @dev Conversion flow:
     *      1. WETH -> ETH (unwrap)
     *      2. ETH -> stETH (stake with Lido)
     *      3. stETH -> wstETH (wrap)
     * @param amount Amount of WETH to convert
     * @return uint256 Amount of WSTETH received after conversion
     *
     * @custom:security Authorization - This function has CUSTOM authorization that differs from onlyProxy
     *
     * Authorized callers:
     * - morpho: For flash loan repayment scenarios where WETH needs conversion
     * - LVLidoVaultUtil: For utility operations requiring WETH->wstETH conversion
     * - LVLidoVaultUpkeeper: For closeEpoch when Lido claim exceeds debt (excess WETH conversion)
     *
     * NOT authorized:
     * - LiquidationProxy: Does not need WETH conversion capability
     *
     * @custom:security IMPORTANT: This authorization list intentionally differs from onlyProxy modifier
     * because it includes Morpho (for flash loans) and excludes LiquidationProxy (doesn't need it).
     * When updating onlyProxy, review if this function needs the same changes.
     *
     * Historical context: GitHub issue #1 - When closeEpoch was extracted to Upkeeper,
     * this auth check was not updated, causing closeEpoch to revert. Fixed by adding Upkeeper here.
     */
    function wethToWsteth(uint256 amount) public returns (uint256) {
        // Validate caller authorization
        // NOTE: This check intentionally differs from onlyProxy - see function documentation
        if (msg.sender != address(morpho) && msg.sender != address(LVLidoVaultUtil) && msg.sender != LVLidoVaultUpkeeper) {
            revert VaultLib.Unauthorized();
        }

        // Step 1: Unwrap WETH to ETH
        if (!IERC20(VaultLib.QUOTE_TOKEN).approve(address(VaultLib.QUOTE_TOKEN), amount)) {
            revert VaultLib.TokenOperationFailed();
        }
        IWeth(VaultLib.QUOTE_TOKEN).withdraw(amount);

        // Step 2: Stake ETH with Lido to receive stETH
        uint256 shares = steth.submit{value: amount}(address(0));
        uint256 stethReceived = steth.getPooledEthByShares(shares);

        // Step 3: Wrap stETH to wstETH
        if (!IERC20(address(steth)).approve(address(VaultLib.COLLATERAL_TOKEN), stethReceived)) {
            revert VaultLib.TokenOperationFailed();
        }

        return wsteth.wrap(stethReceived);
    }

    /**
     * @notice Handles the flash loan callback from Morpho Blue
     * @dev This function is called by Morpho Blue after a flash loan is initiated
     * @dev It performs the following steps:
     *      1. Validates the caller and loan authorization
     *      2. Mints collateral tokens for the pool
     *      3. Draws debt from the Ajna pool
     *      4. Converts borrowed WETH to wstETH to repay the flash loan
     * @param assets The amount of assets received in the flash loan
     * @param data Encoded data containing borrowing parameters
     */
    function onMorphoFlashLoan(uint256 assets, bytes calldata data) external override {
        // SECURITY: No `lock` modifier here - this callback is invoked DURING startEpoch()
        // which already holds the lock. Using lock here would cause ReentrantCall error.
        // Protection is provided by:
        // 1. msg.sender check - only Morpho can call this
        // 2. _borrowInitiated flag - only set by this contract in tryMatchOrders()
        if (msg.sender != address(morpho) || !_borrowInitiated) revert VaultLib.Unauthorized();
        _borrowInitiated = false;

        // Decode the user data to get borrowing parameters
        (uint256 baseLoanCollateral, uint256 amountToBorrow) = abi.decode(data, (uint256, uint256));

        // Calculate total collateral (base + flash loan amount)
        uint256 totalCollateral = baseLoanCollateral + assets;

        // CEI: Record state changes BEFORE any external calls
        totalBorrowAmount = amountToBorrow;

        emit VaultLib.LoanComposition(baseLoanCollateral, assets, totalCollateral, amountToBorrow);

        // Mint test collateral tokens and approve them for the pool
        if (
            !testCollateralToken.mint(address(this), totalCollateral)
                || !testCollateralToken.approve(address(pool), totalCollateral)
        ) {
            revert VaultLib.TokenOperationFailed();
        }

        // Draw debt from the Ajna pool using the collateral
        pool.drawDebt(address(this), amountToBorrow, currentBucketIndex, totalCollateral);

        // Burn test quote tokens (accounting for the borrowed amount)
        if (!testQuoteToken.burn(address(this), amountToBorrow)) {
            revert VaultLib.TokenOperationFailed();
        }

        // Convert WETH to wstETH to repay the flash loan
        uint256 wstethReceived = wethToWsteth(amountToBorrow);

        // CRITICAL SAFETY CHECK: Verify we received enough wstETH to repay the flash loan
        // If Morpho charges fees or conversion has slippage, we need to catch it here
        // Note: Morpho Blue standard is 0% fees, but this protects against future changes
        if (wstethReceived < assets) {
            revert VaultLib.InsufficientFunds();
        }

        // Repay the flash loan - Morpho Blue requires approval
        // Morpho will pull the tokens via transferFrom after this callback completes
        IERC20 wstethToken = IERC20(VaultLib.COLLATERAL_TOKEN);
        if (!wstethToken.approve(address(morpho), assets)) {
            revert VaultLib.TokenOperationFailed();
        }
    }

    /**
     * @notice Matches pending lender, borrower, and collateral lender orders.
     * @dev Creates loans by matching orders from the respective order books. Handles partial fulfillment by scaling
     * orders. Utilizes 97.5% of lender funds for loans, reserving 2.5% for interest. Supports lender funds from
     * direct deposits and flagship vault shares. Backs 50% of new debt with collateral lender deposits. Finally,
     * it initiates a flash loan to provide leverage for borrowers.
     */
    function tryMatchOrders() internal {
        uint256 initialUtilization = 975e15; // 97.5%
        uint256 originationFactor = poolInfoUtils.borrowFeeRate(address(pool));
        uint256 depositFeeRate = poolInfoUtils.depositFeeRate(address(pool));
        if (totalCollateralLenderCT == 0) {
            revert VaultLib.InsufficientFunds();
        }
        uint256 totalPreFeeAmountToDeposit = 0;
        uint256 borrowerCTMatched = 0;
        uint256 borrowAmountMatched = 0;


        // LIFO matching: process from back of arrays so router deposits (newest) self-match first
        uint256 i = lenderOrders.length;
        uint256 j = borrowerOrders.length;

        while (i > 0 && j > 0) {
            uint256 li = i - 1;
            uint256 bi = j - 1;

            // Calculate borrower's debt requirements
            uint256 flashLoanAmount = borrowerOrders[bi].collateralAmount * (VaultLib.leverageFactor - 10);
            uint256 amountToBorrow = (flashLoanAmount * epochStartRedemptionRate) / 1e19;
            uint256 borrowFee = (amountToBorrow * originationFactor) / 1e18;

            // Skip micro amounts from borrowers (zero out so pop() stays correct)
            if (borrowFee == 0) {
                borrowerOrders[bi].collateralAmount = 0;
                j--;
                continue;
            }
            uint256 t0Debt = amountToBorrow + borrowFee;
            uint256 maxLenderAmount = lenderOrders[li].quoteAmount;
            // Check lenderOrder balances, using native amounts for further processing
            if (lenderOrders[li].quoteAmount == 0) {
                i--;
                continue;
            }

            // Skip micro amounts from lenders (zero out so pop() stays correct)
            uint256 maxLenderQuoteAmountFee = (maxLenderAmount * depositFeeRate) / 1e18;
            if (maxLenderQuoteAmountFee == 0) {
                lenderOrders[li].quoteAmount = 0;
                i--;
                continue;
            }
            uint256 maxT0Debt = (initialUtilization * (maxLenderAmount - maxLenderQuoteAmountFee)) / 1e18;

            uint256 scaledT0Debt;
            uint256 scaledAmountToBorrow;
            uint256 scaledBorrowerCollateralAmount;
            uint256 preFeeAmountToDeposit;

            // Scale down values based on max lender deposit amount
            if (t0Debt > maxT0Debt) {
                // If borrower needs more than lender can provide, scale down the borrower's order
                scaledT0Debt = maxT0Debt;
                scaledAmountToBorrow = (scaledT0Debt * 1e18) / (1e18 + originationFactor);
                uint256 scalingFactor = (scaledAmountToBorrow * 1e18) / amountToBorrow;
                scaledBorrowerCollateralAmount = (borrowerOrders[bi].collateralAmount * scalingFactor) / 1e18;
                preFeeAmountToDeposit = maxLenderAmount;

                // Skip lender if scaling causes 0 values (zero out so pop() stays correct)
                if (scaledBorrowerCollateralAmount == 0 || preFeeAmountToDeposit == 0) {
                    lenderOrders[li].quoteAmount = 0;
                    i--;
                    continue;
                }
            }
            // Lender deposit is enough to support borrower order
            else {
                scaledT0Debt = t0Debt;
                scaledAmountToBorrow = amountToBorrow;
                scaledBorrowerCollateralAmount = borrowerOrders[bi].collateralAmount;
                preFeeAmountToDeposit = (scaledT0Debt * 1e36) / (initialUtilization * (1e18 - depositFeeRate));
            }

            // Amount set aside by lender for interest (with 97.5% initial utilization, 2.5% is set aside)
            uint256 scaledReservedQuoteAmount =
                ((1e18 - initialUtilization) * ((scaledT0Debt * 1e18) / initialUtilization)) / 1e18;

            // Create a match
            epochToMatches[epoch].push(
                VaultLib.MatchInfo({
                    lender: lenderOrders[li].lender,
                    borrower: borrowerOrders[bi].borrower,
                    quoteAmount: scaledT0Debt, // 97.5% of the quote token amount
                    collateralAmount: scaledBorrowerCollateralAmount,
                    reservedQuoteAmount: scaledReservedQuoteAmount // 2.5% of the quote token amount
                })
            );
            // Reduce available deposits for user
            lenderOrders[li].quoteAmount -= preFeeAmountToDeposit;
            // Account for totals and adjust borrowerOrder
            totalPreFeeAmountToDeposit += preFeeAmountToDeposit;
            borrowerCTMatched += scaledBorrowerCollateralAmount;
            borrowAmountMatched += scaledAmountToBorrow;
            borrowerOrders[bi].collateralAmount -= scaledBorrowerCollateralAmount;

            // Remove fully consumed orders — pop() is O(1) and always correct
            // because li/bi always point to the last element
            if (lenderOrders[li].quoteAmount == 0) {
                lenderOrders.pop();
                i--;
            }
            if (borrowerOrders[bi].collateralAmount == 0) {
                borrowerOrders.pop();
                j--;
            }
        }

        // Ensure collateral lender deposits are sufficient before processing their orders
        if (((borrowAmountMatched * 1e18) / epochStartRedemptionRate) / inverseBorrowCLAmount > totalCollateralLenderCT)
        {
            revert VaultLib.InsufficientFunds();
        }

        uint256 collateralLenderDepositsToMatch =
            ((borrowAmountMatched * 1e18) / epochStartRedemptionRate) / inverseBorrowCLAmount;

        // LIFO: Match collateral lender orders from back of array for router self-matching
        uint256 ci = collateralLenderOrders.length;
        while (ci > 0 && collateralLenderDepositsToMatch > 0) {
            uint256 cli = ci - 1;
            // Take as much as needed from each collateral lender
            uint256 collateralUtilized = collateralLenderOrders[cli].collateralAmount < collateralLenderDepositsToMatch
                ? collateralLenderOrders[cli].collateralAmount
                : collateralLenderDepositsToMatch;
            collateralLenderDepositsToMatch -= collateralUtilized;
            // Create collateralLenderOrder for the epoch
            epochToCollateralLenderOrders[epoch].push(
                VaultLib.CollateralLenderOrder({
                    collateralLender: collateralLenderOrders[cli].collateralLender,
                    collateralAmount: collateralUtilized
                })
            );

            // Remove or update the collateral lender order
            if (collateralUtilized == collateralLenderOrders[cli].collateralAmount) {
                // Fully utilized — pop() is O(1), cli is always the last element
                collateralLenderOrders.pop();
                ci--;
            } else {
                // Reduce partially utilized order
                collateralLenderOrders[cli].collateralAmount -= collateralUtilized;
            }

            // Decrement totalCollateralLenderCT when moving orders to epoch array
            // This ensures totalCollateralLenderCT always equals sum of collateralLenderOrders[]
            // At epoch end, Upkeeper will re-add with interest when processing epochToCollateralLenderOrders
            totalCollateralLenderCT -= collateralUtilized;
        }

        // Adjust global collateral lender totals
        // Track how much CL collateral was utilized in this epoch matching
        // This amount backs 50% of the borrowed debt (inverseBorrowCLAmount = 2)
        uint256 clUtilized = (((borrowAmountMatched * 1e18) / epochStartRedemptionRate) / inverseBorrowCLAmount);
        totalCLDepositsUtilized += clUtilized;
        // Track remaining unmatched CL for graduated liquidation protection (tranches).
        // totalCollateralLenderCT was decremented by utilized amounts in the loop above,
        // so it now holds exactly the unmatched CL remainder available for avoidLiquidation().
        totalCLDepositsUnutilized = totalCollateralLenderCT;

        // Deposit lender utilized amounts
        if (
            !testQuoteToken.mint(address(this), totalPreFeeAmountToDeposit)
                || !IERC20(pool.quoteTokenAddress()).approve(address(pool), totalPreFeeAmountToDeposit)
        ) {
            revert VaultLib.TokenOperationFailed();
        }
        (, uint256 totalPostFeeDepositAmount) =
            pool.addQuoteToken(totalPreFeeAmountToDeposit, currentBucketIndex, block.timestamp + 3600);

        // Note Accounting, lender fees deducted here
        totalLenderQTUtilized += totalPostFeeDepositAmount;
        if (totalPreFeeAmountToDeposit > totalLenderQTUnutilized) {
            emit AccountingDrift("totalLenderQTUnutilized", totalLenderQTUnutilized, totalPreFeeAmountToDeposit);
            totalLenderQTUnutilized = 0;
        } else {
            totalLenderQTUnutilized -= totalPreFeeAmountToDeposit;
        }

        // Build params and execute flash loan
        uint256 flashLoanAmount = (borrowerCTMatched * (VaultLib.leverageFactor - 10)) / 10;

        // Lock flash loan
        _borrowInitiated = true;
        morpho.flashLoan(
            VaultLib.COLLATERAL_TOKEN, // wstETH token address
            flashLoanAmount, // flash loan amount
            abi.encode(borrowerCTMatched, borrowAmountMatched)
        );
        totalBorrowerCTUnutilized -= borrowerCTMatched;
    }

        /**
     * @notice Gets the current aToken balance including accrued interest (for collateral - wstETH)
     * @dev This shows the total value (principal + interest) in Aave
     * @return The current awstETH balance of this contract
     */
    function getAaveBalance() public view returns (uint256) {
        (,,,,,,, , address aTokenAddress,,,,,,) = aaveV3Pool.getReserveData(VaultLib.COLLATERAL_TOKEN);
        if (aTokenAddress == address(0)) return 0;
        return IAToken(aTokenAddress).balanceOf(address(this));
    }

    /**
     * @notice Gets the current aToken balance including accrued interest (for quote token - WETH)
     * @dev This shows the total value (principal + interest) in Aave
     * @return The current aWETH balance of this contract
     */
    function getAaveBalanceQuote() public view returns (uint256) {
        (,,,,,,, , address aTokenAddress,,,,,,) = aaveV3Pool.getReserveData(VaultLib.QUOTE_TOKEN);
        if (aTokenAddress == address(0)) return 0;
        return IAToken(aTokenAddress).balanceOf(address(this));
    }

    // ========== ORDER ARRAY GETTERS ==========

    /**
     * @notice Returns all lender orders
     * @return Array of lender orders
     */
    function getLenderOrders() external view returns (VaultLib.LenderOrder[] memory) {
        return lenderOrders;
    }

    /**
     * @notice Returns the number of lender orders
     * @return Length of lender orders array
     */
    function getLenderOrdersLength() external view returns (uint256) {
        return lenderOrders.length;
    }

    /**
     * @notice Returns all borrower orders
     * @return Array of borrower orders
     */
    function getBorrowerOrders() external view returns (VaultLib.BorrowerOrder[] memory) {
        return borrowerOrders;
    }

    /**
     * @notice Returns the number of borrower orders
     * @return Length of borrower orders array
     */
    function getBorrowerOrdersLength() external view returns (uint256) {
        return borrowerOrders.length;
    }

    /**
     * @notice Returns all collateral lender orders
     * @return Array of collateral lender orders
     */
    function getCollateralLenderOrders() external view returns (VaultLib.CollateralLenderOrder[] memory) {
        return collateralLenderOrders;
    }

    /**
     * @notice Returns the number of collateral lender orders
     * @return Length of collateral lender orders array
     */
    function getCollateralLenderOrdersLength() external view returns (uint256) {
        return collateralLenderOrders.length;
    }

    /**
     * @notice Returns all matches for a given epoch
     * @param _epoch The epoch to get matches for
     * @return Array of match info for the epoch
     */
    function getEpochMatches(uint256 _epoch) external view returns (VaultLib.MatchInfo[] memory) {
        return epochToMatches[_epoch];
    }

    /**
     * @notice Returns all collateral lender orders for a given epoch
     * @param _epoch The epoch to get collateral lender orders for
     * @return Array of collateral lender orders for the epoch
     */
    function getEpochCollateralLenderOrders(uint256 _epoch) external view returns (VaultLib.CollateralLenderOrder[] memory) {
        return epochToCollateralLenderOrders[_epoch];
    }

    /**
     * @notice Deposits unmatched lender deposits to Aave V3
     * @dev Called after tryMatchOrders() to generate yield on unutilized lender funds
     * @dev Tracks deposits per user and per epoch for accurate accounting
     * @dev Replaces Morpho flagship vault with Aave V3 for better integration
     * @dev Only deposits if there are remaining unmatched lender orders
     */
    function depositUnmatchedLendersToAave() internal {
        // Check if there are any unmatched lender orders remaining
        if (lenderOrders.length == 0 || totalLenderQTUnutilized == 0) {
            return; // No unmatched orders to deposit
        }
        
        uint256 totalToDeposit = 0;
        uint256 userCount = 0;
        
        // Calculate total unmatched lender deposits and track per user for this epoch
        for (uint256 i = 0; i < lenderOrders.length; i++) {
            address user = lenderOrders[i].lender;
            uint256 amount = lenderOrders[i].quoteAmount;
            
            if (amount > 0) {
                // Track user's Aave deposit for this epoch
                userAaveLenderDeposits[user][epoch] += amount;
                totalToDeposit += amount;
                userCount++;
                
                // Clear the quoteAmount since it's going to Aave
                lenderOrders[i].quoteAmount = 0;
            }
        }
        
        // Only proceed if there's something to deposit
        if (totalToDeposit == 0) {
            return;
        }
        
        // Update global tracking
        epochToAaveLenderDeposits[epoch] = totalToDeposit;
        totalAaveLenderDeposits += totalToDeposit;
        
        // Approve Aave Pool to spend WETH
        if (!IERC20(VaultLib.QUOTE_TOKEN).approve(address(aaveV3Pool), totalToDeposit)) {
            revert VaultLib.TokenOperationFailed();
        }
        
        // Deposit to Aave V3 (receives aWETH in return)
        // referralCode = 0 (no referral)
        aaveV3Pool.supply(VaultLib.QUOTE_TOKEN, totalToDeposit, address(this), 0);
        
        // Update state
        totalLenderQTUnutilized = 0;
        
        // Emit event for tracking
        emit AaveLenderDeposited(epoch, totalToDeposit, userCount);
    }

    /**
     * @notice Deposits unmatched collateral lender deposits to Aave V3
     * @dev Called after tryMatchOrders() to generate yield on unutilized CL funds
     * @dev Tracks deposits per user and per epoch for accurate accounting
     * @dev Only deposits if there are remaining unmatched CL orders
     */
    function depositUnmatchedCLToAave() internal {
        // Check if there are any unmatched collateral lender orders remaining
        if (collateralLenderOrders.length == 0) {
            return; // No unmatched orders to deposit
        }
        
        uint256 totalToDeposit = 0;
        uint256 userCount = 0;
        
        // Calculate total unmatched CL deposits and track per user for this epoch
        for (uint256 i = 0; i < collateralLenderOrders.length; i++) {
            address user = collateralLenderOrders[i].collateralLender;
            uint256 amount = collateralLenderOrders[i].collateralAmount;

            if (amount > 0) {
                // Track user's Aave deposit for this epoch
                userAaveCLDeposits[user][epoch] += amount;
                totalToDeposit += amount;
                userCount++;

                // Zero the order amount — funds are moving to Aave
                // Restored at epoch close by withdrawAllAaveDepositsForEpochClose()
                collateralLenderOrders[i].collateralAmount = 0;
            }
        }
        
        // Only proceed if there's something to deposit
        if (totalToDeposit == 0) {
            return;
        }
        
        // Update global tracking
        epochToAaveCLDeposits[epoch] = totalToDeposit;
        totalAaveCLDeposits += totalToDeposit;
        
        // Approve Aave Pool to spend wstETH
        if (!IERC20(VaultLib.COLLATERAL_TOKEN).approve(address(aaveV3Pool), totalToDeposit)) {
            revert VaultLib.TokenOperationFailed();
        }
        
        // Deposit to Aave V3 (receives awstETH in return)
        // referralCode = 0 (no referral)
        aaveV3Pool.supply(VaultLib.COLLATERAL_TOKEN, totalToDeposit, address(this), 0);
        
        // Emit event for tracking
        emit AaveCLDeposited(epoch, totalToDeposit, userCount);
    }


    /**
     * @notice Checks if flash loan conditions are acceptable for matching orders
     * @dev Performs safety checks before committing to epoch matching
     * @return bool True if safe to proceed with flash loan-based matching
     */
    function isFlashLoanSafe() public view returns (bool) {
        // Check 1: Max fee threshold (if Morpho adds fees, we need to know)
        // Since we can't query Morpho fees directly, we rely on admin setting circuit breaker
        // If maxAcceptableFlashLoanFeeBps > 0, admin has approved some fee tolerance
        // If == 0 (default), we assume Morpho Blue's standard 0% fee model
        
        // Check 2: Ensure we have borrower orders to match
        if (borrowerOrders.length == 0) {
            return false;
        }
        
        // Check 3: Ensure we have collateral lender deposits for backing
        if (totalCollateralLenderCT == 0) {
            return false;
        }
        
        // Check 4: Basic liquidity check
        if (lenderOrders.length == 0) {
            return false;
        }

       if (maxAcceptableFlashLoanFeeBps < flashLoanFeeBps){
        return false;
       }
        
        return true;
    }

    /**
     * @notice Starts a new epoch, matching orders and managing funds.
     * @dev Validates epoch conditions, sets the redemption rate, and then calls `tryMatchOrders()` to match pending
     * lender and borrower orders. Any remaining unutilized lender funds are deposited into the flagship vault, and
     * the corresponding shares are distributed to the lenders.
     * @dev SAFETY: If flash loan conditions are unsafe, epoch starts but NO MATCHING occurs (funds stay withdrawable)
     */
    function startEpoch() external lock {
        // Validate epoch parameters
        if (
            lastEpochEnd + epochCoolDownPeriod > block.timestamp || epochStarted
                || deploymentTimestamp + 2 hours > block.timestamp
        ) {
            revert VaultLib.Unauthorized();
        }

        // Get current wstETH/stETH ratio and set rates
        uint256 redemptionRate = wsteth.stEthPerToken();
        epochStartRedemptionRate = redemptionRate;
        currentRedemptionRate = redemptionRate;
        currentBucketIndex = poolInfoUtils.priceToIndex(redemptionRate);

        // Update the rate
        (,,,,, uint256 liquidityRate, uint256 variableBorrowRate,,,,,) = poolDataProvider.getReserveData(VaultLib.QUOTE_TOKEN);
        rate = ((liquidityRate + variableBorrowRate) / 2);
        
        // Update state first
        epoch++;
        epochStarted = true;
        collateralLenderTraunche = 0;
        epochStart = block.timestamp;

        // Emit events before external calls
        emit VaultLib.EpochStarted(epoch, epochStart, epochStart + termDuration);
        emit VaultLib.RedemptionRateUpdated(redemptionRate);

        // SAFETY CHECK: Only match orders if flash loan conditions are safe
        // If Morpho introduces fees or conditions are unsafe, skip matching
        // This keeps all user funds in withdrawable state
        if (isFlashLoanSafe()) {
            // Perform external calls
            tryMatchOrders();
        } else {
            // Emit event explaining why matching was skipped
            emit EpochMatchingSkipped(epoch, "Flash loan conditions unsafe or insufficient liquidity");
            // Note: Users can still withdraw their orders since no matching occurred
        }

        // Deposit any remaining unmatched collateral lender deposits to Aave V3
        depositUnmatchedCLToAave();

        // Deposit any remaining unmatched lender deposits to Aave V3
        depositUnmatchedLendersToAave();
    }

    // PROXY FUNCTIONS
    /**
     * @notice Pushes a lender order to the lenderOrders array.
     * @dev Can only be called by the LVLidoVaultUtil or LiquidationProxy contract.
     * @param lenderOrder The lender order to push.
     */
    function lenderOrdersPush(VaultLib.LenderOrder memory lenderOrder) external onlyProxy {
        lenderOrders.push(lenderOrder);
    }

    /**
     * @notice Pushes a borrower order to the borrowerOrders array.
     * @dev Can only be called by the LVLidoVaultUtil or LiquidationProxy contract.
     * @param borrowerOrder The borrower order to push.
     */
    function borrowerOrdersPush(VaultLib.BorrowerOrder memory borrowerOrder) external onlyProxy {
        borrowerOrders.push(borrowerOrder);
    }

    /**
     * @notice Pushes a collateral lender order to the collateralLenderOrders array.
     * @dev Can only be called by the LVLidoVaultUtil or LiquidationProxy contract.
     * @param collateralLenderOrder The collateral lender order to push.
     */
    function collateralLenderOrdersPush(VaultLib.CollateralLenderOrder memory collateralLenderOrder)
        external
        onlyProxy
    {
        collateralLenderOrders.push(collateralLenderOrder);
    }

    /**
     * @notice Pushes a match info to the epochToMatches mapping.
     * @dev Can only be called by the LVLidoVaultUtil or LiquidationProxy contract.
     * @param epoch The epoch number.
     * @param matchInfo The match info to push.
     */
    function epochToMatchesPush(uint256 epoch, VaultLib.MatchInfo memory matchInfo) external onlyProxy {
        epochToMatches[epoch].push(matchInfo);
    }

    /**
     * @notice Pushes a collateral lender order to the epochToCollateralLenderOrders mapping.
     * @dev Can only be called by the LVLidoVaultUtil or LiquidationProxy contract.
     * @param epoch The epoch number.
     * @param collateralLenderOrder The collateral lender order to push.
     */
    function epochToCollateralLenderOrdersPush(
        uint256 epoch,
        VaultLib.CollateralLenderOrder memory collateralLenderOrder
    ) external onlyProxy {
        epochToCollateralLenderOrders[epoch].push(collateralLenderOrder);
    }

    /**
     * @notice Deletes the matches for a given epoch.
     * @dev Can only be called by the LVLidoVaultUtil or LiquidationProxy contract.
     * @param epoch The epoch number.
     */
    function deleteEpochMatches(uint256 epoch) external onlyProxy {
        delete epochToMatches[epoch];
    }

    /**
     * @notice Deletes the collateral lender orders for a given epoch.
     * @dev Can only be called by the LVLidoVaultUtil or LiquidationProxy contract.
     * @param epoch The epoch number.
     */
    function deleteEpochCollateralLenderOrders(uint256 epoch) external onlyProxy {
        delete epochToCollateralLenderOrders[epoch];
    }

    /**
     * @notice Approves a token for the proxy contract.
     * @dev Can only be called by the LVLidoVaultUtil or LiquidationProxy contract.
     * @param token The address of the token to approve.
     * @param receiver The address of the receiver.
     * @param amount The amount to approve.
     */
    function approveForProxy(address token, address receiver, uint256 amount) external onlyProxy returns (bool) {
        return IERC20(token).approve(receiver, amount);
    }

    /**
     * @notice Transfers a token on behalf of the proxy contract.
     * @dev Can only be called by the LVLidoVaultUtil or LiquidationProxy contract.
     * @param token The address of the token to transfer.
     * @param recipient The address of the recipient.
     * @param amount The amount to transfer.
     */
    function transferForProxy(address token, address recipient, uint256 amount) external onlyProxy returns (bool) {
        return IERC20(token).transfer(recipient, amount);
    }

    /**
     * @notice Requests withdrawals for WstETH from Lido protocol
     * @dev This function initiates the withdrawal process for wstETH tokens
     * @dev Only callable by the proxy contract (LVLidoVaultUtil or LiquidationProxy)
     * @dev Sets the global requestId to the first ID returned from the withdrawal request
     * @dev Marks funds as queued in the Lido withdrawal queue
     * @dev The withdrawal process in Lido is asynchronous - first request, then claim after finalization
     * @param amounts Array of wstETH amounts to withdraw from Lido protocol
     * @return requestId The ID of the first withdrawal request, used later for claiming
     */
    function requestWithdrawalsWstETH(uint256[] memory amounts) external onlyProxy returns (uint256) {
        uint256[] memory requestIds = VaultLib.LIDO_WITHDRAWAL.requestWithdrawalsWstETH(amounts, address(this));
        requestId = requestIds[0];
        fundsQueued = true;
        return requestId;
    }

    /**
     * @notice Claims a withdrawal from Lido protocol
     * @dev Can only be called by the LVLidoVaultUtil or LiquidationProxy contract.
     * @dev Uses the global requestId that was set during the requestWithdrawalsWstETH call
     * @dev This function should only be called after the Lido withdrawal request has been finalized
     * @dev After successful claim, the ETH will be sent to this contract's address
     */
    function claimWithdrawal() external onlyProxy {
        // Call Lido withdrawal contract to claim the finalized withdrawal using stored requestId
        VaultLib.LIDO_WITHDRAWAL.claimWithdrawal(requestId);
        // Note: After claiming, the contract will receive ETH which should be converted to WETH if needed
    }

    /**
     * @notice Deposits ETH for WETH.
     * @dev Can only be called by the LVLidoVaultUtil or LiquidationProxy contract.
     * @param amount The amount of ETH to deposit.
     */
    function depositEthForWeth(uint256 amount) external onlyProxy {
        IWeth(VaultLib.QUOTE_TOKEN).deposit{value: amount}();
    }

    /**
     * @notice Ends the current epoch.
     * @dev Can only be called by the LVLidoVaultUtil or LiquidationProxy contract.
     * @dev This function resets epoch state variables and prepares the vault for the next epoch.
     */
    function end_epoch() external onlyProxy {
        epochStarted = false;
        fundsQueued = false; // Reset withdrawal queue status
        lastEpochEnd = block.timestamp;

        emit VaultLib.EndEpoch(lastEpochEnd);
    }

    // ============================================================
    // Thin execution wrappers — logic moved to LVLidoVaultUtil (emergency)
    // and LVLidoVaultUpkeeper (epoch-close Aave withdrawal loops).
    // ============================================================

    /**
     * @notice Executes an Aave V3 withdrawal on behalf of a proxy caller.
     * @dev The vault holds aTokens, so only the vault can call aaveV3Pool.withdraw().
     */
    function executeAaveWithdraw(address token, uint256 amount) external onlyProxy lock returns (uint256) {
        return aaveV3Pool.withdraw(token, amount, address(this));
    }

    /**
     * @notice Sets a lender order's quoteAmount. Used by Upkeeper during epoch-close Aave restoration.
     */
    function setLenderOrderQuoteAmount(uint256 index, uint256 amount) external onlyProxy {
        lenderOrders[index].quoteAmount = amount;
    }

    /**
     * @notice Sets a CL order's collateralAmount. Used by Upkeeper during epoch-close Aave restoration.
     */
    function setCLOrderCollateralAmount(uint256 index, uint256 amount) external onlyProxy {
        collateralLenderOrders[index].collateralAmount = amount;
    }

    /**
     * @notice Sets a user's Aave lender deposit for a given epoch.
     */
    function setUserAaveLenderDeposit(address user, uint256 _epoch, uint256 amount) external onlyProxy {
        userAaveLenderDeposits[user][_epoch] = amount;
    }

    /**
     * @notice Sets a user's Aave CL deposit for a given epoch.
     */
    function setUserAaveCLDeposit(address user, uint256 _epoch, uint256 amount) external onlyProxy {
        userAaveCLDeposits[user][_epoch] = amount;
    }

    /**
     * @notice Batch setter for Aave lender accounting state.
     */
    function setAaveLenderState(uint256 _epoch, uint256 _totalDeposits, uint256 _epochDeposits) external onlyProxy {
        totalAaveLenderDeposits = _totalDeposits;
        epochToAaveLenderDeposits[_epoch] = _epochDeposits;
    }

    /**
     * @notice Batch setter for Aave CL accounting state.
     */
    function setAaveCLState(uint256 _epoch, uint256 _totalDeposits, uint256 _epochDeposits) external onlyProxy {
        totalAaveCLDeposits = _totalDeposits;
        epochToAaveCLDeposits[_epoch] = _epochDeposits;
    }

    /**
     * @notice Batch setter for emergency lender recovery state.
     */
    function setEmergencyLenderState(uint256 _epoch, bool _withdrawn, uint256 _principal, uint256 _claimable) external onlyProxy {
        epochEmergencyLenderWithdrawn[_epoch] = _withdrawn;
        epochEmergencyLenderPrincipalRemaining[_epoch] = _principal;
        epochEmergencyLenderClaimableRemaining[_epoch] = _claimable;
    }

    /**
     * @notice Batch setter for emergency CL recovery state.
     */
    function setEmergencyCLState(uint256 _epoch, bool _withdrawn, uint256 _principal, uint256 _claimable) external onlyProxy {
        epochEmergencyCLWithdrawn[_epoch] = _withdrawn;
        epochEmergencyCLPrincipalRemaining[_epoch] = _principal;
        epochEmergencyCLClaimableRemaining[_epoch] = _claimable;
    }

    /**
     * @notice Clears Ajna deposits.
     * @dev Can only be called by the LVLidoVaultUtil or LiquidationProxy contract.
     * @param amount The amount of quote token to remove.
     */
    function clearAjnaDeposits(uint256 amount) external onlyProxy lock {
        (uint256 removedAmount_,) = pool.removeQuoteToken(amount, currentBucketIndex);
        if (!testQuoteToken.burn(address(this), removedAmount_)) {
            revert VaultLib.TokenOperationFailed();
        }
    }

    /**
     * @notice Sets the total manual repay amount.
     * @dev Can only be called by the LVLidoVaultUtil or LiquidationProxy contract.
     * @param amount The total manual repay amount.
     */
    function setTotalManualRepay(uint256 amount) external onlyProxy {
        totalManualRepay = amount;
    }

    /**
     * @notice Adds collateral to avoid liquidation.
     * @dev Can only be called by the LVLidoVaultUtil or LiquidationProxy contract.
     * @dev Uses unutilized collateral lender deposits to increase position health.
     * @param amount The amount of collateral to add.
     */
    function avoidLiquidation(uint256 amount) external onlyProxy lock {
        // Check if we have enough unutilized collateral from lenders
        if (totalCLDepositsUnutilized < amount) revert VaultLib.InsufficientFunds();

        // Update state first
        totalCLDepositsUnutilized -= amount;
        totalCLDepositsUtilized += amount;

        // Emit event before external calls
        emit VaultLib.AvoidLiquidation(amount);

        // Perform external calls last
        if (!testCollateralToken.mint(address(this), amount) || !testCollateralToken.approve(address(pool), amount)) {
            revert VaultLib.TokenOperationFailed();
        }

        pool.drawDebt(address(this), 0, 7388, amount);
    }

    /**
     * @notice Sets the LVLidoVaultUtil address.
     * @dev Can only be called by the owner.
     * @param _LVLidoVaultUtil The new LVLidoVaultUtil address.
     */
    function setLVLidoVaultUtilAddress(address _LVLidoVaultUtil) public onlyOwner {
        emit VaultLib.LVLidoVaultUtilAddressUpdated(LVLidoVaultUtil, _LVLidoVaultUtil);
        LVLidoVaultUtil = _LVLidoVaultUtil;
    }

    /**
     * @notice Sets the LVLidoVaultUpkeeper contract address
     * @dev Can only be called by the owner
     * @param _LVLidoVaultUpkeeper The address of the LVLidoVaultUpkeeper contract
     */
    function setLVLidoVaultUpkeeperAddress(address _LVLidoVaultUpkeeper) public onlyOwner {
        require(_LVLidoVaultUpkeeper != address(0), "Invalid address");
        LVLidoVaultUpkeeper = _LVLidoVaultUpkeeper;
    }

    /**
     * @notice Minimal proxy setter for flash loan fee threshold (called by Util)
     * @dev Validation is done in LVLidoVaultUtil.setMaxFlashLoanFeeThreshold()
     */
    function setMaxFlashLoanFeeThresholdProxy(uint256 _maxFeeBps, uint256 _flashLoanFeeBps) external onlyProxy {
        uint256 oldThreshold = maxAcceptableFlashLoanFeeBps;
        maxAcceptableFlashLoanFeeBps = _maxFeeBps;
        flashLoanFeeBps = _flashLoanFeeBps;
        emit FlashLoanFeeThresholdUpdated(oldThreshold, _maxFeeBps);
    }
    
    // Note Anyone can call this function, ensure there are overflow protections in place.
    // Define range of values that can be entered in.
    /**
     * @notice Repays Ajna debt.
     * @param quoteTokenAmount The amount of quote token to repay.
     * @dev This function allows anyone to repay debt on behalf of the vault
     */
    function repayAjnaDebt(uint256 quoteTokenAmount) external lock {
        // Prevent zero-value transactions to save gas
        if (quoteTokenAmount == 0) {
            revert VaultLib.InvalidInput();
        }

        // Update state first
        totalManualRepay += quoteTokenAmount;

        // Perform external calls last
        if (
            !IERC20(VaultLib.QUOTE_TOKEN).transferFrom(msg.sender, address(this), quoteTokenAmount)
                || !testQuoteToken.mint(address(this), quoteTokenAmount)
                || !IERC20(address(testQuoteToken)).approve(address(pool), quoteTokenAmount)
        ) {
            revert VaultLib.TokenOperationFailed();
        }
        pool.repayDebt(address(this), quoteTokenAmount, 0, address(this), 7388);
    }

    /**
     * @notice Sets the total CL deposits unutilized.
     * @dev Can only be called by the LVLidoVaultUtil or LiquidationProxy contract.
     * @param _totalCLDepositsUnutilized The new total CL deposits unutilized.
     */
    function setTotalCLDepositsUnutilized(uint256 _totalCLDepositsUnutilized) external onlyProxy {
        totalCLDepositsUnutilized = _totalCLDepositsUnutilized;
    }

    /**
     * @notice Sets the total CL deposits utilized.
     * @dev Can only be called by the LVLidoVaultUtil or LiquidationProxy contract.
     * @param _totalCLDepositsUtilized The new total CL deposits utilized.
     */
    function setTotalCLDepositsUtilized(uint256 _totalCLDepositsUtilized) external onlyProxy {
        totalCLDepositsUtilized = _totalCLDepositsUtilized;
    }

    /**
     * @notice Sets the collateral lender traunche.
     * @dev Can only be called by the LVLidoVaultUtil or LiquidationProxy contract.
     * @param _collateralLenderTraunche The new collateral lender traunche.
     */
    function setCollateralLenderTraunche(uint256 _collateralLenderTraunche) external onlyProxy {
        collateralLenderTraunche = _collateralLenderTraunche;
    }

    /**
     * @notice Sets the current redemption rate.
     * @dev Can only be called by the LVLidoVaultUtil or LiquidationProxy contract.
     * @param _currentRedemptionRate The new current redemption rate.
     */
    function setCurrentRedemptionRate(uint256 _currentRedemptionRate) external onlyProxy {
        currentRedemptionRate = _currentRedemptionRate;
    }

    /**
     * @notice Mints tokens for the proxy contract.
     * @dev Can only be called by the LVLidoVaultUtil or LiquidationProxy contract.
     * @param token The address of the token to mint.
     * @param receiver The address of the receiver.
     * @param amount The amount to mint.
     */
    function mintForProxy(address token, address receiver, uint256 amount) external onlyProxy returns (bool) {
        if (token == address(testQuoteToken)) {
            return testQuoteToken.mint(receiver, amount);
        } else if (token == address(testCollateralToken)) {
            return testCollateralToken.mint(receiver, amount);
        }
    }

    /**
     * @notice Burns tokens for the proxy contract.
     * @dev Can only be called by the LVLidoVaultUtil or LiquidationProxy contract.
     * @param token The address of the token to burn.
     * @param receiver The address of the receiver.
     * @param amount The amount to burn.
     */
    function burnForProxy(address token, address receiver, uint256 amount) external onlyProxy returns (bool) {
        if (token == address(testQuoteToken)) {
            return testQuoteToken.burn(receiver, amount);
        } else if (token == address(testCollateralToken)) {
            return testCollateralToken.burn(receiver, amount);
        }
    }

    /**
     * @notice Repays debt for the proxy contract.
     * @dev Can only be called by the LVLidoVaultUtil or LiquidationProxy contract.
     * @param debt The amount of debt to repay.
     * @param collateral The amount of collateral to repay.
     */
    function repayDebtForProxy(uint256 debt, uint256 collateral) external onlyProxy {
        pool.repayDebt(address(this), debt, collateral, address(this), 7388);
    }

    /**
     * @notice Sets the total lender QT unutilized.
     * @dev Can only be called by the LVLidoVaultUtil or LiquidationProxy contract.
     * @param _totalLenderQTUnutilized The new total lender QT unutilized.
     */
    function setTotalLenderQTUnutilized(uint256 _totalLenderQTUnutilized) external onlyProxy {
        totalLenderQTUnutilized = _totalLenderQTUnutilized;
    }

    /**
     * @notice Sets the total lender QT utilized.
     * @dev Can only be called by the LVLidoVaultUtil or LiquidationProxy contract.
     * @param _totalLenderQTUtilized The new total lender QT utilized.
     */
    function setTotalLenderQTUtilized(uint256 _totalLenderQTUtilized) external onlyProxy {
        totalLenderQTUtilized = _totalLenderQTUtilized;
    }

    /**
     * @notice Sets the total borrower CT.
     * @dev Can only be called by the LVLidoVaultUtil or LiquidationProxy contract.
     * @param _totalBorrowerCT The new total borrower CT.
     */
    function setTotalBorrowerCT(uint256 _totalBorrowerCT) external onlyProxy {
        totalBorrowerCT = _totalBorrowerCT;
    }

    /**
     * @notice Sets the total borrower CT unutilized.
     * @dev Can only be called by the LVLidoVaultUtil or LiquidationProxy contract.
     * @param _totalBorrowerCTUnutilized The new total borrower CT unutilized.
     */
    function setTotalBorrowerCTUnutilized(uint256 _totalBorrowerCTUnutilized) external onlyProxy {
        totalBorrowerCTUnutilized = _totalBorrowerCTUnutilized;
    }

    /**
     * @notice Sets the total collateral lender CT.
     * @dev Can only be called by the LVLidoVaultUtil or LiquidationProxy contract.
     * @param _totalCollateralLenderCT The new total collateral lender CT.
     */
    function setTotalCollateralLenderCT(uint256 _totalCollateralLenderCT) external onlyProxy {
        totalCollateralLenderCT = _totalCollateralLenderCT;
    }


    // ORDER CREATION AND WITHDRAWAL FUNCTIONS
    /**
     * @notice Creates a lender order.
     * @param amount The amount of quote token (WETH) to lend.
     * @return The amount of quote token lent.
     * @dev This function allows users to deposit quote tokens (WETH) into the vault
     * @dev The deposited tokens are tracked as unutilized until they are matched with borrower orders
     * @dev or deposited into the flagship vault during epoch start
     */
    function createLenderOrder(uint256 amount) external lock returns (uint256) {
        // Anti-DoS: enforce minimum order size
        if (amount < MIN_ORDER_SIZE) revert OrderBelowMinimum(amount, MIN_ORDER_SIZE);
        // Anti-DoS: enforce max orders per user
        if (userActiveOrderCount[msg.sender] >= MAX_ORDERS_PER_USER) {
            revert MaxOrdersExceeded(msg.sender, userActiveOrderCount[msg.sender], MAX_ORDERS_PER_USER);
        }
        // Anti-DoS: enforce global order cap to bound epoch matching gas
        if (lenderOrders.length + borrowerOrders.length + collateralLenderOrders.length >= MAX_ORDERS_PER_EPOCH) {
            revert EpochOrderCapReached();
        }
        userActiveOrderCount[msg.sender]++;

        lenderOrders.push(VaultLib.LenderOrder({lender: msg.sender, quoteAmount: amount, vaultShares: 0}));
        totalLenderQTUnutilized += amount;

        emit VaultLib.LenderOrderAdded(msg.sender, amount);

        if (!IERC20(VaultLib.QUOTE_TOKEN).transferFrom(address(msg.sender), address(this), amount)) {
            revert VaultLib.TokenOperationFailed();
        }

        // If epoch is active, deposit to Aave immediately for interest accrual.
        // Order amount is zeroed — restored at epoch close with principal + interest.
        if (epochStarted) {
            userAaveLenderDeposits[msg.sender][epoch] += amount;
            totalAaveLenderDeposits += amount;
            epochToAaveLenderDeposits[epoch] += amount;

            lenderOrders[lenderOrders.length - 1].quoteAmount = 0;

            // Decrement totalLenderQTUnutilized since funds going to Aave
            totalLenderQTUnutilized -= amount;

            if (!IERC20(VaultLib.QUOTE_TOKEN).approve(address(aaveV3Pool), amount)) {
                revert VaultLib.TokenOperationFailed();
            }
            aaveV3Pool.supply(VaultLib.QUOTE_TOKEN, amount, address(this), 0);

            emit AaveLenderDeposited(epoch, amount, 1);
        }

        return amount;
    }

    /**
     * @notice Creates a new borrower order with the specified collateral amount
     * @dev Transfers collateral from the user to the vault and adds a new borrower order
     * @param collateralAmount The amount of collateral to deposit for the order
     * @return The amount of collateral deposited
     */
    function createBorrowerOrder(uint256 collateralAmount) external lock returns (uint256) {
        // Anti-DoS: enforce minimum order size
        if (collateralAmount < MIN_ORDER_SIZE) revert OrderBelowMinimum(collateralAmount, MIN_ORDER_SIZE);
        // Anti-DoS: enforce max orders per user
        if (userActiveOrderCount[msg.sender] >= MAX_ORDERS_PER_USER) {
            revert MaxOrdersExceeded(msg.sender, userActiveOrderCount[msg.sender], MAX_ORDERS_PER_USER);
        }
        // Anti-DoS: enforce global order cap to bound epoch matching gas
        if (lenderOrders.length + borrowerOrders.length + collateralLenderOrders.length >= MAX_ORDERS_PER_EPOCH) {
            revert EpochOrderCapReached();
        }
        userActiveOrderCount[msg.sender]++;

        totalBorrowerCT += collateralAmount;
        totalBorrowerCTUnutilized += collateralAmount;
        borrowerOrders.push(VaultLib.BorrowerOrder({borrower: msg.sender, collateralAmount: collateralAmount}));

        // Emit event before external call
        emit VaultLib.BorrowerOrderAdded(msg.sender, collateralAmount);

        // Perform external call last
        if (!IERC20(VaultLib.COLLATERAL_TOKEN).transferFrom(msg.sender, address(this), collateralAmount)) {
            revert VaultLib.TokenOperationFailed();
        }

        return collateralAmount;
    }

    /**
     * @notice Lends collateral as a collateral lender.
     * @param amount The amount of collateral to lend.
     * @return The amount of collateral lent.
     * @dev This function allows users to deposit collateral tokens (wstETH) to be used as additional
     * @dev collateral for borrowers, helping to maintain healthy collateralization ratios and
     * @dev potentially preventing liquidations. Collateral lenders earn fees from this service.
     */
    function createCLOrder(uint256 amount) external lock returns (uint256) {
        // Anti-DoS: enforce minimum order size
        if (amount < MIN_ORDER_SIZE) revert OrderBelowMinimum(amount, MIN_ORDER_SIZE);
        // Anti-DoS: enforce max orders per user
        if (userActiveOrderCount[msg.sender] >= MAX_ORDERS_PER_USER) {
            revert MaxOrdersExceeded(msg.sender, userActiveOrderCount[msg.sender], MAX_ORDERS_PER_USER);
        }
        // Anti-DoS: enforce global order cap to bound epoch matching gas
        if (lenderOrders.length + borrowerOrders.length + collateralLenderOrders.length >= MAX_ORDERS_PER_EPOCH) {
            revert EpochOrderCapReached();
        }
        userActiveOrderCount[msg.sender]++;

        totalCollateralLenderCT += amount;
        collateralLenderOrders.push(VaultLib.CollateralLenderOrder(msg.sender, amount));

        emit VaultLib.CollateralLenderDeposit(msg.sender, amount);

        if (!IERC20(VaultLib.COLLATERAL_TOKEN).transferFrom(msg.sender, address(this), amount)) {
            revert VaultLib.TokenOperationFailed();
        }

        // If epoch is active, deposit to Aave immediately for interest accrual.
        // Order amount is zeroed — restored at epoch close with principal + interest.
        if (epochStarted) {
            userAaveCLDeposits[msg.sender][epoch] += amount;
            totalAaveCLDeposits += amount;
            epochToAaveCLDeposits[epoch] += amount;

            collateralLenderOrders[collateralLenderOrders.length - 1].collateralAmount = 0;

            // Decrement totalCollateralLenderCT since funds going to Aave
            // (prevents phantom collateral - totalAaveCLDeposits tracks Aave portion)
            totalCollateralLenderCT -= amount;

            if (!IERC20(VaultLib.COLLATERAL_TOKEN).approve(address(aaveV3Pool), amount)) {
                revert VaultLib.TokenOperationFailed();
            }
            aaveV3Pool.supply(VaultLib.COLLATERAL_TOKEN, amount, address(this), 0);

            emit AaveCLDeposited(epoch, amount, 1);
        }

        return amount;
    }

    /**
     * @notice Withdraws a lender order.
     * @dev This function allows lenders to withdraw their unutilized funds from the vault.
       * @dev Handles withdrawals from both local vault and Aave V3 deposits
     * @dev Uses a swap-and-pop pattern to efficiently remove orders from the array.
     * @return The total amount of quote tokens withdrawn.
     */
   function withdrawLenderOrder() external lock returns (uint256) {
        uint256 userWithdrawalAmount = 0;
        uint256 userPrincipalAmount = 0;
        uint256 ordersRemoved = 0;
        bool aaveWithdrawn = false;

        // Find and collect all orders from this lender
        for (uint256 i = 0; i < lenderOrders.length;) {
            if (lenderOrders[i].lender == msg.sender) {
                ordersRemoved++;
                uint256 orderAmount = lenderOrders[i].quoteAmount;
                userWithdrawalAmount += orderAmount;
                userPrincipalAmount += orderAmount;

                // Check if this order has funds in Aave for the CURRENT epoch only
                uint256 userCurrentEpochAaveDeposit = userAaveLenderDeposits[msg.sender][epoch];

                // If user has Aave deposits in current epoch, withdraw from Aave (once per user)
                if (userCurrentEpochAaveDeposit > 0 && !aaveWithdrawn) {
                    aaveWithdrawn = true;
                    // Get current aToken balance to calculate proportional share including interest
                    uint256 currentAaveBalance = getAaveBalanceQuote();

                    // Calculate user's proportional share of current balance (includes interest)
                    uint256 amountToWithdraw;
                    if (totalAaveLenderDeposits > 0) {
                        amountToWithdraw = (userCurrentEpochAaveDeposit * currentAaveBalance) / totalAaveLenderDeposits;
                    } else {
                        amountToWithdraw = userCurrentEpochAaveDeposit;
                    }

                    // Withdraw from Aave V3 Pool (burns aWETH, receives WETH with interest)
                    uint256 withdrawnFromAave = aaveV3Pool.withdraw(
                        VaultLib.QUOTE_TOKEN,
                        amountToWithdraw,
                        address(this)
                    );

                    // Add FULL Aave withdrawal (principal + interest) since order was zeroed
                    // NOTE: Do NOT add to userPrincipalAmount — totalLenderQTUnutilized was
                    // already decremented when funds went to Aave (in depositUnmatchedLendersToAave
                    // or createLenderOrder mid-epoch)
                    userWithdrawalAmount += withdrawnFromAave;

                    // Update Aave tracking
                    totalAaveLenderDeposits -= userCurrentEpochAaveDeposit;
                    epochToAaveLenderDeposits[epoch] -= userCurrentEpochAaveDeposit;
                    userAaveLenderDeposits[msg.sender][epoch] = 0;

                    emit AaveLenderWithdrawn(msg.sender, withdrawnFromAave, epoch);
                }

                // Swap with last element and pop (more gas efficient than shifting elements)
                if (i < lenderOrders.length - 1) {
                    lenderOrders[i] = lenderOrders[lenderOrders.length - 1];
                }
                lenderOrders.pop();
            } else {
                i++;
            }
        }

        if (userWithdrawalAmount == 0) {
            revert VaultLib.NoUnfilledOrdersFound();
        }

        // Update state - only subtract principal, not interest
        totalLenderQTUnutilized -= userPrincipalAmount;

        // Decrement user's active order count
        if (userActiveOrderCount[msg.sender] >= ordersRemoved) {
            userActiveOrderCount[msg.sender] -= ordersRemoved;
        } else {
            userActiveOrderCount[msg.sender] = 0;
        }

        // Emit event before any external calls
        emit VaultLib.WithdrawLender(msg.sender, userWithdrawalAmount);

        // Transfer all withdrawn funds to user (principal + interest)
        if (!IERC20(VaultLib.QUOTE_TOKEN).transfer(msg.sender, userWithdrawalAmount)) {
            revert VaultLib.TokenOperationFailed();
        }

        return userWithdrawalAmount;
    }

    /**
     * @notice Withdraws a borrower order.
     * @dev This function allows borrowers to withdraw their unutilized collateral from pending orders
     * @dev Uses a gas-efficient removal pattern (swap with last element and pop)
     * @dev Updates global accounting for borrower collateral tracking
     * @return The total amount of collateral tokens withdrawn.
     */
    function withdrawBorrowerOrder() external lock returns (uint256) {
        uint256 userWithdrawalAmount = 0;
        uint256 ordersRemoved = 0;
        for (uint256 i = 0; i < borrowerOrders.length;) {
            if (borrowerOrders[i].borrower == msg.sender) {
                ordersRemoved++;
                userWithdrawalAmount += borrowerOrders[i].collateralAmount;
                if (i < borrowerOrders.length - 1) {
                    borrowerOrders[i] = borrowerOrders[borrowerOrders.length - 1];
                }
                borrowerOrders.pop();
            } else {
                i++;
            }
        }

        if (userWithdrawalAmount == 0) {
            revert VaultLib.NoUnfilledOrdersFound();
        }

        totalBorrowerCT -= userWithdrawalAmount;
        totalBorrowerCTUnutilized -= userWithdrawalAmount;

        // Decrement user's active order count
        if (userActiveOrderCount[msg.sender] >= ordersRemoved) {
            userActiveOrderCount[msg.sender] -= ordersRemoved;
        } else {
            userActiveOrderCount[msg.sender] = 0;
        }

        emit VaultLib.WithdrawBorrower(msg.sender, userWithdrawalAmount);
        if (!IERC20(VaultLib.COLLATERAL_TOKEN).transfer(msg.sender, userWithdrawalAmount)) {
            revert VaultLib.TokenOperationFailed();
        }

        return userWithdrawalAmount;
    }

    /**
     * @notice Withdraws a collateral lender order.
     * @dev Allows collateral lenders to withdraw their unutilized collateral tokens (wstETH)
    * @dev Handles withdrawals from both local vault and Aave V3 deposits
     * @dev For past epochs: funds already redistributed from Aave back to collateralLenderOrders
     * @dev For current epoch: may need to withdraw from Aave if funds were deposited there
     * @dev Finds and aggregates all orders from the caller, then removes them from the array
     * @dev Updates global accounting and transfers tokens back to the lender
     * @dev Protected by the lock modifier to prevent reentrancy attacks
     * @return The total amount of collateral withdrawn
     */
   function withdrawCLOrder() external lock returns (uint256) {
        uint256 userWithdrawalAmount = 0;
        uint256 userPrincipalAmount = 0;
        uint256 ordersRemoved = 0;
        bool aaveWithdrawn = false;

        // Step 1: Collect from local collateralLenderOrders array
        // This includes:
        // - Orders not yet matched (from current or past epochs)
        // - Orders redistributed from past epochs (with interest)
        for (uint256 i = 0; i < collateralLenderOrders.length;) {
            if (collateralLenderOrders[i].collateralLender == msg.sender) {
                ordersRemoved++;
                uint256 orderAmount = collateralLenderOrders[i].collateralAmount;
                userWithdrawalAmount += orderAmount;
                userPrincipalAmount += orderAmount;
                
                // Check if this order has funds in Aave for the CURRENT epoch only
                // (Past epochs already had their Aave funds withdrawn and redistributed)
                uint256 userCurrentEpochAaveDeposit = userAaveCLDeposits[msg.sender][epoch];

                // If user has Aave deposits in current epoch, withdraw from Aave (once per user)
                if (userCurrentEpochAaveDeposit > 0 && !aaveWithdrawn) {
                    aaveWithdrawn = true;
                    // Get current aToken balance to calculate proportional share including interest
                    uint256 currentAaveBalance = getAaveBalance();

                    // Calculate user's proportional share of current balance (includes interest)
                    uint256 amountToWithdraw;
                    if (totalAaveCLDeposits > 0) {
                        amountToWithdraw = (userCurrentEpochAaveDeposit * currentAaveBalance) / totalAaveCLDeposits;
                    } else {
                        amountToWithdraw = userCurrentEpochAaveDeposit;
                    }

                    // Withdraw from Aave V3 Pool (burns awstETH, receives wstETH with interest)
                    uint256 withdrawnFromAave = aaveV3Pool.withdraw(
                        VaultLib.COLLATERAL_TOKEN,
                        amountToWithdraw,
                        address(this)
                    );

                    // Add FULL Aave withdrawal (principal + interest) since order was zeroed
                    userWithdrawalAmount += withdrawnFromAave;
                    // NOTE: Do NOT add to userPrincipalAmount — totalCollateralLenderCT was
                    // already decremented when funds went to Aave (in createCLOrder)

                    // Update Aave tracking
                    totalAaveCLDeposits -= userCurrentEpochAaveDeposit;
                    epochToAaveCLDeposits[epoch] -= userCurrentEpochAaveDeposit;
                    userAaveCLDeposits[msg.sender][epoch] = 0;

                    emit AaveCLWithdrawn(msg.sender, withdrawnFromAave, epoch);
                }
                
                // Remove order from array (swap with last and pop)
                if (i < collateralLenderOrders.length - 1) {
                    collateralLenderOrders[i] = collateralLenderOrders[collateralLenderOrders.length - 1];
                }
                collateralLenderOrders.pop();
                // Don't increment i since we swapped with last element
            } else {
                i++;
            }
        }
        
        // Ensure user has something to withdraw
        if (userWithdrawalAmount == 0) {
            revert VaultLib.NoUnfilledOrdersFound();
        }

        // Update global collateral lender total - only subtract principal, not interest
        totalCollateralLenderCT -= userPrincipalAmount;

        // Keep totalCLDepositsUnutilized consistent so avoidLiquidation() doesn't overcount.
        // Clamp to avoid underflow if CL was deposited mid-epoch (not part of epoch-start pool).
        if (userPrincipalAmount <= totalCLDepositsUnutilized) {
            totalCLDepositsUnutilized -= userPrincipalAmount;
        } else {
            totalCLDepositsUnutilized = 0;
        }

        // Decrement user's active order count
        if (userActiveOrderCount[msg.sender] >= ordersRemoved) {
            userActiveOrderCount[msg.sender] -= ordersRemoved;
        } else {
            userActiveOrderCount[msg.sender] = 0;
        }

        emit VaultLib.WithdrawCollateralLender(msg.sender, userWithdrawalAmount);
        
        // Transfer all withdrawn funds to user (principal + interest)
        if (!IERC20(VaultLib.COLLATERAL_TOKEN).transfer(msg.sender, userWithdrawalAmount)) {
            revert VaultLib.TokenOperationFailed();
        }

        return userWithdrawalAmount;
    }
    // AUCTION BASED FUNCTIONS
    /**
     * @notice Sets whether kicking is allowed.
     * @dev Can only be called by the LVLidoVaultUtil or LiquidationProxy contract.
     * @param _allowKick Whether kicking is allowed.
     */
    function setAllowKick(bool _allowKick) external onlyProxy {
        liquidationProxy.setAllowKick(_allowKick);
    }

    function getAllowKick() external view returns (bool) {
        return liquidationProxy.allowKick();
    }

    function lenderKick(uint256 bondAmount) external onlyProxy {
        if (
            !(
                liquidationProxy.allowKick() == true && testQuoteToken.mint(address(this), bondAmount)
                    && IERC20(address(testQuoteToken)).approve(address(pool), bondAmount)
            )
        ) {
            revert VaultLib.TokenOperationFailed();
        }

        pool.lenderKick(currentBucketIndex, 7388);
    }

    function withdrawBondsForProxy() external onlyProxy returns (uint256) {
        (uint256 claimable, uint256 locked) = pool.kickerInfo(address(this));
        if (locked != 0) {
            revert VaultLib.LockedBonds();
        }
        return pool.withdrawBonds(address(this), claimable);
    }


    function updateRate(uint256 _rate) external onlyProxy {

        if(_rate > 0) {
            rate = _rate;
        } else {
            (,,,,, uint256 liquidityRate, uint256 variableBorrowRate,,,,,) = poolDataProvider.getReserveData(VaultLib.QUOTE_TOKEN);
            rate = ((liquidityRate + variableBorrowRate) / 2);
        }

        emit RateUpdated(rate);
    }
        
    
}
