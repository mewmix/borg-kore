

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../interfaces/ISafe.sol";
import "../libs/auth.sol";

contract ejectImplant is Auth { //is baseImplant

 address public immutable BORG_SAFE;

 constructor(address _owner, address _borgSafe) {
        BORG_SAFE = _borgSafe;
    }

    function removeOwner(address owner) public {
   // require(msg.sender == authorizedCaller, "Caller is not authorized");
    ISafe gnosisSafe = ISafe(BORG_SAFE);
    require(gnosisSafe.isOwner(owner), "Address is not an owner");

    address[] memory owners = gnosisSafe.getOwners();
    address prevOwner = address(0);
    for (uint256 i = 0; i < owners.length; i++) {
        if (owners[i] == owner) {
            if (i > 0) {
                prevOwner = owners[i - 1];
            }
            break;
        }
    }
    bytes memory data = abi.encodeWithSignature("removeOwner(address,address,uint256)", prevOwner, owner, 1);
    gnosisSafe.execTransactionFromModule(address(gnosisSafe), 0, data, Enum.Operation.Call);
   // gnosisSafe.removeOwner(prevOwner, owner, gnosisSafe.getThreshold() - 1);
}

 /* function _execTransaction(
        address _to,
        bytes memory _calldata
    ) internal returns (bytes memory _ret) {
        ISafe(BORG_SAFE).execTransactionFromModule(_to, 0, _calldata, 0);
        bool success;

    }*/
}