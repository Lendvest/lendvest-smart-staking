// SPDX-License-Identifier: BUSL-1.1
// Author: Lendvest

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title LVToken
 * @notice ERC20 token with allowlist-based mint/burn access control.
 * @dev The owner can grant/revoke mint+burn access to multiple addresses.
 *      The owner themselves always have mint+burn access.
 *      This allows both the vault AND an admin to mint/burn,
 *      so the admin can rescue stuck funds if needed.
 */
contract LVToken is ERC20, Ownable {
    mapping(address => bool) public allowed;

    event AllowedUpdated(address indexed account, bool status);

    constructor(string memory name, string memory symbol) ERC20(name, symbol) Ownable(msg.sender) {}

    modifier onlyAllowed() {
        require(allowed[msg.sender] || msg.sender == owner(), "Not allowed");
        _;
    }

    /**
     * @notice Grant or revoke mint/burn access for an address
     * @param addr The address to update
     * @param status True to grant access, false to revoke
     */
    function setAllowed(address addr, bool status) external onlyOwner {
        allowed[addr] = status;
        emit AllowedUpdated(addr, status);
    }

    /**
     * @dev Mint new tokens. Callable by owner or allowed addresses.
     */
    function mint(address to, uint256 amount) public onlyAllowed returns (bool) {
        _mint(to, amount);
        return true;
    }

    /**
     * @dev Burn tokens. Callable by owner or allowed addresses.
     */
    function burn(address from, uint256 amount) public onlyAllowed returns (bool) {
        _burn(from, amount);
        return true;
    }
}
