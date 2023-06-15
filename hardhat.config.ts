import "@nomiclabs/hardhat-waffle";
import "@typechain/hardhat";
import "@openzeppelin/hardhat-upgrades";
import "solidity-coverage";
import { task } from "hardhat/config";

task("accounts", "Prints the list of accounts", async (args, hre) => {
  const accounts = await hre.ethers.getSigners();

  for (const account of accounts) {
    console.log(account.address);
  }
});

export default {
  solidity: {
    compilers: [
      {
        version: "0.8.7",
        settings: {
          optimizer: {
            enabled: false,
            runs: 7500,
          },
        },
      },
      {
        version: "0.8.9",
        settings: {
          optimizer: {
            enabled: true,
            runs: 7500,
          },
        },
      },
      { version: "0.6.0" },
      {
        version: "0.5.17",
        settings: {
          optimizer: {
            enabled: false,
            runs: 7500,
          },
        },
      },
    ],
  },

  defaultNetwork: "hardhat",

  networks: {
    hardhat: {
      forking: {
        // url: "https://api.securerpc.com/v1",
        // blockNumber: 17465652
        url: "https://eth-mainnet.g.alchemy.com/v2/AqlUdmgjvOARQTmzfoQZO-Hi9nsnO_-Q",
      },
    },
  },

  etherscan: {
    apiKey: "<etherscan-api-key>",
  },

  coverage: {
    network: "hardhat",
    outputDirectory: "coverage",
    runs: 1,
  },
};
