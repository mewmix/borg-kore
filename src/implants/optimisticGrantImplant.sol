// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import "../interfaces/ISafe.sol";
import "../libs/auth.sol";
import "metavest/MetaVesTController.sol";
import "./baseImplant.sol";

contract optimisticGrantImplant is BaseImplant { //is baseImplant

    uint256 public immutable IMPLANT_ID = 2;
    uint256 public grantCountLimit;
    uint256 public currentGrantCount;
    uint256 public grantTimeLimit;
    MetaVesT public metaVesT;
    MetaVesTController public metaVesTController;
    bool public requireBorgVote = true;

    struct approvedGrantToken { 
        uint256 spendingLimit;
        uint256 maxPerGrant;
        uint256 amountSpent;
    }

    error optimisticGrantImplant_invalidToken();
    error optimisticGrantImplant_GrantCountLimitReached();
    error optimisticGrantImplant_GrantTimeLimitReached();
    error optimisticGrantImplant_GrantSpendingLimitReached();
    error optimisticGrantImplant_CallerNotBORGMember();
    error optimisticGrantImplant_CallerNotBORG();

    mapping(address => approvedGrantToken) public approvedGrantTokens;

    constructor(Auth _auth, address _borgSafe, address _metaVest, address _metaVestController) BaseImplant(_auth, _borgSafe) {
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

    function toggleBorgVote(bool _requireBorgVote) external onlyOwner {
        requireBorgVote = _requireBorgVote;
    }

    function createDirectGrant(address _token, address _recipient, uint256 _amount) external {
        if(currentGrantCount >= grantCountLimit)
            revert optimisticGrantImplant_GrantCountLimitReached();
        if(block.timestamp >= grantTimeLimit)
            revert optimisticGrantImplant_GrantTimeLimitReached();
        
        if(requireBorgVote) {
            if(BORG_SAFE != msg.sender)
                revert optimisticGrantImplant_CallerNotBORG();
        }
        else {
            if(!ISafe(BORG_SAFE).isOwner(msg.sender))
                revert optimisticGrantImplant_CallerNotBORGMember();
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

    function createBasicGrant(address _token, address _recipient, uint256 _amount) external {

        if(currentGrantCount >= grantCountLimit)
            revert optimisticGrantImplant_GrantCountLimitReached();
        if(block.timestamp >= grantTimeLimit)
            revert optimisticGrantImplant_GrantTimeLimitReached();

         if(requireBorgVote) {
            if(BORG_SAFE != msg.sender)
                revert optimisticGrantImplant_CallerNotBORG();
        }
        else {
            if(!ISafe(BORG_SAFE).isOwner(msg.sender))
                revert optimisticGrantImplant_CallerNotBORGMember();
         }

        //Configure the metavest details
        MetaVesT.Milestone[] memory emptyMilestones;
        MetaVesT.MetaVesTDetails memory _metavestDetails = MetaVesT.MetaVesTDetails({
            metavestType: MetaVesT.MetaVesTType.ALLOCATION,
            allocation: MetaVesT.Allocation({
                tokenStreamTotal: _amount,
                tokenGoverningPower: 0,
                tokensVested: 0,
                tokensUnlocked: 0,
                vestedTokensWithdrawn: 0,
                unlockedTokensWithdrawn: 0,
                vestingCliffCredit: uint128(_amount),
                unlockingCliffCredit: uint128(_amount),
                vestingRate: 0,
                vestingStartTime: 0,
                vestingStopTime: 0,
                unlockRate: 0,
                unlockStartTime: 0,
                unlockStopTime: 0,
                tokenContract: _token
            }),
            option: MetaVesT.TokenOption({exercisePrice: 0, tokensForfeited: 0, shortStopTime: uint48(0)}),
            rta: MetaVesT.RestrictedTokenAward({repurchasePrice: 0, tokensRepurchasable: 0, shortStopTime: uint48(0)}),
            eligibleTokens: MetaVesT.GovEligibleTokens({nonwithdrawable: false, vested: true, unlocked: true}),
            grantee: _recipient,
            milestones: emptyMilestones,
            transferable: false
        });
        
        //approve metaVest to spend the amount
        ISafe(BORG_SAFE).execTransactionFromModule(_token, 0, abi.encodeWithSignature("approve(address,uint256)", address(metaVesT), _amount), Enum.Operation.Call);
        ISafe(BORG_SAFE).execTransactionFromModule(address(metaVesTController), 0, abi.encodeWithSignature("createMetavestAndLockTokens(MetaVesT.MetaVesTDetails calldata)", _metavestDetails), Enum.Operation.Call);
    }

     function createAdvancedGrant(MetaVesT.MetaVesTDetails calldata _metaVestDetails) external {

        if(currentGrantCount >= grantCountLimit)
            revert optimisticGrantImplant_GrantCountLimitReached();
        if(block.timestamp >= grantTimeLimit)
            revert optimisticGrantImplant_GrantTimeLimitReached();

        if(requireBorgVote) {
            if(BORG_SAFE != msg.sender)
                revert optimisticGrantImplant_CallerNotBORG();
        }
        else {
            if(!ISafe(BORG_SAFE).isOwner(msg.sender))
                revert optimisticGrantImplant_CallerNotBORGMember();
         }

         //cycle through any allocations and approve the metavest to spend the amount
        uint256 _milestoneTotal;
        for (uint256 i; i < _metaVestDetails.milestones.length; ++i) {
            _milestoneTotal += _metaVestDetails.milestones[i].milestoneAward;
        }
        uint256 _total = _metaVestDetails.allocation.tokenStreamTotal +
            _milestoneTotal;

        approvedGrantToken storage approvedToken = approvedGrantTokens[_metaVestDetails.allocation.tokenContract];
        if (approvedToken.spendingLimit == 0) {
            revert optimisticGrantImplant_invalidToken();
        }
        if(approvedToken.amountSpent + _total > approvedToken.spendingLimit)
            revert optimisticGrantImplant_GrantSpendingLimitReached();

        ISafe(BORG_SAFE).execTransactionFromModule(_metaVestDetails.allocation.tokenContract, 0, abi.encodeWithSignature("approve(address,uint256)", address(metaVesT), _total), Enum.Operation.Call);
        ISafe(BORG_SAFE).execTransactionFromModule(address(metaVesTController), 0, abi.encodeWithSignature("createMetavestAndLockTokens(MetaVesT.MetaVesTDetails)", _metaVestDetails), Enum.Operation.Call);
    }
}
