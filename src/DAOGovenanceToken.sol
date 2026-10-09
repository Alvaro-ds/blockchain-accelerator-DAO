// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";

/**
 * @title DAOGovernanceToken
 * @dev ERC20 token used for DAO governance voting
 * This token represents voting power in the DAO
 */
contract DAOGovernanceToken is ERC20, Ownable {

    mapping(address => bool) public hasDelegated;

    mapping(address => address) public delegates; 

    mapping(address => uint256) public delegatedVotes;

    event VotingPowerDelegated(address indexed delegator, address indexed delegated, uint256 amount);
    event VomitPowerUndelegated(address indexed delegator, address indexed delegated, uint256 amount);

    /**
     * @dev Constructor that gives msg.sender all of initial tokens
     * @param name Token name
     * @param symbol Token symbol
     * @param initialSupply Initial token supply
     */
    constructor(string memory name, string memory symbol, uint256 initialSupply) ERC20(name, symbol) Ownable(msg.sender) {
        _mint(msg.sender, initialSupply);
    }

    /**
     * @dev Get the voting power of an address (including delegated votes)
     * @param account Address to check voting power for
     * @return Total voting power
     */
    function getVotingPower(address account) external view returns(uint256) {
        return balanceOf(account);
    }

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }
}