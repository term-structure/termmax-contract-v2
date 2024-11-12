import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import { config as dotenvConfig } from "dotenv";
import { resolve } from "path";
import { NetworksUserConfig } from "hardhat/types";

dotenvConfig({ path: resolve(__dirname, ".env") });
function getNetworks(): NetworksUserConfig {
  if (!process.env.INFURA_API_KEY || !process.env.ETHEREUM_PRIVATE_KEY) {
    return {};
  }

  const accounts = [`0x${process.env.ETHEREUM_PRIVATE_KEY}`];
  const infuraApiKey = process.env.INFURA_API_KEY;

  return {
    sepolia: {
      url: `https://sepolia.infura.io/v3/${infuraApiKey}`,
      chainId: 11155111,
      accounts,
    },
  };
}

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.27",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  networks: {
    hardhat: {
      chainId: 1337,
    },
    ...getNetworks(),
  },
};

export default config;
