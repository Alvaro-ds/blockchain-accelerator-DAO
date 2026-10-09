// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "./DAO.sol";

contract DAOTreasury is Ownable {

    // DAO contract reference
    DAO public dao;

    // Mapping to track approved spending proposals
    mapping(uint256 => bool) public approvedProposals;

    // Mapping to track executed spending proposals
    mapping(uint256 => bool) public executedProposals;

    // Events 
    event ProposalApproved(uint256 indexed proposalId);
    event FundsSpend(uint256 indexed proposalId, address indexed recipient, uint256 amount, address token);
    event TreasuryFunded(address indexed sender, uint256 amount);
    event DAOSet(address indexed dao);

    /**
     * @dev Constructor
     * @param _dao Address of the DAO contract
     */
    constructor(address _dao) Ownable(msg.sender) {
        dao = DAO(_dao);
    }
}