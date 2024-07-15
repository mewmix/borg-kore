//mock contract with 2 place holder functions function a and function b for testing
// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

contract MockPerm {
    address public setAddress ;
    uint256 public setUint;
    int256 public setInt;
    bool public setBool;
    string public setString;
    bytes public setBytes;

    function a() public pure returns (uint256) {
        return 1;
    }

    function b() public pure returns (uint256) {
        return 2;
    }

    function params(address _test, bool _bool, uint256 _uint, int256 _int, string memory _string, bytes memory _bytes) public pure returns (address, uint256, int256)
    {
        return (_test, _uint, _int);
    }
}