// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

import "./baseGovernanceAdapater.sol";
import "../../interfaces/IMockDAO.sol";

contract FlexGovernanceAdapter is BaseGovernanceAdapter {
    address public governorContract;

     constructor(address _goverernorContract) {
        governorContract = _goverernorContract;
     }

    function updateGovernorContract(address _goverernorContract) public {
        governorContract = _goverernorContract;
    }

    function createProposal(address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description, uint256 quorum, uint256 threshold, uint256 duration) public override returns (uint256 proposalId) {
        return IMockDAO(governorContract).proposeWithThresholds(targets, values, calldatas, description, quorum, threshold, duration);
    }

    function executeProposal(address[] memory targets, uint256[] memory values, bytes[] memory calldatas, bytes32 descriptionHash, uint256 id) public override returns (uint256) {
        return IMockDAO(governorContract).execute(targets, values, calldatas, descriptionHash);
    }

    function cancelProposal(address[] memory targets, uint256[] memory values, bytes[] memory calldatas, bytes32 descriptionHash, uint256 id) public override returns (uint256) {
        return IMockDAO(governorContract).cancel(targets, values, calldatas, descriptionHash);
    }

    function vote(uint256 proposalId, uint8 support) public override returns(uint256) {
        return IMockDAO(governorContract).castVote(proposalId, support);
    }

    function getVotes(uint256 proposalId) public override returns(uint256 forVotes, uint256 againstVotes, uint256 abstainVotes) {
        forVotes = IMockDAO(governorContract).getSupportVotes(proposalId);
        againstVotes = IMockDAO(governorContract).getAgainstVotes(proposalId);
        abstainVotes = IMockDAO(governorContract).getAbstainVotes(proposalId);
        return (forVotes, againstVotes, abstainVotes);
    }


}