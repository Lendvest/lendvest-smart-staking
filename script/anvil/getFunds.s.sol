// SPDX-License-Identifier: MIT
/*
  forge script script/anvil/getFunds.s.sol:GetFunds --rpc-url http://127.0.0.1:8545 --broadcast --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
*/
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IWsteth} from "../../src/interfaces/vault/IWsteth.sol";
import {IWeth} from "../../src/interfaces/vault/IWeth.sol";
import {ISteth} from "../../src/interfaces/vault/ISteth.sol";

contract GetFunds is Script {
    // Ethereum Mainnet Addresses
    address public constant WSTETH_ADDRESS = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address public constant WETH_ADDRESS = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant STETH_ADDRESS = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;

    IWeth public weth;
    IWsteth public wsteth;
    ISteth public steth;

    // Amounts to convert (example: 1 ETH to WETH, 1 ETH to wstETH)
    uint256 public constant WETH_AMOUNT = 20 ether;

    function run() public {
        vm.startBroadcast();

        weth = IWeth(WETH_ADDRESS);
        wsteth = IWsteth(WSTETH_ADDRESS);
        steth = ISteth(STETH_ADDRESS);

        // Convert ETH to WETH
        weth.deposit{value: WETH_AMOUNT}();
        uint256 shares = steth.submit{value: WETH_AMOUNT}(address(0));
        uint256 stethReceived = steth.getPooledEthByShares(shares);
        IERC20(STETH_ADDRESS).approve(address(wsteth), stethReceived);
        wsteth.wrap(stethReceived);

        vm.stopBroadcast();
    }

    // Allow contract to receive ETH
    receive() external payable {}
}
