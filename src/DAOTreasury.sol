// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "./DAO.sol";

/**
 * @title DAOTreasury
 * @author Alvaro Dapena
 * @notice Holds and disburses the DAO's funds (ETH and ERC20 tokens).
 * @dev Only the DAO contract may approve proposals and trigger fund transfers.
 * The owner retains an emergency-withdraw capability for recovery scenarios.
 */
contract DAOTreasury is Ownable {
    /// @notice Reference to the DAO contract authorised to approve and execute proposals.
    DAO public dao;

    /// @notice Whether a given proposal ID has been approved for spending.
    mapping(uint256 => bool) public approvedProposals;

    /// @notice Whether a given proposal ID has already had its funds disbursed.
    mapping(uint256 => bool) public executedProposals;

    /**
     * @notice Emitted when the DAO approves a proposal for spending.
     * @param proposalId ID of the approved proposal.
     */
    event ProposalApproved(uint256 indexed proposalId);

    /**
     * @notice Emitted after funds have been transferred to a proposal's recipient.
     * @param proposalId ID of the executed proposal.
     * @param recipient Address that received the funds.
     * @param amount Amount transferred (in wei for ETH, or in token units).
     * @param token Token address, or address(0) for ETH.
     */
    event FundsSpend(uint256 indexed proposalId, address indexed recipient, uint256 amount, address token);

    /**
     * @notice Emitted whenever ETH or tokens are deposited into the treasury.
     * @param sender Address that sent the funds.
     * @param amount Amount received (in wei for ETH, or in token units).
     */
    event TreasuryFunded(address indexed sender, uint256 amount);

    /**
     * @notice Emitted when the authorised DAO address is updated.
     * @param dao New DAO contract address.
     */
    event DAOSet(address indexed dao);

    /**
     * @notice Deploys the treasury and records the initial DAO address.
     * @dev Pass address(0) during bootstrapping and call setDAO once the DAO is deployed.
     * @param _dao Address of the DAO contract (may be address(0) at construction time).
     */
    constructor(address _dao) Ownable(msg.sender) {
        dao = DAO(_dao);
    }

    /**
     * @notice Updates the authorised DAO contract address.
     * @dev Only the owner may call this. Required once after the initial bootstrap deployment.
     * @param _dao New DAO contract address. Must not be address(0).
     */
    function setDAO(address _dao) external onlyOwner {
        require(_dao != address(0), "Invalid DAO address");
        dao = DAO(_dao);
        emit DAOSet(_dao);
    }

    /**
     * @notice Marks a proposal as approved for spending. Called exclusively by the DAO.
     * @param proposalId ID of the proposal to approve.
     */
    function approveProposal(uint256 proposalId) external {
        require(msg.sender == address(dao), "Only DAO can approve proposals");
        require(!approvedProposals[proposalId], "Proposal already approved");

        approvedProposals[proposalId] = true;
        emit ProposalApproved(proposalId);
    }

    /**
     * @notice Transfers funds to a proposal's recipient after it has been approved.
     * @dev Only the DAO may call this. Supports both ETH (token == address(0)) and ERC20 transfers.
     * @param proposalId ID of the approved proposal.
     * @param recipient Address to receive the funds. Must not be address(0).
     * @param amount Amount to transfer (in wei for ETH, or in token units).
     * @param token Token contract address, or address(0) to transfer ETH.
     */
    function spendFunds(uint256 proposalId, address recipient, uint256 amount, address token) external {
        require(msg.sender == address(dao), "Only DAO can spend funds");
        require(approvedProposals[proposalId], "Proposal not approved");
        require(!executedProposals[proposalId], "Proposal already executed");
        require(recipient != address(0), "Invalid recipient");
        require(amount > 0, "Amount must be greater than 0");

        executedProposals[proposalId] = true;

        if (token == address(0)) {
            // Send ETH
            require(address(this).balance >= amount, "Insuficient ETH balance");
            (bool succes,) = recipient.call{value: amount}("");
            require(succes, "ETH transference failed");
        } else {
            // Send ERC20 token
            IERC20 tokenContract = IERC20(token);
            require(tokenContract.balanceOf(address(this)) >= amount, "Insufficient token balance");
            require(tokenContract.transfer(recipient, amount), "Token transfer failed");
        }

        emit FundsSpend(proposalId, recipient, amount, token);
    }

    /**
     * @notice Deposits ETH into the treasury.
     * @dev msg.value must be greater than zero.
     */
    function fundTreasury() external payable {
        require(msg.value > 0, "Must send ETH");

        emit TreasuryFunded(msg.sender, msg.value);
    }

    /**
     * @notice Deposits ERC20 tokens into the treasury via transferFrom.
     * @dev The caller must approve this contract for at least `amount` before calling.
     * @param token ERC20 token contract address. Must not be address(0).
     * @param amount Number of tokens to deposit (in token units). Must be greater than zero.
     */
    function fundTreasuryWithToken(address token, uint256 amount) external {
        require(token != address(0), "Invalid token address");
        require(amount > 0, "Amount must be greater than 0");

        IERC20 tokenContract = IERC20(token);
        require(tokenContract.transferFrom(msg.sender, address(this), amount), "Token transfer failed");

        emit TreasuryFunded(msg.sender, amount);
    }

    /**
     * @notice Returns the treasury's current balance for a given asset.
     * @param token Token address to query, or address(0) for ETH.
     * @return balance Current balance in wei (ETH) or token units (ERC20).
     */
    function getBalance(address token) external view returns (uint256 balance) {
        if (token == address(0)) {
            return address(this).balance;
        } else {
            return IERC20(token).balanceOf(address(this));
        }
    }

    /**
     * @notice Returns whether a proposal has been approved for spending.
     * @param proposalId ID of the proposal to query.
     * @return approved True if the proposal has been approved.
     */
    function isProposalApproved(uint256 proposalId) external view returns (bool approved) {
        return approvedProposals[proposalId];
    }

    /**
     * @notice Returns whether a proposal's funds have already been disbursed.
     * @param proposalId ID of the proposal to query.
     * @return executed True if the proposal's funds have been spent.
     */
    function isProposalExecuted(uint256 proposalId) external view returns (bool executed) {
        return executedProposals[proposalId];
    }

    /**
     * @notice Fallback to accept ETH sent directly to the contract address.
     * @dev Emits TreasuryFunded so all inflows are observable on-chain.
     */
    receive() external payable {
        emit TreasuryFunded(msg.sender, msg.value);
    }

    /**
     * @notice Emergency withdrawal of ETH or ERC20 tokens by the owner.
     * @dev Bypasses the proposal workflow. Use only in recovery scenarios.
     * @param token Token address to withdraw, or address(0) for ETH.
     * @param amount Amount to withdraw (in wei or token units). Must be greater than zero.
     * @param receipient Destination address for the withdrawn funds. Must not be address(0).
     */
    function emergencyWithdraw(address token, uint256 amount, address receipient) external onlyOwner {
        require(receipient != address(0), "Invalid receipient");
        require(amount > 0, "Amount must be greater than 0");

        if (token == address(0)) {
            require(address(this).balance >= amount, "Insuficient ETH balance");
            (bool success,) = receipient.call{value: amount}("");
            require(success, "ETH transfer failed");
        } else {
            IERC20 tokenContract = IERC20(token);
            require(tokenContract.balanceOf(address(this)) >= amount, "Insufficient token balance");
            require(tokenContract.transfer(receipient, amount), "Token transfer failed");
        }
    }
}
