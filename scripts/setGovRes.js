require("dotenv").config();
const { ethers } = require("ethers");

async function main() {
	// Load environment variables
	const INFURA_KEY = process.env.INFURA_KEY ?? "";

	const privateKey = process.env.DEPLOYER_PRIVATE_KEY;
	const providerUrl = `https://polygon-amoy.infura.io/v3/${INFURA_KEY}`;
	const contractAddressStaking = "0x8ACFE27d85B2ead0bB457a39E60269b2eD364A3c";
	const newGovResAddress = "0x2E1dD2068f17737E2052b4cb55CaAB7d41F7B41c";

	if (!newGovResAddress) {
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
		// Replace this with the actual ABI for your setGovRes function
		"function setGovRes(address newGovRes)",
	];

	// Connect to your contract
	const contractStaking = new ethers.Contract(
		contractAddressStaking,
		abi,
		wallet
	);

	// Call the setGovRes function
	try {
		const tx1 = await contractStaking.setGovRes(newGovResAddress);
		console.log("Transaction hash:", tx1.hash);
		const receipt1 = await tx1.wait();
		console.log("Transaction confirmed in block:", receipt1.blockNumber);
	} catch (error) {
		console.error("Error calling setGovRes:", error);
	}
}

main().catch(console.error);
