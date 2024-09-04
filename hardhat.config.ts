import "@nomicfoundation/hardhat-chai-matchers";
import "@nomicfoundation/hardhat-toolbox";
import "@openzeppelin/hardhat-upgrades";
import "hardhat-gas-reporter";
import { HardhatUserConfig } from "hardhat/config";

import dotenv from "dotenv";

dotenv.config();

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.24",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  networks: {
    mainnet: {
      url: process.env.MAINNET_URL || "",
      accounts:
        process.env.PRIVATE_KEY_MAIN !== undefined
          ? [process.env.PRIVATE_KEY_MAIN]
          : [],
    },
    holesky: {
      url: process.env.HOLESKY_URL || "",
      accounts:
        process.env.PRIVATE_KEY_DEV !== undefined
          ? [process.env.PRIVATE_KEY_DEV]
          : [],
    },
  },
  gasReporter: {
    enabled: false,
    currency: "USD",
  },
  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY,
  },
};

export default config;
