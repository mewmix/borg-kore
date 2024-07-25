// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

import "./BaseCondition.sol";

/// @title SignatureCondition - A condition that checks if a certain number of signers have signed
contract MultiUseSignCondition is BaseCondition {

    // condition vars
    address public immutable BORG_SAFE;
    uint256 private immutable threshold;
    uint256 private immutable numSigners;
    uint256 public signatureCount;

    // mappings
    mapping(address => bool) public hasSigned;
    mapping(address => bool) public isSigner;
    mapping(address => mapping(address => mapping(bytes => bool))) public hasSignedContractBytes;
    mapping(address => mapping(bytes => uint256)) public signedContractCount;

    // events and errors
    event Signed(address indexed signer, address indexed _contract, bytes data);
    event Revoked(address indexed signer, address indexed _contract, bytes data);

    error SignatureCondition_ThresholdExceedsSigners();
    error SignatureCondition_CallerAlreadySigned();
    error SignatureCondition_CallerHasNotSigned();
    error SignatureCondition_CallerNotSigner();
    error SignatureCondition_InvalidZero();

    /// @notice Constructor to create a SignatureCondition
    /// @param _signers - An array of addresses that are signers
    /// @param _threshold - The number of signers required to satisfy the condition
   
    constructor(
        address _borgSafe,
        address[] memory _signers,
        uint256 _threshold
    ) {
        BORG_SAFE = _borgSafe;
        if (_threshold > _signers.length)
            revert SignatureCondition_ThresholdExceedsSigners();
        if (_threshold == 0) revert SignatureCondition_InvalidZero();
        threshold = _threshold;

        for (uint256 i = 0; i < _signers.length; ) {
            if(_signers[i] == address(0)) revert SignatureCondition_InvalidZero();
            isSigner[_signers[i]] = true;
            unchecked {
                i++; // will not overflow without hitting gas limit
            }
        }
        numSigners = _signers.length;
    }

    /// @notice Function to sign the condition
    function sign(address _contract, bytes memory _data) public {
        if (!isSigner[msg.sender] && msg.sender != BORG_SAFE) revert SignatureCondition_CallerNotSigner();
        if (hasSignedContractBytes[msg.sender][_contract][_data])
            revert SignatureCondition_CallerAlreadySigned();

        hasSignedContractBytes[msg.sender][_contract][_data] = true;
        //update the count if not BORG_SAFE
        if(msg.sender != BORG_SAFE)
            signedContractCount[_contract][_data]++;

        emit Signed(msg.sender, _contract, _data);
    }

    // Function to unsign the condition
    function revokeSignature(address _contract, bytes memory _data) public {
        if (!isSigner[msg.sender] && msg.sender != BORG_SAFE) revert SignatureCondition_CallerNotSigner();
        if (!hasSignedContractBytes[msg.sender][_contract][_data])
            revert SignatureCondition_CallerHasNotSigned();

         hasSignedContractBytes[msg.sender][_contract][_data] = false;
        //update the count if not BORG_SAFE
        if(msg.sender != BORG_SAFE)
            signedContractCount[_contract][_data]--;
            
        emit Revoked(msg.sender, _contract, _data);
    }

    /// @notice Function to check if the condition is satisfied
    /// @return bool - Whether the condition is satisfied
    function checkCondition(address _contract, bytes4 _functionSignature, bytes memory _data) public view override returns (bool) {

      if(hasSignedContractBytes[BORG_SAFE][_contract][_data]) return true;
      return signedContractCount[_contract][_data] >= threshold;
        
    }
}
