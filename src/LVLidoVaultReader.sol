// SPDX-License-Identifier: BUSL-1.1
// Author: Lendvest
pragma solidity ^0.8.20;

import {VaultLib} from "./libraries/VaultLib.sol";

interface ILVLidoVault {
    function epochToMatches(uint256 epoch, uint256 index) external view returns (VaultLib.MatchInfo memory);
    function epochToCollateralLenderOrders(uint256 epoch, uint256 index) external view returns (VaultLib.CollateralLenderOrder memory);
    function lenderOrders(uint256 index) external view returns (VaultLib.LenderOrder memory);
    function borrowerOrders(uint256 index) external view returns (VaultLib.BorrowerOrder memory);
    function collateralLenderOrders(uint256 index) external view returns (VaultLib.CollateralLenderOrder memory);
    function epochToAaveCLDeposits(uint256 epoch) external view returns (uint256);
    function userAaveCLDeposits(address user, uint256 epoch) external view returns (uint256);
    function epochToAaveLenderDeposits(uint256 epoch) external view returns (uint256);
    function getAaveBalance() external view returns (uint256);
    function getAaveBalanceQuote() external view returns (uint256);
    function totalAaveCLDeposits() external view returns (uint256);
    function totalAaveLenderDeposits() external view returns (uint256);
}

/**
 * @title LVLidoVaultReader
 * @notice Separate reader contract to reduce main vault bytecode size
 * @dev This contract contains view-only getter functions that read from LVLidoVault
 * @dev Deploy this contract separately and provide the main vault address
 */
