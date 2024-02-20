// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../../interfaces/ICondition.sol";
import "../auth.sol";


contract ConditionManager is GlobalACL {
    Condition[] private conditions;
    enum Logic { AND, OR } 
    Logic public logic;
    
    struct Condition {
        address condition;
        Logic op;
    }

    constructor(Auth _auth) GlobalACL(_auth) {
        
    }

    function addCondition(Logic _op, address _condition) public onlyOwner {
        conditions.push(Condition(_condition, _op));
    }

    function checkConditions() public returns (bool result) {
        if(conditions.length == 0) 
            return true;
        
        for (uint256 i = 0; i < conditions.length; i++) {
            if (conditions[i].op == Logic.AND) {
                result = ICondition(conditions[i].condition).checkCondition();
                if (!result) {
                    return false;
                }
            } else {
                result = ICondition(conditions[i].condition).checkCondition();
                if (result) {
                    return true;
                }
            }
        }
        return result;
    }
}