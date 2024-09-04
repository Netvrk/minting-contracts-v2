import { expect } from "chai";
import { ethers, upgrades } from "hardhat";

describe("Minter Contract", function () {
  let nrgy: any;
  let minter: any;
  let MintNFT: any;
  let nrgyAddress: string;
  let MintNFTAddress: string;
  let minterAddress: string;
  let owner: any;
  let manager: any;
  let user: any;
  let user2: any;
  let user3: any;
  let ownerAddress: string;
  let managerAddress: string;
  let userAddress: string;
  let user2Address: string;
  let user3Address: string;
  let now: number;

  before(async function () {
    [owner, manager, user, user2, user3] = await ethers.getSigners();
    ownerAddress = await owner.getAddress();
    managerAddress = await manager.getAddress();
    userAddress = await user.getAddress();
    user2Address = await user2.getAddress();
    user3Address = await user3.getAddress();
    now = Math.floor(Date.now() / 1000);
  });

  describe("Deployments", async function () {
    it("Deploy Avatar NFT", async function () {
      const MintNFTContract = await ethers.getContractFactory("MintNFT");
      MintNFT = await MintNFTContract.deploy();
      await MintNFT.waitForDeployment();
      MintNFTAddress = await MintNFT.getAddress();
    });

    it("Deploy NRGY", async function () {
      const nrgyContract = await ethers.getContractFactory("NRGY");
      nrgy = await nrgyContract.deploy(ownerAddress);
      await nrgy.waitForDeployment();
      nrgyAddress = await nrgy.getAddress();
    });

    it("Deploy Minter", async function () {
      const MintNFTAddress = await MintNFT.getAddress();
      const nrgyAddress = await nrgy.getAddress();
      const minterContract = await ethers.getContractFactory("Minter");
      minter = await upgrades.deployProxy(minterContract, [managerAddress, MintNFTAddress, nrgyAddress], {
        kind: "uups"
      });
      await minter.waitForDeployment();
      minterAddress = await minter.getAddress();
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
      const MINTER_ROLE = await MintNFT.MINTER_ROLE();
      const minterAddress = await minter.getAddress();
      expect(await MintNFT.hasRole(MINTER_ROLE, minterAddress)).to.be.false;
      await MintNFT.grantRole(MINTER_ROLE, minterAddress);
      expect(await MintNFT.hasRole(MINTER_ROLE, minterAddress)).to.be.true;
    });

    it("Set 100 NRGY to user", async function () {
      const amount = ethers.parseEther("100");
      await nrgy.transfer(userAddress, amount);
      await nrgy.transfer(user2Address, amount);
      expect(await nrgy.balanceOf(userAddress)).to.be.equal(amount);
      expect(await nrgy.balanceOf(user2Address)).to.be.equal(amount);
    });

    it("Set allowance for minter", async function () {
      const allowance = ethers.parseEther("100");
      const minterAddress = await minter.getAddress();
      await nrgy.connect(user).approve(minterAddress, allowance);
      await nrgy.connect(user2).approve(minterAddress, allowance);
      expect(await nrgy.allowance(userAddress, minterAddress)).to.be.equal(allowance);
      expect(await nrgy.allowance(user2Address, minterAddress)).to.be.equal(allowance);
    });

    it("Set payment token", async function () {

      await expect(minter.connect(user).setPaymentToken(nrgyAddress)).to.be.reverted;
      await minter.connect(manager).setPaymentToken(nrgyAddress);
      expect(await minter.getPaymentToken()).to.be.equal(nrgyAddress);
    });

    it("Set mint nft address", async function () {
      await expect(minter.connect(user).setMintNFT(MintNFTAddress)).to.be.reverted;
      await minter.connect(manager).setMintNFT(MintNFTAddress);
      expect(await minter.getMintNFT()).to.be.equal(MintNFTAddress);
    });

    it("Setup Tiers and Prices", async function () {
      const tier1 = {
        price: ethers.parseEther("1"),
        ranges: [
          [1, 500],
          [
            10001,
            10500
          ]
        ]
      };

      const tier2 = {
        price: ethers.parseEther("2"),
        ranges: [
          [501, 1000],
          [
            10501,
            11000
          ]
        ]
      };

      const tier3 = {
        price: ethers.parseEther("3"),
        ranges: [
          [1001, 1500],
          [
            11001,
            11500
          ]
        ]
      };
      await minter.connect(manager).setTier(1, tier1.price, tier1.ranges);
      await minter.connect(manager).setTier(2, tier2.price, tier2.ranges);

      await expect(minter.connect(manager).setTier(21, tier2.price, tier2.ranges)).to.be.revertedWithCustomError(minter, "INVALID_TIER");

      await expect(minter.connect(user).setTier(3, tier3.price, tier3.ranges)).to.be.reverted;

      await minter.connect(manager).setTiers([1, 2, 3], [tier1.price, tier2.price, tier3.price], [tier1.ranges, tier2.ranges, tier3.ranges]);

      await expect(minter.connect(manager).setTiers([1, 2], [tier1.price, tier2.price], [tier1.ranges, tier2.ranges, tier3.ranges])).to.be.revertedWithCustomError(minter, "INVALID_ARRAY_LENGTH");
      await expect(minter.connect(manager).setTiers([1, 2], [tier1.price], [tier1.ranges, tier2.ranges])).to.be.revertedWithCustomError(minter, "INVALID_ARRAY_LENGTH");
      await expect(minter.connect(manager).setTiers([11, 21], [tier1.price, tier2.price], [tier1.ranges, tier2.ranges])).to.be.revertedWithCustomError(minter, "INVALID_TIER");
      await expect(minter.connect(user).setTiers([1, 2], [tier1.price, tier2.price], [tier1.ranges, tier2.ranges])).to.be.reverted;
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


    });

    it("Revert if the contract balance is zero to withdraw", async function () {
      await expect(minter.withdrawFunds(nrgyAddress, managerAddress))
        .to.be.revertedWithCustomError(minter, "ZERO_BALANCE");
    });
  });




  describe("Minting", async function () {
    it("Mint from minter", async function () {
      const tokenId = 1;
      await minter.connect(user).mint(userAddress, tokenId);
      expect(await MintNFT.ownerOf(tokenId)).to.be.equal(userAddress);
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
      await expect(minter.connect(user3).mint(user3Address, tokenId)).to.be.revertedWithCustomError(minter, "INSUFFICIENT_BALANCE");
    });

    it("Mint from user", async function () {
      const tokenId = 500;
      await minter.connect(user).mint(userAddress, tokenId);
      expect(await MintNFT.ownerOf(tokenId)).to.be.equal(userAddress);
    });

    it("Bulk Mint from minter", async function () {
      const tokenIds = [100, 600, 1100, 200];
      const tokenIds2 = [200, 8900, 2000, 300];
      await expect(minter.connect(user).bulkMint(userAddress, tokenIds2)).to.be.revertedWithCustomError(minter, "INVALID_TIER");

      await expect(minter.connect(user3).bulkMint(user3Address, tokenIds)).to.be.revertedWithCustomError(minter, "INSUFFICIENT_BALANCE");

      const tokenIds3 = [1101, 1102, 1103, 1104, 1105, 1106, 1107, 1108, 1109, 1110, 1111, 1112, 1113, 1114, 1115, 1116, 1117, 1118, 1119, 1120, 1121, 1122, 1123, 1124, 1125, 1126, 1127]
      await expect(minter.connect(user).bulkMint(userAddress, tokenIds3)).to.be.revertedWithCustomError(minter, "MAX_MINT_PER_WALLET_EXCEEDED");

      await minter.connect(user).bulkMint(userAddress, tokenIds);
      for (let i = 0; i < tokenIds.length; i++) {
        expect(await MintNFT.ownerOf(tokenIds[i])).to.be.equal(userAddress);
      }
    });

    it("Mint exceeding maxMintPerWallet", async function () {

      let nftsOfUser2 = await MintNFT.balanceOf(user2Address);
      expect(nftsOfUser2).to.be.equal(0n);

      const tokenIds = Array.from({ length: 20 }, (_, i) => i + 51);

      // Mint up to the maxMintPerWallet limit
      await minter.connect(user2).bulkMint(user2Address, tokenIds);
      for (let i = 0; i < tokenIds.length; i++) {
        expect(await MintNFT.ownerOf(tokenIds[i])).to.be.equal(user2Address);
      }

      nftsOfUser2 = await MintNFT.balanceOf(user2Address);
      // Attempt to mint one more token, which should exceed the maxMintPerWallet limit
      await expect(minter.connect(user2).mint(user2Address, 333)).to.be.revertedWithCustomError(minter, "MAX_MINT_PER_WALLET_EXCEEDED");
      await expect(minter.connect(user2).bulkMint(user2Address, [333, 334])).to.be.revertedWithCustomError(minter, "MAX_MINT_PER_WALLET_EXCEEDED");

      // Set max mint per wallet to 30
      await minter.connect(manager).setMaxMintPerWallet(30);

      await expect(minter.connect(user).setMaxMintPerWallet(30)).to.be.reverted;

      // Mint one more and check if it is successful
      await minter.connect(user2).mint(user2Address, 333);
      nftsOfUser2 = await MintNFT.balanceOf(user2Address);
      expect(nftsOfUser2).to.be.equal(21n);
    });

    it("Unapprove and test minting, then approve again", async function () {
      const tokenId = 1000;
      await nrgy.connect(user).approve(minterAddress, 0);
      await expect(minter.connect(user).mint(userAddress, tokenId)).to.be.revertedWithCustomError(minter, "NO_ALLOWANCE");

      await nrgy.connect(user).approve(minterAddress, ethers.MaxUint256);
      await minter.connect(user).mint(userAddress, tokenId);
      expect(await MintNFT.ownerOf(tokenId)).to.be.equal(userAddress);
    });

    it("should withdraw funds successfully", async function () {
      await expect(minter.connect(manager).withdrawFunds(nrgyAddress, managerAddress)).to.be.reverted;
      await minter.withdrawFunds(nrgyAddress, managerAddress);
    });
  });

  describe("Test pause unpause", async function () {
    it("Pause contract", async function () {
      await expect(minter.connect(user).pause()).to.be.reverted;
      await minter.connect(manager).pause();
      await expect(minter.mint(userAddress, 1301)).to.be.reverted;
    });

    it("Unpause contract", async function () {
      await expect(minter.connect(user).unpause()).to.be.reverted;
      await minter.connect(manager).unpause();
      await minter.connect(user).mint(userAddress, 1301);
    });
  });

});
