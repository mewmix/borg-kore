// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "openzeppelin/contracts/governance/Governor.sol";
import "openzeppelin/contracts/governance/extensions/GovernorVotes.sol";
import "openzeppelin/contracts/governance/extensions/GovernorCountingSimple.sol";
import "openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "forge-std/interfaces/IERC20.sol";

contract MockDAO is Governor, GovernorVotes, GovernorCountingSimple {
    struct ProposalThresholds {
        uint256 quorum;
        uint256 threshold;
        uint256 length;
    }
    uint256 lastLength;

    mapping(uint256 => ProposalThresholds) public proposalThresholds;
    mapping(uint256 => ProposalVote) public _proposalVotes;

    constructor(IVotes _token)
        Governor("CustomGovernor")
        GovernorVotes(_token)
        GovernorCountingSimple()
    {}

    function proposeWithThresholds(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description,
        uint256 quorum,
        uint256 threshold,
        uint256 length
    ) public returns (uint256) {
        lastLength = length;
        uint256 proposalId = propose(targets, values, calldatas, description);
        proposalThresholds[proposalId] = ProposalThresholds({
            quorum: quorum,
            threshold: threshold,
            length: length
        });
        return proposalId;
    }

    function _quorumReached(uint256 proposalId) internal view override(Governor, GovernorCountingSimple) returns (bool) {
        return proposalThresholds[proposalId].quorum <= getVotes(proposalId);
    }

    function _voteSucceeded(uint256 proposalId) internal view override(Governor, GovernorCountingSimple) returns (bool) {
        uint256 totalVotes = getSupportVotes(proposalId);
        uint256 votesRequired = (totalVotes * proposalThresholds[proposalId].threshold) / 100;
        return getSupportVotes(proposalId) >= votesRequired;
    }

    function getVotes(uint256 proposalId) public view returns (uint256) {
        ProposalVote storage proposal = _proposalVotes[proposalId];
        return proposal.forVotes + proposal.againstVotes + proposal.abstainVotes;
    }

    function getSupportVotes(uint256 proposalId) public view returns (uint256) {
        ProposalVote storage proposal = _proposalVotes[proposalId];
        return proposal.forVotes;
    }

      // Implementing required abstract functions
    function quorum(uint256 blockNumber) public view override returns (uint256) {
        return 1; 
    }

    function votingDelay() public view override returns (uint256) {
        return 1; 
    }

    function votingPeriod() public view override returns (uint256) {
        return lastLength; 
    }
}