import { ethers } from "hardhat";


async function main() {
    const MintNFTContract = await ethers.getContractFactory("MintNFT");
    const MintNFT = await MintNFTContract.deploy();
    await MintNFT.waitForDeployment();
    console.log("Avatar NFT deployed to:", await MintNFT.getAddress());
}

main().catch(console.error);
