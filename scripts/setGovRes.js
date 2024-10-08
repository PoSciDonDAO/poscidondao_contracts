require("dotenv").config();
const { ethers } = require("ethers");

async function main() {
	// Load environment variables
	const ALCHEMY_KEY = process.env.ALCHEMY_KEY ?? "";
	const ALCHEMY_URL = process.env.ALCHEMY_URL ?? "";
	const providerUrl = `${ALCHEMY_URL}${ALCHEMY_KEY}`;
	const privateKey = process.env.DEPLOYER_PRIVATE_KEY;
	const contractAddressStaking = "0x0D9666506da4ace5ef4aa10863992853158BB6e2";
	const newGovResAddress = "0x0772546B576152f806935A9c57d38C633c05B0d4";

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
