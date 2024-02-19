// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./baseCondition.sol";
import "../auth.sol";


contract ConditionManager is GlobalACL {
    Condition[] private conditions;
    enum Logic { AND, OR }
    
    struct Condition {
        BaseCondition condition;
        Logic op;
    }

    constructor(Auth _auth) GlobalACL(_auth) {
        
    }

    function addCondition(Logic _op, BaseCondition _condition) public onlyOwner {
        conditions.push(Condition(_condition, _op));
    }

    function checkConditions() private returns (bool result) {
        for (uint256 i = 0; i < conditions.length; i++) {
            if (conditions[i].op == Logic.AND) {
                result = conditions[i].condition.checkCondition();
                if (!result) {
                    return false;
                }
            } else {
                result = conditions[i].condition.checkCondition();
                if (result) {
                    return true;
                }
            }
        }
        return result;
    }
}