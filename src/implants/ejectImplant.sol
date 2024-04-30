// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

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
    constructor(Auth _auth, address _borgSafe, address _failSafe) BaseImplant(_auth, _borgSafe) {
        if (IBaseImplant(_failSafe).IMPLANT_ID() != 0)
            revert ejectImplant_InvalidFailSafeImplant();
        FAIL_SAFE = _failSafe;
    }

    /// @notice for an 'owner' to eject an 'owner' from the Safe
    /// @param owner address of the 'owner' to be ejected from the Safe
    function ejectOwner(address owner) external onlyOwner {

        if (!checkConditions()) revert ejectImplant_ConditionsNotMet();

        address[] memory owners = ISafe(BORG_SAFE).getOwners();
        address prevOwner = address(0x1);
        for (uint256 i = 1; i <= owners.length-1; i++) {
            if (owners[i] == owner) {
                prevOwner = owners[i - 1];
                break;
            }
        }
        bytes memory data = abi.encodeWithSignature(
            "removeOwner(address,address,uint256)",
            prevOwner,
            owner,
            1
        );
        ISafe(BORG_SAFE).execTransactionFromModule(
            BORG_SAFE,
            0,
            data,
            Enum.Operation.Call
        );
    }

    /// @notice for a msg.sender 'owner' to self-eject from the BORG
    function selfEject() public conditionCheck {
        if (!ISafe(BORG_SAFE).isOwner(msg.sender)) revert ejectImplant_NotOwner();

        address[] memory owners = ISafe(BORG_SAFE).getOwners();
         address prevOwner = address(0x1);
        for (uint256 i = 1; i <= owners.length-1; i++) {
            if (owners[i] == msg.sender) {
                prevOwner = owners[i - 1];
                break;
            }
        }

        bytes memory data = abi.encodeWithSignature(
            "removeOwner(address,address,uint256)",
            prevOwner,
            msg.sender,
            1
        );
        ISafe(BORG_SAFE).execTransactionFromModule(
            address(BORG_SAFE),
            0,
            data,
            Enum.Operation.Call
        );
    }

}

