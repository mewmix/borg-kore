// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import "../interfaces/ISafe.sol";
import "../libs/auth.sol";
import "forge-std/interfaces/IERC20.sol";
import "../libs/conditions/conditionManager.sol";
import "metavest/MetaVesTController.sol";
import "../interfaces/IGovernanceAdapter.sol";

contract daoVoteGrantImplant is GlobalACL, ConditionManager { //is baseImplant

    address public immutable BORG_SAFE;
    uint256 public duration;
    address public governanceAdapter;
    address public governanceExecutor;
    MetaVesT public metaVesT;
    MetaVesTController public metaVesTController;

     struct Proposal {
        uint256 id;
        uint256 duration;
        uint256 startTime;
        address token;
        address recipient;
        uint256 amount;
        address votingAuthority;
    }

    struct approvedGrantToken { 
        address token;
        uint256 spendingLimit;
        uint256 amountSpent;
    }

    error daoVoteGrantImplant_NotAuthorized();
    error daoVoteGrantImplant_ProposalExpired();
    error daoVoteGrantImplant_GrantSpendingLimitReached();
    error daoVoteGrantImplant_CallerNotBORGMember();
    error daoVoteGrantImplant_CallerNotBORG();
    error daoVoteGrantImplant_CallerNotGovernance();
    error daoVoteGrantImplant_GrantCountLimitReached();
    error daoVoteGrantImplant_GrantTimeLimitReached();
    error daoVoteGrantImplant_invalidToken();


    constructor(Auth _auth, address _borgSafe, uint256 _duration, address _governanceAdapter, address _governanceExecutor) ConditionManager(_auth) {
        BORG_SAFE = _borgSafe;
        duration = _duration;
        governanceAdapter = _governanceAdapter;
        governanceExecutor = _governanceExecutor;
    }

    function updateDuration(uint256 _duration) external onlyOwner {
        duration = _duration;
    }


    function setGovernanceAdapter(address _governanceAdapter) external onlyOwner {
        governanceAdapter = _governanceAdapter;
    }


    function proposeDirectGrant(address _token, address _recipient, uint256 _amount, string memory _desc) external {
        if(IERC20(_token).balanceOf(address(BORG_SAFE)) < _amount)
            revert daoVoteGrantImplant_GrantSpendingLimitReached();

        if(!ISafe(BORG_SAFE).isOwner(msg.sender))
            revert daoVoteGrantImplant_CallerNotBORGMember();

        if(BORG_SAFE != msg.sender)
            revert daoVoteGrantImplant_CallerNotBORG();

        bytes memory proposalBytecode = abi.encodeWithSignature("executeDirectGrant(address,address,uint256)", _token, _recipient, _amount);

        address[] memory targets = new address[](1);
        targets[0] = address(this);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory proposalBytecodes = new bytes[](1);
        proposalBytecodes[0] = proposalBytecode;
        IGovernanceAdapter(governanceAdapter).createProposal(targets, values, proposalBytecodes, _desc);
       
    }

     function executeDirectGrant(address _token, address _recipient, uint256 _amount) external {

        if(governanceExecutor != msg.sender)
            revert daoVoteGrantImplant_CallerNotGovernance();

        if(IERC20(_token).balanceOf(address(BORG_SAFE)) < _amount)
            revert daoVoteGrantImplant_GrantSpendingLimitReached();

        if(_token==address(0))
            ISafe(BORG_SAFE).execTransactionFromModule(_recipient, _amount, "", Enum.Operation.Call);
        else
            ISafe(BORG_SAFE).execTransactionFromModule(_token, 0, abi.encodeWithSignature("transfer(address,uint256)", _recipient, _amount), Enum.Operation.Call);
    }


    function executeSimpleGrant(address _token, address _recipient, uint256 _amount) external {

        if(governanceExecutor != msg.sender)
        revert daoVoteGrantImplant_CallerNotGovernance();

        if(IERC20(_token).balanceOf(address(BORG_SAFE)) < _amount)
            revert daoVoteGrantImplant_GrantSpendingLimitReached();

        //Configure the metavest details
        MetaVesT.MetaVesTDetails memory metaVesTDetails;
        metaVesTDetails.metavestType = MetaVesT.MetaVesTType.ALLOCATION;
        metaVesTDetails.grantee = _recipient;
        metaVesTDetails.transferable = false;
        MetaVesT.Allocation memory allocation;
        allocation.cliffCredit = _amount;
        allocation.startTime = 0;
        metaVesTDetails.allocation = allocation;
        //approve metaVest to spend the amount
        ISafe(BORG_SAFE).execTransactionFromModule(_token, 0, abi.encodeWithSignature("approve(address,uint256)", address(metaVesT), _amount), Enum.Operation.Call);
        metaVesTController.createMetavestAndLockTokens(metaVesTDetails);
    }

     function executeAdvancedGrant(MetaVesT.MetaVesTDetails calldata _metaVestDetails) external {

        if(governanceExecutor != msg.sender)
        revert daoVoteGrantImplant_CallerNotGovernance();

         //cycle through any allocations and approve the metavest to spend the amount
        uint256 _milestoneTotal;
        for (uint256 i; i < _metaVestDetails.milestones.length; ++i) {
            _milestoneTotal += _metaVestDetails.milestones[i].milestoneAward;
        }
        uint256 _total = _metaVestDetails.allocation.tokenStreamTotal +
            _metaVestDetails.allocation.cliffCredit +
            _milestoneTotal;

        ISafe(BORG_SAFE).execTransactionFromModule(_metaVestDetails.allocation.tokenContract, 0, abi.encodeWithSignature("approve(address,uint256)", address(metaVesT), _total), Enum.Operation.Call);
        metaVesTController.createMetavestAndLockTokens(_metaVestDetails);
    }
}
