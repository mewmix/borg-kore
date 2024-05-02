// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

import "../interfaces/ISafe.sol";
import "../libs/auth.sol";
import "../libs/conditions/conditionManager.sol";
import "./baseImplant.sol";
import "../interfaces/IBaseImplant.sol";

contract ejectImplant is BaseImplant {
    uint256 public immutable IMPLANT_ID = 1;
    address public immutable FAIL_SAFE;

    error ejectImplant_ConditionsNotMet();
    error ejectImplant_NotOwner();
    error ejectImplant_InvalidFailSafeImplant();

    /// @param _auth initialize authorization parameters for this contract, including applicable conditions
    /// @param _borgSafe address of the applicable BORG's Gnosis Safe which is adding this ejectImplant
    constructor(BorgAuth _auth, address _borgSafe, address _failSafe) BaseImplant(_auth, _borgSafe) {
        if (IBaseImplant(_failSafe).IMPLANT_ID() != 0)
            revert ejectImplant_InvalidFailSafeImplant();
        FAIL_SAFE = _failSafe;
    }

    /// @notice for an 'owner' to eject an 'owner' from the Safe
    /// @param _owner address of the 'owner' to be ejected from the Safe
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

        ISafe(BORG_SAFE).execTransactionFromModule(
            BORG_SAFE,
            0,
            data,
            Enum.Operation.Call
        );
    }

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

        ISafe(BORG_SAFE).execTransactionFromModule(
            BORG_SAFE,
            0,
            data,
            Enum.Operation.Call
        );
    }

    function changeThreshold(uint256 _newThreshold) external onlyOwner {
        if (!checkConditions()) revert ejectImplant_ConditionsNotMet();

        bytes memory data = abi.encodeWithSignature(
            "changeThreshold(uint256)",
            _newThreshold
        );

        ISafe(BORG_SAFE).execTransactionFromModule(
            BORG_SAFE,
            0,
            data,
            Enum.Operation.Call
        );
    }

    function addOwner(address _newOwner, uint256 _threshold) external onlyOwner {
        if (!checkConditions()) revert ejectImplant_ConditionsNotMet();

        bytes memory data = abi.encodeWithSignature(
            "addOwner(address,uint256)",
            _newOwner,
            _threshold
        );

        ISafe(BORG_SAFE).execTransactionFromModule(
            BORG_SAFE,
            0,
            data,
            Enum.Operation.Call
        );
    }

    /// @notice for a msg.sender 'owner' to self-eject from the BORG
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
        ISafe(BORG_SAFE).execTransactionFromModule(
            address(BORG_SAFE),
            0,
            data,
            Enum.Operation.Call
        );
    }

}

