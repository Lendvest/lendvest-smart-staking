// SPDX-License-Identifier: BUSL-1.1
// Author: Lendvest

pragma solidity ^0.8.20;

interface ILiquidationProxy {
    function setAllowKick(bool _allowKick) external;
    function allowKick() external view returns (bool);
}
