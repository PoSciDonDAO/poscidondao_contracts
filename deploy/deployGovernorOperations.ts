import { ethers, hardhatArguments, run } from "hardhat";
import { getEnv, sleep } from "./utils";
import dotenv from "dotenv";
dotenv.config();

async function main() {
	console.log(`Running deploy script for the GovernorOperations contract`);
	// load wallet private key from env file
	const PRIVATE_KEY = process.env.DEPLOYER_PRIVATE_KEY || "";

	if (!PRIVATE_KEY)
		throw "⛔️ Private key not detected! Add it to the .env file!";

	const [deployer] = await ethers.getSigners();

	console.log("Deploying Contract with the account:", deployer.address);
	console.log("Account Balance:", (await deployer.getBalance()).toString());

	if (!hardhatArguments.network) {
		throw new Error("please pass --network");
	}

	const govResAddress = "0x3212504672D01ec8339B99fF7A12A332Af6bf08a";
	const stakingAddress = "0xD800cBb54DBE5e126d21f859c4E2a6c8DE9986fB";
	const treasuryWallet = "0x96f67a852f8d3bc05464c4f91f97aace060e247a";
	const usdc = "0x08D39BBFc0F63668d539EA8BF469dfdeBAe58246";
	const sciToken = "0x8cC93105f240B4aBAF472e7cB2DeC836159AA311";
	const poToken = "0xa69023aC575084D5aaa621f56AE3EC528F4D2794";
	const signerAddress = "0x690BF2dB31D39EE0a88fcaC89117b66a588E865a";

	const constructorArguments = [
		govResAddress,
		stakingAddress,
		treasuryWallet,
		usdc,
		sciToken,
		poToken,
		signerAddress,
	];

	const Contract = await ethers.getContractFactory("GovernorOperations");
	// Estimate contract deployment fee
	const estimatedGas = await ethers.provider.estimateGas(
		Contract.getDeployTransaction(...constructorArguments)
	);

	// Fetch current gas price
	const gasPrice = await ethers.provider.getGasPrice();

	// Calculate the estimated deployment cost
	const estimatedCost = estimatedGas.mul(gasPrice);

	console.log(
		`Estimated deployment cost: ${ethers.utils.formatEther(
			estimatedCost
		)} ETH`
	);

	const contract = await Contract.deploy(...constructorArguments);
	console.log("Deployed Contract Address:", contract.address);
	console.log("Verifying contract in 2 minutes...");
	await sleep(120000 * 1);
	await run("verify:verify", {
		address: contract.address,
		constructorArguments: [...constructorArguments],
	});
	console.log(`${contract.address} has been verified`);
}

main()
	.then(() => process.exit(0))
	.catch((error) => {
		console.error(error);
		process.exit(1);
	});
