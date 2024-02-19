// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

abstract contract BaseCondition {
    function checkCondition() public virtual returns (bool);
}