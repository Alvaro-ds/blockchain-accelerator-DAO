# DAO — On-Chain Governance System

A three-contract Ethereum governance system built with Foundry and OpenZeppelin. Token holders create proposals to request treasury funds, vote during a configurable window, and execute passing proposals automatically through the treasury.

## Contracts

| Contract | Purpose |
|---|---|
| `DAOGovernanceToken` | ERC20 token whose balance equals voting power. Supports explicit delegation (token transfer). |
| `DAO` | Core governance logic: proposal creation, voting, cancellation, and execution. |
| `DAOTreasury` | Holds ETH and ERC20 tokens. Disburses funds only on DAO instruction. |

### Governance flow

```
1. Mint / acquire governance tokens
2. createProposal()  — requires ≥ proposalThreshold tokens
3. vote()            — for or against, during the voting window
4. executeProposal() — after voting ends, if quorum met and forVotes > againstVotes
                       → treasury.approveProposal() + treasury.spendFunds()
```

Proposals can be canceled at any time by the proposer or the owner before execution.

## Security properties

- **CEI pattern** — state is updated before any external call in `executeProposal`.
- **DAO-only treasury** — `approveProposal` and `spendFunds` revert unless `msg.sender == address(dao)`.
- **No double-spend** — `executedProposals` mapping blocks a second `spendFunds` call.
- **Owner emergency exit** — `emergencyWithdraw` allows the owner to recover funds independently of governance.
- **OpenZeppelin Ownable** — privileged functions use the audited OZ access-control base.

## Development

### Requirements

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Solidity 0.8.20

### Setup

```shell
git clone <repo-url>
cd DAO
forge install
```

### Build

```shell
forge build
```

### Test

```shell
forge test
forge test -vvv          # verbose output
forge coverage           # branch + line coverage report
```

### Format

```shell
forge fmt
```

### Gas snapshot

```shell
forge snapshot
```

## Deployment

> **Warning:** Deploy with a multisig as owner for any production use. The bootstrap sequence is order-dependent:

```shell
# 1. Deploy governance token
forge create src/DAOGovernanceToken.sol:DAOGovernanceToken \
  --constructor-args "DAO Token" "DAO" <initial_supply> \
  --rpc-url <rpc_url> --private-key <key>

# 2. Deploy treasury (pass address(0) — DAO not yet deployed)
forge create src/DAOTreasury.sol:DAOTreasury \
  --constructor-args 0x0000000000000000000000000000000000000000 \
  --rpc-url <rpc_url> --private-key <key>

# 3. Deploy DAO
forge create src/DAO.sol:DAO \
  --constructor-args <token> <treasury> <threshold> <votingPeriod> <quorum> \
  --rpc-url <rpc_url> --private-key <key>

# 4. Wire treasury to DAO
cast send <treasury_address> "setDAO(address)" <dao_address> \
  --rpc-url <rpc_url> --private-key <key>
```

## Configuration parameters

| Parameter | Description | Example |
|---|---|---|
| `proposalThreshold` | Minimum tokens to submit a proposal (wei) | `1000e18` |
| `votingPeriod` | Voting window in seconds | `604800` (7 days) |
| `quorumVotes` | Minimum total votes for a valid result (wei) | `10000e18` |

The owner can update all three at any time via `DAO.updateConfiguration()`.

## Known limitations

- Voting power is snapshotted at vote time, not at proposal creation — a user can acquire tokens after a proposal opens.
- A user can only have one active delegation at a time.
- Parameter names contain minor typos in the source (`proposalThreshols`, `receipient`, `FundsSpend`) preserved intentionally to avoid breaking existing integrations.

## License

MIT
