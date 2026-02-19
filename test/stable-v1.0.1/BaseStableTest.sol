// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {LVLidoVault} from "../../src/LVLidoVault.sol";
import {LVLidoVaultUtil} from "../../src/LVLidoVaultUtil.sol";
import {LiquidationProxy} from "../../src/LiquidationProxy.sol";
import {LVToken} from "../../src/LVToken.sol";
import {VaultLib} from "../../src/libraries/VaultLib.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Pool} from "../../src/interfaces/pool/erc20/IERC20Pool.sol";
import {IERC20PoolFactory} from "../../src/interfaces/pool/erc20/IERC20PoolFactory.sol";
import {IWeth} from "../../src/interfaces/vault/IWeth.sol";
import {IWsteth} from "../../src/interfaces/vault/IWsteth.sol";
import {IPoolInfoUtils} from "../../src/interfaces/IPoolInfoUtils.sol";
import {TestHelpers} from "../TestHelpers.t.sol";

/**
 * @title BaseStableTest
 * @notice Shared setup for all stable-v1.0.1 test contracts
 */
abstract contract BaseStableTest is Test, TestHelpers {
    LVToken internal lvweth;
    IERC20 internal weth;
    IWsteth internal wsteth;
    LVToken internal lvwsteth;
    LVLidoVault internal vault;
    LiquidationProxy internal liquidationProxy;
    IERC20Pool internal ajnaPool;
    LVLidoVaultUtil internal vaultUtil;

    address public constant POOL_FACTORY_ADDRESS = 0x6146DD43C5622bB6D12A5240ab9CF4de14eDC625;
    address internal owner = 0x6f33D099880D4b08AAd6B80c26423ec138318520;
    address internal forwarder = makeAddr("forwarder");
    address internal lender1 = makeAddr("lender1");
    address internal borrower1 = makeAddr("borrower1");
    address internal collateralLender1 = makeAddr("collateralLender1");

    function setUp() public virtual {
        vm.startPrank(owner);

        weth = IERC20(WETH_ADDRESS);
        wsteth = IWsteth(WSTETH_ADDRESS);

        lvweth = new LVToken("LV WETH", "LVWETH");
        lvwsteth = new LVToken("LV WSTETH", "LVWSTETH");

        IERC20PoolFactory poolFactory = IERC20PoolFactory(POOL_FACTORY_ADDRESS);
        address ajnaPoolAddress = poolFactory.deployPool(
            address(lvwsteth),
            address(lvweth),
            100000000000000000
        );
        ajnaPool = IERC20Pool(ajnaPoolAddress);

        liquidationProxy = new LiquidationProxy(ajnaPoolAddress);
        vault = new LVLidoVault(ajnaPoolAddress, address(liquidationProxy));
        vaultUtil = new LVLidoVaultUtil(address(vault));

        vault.setLVLidoVaultUtilAddress(address(vaultUtil));
        liquidationProxy.setLVLidoVault(address(vault));

        lvwsteth.transferOwnership(address(vault));
        lvweth.transferOwnership(address(vault));
        liquidationProxy.transferOwnership(address(vault));

        vaultUtil.setForwarderAddress(forwarder);

        vm.stopPrank();

        // Skip deployment cooldown
        vm.warp(vault.deploymentTimestamp() + 72 hours);
    }

    function _fundLender(address lender, uint256 amount) internal {
        deal(WETH_ADDRESS, lender, amount);
        vm.startPrank(lender);
        IERC20(WETH_ADDRESS).approve(address(vault), amount);
        vault.createLenderOrder(amount);
        vm.stopPrank();
    }

    function _fundBorrower(address borrower, uint256 amount) internal {
        deal(WSTETH_ADDRESS, borrower, amount);
        vm.startPrank(borrower);
        IERC20(WSTETH_ADDRESS).approve(address(vault), amount);
        vault.createBorrowerOrder(amount);
        vm.stopPrank();
    }

    function _fundCollateralLender(address cl, uint256 amount) internal {
        deal(WSTETH_ADDRESS, cl, amount);
        vm.startPrank(cl);
        IERC20(WSTETH_ADDRESS).approve(address(vault), amount);
        vault.createCLOrder(amount);
        vm.stopPrank();
    }

    /**
     * @notice Creates balanced orders that will successfully match
     * @dev Uses larger amounts to avoid slippage issues in ETH→stETH→wstETH conversion
     *      during the Morpho flash loan callback
     */
    function _setupBalancedOrders() internal {
        _fundLender(lender1, 10 ether);
        _fundBorrower(borrower1, 5 ether);
        _fundCollateralLender(collateralLender1, 5 ether);
    }

    /**
     * @notice Starts an epoch with balanced orders
     * @dev Helper for tests that need an active epoch
     */
    function _startBalancedEpoch() internal {
        _setupBalancedOrders();
        // Set flash loan fee threshold to allow some slippage
        vm.prank(owner);
        vault.setMaxFlashLoanFeeThreshold(100, 0);
        vm.prank(owner);
        vault.startEpoch();
    }
}
