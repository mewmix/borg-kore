// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

interface IBaseImplant {
    function BORG_SAFE() external view returns (address);
    function IMPLANT_ID() external view returns (uint256);
}