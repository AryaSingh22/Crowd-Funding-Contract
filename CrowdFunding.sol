// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title CrowdfundingKickstart
 * @notice Simple crowdfunding contract with goal, deadline, refunds if goal not met,
 * and milestone-based release schedule controlled by contributor-weighted votes.
 *
 * Features:
 *  - Contributors pledge ETH until deadline
 *  - If raised < goal at deadline => contributors can claim refunds (pull pattern)
 *  - If raised >= goal at deadline => campaign is Successful
 *  - Creator proposes milestones (set at deployment)
 *  - For each milestone, creator opens a release vote; contributors vote YES/NO
 *    and vote weight is proportional to contribution. If >= 50% YES by weight, milestone funds are released to creator.
 *  - Funds are released in milestone order. Unreleased funds remain claimable only via refund if campaign considered failed.
 *
 * Security notes:
 *  - No external libraries used.
 *  - Uses a simple nonReentrant guard for withdrawals.
 *  - Uses pull-over-push for refunds.
 */

contract CrowdfundingKickstart {
    // --- Events ---
    event Pledged(address indexed backer, uint256 amount);
    event WithdrawnPledge(address indexed backer, uint256 amount);
    event RefundClaimed(address indexed backer, uint256 amount);
    event CampaignSuccessful(uint256 totalRaised);
    event CampaignFailed(uint256 totalRaised);
    event MilestoneVoteStarted(uint256 indexed milestoneId, uint256 votingDeadline);
    event Voted(address indexed backer, uint256 indexed milestoneId, bool support, uint256 weight);
    event MilestoneReleased(uint256 indexed milestoneId, uint256 amount);

    // --- Basic campaign data ---
    address public immutable creator;
    uint256 public immutable goal; // in wei
    uint256 public immutable deadline; // unix timestamp
    string public campaignTitle;

    uint256 public totalRaised; // total pledged
    bool public goalReached; // set after deadline check
    bool public finalized; // whether campaign result evaluated

    // --- Contributor bookkeeping ---
    mapping(address => uint256) public contributions;

    // --- NonReentrant ---
    uint8 private _locked;

    modifier nonReentrant() {
        require(_locked == 0, "Reentrant call");
        _locked = 1;
        _;
        _locked = 0;
    }

    modifier onlyCreator() {
        require(msg.sender == creator, "Only creator");
        _;
    }

    // --- Milestone system ---
    struct Milestone {
        string title;
        uint256 amount; // wei to be released when milestone passes
        bool released;
        bool votingActive;
        uint256 votingDeadline;
        uint256 yesWeight; // sum of contributor weights who voted yes
        uint256 noWeight;
        mapping(address => bool) voted; // track per-milestone voting
    }

    Milestone[] private milestones;

    // Keep an easy-to-read public array view for milestone metadata
    struct MilestoneView {
        string title;
        uint256 amount;
        bool released;
        bool votingActive;
        uint256 votingDeadline;
        uint256 yesWeight;
        uint256 noWeight;
    }

    // --- Constructor ---
    /// @param _title Campaign title
    /// @param _goal Funding goal in wei
    /// @param _durationSeconds Seconds from now until deadline
    /// @param _milestoneTitles Titles for milestones (optional)
    /// @param _milestoneAmounts Amounts in wei for each milestone (must sum <= _goal)
    constructor(
        string memory _title,
        uint256 _goal,
        uint256 _durationSeconds,
        string[] memory _milestoneTitles,
        uint256[] memory _milestoneAmounts
    ) {
        require(_goal > 0, "Goal > 0");
        require(_durationSeconds > 0, "Duration > 0");
        require(_milestoneTitles.length == _milestoneAmounts.length, "Milestone arrays mismatch");

        creator = msg.sender;
        campaignTitle = _title;
        goal = _goal;
        deadline = block.timestamp + _durationSeconds;

        // initialize milestones
        uint256 sum = 0;
        for (uint256 i = 0; i < _milestoneTitles.length; ++i) {
            require(_milestoneAmounts[i] > 0, "Milestone amount > 0");
            Milestone storage m = milestones.push();
            m.title = _milestoneTitles[i];
            m.amount = _milestoneAmounts[i];
            m.released = false;
            m.votingActive = false;
            m.votingDeadline = 0;
            sum += _milestoneAmounts[i];
        }
        require(sum <= _goal, "Milestone sum exceeds goal");

        _locked = 0;
    }

    // --- Pledging (before deadline) ---
    function pledge() external payable {
        require(block.timestamp < deadline, "Campaign ended");
        require(msg.value > 0, "Must send ETH");

        contributions[msg.sender] += msg.value;
        totalRaised += msg.value;

        emit Pledged(msg.sender, msg.value);
    }

    // Allow backer to withdraw pledge before deadline
    function withdrawPledge(uint256 amount) external nonReentrant {
        require(block.timestamp < deadline, "Cannot withdraw after deadline");
        uint256 bal = contributions[msg.sender];
        require(amount > 0 && amount <= bal, "Invalid amount");

        contributions[msg.sender] = bal - amount;
        totalRaised -= amount;
        (bool sent, ) = msg.sender.call{value: amount}('');
        require(sent, "ETH transfer failed");

        emit WithdrawnPledge(msg.sender, amount);
    }

    // Evaluate campaign result after deadline
    function finalizeCampaign() public {
        require(block.timestamp >= deadline, "Deadline not reached");
        require(!finalized, "Already finalized");
        finalized = true;

        if (totalRaised >= goal) {
            goalReached = true;
            emit CampaignSuccessful(totalRaised);
        } else {
            goalReached = false;
            emit CampaignFailed(totalRaised);
        }
    }

    // Claim refund if campaign failed (finalize first if needed)
    function claimRefund() external nonReentrant {
        if (!finalized) finalizeCampaign();
        require(!goalReached, "Goal reached - no refunds");
        uint256 contributed = contributions[msg.sender];
        require(contributed > 0, "No contribution");

        contributions[msg.sender] = 0;
        (bool sent, ) = msg.sender.call{value: contributed}('');
        require(sent, "Refund failed");

        emit RefundClaimed(msg.sender, contributed);
    }

    // Creator starts voting for next unreleased milestone (only if campaign successful)
    // votingPeriodSeconds: length of voting window
    function startMilestoneVote(uint256 milestoneId, uint256 votingPeriodSeconds) external onlyCreator {
        require(milestoneId < milestones.length, "Bad milestone");
        if (!finalized) finalizeCampaign();
        require(goalReached, "Campaign not successful");

        Milestone storage m = milestones[milestoneId];
        require(!m.released, "Already released");
        require(!m.votingActive, "Voting already active");
        // ensure milestone order (can't start later milestone before earlier ones released)
        for (uint256 i = 0; i < milestoneId; ++i) {
            require(milestones[i].released, "Previous milestone not released");
        }

        m.votingActive = true;
        m.votingDeadline = block.timestamp + votingPeriodSeconds;

        emit MilestoneVoteStarted(milestoneId, m.votingDeadline);
    }

    // Contributors vote (YES/NO) on active milestone. Weight = their current contribution.
    function voteOnMilestone(uint256 milestoneId, bool support) external {
        require(milestoneId < milestones.length, "Bad milestone");
        Milestone storage m = milestones[milestoneId];
        require(m.votingActive, "Voting not active");
        require(block.timestamp <= m.votingDeadline, "Voting ended");
        require(contributions[msg.sender] > 0, "No contribution to vote with");
        require(!m.voted[msg.sender], "Already voted");

        uint256 weight = contributions[msg.sender];
        m.voted[msg.sender] = true;
        if (support) {
            m.yesWeight += weight;
        } else {
            m.noWeight += weight;
        }

        emit Voted(msg.sender, milestoneId, support, weight);
    }

    // Anyone can finalize voting after deadline; if yesWeight >= 50% of totalRaised, milestone is released.
    function finalizeMilestoneVote(uint256 milestoneId) external nonReentrant {
        require(milestoneId < milestones.length, "Bad milestone");
        Milestone storage m = milestones[milestoneId];
        require(m.votingActive, "Voting not active");
        require(block.timestamp > m.votingDeadline, "Voting still active");

        m.votingActive = false; // close voting

        // if no votes cast, do NOT release automatically; allow creator to propose re-vote or backers to negotiate off-chain
        uint256 yes = m.yesWeight;
        uint256 no = m.noWeight;
        uint256 totalVotes = yes + no;
        if (totalVotes == 0) {
            // voting failed due to no participation; milestone remains unreleased
            return;
        }

        // Pass threshold: yesWeight * 100 >= 50 * totalRaised  => yesWeight >= totalRaised/2
        // Use multiplication to avoid fractions
        if (yes * 100 >= 50 * totalRaised) {
            // release funds for this milestone (pull pattern for creator)
            m.released = true;
            // deduct the amount from a 'locked' pool represented implicitly by totalRaised
            // We will transfer immediately to creator
            uint256 amt = m.amount;
            require(address(this).balance >= amt, "Insufficient contract balance");

            // reduce totalRaised to reflect funds moved out to creator
            totalRaised -= amt;

            (bool sent, ) = payable(creator).call{value: amt}('');
            require(sent, "Transfer to creator failed");

            emit MilestoneReleased(milestoneId, amt);
        } else {
            // voting did not pass; milestone remains unreleased
        }
    }

    // View helpers
    function milestoneCount() external view returns (uint256) {
        return milestones.length;
    }

    function getMilestone(uint256 idx) external view returns (MilestoneView memory mv) {
        require(idx < milestones.length, "Bad idx");
        Milestone storage m = milestones[idx];
        mv.title = m.title;
        mv.amount = m.amount;
        mv.released = m.released;
        mv.votingActive = m.votingActive;
        mv.votingDeadline = m.votingDeadline;
        mv.yesWeight = m.yesWeight;
        mv.noWeight = m.noWeight;
    }

    // Emergency: if creator never starts voting, contributors cannot get their money if goalReached==true.
    // To handle stuck campaigns, we allow contributors to trigger refund reclaim if no milestone progressed within a timeout after finalization.
    // This timeout can be used by contributors to reclaim remaining funds proportionally. For simplicity we provide a function for creator to cancel campaign and return remaining funds proportionally.

    // Creator can cancel the campaign and enable proportional refunds for remaining balance (only if campaign successful earlier)
    function creatorCancelAndRefund() external onlyCreator nonReentrant {
        // allow cancel only if campaign was successful earlier (finalized and goalReached true)
        if (!finalized) finalizeCampaign();
        require(goalReached, "Can only cancel successful campaign");

        // mark as failed for the purpose of refunds and set goalReached false
        goalReached = false;

        // Remaining balance stays in contract; backers can claim refunds (their contributions are still tracked)
    }

    // Fallbacks
    receive() external payable {
        pledge();
    }

    fallback() external payable {
        pledge();
    }
}
