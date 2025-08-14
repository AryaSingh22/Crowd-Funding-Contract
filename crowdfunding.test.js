const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("CrowdfundingKickstart", function () {
    let Crowdfunding, crowdfunding, creator, backer1, backer2, whale;

    const goal = ethers.utils.parseEther("5"); // 5 ETH
    const milestoneAmounts = [
        ethers.utils.parseEther("2"),
        ethers.utils.parseEther("3"),
    ];
    const milestoneTitles = ["Phase 1", "Phase 2"];

    beforeEach(async function () {
        [creator, backer1, backer2, whale] = await ethers.getSigners();
        Crowdfunding = await ethers.getContractFactory("CrowdfundingKickstart");
        crowdfunding = await Crowdfunding.deploy(
            "Test Campaign",
            goal,
            60, // deadline in seconds
            milestoneTitles,
            milestoneAmounts
        );
    });

    async function fastForward(seconds) {
        await ethers.provider.send("evm_increaseTime", [seconds]);
        await ethers.provider.send("evm_mine");
    }

    it("Should allow pledges and update totalRaised", async function () {
        await crowdfunding.connect(backer1).pledge({ value: ethers.utils.parseEther("1") });
        await crowdfunding.connect(backer2).pledge({ value: ethers.utils.parseEther("2") });

        expect(await crowdfunding.totalRaised()).to.equal(ethers.utils.parseEther("3"));
        expect(await crowdfunding.contributions(backer1.address)).to.equal(ethers.utils.parseEther("1"));
    });

    it("Should allow withdrawing pledge before deadline", async function () {
        await crowdfunding.connect(backer1).pledge({ value: ethers.utils.parseEther("1") });
        await crowdfunding.connect(backer1).withdrawPledge(ethers.utils.parseEther("0.5"));

        expect(await crowdfunding.contributions(backer1.address)).to.equal(ethers.utils.parseEther("0.5"));
    });

    it("Should fail campaign if goal not met and allow refunds", async function () {
        await crowdfunding.connect(backer1).pledge({ value: ethers.utils.parseEther("1") });
        await fastForward(70); // after deadline
        await crowdfunding.finalizeCampaign();

        expect(await crowdfunding.goalReached()).to.be.false;

        const beforeBal = await ethers.provider.getBalance(backer1.address);
        const tx = await crowdfunding.connect(backer1).claimRefund();
        const receipt = await tx.wait();
        const gasCost = receipt.gasUsed.mul(receipt.effectiveGasPrice);

        const afterBal = await ethers.provider.getBalance(backer1.address);
        expect(afterBal.add(gasCost)).to.be.closeTo(beforeBal.add(ethers.utils.parseEther("1")), ethers.utils.parseEther("0.0001"));
    });

    it("Should succeed campaign if goal met", async function () {
        await crowdfunding.connect(backer1).pledge({ value: ethers.utils.parseEther("3") });
        await crowdfunding.connect(backer2).pledge({ value: ethers.utils.parseEther("2") });

        await fastForward(70);
        await crowdfunding.finalizeCampaign();

        expect(await crowdfunding.goalReached()).to.be.true;
    });

    it("Should handle milestone voting and release funds", async function () {
        // Reach goal
        await crowdfunding.connect(backer1).pledge({ value: ethers.utils.parseEther("3") });
        await crowdfunding.connect(backer2).pledge({ value: ethers.utils.parseEther("2") });

        await fastForward(70);
        await crowdfunding.finalizeCampaign();

        // Start milestone vote
        await crowdfunding.connect(creator).startMilestoneVote(0, 60);

        // Both vote YES
        await crowdfunding.connect(backer1).voteOnMilestone(0, true);
        await crowdfunding.connect(backer2).voteOnMilestone(0, true);

        // After vote deadline
        await fastForward(70);

        const beforeCreatorBal = await ethers.provider.getBalance(creator.address);
        const tx = await crowdfunding.finalizeMilestoneVote(0);
        const receipt = await tx.wait();
        const gasCost = receipt.gasUsed.mul(receipt.effectiveGasPrice);

        const afterCreatorBal = await ethers.provider.getBalance(creator.address);

        expect(afterCreatorBal.add(gasCost)).to.be.closeTo(
            beforeCreatorBal.add(ethers.utils.parseEther("2")),
            ethers.utils.parseEther("0.0001")
        );

        const milestone = await crowdfunding.getMilestone(0);
        expect(milestone.released).to.be.true;
    });

    it("Should not release milestone if majority votes NO", async function () {
        // Reach goal
        await crowdfunding.connect(backer1).pledge({ value: ethers.utils.parseEther("3") });
        await crowdfunding.connect(backer2).pledge({ value: ethers.utils.parseEther("2") });

        await fastForward(70);
        await crowdfunding.finalizeCampaign();

        // Start milestone vote
        await crowdfunding.connect(creator).startMilestoneVote(0, 60);

        // Vote NO
        await crowdfunding.connect(backer1).voteOnMilestone(0, false);
        await crowdfunding.connect(backer2).voteOnMilestone(0, false);

        await fastForward(70);
        await crowdfunding.finalizeMilestoneVote(0);

        const milestone = await crowdfunding.getMilestone(0);
        expect(milestone.released).to.be.false;
    });

    it("Should allow creator to cancel and enable refunds for successful campaign", async function () {
        await crowdfunding.connect(backer1).pledge({ value: ethers.utils.parseEther("3") });
        await crowdfunding.connect(backer2).pledge({ value: ethers.utils.parseEther("2") });

        await fastForward(70);
        await crowdfunding.finalizeCampaign();

        expect(await crowdfunding.goalReached()).to.be.true;

        await crowdfunding.connect(creator).creatorCancelAndRefund();
        expect(await crowdfunding.goalReached()).to.be.false;
    });

    it("Should prevent pledging after deadline", async function () {
        await fastForward(70);
        await expect(
            crowdfunding.connect(backer1).pledge({ value: ethers.utils.parseEther("1") })
        ).to.be.revertedWith("Campaign ended");
    });
});
