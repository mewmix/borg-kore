// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import "../interfaces/ISafe.sol";
import "../libs/auth.sol";
import "../utils/lockedGrantMilestones.sol";

contract optimisticGrantImplant is GlobalACL { //is baseImplant

    address public immutable BORG_SAFE;

    uint256 public grantCountLimit;
    uint256 public currentGrantCount;
    uint256 public grantTimeLimit;
    bool allowOwners;

    struct approvedGrantToken { 
        uint256 spendingLimit;
        uint256 amountSpent;
    }

    error optimisticGrantImplant_invalidToken();
    error optimisticGrantImplant_GrantCountLimitReached();
    error optimisticGrantImplant_GrantTimeLimitReached();
    error optimisticGrantImplant_GrantSpendingLimitReached();
    error optimisticGrantImplant_CallerNotBORGMember();
    error optimisticGrantImplant_CallerNotBORG();

    mapping(address => approvedGrantToken) public approvedGrantTokens;

    constructor(Auth _auth, address _borgSafe) GlobalACL(_auth) {
        BORG_SAFE = _borgSafe;
        allowOwners = false;
    }

    function updateApprovedGrantToken(address _token, uint256 _spendingLimit) external onlyOwner {
        approvedGrantTokens[_token] = approvedGrantToken(_spendingLimit, 0);
    }

    function removeApprovedGrantToken(address _token) external onlyOwner {
        approvedGrantTokens[_token] = approvedGrantToken(0, 0);
    }

    function setGrantLimits(uint256 _grantCountLimit, uint256 _grantTimeLimit) external onlyOwner {
        grantCountLimit = _grantCountLimit;
        grantTimeLimit = _grantTimeLimit;
        currentGrantCount = 0;
    }

    function toggleAllowOwners(bool _allowOwners) external onlyOwner {
        allowOwners = _allowOwners;
    }

    function createGrant(address _token, address _recipient, uint256 _amount) external {
        if(currentGrantCount >= grantCountLimit)
            revert optimisticGrantImplant_GrantCountLimitReached();
        if(block.timestamp >= grantTimeLimit)
            revert optimisticGrantImplant_GrantTimeLimitReached();
        
        if(allowOwners) {
            if(!ISafe(BORG_SAFE).isOwner(msg.sender))
                revert optimisticGrantImplant_CallerNotBORGMember();
        }
        else {
            if(BORG_SAFE != msg.sender)
                revert optimisticGrantImplant_CallerNotBORG();
         }

        approvedGrantToken storage approvedToken = approvedGrantTokens[_token];
        if (approvedToken.spendingLimit == 0) {
            revert optimisticGrantImplant_invalidToken();
        }
        if(approvedToken.amountSpent + _amount > approvedToken.spendingLimit)
            revert optimisticGrantImplant_GrantSpendingLimitReached();
        approvedToken.amountSpent += _amount;
        currentGrantCount++;
        if(_token==address(0))
            ISafe(BORG_SAFE).execTransactionFromModule(_recipient, _amount, "", Enum.Operation.Call);
        else
            ISafe(BORG_SAFE).execTransactionFromModule(_token, 0, abi.encodeWithSignature("transfer(address,uint256)", _recipient, _amount), Enum.Operation.Call);
    }


    function createMilestoneGrant(address _recipient, address _revokeConditions, GrantMilestones.Milestone[] memory _milestones) external {

        if(currentGrantCount >= grantCountLimit)
            revert optimisticGrantImplant_GrantCountLimitReached();
        if(block.timestamp >= grantTimeLimit)
            revert optimisticGrantImplant_GrantTimeLimitReached();

        GrantMilestones grantMilestones = new GrantMilestones(_recipient, BORG_SAFE, _revokeConditions, _milestones);
        
        if(allowOwners) {
            if(!ISafe(BORG_SAFE).isOwner(msg.sender))
                revert optimisticGrantImplant_CallerNotBORGMember();
        }
        else {
            if(BORG_SAFE != msg.sender)
                revert optimisticGrantImplant_CallerNotBORG();
         }

        for (uint256 i = 0; i < _milestones.length; i++) {
            approvedGrantToken storage approvedToken = approvedGrantTokens[_milestones[i].token];
            if (approvedToken.spendingLimit == 0) {
                revert optimisticGrantImplant_invalidToken();
            }
            
            if(approvedToken.amountSpent + _milestones[i].tokensToUnlock > approvedToken.spendingLimit)
                revert optimisticGrantImplant_GrantSpendingLimitReached();

            approvedToken.amountSpent += _milestones[i].tokensToUnlock;
            currentGrantCount++;
            if(_milestones[i].token==address(0))
                ISafe(BORG_SAFE).execTransactionFromModule(address(grantMilestones), _milestones[i].tokensToUnlock, "", Enum.Operation.Call);
            else
                ISafe(BORG_SAFE).execTransactionFromModule(_milestones[i].token, 0, abi.encodeWithSignature("transfer(address,uint256)", address(grantMilestones), _milestones[i].tokensToUnlock), Enum.Operation.Call);
        }
    }


}
