// SPDX-License-Identifier: BUSL-1.1
// Author: Lendvest

pragma solidity ^0.8.20;

import {IERC20Pool} from "./interfaces/pool/erc20/IERC20Pool.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IPoolInfoUtils} from "./interfaces/IPoolInfoUtils.sol";
import {ILVToken} from "./interfaces/ILVToken.sol";
import {UD60x18} from "lib/prb-math/src/ud60x18/ValueType.sol";
import {wrap, unwrap} from "lib/prb-math/src/ud60x18/Casting.sol";
import {mul} from "lib/prb-math/src/ud60x18/Math.sol";
import {ReentrancyGuard} from "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import {IWsteth} from "./interfaces/vault/IWsteth.sol";

interface ILVLidoVault {
    function mintForProxy(address token, address receiver, uint256 amount) external returns (bool);
    function burnForProxy(address token, address account, uint256 amount) external returns (bool);
    function lenderKick(uint256 bondAmount) external;
    function transferForProxy(address token, address recipient, uint256 amount) external returns (bool);
    function withdrawBondsForProxy() external returns (uint256);
}

contract LiquidationProxy is Ownable, ReentrancyGuard {
    IERC20Pool public pool;
    IPoolInfoUtils public constant poolInfoUtils = IPoolInfoUtils(0x30c5eF2997d6a882DE52c4ec01B6D0a5e5B4fAAE);
    uint256 constant MIN_BOND_FACTOR = 0.005 * 1e18;
    uint256 constant MAX_BOND_FACTOR = 0.03 * 1e18;
    bool public allowKick = false;
    address public constant quoteToken = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant collateralToken = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    ILVToken public testCollateralToken;
    ILVToken public testQuoteToken;
    ILVLidoVault public LVLidoVault;
    // Kicker tracking
    uint256 currentBondAmount;
    mapping(address => uint256) public kickerAmount;
    address currentKicker;

    event KickByVault(address sender, uint256 bondSize);
    event PurchaseLVToken(uint256 price, uint256 quoteTokenAmount, uint256 collateralAmount, address sender);
    event AllowKickSet(bool allowKick);
    event AuctionSettled(
        address indexed borrower,
        uint256 collateralSettled,
        bool isBorrowerSettled,
        uint256 remainingDebt,
        uint256 timestamp
    );

    constructor(address _pool) Ownable(msg.sender) {
        pool = IERC20Pool(_pool);
        testCollateralToken = ILVToken(pool.collateralAddress());
        testQuoteToken = ILVToken(pool.quoteTokenAddress());
    }

    function settle(uint256 maxDepth_) external nonReentrant returns (uint256, bool) {
        // Get auction status from PoolInfoUtils.
        // auctionStatus returns: kickTime, collateral, debtToCover, isCollateralized, price, neutralPrice, referencePrice, debtToCollateral, bondFactor.
        (
            uint256 kickTime,
            uint256 collateral,
            uint256 debtToCover,
            bool isCollateralized,
            uint256 price,
            uint256 neutralPrice,
            uint256 referencePrice,
            uint256 debtToCollateral,
            uint256 bondFactor
        ) = auctionStatus();

        require(
            (allowKick && (debtToCover == 0 || collateral == 0 || block.timestamp > kickTime + 72 hours)),
            "Cannot settle auction."
        );

        (uint256 collateralSettled, bool isBorrowerSettled) = pool.settle(address(LVLidoVault), maxDepth_);

        if (isBorrowerSettled) {
            // Store kicker info before resetting
            address kicker = currentKicker;
            uint256 bondAmount = currentBondAmount;

            // Reset kicker state
            currentKicker = address(0);
            currentBondAmount = 0;
            allowKick = false;

            // Remove bond
            (uint256 claimable, uint256 locked) = pool.kickerInfo(address(LVLidoVault));
            require(locked == 0);
            uint256 withdrawnAmount_ = LVLidoVault.withdrawBondsForProxy();
            if (withdrawnAmount_ > 0) {
                // Unwrap tokens as needed and transfer the bond reward to the kicker.
                require(
                    LVLidoVault.burnForProxy(address(testQuoteToken), address(LVLidoVault), withdrawnAmount_),
                    "Burn failed."
                );
                uint256 initialKickerAmount = kickerAmount[kicker];
                // Reset auction state
                if (withdrawnAmount_ > initialKickerAmount) {
                    // Kicker bond grew
                    uint256 extraAmount = withdrawnAmount_ - initialKickerAmount;
                    require(LVLidoVault.transferForProxy(quoteToken, address(this), extraAmount), "Transfer failure.");
                    kickerAmount[kicker] += extraAmount;
                }
            }
        }

        // Emit an event documenting the auction settlement.
        emit AuctionSettled(address(LVLidoVault), collateralSettled, isBorrowerSettled, debtToCover, block.timestamp);

        return (collateralSettled, isBorrowerSettled);
    }

    function auctionStatus()
        public
        view
        returns (
            uint256 kickTime_,
            uint256 collateral_,
            uint256 debtToCover_,
            bool isCollateralized_,
            uint256 price_,
            uint256 neutralPrice_,
            uint256 referencePrice_,
            uint256 debtToCollateral_,
            uint256 bondFactor_
        )
    {
        (
            kickTime_,
            collateral_,
            debtToCover_,
            isCollateralized_,
            price_,
            neutralPrice_,
            referencePrice_,
            debtToCollateral_,
            bondFactor_
        ) = poolInfoUtils.auctionStatus(address(pool), address(LVLidoVault));
        return (
            kickTime_,
            collateral_,
            debtToCover_,
            isCollateralized_,
            price_,
            neutralPrice_,
            referencePrice_,
            debtToCollateral_,
            bondFactor_
        );
    }

    function setLVLidoVault(address _LVLidoVault) public onlyOwner {
        LVLidoVault = ILVLidoVault(_LVLidoVault);
    }

    function setAllowKick(bool _allowKick) external onlyOwner {
        allowKick = _allowKick;
        emit AllowKickSet(_allowKick);
    }

    // Kick to start AUCTION
    function lenderKick() public {
        //require(eligibleForLiquidationPool(_borrower), "Ineligible for liquidation");
        require(allowKick, "Kick not allowed");
        // 3 Scenarios to liquidate in:
        // 1. Borrowers are undercollateralized based on redemption price (collateral lender, else auction)
        // 2. Borrowers are overutilized based on Ajna pool utilization (collateral lender, else auction)
        // 3. Borrowers are undercollateralized based on Ajna bucket price (auction) (redemption price higher than bucket price)

        uint256 bondAmount = getBondSize();

        // Transfer from user to this contract
        require(IERC20(quoteToken).transferFrom(msg.sender, address(this), bondAmount), "Transfer failed");
        LVLidoVault.lenderKick(bondAmount);

        // Track the actual kicker
        currentBondAmount = bondAmount;
        kickerAmount[msg.sender] += bondAmount;
        currentKicker = msg.sender;

        emit KickByVault(msg.sender, bondAmount);
    }

    function take(uint256 collateralToPurchase) external returns (uint256) {
        // Get auction price and calculate quote token amount needed
        (,, uint256 debtToCover,, uint256 auctionPrice,,,,) = auctionStatus();
        require(debtToCover > 0, "Auction not ongoing.");

        // Internal implementation note tracked in .internal-notes/fixme-tracker.md
        // We can't do that currently because we don't have the rate before the term ends
        // For now, set total borrow amount to 0 if debt is paid off in full
        UD60x18 collateralAmount = wrap(collateralToPurchase);
        UD60x18 price = wrap(auctionPrice);
        UD60x18 quoteTokenPaymentUD60x18 = mul(collateralAmount, price);
        uint256 quoteTokenPayment = unwrap(quoteTokenPaymentUD60x18) + 1 wei;
        // uint256 quoteTokenPayment = (collateralToPurchase * auctionPrice) / 1e18;

        require(
            LVLidoVault.mintForProxy(address(testQuoteToken), address(this), quoteTokenPayment)
                && IERC20(address(testQuoteToken)).approve(address(pool), quoteTokenPayment),
            "Take failure."
        );

        uint256 collateralTaken = pool.take(address(LVLidoVault), collateralToPurchase, address(this), "");

        // Calculate transfer amount using PRBMath
        UD60x18 collateralTakenAmount = wrap(collateralTaken);
        UD60x18 transferAmountUD60x18 = mul(collateralTakenAmount, price);
        uint256 transferAmount = unwrap(transferAmountUD60x18);

        // Internal implementation note tracked in .internal-notes/fixme-tracker.md
        require(
            IERC20(quoteToken).transferFrom(msg.sender, address(LVLidoVault), transferAmount),
            "Transfer from user failed"
        );

        // console.log("LiqProxy Collateral Balance:", testCollateralToken.balanceOf(address(this)));
        require(
            LVLidoVault.transferForProxy(collateralToken, msg.sender, collateralTaken)
                && LVLidoVault.burnForProxy(address(testCollateralToken), address(this), collateralTaken),
            "Transfer or burn failed."
        );

        // Check if auction is settled
        (uint256 kickTime,,,,,,,,) = auctionStatus();
        bool isBorrowerSettled;
        (,, debtToCover,,,,,,) = auctionStatus();
        // console.log("debtToCover:", debtToCover);

        if (kickTime == 0) {
            // Remove bond
            (uint256 claimable, uint256 locked) = pool.kickerInfo(address(LVLidoVault));
            require(locked == 0);
            uint256 withdrawnAmount_ = LVLidoVault.withdrawBondsForProxy();
            if (withdrawnAmount_ > 0) {
                // Unwrap tokens as needed and transfer the bond reward to the kicker.
                require(
                    LVLidoVault.burnForProxy(address(testQuoteToken), address(LVLidoVault), withdrawnAmount_),
                    "Burn failed."
                );
                uint256 initialKickerAmount = kickerAmount[currentKicker];
                // Reset auction state
                if (withdrawnAmount_ > initialKickerAmount) {
                    // Kicker bond grew
                    uint256 extraAmount = withdrawnAmount_ - initialKickerAmount;
                    require(LVLidoVault.transferForProxy(quoteToken, address(this), extraAmount), "Transfer failure.");
                    kickerAmount[currentKicker] += extraAmount;
                }
            }
            currentBondAmount = 0;
            currentKicker = address(0);
            allowKick = false;
        }
        return collateralTaken;
    }

    function getBondSize() public view returns (uint256) {
        (uint256 debt, uint256 collateral, uint256 npTpRatio) = pool.borrowerInfo(address(LVLidoVault));
        (, uint256 bondSize_) = _bondParams(debt, npTpRatio);
        return bondSize_ + 1 wei;
    }

    function _bondParams(uint256 borrowerDebt_, uint256 npTpRatio_)
        internal
        pure
        returns (uint256 bondFactor_, uint256 bondSize_)
    {
        // Calculate bond factor using PRBMath
        UD60x18 npTpRatio = wrap(npTpRatio_);
        UD60x18 maxBondFactor = wrap(MAX_BOND_FACTOR);
        UD60x18 minBondFactor = wrap(MIN_BOND_FACTOR);

        // Calculate (npTpRatio - 1e18) / 10
        UD60x18 ratioDiff = wrap((npTpRatio_ - 1e18) / 10);

        // Use min and max operations
        UD60x18 tempFactor = ratioDiff.unwrap() > MAX_BOND_FACTOR ? maxBondFactor : ratioDiff;
        bondFactor_ = tempFactor.unwrap() < MIN_BOND_FACTOR ? MIN_BOND_FACTOR : tempFactor.unwrap();

        // Calculate bond size using PRBMath multiplication
        UD60x18 bondFactor = wrap(bondFactor_);
        UD60x18 borrowerDebt = wrap(borrowerDebt_);
        bondSize_ = unwrap(mul(bondFactor, borrowerDebt));
    }

    function eligibleForLiquidationPool(address _borrower) public view returns (bool) {
        uint256 lup = poolInfoUtils.lup(address(pool));
        (uint256 debt_, uint256 collateral_, uint256 t0Np_, uint256 thresholdPrice_) =
            poolInfoUtils.borrowerInfo(address(pool), _borrower);

        if (lup < thresholdPrice_) {
            return true;
        }
        return false;
    }

    function claimBond() public returns (uint256) {
        // Get bond amount locally
        uint256 bondAmount = kickerAmount[msg.sender];
        require(bondAmount > 0, "No bond to claim");
        // Reset kicker state
        kickerAmount[msg.sender] = 0;
        // Transfer bond to user
        require(IERC20(quoteToken).transfer(msg.sender, bondAmount), "Bond transfer failed");
        return bondAmount;
    }
}
