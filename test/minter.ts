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

      await expect(minter.connect(user).setTier(3, tier3.price, tier3.ranges)).to.be.revertedWithCustomError;

      await minter.connect(manager).setTiers([1, 2, 3], [tier1.price, tier2.price, tier3.price], [tier1.ranges, tier2.ranges, tier3.ranges]);

      await expect(minter.connect(manager).setTiers([1, 2], [tier1.price, tier2.price], [tier1.ranges, tier2.ranges, tier3.ranges])).to.be.revertedWithCustomError(minter, "INVALID_ARRAY_LENGTH");

      await expect(minter.connect(manager).setTiers([1, 2], [tier1.price, tier2.price], [tier1.ranges, tier2.ranges,])).to.be.revertedWithCustomError;
    });

    it("Check tiers and prices", async function () {
      const tier1 = await minter.getTokenTier(500);
      const tier2 = await minter.getTokenTier(501);
      const tier3 = await minter.getTokenTier(11200);

      expect(tier1).to.be.equal(1n);
      expect(tier2).to.be.equal(2n);
      expect(tier3).to.be.equal(3n);

      const tier1Detail = await minter.getTier(1);
      const tier2Detail = await minter.getTier(2);
      const tier3Detail = await minter.getTier(3);

      expect(tier1Detail.price).to.be.equal(ethers.parseEther("1"));
      expect(tier2Detail.price).to.be.equal(ethers.parseEther("2"));
      expect(tier3Detail.price).to.be.equal(ethers.parseEther("3"));

      const tier1Price = await minter.getTokenPrice(500);
      const tier2Price = await minter.getTokenPrice(999);
      const tier3Price = await minter.getTokenPrice(1300);

      expect(tier1Price).to.be.equal(ethers.parseEther("1"));
      expect(tier2Price).to.be.equal(ethers.parseEther("2"));
      expect(tier3Price).to.be.equal(ethers.parseEther("3"));

      await expect(minter.getTokenPrice(7500)).to.be.revertedWithCustomError(minter, "INVALID_TIER");

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


    it("Mint from user with invalid tier token id", async function () {
      const tokenId = 10000;
      await expect(minter.connect(user).mint(userAddress, tokenId)).to.be.revertedWithCustomError(minter, "INVALID_TIER");
    });

    it("Mint with insufficient balance", async function () {
      const tokenId = 10;
      await expect(minter.connect(user2).mint(user2Address, tokenId)).to.be.revertedWithCustomError(minter, "INSUFFICIENT_BALANCE");
    });

    it("Mint from user", async function () {
      const tokenId = 500;
      await minter.connect(user).mint(userAddress, tokenId);
      expect(await avatarNFT.ownerOf(tokenId)).to.be.equal(userAddress);
    });

    it("Bulk Mint from minter", async function () {
      const tokenIds = [100, 600, 1100, 20];
      const tokenIds2 = [200, 8900, 2000, 30];
      await expect(minter.connect(user).bulkMint(userAddress, tokenIds2)).to.be.revertedWithCustomError(minter, "INVALID_TIER");

      await expect(minter.connect(user2).bulkMint(userAddress, tokenIds)).to.be.revertedWithCustomError(minter, "INSUFFICIENT_BALANCE");

      await minter.connect(user).bulkMint(userAddress, tokenIds);
      for (let i = 0; i < tokenIds.length; i++) {
        expect(await avatarNFT.ownerOf(tokenIds[i])).to.be.equal(userAddress);
      }
    });
  });


});
