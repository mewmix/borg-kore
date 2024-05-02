// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

import "forge-std/interfaces/IERC20.sol";
import "openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

contract MockERC20Votes is ERC20, ERC20Permit, ERC20Votes {
    constructor(string memory name, string memory symbol)
        ERC20(name, symbol) 
        ERC20Permit(name)
    {
        _mint(msg.sender, 1e30); // Mint tokens for the deployer for testing
    }

    function clock() public view override(Votes) returns (uint48) {
        return uint48(block.number-1);
    }

    function _update(
        address from,
        address to,
        uint256 amount
    ) internal override(ERC20, ERC20Votes) {
        ERC20Votes._update(from, to, amount);
    }

    function nonces(address owner) public view virtual override(ERC20Permit, Nonces) returns (uint256) {
        return super.nonces(owner);
    }

}