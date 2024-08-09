import { ethers, upgrades } from "hardhat";


async function main() {
    const managerAddress = "0x70997970";
    const avatarNFTAddress = "0x5FbDB2315678afecb367f032d93F642f64180aa3";
    const nrgyAddress = "0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512";
    const minterContract = await ethers.getContractFactory("Minter");
    const minter = await upgrades.deployProxy(minterContract, [managerAddress, avatarNFTAddress, nrgyAddress], {
        kind: "uups"
    });
    await minter.waitForDeployment();
    console.log("Minter deployed to:", await minter.getAddress());
}

main().catch(console.error);
