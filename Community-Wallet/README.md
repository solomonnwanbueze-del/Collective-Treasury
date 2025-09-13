# Community Fund Smart Contract

A robust Clarity smart contract for managing community funds with decentralized governance through voting and proposal mechanisms.

## Overview

This smart contract enables communities to pool funds and make collective decisions about fund allocation through a transparent voting system. Members can contribute to the fund, create proposals for fund usage, vote on proposals, and execute approved proposals.

## Features

- **Fund Management**: Secure contribution and withdrawal of STX tokens
- **Member Management**: Add/remove community members with configurable voting power
- **Proposal System**: Create detailed funding proposals with categories and descriptions
- **Voting Mechanism**: Weighted voting system based on member voting power
- **Governance**: Quorum requirements and majority voting for proposal execution
- **Reputation System**: Member reputation scores based on participation
- **Security Controls**: Contract pausing, authorization checks, and emergency functions
- **Transparency**: Full audit trail of votes and proposal execution

## Contract Constants

- **Minimum Proposal Amount**: 1 STX (1,000,000 microSTX)
- **Maximum Proposal Amount**: 100,000 STX (100,000,000,000 microSTX)
- **Default Voting Period**: 1,440 blocks (approximately 10 days)
- **Minimum Quorum**: 10% of total members must vote
- **Voting Period Range**: 1-30 days (144-4,320 blocks)

## Data Structures

### Community Members
```clarity
{
  is-member: bool,
  voting-power: uint,
  joined-at: uint,
  reputation-score: uint
}
```

### Proposals
```clarity
{
  proposer: principal,
  recipient: principal,
  amount: uint,
  title: (string-ascii 100),
  description: (string-ascii 500),
  created-at: uint,
  voting-ends-at: uint,
  executed: bool,
  votes-for: uint,
  votes-against: uint,
  total-votes: uint,
  category: (string-ascii 50)
}
```

### Member Votes
```clarity
{
  vote: bool,
  voting-power-used: uint,
  voted-at: uint
}
```

## Public Functions

### Fund Management

#### `contribute-to-fund (amount uint)`
- Allows anyone to contribute STX to the community fund
- Automatically adds contributors as members if they're not already registered
- Increases reputation score for existing members
- **Returns**: Amount contributed

#### `add-member (member principal) (voting-power uint)`
- Adds a new member to the community (fund manager only)
- Sets initial voting power and reputation score
- **Requires**: Fund manager authorization

#### `remove-member (member principal)`
- Removes a member from the community (fund manager only)
- **Requires**: Fund manager authorization

### Proposal Management

#### `create-proposal (recipient principal) (amount uint) (title string) (description string) (category string) (voting-period uint)`
- Creates a new funding proposal
- **Requirements**:
  - Must be a community member
  - Amount between minimum and maximum limits
  - Valid recipient address
  - Voting period between 1-30 days
  - Valid string inputs (non-empty, within length limits)
- **Returns**: Proposal ID

#### `vote-on-proposal (proposal-id uint) (vote bool)`
- Allows members to vote on proposals
- **Requirements**:
  - Must be a community member
  - Cannot vote twice on same proposal
  - Voting period must be active
  - Proposal must not be executed
- **Effects**: Updates vote counts and member reputation

#### `execute-proposal (proposal-id uint)`
- Executes an approved proposal
- **Requirements**:
  - Voting period must be ended
  - Quorum must be met (minimum 10% participation)
  - Majority must support the proposal
  - Sufficient funds must be available
- **Effects**: Transfers funds and marks proposal as executed

### Administrative Functions

#### `pause-contract ()`
- Pauses all contract operations (fund manager only)

#### `unpause-contract ()`
- Resumes contract operations (fund manager only)

#### `transfer-management (new-manager principal)`
- Transfers fund management to a new address (fund manager only)

#### `emergency-withdraw (amount uint) (recipient principal)`
- Emergency fund withdrawal (contract owner only, requires paused contract)

## Read-Only Functions

- `get-fund-balance ()`: Returns total fund balance
- `get-total-members ()`: Returns number of community members
- `get-member-info (member principal)`: Returns member details
- `get-proposal (proposal-id uint)`: Returns proposal information
- `get-proposal-vote (proposal-id uint) (voter principal)`: Returns vote details
- `get-contract-info ()`: Returns contract state summary
- `is-proposal-executable (proposal-id uint)`: Checks if proposal can be executed
- `get-proposal-supporters (proposal-id uint)`: Returns list of supporters
- `get-proposal-opponents (proposal-id uint)`: Returns list of opponents
- `calculate-quorum-for-proposal (proposal-id uint)`: Calculates required quorum

## Error Codes

- `u100`: Not authorized
- `u101`: Proposal not found
- `u102`: Proposal expired
- `u103`: Proposal already executed
- `u104`: Invalid amount
- `u105`: Insufficient funds
- `u106`: Already voted
- `u107`: Voting period active
- `u108`: Minimum quorum not met
- `u109`: Invalid recipient
- `u110`: Contract paused
- `u111`: Member not found
- `u112`: Invalid voting period
- `u113`: Invalid string input

## Security Features

1. **Authorization Controls**: Multiple permission levels (owner, manager, member)
2. **Input Validation**: Comprehensive validation of all inputs
3. **Reentrancy Protection**: Safe transfer patterns
4. **Pause Mechanism**: Emergency stop functionality
5. **Amount Limits**: Min/max proposal amount restrictions
6. **Time-based Controls**: Voting period enforcement
7. **Quorum Requirements**: Minimum participation thresholds

## Usage Examples

### Contributing to the Fund
```clarity
(contract-call? .community-fund contribute-to-fund u5000000) ;; 5 STX
```

### Creating a Proposal
```clarity
(contract-call? .community-fund create-proposal 
  'SP1ABC...XYZ  ;; recipient
  u2000000       ;; 2 STX
  "Website Development"
  "Fund development of new community website with modern features"
  "Development"
  u720)          ;; 5 day voting period
```

### Voting on a Proposal
```clarity
(contract-call? .community-fund vote-on-proposal u1 true) ;; Vote yes on proposal 1
```

### Executing a Proposal
```clarity
(contract-call? .community-fund execute-proposal u1)
```