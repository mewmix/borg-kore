// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../utils/lockedGrantMilestones.sol"; 
import "../libs/auth.sol";
import "../libs/conditions/SignatureCondition.sol"; // Make sure this path is correct

contract GrantMilestonesFactory is GlobalACL {
    // List of deployed GrantMilestones contracts
    address[] public deployedMilestones;

    // Event for when a new GrantMilestones contract is deployed
    event GrantMilestonesDeployed(address indexed contractAddress, address indexed borgSafe, address indexed revokeConditions);
    // Event for new SignatureCondition
    event SignatureConditionDeployed(address indexed conditionAddress, address indexed grantMilestonesAddress);

    //Constructor
    constructor(Auth _auth) GlobalACL(_auth) {}

    /**
     * @dev Deploy a new GrantMilestones contract
     * @param _borgSafe The BORG_SAFE address
     * @param _revokeConditions The REVOKE_CONDITIONS address
     * @param _milestones The milestones array to be passed to the GrantMilestones contract
     */
    function deployGrantMilestones(
        Auth _auth,
        address _borgSafe,
        address _revokeConditions,
        GrantMilestones.Milestone[] memory _milestones
    ) public returns (address) {
        require(_borgSafe != address(0), "Borg Safe cannot be the zero address.");
        require(_revokeConditions != address(0), "Revoke Conditions cannot be the zero address.");
        require(_milestones.length > 0, "Must have at least one milestone.");

        GrantMilestones newGrantMilestones = new GrantMilestones(_borgSafe, _revokeConditions, _milestones);
        emit GrantMilestonesDeployed(address(newGrantMilestones), _borgSafe, _revokeConditions);
        return address(newGrantMilestones);
    }

    /**
     * @dev Deploy a new GrantMilestones contract with a SignatureCondition
     * @param _borgSafe The BORG_SAFE address
     * @param _revokeConditions The REVOKE_CONDITIONS address
     * @param _milestones The milestones array to be passed to the GrantMilestones contract
     * @param _signers Array of signer addresses for the SignatureCondition
     * @param _threshold The threshold number of signatures for the SignatureCondition
     * @param _logic The logic (AND/OR) for the SignatureCondition
     */
    function deployGrantMilestonesWithSignatureCondition(
        Auth _auth,
        address _borgSafe,
        address _revokeConditions,
        GrantMilestones.Milestone[] memory _milestones,
        address[] memory _signers,
        uint256 _threshold,
        SignatureCondition.Logic _logic
    ) public returns (address) {
        require(_borgSafe != address(0), "Borg Safe cannot be the zero address.");
        require(_revokeConditions != address(0), "Revoke Conditions cannot be the zero address.");
        require(_milestones.length > 0, "Must have at least one milestone.");

        // Deploy the GrantMilestones contract
        GrantMilestones newGrantMilestones = new GrantMilestones(_borgSafe, _revokeConditions, _milestones);

        // Deploy the SignatureCondition contract
        SignatureCondition newSignatureCondition = new SignatureCondition(_signers, _threshold, _logic);

        // Emit both events
        emit GrantMilestonesDeployed(address(newGrantMilestones), _borgSafe, _revokeConditions);
        emit SignatureConditionDeployed(address(newSignatureCondition), address(newGrantMilestones));

        return address(newGrantMilestones);
    }

    /**
     * @dev Returns all deployed GrantMilestones contracts
     */
    function getDeployedMilestones() public view returns (address[] memory) {
        return deployedMilestones;
    }
}
