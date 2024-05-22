// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

import "../libs/auth.sol";
import "../libs/conditions/conditionManager.sol";

contract BaseImplant is BorgAuthACL, ConditionManager {

  address public immutable BORG_SAFE;

  constructor(BorgAuth _auth, address _borgSafe) ConditionManager(_auth)
  {
    BORG_SAFE = _borgSafe;
  }

} 