// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import "../interfaces/ISafe.sol";
import "../libs/auth.sol";
import "forge-std/interfaces/IERC20.sol";
import "../interfaces/IGovernanceAdapter.sol";
import "metavest/MetaVesTController.sol";
import "./baseImplant.sol";


contract daoVetoGrantImplant is BaseImplant { //is baseImplant

    uint256 public immutable IMPLANT_ID = 3;
    uint256 public lastMotionId;
    address public governanceAdapter;
    address public governanceExecutor;
    MetaVesT public metaVesT;
    MetaVesTController public metaVesTController;
    uint256 public duration = 3; //3 days
    uint256 public quorum = 3; //3%
    uint256 public threshold = 25; //25%
    uint256 public waitingPeriod = 24 hours;
    uint256 public lastProposalTime;
    bool public requireBorgVote = true;

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

    error daoVetoGrantImplant_NotAuthorized();
    error daoVetoGrantImplant_CallerNotBORGMember();
    error daoVetoGrantImplant_CallerNotBORG();
    error daoVetoGrantImplant_GrantSpendingLimitReached();
    error daoVetoGrantImplant_CallerNotGovernance();
    error daoVetoGrantImplant_InvalidToken();
    error daoVetoGrantImplant_ProposalNotReady();
    error daoVetoGrantImplant_ProposalExecutionError();

    Proposal[] public currentProposals;
    mapping(uint256 => prop) public vetoProposals;
    mapping(uint256 => uint256) internal proposalIndicesByProposalId;
    mapping(address => uint256) approvedGrantTokens;
    uint256 internal constant PERC_SCALE = 10000;

    constructor(Auth _auth, address _borgSafe, uint256 _duration, uint _quorum, uint256 _threshold, uint _waitingPeriod, address _governanceAdapter, address _governanceExecutor, address _metaVesT, address _metaVesTController) BaseImplant(_auth, _borgSafe) {
        duration = _duration;
        quorum = _quorum;
        threshold = _threshold;
        waitingPeriod = _waitingPeriod;
        lastMotionId=0;
        governanceAdapter = _governanceAdapter;
        governanceExecutor = _governanceExecutor;
        metaVesT = MetaVesT(_metaVesT);
        metaVesTController = MetaVesTController(_metaVesTController);
    }

    function addApprovedGrantToken(address _token, uint256 _spendingLimit) external onlyOwner {
        approvedGrantTokens[_token] = _spendingLimit;
    }

    function removeApprovedGrantToken(address _token) external onlyOwner {
        approvedGrantTokens[_token] = 0;
    }

    function updateWaitingPeriod(uint256 _waitingPeriod) external onlyOwner {
        waitingPeriod = _waitingPeriod;
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

    function toggleBorgVote(bool _requireBorgVote) external onlyOwner {
        requireBorgVote = _requireBorgVote;
    }

    // should only be executed by a BORG owner/member
    function executeProposal(uint256 _proposalId)
        external
    {
        if(!ISafe(BORG_SAFE).isOwner(msg.sender))
            revert daoVetoGrantImplant_CallerNotBORGMember();

        Proposal storage proposal = _getProposal(_proposalId);

        if(proposal.startTime + proposal.duration > block.timestamp)
            revert daoVetoGrantImplant_ProposalNotReady();

        (bool success,) = address(this).call(proposal.cdata);
        if(!success)
            revert daoVetoGrantImplant_ProposalExecutionError();
        _deleteProposal(_proposalId);
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

    function proposeDirectGrant(address _token, address _recipient, uint256 _amount, string memory _desc) external returns (uint256 proposalId, uint256 _newProposalId) {
        //Set ID to 0 incase there is a failure in the GovernanceAdapter
        proposalId = 0;

        if(IERC20(_token).balanceOf(address(BORG_SAFE)) < _amount || approvedGrantTokens[_token] < _amount)
            revert daoVetoGrantImplant_GrantSpendingLimitReached();

        if(requireBorgVote) {
            if(BORG_SAFE != msg.sender)
                revert daoVetoGrantImplant_CallerNotBORG();
        }
        else if (BORG_SAFE != msg.sender) {
            if(!ISafe(BORG_SAFE).isOwner(msg.sender))
                revert daoVetoGrantImplant_CallerNotBORGMember();
        }

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
        if(IERC20(_token).balanceOf(address(BORG_SAFE)) < _amount || approvedGrantTokens[_token] < _amount)
            revert daoVetoGrantImplant_GrantSpendingLimitReached();

        if(requireBorgVote) {
            if(BORG_SAFE != msg.sender)
                revert daoVetoGrantImplant_CallerNotBORG();
        }
        else if (BORG_SAFE != msg.sender) {
            if(!ISafe(BORG_SAFE).isOwner(msg.sender))
                revert daoVetoGrantImplant_CallerNotBORGMember();
        }

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

        if(IERC20(_metaVestDetails.allocation.tokenContract).balanceOf(address(BORG_SAFE)) < _total || approvedGrantTokens[_metaVestDetails.allocation.tokenContract] < _total)
            revert daoVetoGrantImplant_GrantSpendingLimitReached();

        if(requireBorgVote) {
            if(BORG_SAFE != msg.sender)
                revert daoVetoGrantImplant_CallerNotBORG();
        }
        else if (BORG_SAFE != msg.sender) {
            if(!ISafe(BORG_SAFE).isOwner(msg.sender))
                revert daoVetoGrantImplant_CallerNotBORGMember();
        }

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

    function executeDirectGrant(address _token, address _recipient, uint256 _amount) internal {

        if(IERC20(_token).balanceOf(address(BORG_SAFE)) < _amount)
            revert daoVetoGrantImplant_GrantSpendingLimitReached();

        if(_token==address(0))
            ISafe(BORG_SAFE).execTransactionFromModule(_recipient, _amount, "", Enum.Operation.Call);
        else
            ISafe(BORG_SAFE).execTransactionFromModule(_token, 0, abi.encodeWithSignature("transfer(address,uint256)", _recipient, _amount), Enum.Operation.Call);
    }

    function executeSimpleGrant(address _token, address _recipient, uint256 _amount) internal {

        if(IERC20(_token).balanceOf(address(BORG_SAFE)) < _amount)
            revert daoVetoGrantImplant_GrantSpendingLimitReached();

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

    function executeAdvancedGrant(MetaVesT.MetaVesTDetails calldata _metaVestDetails) internal {

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
