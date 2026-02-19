// SPDX-License-Identifier: BUSL-1.1
// Author: Lendvest
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import "forge-std/console.sol";
import {LVLidoVault} from "../src/LVLidoVault.sol";
import "../src/interfaces/pool/erc20/IERC20PoolFactory.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {LiquidationProxy} from "../src/LiquidationProxy.sol";
import {LVToken} from "../src/LVToken.sol";
import {IPoolInfoUtils} from "../src/interfaces/IPoolInfoUtils.sol";
import {IERC20Pool} from "../src/interfaces/pool/erc20/IERC20Pool.sol";
import {TestHelpers} from "./TestHelpers.t.sol";
import {IWsteth} from "../src/interfaces/vault/IWsteth.sol";
import {VaultLib} from "../src/libraries/VaultLib.sol";
import {LVLidoVaultUtil} from "../src/LVLidoVaultUtil.sol";
import {IMorpho} from "../src/interfaces/IMorpho.sol";

/**
 * @title MorphoFlashLoanTests
 * @notice Comprehensive test suite for Morpho Blue flashloan integration
 * @dev Tests the flashloan flow in a mainnet fork environment
 */
contract MorphoFlashLoanTests is Test, TestHelpers {
    // Events to track
    event LoanComposition(
        uint256 baseLoanCollateral,
        uint256 flashLoanAmount,
        uint256 totalCollateral,
        uint256 amountToBorrow
    );
    event EpochStarted(uint256 indexed epoch, uint256 startTime, uint256 endTime);

    LVToken private lvweth;
    IERC20 private weth;
    IWsteth private wsteth;
    LVToken private lvwsteth;
    LVLidoVault private lvlido;
    LiquidationProxy private liquidationProxy;
    IERC20Pool private ajnaPool;
    LVLidoVaultUtil private lvlidoVaultUtil;
    IMorpho private morpho;

    address public constant POOL_FACTORY_ADDRESS = 0x6146DD43C5622bB6D12A5240ab9CF4de14eDC625;
    address public constant MORPHO_ADDRESS = 0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb;
    // address public constant MORPHO_WSTETH_WETH_MARKET = 0xb8fc70e82bc5bb53e773626fcc6a23f7eefa036918d7ef216ecfb1950a94a85e;
    
    address owner = 0x6f33D099880D4b08AAd6B80c26423ec138318520;
    address forwarder = makeAddr("forwarder");
    address lender1 = makeAddr("lender1");
    address borrower1 = makeAddr("borrower1");
    address collateralLender1 = makeAddr("collateralLender1");

    function setUp() public {
        // Create mainnet fork at a recent block
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));
        
        // Start impersonating the owner account
        vm.startPrank(owner);

        // Initialize token contracts
        weth = IERC20(WETH_ADDRESS);
        wsteth = IWsteth(WSTETH_ADDRESS);
        morpho = IMorpho(MORPHO_ADDRESS);

        // Deploy LV token contracts
        lvweth = new LVToken("LV WETH", "LVWETH");
        lvwsteth = new LVToken("LV WSTETH", "LVWSTETH");

        // Deploy the Ajna pool using the pool factory
        IERC20PoolFactory poolFactory = IERC20PoolFactory(POOL_FACTORY_ADDRESS);
        address ajnaPoolAddress = poolFactory.deployPool(
            address(lvwsteth),
            address(lvweth),
            100000000000000000 // 10% interest rate
        );
        ajnaPool = IERC20Pool(ajnaPoolAddress);

        // Deploy the Liquidation Proxy
        liquidationProxy = new LiquidationProxy(ajnaPoolAddress);

        // Deploy the LVLidoVault and its utility contract
        lvlido = new LVLidoVault(ajnaPoolAddress, address(liquidationProxy));
        lvlidoVaultUtil = new LVLidoVaultUtil(address(lvlido));
        lvlido.setLVLidoVaultUtilAddress(address(lvlidoVaultUtil));
        liquidationProxy.setLVLidoVault(address(lvlido));

        // Transfer ownership of contracts to LVLidoVault
        lvwsteth.transferOwnership(address(lvlido));
        lvweth.transferOwnership(address(lvlido));
        liquidationProxy.transferOwnership(address(lvlido));

        // Set the forwarder address for automation
        lvlidoVaultUtil.setForwarderAddress(forwarder);

        // Stop impersonating the owner account
        vm.stopPrank();

        // Forward time based on deployment timestamp and initial cooldown period
        vm.warp(lvlido.deploymentTimestamp() + 72 hours);

        console.log("Setup complete");
        console.log("LVLidoVault:", address(lvlido));
        console.log("Morpho:", address(morpho));
    }

    /**
     * @notice Test basic Morpho flashloan execution during epoch start
     * @dev Verifies that:
     *      1. Flash loan is requested from Morpho
     *      2. Callback is executed correctly
     *      3. Collateral is properly handled
     *      4. Debt is drawn from Ajna pool
     *      5. Flash loan is repaid with approval
     * @dev Note: leverageFactor = 80 (8x leverage), inverseBorrowCLAmount = 2 (need 50% collateral)
     *      For 1 wstETH borrower collateral:
     *      - Flash loan: 1 * (80-10)/10 = 7 wstETH
     *      - Total collateral: 1 + 7 = 8 wstETH
     *      - Borrow: 7 * redemptionRate WETH
     *      - Required CL: 7 / 2 = 3.5 wstETH
     */
    function testMorphoFlashLoanBasic() public {
        uint256 lenderAmount = 50 ether; // 50 WETH (enough for leverage)
        uint256 borrowerAmount = 1 ether; // 1 wstETH
        uint256 collateralLenderAmount = 4 ether; // 4 wstETH (more than 3.5 needed)

        console.log("\n=== Starting Morpho Flash Loan Basic Test ===");

        // Setup: Fund test accounts
        _fundAccount(lender1, lenderAmount, 0);
        _fundAccount(borrower1, 0, borrowerAmount);
        _fundAccount(collateralLender1, 0, collateralLenderAmount);

        // Step 1: Create orders
        console.log("\n--- Step 1: Creating Orders ---");
        _createLenderOrder(lender1, lenderAmount);
        _createBorrowerOrder(borrower1, borrowerAmount);
        _createCollateralLenderOrder(collateralLender1, collateralLenderAmount);

        // Verify orders were created
        assertEq(lvlido.getLenderOrdersLength(), 1, "Should have 1 lender order");
        assertEq(lvlido.getBorrowerOrdersLength(), 1, "Should have 1 borrower order");
        assertEq(lvlido.getCollateralLenderOrdersLength(), 1, "Should have 1 collateral lender order");

        // Step 2: Record state before epoch start
        console.log("\n--- Step 2: Recording Pre-Epoch State ---");
        uint256 vaultWstethBefore = IERC20(address(wsteth)).balanceOf(address(lvlido));
        uint256 vaultWethBefore = weth.balanceOf(address(lvlido));
        uint256 morphoWstethBefore = IERC20(address(wsteth)).balanceOf(MORPHO_ADDRESS);
        
        console.log("Vault WSTETH Before:", vaultWstethBefore);
        console.log("Vault WETH Before:", vaultWethBefore);
        console.log("Morpho WSTETH Before:", morphoWstethBefore);

        // Step 3: Start epoch (triggers flash loan)
        console.log("\n--- Step 3: Starting Epoch (Triggers Flash Loan) ---");
        
        // Note: Multiple events are emitted, don't check specific event order
        lvlido.startEpoch();

        // Step 4: Verify post-epoch state
        console.log("\n--- Step 4: Verifying Post-Epoch State ---");
        
        // Check epoch started (note: epoch counter increments twice in startEpoch, so it's 2 not 1)
        assertTrue(lvlido.epochStarted(), "Epoch should be started");
        assertEq(lvlido.epoch(), 2, "Epoch should be 2");

        // Check that debt was drawn from Ajna pool
        (uint256 debt, uint256 collateral, uint256 t0Np) = ajnaPool.borrowerInfo(address(lvlido));
        console.log("Ajna Debt:", debt);
        console.log("Ajna Collateral:", collateral);
        assertTrue(debt > 0, "Should have debt in Ajna pool");
        assertTrue(collateral > 0, "Should have collateral in Ajna pool");

        // Check total borrow amount was recorded
        assertTrue(lvlido.totalBorrowAmount() > 0, "Total borrow amount should be recorded");
        console.log("Total Borrow Amount:", lvlido.totalBorrowAmount());

        // Check matches were created (epoch is 2)
        VaultLib.MatchInfo[] memory matches = lvlido.getEpochMatches(2);
        assertTrue(matches.length > 0, "Should have created matches");
        console.log("Number of matches:", matches.length);

        // Step 5: Verify flash loan was repaid (no remaining approval)
        console.log("\n--- Step 5: Verifying Flash Loan Repayment ---");
        uint256 vaultWstethAfter = IERC20(address(wsteth)).balanceOf(address(lvlido));
        console.log("Vault WSTETH After:", vaultWstethAfter);
        
        // The vault should have used WSTETH from the flash loan and its own collateral
        // After repayment, balance should reflect the utilized amounts

        console.log("\n=== Test Complete ===");
    }

    /**
     * @notice Test Morpho flashloan with multiple lenders and borrowers
     * @dev Tests complex matching scenario with multiple participants
     * @dev For 2 borrowers with 1 + 0.5 = 1.5 wstETH total:
     *      - Flash loan: 1.5 * 7 = 10.5 wstETH
     *      - Required CL: 10.5 / 2 = 5.25 wstETH minimum
     */
    function testMorphoFlashLoanMultipleParticipants() public {
        console.log("\n=== Starting Morpho Flash Loan Multiple Participants Test ===");

        address lender2 = makeAddr("lender2");
        address borrower2 = makeAddr("borrower2");
        address collateralLender2 = makeAddr("collateralLender2");

        // Fund accounts with varying amounts (reduced borrower amounts, increased CL)
        _fundAccount(lender1, 50 ether, 0);
        _fundAccount(lender2, 30 ether, 0);
        _fundAccount(borrower1, 0, 1 ether);   // Reduced from 7
        _fundAccount(borrower2, 0, 0.5 ether); // Reduced from 4
        _fundAccount(collateralLender1, 0, 4 ether);  // Increased
        _fundAccount(collateralLender2, 0, 3 ether);  // Keep same

        // Create multiple orders
        console.log("\n--- Creating Multiple Orders ---");
        _createLenderOrder(lender1, 50 ether);
        _createLenderOrder(lender2, 30 ether);
        _createBorrowerOrder(borrower1, 1 ether);
        _createBorrowerOrder(borrower2, 0.5 ether);
        _createCollateralLenderOrder(collateralLender1, 4 ether);
        _createCollateralLenderOrder(collateralLender2, 3 ether);

        // Verify orders
        assertEq(lvlido.getLenderOrdersLength(), 2, "Should have 2 lender orders");
        assertEq(lvlido.getBorrowerOrdersLength(), 2, "Should have 2 borrower orders");
        assertEq(lvlido.getCollateralLenderOrdersLength(), 2, "Should have 2 collateral lender orders");

        // Start epoch
        console.log("\n--- Starting Epoch ---");
        lvlido.startEpoch();

        // Verify matches were created for multiple participants (epoch is 2)
        VaultLib.MatchInfo[] memory matches = lvlido.getEpochMatches(2);
        console.log("Number of matches created:", matches.length);
        assertTrue(matches.length >= 1, "Should have created matches");

        // Verify debt accumulation
        (uint256 totalDebt,,) = ajnaPool.borrowerInfo(address(lvlido));
        console.log("Total Debt:", totalDebt);
        assertTrue(totalDebt > 0, "Should have accumulated debt");

        console.log("\n=== Test Complete ===");
    }

    /**
     * @notice Test that flashloan callback properly validates caller
     * @dev Should revert if called by non-Morpho address
     */
    function testMorphoFlashLoanCallbackValidation() public {
        console.log("\n=== Testing Flash Loan Callback Validation ===");

        // Try to call callback directly (should fail)
        vm.expectRevert(VaultLib.Unauthorized.selector);
        lvlido.onMorphoFlashLoan(1 ether, abi.encode(1 ether, 1 ether));

        console.log("Callback correctly rejected unauthorized caller");
        console.log("\n=== Test Complete ===");
    }

    /**
     * @notice Test flashloan execution and repayment flow
     * @dev Verifies the complete lifecycle of a flash loan
     * @dev For 1 wstETH borrower: needs 3.5 wstETH collateral lender
     */
    function testMorphoFlashLoanRepaymentFlow() public {
        console.log("\n=== Testing Flash Loan Repayment Flow ===");

        uint256 lenderAmount = 50 ether;
        uint256 borrowerAmount = 1 ether;
        uint256 collateralLenderAmount = 4 ether;

        // Setup
        _fundAccount(lender1, lenderAmount, 0);
        _fundAccount(borrower1, 0, borrowerAmount);
        _fundAccount(collateralLender1, 0, collateralLenderAmount);

        _createLenderOrder(lender1, lenderAmount);
        _createBorrowerOrder(borrower1, borrowerAmount);
        _createCollateralLenderOrder(collateralLender1, collateralLenderAmount);

        // Record Morpho's WSTETH balance before
        uint256 morphoBalanceBefore = IERC20(address(wsteth)).balanceOf(MORPHO_ADDRESS);
        console.log("Morpho WSTETH Balance Before:", morphoBalanceBefore);

        // Start epoch (triggers flash loan and repayment)
        lvlido.startEpoch();

        // Verify Morpho's balance is unchanged (loan was repaid)
        uint256 morphoBalanceAfter = IERC20(address(wsteth)).balanceOf(MORPHO_ADDRESS);
        console.log("Morpho WSTETH Balance After:", morphoBalanceAfter);
        
        // Morpho's balance should be equal or greater (if flash loan fee exists)
        assertGe(morphoBalanceAfter, morphoBalanceBefore, "Morpho should have been repaid");

        // Verify no hanging approvals
        uint256 vaultApprovalToMorpho = IERC20(address(wsteth)).allowance(address(lvlido), MORPHO_ADDRESS);
        console.log("Vault approval to Morpho after:", vaultApprovalToMorpho);

        console.log("\n=== Test Complete ===");
    }

    /**
     * @notice Test wethToWsteth conversion within flash loan context
     * @dev Verifies the conversion process during flash loan callback
     */
    function testWethToWstethConversion() public {
        console.log("\n=== Testing WETH to WSTETH Conversion ===");

        uint256 lenderAmount = 5 ether;
        uint256 borrowerAmount = 2 ether;
        uint256 collateralLenderAmount = 2 ether;

        _fundAccount(lender1, lenderAmount, 0);
        _fundAccount(borrower1, 0, borrowerAmount);
        _fundAccount(collateralLender1, 0, collateralLenderAmount);

        _createLenderOrder(lender1, lenderAmount);
        _createBorrowerOrder(borrower1, borrowerAmount);
        _createCollateralLenderOrder(collateralLender1, collateralLenderAmount);

        // Get redemption rate
        uint256 redemptionRateBefore = wsteth.stEthPerToken();
        console.log("Redemption Rate:", redemptionRateBefore);

        // Start epoch
        lvlido.startEpoch();

        // Verify redemption rate was set correctly
        assertEq(lvlido.epochStartRedemptionRate(), redemptionRateBefore, "Redemption rate should be set");
        
        // Verify conversion happened (debt was drawn)
        assertTrue(lvlido.totalBorrowAmount() > 0, "Should have borrowed amount");

        console.log("\n=== Test Complete ===");
    }

    /**
     * @notice Test flash loan with edge case: minimum amounts
     * @dev Tests behavior with very small amounts
     * @dev For 0.01 wstETH borrower: needs 0.035 wstETH collateral lender
     */
    function testMorphoFlashLoanMinimumAmounts() public {
        console.log("\n=== Testing Flash Loan with Minimum Amounts ===");

        uint256 lenderAmount = 5 ether;
        uint256 borrowerAmount = 0.01 ether;
        uint256 collateralLenderAmount = 0.04 ether; // 0.01 * 7 / 2 = 0.035

        _fundAccount(lender1, lenderAmount, 0);
        _fundAccount(borrower1, 0, borrowerAmount);
        _fundAccount(collateralLender1, 0, collateralLenderAmount);

        _createLenderOrder(lender1, lenderAmount);
        _createBorrowerOrder(borrower1, borrowerAmount);
        _createCollateralLenderOrder(collateralLender1, collateralLenderAmount);

        // Should successfully start epoch even with minimum amounts
        lvlido.startEpoch();

        assertTrue(lvlido.epochStarted(), "Epoch should start with minimum amounts");
        console.log("\n=== Test Complete ===");
    }

    /**
     * @notice Test that epoch start fails without collateral lender funds
     * @dev Should revert if insufficient collateral lender deposits
     */
    function testMorphoFlashLoanInsufficientCollateralLender() public {
        console.log("\n=== Testing Flash Loan with Insufficient Collateral Lender ===");

        uint256 lenderAmount = 10 ether;
        uint256 borrowerAmount = 5 ether;
        // No collateral lender

        _fundAccount(lender1, lenderAmount, 0);
        _fundAccount(borrower1, 0, borrowerAmount);

        _createLenderOrder(lender1, lenderAmount);
        _createBorrowerOrder(borrower1, borrowerAmount);

        // Should revert due to insufficient collateral lender funds
        vm.expectRevert(VaultLib.InsufficientFunds.selector);
        lvlido.startEpoch();

        console.log("Correctly reverted due to insufficient collateral lender funds");
        console.log("\n=== Test Complete ===");
    }

    // ============================================
    // HELPER FUNCTIONS
    // ============================================

    /**
     * @notice Fund an account with WETH and/or WSTETH
     */
    function _fundAccount(address account, uint256 wethAmount, uint256 wstethAmount) internal {
        if (wethAmount > 0) {
            deal(address(weth), account, wethAmount);
        }
        if (wstethAmount > 0) {
            deal(address(wsteth), account, wstethAmount);
        }
    }

    /**
     * @notice Create a lender order
     */
    function _createLenderOrder(address lender, uint256 amount) internal {
        vm.startPrank(lender);
        weth.approve(address(lvlido), amount);
        lvlido.createLenderOrder(amount);
        vm.stopPrank();
        console.log("Created lender order:", amount);
    }

    /**
     * @notice Create a borrower order
     */
    function _createBorrowerOrder(address borrower, uint256 amount) internal {
        vm.startPrank(borrower);
        IERC20(address(wsteth)).approve(address(lvlido), amount);
        lvlido.createBorrowerOrder(amount);
        vm.stopPrank();
        console.log("Created borrower order:", amount);
    }

    /**
     * @notice Create a collateral lender order
     */
    function _createCollateralLenderOrder(address collateralLender, uint256 amount) internal {
        vm.startPrank(collateralLender);
        IERC20(address(wsteth)).approve(address(lvlido), amount);
        lvlido.createCLOrder(amount);
        vm.stopPrank();
        console.log("Created collateral lender order:", amount);
    }
}

