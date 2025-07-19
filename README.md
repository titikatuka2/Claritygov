# 🏛️ ClarityGov - Decentralized Governance System

A comprehensive governance smart contract built on Stacks blockchain that enables decentralized voting on standards and best practices for the Clarity ecosystem.

## 🚀 Features

- **📝 Proposal Creation**: Create detailed proposals with categories and custom voting periods
- **🗳️ Voting System**: Weighted voting with reputation tracking
- **👥 Voter Registration**: Self-registration system for community participation  
- **🤝 Delegation**: Delegate voting power to trusted community members
- **⏰ Time-bound Voting**: Configurable voting periods with automatic finalization
- **📊 Quorum Requirements**: Minimum participation thresholds for valid proposals
- **🏆 Reputation System**: Track voter participation and build community reputation

## 📋 Contract Functions

### Public Functions

#### `register-voter()`
Register yourself as a voter in the governance system
- **Returns**: `(ok true)` on success
- **Initial voting power**: 1
- **Initial reputation**: 0

#### `create-proposal(title, description, voting-period, category)`
Create a new governance proposal
- **title**: Proposal title (max 100 chars)
- **description**: Detailed description (max 500 chars)  
- **voting-period**: Duration in blocks (144-4320 blocks)
- **category**: Proposal category (max 50 chars)
- **Returns**: Proposal ID on success

#### `vote(proposal-id, vote-choice)`
Cast your vote on an active proposal
- **proposal-id**: ID of the proposal to vote on
- **vote-choice**: `true` for yes, `false` for no
- **Requirements**: Must be registered, proposal must be active
- **Effect**: Increases voter reputation

#### `finalize-proposal(proposal-id)`
Finalize a proposal after voting period ends
- **proposal-id**: ID of the proposal to finalize
- **Requirements**: Voting period must be over
- **Result**: Sets status to "passed" or "rejected"

#### `delegate-voting-power(delegate, amount)`
Delegate voting power to another user
- **delegate**: Principal to delegate power to
- **amount**: Amount of voting power to delegate
- **Requirements**: Must have sufficient voting power

### Read-Only Functions

#### `get-proposal(proposal-id)`
Get complete proposal details

#### `get-voter-info(voter)`
Get voter registration status, voting power, and reputation

#### `get-voting-results(proposal-id)`
Get vote counts and totals for a proposal

#### `is-voting-active(proposal-id)`
Check if voting is currently active for a proposal

## 🛠️ Usage Examples

### Register as a Voter
```clarity
(contract-call? .claritygov register-voter)
```

### Create a Proposal
```clarity
(contract-call? .claritygov create-proposal 
  "Implement new standard" 
  "Proposal to adopt new coding standards for Clarity contracts"
  u1000
  "standards")
```

### Vote on a Proposal
```clarity
(contract-call? .claritygov vote u1 true)
```

### Check Proposal Status
```clarity
(contract-call? .claritygov get-proposal u1)
```

## ⚙️ Configuration

- **Minimum Voting Period**: 144 blocks (~24 hours)
- **Maximum Voting Period**: 4320 blocks (~30 days)
- **Default Minimum Quorum**: 100 votes
- **Initial Voting Power**: 1 per registered voter

## 🔒 Security Features

- Prevents double voting on the same proposal
- Time-bound voting periods
- Authorization checks for all actions
- Quorum requirements for proposal validity

## 📈 Governance Categories

Organize proposals by category:
- `standards` - Coding standards and best practices
- `protocol` - Protocol improvements
- `community` - Community initiatives
- `technical` - Technical specifications
- `economic` - Economic parameters

## 🎯 Getting Started

1. Deploy the contract to Stacks blockchain
2. Register as a voter using `register-voter()`
3. Create proposals or vote on existing ones
4. Build reputation through active participation
5. Delegate voting power to trusted community members

## 🤝 Contributing

This governance system is designed to evolve with community input. Participate by:
- Creating thoughtful proposals
- Engaging in community discussions
- Building reputation through consistent participation
- Delegating wisely to active community members


