// SPDX-License-Identifier: BUSL-1.1
// Author: Lendvest

pragma solidity ^0.8.20;

import {ILVLidoVault} from "./interfaces/ILVLidoVault.sol";
import {LVLidoVaultUpkeeper} from "./LVLidoVaultUpkeeper.sol";
import {AutomationCompatibleInterface} from "@chainlink/contracts/src/v0.8/automation/AutomationCompatible.sol";
import {FunctionsClient} from "@chainlink/contracts/src/v0.8/functions/v1_0_0/FunctionsClient.sol";
import {FunctionsRequest} from "@chainlink/contracts/src/v0.8/functions/v1_0_0/libraries/FunctionsRequest.sol";
import {IWsteth} from "./interfaces/vault/IWsteth.sol";
import {VaultLib} from "./libraries/VaultLib.sol";
import {IPoolInfoUtils} from "./interfaces/IPoolInfoUtils.sol";
import {IERC20Pool} from "./interfaces/pool/erc20/IERC20Pool.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IWeth} from "./interfaces/vault/IWeth.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract LVLidoVaultUtil is AutomationCompatibleInterface, Ownable, FunctionsClient {
    using FunctionsRequest for FunctionsRequest.Request;

    ILVLidoVault public LVLidoVault;
    LVLidoVaultUpkeeper public lvLidoVaultUpkeeper;
    IPoolInfoUtils public constant poolInfoUtils = IPoolInfoUtils(0x30c5eF2997d6a882DE52c4ec01B6D0a5e5B4fAAE);
    uint256 stEthPerToken = IWsteth(address(VaultLib.COLLATERAL_TOKEN)).stEthPerToken();
    AggregatorV3Interface internal stethUsdPriceFeed;
    AggregatorV3Interface internal ethUsdPriceFeed;
    uint8 public constant PRICE_FEED_DECIMALS = 8;
    // Each top-up tranche is triggered after an additional ≈1.1 % market draw-down
    // (1 / leverageFactor when leverageFactor≈15). Three tranches correspond to
    // 1.11 %, 2.22 %, 3.33 % cumulative price moves, after which liquidation may be allowed.
    uint256 public constant FACTOR_COLLATERAL_INCREASE = 11e15; // 1.1 %
    // Exactly three collateral-lender tranches; when the counter reaches 3 we switch to allowKick.
    uint256 public constant MAX_TRANCHES = 3;
    uint256 public constant lidoClaimDelay = 7 days;
    uint256 public constant PRICE_STALENESS_THRESHOLD = 1 hours;

    error StalePrice(uint256 updatedAt, uint256 currentTime);
    error InvalidPrice(int256 price);

    // Rate is set by the LVLidoVault contract
    uint256 public upperBoundRate = 0;
    uint256 public lowerBoundRate = 0;

    bool public updateRateNeeded = true;
    uint256 public s_lastUpkeepTimeStamp;
    uint256 public s_requestCounter;
    uint64 public s_subscriptionId;
    uint32 public s_fulfillGasLimit;
    bytes32 public s_lastRequestId;
    bytes public s_requestCBOR;
    bytes public s_lastResponse;
    bytes public s_lastError;
    address public s_forwarderAddress;

    constructor(address _LVLidoVault) Ownable(msg.sender) FunctionsClient(VaultLib.router) {
        LVLidoVault = ILVLidoVault(_LVLidoVault);
        stethUsdPriceFeed = AggregatorV3Interface(0xCfE54B5cD566aB89272946F602D76Ea879CAb4a8);
        ethUsdPriceFeed = AggregatorV3Interface(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419);
        // Set rate bounds: 0.5% to 10% (in 1e18 scale)
        lowerBoundRate = 5e15; // 0.5%
        upperBoundRate = 1e17; // 10%
    }

    modifier onlyForwarder() {
        if (msg.sender != s_forwarderAddress && msg.sender != address(this)) {
            revert VaultLib.OnlyForwarder();
        }
        _;
    }

    modifier onlyLVLidoVault() {
        if (msg.sender != address(LVLidoVault)) {
            revert VaultLib.Unauthorized();
        }
        _;
    }

    function getWstethToWeth(uint256 _amount) public view returns (uint256) {
        // WSTETH -> STETH -> USD -> ETH -> USD -> WETH
        (, int256 stethPrice,,uint256 stethUpdatedAt,) = stethUsdPriceFeed.latestRoundData();
        if (block.timestamp - stethUpdatedAt > PRICE_STALENESS_THRESHOLD) {
            revert StalePrice(stethUpdatedAt, block.timestamp);
        }
        if (stethPrice <= 0) {
            revert InvalidPrice(stethPrice);
        }

        uint256 stethAmount = _amount * IWsteth(VaultLib.COLLATERAL_TOKEN).stEthPerToken() / 1e18;
        // STETH -> USD
        uint256 stethValueScaled = stethAmount * uint256(stethPrice);

        // USD -> ETH = WETH
        (, int256 ethPrice,,uint256 ethUpdatedAt,) = ethUsdPriceFeed.latestRoundData();
        if (block.timestamp - ethUpdatedAt > PRICE_STALENESS_THRESHOLD) {
            revert StalePrice(ethUpdatedAt, block.timestamp);
        }
        if (ethPrice <= 0) {
            revert InvalidPrice(ethPrice);
        }

        return stethValueScaled / uint256(ethPrice);
    }

    function checkUpkeep(bytes calldata) public view override returns (bool upkeepNeeded, bytes memory performData) {
        // Get the rate for the term if it has passed and auction hasn't happened (Ajna debt 0)
        IERC20Pool pool = LVLidoVault.pool();
        (uint256 debt,,,) = poolInfoUtils.borrowerInfo(address(pool), address(LVLidoVault));
        if (updateRateNeeded && block.timestamp > (LVLidoVault.epochStart() + LVLidoVault.termDuration()) && debt > 0) {
            upkeepNeeded = true;
            performData = abi.encode(221); // Task ID 221: Get new rate
            return (upkeepNeeded, performData);
        }

        // If no epoch has started yet or currentRedemptionRate is 0, no upkeep needed
        uint256 currentRedemptionRate = LVLidoVault.currentRedemptionRate();
        if (currentRedemptionRate == 0) {
            return (false, performData);
        }

        // Calculate the market rate rather than the redemption rate

        uint256 newRedemptionRate = getWstethToWeth(1e18);

        int256 percentageDifferenceRedemptionRate = (
            (int256(newRedemptionRate) - int256(currentRedemptionRate)) * 1e18
        ) / int256(currentRedemptionRate); // Drawdown percentage

        int256 currentThreshold = LVLidoVault.priceDifferencethreshold()
            - int256(FACTOR_COLLATERAL_INCREASE * LVLidoVault.collateralLenderTraunche()); // -1% - 33% * tranche_num

        if (
            LVLidoVault.epochStarted() && block.timestamp < (LVLidoVault.epochStart() + LVLidoVault.termDuration())
                && debt > 0
        ) {
            uint256 tranchesToTrigger = 0;
            int256 checkThreshold = LVLidoVault.priceDifferencethreshold(); // -1%
            uint256 collateralLenderTraunche = LVLidoVault.collateralLenderTraunche();
            while (
                percentageDifferenceRedemptionRate < checkThreshold
                    && tranchesToTrigger + collateralLenderTraunche < MAX_TRANCHES
            ) {
                tranchesToTrigger++;
                // -1% - 33% * (0 + 1) = -34%
                // -1% - 33% * (0 + 2) = -67%
                // -1% - 33% * (0 + 3) = -100%
                checkThreshold = LVLidoVault.priceDifferencethreshold()
                    - int256(FACTOR_COLLATERAL_INCREASE * (collateralLenderTraunche + tranchesToTrigger));
            }

            uint256 totalCLDepositsUnutilized = LVLidoVault.totalCLDepositsUnutilized();
            if (
                tranchesToTrigger > 0 && tranchesToTrigger + collateralLenderTraunche <= MAX_TRANCHES
                    && totalCLDepositsUnutilized > 0
            ) {
                // Equal-sized tranche approach: add 1/N of remaining protector funds
                uint256 remainingTranches = MAX_TRANCHES - collateralLenderTraunche;
                if (remainingTranches == 0) remainingTranches = 1;
                uint256 collateralToAddToPreventLiquidation =
                    LVLidoVault.totalCLDepositsUnutilized() / remainingTranches;

                if (collateralToAddToPreventLiquidation > 0) {
                    upkeepNeeded = true;
                    performData = abi.encode(0); // Task ID 0: Add collateral (Avoid Liquidation)
                    return (upkeepNeeded, performData);
                }
            } else if (tranchesToTrigger + collateralLenderTraunche >= MAX_TRANCHES) {
                upkeepNeeded = true;
                performData = abi.encode(3); // Task ID 3: Allow kick
                return (upkeepNeeded, performData);
            }
        } else if (
            LVLidoVault.epochStarted() && block.timestamp > (LVLidoVault.epochStart() + LVLidoVault.termDuration())
                && LVLidoVault.getAllowKick() == false
        ) {
            if (debt == 0) {
                return (true, abi.encode(2)); // Auction happened and debt was cleared, queue task ID 2
            } else if (!LVLidoVault.fundsQueued()) {
                // See if Ajna debt is 0 or not
                (uint256 currentDebt,,,) = poolInfoUtils.borrowerInfo(address(LVLidoVault.pool()), address(LVLidoVault));
                if (currentDebt == 0) {
                    upkeepNeeded = true;
                    performData = abi.encode(2); // Task ID 2: Withdraw funds
                    return (upkeepNeeded, performData);
                }
                upkeepNeeded = true;
                performData = abi.encode(1); // Task ID 1: End term and queue funds
                return (upkeepNeeded, performData);
            } else {
                // Determine how much ETH can be claimed
                uint256 firstIndex = 1;
                uint256 lastIndex = VaultLib.LIDO_WITHDRAWAL.getLastCheckpointIndex();
                uint256[] memory requestIds = new uint256[](1);
                requestIds[0] = LVLidoVault.requestId();
                uint256[] memory hints = VaultLib.LIDO_WITHDRAWAL.findCheckpointHints(requestIds, firstIndex, lastIndex);
                uint256[] memory claimableEthValues = VaultLib.LIDO_WITHDRAWAL.getClaimableEther(requestIds, hints);
                uint256 amount = claimableEthValues[0];

                if (amount > 0) {
                    upkeepNeeded = true;
                    performData = abi.encode(2); // Task ID 2: Withdraw funds
                    return (upkeepNeeded, performData);
                }
            }
        }
        upkeepNeeded = false;
        performData = "";
        return (upkeepNeeded, performData);
    }

    function performUpkeep(bytes calldata performData) public override onlyForwarder {
        if (performData.length == 0) revert VaultLib.InvalidInput();
        uint256 taskId = abi.decode(performData, (uint256));
        IERC20Pool pool = LVLidoVault.pool();
        (uint256 t1Debt,,,) = poolInfoUtils.borrowerInfo(address(pool), address(LVLidoVault));
        if (taskId == 221 && updateRateNeeded && t1Debt > 0) {
            getRate();
            emit VaultLib.TermEnded(LVLidoVault.epochStart() + LVLidoVault.termDuration());
            return;
        }
        (uint256 t0Debt, uint256 collateral,) = pool.borrowerInfo(address(LVLidoVault));

        // Add collateral to Ajna pool; Logic for Avoid Liquidations
        // Only proceed if we're in an active epoch
        if (
            LVLidoVault.epochStarted() && block.timestamp < (LVLidoVault.epochStart() + LVLidoVault.termDuration())
                && t1Debt > 0
        ) {
            uint256 newRedemptionRate = getWstethToWeth(1e18);

            // Calculate price change as percentage
            int256 percentageDifferenceRedemptionRate = (
                (int256(newRedemptionRate) - int256(LVLidoVault.currentRedemptionRate())) * 1e18
            ) / int256(LVLidoVault.currentRedemptionRate());

            // Calculate how many tranches should be triggered
            uint256 tranchesToTrigger = 0;
            int256 checkThreshold = LVLidoVault.priceDifferencethreshold();

            // Count how many thresholds have been crossed
            // -20% < -1% && 0 +
            while (
                percentageDifferenceRedemptionRate < checkThreshold
                    && tranchesToTrigger + LVLidoVault.collateralLenderTraunche() < MAX_TRANCHES
            ) {
                tranchesToTrigger++;
                checkThreshold = LVLidoVault.priceDifferencethreshold()
                    - int256(FACTOR_COLLATERAL_INCREASE * (LVLidoVault.collateralLenderTraunche() + tranchesToTrigger));
            }
            if (
                tranchesToTrigger > 0 && tranchesToTrigger + LVLidoVault.collateralLenderTraunche() <= MAX_TRANCHES
                    && LVLidoVault.totalCLDepositsUnutilized() > 0
            ) {
                // Equal-sized tranche approach: add 1/N of remaining protector funds
                uint256 remainingTranches = MAX_TRANCHES - LVLidoVault.collateralLenderTraunche();
                if (remainingTranches == 0) remainingTranches = 1;
                uint256 collateralToAddToPreventLiquidation =
                    LVLidoVault.totalCLDepositsUnutilized() / remainingTranches;

                if (collateralToAddToPreventLiquidation > 0) {
                    LVLidoVault.avoidLiquidation(collateralToAddToPreventLiquidation);
                    LVLidoVault.setCollateralLenderTraunche(LVLidoVault.collateralLenderTraunche() + tranchesToTrigger);
                    LVLidoVault.setCurrentRedemptionRate(newRedemptionRate);
                }
            } else if (tranchesToTrigger + LVLidoVault.collateralLenderTraunche() >= MAX_TRANCHES) {
                LVLidoVault.setAllowKick(true);
            }
        }
        // Request withdrawals
        else if (
            LVLidoVault.epochStarted() && block.timestamp > (LVLidoVault.epochStart() + LVLidoVault.termDuration())
                && !updateRateNeeded && LVLidoVault.getAllowKick() == false
        ) {
            if (taskId == 1 && t1Debt > 0) {
                uint256 approxPercentFinalInterest =
                    (LVLidoVault.rate() * ((block.timestamp - LVLidoVault.epochStart()) + lidoClaimDelay)) / 365 days;
                uint256 stethPerWsteth = getWstethToWeth(1e18);
                LVLidoVault.setCurrentRedemptionRate(stethPerWsteth);
                emit VaultLib.RedemptionRateUpdated(stethPerWsteth);
                uint256 approxCTForClaim =
                    (LVLidoVault.totalBorrowAmount() * (1e18 + uint256(approxPercentFinalInterest))) / stethPerWsteth;
                require(
                    LVLidoVault.approveForProxy(
                        VaultLib.COLLATERAL_TOKEN, address(VaultLib.LIDO_WITHDRAWAL), approxCTForClaim
                    ),
                    "Approval failure."
                );
                // Todo: Debt exceeds borrower leveraged collateral + epoch collateralLender funds (utilized + unutilized)
                uint256[] memory amounts = new uint256[](1);
                amounts[0] = approxCTForClaim;
                uint256 _requestId = LVLidoVault.requestWithdrawalsWstETH(amounts);
                emit VaultLib.FundsQueued(_requestId, approxCTForClaim);
            }
            // Withdraw funds, End epoch - delegated to LVLidoVaultUpkeeper
            else if (taskId == 2) {
                // Delegate epoch closing to LVLidoVaultUpkeeper to reduce contract size
                lvLidoVaultUpkeeper.closeEpoch(t1Debt, collateral);
                updateRateNeeded = true;
            }
        }
    }


    function performTask() external {
        (bool upkeepNeeded, bytes memory performData) = this.checkUpkeep("0x");
        if (upkeepNeeded) {
            // Temporarily store the forwarder and set it to this contract
            address originalForwarder = s_forwarderAddress;
            s_forwarderAddress = address(this);
            
            // Make external call to performUpkeep with the memory data
            this.performUpkeep(performData);
            
            // Restore original forwarder
            s_forwarderAddress = originalForwarder;
        }
        else {
            revert("No upkeep needed");
        }
    }

    // CHAINLINK FUNCTIONS
    /**
     * @notice Sets the forwarder address for meta-transactions.
     * @dev Can only be called by the owner.
     * @param forwarderAddress The new forwarder address.
     */
    function setForwarderAddress(address forwarderAddress) public {
        require(msg.sender == LVLidoVault.owner(), "Only callable by LVLidoVault");
        if (forwarderAddress == address(0)) revert VaultLib.InvalidInput(); // Zero address check for security
        emit VaultLib.ForwarderAddressUpdated(s_forwarderAddress, forwarderAddress);
        s_forwarderAddress = forwarderAddress;
    }

    /**
     * @notice Sets the LVLidoVaultUpkeeper contract address
     * @dev Can only be called by the LVLidoVault owner
     * @param _upkeeper The address of the LVLidoVaultUpkeeper contract
     */
    function setLVLidoVaultUpkeeper(address _upkeeper) public {
        require(msg.sender == LVLidoVault.owner(), "Only callable by LVLidoVault");
        if (_upkeeper == address(0)) revert VaultLib.InvalidInput();
        lvLidoVaultUpkeeper = LVLidoVaultUpkeeper(_upkeeper);
    }

    /**
     * @notice Sets the bytes representing the CBOR-encoded FunctionsRequest.Request that is sent when performUpkeep is called
     *
     * @param _subscriptionId The Functions billing subscription ID used to pay for Functions requests
     * @param _fulfillGasLimit Maximum amount of gas used to call the client contract's `handleOracleFulfillment` function
     * @param requestCBOR Bytes representing the CBOR-encoded FunctionsRequest.Request
     */

    function setRequest(bytes memory requestCBOR, uint64 _subscriptionId, uint32 _fulfillGasLimit) external {
        require(msg.sender == LVLidoVault.owner(), "Only callable by LVLidoVault");
        s_subscriptionId = _subscriptionId;
        s_fulfillGasLimit = _fulfillGasLimit;
        s_requestCBOR = requestCBOR;
    }

    /**
     * @notice Sends a request to Chainlink Functions to fetch and compute the new rate
     * @dev This function attempts to send a request using the router contract and handles any errors
     * that may occur during the request.
     */
    function getRate() internal {
        // Update state first
        s_requestCounter = s_requestCounter + 1;

        try i_router.sendRequest(
            s_subscriptionId, s_requestCBOR, FunctionsRequest.REQUEST_DATA_VERSION, s_fulfillGasLimit, VaultLib.donId
        ) returns (bytes32 requestId_) {
            s_lastRequestId = requestId_;
            emit RequestSent(requestId_);
        } catch Error(string memory reason) {
            emit VaultLib.RequestRevertedWithErrorMsg(reason);
            LVLidoVault.updateRate(0);
            updateRateNeeded = false;
        } catch (bytes memory data) {
            emit VaultLib.RequestRevertedWithoutErrorMsg(data);
            LVLidoVault.updateRate(0);
            updateRateNeeded = false;
        }
    }

    /**
     * @notice Processes Chainlink Functions response
     * @dev Decodes pre-aggregated rate sums (1e27) and calculates average APR (1e18)
     * @param requestId Chainlink request ID
     * @param response Encoded (sumLiquidityRates, sumBorrowRates, numRates)
     * @param err Error data if any
     */
    function fulfillRequest(bytes32 requestId, bytes memory response, bytes memory err) internal override {
        // Store request metadata for tracking and debugging purposes
        s_lastRequestId = requestId;
        s_lastResponse = response;
        s_lastError = err;
        s_lastUpkeepTimeStamp = block.timestamp;

        // If there's an error in the response, log it and exit early
        if (err.length > 0) {
            emit VaultLib.OCRResponse(requestId, response, LVLidoVault.rate(), err);
            LVLidoVault.updateRate(0);
            updateRateNeeded = false;
            return;
        }

        // Validate response data exists
        if (response.length == 0) {
            emit VaultLib.OCRResponse(requestId, response, LVLidoVault.rate(), abi.encodePacked("Empty response"));
            LVLidoVault.updateRate(0);
            updateRateNeeded = false;
            return;
        }

        // Decode the aggregated rate data from Chainlink Functions
        (uint256 sumLiquidityRates_1e27, uint256 sumVariableBorrowRates_1e27, uint256 numRates) =
            abi.decode(response, (uint256, uint256, uint256));
        // Ensure we have valid rate data to process
        // If numRates is 0, trigger fallback rate from Aave
        if (numRates == 0) {
            emit VaultLib.OCRResponse(requestId, response, LVLidoVault.rate(), abi.encodePacked("Decoded response is empty"));
            LVLidoVault.updateRate(0);
            updateRateNeeded = false;
            return;
        }

        // Calculate the average APR by:
        // 1. Adding supply and borrow rates
        // 2. Dividing by 2 to get the average between supply and borrow
        // 3. Dividing by numRates to get the average across all protocols
        // 4. Converting from 1e27 to 1e18 scale by dividing by 1e9
        uint256 rate = (sumLiquidityRates_1e27 + sumVariableBorrowRates_1e27) / (2 * numRates * 1e9);
        
        // Validate rate is within bounds before updating
        if (rate < lowerBoundRate || rate > upperBoundRate) {
            emit VaultLib.OCRResponse(requestId, response, LVLidoVault.rate(), abi.encodePacked("Rate out of bounds"));
            // Don't update the rate if it's outside bounds
            LVLidoVault.updateRate(0);
            updateRateNeeded = false;
            return;
        }
        // Rate is within bounds, proceed with update
        LVLidoVault.updateRate(rate);
        updateRateNeeded = false; // Mark that we've successfully updated the rate
        emit VaultLib.OCRResponse(requestId, response, rate, err);
    }

    // ============================================================
    // Emergency Aave recovery — extracted from LVLidoVault to reduce
    // vault bytecode below EIP-170 limit.
    // ============================================================

    function _validateEmergencyTargetEpoch(uint256 targetEpoch) internal view {
        uint256 currentEpoch = LVLidoVault.epoch();
        if (targetEpoch == 0 || targetEpoch > currentEpoch) {
            revert VaultLib.InvalidEpoch();
        }
        if (targetEpoch < currentEpoch) {
            return;
        }
        if (!LVLidoVault.epochStarted() || block.timestamp <= LVLidoVault.epochStart() + LVLidoVault.termDuration()) {
            revert VaultLib.EpochNotEnded();
        }
        if (block.timestamp <= LVLidoVault.epochStart() + LVLidoVault.termDuration() + LVLidoVault.emergencyAaveWithdrawDelay()) {
            revert VaultLib.EmergencyWithdrawalTooEarly();
        }
    }

    /**
     * @notice Permissionless emergency withdrawal of lender Aave funds for a specific ended epoch.
     * @dev Withdraws only the epoch's proportional share from Aave and moves it to per-epoch claimable state.
     * @dev Idempotent: returns 0 if already executed or if epoch has no lender Aave deposits.
     */
    function emergencyWithdrawLenderAaveForEpoch(uint256 targetEpoch) external returns (uint256) {
        _validateEmergencyTargetEpoch(targetEpoch);

        if (LVLidoVault.epochEmergencyLenderWithdrawn(targetEpoch)) {
            return 0;
        }

        uint256 epochPrincipal = LVLidoVault.epochToAaveLenderDeposits(targetEpoch);
        uint256 totalDeposits = LVLidoVault.totalAaveLenderDeposits();
        if (epochPrincipal == 0 || totalDeposits == 0) {
            return 0;
        }

        uint256 currentAaveBalance = LVLidoVault.getAaveBalanceQuote();
        uint256 amountToWithdraw = (epochPrincipal * currentAaveBalance) / totalDeposits;
        if (amountToWithdraw == 0) {
            return 0;
        }

        uint256 withdrawn = LVLidoVault.executeAaveWithdraw(VaultLib.QUOTE_TOKEN, amountToWithdraw);
        if (withdrawn != amountToWithdraw) {
            revert VaultLib.TokenOperationFailed();
        }

        LVLidoVault.setAaveLenderState(targetEpoch, totalDeposits - epochPrincipal, 0);
        LVLidoVault.setEmergencyLenderState(targetEpoch, true, epochPrincipal, withdrawn);

        emit VaultLib.EmergencyAaveLenderEpochWithdrawn(targetEpoch, epochPrincipal, withdrawn);
        return withdrawn;
    }

    /**
     * @notice Permissionless emergency withdrawal of collateral-lender Aave funds for a specific ended epoch.
     * @dev Withdraws only the epoch's proportional share from Aave and moves it to per-epoch claimable state.
     * @dev Idempotent: returns 0 if already executed or if epoch has no CL Aave deposits.
     */
    function emergencyWithdrawCLAaveForEpoch(uint256 targetEpoch) external returns (uint256) {
        _validateEmergencyTargetEpoch(targetEpoch);

        if (LVLidoVault.epochEmergencyCLWithdrawn(targetEpoch)) {
            return 0;
        }

        uint256 epochPrincipal = LVLidoVault.epochToAaveCLDeposits(targetEpoch);
        uint256 totalDeposits = LVLidoVault.totalAaveCLDeposits();
        if (epochPrincipal == 0 || totalDeposits == 0) {
            return 0;
        }

        uint256 currentAaveBalance = LVLidoVault.getAaveBalance();
        uint256 amountToWithdraw = (epochPrincipal * currentAaveBalance) / totalDeposits;
        if (amountToWithdraw == 0) {
            return 0;
        }

        uint256 withdrawn = LVLidoVault.executeAaveWithdraw(VaultLib.COLLATERAL_TOKEN, amountToWithdraw);
        if (withdrawn != amountToWithdraw) {
            revert VaultLib.TokenOperationFailed();
        }

        LVLidoVault.setAaveCLState(targetEpoch, totalDeposits - epochPrincipal, 0);
        LVLidoVault.setEmergencyCLState(targetEpoch, true, epochPrincipal, withdrawn);

        emit VaultLib.EmergencyAaveCLEpochWithdrawn(targetEpoch, epochPrincipal, withdrawn);
        return withdrawn;
    }

    /**
     * @notice Claims a user's lender share after emergency epoch withdrawal.
     * @dev User claim = proportional share of the epoch's withdrawn amount.
     */
    function emergencyClaimLenderAaveForEpoch(uint256 targetEpoch) external returns (uint256) {
        uint256 userPrincipal = LVLidoVault.userAaveLenderDeposits(msg.sender, targetEpoch);
        if (userPrincipal == 0) {
            revert VaultLib.NoEmergencyClaim();
        }

        uint256 principalRemaining = LVLidoVault.epochEmergencyLenderPrincipalRemaining(targetEpoch);
        uint256 claimableRemaining = LVLidoVault.epochEmergencyLenderClaimableRemaining(targetEpoch);
        if (principalRemaining == 0 || claimableRemaining == 0) {
            revert VaultLib.NoEmergencyClaim();
        }

        uint256 amount = (userPrincipal * claimableRemaining) / principalRemaining;
        if (amount == 0) {
            if (userPrincipal == principalRemaining) {
                amount = claimableRemaining;
            } else {
                revert VaultLib.NoEmergencyClaim();
            }
        }

        LVLidoVault.setUserAaveLenderDeposit(msg.sender, targetEpoch, 0);
        LVLidoVault.setEmergencyLenderState(
            targetEpoch, true, principalRemaining - userPrincipal, claimableRemaining - amount
        );
        require(LVLidoVault.transferForProxy(VaultLib.QUOTE_TOKEN, msg.sender, amount), "Transfer failed");

        emit VaultLib.EmergencyAaveLenderClaimed(msg.sender, targetEpoch, userPrincipal, amount);
        return amount;
    }

    /**
     * @notice Claims a user's collateral-lender share after emergency epoch withdrawal.
     * @dev User claim = proportional share of the epoch's withdrawn amount.
     */
    function emergencyClaimCLAaveForEpoch(uint256 targetEpoch) external returns (uint256) {
        uint256 userPrincipal = LVLidoVault.userAaveCLDeposits(msg.sender, targetEpoch);
        if (userPrincipal == 0) {
            revert VaultLib.NoEmergencyClaim();
        }

        uint256 principalRemaining = LVLidoVault.epochEmergencyCLPrincipalRemaining(targetEpoch);
        uint256 claimableRemaining = LVLidoVault.epochEmergencyCLClaimableRemaining(targetEpoch);
        if (principalRemaining == 0 || claimableRemaining == 0) {
            revert VaultLib.NoEmergencyClaim();
        }

        uint256 amount = (userPrincipal * claimableRemaining) / principalRemaining;
        if (amount == 0) {
            if (userPrincipal == principalRemaining) {
                amount = claimableRemaining;
            } else {
                revert VaultLib.NoEmergencyClaim();
            }
        }

        LVLidoVault.setUserAaveCLDeposit(msg.sender, targetEpoch, 0);
        LVLidoVault.setEmergencyCLState(
            targetEpoch, true, principalRemaining - userPrincipal, claimableRemaining - amount
        );
        // Keep totalCollateralLenderCT consistent with principal leaving the vault.
        LVLidoVault.setTotalCollateralLenderCT(LVLidoVault.totalCollateralLenderCT() - userPrincipal);
        require(LVLidoVault.transferForProxy(VaultLib.COLLATERAL_TOKEN, msg.sender, amount), "Transfer failed");

        emit VaultLib.EmergencyAaveCLClaimed(msg.sender, targetEpoch, userPrincipal, amount);
        return amount;
    }

    // ============================================================
    // Admin functions — moved from LVLidoVault to reduce bytecode
    // ============================================================

    /**
     * @notice Sets the maximum acceptable flash loan fee threshold
     * @dev CIRCUIT BREAKER: If Morpho Blue introduces flash loan fees, this protects the vault
     * @param _maxFeeBps Maximum fee in basis points (100 bps = 1%)
     * @param _flashLoanFeeBps Flash loan fee in basis points
     */
    function setMaxFlashLoanFeeThreshold(uint256 _maxFeeBps, uint256 _flashLoanFeeBps) external onlyOwner {
        require(_maxFeeBps <= 1000, "Fee threshold too high");
        require(_flashLoanFeeBps <= 1000, "Flash loan fee too high");
        LVLidoVault.setMaxFlashLoanFeeThresholdProxy(_maxFeeBps, _flashLoanFeeBps);
    }
}
