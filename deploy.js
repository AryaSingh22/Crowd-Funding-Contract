const { ethers } = require("hardhat");

async function main() {
    // Campaign settings
    const title = "My Kickstarter Project";
    const goal = ethers.utils.parseEther("5"); // 5 ETH
    const duration = 7 * 24 * 60 * 60; // 7 days
    const milestoneTitles = ["Phase 1", "Phase 2"];
    const milestoneAmounts = [
        ethers.utils.parseEther("2"),
        ethers.utils.parseEther("3")
    ];

    console.log("Deploying CrowdfundingKickstart...");

    const CrowdfundingKickstart = await ethers.getContractFactory("CrowdfundingKickstart");
    const crowdfunding = await CrowdfundingKickstart.deploy(
        title,
        goal,
        duration,
        milestoneTitles,
        milestoneAmounts
    );

    await crowdfunding.deployed();

    console.log(`CrowdfundingKickstart deployed to: ${crowdfunding.address}`);
    console.log(`Campaign title: ${title}`);
    console.log(`Goal: ${ethers.utils.formatEther(goal)} ETH`);
    console.log(`Deadline in: ${duration / 86400} days`);
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
