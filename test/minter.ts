import { expect } from "chai";
import { ethers, upgrades } from "hardhat";

describe("Minter Contract", function () {
  let nrgy: any;
  let minter: any;
  let avatarNFT: any;
  let owner: any;
  let manager: any;
  let user: any;
  let user2: any;
  let treasury: any;
  let ownerAddress: string;
  let managerAddress: string;
  let userAddress: string;
  let user2Address: string;
  let treasuryAddress: string;
  let now: number;

  before(async function () {
    [owner, manager, user, user2, treasury] = await ethers.getSigners();
    ownerAddress = await owner.getAddress();
    managerAddress = await manager.getAddress();
    userAddress = await user.getAddress();
    user2Address = await user2.getAddress();
    treasuryAddress = await treasury.getAddress();
    now = Math.floor(Date.now() / 1000);
  });

  describe("Deployments", async function () {
    it("Deploy Avatar NFT", async function () {
      const avatarNFTContract = await ethers.getContractFactory("AvatarNFT");
      avatarNFT = await avatarNFTContract.deploy();
      await avatarNFT.waitForDeployment();
    });

    it("Deploy NRGY", async function () {
      const nrgyContract = await ethers.getContractFactory("NRGY");
      nrgy = await nrgyContract.deploy(ownerAddress);
      await nrgy.waitForDeployment();
    });

    it("Deploy Minter", async function () {
      const avatarNFTAddress = await avatarNFT.getAddress();
      const nrgyAddress = await nrgy.getAddress();
      const minterContract = await ethers.getContractFactory("Minter");
      minter = await upgrades.deployProxy(minterContract, [managerAddress, avatarNFTAddress, nrgyAddress], {
        kind: "uups"
      });
      await minter.waitForDeployment();
    });

  });


  describe("Setup User Roles, Allowance, and Balance", async function () {

    it("Set minter role to manager in Minter contract", async function () {
      const MINTER_ROLE = await minter.MINTER_ROLE();

      expect(await minter.hasRole(MINTER_ROLE, managerAddress)).to.be.false;
      await minter.grantRole(MINTER_ROLE, managerAddress);
      expect(await minter.hasRole(MINTER_ROLE, managerAddress)).to.be.true;
    });

    it("Set Minter role to avatar contract", async function () {
      const MINTER_ROLE = await avatarNFT.MINTER_ROLE();
      const minterAddress = await minter.getAddress();
      expect(await avatarNFT.hasRole(MINTER_ROLE, minterAddress)).to.be.false;
      await avatarNFT.grantRole(MINTER_ROLE, minterAddress);
      expect(await avatarNFT.hasRole(MINTER_ROLE, minterAddress)).to.be.true;
    });

    it("Set 100 NRGY to user", async function () {
      const amount = ethers.parseEther("100");
      await nrgy.transfer(userAddress, amount);
      expect(await nrgy.balanceOf(userAddress)).to.be.equal(amount);
    });

    it("Set allowance for minter", async function () {
      const allowance = ethers.parseEther("100");
      const minterAddress = await minter.getAddress();
      await nrgy.connect(user).approve(minterAddress, allowance);
      expect(await nrgy.allowance(userAddress, minterAddress)).to.be.equal(allowance);
    });

    it("Setup Tiers and Prices", async function () {
      const tier1 = {
        price: ethers.parseEther("1"),
        ranges: [
          {
            start: 1,
            end: 500
          },
          {
            start: 10001,
            end: 10500
          },
        ]
      };

      const tier2 = {
        price: ethers.parseEther("2"),
        ranges: [
          {
            start: 501,
            end: 1000
          },
          {
            start: 10501,
            end: 11000
          }
        ]
      };

      const tier3 = {
        price: ethers.parseEther("3"),
        ranges: [
          {
            start: 1001,
            end: 1500
          },
          {
            start: 11001,
            end: 11500
          }
        ]
      };
      await minter.connect(manager).setTier(1, tier1.price, tier1.ranges);
      await minter.connect(manager).setTier(2, tier2.price, tier2.ranges);
      // await minter.connect(manager).setTiers([1, 2, 3], [tier1.price, tier2.price, tier3.price], [tier1.ranges, tier2.ranges, tier3.ranges]);
    });
  });



  describe("Minting", async function () {
    it("Mint from minter", async function () {
      const tokenId = 1;
      await minter.connect(user).mint(userAddress, tokenId);
      expect(await avatarNFT.ownerOf(tokenId)).to.be.equal(userAddress);
    });

    it("Check balance of user", async function () {
      const balance = ethers.parseEther("99");
      expect(await nrgy.balanceOf(userAddress)).to.be.equal(balance);
    });
  });


});
