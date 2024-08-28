require("dotenv").config();
const { ethers } = require("ethers");

async function main() {
	// Load environment variables
	const ALCHEMY_KEY = process.env.ALCHEMY_KEY ?? "";
	const ALCHEMY_URL = process.env.ALCHEMY_URL ?? "";
	const providerUrl = `${ALCHEMY_URL}${ALCHEMY_KEY}`;
	const privateKey = process.env.DEPLOYER_PRIVATE_KEY;
	const contractAddressGovOps = "0x9EaFED1c7855839Ed8A7767545F221eDb98b8A16";

	// Connect to the Ethereum network
	const provider = new ethers.providers.JsonRpcProvider(providerUrl);
	const wallet = new ethers.Wallet(`0x${privateKey}`, provider);

	// Define the smart contract interface (ABI) for the function you want to call
	const abi = [
		// Replace this with the actual ABI for your setGovOps function
		"function setGovParams(bytes32 _param,uint256 _data)",
	];

	// Connect to your contract
	const contractGovOps = new ethers.Contract(
		contractAddressGovOps,
		abi,
		wallet
	);

	// Call the setGovOps function
	try {
		const tx1 = await contractGovOps.setGovParams(
			"0x70726f706f73616c4c69666554696d6500000000000000000000000000000000",
			"86400"
		);
		console.log("Transaction hash:", tx1.hash);
		const receipt1 = await tx1.wait();
		console.log("Transaction confirmed in block:", receipt1.blockNumber);
	} catch (error) {
		console.error("Error calling setGovOps:", error);
	}
}

main().catch(console.error);
