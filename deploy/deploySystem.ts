"use client";

import { ethers, run, hardhatArguments } from "hardhat";
import { ContractFactory, Signer } from "ethers";
import dotenv from "dotenv";
import fs from "fs";
import path from "path";
dotenv.config();

interface DeployedContracts {
	[key: string]: string | number;
}

function generateSolidityAddressFile(
	deployedContracts: DeployedContracts
): void {
	const contractsDir: string = path.join(__dirname, "..", "contracts");
	const outputPath: string = path.join(contractsDir, "DeployedAddresses.sol");

	if (!fs.existsSync(contractsDir)) {
		fs.mkdirSync(contractsDir, { recursive: true });
	}

	const solidityFileContent: string = `
  // SPDX-License-Identifier: UNLICENSED
  pragma solidity ^0.8.13;

  library DeployedAddresses {
      ${Object.entries(deployedContracts)
			.map(([key, value]) => {
				if (key === "providerUrl" || key === "explorerLink") {
					return `string constant ${key} = ${JSON.stringify(value)};`;
				} else if (ethers.utils.isAddress(value.toString())) {
					const checksummedAddress: string = ethers.utils.getAddress(
						value.toString()
					);
					return `address constant ${key} = ${checksummedAddress};`;
				} else if (typeof value === "number") {
					return `uint constant ${key} = ${value};`;
				} else {
					return `address constant ${key} = ${value};`;
				}
			})
			.join("\n")}
  }
  `;

	fs.writeFileSync(outputPath, solidityFileContent);
	console.log(`DeployedAddresses.sol has been generated at ${outputPath}`);
}

function encodeFunctionData(functionSignature: string, input: any): string {
	const iface = new ethers.utils.Interface([`function ${functionSignature}`]);
	return iface.encodeFunctionData(functionSignature.split("(")[0], [input]);
}

async function main(): Promise<DeployedContracts> {
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

	if (!hardhatArguments.network) throw new Error("Please pass --network");

	const getRpcUrl = (): string => {
		return `https://base-sepolia.g.alchemy.com/v2/${process.env.ALCHEMY_KEY}`;
	};

	const rpcUrl: string = getRpcUrl();
	const donation = "0x5247514Ee8139f849057721d932701A83679F107";
	const usdc = "0x08D39BBFc0F63668d539EA8BF469dfdeBAe58246";
	const admin = "0x96f67a852f8d3bc05464c4f91f97aace060e247a";
	const sci = "0x8cC93105f240B4aBAF472e7cB2DeC836159AA311";
	const researchFundingWallet = "0x2Cd5221188390bc6e3a3BAcF7EbB7BCC0FdFC3Fe";
	const signer = "0x690BF2dB31D39EE0a88fcaC89117b66a588E865a";

	const addresses: DeployedContracts = {};

	const deployAndVerify = async (
		contractName: string,
		constructorArgs: any[],
		contractKey: string
	): Promise<void> => {
		const Contract: ContractFactory = await ethers.getContractFactory(
			contractName
		);
		const contract = await Contract.deploy(...constructorArgs);
		await contract.deployed();
		console.log(`${contractName} deployed at:`, contract.address);
		addresses[contractKey] = contract.address;
	};

	await deployAndVerify("Po", ["https://baseURI.example/", admin], "po");
	await deployAndVerify(
		"PoToSciExchange",
		[admin, sci, addresses.po],
		"poToSciExchange"
	);
	await deployAndVerify("Staking", [admin, sci], "staking");
	await deployAndVerify(
		"GovernorOperations",
		[addresses.staking, admin, addresses.po, signer],
		"governorOperations"
	);
	await deployAndVerify(
		"GovernorResearch",
		[addresses.staking, admin, researchFundingWallet],
		"governorResearch"
	);
	await deployAndVerify(
		"GovernorExecutor",
		[admin, 600, addresses.governorOperations, addresses.governorResearch],
		"governorExecutor"
	);
	await deployAndVerify(
		"GovernorGuard",
		[admin, addresses.governorOperations, addresses.governorResearch],
		"governorGuard"
	);

	console.log("All contracts deployed and verified successfully");

	generateSolidityAddressFile({
		chainId: hardhatArguments.network === "baseMainnet" ? 8453 : 84532,
		providerUrl: rpcUrl,
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
		governorGuard: addresses.governorGuard,
	});

	// Batch Transaction JSON Creation
	const transactions = [
		{
			to: addresses.staking,
			value: "0",
			data: encodeFunctionData(
				"setGovExec(address)",
				addresses.governorExecutor
			),
		},
		{
			to: addresses.governorResearch,
			value: "0",
			data: encodeFunctionData(
				"setGovExec(address)",
				addresses.governorExecutor
			),
		},
		{
			to: addresses.governorOperations,
			value: "0",
			data: encodeFunctionData(
				"setGovExec(address)",
				addresses.governorExecutor
			),
		},
		{
			to: addresses.governorOperations,
			value: "0",
			data: encodeFunctionData(
				"setGovGuard(address)",
				addresses.governorGuard
			),
		},
		{
			to: addresses.governorResearch,
			value: "0",
			data: encodeFunctionData(
				"setGovGuard(address)",
				addresses.governorGuard
			),
		},
		{
			to: addresses.po,
			value: "0",
			data: encodeFunctionData(
				"setGovOps(address)",
				addresses.governorOperations
			),
		},
		{
			to: addresses.staking,
			value: "0",
			data: encodeFunctionData(
				"setGovOps(address)",
				addresses.governorOperations
			),
		},
	];

	const safeBatchTransaction = {
		version: "1.0",
		chainId: hardhatArguments.network === "baseMainnet" ? 8453 : 84532,
		createdAt: Date.now(),
		meta: {
			name: "Setting GovernorExecutor, GovernorGuard, and GovernorOperations addresses for Staking, Research, and PO Contracts",
			description:
				"Batch transaction to set the GovernorExecutor address across Staking, GovernorOperations, and Research contracts, set the GovernorGuard address for GovernorOperations and Research, and set the GovernorOperations address in the PO and Staking contracts.",
			txBuilderVersion: "1.17.0",
			createdFromSafeAddress: admin,
			createdFromOwnerAddress: "",
		},
		transactions: transactions,
		checksum: ethers.utils.keccak256(
			ethers.utils.toUtf8Bytes(JSON.stringify(transactions))
		),
	};

	// Overwrite the `safeBatchTransaction.json` file every time the script is run
	const outputPath = path.join(__dirname, "safeBatchTransaction.json");
	fs.writeFileSync(
		outputPath,
		JSON.stringify(safeBatchTransaction, null, 2),
		"utf8"
	);
	console.log(
		`Batch transaction JSON successfully generated and saved at: ${outputPath}`
	);

	return addresses;
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
