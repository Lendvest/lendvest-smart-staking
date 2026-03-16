// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {LVLidoVault} from "../src/LVLidoVault.sol";
import {LVLidoVaultUtil} from "../src/LVLidoVaultUtil.sol";
import {LVLidoVaultReader} from "../src/LVLidoVaultReader.sol";
import {LiquidationProxy} from "../src/LiquidationProxy.sol";
import {LVToken} from "../src/LVToken.sol";
import {VaultLib} from "../src/libraries/VaultLib.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Pool} from "../src/interfaces/pool/erc20/IERC20Pool.sol";
import {IPoolInfoUtils} from "../src/interfaces/IPoolInfoUtils.sol";

/**
 * @title MainnetDeployedTest
 * @notice Tests against the actual deployed mainnet contracts
 * @dev Uses addresses from README.md - Ethereum Mainnet deployments
 */
contract MainnetDeployedTest is Test {
    // Deployed contract addresses from README.md
    LVLidoVault public vault = LVLidoVault(payable(0xe3C272F793d32f4a885e4d748B8E5968f515c8D6));
    LVLidoVaultUtil public vaultUtil = LVLidoVaultUtil(0x5f01bc229629342f1B94c4a84C43f30eF8ef76Fe);
    LVLidoVaultReader public vaultReader = LVLidoVaultReader(0x4e66D9073AA97b9BCEa5f0123274f22aE42229FC);
    LiquidationProxy public liquidationProxy = LiquidationProxy(payable(0x5f113C3977d633859C1966E95a4Ec542f594365c));
    LVToken public lvweth = LVToken(0x1745D52b537b9e2DC46CeeDD7375614b3D91CB8C);
    LVToken public lvwsteth = LVToken(0xEFe6E493184F48b5f5533a827C9b4A6b4fFC09dE);
    IERC20Pool public ajnaPool = IERC20Pool(0x4bb3e528dd71fc268fCb5AE7A19C88f9d4A85caC);

    // External protocol addresses
    address public constant WETH_ADDRESS = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant WSTETH_ADDRESS = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address public constant POOL_INFO_UTILS = 0x30c5eF2997d6a882DE52c4ec01B6D0a5e5B4fAAE;

    IPoolInfoUtils public poolInfoUtils = IPoolInfoUtils(POOL_INFO_UTILS);
    IERC20 public weth = IERC20(WETH_ADDRESS);
    IERC20 public wsteth = IERC20(WSTETH_ADDRESS);

    function setUp() public {
        // No setup needed - we're using deployed contracts
    }

    // ============ Contract Existence Tests ============

    function test_VaultIsDeployed() public view {
        uint256 codeSize;
        address vaultAddr = address(vault);
        assembly {
            codeSize := extcodesize(vaultAddr)
        }
        assertGt(codeSize, 0, "Vault contract should exist");
        console.log("LVLidoVault code size:", codeSize);
    }

    function test_VaultUtilIsDeployed() public view {
        uint256 codeSize;
        address utilAddr = address(vaultUtil);
        assembly {
            codeSize := extcodesize(utilAddr)
        }
        assertGt(codeSize, 0, "VaultUtil contract should exist");
        console.log("LVLidoVaultUtil code size:", codeSize);
    }

    function test_LiquidationProxyIsDeployed() public view {
        uint256 codeSize;
        address proxyAddr = address(liquidationProxy);
        assembly {
            codeSize := extcodesize(proxyAddr)
        }
        assertGt(codeSize, 0, "LiquidationProxy contract should exist");
        console.log("LiquidationProxy code size:", codeSize);
    }

    // ============ Contract Configuration Tests ============

    function test_VaultConfiguration() public view {
        console.log("=== Vault Configuration ===");

        // Check epoch
        uint256 currentEpoch = vault.epoch();
        console.log("Current epoch:", currentEpoch);

        // Check epoch status
        bool isEpochStarted = vault.epochStarted();
        bool isFundsQueued = vault.fundsQueued();
        console.log("Epoch started:", isEpochStarted);
        console.log("Funds queued:", isFundsQueued);

        // Check linked contracts
        address utilAddress = vault.LVLidoVaultUtil();
        console.log("VaultUtil address:", utilAddress);
        assertEq(utilAddress, address(vaultUtil), "VaultUtil address mismatch");
    }

    function test_VaultUtilConfiguration() public view {
        console.log("=== VaultUtil Configuration ===");

        // Check linked vault
        address linkedVault = address(vaultUtil.LVLidoVault());
        console.log("Linked vault:", linkedVault);
        assertEq(linkedVault, address(vault), "Vault address mismatch in VaultUtil");
    }

    function test_LiquidationProxyConfiguration() public view {
        console.log("=== LiquidationProxy Configuration ===");

        // Check linked vault
        address linkedVault = address(liquidationProxy.LVLidoVault());
        console.log("Linked vault:", linkedVault);
        assertEq(linkedVault, address(vault), "Vault address mismatch in LiquidationProxy");
    }

    function test_TokenConfiguration() public view {
        console.log("=== Token Configuration ===");

        // Governance multisig (as per README: Token ownership held by a 3-of-5 governance multisig)
        address governanceMultisig = 0x3F0976C7007F50b0BA5EFe00764fCFB251656D4f;

        // LVWETH
        console.log("LVWETH name:", lvweth.name());
        console.log("LVWETH symbol:", lvweth.symbol());
        console.log("LVWETH owner:", lvweth.owner());
        assertEq(lvweth.owner(), governanceMultisig, "LVWETH owner should be governance multisig");

        // LVWSTETH
        console.log("LVWSTETH name:", lvwsteth.name());
        console.log("LVWSTETH symbol:", lvwsteth.symbol());
        console.log("LVWSTETH owner:", lvwsteth.owner());
        assertEq(lvwsteth.owner(), governanceMultisig, "LVWSTETH owner should be governance multisig");
    }

    // ============ State Reading Tests ============

    function test_ReadCurrentEpochState() public view {
        console.log("=== Current Epoch State ===");

        uint256 epoch = vault.epoch();
        console.log("Epoch:", epoch);

        // Queue lengths
        uint256 lenderOrders = vault.getLenderOrdersLength();
        uint256 borrowerOrders = vault.getBorrowerOrdersLength();
        uint256 clOrders = vault.getCollateralLenderOrdersLength();

        console.log("Pending lender orders:", lenderOrders);
        console.log("Pending borrower orders:", borrowerOrders);
        console.log("Pending CL orders:", clOrders);

        // Totals
        console.log("Total lender QT unutilized:", vault.totalLenderQTUnutilized());
        console.log("Total borrower CT:", vault.totalBorrowerCT());
        console.log("Total CL CT:", vault.totalCollateralLenderCT());
    }

    function test_ReadAjnaPoolState() public view {
        console.log("=== Ajna Pool State ===");

        // Pool info
        uint256 depositSize = ajnaPool.depositSize();
        console.log("Pool deposit size:", depositSize);

        // Vault position in pool
        (uint256 debt, uint256 collateral, uint256 npTpRatio) = ajnaPool.borrowerInfo(address(vault));
        console.log("Vault debt:", debt);
        console.log("Vault collateral:", collateral);
        console.log("Vault npTpRatio:", npTpRatio);

        // Pool utilization
        if (depositSize > 0) {
            uint256 utilization = (debt * 1e18) / depositSize;
            console.log("Pool utilization (1e18):", utilization);
        }
    }

    function test_ReadVaultBalances() public view {
        console.log("=== Vault Token Balances ===");

        uint256 vaultWeth = weth.balanceOf(address(vault));
        uint256 vaultWsteth = wsteth.balanceOf(address(vault));

        console.log("Vault WETH balance:", vaultWeth);
        console.log("Vault wstETH balance:", vaultWsteth);
    }

    // ============ Integration Tests ============

    function test_VaultReaderIntegration() public view {
        console.log("=== Vault Reader Integration ===");

        // Test reader can access vault state (reader takes vault address as parameter)
        // Get all lender orders through reader
        VaultLib.LenderOrder[] memory orders = vaultReader.getLenderOrders(address(vault));
        console.log("Lender orders via reader:", orders.length);

        // Get all borrower orders
        VaultLib.BorrowerOrder[] memory bOrders = vaultReader.getBorrowerOrders(address(vault));
        console.log("Borrower orders via reader:", bOrders.length);

        // Get all CL orders
        VaultLib.CollateralLenderOrder[] memory clOrders = vaultReader.getCollateralLenderOrders(address(vault));
        console.log("CL orders via reader:", clOrders.length);
    }

    function test_AjnaPoolIntegration() public view {
        console.log("=== Ajna Pool Integration ===");

        // Verify pool tokens match
        address poolCollateral = ajnaPool.collateralAddress();
        address poolQuote = ajnaPool.quoteTokenAddress();

        console.log("Pool collateral token:", poolCollateral);
        console.log("Pool quote token:", poolQuote);

        assertEq(poolCollateral, address(lvwsteth), "Pool collateral should be LVWSTETH");
        assertEq(poolQuote, address(lvweth), "Pool quote should be LVWETH");
    }

    // ============ Historical Epoch Tests ============

    function test_ReadHistoricalEpochData() public view {
        uint256 currentEpoch = vault.epoch();
        console.log("=== Historical Epoch Data ===");
        console.log("Current epoch:", currentEpoch);

        if (currentEpoch > 0) {
            // Read data from previous epochs
            for (uint256 i = 1; i <= currentEpoch && i <= 3; i++) {
                console.log("--- Epoch", i, "---");

                VaultLib.MatchInfo[] memory matches = vault.getEpochMatches(i);
                console.log("Number of matches:", matches.length);

                if (matches.length > 0) {
                    console.log("First match quote amount:", matches[0].quoteAmount);
                    console.log("First match collateral:", matches[0].collateralAmount);
                }
            }
        }
    }

    // ============ Access Control Tests ============

    function test_OwnershipConfiguration() public view {
        console.log("=== Ownership Configuration ===");

        address vaultOwner = vault.owner();
        address utilOwner = vaultUtil.owner();
        address proxyOwner = liquidationProxy.owner();

        console.log("Vault owner:", vaultOwner);
        console.log("VaultUtil owner:", utilOwner);
        console.log("LiquidationProxy owner:", proxyOwner);

        // Tokens should be owned by vault
        console.log("LVWETH owner:", lvweth.owner());
        console.log("LVWSTETH owner:", lvwsteth.owner());
    }

    // ============ Emergency State Tests ============

    function test_EmergencyStateCheck() public view {
        console.log("=== Emergency State Check ===");

        // Check epoch emergency state
        uint256 currentEpoch = vault.epoch();
        if (currentEpoch > 0) {
            bool emergencyLenderWithdrawn = vault.epochEmergencyLenderWithdrawn(currentEpoch);
            bool emergencyCLWithdrawn = vault.epochEmergencyCLWithdrawn(currentEpoch);
            console.log("Emergency lender withdrawn:", emergencyLenderWithdrawn);
            console.log("Emergency CL withdrawn:", emergencyCLWithdrawn);
        }

        // Check if there are any pending liquidations
        (address kicker,,, uint256 kickTime,,,,,,) = ajnaPool.auctionInfo(address(vault));
        bool hasActiveAuction = kicker != address(0);
        console.log("Has active auction:", hasActiveAuction);
        if (hasActiveAuction) {
            console.log("Auction kicker:", kicker);
            console.log("Auction kick time:", kickTime);
        }
    }
}
