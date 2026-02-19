// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @notice all information about an upkeep
 * @dev only used in return values
 * @member target the contract which needs to be serviced
 * @member executeGas the gas limit of upkeep execution
 * @member checkData the checkData bytes for this upkeep
 * @member balance the balance of this upkeep
 * @member admin for this upkeep
 * @member maxValidBlocknumber until which block this upkeep is valid
 * @member lastPerformBlockNumber the last block number when this upkeep was performed
 * @member amountSpent the amount this upkeep has spent
 * @member paused if this upkeep has been paused
 * @member skipSigVerification skip signature verification in transmit for a low security low cost model
 */
struct UpkeepInfo {
    address target;
    uint32 executeGas;
    bytes checkData;
    uint96 balance;
    address admin;
    uint64 maxValidBlocknumber;
    uint32 lastPerformBlockNumber;
    uint96 amountSpent;
    bool paused;
    bytes offchainConfig;
}

interface IRegistry {
    function getUpkeep(uint256 id) external view returns (UpkeepInfo memory upkeepInfo);
    function acceptUpkeepAdmin(uint256 id) external;
    function addFunds(uint256 id, uint96 amount) external;
}

contract UpkeepAdmin {
    IRegistry public registry;
    IERC20 public linkToken;

    constructor(address _registry, address _linkToken) {
        registry = IRegistry(_registry);
        linkToken = IERC20(_linkToken);
    }

    function acceptUpkeepAdmin(uint256 id) external {
        registry.acceptUpkeepAdmin(id);
    }

    function transferLinkToken(uint256 id, uint96 amount) external {
        require(
            linkToken.transferFrom(msg.sender, address(this), amount) && linkToken.approve(address(registry), amount),
            "LINK transfer failed."
        );
        registry.addFunds(id, amount);
    }

    function getUpkeep(uint256 id) external view returns (UpkeepInfo memory upkeepInfo) {
        upkeepInfo = registry.getUpkeep(id);
    }
}
