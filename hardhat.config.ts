import "@nomiclabs/hardhat-waffle";
import { task } from "hardhat/config";
import "hardhat-typechain";
import { ethers } from "hardhat";
require("dotenv").config();
require("@nomiclabs/hardhat-waffle");
import "@nomicfoundation/hardhat-verify";

// This is a sample Hardhat task. To learn how to create your own go to
// https://hardhat.org/guides/create-task.html
task("accounts", "Prints the list of accounts", async (taskArgs, hre) => {
	const accounts = await hre.ethers.getSigners();

	for (const account of accounts) {
		const accountBalance = await account.getBalance();
		console.log(
			account.address,
			"balance:",
			hre.ethers.utils.formatEther(accountBalance)
		);
	}
});

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
export default {
	solidity: {
		compilers: [
			{
				version: "0.8.28",
				settings: {
					optimizer: {
						enabled: true,
						runs: 1000,
					},
				},
			},
			// {
			// 	version: "0.8.20",
			// 	settings: {
			// 		optimizer: {
			// 			enabled: true,
			// 			runs: 1000,
			// 		},
			// 	},
			// },
		],
	},
	networks: {
		mainnet: {
			url: `https://eth-mainnet.alchemyapi.io/v2/${process.env.ALCHEMY_MAINNET_API_KEY}`,
			accounts: [`0x${process.env.DEPLOYER_PRIVATE_KEY}`],
		},
		sepolia: {
			url: `https://eth-sepolia.g.alchemy.com/v2/${process.env.ALCHEMY_SEPOLIA_API_KEY}`,
			accounts: [`0x${process.env.DEPLOYER_PRIVATE_KEY}`],
		},
		polygon: {
			url: `https://polygon-mainnet.g.alchemy.com/v2/${process.env.ALCHEMY_POLYGON_MAINNET_API_KEY}`,
			accounts: [`0x${process.env.DEPLOYER_PRIVATE_KEY}`],
		},
		polygonMumbai: {
			url: `https://polygon-mumbai.g.alchemy.com/v2/${process.env.ALCHEMY_POLYGON_TESTNET_API_KEY}`,
			accounts: [`0x${process.env.DEPLOYER_PRIVATE_KEY}`],
		},
		polygonAmoy: {
			url: `https://polygon-amoy.g.alchemy.com/v2/${process.env.ALCHEMY_POLYGON_TESTNET_API_KEY}`,
			accounts: [`0x${process.env.DEPLOYER_PRIVATE_KEY}`],
		},
		optimismMainnet: {
			url: `https://opt-mainnet.g.alchemy.com/v2/${process.env.ALCHEMY_OPTIMISM_MAINNET_API_KEY}`,
			accounts: [`0x${process.env.DEPLOYER_PRIVATE_KEY}`],
		},
		optimismTestnet: {
			url: `https://opt-sepolia.g.alchemy.com/v2/${process.env.ALCHEMY_OPTIMISM_TESTNET_API_KEY}`,
			accounts: [`0x${process.env.DEPLOYER_PRIVATE_KEY}`],
			chainId: 11155420,
		},
		baseMainnet: {
			url: `https://base-mainnet.g.alchemy.com/v2/${process.env.ALCHEMY_KEY}`,
			accounts: [`0x${process.env.DEPLOYER_PRIVATE_KEY}`],
			chainId: 8453,
		},
		baseSepolia: {
			url: `https://base-sepolia.g.alchemy.com/v2/${process.env.ALCHEMY_KEY}`,
			accounts: [`0x${process.env.DEPLOYER_PRIVATE_KEY}`],
			chainId: 84532,
		},
	},
	etherscan: {
		apiKey: {
			mainnet: process.env.ETHERSCAN_API_KEY,
			sepolia: process.env.ETHERSCAN_API_KEY,
			polygon: process.env.POLYGONSCAN_API_KEY,
			polygonMumbai: process.env.POLYGONSCAN_API_KEY,
			polygonAmoy: process.env.POLYGONSCAN_API_KEY,
			optimismMainnet: process.env.OPTIMISMSCAN_API_KEY,
			optimismTestnet: process.env.OPTIMISMSCAN_API_KEY,
			base: process.env.BASESCAN_API_KEY,
			baseSepolia: process.env.BASESCAN_API_KEY
		},
	},
};
