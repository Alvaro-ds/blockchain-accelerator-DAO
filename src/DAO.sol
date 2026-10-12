// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import "./DAOGovernanceToken.sol";

/**
 * @title IDAOTreasury
 * @notice Interface for the DAO Treasury contract.
 * @dev Exposes only the functions the DAO needs to call on the treasury.
 */
interface IDAOTreasury {
    function approveProposal(uint256 proposalId) external;
    function spendFunds(uint256 proposalId, address recipient, uint256 amount, address token) external;
}

/**
 * @title DAO
 * @author Alvaro Dapena
 * @notice Decentralized Autonomous Organization: handles proposal creation, voting, and execution.
 * @dev Voting power is derived from the associated DAOGovernanceToken balance.
 * Proposals that pass quorum and receive more for-votes than against-votes
 * are executed by the linked DAOTreasury.
 */
contract DAO is Ownable {
    /// @notice Governance token whose balance determines each address's voting power.
    DAOGovernanceToken public governanceToken;

    /// @notice Treasury contract that holds and disburses funds on behalf of the DAO.
    IDAOTreasury public treasury;

    /**
     * @notice On-chain record of a governance proposal.
     * @dev Mappings inside a struct cannot be returned directly; use getProposal / getVoteInfo.
     */
    struct Proposal {
        uint256 id;
        address proposer;
        string description;
        uint256 forVotes;
        uint256 againstVotes;
        uint256 startTime;
        uint256 endTime;
        bool executed;
        bool canceled;
        address recipient;
        uint256 amount;
        address token;
        mapping(address => bool) hasVoted;
        mapping(address => bool) votedFor;
    }

    /// @notice Minimum governance tokens required to submit a proposal.
    uint256 public proposalThreshold;

    /// @notice Duration of the voting window in seconds.
    uint256 public votingPeriod;

    /// @notice Minimum total votes (for + against) required for a proposal to be executable.
    uint256 public quorumVotes;

    /// @notice Total number of proposals ever created (also the next proposal's ID).
    uint256 public proposalCount;

    /// @notice Storage mapping from proposal ID to Proposal data.
    mapping(uint256 => Proposal) public proposals;

    /**
     * @notice Emitted when a new proposal is submitted.
     * @param proposalId Unique identifier assigned to the proposal.
     * @param proposer Address that created the proposal.
     * @param description Human-readable description of the proposal.
     * @param recipient Address that will receive funds if the proposal passes.
     * @param amount Amount of funds to transfer on execution.
     * @param token Token address (address(0) for ETH).
     * @param startTime Timestamp when voting opens.
     * @param endTime Timestamp when voting closes.
     */
    event ProposalCreated(uint256 indexed proposalId, address indexed proposer, string description, address recipient, uint256 amount, address token, uint256 startTime, uint256 endTime);

    /**
     * @notice Emitted when an address casts a vote.
     * @param proposalId Proposal that was voted on.
     * @param voter Address that cast the vote.
     * @param support True if the vote is in favour, false if against.
     * @param votes Number of governance tokens behind the vote.
     */
    event Voted(uint256 indexed proposalId, address indexed voter, bool support, uint256 votes);

    /**
     * @notice Emitted when a passing proposal is executed and funds are disbursed.
     * @param proposalId ID of the executed proposal.
     */
    event ProposalExecuted(uint256 indexed proposalId);

    /**
     * @notice Emitted when a proposal is canceled before execution.
     * @param proposalId ID of the canceled proposal.
     */
    event ProposalCanceled(uint256 indexed proposalId);

    /**
     * @notice Emitted when the DAO's governance parameters are updated.
     * @param proposalThreshols Minimum tokens required to create a proposal.
     * @param votingPeriod Duration of the voting period in seconds.
     * @param quorumVotes Minimum total votes required for a valid result.
     */
    event ConfigurationUpdated(uint256 proposalThreshols, uint256 votingPeriod, uint256 quorumVotes);

    /**
     * @notice Initialises the DAO with its governance token, treasury, and voting parameters.
     * @param _governanceToken Address of the DAOGovernanceToken contract.
     * @param _treasury Address of the DAOTreasury contract.
     * @param _proposalThreshold Minimum tokens required to create a proposal.
     * @param _votingPeriod Duration of the voting period in seconds.
     * @param _quorumVotes Minimum total votes required for a proposal to be executable.
     */
    constructor(address _governanceToken, address _treasury, uint256 _proposalThreshold, uint256 _votingPeriod, uint256 _quorumVotes) Ownable(msg.sender) {
        governanceToken = DAOGovernanceToken(_governanceToken);
        treasury = IDAOTreasury(_treasury);
        proposalThreshold = _proposalThreshold;
        votingPeriod = _votingPeriod;
        quorumVotes = _quorumVotes;
    }

    /**
     * @notice Submits a new governance proposal requesting a treasury transfer.
     * @dev The caller must hold at least `proposalThreshold` tokens.
     * @param description Human-readable description of the proposal. Must not be empty.
     * @param recipient Address to receive funds if the proposal passes. Must not be address(0).
     * @param amount Amount of funds to transfer on execution. Must be greater than zero.
     * @param token Token address (address(0) to request ETH).
     * @return proposalId The ID assigned to the newly created proposal.
     */
    function createProposal(string memory description, address recipient, uint256 amount, address token) external returns (uint256 proposalId) {
        require(governanceToken.getVotingPower(msg.sender) >= proposalThreshold, "Insufficient voting power to create proposal");
        require(bytes(description).length > 0, "Description cannot be empty");
        require(recipient != address(0), "Invalid recipient address");
        require(amount > 0, "Amount must be greater than 0");

        proposalId = proposalCount++;
        Proposal storage proposal = proposals[proposalId];

        proposal.id = proposalId;
        proposal.proposer = msg.sender;
        proposal.description = description;
        proposal.recipient = recipient;
        proposal.amount = amount;
        proposal.token = token;
        proposal.startTime = block.timestamp;
        proposal.endTime = block.timestamp + votingPeriod;
        proposal.executed = false;
        proposal.canceled = false;

        emit ProposalCreated(proposalId, msg.sender, description, proposal.recipient, proposal.amount, proposal.token, proposal.startTime, proposal.endTime);
    }

    /**
     * @notice Casts a vote on an active proposal.
     * @dev Each address may vote once per proposal. Voting power equals the caller's token balance at the time of the call.
     * @param proposalId ID of the proposal to vote on.
     * @param support True to vote in favour, false to vote against.
     */
    function vote(uint256 proposalId, bool support) external {
        Proposal storage proposal = proposals[proposalId];

        require(proposal.proposer != address(0), "Proposal does not exist");
        require(block.timestamp >= proposal.startTime, "Voting not started");
        require(block.timestamp < proposal.endTime, "Voting ended");
        require(!proposal.hasVoted[msg.sender], "Already voted");
        require(!proposal.canceled, "Proposal is canceled");
        require(!proposal.executed, "Proposal already executed");

        uint256 votes = governanceToken.getVotingPower(msg.sender);
        require(votes > 0, "No voting power");

        proposal.hasVoted[msg.sender] = true;
        proposal.votedFor[msg.sender] = support;

        if (support) {
            proposal.forVotes += votes;
        } else {
            proposal.againstVotes += votes;
        }

        emit Voted(proposalId, msg.sender, support, votes);
    }

    /**
     * @notice Cancels a proposal, preventing it from being executed.
     * @dev Only the original proposer or the contract owner may cancel a proposal.
     * @param proposalId ID of the proposal to cancel.
     */
    function cancelProposal(uint256 proposalId) external {
        Proposal storage proposal = proposals[proposalId];

        require(proposal.proposer != address(0), "Proposal does not exist");
        require(!proposal.executed, "Proposal already executed");
        require(!proposal.canceled, "Proposal already canceled");
        require(msg.sender == proposal.proposer || msg.sender == owner(), "Not authorized to cancel");

        proposal.canceled = true;

        emit ProposalCanceled(proposalId);
    }

    /**
     * @notice Executes a proposal that has passed voting, triggering the treasury transfer.
     * @dev Requires: voting period ended, quorum met, more for-votes than against-votes,
     * proposal not previously executed or canceled.
     * @param proposalId ID of the proposal to execute.
     */
    function executeProposal(uint256 proposalId) external {
        Proposal storage proposal = proposals[proposalId];

        require(proposal.proposer != address(0), "Proposal does not exists");
        require(block.timestamp >= proposal.endTime, "Voting not ended");
        require(!proposal.executed, "Proposal already executed");
        require(!proposal.canceled, "Proposal is canceled");
        require(proposal.forVotes + proposal.againstVotes >= quorumVotes, "Quorum not reached");
        require(proposal.forVotes > proposal.againstVotes, "Proposal not passed");

        proposal.executed = true;

        treasury.approveProposal(proposalId);

        treasury.spendFunds(proposalId, proposal.recipient, proposal.amount, proposal.token);

        emit ProposalExecuted(proposalId);
    }

    /**
     * @notice Returns all stored fields of a proposal (excluding the internal vote mappings).
     * @param proposalId ID of the proposal to query.
     * @return proposer Address that created the proposal.
     * @return description Human-readable proposal description.
     * @return forVotes Cumulative votes cast in favour.
     * @return againstVotes Cumulative votes cast against.
     * @return startTime Timestamp when voting opened.
     * @return endTime Timestamp when voting closes.
     * @return executed Whether the proposal has been executed.
     * @return canceled Whether the proposal has been canceled.
     * @return recipient Address designated to receive the funds.
     * @return amount Amount of funds to transfer.
     * @return token Token address (address(0) for ETH).
     */
    function getProposal(uint256 proposalId) external view returns (address proposer, string memory description, uint256 forVotes, uint256 againstVotes, uint256 startTime, uint256 endTime, bool executed, bool canceled, address recipient, uint256 amount, address token) {
        Proposal storage proposal = proposals[proposalId];
        return (proposal.proposer, proposal.description, proposal.forVotes, proposal.againstVotes, proposal.startTime, proposal.endTime, proposal.executed, proposal.canceled, proposal.recipient, proposal.amount, proposal.token);
    }

    /**
     * @notice Returns whether an address has voted on a proposal and how they voted.
     * @param proposalId ID of the proposal to query.
     * @param voter Address to look up.
     * @return hasVoted True if `voter` has cast a vote on this proposal.
     * @return votedFor True if `voter` voted in favour (only meaningful when hasVoted is true).
     */
    function getVoteInfo(uint256 proposalId, address voter) external view returns (bool hasVoted, bool votedFor) {
        Proposal storage proposal = proposals[proposalId];
        return (proposal.hasVoted[voter], proposal.votedFor[voter]);
    }

    /**
     * @notice Updates the DAO's governance parameters. Only callable by the owner.
     * @param _proposalThreshold New minimum tokens required to create a proposal.
     * @param _votingPeriod New voting period duration in seconds.
     * @param _quorumVotes New minimum total votes required for a valid result.
     */
    function updateConfiguration(uint256 _proposalThreshold, uint256 _votingPeriod, uint256 _quorumVotes) external onlyOwner {
        proposalThreshold = _proposalThreshold;
        votingPeriod = _votingPeriod;
        quorumVotes = _quorumVotes;

        emit ConfigurationUpdated(_proposalThreshold, _votingPeriod, _quorumVotes);
    }

    /**
     * @notice Replaces the treasury contract address. Only callable by the owner.
     * @param _treasury New treasury address. Must not be address(0).
     */
    function setTreasury(address _treasury) external onlyOwner {
        require(_treasury != address(0), "Invalid treasury address");
        treasury = IDAOTreasury(_treasury);
    }

    /**
     * @notice Returns whether a proposal has passed and is eligible for execution.
     * @dev Returns false if the proposal does not exist, is canceled, is already executed,
     * the voting period has not ended, quorum has not been reached, or for-votes do not
     * exceed against-votes.
     * @param proposalId ID of the proposal to evaluate.
     * @return passed True if the proposal has passed all conditions for execution.
     */
    function proposalPassed(uint256 proposalId) external view returns (bool passed) {
        Proposal storage proposal = proposals[proposalId];

        if (proposal.proposer == address(0) || proposal.canceled || proposal.executed) {
            return false;
        }

        if (block.timestamp < proposal.endTime) {
            return false; // Voting not ended
        }

        if (proposal.forVotes + proposal.againstVotes < quorumVotes) {
            return false; // Quorum not reached
        }

        return proposal.forVotes > proposal.againstVotes;
    }
}
