// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

import "../interfaces/ISafe.sol";
import "../libs/auth.sol";
import "forge-std/interfaces/IERC20.sol";
import "../libs/conditions/conditionManager.sol";
import "metavest/MetaVesTController.sol";
import "../interfaces/IGovernanceAdapter.sol";
import "./baseImplant.sol";

contract daoVoteGrantImplant is BaseImplant { //is baseImplant

    uint256 public immutable IMPLANT_ID = 4;
    address public governanceAdapter;
    address public governanceExecutor;
    MetaVesT public metaVesT;
    MetaVesTController public metaVesTController;
    uint256 public duration = 0; //7 days
    uint256 public quorum = 10; //10%
    uint256 public threshold = 40; //40%
    bool public requireBorgVote = true;

    struct proposalDetail {
        address[] targets;
        uint256[] values;
        bytes[] proposalBytecodes;
        bytes32 desc;
    }

    mapping(uint256 => proposalDetail) public proposalDetails;

    error daoVoteGrantImplant_NotAuthorized();
    error daoVoteGrantImplant_ProposalExpired();
    error daoVoteGrantImplant_GrantSpendingLimitReached();
    error daoVoteGrantImplant_CallerNotBORGMember();
    error daoVoteGrantImplant_CallerNotBORG();
    error daoVoteGrantImplant_CallerNotGovernance();
    error daoVoteGrantImplant_GrantCountLimitReached();
    error daoVoteGrantImplant_GrantTimeLimitReached();
    error daoVoteGrantImplant_invalidToken();


    constructor(BorgAuth _auth, address _borgSafe, uint256 _duration, uint256 _quorum, uint256 _threshold, address _governanceAdapter, address _governanceExecutor, address _metaVesT, address _metaVesTController) BaseImplant(_auth, _borgSafe) {
        duration = _duration;
        quorum = _quorum;
        threshold = _threshold;
        governanceAdapter = _governanceAdapter;
        governanceExecutor = _governanceExecutor;
        metaVesT = MetaVesT(_metaVesT);
        metaVesTController = MetaVesTController(_metaVesTController);
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

    function proposeDirectGrant(address _token, address _recipient, uint256 _amount, string memory _desc) external returns (uint256 proposalId) {
        proposalId = 0;
        if(IERC20(_token).balanceOf(address(BORG_SAFE)) < _amount)
            revert daoVoteGrantImplant_GrantSpendingLimitReached();

        if(requireBorgVote) {
            if(BORG_SAFE != msg.sender)
                revert daoVoteGrantImplant_CallerNotBORG();
        }
        else if(BORG_SAFE != msg.sender) {
            if(!ISafe(BORG_SAFE).isOwner(msg.sender))
                revert daoVoteGrantImplant_CallerNotBORGMember();
         }

        bytes memory proposalBytecode = abi.encodeWithSignature("executeDirectGrant(address,address,uint256)", _token, _recipient, _amount);
        address[] memory targets = new address[](1);
        targets[0] = address(this);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory proposalBytecodes = new bytes[](1);
        proposalBytecodes[0] = proposalBytecode;

        if(governanceAdapter != address(0))
        {
            proposalId = IGovernanceAdapter(governanceAdapter).createProposal(targets, values, proposalBytecodes, _desc, quorum, threshold, duration);
            proposalDetails[proposalId] = proposalDetail(targets, values, proposalBytecodes, keccak256(abi.encodePacked(_desc)));
        }
       
    }

    function proposeSimpleGrant(address _token, address _recipient, uint256 _amount, string memory _desc) external returns (uint256 proposalId) {
        proposalId = 0;
        if(IERC20(_token).balanceOf(address(BORG_SAFE)) < _amount)
            revert daoVoteGrantImplant_GrantSpendingLimitReached();

        if(requireBorgVote) {
            if(BORG_SAFE != msg.sender)
                revert daoVoteGrantImplant_CallerNotBORG();
        }
        else if(BORG_SAFE != msg.sender) {
            if(!ISafe(BORG_SAFE).isOwner(msg.sender))
                revert daoVoteGrantImplant_CallerNotBORGMember();
         }

        bytes memory proposalBytecode = abi.encodeWithSignature("executeSimpleGrant(address,address,uint256)", _token, _recipient, _amount);
        address[] memory targets = new address[](1);
        targets[0] = address(this);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory proposalBytecodes = new bytes[](1);
        proposalBytecodes[0] = proposalBytecode;
      
        if(governanceAdapter != address(0))
        {
            proposalId = IGovernanceAdapter(governanceAdapter).createProposal(targets, values, proposalBytecodes, _desc, quorum, threshold, duration);
            proposalDetails[proposalId] = proposalDetail(targets, values, proposalBytecodes, keccak256(abi.encodePacked(_desc)));
        }
    }

    function proposeAdvancedGrant(MetaVesT.MetaVesTDetails calldata _metaVestDetails, string memory _desc) external returns (uint256 proposalId) {
        proposalId = 0;
        uint256 _milestoneTotal;
        for (uint256 i; i < _metaVestDetails.milestones.length; ++i) {
            _milestoneTotal += _metaVestDetails.milestones[i].milestoneAward;
        }
        uint256 _total = _metaVestDetails.allocation.tokenStreamTotal +
            _milestoneTotal;

        if(IERC20(_metaVestDetails.allocation.tokenContract).balanceOf(address(BORG_SAFE)) < _total)
            revert daoVoteGrantImplant_GrantSpendingLimitReached();

        if(requireBorgVote) {
            if(BORG_SAFE != msg.sender)
                revert daoVoteGrantImplant_CallerNotBORG();
        }
        else if(BORG_SAFE != msg.sender) {
            if(!ISafe(BORG_SAFE).isOwner(msg.sender))
                revert daoVoteGrantImplant_CallerNotBORGMember();
         }

        bytes memory proposalBytecode = abi.encodeWithSignature("executeAdvancedGrant(MetaVesT.MetaVesTDetails)", _metaVestDetails);
        address[] memory targets = new address[](1);
        targets[0] = address(this);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory proposalBytecodes = new bytes[](1);
        proposalBytecodes[0] = proposalBytecode;
      
        if(governanceAdapter != address(0))
        {
            proposalId = IGovernanceAdapter(governanceAdapter).createProposal(targets, values, proposalBytecodes, _desc, quorum, threshold, duration);
            proposalDetails[proposalId] = proposalDetail(targets, values, proposalBytecodes, keccak256(abi.encodePacked(_desc)));
            
        }
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
                vestingStopTime: 1,
                unlockRate: 1,
                unlockStartTime: 0,
                unlockStopTime: 1,
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
        ISafe(BORG_SAFE).execTransactionFromModule(address(metaVesTController), 0, abi.encodeWithSignature("createMetavestAndLockTokens((address,bool,uint8,(uint256,uint256,uint256,uint256,uint256,uint256,uint128,uint128,uint160,uint48,uint48,uint160,uint48,uint48,address),(uint256,uint208,uint48),(uint256,uint208,uint48),(bool,bool,bool),(uint256,bool,address[])[]))", _metavestDetails), Enum.Operation.Call);
  
    }

    function executeAdvancedGrant(MetaVesT.MetaVesTDetails calldata _metavestDetails) external {

        if(governanceExecutor != msg.sender)
        revert daoVoteGrantImplant_CallerNotGovernance();

         //cycle through any allocations and approve the metavest to spend the amount
        uint256 _milestoneTotal;
        for (uint256 i; i < _metavestDetails.milestones.length; ++i) {
            _milestoneTotal += _metavestDetails.milestones[i].milestoneAward;
        }
        uint256 _total = _metavestDetails.allocation.tokenStreamTotal +
            _milestoneTotal;

        ISafe(BORG_SAFE).execTransactionFromModule(_metavestDetails.allocation.tokenContract, 0, abi.encodeWithSignature("approve(address,uint256)", address(metaVesT), _total), Enum.Operation.Call);
        ISafe(BORG_SAFE).execTransactionFromModule(address(metaVesTController), 0, abi.encodeWithSignature("createMetavestAndLockTokens((address,bool,uint8,(uint256,uint256,uint256,uint256,uint256,uint256,uint128,uint128,uint160,uint48,uint48,uint160,uint48,uint48,address),(uint256,uint208,uint48),(uint256,uint208,uint48),(bool,bool,bool),(uint256,bool,address[])[]))", _metavestDetails), Enum.Operation.Call);
  
    }

    function getProposalDetails(uint256 _proposalId) external view returns (proposalDetail memory) {
        return proposalDetails[_proposalId];
    }
}
