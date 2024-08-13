import { ethers, upgrades } from "hardhat";


async function main() {
    const managerAddress = "0x57291FE9b6dC5bBeF1451c4789d4e578ce956219";
    const avatarNFTAddress = "0x79c976BC969B58622E0C924462442b6A1eD20C8f";
    const nrgyAddress = "0x14377ab79fDe67fA3A38a0cf89a83736013acdA6";
    const minterContract = await ethers.getContractFactory("Minter");
    const minter = await upgrades.deployProxy(minterContract, [managerAddress, avatarNFTAddress, nrgyAddress], {
        kind: "uups"
    });
    await minter.waitForDeployment();
    console.log("Minter deployed to:", await minter.getAddress());
}

main().catch(console.error);
