// SPDX-License-Identifier: BUSL-1.1
// Author: Lendvest

pragma solidity ^0.8.20;

interface IWeth {
    function withdraw(uint256 amount) external;
    function deposit() external payable;
}
