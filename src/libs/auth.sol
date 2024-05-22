// SPDX-License-Identifier: AGPL-3.0-only

/*                                                                                           
    _/_/_/      _/_/    _/_/_/      _/_/_/        _/_/    _/    _/  _/_/_/_/_/  _/    _/   
   _/    _/  _/    _/  _/    _/  _/            _/    _/  _/    _/      _/      _/    _/    
  _/_/_/    _/    _/  _/_/_/    _/  _/_/      _/_/_/_/  _/    _/      _/      _/_/_/_/     
 _/    _/  _/    _/  _/    _/  _/    _/      _/    _/  _/    _/      _/      _/    _/      
_/_/_/      _/_/    _/    _/    _/_/_/      _/    _/    _/_/        _/      _/    */ 


pragma solidity 0.8.20;

interface IAuthAdapter {
    function isAuthorized(address user) external view returns (uint256);
}


/// @title BorgAuth
/// @notice ACL with extensibility for different role hierarchies and custom adapters
contract BorgAuth {
    //cosntants
    uint256 public constant OWNER_ROLE = 99;
    uint256 public constant ADMIN_ROLE = 98;
    uint256 public constant PRIVILEGED_ROLE = 97;

    /// @dev user not authorized with given role
    error BorgAuth_NotAuthorized(uint256 role, address user);

    mapping(address => uint256) public userRoles;
    // Mapping from role to adapters
    mapping(address => IAuthAdapter) public roleAdapters;

    constructor() {
        _updateRole(msg.sender, OWNER_ROLE);
    }

    function updateRole(
        address user,
        uint256 role
    ) external {
         onlyRole(OWNER_ROLE, msg.sender);
        _updateRole(user, role);
    }

    function setRoleAdapter(address user, IAuthAdapter adapter) external {
        onlyRole(OWNER_ROLE, msg.sender);
        roleAdapters[user] = adapter;
    }

    function onlyRole(uint256 role, address user) public view {
        uint256 authorized = userRoles[user];
        if (authorized < role) {
        IAuthAdapter adapter = roleAdapters[user];
        if (address(adapter) != address(0)) 
             if (adapter.isAuthorized(user) < role) 
                revert BorgAuth_NotAuthorized(role, user);
         revert BorgAuth_NotAuthorized(role, user);
        }
    }

    function _updateRole(
        address user,
        uint256 role
    ) internal {
        userRoles[user] = role;
    }
}

abstract contract BorgAuthACL {
    BorgAuth public immutable AUTH;

    error BorgAuthACL_ZeroAddress();

    constructor(BorgAuth _auth) {
        if(address(_auth) == address(0)) revert BorgAuthACL_ZeroAddress();
        AUTH = _auth;
    }

    modifier onlyOwner() {
        AUTH.onlyRole(AUTH.OWNER_ROLE(), msg.sender);
        _;
    }

    modifier onlyAdmin() {
        AUTH.onlyRole(AUTH.ADMIN_ROLE(), msg.sender);
        _;
    }

    modifier onlyPriv() {
        AUTH.onlyRole(AUTH.PRIVILEGED_ROLE(), msg.sender);
        _;
    }

    modifier onlyRole(uint256 _role) {
        AUTH.onlyRole(_role, msg.sender);
        _;
    }
}
