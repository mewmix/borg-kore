// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import "../libs/auth.sol";
import "../libs/conditions/conditionManager.sol";

contract BaseImplant is GlobalACL, ConditionManager {

  address public immutable BORG_SAFE;

  constructor(Auth _auth, address _borgSafe) ConditionManager(_auth)
  {
    BORG_SAFE = _borgSafe;
  }

} 