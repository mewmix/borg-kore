// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

import "../interfaces/ISafe.sol";
import "../libs/auth.sol";
import "../libs/conditions/conditionManager.sol";
import "forge-std/interfaces/IERC20.sol";
import "./baseImplant.sol";

interface IERC1155 {
    function balanceOf(address account, uint256 id) external view returns (uint256);
    function safeTransferFrom(address from, address to, uint256 id, uint256 amount, bytes calldata data) external;
}

contract failSafeImplant is BaseImplant { //is baseImplant

    uint256 public immutable IMPLANT_ID = 0;
    address public immutable RECOVERY_ADDRESS;

    error failSafeImplant_NotAuthorized();
    error failSafeImplant_ConditionsNotMet();
    error failSafeImplant_InvalidToken();
    error failSafeImplant_FailedTransfer();

    struct TokenInfo {
        address tokenAddress;
        uint256 id; // For ERC721 and ERC1155, id represents the token ID. For ERC20, this can be ignored.
        uint256 amount; // For ERC20 and ERC1155, amount represents the token amount. For ERC721, this can be ignored.
        uint8 tokenType; // 1 for ERC20, 2 for ERC721, 3 for ERC1155
    }

    TokenInfo[] public tokenList;

    event TokenAdded(address indexed tokenAddress, uint256 id, uint256 amount, uint8 tokenType);
    event TokenRemoved(address indexed tokenAddress);

    constructor(BorgAuth _auth, address _borgSafe, address _recoveryAddress) BaseImplant(_auth, _borgSafe) {
        RECOVERY_ADDRESS = _recoveryAddress;
    }

    function addToken(address _tokenAddress, uint256 _id, uint256 _amount, uint8 _tokenType) external onlyOwner {
        TokenInfo memory newToken = TokenInfo({
            tokenAddress: _tokenAddress,
            id: _id,
            amount: _amount,
            tokenType: _tokenType
        });
        tokenList.push(newToken);
        emit TokenAdded(_tokenAddress, _id, _amount, _tokenType);
    }

    function removeTokenByAddress(address _tokenAddress) external onlyOwner {
        for(uint i = 0; i < tokenList.length; i++) {
            if(tokenList[i].tokenAddress == _tokenAddress) {
                tokenList[i] = tokenList[tokenList.length - 1];
                tokenList.pop();
                emit TokenRemoved(_tokenAddress);
                break;
            }
        }
    }

    function recoverSafeFunds() external {

        ISafe gnosisSafe = ISafe(BORG_SAFE);
        if(!checkConditions()) revert failSafeImplant_ConditionsNotMet();

        for(uint i = 0; i < tokenList.length; i++) {
            if(tokenList[i].tokenType == 1) {
                // Encode the call to the ERC20 token's `transfer` function
                uint256 amountToSend = tokenList[i].amount;
                uint256 balance = IERC20(tokenList[i].tokenAddress).balanceOf(address(BORG_SAFE));
                if(amountToSend==0 || amountToSend > balance) 
                     amountToSend = balance;
                bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", RECOVERY_ADDRESS, amountToSend);
                // Request the Safe to execute the token transfer
                bool success = gnosisSafe.execTransactionFromModule(tokenList[i].tokenAddress, 0, data, Enum.Operation.Call);
                if(!success) revert failSafeImplant_FailedTransfer();
            } else if(tokenList[i].tokenType == 2) {
                bytes memory data = abi.encodeWithSignature("transferFrom(address,address,uint256)", BORG_SAFE, RECOVERY_ADDRESS, tokenList[i].id);
                bool success = gnosisSafe.execTransactionFromModule(tokenList[i].tokenAddress, 0, data, Enum.Operation.Call);
                if(!success) revert failSafeImplant_FailedTransfer();
            } else if(tokenList[i].tokenType == 3) {
                uint256 amountToSend = tokenList[i].amount;
                uint256 balance = IERC1155(tokenList[i].tokenAddress).balanceOf(BORG_SAFE, tokenList[i].id);
                if(amountToSend==0 || amountToSend > balance) 
                     amountToSend = balance;
                bytes memory data = abi.encodeWithSignature("safeTransferFrom(address,address,uint256,uint256,bytes)", BORG_SAFE, RECOVERY_ADDRESS, tokenList[i].id, amountToSend, "");
                bool success = gnosisSafe.execTransactionFromModule(tokenList[i].tokenAddress, 0, data, Enum.Operation.Call);
                if(!success) revert failSafeImplant_FailedTransfer();
            }
        }
    }

    function recoverSafeFundsERC20(address _token) external onlyOwner conditionCheck {
        ISafe gnosisSafe = ISafe(BORG_SAFE);
        uint256 amountToSend = IERC20(_token).balanceOf(address(BORG_SAFE));
        bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", RECOVERY_ADDRESS, amountToSend);
        // Request the Safe to execute the token transfer
        bool success = gnosisSafe.execTransactionFromModule(_token, 0, data, Enum.Operation.Call);
        if(!success) revert failSafeImplant_FailedTransfer();
    }

    function recoverSafeFundsERC721(address _token, uint256 _id) external onlyOwner conditionCheck {
        ISafe gnosisSafe = ISafe(BORG_SAFE);
        bytes memory data = abi.encodeWithSignature("transferFrom(address,address,uint256)", BORG_SAFE, RECOVERY_ADDRESS, _id);
        bool success = gnosisSafe.execTransactionFromModule(_token, 0, data, Enum.Operation.Call);
        if(!success) revert failSafeImplant_FailedTransfer();
    }

    function recoverSafeFundsERC1155(address _token, uint256 _id) external onlyOwner conditionCheck {
        ISafe gnosisSafe = ISafe(BORG_SAFE);
        //get erc1155 token amount
        uint256 _amount = IERC1155(_token).balanceOf(BORG_SAFE, _id);
        bytes memory data = abi.encodeWithSignature("safeTransferFrom(address,address,uint256,uint256,bytes)", BORG_SAFE, RECOVERY_ADDRESS, _id, _amount, "");
        bool success = gnosisSafe.execTransactionFromModule(_token, 0, data, Enum.Operation.Call);
        if(!success) revert failSafeImplant_FailedTransfer();
    }
}

