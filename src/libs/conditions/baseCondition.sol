// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

abstract contract BaseCondition {
    function checkCondition() public virtual returns (bool);
}
