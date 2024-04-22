// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import "../interfaces/ISafe.sol";
import "../libs/auth.sol";
import "forge-std/interfaces/IERC20.sol";
import "../interfaces/IGovernanceAdapter.sol";
import "metavest/MetaVesTController.sol";
import "../libs/conditions/conditionManager.sol";

contract daoVetoGrantImplant is GlobalACL, ConditionManager { //is baseImplant

    address public immutable BORG_SAFE;
    address public immutable governanceToken;
    uint256 public objectionsThreshold;
    uint256 public lastMotionId;
    address public governanceAdapter;
    address public governanceExecutor;
    MetaVesT public metaVesT;
    MetaVesTController public metaVesTController;
    uint256 public duration = 3; //3 days
    uint256 public quorum = 3; //3%
    uint256 public threshold = 25; //25%

    struct Proposal {
        uint256 id;
        uint256 duration;
        uint256 startTime;
        bytes cdata;
    }

    struct prop {
        address[] targets;
        uint256[] values;
        bytes[] proposalBytecodes;
        bytes32 desc;
    }

    struct approvedGrantToken { 
        address token;
        uint256 grantLimit;
    }

    error daoVetoGrantImplant_NotAuthorized();
    error daoVetoGrantImplant_ProposalExpired();
    error daoVetoGrantImplant_CallerNotBORGMember();
    error daoVetoGrantImplant_CallerNotBORG();
    error daoVetoGrantImplant_GrantSpendingLimitReached();
    error daoVetoGrantImplant_CallerNotGovernance();
    error daoVetoGrantImplant_GrantCountLimitReached();
    error daoVetoGrantImplant_GrantTimeLimitReached();
    error daoVetoGrantImplant_invalidToken();

    Proposal[] public currentProposals;
    mapping(uint256 => prop) public vetoProposals;
    approvedGrantToken[] public approvedGrantTokens;
    mapping(uint256 => uint256) internal proposalIndicesByProposalId;
    uint256 internal constant PERC_SCALE = 10000;

    constructor(Auth _auth, address _borgSafe, address _governanceToken, uint256 _duration, uint256 _objectionsThreshold, address _governanceAdapter) ConditionManager(_auth) {
        BORG_SAFE = _borgSafe;
        governanceToken = _governanceToken;
        duration = _duration;
        objectionsThreshold = _objectionsThreshold;
        lastMotionId=0;
        governanceAdapter = _governanceAdapter;
    }

    function addApprovedGrantToken(address _token, uint256 _spendingLimit) external onlyOwner {
        approvedGrantTokens.push(approvedGrantToken(_token, _spendingLimit));
    }

    function removeApprovedGrantToken(address _token) external onlyOwner {
        for (uint256 i = 0; i < approvedGrantTokens.length; i++) {
            if (approvedGrantTokens[i].token == _token) {
                approvedGrantTokens[i] = approvedGrantTokens[approvedGrantTokens.length - 1];
                approvedGrantTokens.pop();
                break;
            }
        }
    }

    function updateObjectionsThreshold(uint256 _objectionsThreshold) external onlyOwner {
        objectionsThreshold = _objectionsThreshold;
    }

    function getApprovedGrantTokenByAddress(address _token) internal view returns (approvedGrantToken storage) {
        for (uint256 i = 0; i < approvedGrantTokens.length; i++) {
            if (approvedGrantTokens[i].token == _token) {
                return approvedGrantTokens[i];
            }
        }
        return approvedGrantTokens[0];
    }

    function _isTokenApproved(address _token) internal view returns (bool) {
        for (uint256 i = 0; i < approvedGrantTokens.length; i++) {
            if (approvedGrantTokens[i].token == _token) {
                return true;
            }
        }
        return false;
    }

    function createProposal(address _token, address _recipient, uint256 _amount, address _votingAuthority) external 
        returns (uint256 _newProposalId)
    {
          if(!ISafe(BORG_SAFE).isOwner(msg.sender))
            revert daoVetoGrantImplant_CallerNotBORGMember();
        if(!_isTokenApproved(_token))
            revert daoVetoGrantImplant_invalidToken();
        approvedGrantToken storage approvedToken = getApprovedGrantTokenByAddress(_token);


        Proposal storage newProposal = currentProposals.push();
        _newProposalId = ++lastMotionId;
        newProposal.id = _newProposalId;
        newProposal.startTime = block.timestamp;
        proposalIndicesByProposalId[_newProposalId] = currentProposals.length;
    }

    // should only be executed by a BORG owner/member
    function executeProposal(uint256 _proposalId)
        external
    {
        if(!ISafe(BORG_SAFE).isOwner(msg.sender))
            revert daoVetoGrantImplant_CallerNotBORGMember();
        Proposal storage proposal = _getProposal(_proposalId);
        require(proposal.startTime + proposal.duration <= block.timestamp, "Proposal is not ready to be executed");
        ISafe(BORG_SAFE).execTransactionFromModule(address(this), 0, proposal.cdata, Enum.Operation.Call);
    }

    function _getProposal(uint256 _proposalId) internal view returns (Proposal storage) {
        uint256 proposalIndex = proposalIndicesByProposalId[_proposalId];
        require(proposalIndex > 0, "Proposal not found");
        return currentProposals[proposalIndex - 1];
    }

    function _deleteProposal(uint256 _proposalId) public {
        uint256 proposalIndex = proposalIndicesByProposalId[_proposalId];
        require(proposalIndex > 0, "Proposal not found");
        uint256 lastProposalIndex = currentProposals.length - 1;
        if (proposalIndex != lastProposalIndex) {
            currentProposals[proposalIndex - 1] = currentProposals[lastProposalIndex];
            proposalIndicesByProposalId[currentProposals[lastProposalIndex].id] = proposalIndex;
        }
        currentProposals.pop();
        delete proposalIndicesByProposalId[_proposalId];
    }

    function updateDuration(uint256 _duration) external onlyOwner {
        duration = _duration;
    }

    function updateQuorum(uint256 _quorum) external onlyOwner {
        quorum = _quorum;
    }

    function updateThreshold(uint256 _threshold) external onlyOwner {
         threshold = _threshold;
    }

    function setGovernanceAdapter(address _governanceAdapter) external onlyOwner {
        governanceAdapter = _governanceAdapter;
    }

    function proposeDirectGrant(address _token, address _recipient, uint256 _amount, string memory _desc) external returns (uint256 proposalId, uint256 _newProposalId) {
        proposalId = 0;
        if(IERC20(_token).balanceOf(address(BORG_SAFE)) < _amount)
            revert daoVetoGrantImplant_GrantSpendingLimitReached();

        if(!ISafe(BORG_SAFE).isOwner(msg.sender))
            revert daoVetoGrantImplant_CallerNotBORGMember();

        //if(BORG_SAFE != msg.sender)
        //    revert daoVetoGrantImplant_CallerNotBORG();

        bytes memory proposalBytecode = abi.encodeWithSignature("executeDirectGrant(address,address,uint256)", _token, _recipient, _amount);
       
        Proposal storage newProposal = currentProposals.push();
        _newProposalId = ++lastMotionId;
        newProposal.id = _newProposalId;
        newProposal.startTime = block.timestamp;
        newProposal.cdata = proposalBytecode;
        proposalIndicesByProposalId[_newProposalId] = currentProposals.length;

        bytes memory vetoBytecode = abi.encodeWithSignature("_deleteProposal(uint256)", _newProposalId);
        address[] memory targets = new address[](1);
        targets[0] = address(this);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory vetoBytecodes = new bytes[](1);
        vetoBytecodes[0] = vetoBytecode;

        if(governanceAdapter != address(0))
        {
            proposalId = IGovernanceAdapter(governanceAdapter).createProposal(targets, values, vetoBytecodes, _desc, quorum, threshold, duration);
            vetoProposals[proposalId] = prop(targets, values, vetoBytecodes, keccak256(abi.encodePacked(_desc)));
        }
       
    }

    function proposeSimpleGrant(address _token, address _recipient, uint256 _amount, string memory _desc) external returns (uint256 proposalId, uint256 _newProposalId) {
        proposalId = 0;
        if(IERC20(_token).balanceOf(address(BORG_SAFE)) < _amount)
            revert daoVetoGrantImplant_GrantSpendingLimitReached();

        if(!ISafe(BORG_SAFE).isOwner(msg.sender))
            revert daoVetoGrantImplant_CallerNotBORGMember();

        //if(BORG_SAFE != msg.sender)
        //    revert daoVetoGrantImplant_CallerNotBORG();

        bytes memory proposalBytecode = abi.encodeWithSignature("executeSimpleGrant(address,address,uint256)", _token, _recipient, _amount);
     
        Proposal storage newProposal = currentProposals.push();
        _newProposalId = ++lastMotionId;
        newProposal.id = _newProposalId;
        newProposal.startTime = block.timestamp;
        newProposal.cdata = proposalBytecode;
        proposalIndicesByProposalId[_newProposalId] = currentProposals.length;

        bytes memory vetoBytecode = abi.encodeWithSignature("_deleteProposal(uint256)", _newProposalId);
        address[] memory targets = new address[](1);
        targets[0] = address(this);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory vetoBytecodes = new bytes[](1);
        vetoBytecodes[0] = vetoBytecode;

        if(governanceAdapter != address(0))
        {
            proposalId = IGovernanceAdapter(governanceAdapter).createProposal(targets, values, vetoBytecodes, _desc, quorum, threshold, duration);
            vetoProposals[proposalId] = prop(targets, values, vetoBytecodes, keccak256(abi.encodePacked(_desc)));
        }
    }

    function proposeAdvancedGrant(MetaVesT.MetaVesTDetails calldata _metaVestDetails, string memory _desc) external returns (uint256 proposalId, uint256 _newProposalId) {
        proposalId = 0;
        uint256 _milestoneTotal;
        for (uint256 i; i < _metaVestDetails.milestones.length; ++i) {
            _milestoneTotal += _metaVestDetails.milestones[i].milestoneAward;
        }
        uint256 _total = _metaVestDetails.allocation.tokenStreamTotal +
            _metaVestDetails.allocation.cliffCredit +
            _milestoneTotal;

        if(IERC20(_metaVestDetails.allocation.tokenContract).balanceOf(address(BORG_SAFE)) < _total)
            revert daoVetoGrantImplant_GrantSpendingLimitReached();

        if(!ISafe(BORG_SAFE).isOwner(msg.sender))
            revert daoVetoGrantImplant_CallerNotBORGMember();

        //if(BORG_SAFE != msg.sender)
        //    revert daoVetoGrantImplant_CallerNotBORG();

        bytes memory proposalBytecode = abi.encodeWithSignature("executeAdvancedGrant(MetaVesT.MetaVesTDetails)", _metaVestDetails);

        Proposal storage newProposal = currentProposals.push();
        _newProposalId = ++lastMotionId;
        newProposal.id = _newProposalId;
        newProposal.startTime = block.timestamp;
        newProposal.cdata = proposalBytecode;
        proposalIndicesByProposalId[_newProposalId] = currentProposals.length;

        bytes memory vetoBytecode = abi.encodeWithSignature("_deleteProposal(uint256)", _newProposalId);
        address[] memory targets = new address[](1);
        targets[0] = address(this);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory vetoBytecodes = new bytes[](1);
        vetoBytecodes[0] = vetoBytecode;

        if(governanceAdapter != address(0))
        {
            proposalId = IGovernanceAdapter(governanceAdapter).createProposal(targets, values, vetoBytecodes, _desc, quorum, threshold, duration);
            vetoProposals[proposalId] = prop(targets, values, vetoBytecodes, keccak256(abi.encodePacked(_desc)));
        }
    }
}
