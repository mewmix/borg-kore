// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import "../libs/auth.sol";
import "../interfaces/ICondition.sol";
import "../interfaces/IConditionManager.sol";
import "forge-std/interfaces/IERC20.sol";

contract GrantMilestones is GlobalACL {
    address public BORG_SAFE;
    address public REVOKE_CONDITIONS;
    address public RECEPIENT;

    struct Milestone {
        address token;
        uint256 tokensToUnlock;
        address[] conditionContracts;
        uint256 unlockTime;
        uint256 expiryTime;
        bool isAchieved;
    }

    Milestone[] public milestones;

    //Error Messages
    error GrantMilestones_RevokeConditionsNotMet();
    error GrantMilestones_MilestoneStartTimeNotReached();
    error GrantMilestones_MilestoneExpired();
    error GrantMilestones_MilestoneAlreadyPaid();
    error GrantMilestones_MilestoneNotAchieved();

    //May delete this version and just used the locked version..
    constructor(BorgAuth _auth, address _borgSafe) GlobalACL(_auth) {
        BORG_SAFE = _borgSafe;
    }

    modifier onlyBorgSafe() {
        require(BORG_SAFE == msg.sender, "Caller is not the BORG");
        _;
    }

    function addMilestone(address _token, uint256 _tokensToUnlock, uint256 _unlockTime, uint256 _expiryTime, address[] memory _conditionContracts) external onlyOwner {
        milestones.push(Milestone(_token, _tokensToUnlock, _conditionContracts, _unlockTime, _expiryTime, false));
    }

    function removeMilestone(uint256 _milestoneIndex) external onlyOwner {
        require(_milestoneIndex < milestones.length, "Invalid milestone index");
        milestones[_milestoneIndex] = milestones[milestones.length - 1];
        milestones.pop();
    }

function checkAndUnlockMilestone(uint256 _milestoneIndex) external {
        require(_milestoneIndex < milestones.length, "Invalid milestone index");
        Milestone storage milestone = milestones[_milestoneIndex];

        if(milestone.unlockTime > 0 && block.timestamp < milestone.unlockTime)
            revert GrantMilestones_MilestoneStartTimeNotReached();

        if(milestone.expiryTime > 0 && block.timestamp > milestone.expiryTime)
            revert GrantMilestones_MilestoneExpired();

        if(milestone.isAchieved)
            revert GrantMilestones_MilestoneAlreadyPaid();

        for(uint256 i = 0; i < milestone.conditionContracts.length; i++)
            if(!ICondition(milestone.conditionContracts[i]).checkCondition())
                revert GrantMilestones_MilestoneNotAchieved();

        milestone.isAchieved = true;

        // Execute the token transfer based on the milestone specifics
        if(milestone.token == address(0)) { // native currency transfer from this contract to receipient, not the borg_safe
            payable(RECEPIENT).transfer(milestone.tokensToUnlock);
        } else { // ERC20 token transfer
            IERC20(milestone.token).transfer(RECEPIENT, milestone.tokensToUnlock);
        }
    }

    function revokeGrant() external {
        if(!IConditionManager(REVOKE_CONDITIONS).checkConditions())
            revert GrantMilestones_RevokeConditionsNotMet();
        //Transfer the tokens back to the BORG_SAFE
        for(uint256 i = 0; i < milestones.length; i++) {
            Milestone storage milestone = milestones[i];
                if(milestone.token == address(0)) {
                    payable(BORG_SAFE).transfer(milestone.tokensToUnlock);
                } else {
                    IERC20(milestones[i].token).transfer(BORG_SAFE, milestone.tokensToUnlock);
                }
        }
    }

}