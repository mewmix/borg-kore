

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "safe-contracts/safe.sol";
import "../libs/auth.sol";

contract ejectImplant is Auth { //is baseImplant

 Safe public immutable BORG_SAFE;

 constructor(address _owner, Safe _borgSafe) {
        BORG_SAFE = _borgSafe;
    }

  function _execTransaction(
        address _to,
        bytes memory _calldata
    ) internal returns (bytes memory _ret) {
        bool success;
        (success, _ret) = BORG_SAFE.execTransactionFromModuleReturnData(
            _to,
            0,
            _calldata,
            Enum.Operation.Call
        );
        if (!success) {
            /// @solidity memory-safe-assembly
            assembly {
                revert(add(_ret, 0x20), mload(_ret))
            }
        }
    }
}