// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { ERC20 } from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import { Ownable } from "openzeppelin-contracts/contracts/access/Ownable.sol";

contract Points is ERC20, Ownable {
    address private constant ATLAS = address(0); // Replace with actual ATLAS address

    // Address of Uniswap Router to be blacklisted
    address public immutable uniswapRouter;

    // Mapping to track blacklisted addresses
    mapping(address => bool) public isBlacklisted;

    constructor(address _uniswapRouter) ERC20("Points", "PTS") Ownable(ATLAS) {
        uniswapRouter = _uniswapRouter;
        isBlacklisted[_uniswapRouter] = true; // Uniswap Router blacklisted by default
    }

    // Modifier to check if sender/receiver is blacklisted
    modifier notBlacklisted(address account) {
        require(!isBlacklisted[account], "Blacklisted address");
        _;
    }

    // Override transfer to include blacklist check
    function _update(
        address from,
        address to,
        uint256 amount
    )
        internal
        override
        notBlacklisted(from)
        notBlacklisted(to)
    {
        super._update(from, to, amount);
    }

    // Function to add or remove addresses from blacklist
    function blacklistAddress(address account, bool blacklisted) external onlyOwner {
        isBlacklisted[account] = blacklisted;
    }
}
