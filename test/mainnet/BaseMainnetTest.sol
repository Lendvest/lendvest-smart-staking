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
import {IWeth} from "../../src/interfaces/vault/IWeth.sol";
import {IWsteth} from "../../src/interfaces/vault/IWsteth.sol";
import {IPoolInfoUtils} from "../../src/interfaces/IPoolInfoUtils.sol";
import {ILidoWithdrawal} from "../../src/interfaces/vault/ILidoWithdrawal.sol";
import {TestHelpers} from "../TestHelpers.t.sol";

/**
 * @title BaseMainnetTest
 * @notice Base test that uses deployed mainnet contracts from README.md
 * @dev All tests extending this will run against actual deployed contracts
 */
abstract contract BaseMainnetTest is Test, TestHelpers {
    // Deployed contract addresses from README.md
    LVToken internal lvweth;
    IERC20 internal weth;
    IWsteth internal wsteth;
    LVToken internal lvwsteth;
    LVLidoVault internal vault;
    LiquidationProxy internal liquidationProxy;
    IERC20Pool internal ajnaPool;
    LVLidoVaultUtil internal vaultUtil;

    // Deployed addresses from README.md
    address public constant DEPLOYED_VAULT = 0xe3C272F793d32f4a885e4d748B8E5968f515c8D6;
    address public constant DEPLOYED_VAULT_UTIL = 0x5f01bc229629342f1B94c4a84C43f30eF8ef76Fe;
    address public constant DEPLOYED_LIQUIDATION_PROXY = 0x5f113C3977d633859C1966E95a4Ec542f594365c;
    address public constant DEPLOYED_LVWETH = 0x1745D52b537b9e2DC46CeeDD7375614b3D91CB8C;
    address public constant DEPLOYED_LVWSTETH = 0xEFe6E493184F48b5f5533a827C9b4A6b4fFC09dE;
    address public constant DEPLOYED_AJNA_POOL = 0x4bb3e528dd71fc268fCb5AE7A19C88f9d4A85caC;

    // Actual owner of deployed contracts
    address internal owner = 0x439dEAD08d45811d9eE380e58161BAA87F7e8757;
    // Governance multisig (token owner)
    address internal governanceMultisig = 0x3F0976C7007F50b0BA5EFe00764fCFB251656D4f;

    address internal forwarder = makeAddr("forwarder");
    address internal lender1 = makeAddr("lender1");
    address internal borrower1 = makeAddr("borrower1");
    address internal collateralLender1 = makeAddr("collateralLender1");

    function setUp() public virtual {
        // Use deployed contracts
        vault = LVLidoVault(payable(DEPLOYED_VAULT));
        vaultUtil = LVLidoVaultUtil(DEPLOYED_VAULT_UTIL);
        liquidationProxy = LiquidationProxy(payable(DEPLOYED_LIQUIDATION_PROXY));
        lvweth = LVToken(DEPLOYED_LVWETH);
        lvwsteth = LVToken(DEPLOYED_LVWSTETH);
        ajnaPool = IERC20Pool(DEPLOYED_AJNA_POOL);

        weth = IERC20(WETH_ADDRESS);
        wsteth = IWsteth(WSTETH_ADDRESS);

        // Note: Don't override the forwarder on mainnet deployed contracts
        // The forwarder is already set correctly for production use
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
     */
    function _setupBalancedOrders() internal {
        _fundLender(lender1, 10 ether);
        _fundBorrower(borrower1, 5 ether);
        _fundCollateralLender(collateralLender1, 5 ether);
    }

    /**
     * @notice Starts an epoch with balanced orders
     */
    function _startBalancedEpoch() internal {
        _setupBalancedOrders();
        vm.prank(owner);
        vaultUtil.setMaxFlashLoanFeeThreshold(100, 0);
        vm.prank(owner);
        vault.startEpoch();
    }
}
