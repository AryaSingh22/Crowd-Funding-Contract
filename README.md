# Crowd Funding Contract

A simple yet robust Ethereum crowdfunding smart contract with milestone-based fund releases governed by contributor-weighted votes. Includes a Hardhat test suite and a deployment script.

## Features

- **Pledging and withdrawals**
  - Backers can `pledge()` ETH any time before the deadline.
  - Backers can `withdrawPledge(amount)` before the deadline.
- **Campaign result finalization**
  - After the deadline, anyone can call `finalizeCampaign()`.
  - If `totalRaised >= goal` → campaign is successful; otherwise failed and refunds are enabled.
- **Refunds (pull pattern)**
  - If failed (or creator cancels a previously successful campaign), backers can `claimRefund()`.
- **Milestone-based releases with voting**
  - Creator defines milestones at deployment (title + amount).
  - Creator starts a vote per milestone via `startMilestoneVote(milestoneId, votingPeriodSeconds)`.
  - Backers vote with weight proportional to their current contribution using `voteOnMilestone(milestoneId, support)`.
  - After the voting deadline, `finalizeMilestoneVote(milestoneId)` releases milestone funds if YES weight ≥ 50% of `totalRaised` at the time of voting.
- **Emergency cancel**
  - `creatorCancelAndRefund()` allows the creator to cancel a previously successful campaign, enabling refunds for backers on remaining funds.
- **Security design**
  - Minimalistic design without external libs.
  - Non-reentrant critical functions via a simple lock modifier.
  - Pull-over-push pattern for refunds.

## Contract

- File: `CrowdFunding.sol`
- Name: `CrowdfundingKickstart`
- Constructor params:
  - `string _title`
  - `uint256 _goal` ( wei )
  - `uint256 _durationSeconds`
  - `string[] _milestoneTitles`
  - `uint256[] _milestoneAmounts` (sum must be ≤ goal)

### Key Methods

- `pledge()` payable: Contribute ETH before the deadline.
- `withdrawPledge(uint256 amount)`: Withdraw part/all of your pledge before the deadline.
- `finalizeCampaign()`: Determine success/failure after the deadline.
- `claimRefund()`: Claim your refund if the campaign failed (or creator canceled after success).
- `startMilestoneVote(uint256 milestoneId, uint256 votingPeriodSeconds)`: Creator opens voting for the next unreleased milestone.
- `voteOnMilestone(uint256 milestoneId, bool support)`: Backer votes yes/no, weight equals their current contribution.
- `finalizeMilestoneVote(uint256 milestoneId)`: Finalizes voting; releases milestone funds to the creator if threshold is met.
- `creatorCancelAndRefund()`: Creator cancels a previously successful campaign to enable refunds on remaining funds.
- `getMilestone(uint256 idx) → MilestoneView`: Returns info for UI/analytics.
- `milestoneCount() → uint256`: Milestone array length.

## Project Structure

- `CrowdFunding.sol` — the smart contract.
- `crowdfunding.test.js` — Hardhat tests covering pledging, refunds, voting, releases, and cancel flow.
- `deploy.js` — sample Hardhat script for deployment with example parameters.

## Requirements

- Node.js (LTS recommended)
- Yarn or npm
- Hardhat

If you do not have a Hardhat project initialized, create one and place these files accordingly, or add Hardhat to this repo:

```bash
npm install --save-dev hardhat @nomicfoundation/hardhat-toolbox
npx hardhat
```

Then configure networks in `hardhat.config.js` if deploying to a live/test network.

## Quick Start (Hardhat)

1) Install deps (if needed):

```bash
npm install
```

2) Run tests:

```bash
npx hardhat test
```

3) Start a local node and deploy:

```bash
npx hardhat node
# in another terminal
npx hardhat run deploy.js --network localhost
```

4) Interact (examples):

```javascript
// pledge 1 ETH
await crowdfunding.pledge({ value: ethers.utils.parseEther("1") });

// withdraw part of pledge before deadline
await crowdfunding.withdrawPledge(ethers.utils.parseEther("0.5"));

// after deadline
await crowdfunding.finalizeCampaign();

// creator starts milestone 0 vote for 1 hour
await crowdfunding.startMilestoneVote(0, 3600);

// backer votes yes
await crowdfunding.voteOnMilestone(0, true);

// after vote deadline
await crowdfunding.finalizeMilestoneVote(0);

// if failed campaign or canceled by creator, claim refund
await crowdfunding.claimRefund();
```

## Notes & Limitations

- Voting threshold uses ≥ 50% of `totalRaised` at finalization time via `yes * 100 >= 50 * totalRaised` for integer safety.
- If no votes are cast in a voting round, the milestone remains unreleased; the creator can reopen voting later.
- Milestones must be released in order; you cannot vote/release a later milestone before earlier ones are released.
- Contract does not include fee mechanics, KYC, or advanced governance; it is a minimal, educational reference.

## License

SPDX-License-Identifier: MIT
