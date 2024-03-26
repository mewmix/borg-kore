// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import "safe-contracts/base/GuardManager.sol";
import "./libs/auth.sol";

contract borgCore is BaseGuard, GlobalACL {

    /// Error Messages
    error BORG_CORE_InvalidRecipient();
    error BORG_CORE_InvalidContract();
    error BORG_CORE_AmountOverLimit();

    enum CORE_TYPE { FULL, PARTIAL, NONE }
    
    enum ParamType { UINT, ADDRESS, STRING, BYTES, BOOL, INT }

    struct ParamConstraint {
        bool exists;
        ParamType paramType;
        uint256 minValue;
        uint256 maxValue;
        bytes exactMatch; // Use bytes to store the exact match value for dynamic types
        uint256 byteOffset; // Offset in bytes for the parameter
        uint256 byteLength;
    }

    struct MethodConstraint {
        bool allowed;
        mapping(uint8 => ParamConstraint) parameterConstraints;
        uint8 currentConstraints;
    }

    struct PolicyItem {
        bool allowed;
        bool fullAccess;
        mapping(bytes4 => MethodConstraint) methods;
    }

    mapping(address => PolicyItem) public policy;

    /// Whitelist Structs
    struct Recipient {
        bool approved;
        uint256 transactionLimit;
    }

    /// Method IDs
    /// @dev To check for transfers. See note above -- we can add these
    /// to the whitelisted structs for more granular control.
    bytes4 private constant TRANSFER_METHOD_ID = 0xa9059cbb;
    bytes4 private constant TRANSFER_FROM_METHOD_ID = 0x23b872dd;

    /// Whitelist Mappings
    mapping(address => Recipient) public whitelistedRecipients;

    /// Constructor
    /// @param _auth Address, ideally an oversight multisig or other safeguard.
    constructor(Auth _auth) GlobalACL(_auth) {
    }

    /// checkTransaction
    /// @dev This is pre-tx execution on the Safe that gets called on every execTx
    /// We here check for Native Gas transfers and ERC20 transfers based on the
    /// whitelist allowance. This implementation also blocks any other contract
    /// interaction if not on the whitelisted contract mapping. 
    function checkTransaction(
        address to, 
        uint256 value, 
        bytes calldata data, 
        Enum.Operation operation, 
        uint256 safeTxGas, 
        uint256 baseGas, 
        uint256 gasPrice, 
        address gasToken, 
        address payable refundReceiver, 
        bytes calldata signatures, 
        address msgSender
    ) 
        external view override
    {
        if (value > 0 && data.length == 0) {
            // Native Gas transfer
            if(!whitelistedRecipients[to].approved) {
                revert BORG_CORE_InvalidRecipient();
            }
            if(value > whitelistedRecipients[to].transactionLimit) {
                revert BORG_CORE_AmountOverLimit();
            }
         } else if (data.length >= 4) {
            if(policy[to].allowed == false) {
              revert BORG_CORE_InvalidContract();
            }
            if(policy[to].fullAccess != true)
                if(isMethodCallAllowed(to, data))
                    return;
                else 
                    revert BORG_CORE_InvalidContract();
            bytes4 methodId = bytes4(data[:4]);
            // Check for an ERC20 transfer
            if (methodId == TRANSFER_METHOD_ID || methodId == TRANSFER_FROM_METHOD_ID) {

                // Pull the destination address from the call data
                address destination = abi.decode(data[4:36], (address));
                // Pull the tx amount from the call data
                uint256 amount = abi.decode(data[36:68], (uint256));
                if(!whitelistedRecipients[destination].approved) {
                   revert BORG_CORE_InvalidRecipient();
                }
                if((amount > whitelistedRecipients[destination].transactionLimit)) {
                 revert BORG_CORE_AmountOverLimit();
                }
         }
         }
         else {
            revert BORG_CORE_InvalidContract();
         }
    }

    // @dev This is post transaction execution. We can react but cannot revert what just occured.
    function checkAfterExecution(bytes32 txHash, bool success) external view override {
     
    }

    // @dev add recipient address and transaction limit to the whitelist
    function addRecipient(address _recipient, uint256 _transactionLimit) external onlyOwner {
        whitelistedRecipients[_recipient] = Recipient(true, _transactionLimit);
    }

    // @dev remove recipient address from the whitelist
    function removeRecipient(address _recipient) external onlyOwner {
        whitelistedRecipients[_recipient] = Recipient(false, 0);
    }

    // @dev add contract address and transaction limit to the whitelist
    function addContract(address _contract, uint256 _transactionLimit) external onlyOwner {
       policy[_contract].allowed = true;
       policy[_contract].fullAccess = true;
    }

    // @dev remove contract address from the whitelist
    function removeContract(address _contract) external onlyOwner {
       policy[_contract].allowed = false;
       policy[_contract].fullAccess = false;
    }

    // @dev to maintain erc165 compatiblity for the Gnosis Safe Guard Manager
    function supportsInterface(bytes4 interfaceId) external view virtual override returns (bool) {
        return
            interfaceId == type(Guard).interfaceId || 
            interfaceId == type(IERC165).interfaceId; 
    }

    function updatePolicy(address[] memory _contracts, bool _allowed) public onlyOwner {

    }

    function updatePolicy(address[] memory _contracts, bool _allowed, string[] memory _methodNames, uint256[] memory _minValues, ParamType[] memory _paramTypes, uint256[] memory _paramIndex, uint256[] memory _maxValues, bytes[] memory _exactMatches, uint256[] memory _byteOffsets, uint256[] memory _byteLengths) public onlyOwner {
        //check inputs
        require(_contracts.length == _methodNames.length, "Invalid input length");
        require(_contracts.length == _minValues.length, "Invalid input length");
        require(_contracts.length == _maxValues.length, "Invalid input length");
        require(_contracts.length == _exactMatches.length, "Invalid input length");
        require(_contracts.length == _byteOffsets.length, "Invalid input length");
        require(_contracts.length == _byteLengths.length, "Invalid input length");
        require(_contracts.length == _paramTypes.length, "Invalid input length");
        require(_contracts.length == _paramIndex.length, "Invalid input length");

        for (uint256 i = 0; i < _contracts.length;) {
            address contractAddress = _contracts[i];
            string memory methodName = _methodNames[i];
            uint256 minValue = _minValues[i];
            uint256 maxValue = _maxValues[i];
            bytes memory exactMatch = _exactMatches[i];
            uint256 byteOffset = _byteOffsets[i];
            uint256 byteLength = _byteLengths[i];
            ParamType paramType = _paramTypes[i];
            uint8 paramIndex = uint8(_paramIndex[i]);

            //if the string is empty
            if (bytes(methodName).length == 0){
                policy[contractAddress].allowed = _allowed;
                policy[contractAddress].fullAccess = _allowed;
            } else if (minValue>0){
                _addParameterConstraint(contractAddress, methodName, paramIndex, paramType, minValue, maxValue, "", byteOffset, byteLength);
            }
            else 
            {
               _addParameterConstraint(contractAddress, methodName, paramIndex, paramType, 0, 0, exactMatch, byteOffset, byteLength);
            }
            unchecked {
             ++i; // cannot overflow without hitting gaslimit
            }
        }
    }

        // Function to add a parameter constraint for uint256 with range
    function addRangeParameterConstraint(
        address _contract,
        string memory _methodSignature,
        uint8 _paramIndex,
        ParamType _paramType,
        uint256 _minValue,
        uint256 _maxValue,
        uint256 _byteOffset,
        uint8 _byteLength
    ) public onlyOwner {
        _addParameterConstraint(_contract, _methodSignature, _paramIndex, _paramType, _minValue, _maxValue, "", _byteOffset, _byteLength);
    }

    // Function to add a parameter constraint for exact match (address, string, bytes)
    function addExactMatchParameterConstraint(
        address _contract,
        string memory _methodSignature,
        uint8 _paramIndex,
        ParamType _paramType,
        bytes memory _exactMatch,
        uint256 _byteOffset,
        uint256 _byteLength
    ) public onlyOwner {
        require(_paramType == ParamType.ADDRESS || _paramType == ParamType.STRING || _paramType == ParamType.BYTES, "Invalid param type for exact match");
        _addParameterConstraint(_contract, _methodSignature, _paramIndex, _paramType, 0, 0, _exactMatch, _byteOffset, _byteLength);
    }

      // Internal function to add a parameter constraint
    function _addParameterConstraint(
        address _contract,
        string memory _methodSignature,
        uint8 _paramIndex,
        ParamType _paramType,
        uint256 _minValue,
        uint256 _maxValue,
        bytes memory _exactMatch,
        uint256 _byteOffset,
        uint256 _byteLength
    ) internal {
        bytes4 methodSelector = bytes4(keccak256(bytes(_methodSignature)));

        policy[_contract].methods[methodSelector].parameterConstraints[_paramIndex] = ParamConstraint({
            exists: true,
            paramType: _paramType,
            minValue: _minValue,
            maxValue: _maxValue,
            exactMatch: _exactMatch,
            byteOffset: _byteOffset,
            byteLength: _byteLength
        });

        policy[_contract].allowed = true;
        policy[_contract].fullAccess = false;
         //set method allowed to true
        policy[_contract].methods[methodSelector].allowed = true;
        //update the currentConstraints counter
        policy[_contract].methods[methodSelector].currentConstraints++;
    }

    function removeParameterConstraint(
        address _contract,
        string memory _methodSignature,
        uint8 _paramIndex
    ) public onlyOwner {
        bytes4 methodSelector = bytes4(keccak256(bytes(_methodSignature)));
        //remove the parameter constraint, not set it to false
        delete policy[_contract].methods[methodSelector].parameterConstraints[_paramIndex];
        //update the currentConstraints counter
       
        policy[_contract].methods[methodSelector].currentConstraints--;
    }

     // Adjusted function to check if a method call is allowed using abi.decode
    function isMethodCallAllowed(
        address _contract,
        bytes calldata _methodCallData
    ) public view returns (bool) {
        bytes4 methodSelector = bytes4(_methodCallData[:4]);
        MethodConstraint storage methodConstraint = policy[_contract].methods[methodSelector];

        if (!methodConstraint.allowed) {
            return false;
        }

        // Iterate through the whitelist constraints for the method
        for (uint8 i = 0; i < methodConstraint.currentConstraints;) { 
            ParamConstraint storage param = methodConstraint.parameterConstraints[i];

            if (param.exists) {
                if (param.paramType == ParamType.UINT) {

                    // Extracting a uint256 value
                    uint256 paramValue = abi.decode(_methodCallData[param.byteOffset:param.byteOffset+param.byteLength], (uint256));
                    if (paramValue < param.minValue || paramValue > param.maxValue) {
                        return false;
                    }
                } else if (param.paramType == ParamType.ADDRESS) {
                    // Extracting an address value
                    address addrValue = abi.decode(_methodCallData[param.byteOffset:param.byteOffset+param.byteLength], (address));
                    if (keccak256(abi.encodePacked(addrValue)) != keccak256(param.exactMatch)) {
                        return false;
                    }
                }
                else if (param.paramType == ParamType.STRING) {
                    // Extracting a string value
                    string memory addrValue = abi.decode(_methodCallData[param.byteOffset:param.byteOffset+param.byteLength], (string));
                    if (keccak256(abi.encodePacked(addrValue)) != keccak256(param.exactMatch)) {
                        return false;
                    }
                }
                else if (param.paramType == ParamType.BYTES) {
                    // Extracting bytes
                    bytes memory addrValue = abi.decode(_methodCallData[param.byteOffset:param.byteOffset+param.byteLength], (bytes));
                    if (keccak256(abi.encodePacked(addrValue)) != keccak256(param.exactMatch)) {
                        return false;
                    }
                }
                else if (param.paramType == ParamType.BOOL) {
                    // Extracting a bool value
                    bool boolValue = abi.decode(_methodCallData[param.byteOffset:param.byteOffset+param.byteLength], (bool));
                    if (boolValue != abi.decode(param.exactMatch, (bool))) {
                        return false;
                    }
                }
                else if (param.paramType == ParamType.INT) {
                    // Extracting an int value
                    int intValue = abi.decode(_methodCallData[param.byteOffset:param.byteOffset+param.byteLength], (int));
                    if (intValue < int(param.minValue) || intValue > int(param.maxValue)) {
                        return false;
                    }
                }
            }
            unchecked {
             ++i; // cannot overflow without hitting gaslimit
            }
        }

        return true;
    }
}

