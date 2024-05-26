// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

import "../interfaces/ISafe.sol";
import "../libs/auth.sol";
import "../libs/conditions/conditionManager.sol";
import "./baseImplant.sol";
import "../interfaces/IBaseImplant.sol";

/// @title ejectImplant - allows the DAO to have ownership controls over the BORG members on chain safe access
/// as well as the ability to self-eject from the BORG.
contract ejectImplant is BaseImplant {
    // BORG Safe Implant ID
    uint256 public immutable IMPLANT_ID = 1;
    // Fail Safe Implant address
    address public immutable FAIL_SAFE;

    // Errors and Events
    error ejectImplant_ConditionsNotMet();
    error ejectImplant_NotOwner();
    error ejectImplant_InvalidFailSafeImplant();
    error ejectImplant_FailedTransaction();

    event OwnerEjected(address indexed owner, uint256 threshold);
    event OwnerSwapped(address indexed oldOwner, address indexed newOwner);
    event ThresholdChanged(uint256 newThreshold);
    event OwnerAdded(address indexed newOwner);
    event SelfEjected(address indexed owner, bool reduceThreshold);

    /// @param _auth initialize authorization parameters for this contract, including applicable conditions
    /// @param _borgSafe address of the applicable BORG's Gnosis Safe which is adding this ejectImplant
    constructor(BorgAuth _auth, address _borgSafe, address _failSafe) BaseImplant(_auth, _borgSafe) {
        if (IBaseImplant(_failSafe).IMPLANT_ID() != 0)
            revert ejectImplant_InvalidFailSafeImplant();
        FAIL_SAFE = _failSafe;
    }

    /// @notice ejectOwner for the DAO or oversight BORG to eject a BORG member from the Safe
    /// @param _owner address of the BORG member to be ejected from the Safe
    /// @param _threshold updating the minimum number of 'owners' required to approve a transaction to this value
    function ejectOwner(address _owner, uint256 _threshold) external onlyOwner {

        if (!checkConditions()) revert ejectImplant_ConditionsNotMet();

        address[] memory owners = ISafe(BORG_SAFE).getOwners();
        address prevOwner = address(0x1);
        for (uint256 i = 1; i <= owners.length-1; i++) {
            if (owners[i] == _owner) {
                prevOwner = owners[i - 1];
                break;
            }
        }
        bytes memory data = abi.encodeWithSignature(
            "removeOwner(address,address,uint256)",
            prevOwner,
            _owner,
            _threshold
        );

        bool success = ISafe(BORG_SAFE).execTransactionFromModule(
            BORG_SAFE,
            0,
            data,
            Enum.Operation.Call
        );
        if(!success)
            revert ejectImplant_FailedTransaction();
        emit OwnerEjected(_owner, _threshold);
    }

    /// @notice swapOwner for the DAO or oversight BORG to swap an owner with a new owner
    /// @param _oldOwner address of the BORG member to be swapped
    /// @param _newOwner address of the new BORG member
    function swapOwner(address _oldOwner, address _newOwner) external onlyOwner {
        if (!checkConditions()) revert ejectImplant_ConditionsNotMet();

        address[] memory owners = ISafe(BORG_SAFE).getOwners();
        address prevOwner = address(0x1);
        for (uint256 i = 1; i <= owners.length-1; i++) {
            if (owners[i] == _oldOwner) {
                prevOwner = owners[i - 1];
                break;
            }
        }

        bytes memory data = abi.encodeWithSignature(
            "swapOwner(address,address,address)",
            prevOwner,
            _oldOwner,
            _newOwner
        );

        bool success = ISafe(BORG_SAFE).execTransactionFromModule(
            BORG_SAFE,
            0,
            data,
            Enum.Operation.Call
        );
        if(!success)
            revert ejectImplant_FailedTransaction();
        emit OwnerSwapped(_oldOwner, _newOwner);
    }

    /// @notice changeThreshold for the DAO or oversight BORG to change the minimum number of 'owners' required to approve a transaction
    /// @param _newThreshold updating the minimum number of 'owners' required to approve a transaction to this value
    function changeThreshold(uint256 _newThreshold) external onlyOwner {
        if (!checkConditions()) revert ejectImplant_ConditionsNotMet();

        bytes memory data = abi.encodeWithSignature(
            "changeThreshold(uint256)",
            _newThreshold
        );

        bool success = ISafe(BORG_SAFE).execTransactionFromModule(
            BORG_SAFE,
            0,
            data,
            Enum.Operation.Call
        );

        if(!success)
            revert ejectImplant_FailedTransaction();

        emit ThresholdChanged(_newThreshold);

    }

    /// @notice addOwner for the DAO or oversight BORG to add a new owner to the Safe
    /// @param _newOwner address of the new BORG member
    /// @param _threshold updating the minimum number of 'owners' required to approve a transaction to this value
    function addOwner(address _newOwner, uint256 _threshold) external onlyOwner {
        if (!checkConditions()) revert ejectImplant_ConditionsNotMet();

        bytes memory data = abi.encodeWithSignature(
            "addOwner(address,uint256)",
            _newOwner,
            _threshold
        );

        bool success = ISafe(BORG_SAFE).execTransactionFromModule(
            BORG_SAFE,
            0,
            data,
            Enum.Operation.Call
        );

        if(!success)
            revert ejectImplant_FailedTransaction();

        emit OwnerAdded(_newOwner);
    }

    /// @notice for a BORG member to self-eject/resign from the BORG
    /// @param _reduce boolean to reduce the threshold if the owner is the last to self-eject
    function selfEject(bool _reduce) public conditionCheck {
        if (!ISafe(BORG_SAFE).isOwner(msg.sender)) revert ejectImplant_NotOwner();

        address[] memory owners = ISafe(BORG_SAFE).getOwners();
         address prevOwner = address(0x1);
        for (uint256 i = 1; i <= owners.length-1; i++) {
            if (owners[i] == msg.sender) {
                prevOwner = owners[i - 1];
                break;
            }
        }

        uint256 threshold = ISafe(BORG_SAFE).getThreshold();

        if(_reduce && (threshold > 1) && (owners.length > threshold)){
           threshold = threshold-1;
        }

        bytes memory data = abi.encodeWithSignature(
            "removeOwner(address,address,uint256)",
            prevOwner,
            msg.sender,
            threshold
        );

        bool success = ISafe(BORG_SAFE).execTransactionFromModule(
            address(BORG_SAFE),
            0,
            data,
            Enum.Operation.Call
        );

        if(!success)
            revert ejectImplant_FailedTransaction();

        emit SelfEjected(msg.sender, _reduce);
    }

}

