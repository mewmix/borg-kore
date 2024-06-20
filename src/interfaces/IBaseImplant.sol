// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

interface IBaseImplant {
    /// @notice Emitted when a transaction creates a proposal that will be
    /// executed later - either by BORG members after a VETO period, or by 
    /// the DAO's governance solution after a successful vote.
    /// @param pendingProposalId The id of the proposal that will be used later to 
    /// execute it.
    /// @param governanceProposalId The id of the governance proposal that will
    /// execute the proposal in the case of an approval vote, or will delete
    /// the proposal if it is vetoed.
    /// @dev The `governanceProposalId` is not used by the implant directly, 
    /// but is provided so that frontends can link the pending proposal to the 
    /// governance proposal that will execute or veto it.
    event PendingProposalCreated(uint256 indexed pendingProposalId, uint256 indexed governanceProposalId);
    
    function BORG_SAFE() external view returns (address);
    function IMPLANT_ID() external view returns (uint256);
}
