// SPDX-License-Identifer: MIT

pragma solidity 0.8.20;

import "forge-std/Test.sol";
import "../src/DAOGovernanceToken.sol";
import "../src/DAOTreasury.sol";
import "../src/DAO.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract DAOtest is Test {

    // Test addresses
    address public owner = address(1);
    address public user1 = address(2);
    address public user2 = address(3);
    address public user3 = address(4);
    address public delegate = address(5);

    // Contracts
    DAOGovernanceToken public governanceToken;
    DAO public dao;
    DAOTreasury public treasury;

    // Test parameters
    uint256 public constant INITIAL_SUPPLY = 1000000 * 10**18; // 1M tokens
    uint256 public constant PROPOSAL_THRESHOLD = 1000 * 10**18; // 1K tokens
    uint256 public constant VOTING_PERIOD = 7 days; 
    uint256 public constant QUORUM_VOTES = 10000 * 10**18; // 10K tokens

    // Events to test 
    event ProposalCreated(uint256 indexed proposalId, address indexed proposer, string description, address recipient, uint256 amount, address token, uint256 startTime, uint256 endTime);
    event Voted(uint256 indexed proposalId, address indexed voter, bool support, uint256 votes);
    event ProposalExecuted(uint256 indexed proposalId);
    event VotingPowerDelegated(address indexed delegator, address indexed delegate, uint256 amount);

    function setUp() public {
        // Deploy governance token
        vm.startPrank(owner);
        governanceToken = new DAOGovernanceToken("DAO Token", "DAO", INITIAL_SUPPLY);

        // Deploy treasury first (without DAO address initially)
        treasury = new DAOTreasury(address(0));

        // Deploy DAO with treasury address
        dao = new DAO(address(governanceToken), address(treasury), PROPOSAL_THRESHOLD, VOTING_PERIOD, QUORUM_VOTES);

        // Set DAO address in treasury
        treasury.setDAO(address(dao));

        // Distribute tokens to test users
        governanceToken.mint(user1, 50000 * 10**18);
        governanceToken.mint(user2, 30000 * 10**18);
        governanceToken.mint(user3, 20000 * 10**18);
        vm.stopPrank();
    }

    // ===================== Helper Functions =================

    function createTestProposal(string memory description) internal returns(uint256 proposalID) {
        return dao.createProposal(
            description, 
            user1, // recipient
            1 ether, // amount: 1 ETH
            address(0) // token: ETH
        );
    }

    // ============= Governance Token Tests ==============
    
    function testTokenInicialization() public view{
        assertEq(governanceToken.name(), "DAO Token");
        assertEq(governanceToken.symbol(), "DAO");
        assertEq(governanceToken.totalSupply(), 1100000 * 10**18); // Initial + minted to users
        assertEq(governanceToken.balanceOf(owner), INITIAL_SUPPLY); // Initial supply
    }

    function testTokenMinting() public {
        uint256 mintAmount = 1000 * 10**18;
        uint256 user1Amount = governanceToken.balanceOf(user1);

        vm.startPrank(owner);
        governanceToken.mint(user1, mintAmount);
        vm.stopPrank();

        assertEq(governanceToken.balanceOf(user1), user1Amount + mintAmount);
    }

    function testTokenBurning() public {
        uint256 user1Amount = governanceToken.balanceOf(user1);
        uint256 burnAmount = 1000 * 10**18;

        vm.startPrank(user1);
        governanceToken.burn(burnAmount);
        vm.stopPrank();

        assertEq(governanceToken.balanceOf(user1), user1Amount - burnAmount);
    }

    function testVotingPowerDelegation() public {
        uint256 user1Amount = governanceToken.getVotingPower(user1);
        uint256 delegateAmount = 10000 * 10**18;

        vm.startPrank(user1);
        governanceToken.delegateVotingPower(delegate, delegateAmount);
        vm.stopPrank();

        assertEq(governanceToken.getVotingPower(delegate), delegateAmount);
        assertEq(governanceToken.getVotingPower(user1), user1Amount - delegateAmount);
        assertTrue(governanceToken.hasDelegated(user1));
        assertEq(governanceToken.delegates(user1), delegate);
    }

    function testVotingPowerUndelegation() public {
        uint256 user1Amount = governanceToken.getVotingPower(user1);
        uint256 delegateAmount = 10000 * 10**18;

        vm.startPrank(user1);
        governanceToken.delegateVotingPower(delegate, delegateAmount);
        uint256 delegateBalance = governanceToken.getVotingPower(delegate);
        
        uint256 undelegateAmount = 5000 * 10**18;
        governanceToken.undelegateVotingPower(undelegateAmount);
        vm.stopPrank();
        
        assertEq(governanceToken.getVotingPower(delegate), delegateBalance - undelegateAmount);
        assertEq(governanceToken.getVotingPower(user1), (user1Amount - delegateAmount) + undelegateAmount);
    }

    function test_RevertWhen_DelegationToZeroAddress() public {
        uint256 delegateAmount = 1000 * 10**18;

        vm.startPrank(user1);
        vm.expectRevert("Cannot delegate to zero address");
        governanceToken.delegateVotingPower(address(0), delegateAmount);
        vm.stopPrank();
    }

    function test_RevertWhen_DelegationToSelf() public {
        uint256 delegateAmount = 1000 * 10**18;

        vm.startPrank(user1);
        vm.expectRevert("Cannot delegate to self");
        governanceToken.delegateVotingPower(user1, delegateAmount);
        vm.stopPrank();
    }

    // ============== DAO Tests ===================
    function testProposalCreation() public {
        string memory description = "Test proposal for funding";

        vm.startPrank(user1);
        uint256 proposalId = createTestProposal(description);
        vm.stopPrank();

        assertEq(proposalId, 0);
        assertEq(dao.proposalCount(), 1);

        (address proposer, string memory desc, , , uint256 startTime, uint256 endTime, bool executed, bool canceled,,,) = dao.getProposal(0);
        assertEq(proposer, user1);
        assertEq(desc, description);
        assertEq(startTime, block.timestamp);
        assertEq(endTime, block.timestamp + VOTING_PERIOD);
        assertFalse(executed);
        assertFalse(canceled);
    }

    function testVoting() public {
        // Create proposal
        vm.startPrank(user1);
        uint256 proposalId = createTestProposal("Test proposal");
        vm.stopPrank();

        // Vote for the proposal
        vm.startPrank(user2);
        dao.vote(proposalId, true);
        vm.stopPrank();

        // Vote against the proposal
        vm.startPrank(user3);
        dao.vote(proposalId, false);
        vm.stopPrank();

        (,, uint256 forVotes, uint256 againstVotes, , , bool executed, bool canceled, , ,) = dao.getProposal(proposalId);
        assertEq(forVotes, governanceToken.getVotingPower(user2));
        assertEq(againstVotes, governanceToken.getVotingPower(user3));
        assertFalse(executed);
        assertFalse(canceled);
    }

    function test_RevertWhen_VotingTwice() public {
        // Create proposal
        vm.startPrank(user1);
        uint256 proposalId = createTestProposal("Test proposal");
        vm.stopPrank();

        // Vote for the proposal
        vm.startPrank(user2);
        dao.vote(proposalId, true);

        vm.expectRevert("Already voted");
        dao.vote(proposalId, true);
        vm.stopPrank();
    }

    function testProposalExecution() public {
        // Fund treasury with ETH first
        uint256 fundingAmount = 10 ether;
        vm.deal(user1, fundingAmount);
        vm.startPrank(user1);
        treasury.fundTreasury{value: fundingAmount}();
        vm.stopPrank();

        // Create a proposal
        vm.startPrank(user1);
        uint256 proposalId = createTestProposal("Test proposal");
        vm.stopPrank();

        // Vote for the proposal with enough votes to meet quorum
        vm.startPrank(user2);
        dao.vote(proposalId, true);
        vm.stopPrank();

        // Fast forward past voting period
        vm.warp(block.timestamp + VOTING_PERIOD + 1);

        // Execute proposal
        vm.startPrank(user1);
        dao.executeProposal(proposalId);
        vm.stopPrank();

        (,,,,,, bool executed,,,,) = dao.getProposal(proposalId);
        assertTrue(executed);
    }

    function test_RevertWhen_ProposalExecutionBeforeVotingEnds() public {
        // Create proposal
        vm.startPrank(user1);
        uint256 proposalId = createTestProposal("Test proposal");
        vm.stopPrank();

        vm.expectRevert("Voting not ended");
        dao.executeProposal(proposalId);
    }

    function test_RevertWhen_ProposalExecutionInsufficientQuorum() public {
        // Fund treasury with ETH first
        uint256 fundingAmount = 10 ether;
        vm.deal(user1, fundingAmount);
        vm.startPrank(user1);
        treasury.fundTreasury{value: fundingAmount}();
        vm.stopPrank();
        
        // Create proposal
        vm.startPrank(user1);
        uint256 proposalId = createTestProposal("Test proposal");
        vm.stopPrank();
        
        // We make user3 to burn some tokens so he does not reach the quorum
        vm.startPrank(user3);
        governanceToken.burn(15000 * 10**18);
        dao.vote(proposalId, true);
        vm.stopPrank();
        
        // Fast forward past voting period
        vm.warp(block.timestamp + VOTING_PERIOD + 1);
        
        vm.startPrank(user1);
        vm.expectRevert("Quorum not reached");
        dao.executeProposal(proposalId);
        vm.stopPrank();
        
        (,,,,,, bool executed,,,,) = dao.getProposal(proposalId);
        assertFalse(executed);
    }

    function testProposalCancellation() public{
        // Create proposal
        vm.startPrank(user1);
        uint256 proposalId = createTestProposal("Test proposal");
        dao.cancelProposal(proposalId);
        vm.stopPrank();

        (,,,,,,, bool canceled,,,)= dao.getProposal(proposalId);
        assertTrue(canceled);
    }

    function test_RevertWhen_ProposalCancellationByUnauthorized() public {
        vm.startPrank(user1);
        uint256 proposalId = createTestProposal("Test proposal");
        vm.stopPrank();

        vm.startPrank(user2);
        vm.expectRevert("Not authorized to cancel");
        dao.cancelProposal(proposalId);
        vm.stopPrank();

        (,,,,,,, bool canceled,,,)= dao.getProposal(proposalId);
        assertFalse(canceled);
    }

    function testVoteInfo() public {
        vm.startPrank(user1);
        uint256 proposalId = createTestProposal("Test proposal");
        vm.stopPrank();

        vm.startPrank(user2);
        dao.vote(proposalId, true);
        vm.stopPrank();

        (bool hasVoted, bool votedFor) = dao.getVoteInfo(proposalId, user2);
        assertTrue(hasVoted);
        assertTrue(votedFor);

        (hasVoted, votedFor) = dao.getVoteInfo(proposalId, user3);
        assertFalse(hasVoted);
        assertFalse(votedFor);
    }

    function testProposalPassed() public {
        uint256 fundingAmount = 10 ether;
        vm.deal(user1, fundingAmount);
        vm.startPrank(user1);
        treasury.fundTreasury{value: fundingAmount}();
        vm.stopPrank();
        
        vm.startPrank(user1);
        uint256 proposalId = createTestProposal("Test proposal");
        vm.stopPrank();

        vm.startPrank(user2);
        dao.vote(proposalId, true);
        vm.stopPrank();

        vm.startPrank(user3);
        dao.vote(proposalId, false);
        vm.stopPrank();

        vm.warp(block.timestamp + VOTING_PERIOD + 1);

        (bool passed) = dao.proposalPassed(proposalId);
        assertTrue(passed);
    }

    // ============= Treasury Tests ===========

    function testTreasuryFunding() public{
        uint256 fundingAmount = 10 ether;
        
        vm.deal(user1, fundingAmount);
        vm.startPrank(user1);
        treasury.fundTreasury{value: fundingAmount}();
        vm.stopPrank();

        assertEq(treasury.getBalance(address(0)), fundingAmount);
    }

    function testTreasuryTokenFunding() public {
        uint fundingAmount = 1000 * 10**18;

        vm.startPrank(user1);
        governanceToken.approve(address(treasury), fundingAmount);
        treasury.fundTreasuryWithToken(address(governanceToken), fundingAmount);
        vm.stopPrank();

        assertEq(treasury.getBalance(address(governanceToken)), fundingAmount);
    }

    function testProposalApproval() public {
        vm.startPrank(user1);
        uint256 proposalId = createTestProposal("Test proposal");
        vm.stopPrank();
        
        vm.startPrank(address(dao));
        treasury.approveProposal(proposalId);
        vm.stopPrank();

        assertTrue(treasury.isProposalApproved(proposalId));
    }

    function test_RevertWhen_ProposalApprovalByUnauthorized() public {
        vm.startPrank(user1);
        vm.expectRevert("Only DAO can approve proposals");
        treasury.approveProposal(1);
        vm.stopPrank();
    }

    function testFundSpending() public {
        uint256 fundingAmount = 10 ether;
        uint256 spendingAmount = 5 ether;

        vm.deal(user1, fundingAmount);
        vm.startPrank(user1);
        treasury.fundTreasury{value: fundingAmount}();
        
        uint256 proposalId = createTestProposal("Test proposal");
        vm.stopPrank();

        vm.startPrank(address(dao));
        treasury.approveProposal(proposalId);

        treasury.spendFunds(proposalId, user1, spendingAmount, address(0));
        vm.stopPrank();

        assertEq(treasury.getBalance(address(0)), fundingAmount - spendingAmount);
        assertEq(user1.balance, spendingAmount);
        assertTrue(treasury.isProposalExecuted(proposalId));
    }

    function test_RevertWhen_FundSpendingWithoutApproval() public {
        uint256 fundingAmount = 10 ether;
        uint256 spendingAmount = 5 ether;

        vm.deal(user1, fundingAmount);
        vm.startPrank(user1);
        treasury.fundTreasury{value: fundingAmount}();
        
        uint256 proposalId = createTestProposal("Test proposal");
        vm.stopPrank();

        vm.startPrank(address(dao));
        vm.expectRevert("Proposal not approved");
        treasury.spendFunds(proposalId, user1, spendingAmount, address(0));
        vm.stopPrank();
    }
}