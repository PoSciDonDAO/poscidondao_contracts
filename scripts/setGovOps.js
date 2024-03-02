require("dotenv").config();
const { ethers } = require("ethers");

async function main() {
	// Load environment variables
	const INFURA_KEY = process.env.INFURA_KEY ?? "";

	const privateKey = process.env.DEPLOYER_PRIVATE_KEY;
	const providerUrl = `https://optimism-sepolia.infura.io/v3/${INFURA_KEY}`;
	const contractAddressStaking = "0x7177A5D2Bc6D50FE857B5E797907C45632C7c43c";
	const contractAddressParticipation =
		"0x8Aed302331bE40532e0DCf780E33b9Bd3668434E";
	const newAddress = "0x9EaFED1c7855839Ed8A7767545F221eDb98b8A16";

	if (!newAddress) {
		console.error(
			"You must provide the new address as a command line argument."
		);
		process.exit(1);
	}

	// Connect to the Ethereum network
	const provider = new ethers.providers.JsonRpcProvider(providerUrl);
	const wallet = new ethers.Wallet(`0x${privateKey}`, provider);

	// Define the smart contract interface (ABI) for the function you want to call
	const abi = [
		// Replace this with the actual ABI for your setGovOps function
		"function setGovOps(address newAddress)",
	];

	// Connect to your contract
	const contractStaking = new ethers.Contract(
		contractAddressStaking,
		abi,
		wallet
	);
	const contractParticipation = new ethers.Contract(
		contractAddressParticipation,
		abi,
		wallet
	);

	// Call the setGovOps function
	try {
		const tx1 = await contractStaking.setGovOps(newAddress);
		console.log("Transaction hash:", tx1.hash);
		const receipt1 = await tx1.wait();
		console.log("Transaction confirmed in block:", receipt1.blockNumber);
		const tx2 = await contractParticipation.setGovOps(newAddress);
		console.log("Transaction hash:", tx2.hash);
		const receipt2 = await tx2.wait();
		console.log("Transaction confirmed in block:", receipt2.blockNumber);
	} catch (error) {
		console.error("Error calling setGovOps:", error);
	}
}

main().catch(console.error);
