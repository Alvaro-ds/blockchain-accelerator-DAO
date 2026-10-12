// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";

/**
 * @title DAOGovernanceToken
 * @author Alvaro Dapena
 * @notice ERC20 governance token that represents voting power in the DAO.
 * @dev Token transfers act as delegation: transferring tokens to another address
 * increases that address's voting power. Explicit delegation helpers track the
 * delegator-delegate relationship so it can be reversed.
 */
contract DAOGovernanceToken is ERC20, Ownable {
    /// @notice Whether an address has an active delegation outstanding.
    mapping(address => bool) public hasDelegated;

    /// @notice The delegate address chosen by each delegator.
    mapping(address => address) public delegates;

    /// @notice Cumulative tokens delegated to each delegate address.
    mapping(address => uint256) public delegatedVotes;

    /**
     * @notice Emitted when a holder delegates voting power to another address.
     * @param delegator Address that transferred tokens.
     * @param delegated Address that received the tokens.
     * @param amount Number of tokens delegated (in wei).
     */
    event VotingPowerDelegated(address indexed delegator, address indexed delegated, uint256 amount);

    /**
     * @notice Emitted when a delegator reclaims previously delegated tokens.
     * @param delegator Address reclaiming tokens.
     * @param delegated Address returning the tokens.
     * @param amount Number of tokens returned (in wei).
     */
    event VotingPowerUndelegated(address indexed delegator, address indexed delegated, uint256 amount);

    /**
     * @notice Deploys the token and mints the entire initial supply to the deployer.
     * @param name Token name.
     * @param symbol Token symbol.
     * @param initialSupply Total initial supply minted to msg.sender (in wei).
     */
    constructor(string memory name, string memory symbol, uint256 initialSupply) ERC20(name, symbol) Ownable(msg.sender) {
        _mint(msg.sender, initialSupply);
    }

    /**
     * @notice Delegates `amount` tokens to `delegate`, increasing their voting power.
     * @dev Transfers tokens so that `getVotingPower` (which returns `balanceOf`) reflects the change.
     * A delegator can only delegate to one address at a time; a subsequent call overwrites
     * the previous delegate entry while the `delegatedVotes` accumulator remains additive.
     * @param delegate Address to receive the delegated tokens. Cannot be address(0) or msg.sender.
     * @param amount Number of tokens to delegate (must be strictly less than the caller's balance).
     */
    function delegateVotingPower(address delegate, uint256 amount) external {
        require(delegate != address(0), "Cannot delegate to zero address");
        require(delegate != msg.sender, "Cannot delegate to self");
        require(amount > 0, "Amount must be greater than 0");
        require(balanceOf(msg.sender) > amount, "Insufficient balance");

        _transfer(msg.sender, delegate, amount);

        delegates[msg.sender] = delegate;
        delegatedVotes[delegate] += amount;
        hasDelegated[msg.sender] = true;

        emit VotingPowerDelegated(msg.sender, delegate, amount);
    }

    /**
     * @notice Reclaims `amount` previously delegated tokens from the current delegate.
     * @dev Transfers tokens back from the delegate to the caller. Clears the delegation
     * state entirely once the delegate's accumulated balance from this delegator reaches zero.
     * @param amount Number of tokens to undelegate (must be <= total delegated to the current delegate).
     */
    function undelegateVotingPower(uint256 amount) external {
        require(hasDelegated[msg.sender], "No delegation found");
        require(amount > 0, "Amount must be greater than 0");
        require(delegatedVotes[delegates[msg.sender]] >= amount, "Insufficient delegated amount");

        address delegate = delegates[msg.sender];
        _transfer(delegate, msg.sender, amount);

        delegatedVotes[delegate] -= amount;

        if (delegatedVotes[delegate] == 0) {
            hasDelegated[msg.sender] = false;
            delete delegates[msg.sender];
        }

        emit VotingPowerUndelegated(msg.sender, delegate, amount);
    }

    /**
     * @notice Returns the voting power (token balance) of `account`.
     * @param account Address to query.
     * @return Total tokens held by `account`, which equals its current voting power.
     */
    function getVotingPower(address account) external view returns (uint256) {
        return balanceOf(account);
    }

    /**
     * @notice Mints `amount` new tokens to `to`. Only callable by the contract owner.
     * @param to Recipient address.
     * @param amount Number of tokens to mint (in wei).
     */
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    /**
     * @notice Burns `amount` tokens from the caller's balance.
     * @param amount Number of tokens to burn (in wei).
     */
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }
}
