// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

/// @title EIP-4824 DAOs
/// @dev See https://eips.ethereum.org/EIPS/eip-4824
interface IEIP4824 {
    /// @notice A distinct Uniform Resource Identifier (URI) for the DAO.
    function daoURI() external view returns (string memory);
}