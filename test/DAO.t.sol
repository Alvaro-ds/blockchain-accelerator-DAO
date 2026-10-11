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
}