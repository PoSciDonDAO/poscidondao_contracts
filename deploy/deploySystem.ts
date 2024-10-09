"use client";

import { ethers, run, hardhatArguments } from "hardhat";
import { ContractFactory, Signer } from "ethers";
import dotenv from "dotenv";
import fs from "fs";
import { GovernorExecutor } from "../typechain";
dotenv.config();

interface DeployedContracts {
	[key: string]: string;
}

async function main() {
	// Load deployer's private key from the .env file
	const PRIVATE_KEY: string = process.env.DEPLOYER_PRIVATE_KEY || "";

	if (!PRIVATE_KEY)
		throw new Error(
			"⛔️ Private key not detected! Add it to the .env file!"
		);

	const [deployer]: Signer[] = await ethers.getSigners();
	console.log(
		"Deploying contracts with the account:",
		await deployer.getAddress()
	);
	console.log("Account Balance:", (await deployer.getBalance()).toString());

	// Check for the network argument
	if (!hardhatArguments.network) {
		throw new Error("Please pass --network");
	}

	// Step 1: Define common addresses
	const getRpcUrl = () => {
		return `https://base-sepolia.g.alchemy.com/v2/${process.env.ALCHEMY_KEY}`;
	};

	const rpcUrl = getRpcUrl();
	const donation: string = "0x5247514Ee8139f849057721d932701A83679F107";
	const usdc: string = "0x08D39BBFc0F63668d539EA8BF469dfdeBAe58246";
	const admin: string = "0x96f67a852f8d3bc05464c4f91f97aace060e247a";
	const sci: string = "0x8cC93105f240B4aBAF472e7cB2DeC836159AA311";
	const researchFundingWallet: string =
		"0x2Cd5221188390bc6e3a3BAcF7EbB7BCC0FdFC3Fe";
	const signer = "0x690BF2dB31D39EE0a88fcaC89117b66a588E865a";

	// Store deployed contract addresses
	const addresses: DeployedContracts = {};

	// Helper function to deploy and verify contracts
	const deployAndVerify = async (
		contractName: string,
		constructorArgs: any[],
		contractKey: string
		// delayTime: number = 30000
	): Promise<void> => {
		const Contract: ContractFactory = await ethers.getContractFactory(
			contractName
		);
		const contract = await Contract.deploy(...constructorArgs);
		console.log(`${contractName} deployed at:`, contract.address);
		addresses[contractKey] = contract.address;

		// console.log(
		//  `Verifying ${contractName} in ${delayTime / 1000} seconds...`
		// );
		// await contract.deployTransaction.wait(5); // Wait for the transaction to be mined
		// await new Promise((resolve) => setTimeout(resolve, delayTime)); // Wait for verification delay

		// await run("verify:verify", {
		//  address: contract.address,
		//  constructorArguments: constructorArgs,
		// });
		// console.log(`${contractName} has been verified`);
	};

	// 3. Deploy PO (Participation) token
	await deployAndVerify("Po", ["https://baseURI.example/", admin], "po");

	// 4. Deploy PoToSciExchange
	await deployAndVerify(
		"PoToSciExchange",
		[admin, sci, addresses.po],
		"poToSciExchange"
	);

	// 5. Deploy Staking
	await deployAndVerify("Staking", [admin, sci], "staking");

	// 6. Deploy GovernorOperations
	await deployAndVerify(
		"GovernorOperations",
		[addresses.staking, admin, addresses.po, signer],
		"governorOperations"
	);

	// 7. Deploy GovernorResearch
	await deployAndVerify(
		"GovernorResearch",
		[addresses.staking, admin, researchFundingWallet],
		"governorResearch"
	);

	// 8. Deploy GovernorExecutor for both GovernorResearch and GovernorOperations
	await deployAndVerify(
		"GovernorExecutor",
		[admin, 600, addresses.governorOperations, addresses.governorResearch],
		"governorExecutor"
	);

	// 9. Deploy GovernorGuard for both GovernorResearch and GovernorOperations
	await deployAndVerify(
		"GovernorGuard",
		[admin, addresses.governorOperations, addresses.governorResearch],
		"governorGuard"
	);

	console.log("All contracts deployed and verified successfully");
	console.log("Deployed Contract Addresses:", addresses);

	const serverUtilsObject = {
		chainId: hardhatArguments.network === "baseMainnet" ? 8453 : 84532, // base testnet: 84532, base mainnet: 8453
		providerUrl: `${rpcUrl}`,
		explorerLink:
			hardhatArguments.network === "baseMainnet"
				? "https://basescan.org"
				: "https://sepolia.basescan.org",
		admin: admin,
		researchFundingWallet: researchFundingWallet,
		usdc: usdc,
		sci: sci,
		swapAddress: "0x3Cc223D3A738eA81125689355F8C16A56768dF70",
		donation: donation,
		po: addresses.po,
		poToSciExchange: addresses.poToSciExchange,
		staking: addresses.staking,
		governorOperations: addresses.governorOperations,
		governorResearch: addresses.governorResearch,
		governorExecutor: addresses.governorExecutor,
		governorGuard: addresses.governorGuard
	};

	fs.writeFileSync(
		"scripts/deployedContracts.json",
		JSON.stringify(serverUtilsObject, null, 2)
	);

	return serverUtilsObject;
}

main()
	.then((result) => {
		console.log("Deployment completed. Updated Object:");
		console.log(result);
		process.exit(0);
	})
	.catch((error) => {
		console.error(error);
		process.exit(1);
	});
