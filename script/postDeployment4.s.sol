// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {LVLidoVault} from "../src/LVLidoVault.sol";
import {LVToken} from "../src/LVToken.sol";
import {LiquidationProxy} from "../src/LiquidationProxy.sol";

contract OwnershipTransfer1 is Script {
    function run() public {
        vm.startBroadcast();

        // First cast to payable address, then to contract
        address payable lvlidoAddress = payable(0xC4c52D111d1CFd0D7Fc4a336C931F41EeF1f1456);
        LVLidoVault lvlido = LVLidoVault(lvlidoAddress);

        address lvtokenAddress = 0x2a6C668E0daBcbf7579b06d8955315A8B48494D5;
        LVToken lvtoken = LVToken(lvtokenAddress);
        lvtoken.transferOwnership(address(lvlido));

        address lvtokenAddress2 = 0x87394fdE469B13B04706EaB79c0AE2B25DE63345;
        LVToken lvtoken2 = LVToken(lvtokenAddress2);
        lvtoken2.transferOwnership(address(lvlido));

        address liquidationProxyAddress =  0xc48A0491a1A08975885B6949dfddFd49C4BFB13B;
        LiquidationProxy liquidationProxy = LiquidationProxy(liquidationProxyAddress);
        liquidationProxy.transferOwnership(address(lvlido));

        vm.stopBroadcast();
    }
}
