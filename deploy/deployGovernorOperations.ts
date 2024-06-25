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

	const govResAddress = "0xA2cF37B3d04640b0e22bBe229148919d7eCf8Ac1";
	const stakingAddress = "0x0D9666506da4ace5ef4aa10863992853158BB6e2";
	const treasuryWallet = "0x690BF2dB31D39EE0a88fcaC89117b66a588E865a";
	const usdc = "0x08D39BBFc0F63668d539EA8BF469dfdeBAe58246";
	const sciToken = "0x25E0A7767d03461EaF88b47cd9853722Fe05DFD3";
	const poToken = "0xc1709720bE448D8c0C829D3Ab1A4D661E94f327a";
	const signerAddress = "0x690bf2db31d39ee0a88fcac89117b66a588e865a";

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
