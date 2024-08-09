import { ethers } from "hardhat";


async function main() {
    const avatarNFTContract = await ethers.getContractFactory("AvatarNFT");
    const avatarNFT = await avatarNFTContract.deploy();
    await avatarNFT.waitForDeployment();]
    console.log("Avatar NFT deployed to:", await avatarNFT.getAddress());
}

main().catch(console.error);
