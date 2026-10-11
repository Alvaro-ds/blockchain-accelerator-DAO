// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import "./DAOGovernanceToken.sol";

/**
 * @title IDAOTreasury
 * @dev Interface for DAO Treasury contract functions
 */
interface IDAOTreasury {
    function approveProposal(uint256 proposalId) external;
    function spendFunds(uint256 proposalId, address recipient, uint256 amount, address token) external;
}

/**
 * @title DAO
 * @author Alvaro Dapena
 * @dev Decentralized Autonomous Organization contract 
 * Handles proposal creation, voting and execution
 */
contract DAO is Ownable{

    DAOGovernanceToken public governanceToken;

    IDAOTreasury public treasury;

    // Proposal struct
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

    // DAO configuration
    uint256 proposalThreshold;
    uint256 votingPeriod;
    uint256 quorumVotes;

    // Proposal tracking
    uint256 public proposalCount;
    mapping(uint256 => Proposal) public proposals;

    // Events
    event ProposalCreated(uint256 indexed proposalId, address indexed proposer, string description, address recipient, uint256 amount, address token, uint256 startTime, uint256 endTime);
    event Voted(uint256 indexed proposalId, address indexed voter, bool support, uint256 votes);
    event ProposalExecuted(uint256 indexed proposalId);
    event ProposalCanceled(uint256 indexed proposalId);
    event ConfigurationUpdated(uint256 proposalThreshols, uint256 votingPeriod, uint256 quorumVotes);

    /** 
     * @dev Constructor
     * @param _governanceToken Address of the governance token contract
     * @param _proposalThreshold Minimum tokens required to create a proposal
     * @param _votingPeriod Duration of the voting preiod in seconds
     * @param _quorumVotes Minimum votes required for proposal to pass
     */
    constructor(address _governanceToken,address _treasury, uint256 _proposalThreshold, uint256 _votingPeriod, uint256 _quorumVotes) Ownable(msg.sender) {
        governanceToken = DAOGovernanceToken(_governanceToken);
        treasury = IDAOTreasury(_treasury);
        proposalThreshold = _proposalThreshold;
        votingPeriod = _votingPeriod;
        quorumVotes = _quorumVotes;
    }

    /**
     * @dev Create a new proposal
     * @param description Description of the proposal
     * @param recipient Address to receive funds if proposal passes
     * @param amount Amount of funds to be spent
     * @param token Token address (address(0) for ETH)
     * @return proposalId The ID of the created proposal
     */
    function createProposal(string memory description, address recipient, uint256 amount, address token) external returns(uint256 proposalId) {
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
     * @dev Vote on a proposal
     * @param proposalId ID of the proposal to vote on
     * @param support True for yes, false for no
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
     * @dev Cancel a proposal
     * @param proposalId ID of the proposal to cancel
     */
    function cancelProposal(uint256 proposalId) external {
        Proposal storage proposal = proposals[proposalId];

        require(proposal.proposer != address(0), "Proposal does not exist");
        require(!proposal.executed, "Proposal already executed");
        require(!proposal.canceled, "Proposal already canceled");
        require(msg.sender == proposal.proposer || msg.sender == owner(), "Not authorized to cancle");

        proposal.canceled = true;

        emit ProposalCanceled(proposalId);
    }

    /**
     * @dev Execute a proposal if it has passed
     * @param proposalId ID of the proposal to execute
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

    function getProposal(uint256 proposalId) external view returns(
        address proposer,
        string memory description, 
        uint256 forVotes,
        uint256 againstVotes, 
         uint256 startTime,
        uint256 endTime,
        bool executed,
        bool canceled,
        address recipient,
        uint256 amount,
        address token
    ) {
        Proposal storage proposal = proposals[proposalId];
        return (
            proposal.proposer,
            proposal.description,
            proposal.forVotes,
            proposal.againstVotes,
            proposal.startTime,
            proposal.endTime,
            proposal.executed,
            proposal.canceled,
            proposal.recipient,
            proposal.amount,
            proposal.token
        );
    }

    function getVoteInfo(uint256 proposalId, address voter) external view returns(bool hasVoted, bool votedFor) {
        Proposal storage proposal = proposals[proposalId];
        return(proposal.hasVoted[voter], proposal.votedFor[voter]);
    }

    function updateConfiguration(
        uint256 _proposalThreshold,
        uint256 _votingPeriod,
        uint256 _quorumVotes
    ) external onlyOwner {
        proposalThreshold = _proposalThreshold;
        votingPeriod = _votingPeriod;
        quorumVotes = _quorumVotes;

        emit ConfigurationUpdated(_proposalThreshold, _votingPeriod, _quorumVotes);
    }

    function setTreasury(address _treasury) external onlyOwner {
        require(_treasury != address(0), "Invalid treasury address");
        treasury = IDAOTreasury(_treasury);
    }

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