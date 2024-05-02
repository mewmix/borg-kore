// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

interface IGovernanceAdapter {
    function createProposal(address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description, uint256 quorum, uint256 threshold, uint256 duration) external returns (uint256);
    function executeProposal(address[] memory targets, uint256[] memory values, bytes[] memory calldatas, bytes32 descriptionHash, uint256 id) external returns (uint256);
    function cancelProposal(address[] memory targets, uint256[] memory values, bytes[] memory calldatas, bytes32 descriptionHash, uint256 id) external returns (uint256);
    function vote(uint256 proposalId, uint8 support) external returns (uint256);
}