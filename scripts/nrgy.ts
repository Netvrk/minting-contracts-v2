import { ethers } from "hardhat";


async function main() {
    const ownerAddress = "0x57291FE9b6dC5bBeF1451c4789d4e578ce956219";
    const nrgyContract = await ethers.getContractFactory("NRGY");
    const nrgy = await nrgyContract.deploy(ownerAddress);
    await nrgy.waitForDeployment();
    console.log("Minter deployed to:", await nrgy.getAddress());
}

main().catch(console.error);
