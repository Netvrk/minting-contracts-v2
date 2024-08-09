import { ethers } from "hardhat";


async function main() {
    const ownerAddress = "0x70997970";
    const nrgyContract = await ethers.getContractFactory("NRGY");
    const nrgy = await nrgyContract.deploy(ownerAddress);
    await nrgy.waitForDeployment();
    console.log("Minter deployed to:", await nrgy.getAddress());
}

main().catch(console.error);
