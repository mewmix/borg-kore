

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../interfaces/ISafe.sol";
import "../libs/auth.sol";

contract ejectImplant is Auth { //is baseImplant

 address public immutable BORG_SAFE;

 constructor(address _owner, address _borgSafe) {
        BORG_SAFE = _borgSafe;
    }

  function _execTransaction(
        address _to,
        bytes memory _calldata
    ) internal returns (bytes memory _ret) {
        bool success;

    }
}