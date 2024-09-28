import { ethers, run, hardhatArguments } from "hardhat";
import { ContractFactory, Signer } from "ethers";
import dotenv from "dotenv";
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
	const admin: string = "0x96f67a852f8d3bc05464c4f91f97aace060e247a";
	const sciToken: string = "0x8cC93105f240B4aBAF472e7cB2DeC836159AA311";
	const researchFundingWallet: string =
		"0x2Cd5221188390bc6e3a3BAcF7EbB7BCC0FdFC3Fe";

	// Store deployed contract addresses
	const addresses: DeployedContracts = {};

	// Helper function to deploy and verify contracts
	const deployAndVerify = async (
		contractName: string,
		constructorArgs: any[],
		contractKey: string,
		delayTime: number = 120000
	): Promise<void> => {
		const Contract: ContractFactory = await ethers.getContractFactory(
			contractName
		);
		const contract = await Contract.deploy(...constructorArgs);
		console.log(`${contractName} deployed at:`, contract.address);
		addresses[contractKey] = contract.address;

		console.log(
			`Verifying ${contractName} in ${delayTime / 1000} seconds...`
		);
		await contract.deployTransaction.wait(5); // Wait for the transaction to be mined
		await new Promise((resolve) => setTimeout(resolve, delayTime)); // Wait for verification delay

		await run("verify:verify", {
			address: contract.address,
			constructorArguments: constructorArgs,
		});
		console.log(`${contractName} has been verified`);
	};

	// 3. Deploy PO (Participation) token
	await deployAndVerify(
		"PO",
		["https://baseURI.example/", admin], // baseURI and treasuryWallet(admin)
		"poToken"
	);

	// 4. Deploy PoToSciExchange
	await deployAndVerify(
		"PoToSciExchange",
		[admin, sciToken, addresses.poToken], // rewardWallet(admin), sci, and poToken addresses
		"poToSciExchange"
	);

	// 5. Deploy Staking
	await deployAndVerify(
		"Staking",
		[admin, sciToken], // treasuryWallet(admin) and sci address
		"staking"
	);

	// 6. Deploy GovernorOperations
	await deployAndVerify(
		"GovernorOperations",
		[addresses.staking, admin, sciToken, addresses.poToken, admin], // stakingAddress, admin, sci, poToken, signer
		"governorOperations"
	);

	// 7. Deploy GovernorResearch
	await deployAndVerify(
		"GovernorResearch",
		[addresses.staking, admin, researchFundingWallet, sciToken, sciToken], // stakingAddress, admin, researchFundingWallet, usdc, sci
		"governorResearch"
	);

	// 8. Deploy GovernorExecutor for both GovernorResearch and GovernorOperations
	await deployAndVerify(
		"GovernorExecutor",
		[admin, 600, addresses.governorOperations], // admin, delay (600 seconds), governorOperations
		"governorOperationsExecutor"
	);

	await deployAndVerify(
		"GovernorExecutor",
		[admin, 600, addresses.governorResearch], // admin, delay (600 seconds), governorResearch
		"governorResearchExecutor"
	);

	// 9. Deploy GovernorGuard for both GovernorResearch and GovernorOperations
	await deployAndVerify(
		"GovernorGuard",
		[admin, addresses.governorOperations], // admin and GovernorOperations address
		"governorOperationsGuard"
	);

	await deployAndVerify(
		"GovernorGuard",
		[admin, addresses.governorResearch], // admin and GovernorResearch address
		"governorResearchGuard"
	);

	// 10. Deploy Executors (Transaction, Election, Impeachment, GovernorParams)
	// Transaction Executors for both Governors
	await deployAndVerify(
		"Transaction",
		[
			researchFundingWallet,
			ethers.utils.parseUnits("1000", 18),
			ethers.utils.parseUnits("500", 18),
			addresses.governorOperationsExecutor,
		],
		"transactionOperations"
	);

	await deployAndVerify(
		"Transaction",
		[
			researchFundingWallet,
			ethers.utils.parseUnits("2000", 18),
			ethers.utils.parseUnits("1000", 18),
			addresses.governorResearchExecutor,
		],
		"transactionResearch"
	);

	// Election and Impeachment Executors for GovernorOperations
	const targetWallets: string[] = [admin, researchFundingWallet];

	await deployAndVerify(
		"Election",
		[targetWallets, addresses.governorOperations], // targetWallets, GovernorOperations address
		"election"
	);

	await deployAndVerify(
		"Impeachment",
		[targetWallets, addresses.governorOperations], // targetWallets, GovernorOperations address
		"impeachment"
	);

	// GovernorParams Executors for both Governors
	await deployAndVerify(
		"GovernorParams",
		[
			addresses.governorOperations,
			ethers.utils.formatBytes32String("proposalLifeTime"),
			604800,
		], // GovernorOperations, param, data
		"governorParamsOperations"
	);

	await deployAndVerify(
		"GovernorParams",
		[
			addresses.governorResearch,
			ethers.utils.formatBytes32String("proposalLifeTime"),
			604800,
		], // GovernorResearch, param, data
		"governorParamsResearch"
	);

	console.log("All contracts deployed and verified successfully");
	console.log("Deployed Contract Addresses:", addresses);
}

main()
	.then(() => process.exit(0))
	.catch((error) => {
		console.error(error);
		process.exit(1);
	});
