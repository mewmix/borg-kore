// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import "../interfaces/ISafe.sol";
import "../libs/auth.sol";
import "metavest/MetaVesT.sol";
import "metavest/MetaVesTController.sol";

contract optimisticGrantImplant is GlobalACL { //is baseImplant

    address public immutable BORG_SAFE;
    uint256 public immutable IMPLANT_ID = 2;
    uint256 public grantCountLimit;
    uint256 public currentGrantCount;
    uint256 public grantTimeLimit;
    MetaVesT public metaVesT;
    MetaVesTController public metaVesTController;
    bool allowOwners;

    struct approvedGrantToken { 
        uint256 spendingLimit;
        uint256 maxPerGrant;
        uint256 amountSpent;
    }

    //automatic refresh let's make this a option //auto refresh
    //stop 
    
    error optimisticGrantImplant_invalidToken();
    error optimisticGrantImplant_GrantCountLimitReached();
    error optimisticGrantImplant_GrantTimeLimitReached();
    error optimisticGrantImplant_GrantSpendingLimitReached();
    error optimisticGrantImplant_CallerNotBORGMember();
    error optimisticGrantImplant_CallerNotBORG();

    mapping(address => approvedGrantToken) public approvedGrantTokens;

    constructor(Auth _auth, address _borgSafe, address _metaVest, address _metaVestController) GlobalACL(_auth) {
        BORG_SAFE = _borgSafe;
        allowOwners = false;
        metaVesT = MetaVesT(_metaVest);
        metaVesTController = MetaVesTController(_metaVestController);
    }

    function updateApprovedGrantToken(address _token, uint256 _spendingLimit) external onlyOwner {
        approvedGrantTokens[_token] = approvedGrantToken(_spendingLimit, 0, 0);
    }

    function removeApprovedGrantToken(address _token) external onlyOwner {
        approvedGrantTokens[_token] = approvedGrantToken(0, 0, 0);
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

    function createDirectGrant(address _token, address _recipient, uint256 amount) external {

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

        //Configure the metavest details
        MetaVesT.MetaVesTDetails memory metaVesTDetails;
        metaVesTDetails.metavestType = MetaVesT.MetaVesTType.ALLOCATION;
        metaVesTDetails.grantee = _recipient;
        metaVesTDetails.transferable = false;
        MetaVesT.Allocation memory allocation;
        allocation.cliffCredit = amount;
        allocation.startTime = 0;
        metaVesTDetails.allocation = allocation;
        //approve metaVest to spend the amount
        ISafe(BORG_SAFE).execTransactionFromModule(_token, 0, abi.encodeWithSignature("approve(address,uint256)", address(metaVesT), amount), Enum.Operation.Call);
        metaVesTController.createMetavestAndLockTokens(metaVesTDetails);
    }

     function createAdvancedGrant(MetaVesT.MetaVesTDetails calldata _metaVestDetails) external {

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

         //cycle through any allocations and approve the metavest to spend the amount
        uint256 _milestoneTotal;
        for (uint256 i; i < _metaVestDetails.milestones.length; ++i) {
            _milestoneTotal += _metaVestDetails.milestones[i].milestoneAward;
        }
        uint256 _total = _metaVestDetails.allocation.tokenStreamTotal +
            _metaVestDetails.allocation.cliffCredit +
            _milestoneTotal;

        approvedGrantToken storage approvedToken = approvedGrantTokens[_metaVestDetails.allocation.tokenContract];
        if (approvedToken.spendingLimit == 0) {
            revert optimisticGrantImplant_invalidToken();
        }
        if(approvedToken.amountSpent + _total > approvedToken.spendingLimit)
            revert optimisticGrantImplant_GrantSpendingLimitReached();

        ISafe(BORG_SAFE).execTransactionFromModule(_metaVestDetails.allocation.tokenContract, 0, abi.encodeWithSignature("approve(address,uint256)", address(metaVesT), _total), Enum.Operation.Call);
        metaVesTController.createMetavestAndLockTokens(_metaVestDetails);
    }


}