contract LVLidoVaultReader {
    /**
     * @notice Gets the matches for a given epoch from the vault
     * @param vault The address of the LVLidoVault contract
     * @param _epoch The epoch number
     * @return An array of MatchInfo structs
     */
    function getEpochMatches(address vault, uint256 _epoch) external view returns (VaultLib.MatchInfo[] memory) {
        ILVLidoVault vaultContract = ILVLidoVault(vault);
        
        // Count how many matches exist for this epoch
        uint256 count = 0;
        bool hasMore = true;
        
        // Try to find the length by attempting to access indices until we get a revert
        while (hasMore) {
            try vaultContract.epochToMatches(_epoch, count) returns (VaultLib.MatchInfo memory) {
                count++;
            } catch {
                hasMore = false;
            }
        }
        
        // Now build the array
        VaultLib.MatchInfo[] memory matches = new VaultLib.MatchInfo[](count);
        for (uint256 i = 0; i < count; i++) {
            matches[i] = vaultContract.epochToMatches(_epoch, i);
        }
        
        return matches;
    }

    /**
     * @notice Gets the collateral lender orders for a given epoch from the vault
     * @param vault The address of the LVLidoVault contract
     * @param _epoch The epoch number
     * @return An array of CollateralLenderOrder structs
     */
    function getEpochCollateralLenderOrders(address vault, uint256 _epoch)
        external
        view
        returns (VaultLib.CollateralLenderOrder[] memory)
    {
        ILVLidoVault vaultContract = ILVLidoVault(vault);
        
        uint256 count = 0;
        bool hasMore = true;
        
        while (hasMore) {
            try vaultContract.epochToCollateralLenderOrders(_epoch, count) returns (VaultLib.CollateralLenderOrder memory) {
                count++;
            } catch {
                hasMore = false;
            }
        }
        
        VaultLib.CollateralLenderOrder[] memory orders = new VaultLib.CollateralLenderOrder[](count);
        for (uint256 i = 0; i < count; i++) {
            orders[i] = vaultContract.epochToCollateralLenderOrders(_epoch, i);
        }
        
        return orders;
    }

    /**
     * @notice Gets all lender orders from the vault
     * @param vault The address of the LVLidoVault contract
     * @return An array of LenderOrder structs
     */
    function getLenderOrders(address vault) external view returns (VaultLib.LenderOrder[] memory) {
        ILVLidoVault vaultContract = ILVLidoVault(vault);
        
        // Count orders using try-catch pattern
        uint256 count = 0;
        bool hasMore = true;
        
        while (hasMore) {
            try vaultContract.lenderOrders(count) returns (VaultLib.LenderOrder memory) {
                count++;
            } catch {
                hasMore = false;
            }
        }
        
        // Build array
        VaultLib.LenderOrder[] memory orders = new VaultLib.LenderOrder[](count);
        for (uint256 i = 0; i < count; i++) {
            orders[i] = vaultContract.lenderOrders(i);
        }
        
        return orders;
    }

    /**
     * @notice Gets a specific lender order by index from the vault
     * @param vault The address of the LVLidoVault contract
     * @param index The index of the lender order
     * @return The LenderOrder struct at the specified index
     */
    function getLenderOrder(address vault, uint256 index) external view returns (VaultLib.LenderOrder memory) {
        return ILVLidoVault(vault).lenderOrders(index);
    }

    /**
     * @notice Gets the length of the lender orders array from the vault
     * @param vault The address of the LVLidoVault contract
     * @return The number of lender orders
     */
    function getLenderOrdersLength(address vault) external view returns (uint256) {
        ILVLidoVault vaultContract = ILVLidoVault(vault);
        
        uint256 count = 0;
        bool hasMore = true;
        
        while (hasMore) {
            try vaultContract.lenderOrders(count) returns (VaultLib.LenderOrder memory) {
                count++;
            } catch {
                hasMore = false;
            }
        }
        
        return count;
    }

    /**
     * @notice Gets all borrower orders from the vault
     * @param vault The address of the LVLidoVault contract
     * @return An array of BorrowerOrder structs
     */
    function getBorrowerOrders(address vault) external view returns (VaultLib.BorrowerOrder[] memory) {
        ILVLidoVault vaultContract = ILVLidoVault(vault);
        
        // Count orders using try-catch pattern
        uint256 count = 0;
        bool hasMore = true;
        
        while (hasMore) {
            try vaultContract.borrowerOrders(count) returns (VaultLib.BorrowerOrder memory) {
                count++;
            } catch {
                hasMore = false;
            }
        }
        
        // Build array
        VaultLib.BorrowerOrder[] memory orders = new VaultLib.BorrowerOrder[](count);
        for (uint256 i = 0; i < count; i++) {
            orders[i] = vaultContract.borrowerOrders(i);
        }
        
        return orders;
    }

    /**
     * @notice Gets a specific borrower order by index from the vault
     * @param vault The address of the LVLidoVault contract
     * @param index The index of the borrower order
     * @return The BorrowerOrder struct at the specified index
     */
    function getBorrowerOrder(address vault, uint256 index) external view returns (VaultLib.BorrowerOrder memory) {
        return ILVLidoVault(vault).borrowerOrders(index);
    }

    /**
     * @notice Gets the length of the borrower orders array from the vault
     * @param vault The address of the LVLidoVault contract
     * @return The number of borrower orders
     */
    function getBorrowerOrdersLength(address vault) external view returns (uint256) {
        ILVLidoVault vaultContract = ILVLidoVault(vault);
        
        uint256 count = 0;
        bool hasMore = true;
        
        while (hasMore) {
            try vaultContract.borrowerOrders(count) returns (VaultLib.BorrowerOrder memory) {
                count++;
            } catch {
                hasMore = false;
            }
        }
        
        return count;
    }

    /**
     * @notice Gets all collateral lender orders from the vault
     * @param vault The address of the LVLidoVault contract
     * @return An array of CollateralLenderOrder structs
     */
    function getCollateralLenderOrders(address vault) external view returns (VaultLib.CollateralLenderOrder[] memory) {
        ILVLidoVault vaultContract = ILVLidoVault(vault);
        
        // Count orders using try-catch pattern
        uint256 count = 0;
        bool hasMore = true;
        
        while (hasMore) {
            try vaultContract.collateralLenderOrders(count) returns (VaultLib.CollateralLenderOrder memory) {
                count++;
            } catch {
                hasMore = false;
            }
        }
        
        // Build array
        VaultLib.CollateralLenderOrder[] memory orders = new VaultLib.CollateralLenderOrder[](count);
        for (uint256 i = 0; i < count; i++) {
            orders[i] = vaultContract.collateralLenderOrders(i);
        }
        
        return orders;
    }

    /**
     * @notice Gets a specific collateral lender order by index from the vault
     * @param vault The address of the LVLidoVault contract
     * @param index The index of the collateral lender order
     * @return The CollateralLenderOrder struct at the specified index
     */
    function getCollateralLenderOrder(address vault, uint256 index) external view returns (VaultLib.CollateralLenderOrder memory) {
        return ILVLidoVault(vault).collateralLenderOrders(index);
    }

    /**
     * @notice Gets the length of the collateral lender orders array from the vault
     * @param vault The address of the LVLidoVault contract
     * @return The number of collateral lender orders
     */
    function getCollateralLenderOrdersLength(address vault) external view returns (uint256) {
        ILVLidoVault vaultContract = ILVLidoVault(vault);
        
        uint256 count = 0;
        bool hasMore = true;
        
        while (hasMore) {
            try vaultContract.collateralLenderOrders(count) returns (VaultLib.CollateralLenderOrder memory) {
                count++;
            } catch {
                hasMore = false;
            }
        }
        
        return count;
    }

    /**
     * @notice Gets the quote amount for a specific lender order by index from the vault
     * @param vault The address of the LVLidoVault contract
     * @param index The index of the lender order
     * @return The quote amount of the lender order
     */
    function getLenderOrderQuoteAmount(address vault, uint256 index) external view returns (uint256) {
        VaultLib.LenderOrder memory order = ILVLidoVault(vault).lenderOrders(index);
        return order.quoteAmount;
    }

    /**
     * @notice Gets the collateral amount for a specific borrower order by index from the vault
     * @param vault The address of the LVLidoVault contract
     * @param index The index of the borrower order
     * @return The collateral amount of the borrower order
     */
    function getBorrowerOrderCollateralAmount(address vault, uint256 index) external view returns (uint256) {
        VaultLib.BorrowerOrder memory order = ILVLidoVault(vault).borrowerOrders(index);
        return order.collateralAmount;
    }

    /**
     * @notice Gets the collateral amount for a specific collateral lender order by index from the vault
     * @param vault The address of the LVLidoVault contract
     * @param index The index of the collateral lender order
     * @return The collateral amount of the collateral lender order
     */
    function getCollateralLenderOrderAmount(address vault, uint256 index) external view returns (uint256) {
        VaultLib.CollateralLenderOrder memory order = ILVLidoVault(vault).collateralLenderOrders(index);
        return order.collateralAmount;
    }

    /**
     * @notice Gets the total Aave CL deposits for a specific epoch from the vault
     * @param vault The address of the LVLidoVault contract
     * @param _epoch The epoch number
     * @return The total amount of CL deposits in Aave for that epoch
     */
    function getEpochAaveCLDeposits(address vault, uint256 _epoch) external view returns (uint256) {
        return ILVLidoVault(vault).epochToAaveCLDeposits(_epoch);
    }

    /**
     * @notice Gets a user's Aave CL deposit for a specific epoch from the vault
     * @param vault The address of the LVLidoVault contract
     * @param user The user address
     * @param _epoch The epoch number
     * @return The amount the user has deposited in Aave for that epoch
     */
    function getUserAaveCLDeposit(address vault, address user, uint256 _epoch) external view returns (uint256) {
        return ILVLidoVault(vault).userAaveCLDeposits(user, _epoch);
    }

    /**
     * @notice Gets the total Aave lender deposits for a specific epoch from the vault
     * @param vault The address of the LVLidoVault contract
     * @param _epoch The epoch number
     * @return The total amount of lender deposits in Aave for that epoch
     */
    function getEpochAaveLenderDeposits(address vault, uint256 _epoch) external view returns (uint256) {
        return ILVLidoVault(vault).epochToAaveLenderDeposits(_epoch);
    }

    /**
     * @notice Gets the total accrued interest from Aave across all epochs (collateral lenders)
     * @dev Calculates: current aToken balance - total deposited principal
     * @param vault The address of the LVLidoVault contract
     * @return The total interest earned but not yet withdrawn
     */
    function getTotalAaveInterestAccrued(address vault) external view returns (uint256) {
        ILVLidoVault vaultContract = ILVLidoVault(vault);
        uint256 currentBalance = vaultContract.getAaveBalance();
        uint256 totalDeposits = vaultContract.totalAaveCLDeposits();
        
        // If current balance is less than deposited (shouldn't happen), return 0
        if (currentBalance <= totalDeposits) {
            return 0;
        }
        
        return currentBalance - totalDeposits;
    }

    /**
     * @notice Gets the total accrued interest from Aave across all epochs (lenders)
     * @dev Calculates: current aToken balance - total deposited principal
     * @param vault The address of the LVLidoVault contract
     * @return The total interest earned but not yet withdrawn
     */
    function getTotalAaveInterestAccruedLender(address vault) external view returns (uint256) {
        ILVLidoVault vaultContract = ILVLidoVault(vault);
        uint256 currentBalance = vaultContract.getAaveBalanceQuote();
        uint256 totalDeposits = vaultContract.totalAaveLenderDeposits();
        
        if (currentBalance <= totalDeposits) {
            return 0;
        }
        
        return currentBalance - totalDeposits;
    }



}

