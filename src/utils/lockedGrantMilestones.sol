// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../interfaces/ISafe.sol";
import "../libs/auth.sol";
import "../interfaces/ICondition.sol";
import "../interfaces/IConditionManager.sol";

contract GrantMilestones {
    address public immutable BORG_SAFE;
    address public immutable REVOKE_CONDITIONS;

    struct Milestone {
        address token;
        uint256 tokensToUnlock;
        address[] conditionContracts;
        bool isAchieved;
    }

    Milestone[] public milestones;

    //Error Messages
    error GrantMilestones_RevokeConditionsNotMet();

    constructor(address _borgSafe, address _revokeConditions, Milestone[] memory _milestones) {
        BORG_SAFE = _borgSafe;
        REVOKE_CONDITIONS = _revokeConditions;
        milestones = _milestones;
    }

    modifier onlyBorgSafe() {
        require(BORG_SAFE == msg.sender, "Caller is not the BORG");
        _;
    }

    function checkAndUnlockMilestone(uint256 _milestoneIndex) external {
        require(_milestoneIndex < milestones.length, "Invalid milestone index");
        Milestone storage milestone = milestones[_milestoneIndex];

        require(!milestone.isAchieved, "Milestone already achieved");
        for(uint256 i = 0; i < milestone.conditionContracts.length; i++)
            require(ICondition(milestone.conditionContracts[i]).checkCondition(), "Milestone condition not satisfied");

        milestone.isAchieved = true;

        // Execute the token transfer based on the milestone specifics
        if(milestone.token == address(0)) { // native currency transfer
            ISafe(BORG_SAFE).execTransactionFromModule(msg.sender, milestone.tokensToUnlock, "", Enum.Operation.Call);
        } else { // ERC20 token transfer
            ISafe(BORG_SAFE).execTransactionFromModule(milestone.token, 0, abi.encodeWithSignature("transfer(address,uint256)", msg.sender, milestone.tokensToUnlock), Enum.Operation.Call);
        }
    }

    function revokeGrant() external {
        if(!IConditionManager(REVOKE_CONDITIONS).checkConditions())
            revert GrantMilestones_RevokeConditionsNotMet();
        //Transfer the tokens back to the BORG_SAFE
        for(uint256 i = 0; i < milestones.length; i++) {
                if(milestones[i].token == address(0)) {
                    ISafe(BORG_SAFE).execTransactionFromModule(msg.sender, milestones[i].tokensToUnlock, "", Enum.Operation.Call);
                } else {
                    ISafe(BORG_SAFE).execTransactionFromModule(milestones[i].token, 0, abi.encodeWithSignature("transfer(address,uint256)", BORG_SAFE, milestones[i].tokensToUnlock), Enum.Operation.Call);
                }
        }
    }
}