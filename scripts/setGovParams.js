require("dotenv").config();
const { ethers } = require("ethers");

async function main() {
	// Load environment variables
	const INFURA_KEY = process.env.INFURA_KEY ?? "";

	const privateKey = process.env.DEPLOYER_PRIVATE_KEY;
	const providerUrl = `https://polygon-mumbai.infura.io/v3/${INFURA_KEY}`;
	const contractAddressGovOps = "0x9EaFED1c7855839Ed8A7767545F221eDb98b8A16";

	// Connect to the Ethereum network
	const provider = new ethers.providers.JsonRpcProvider(providerUrl);
	const wallet = new ethers.Wallet(`0x${privateKey}`, provider);

	// Define the smart contract interface (ABI) for the function you want to call
	const abi = [
		// Replace this with the actual ABI for your setGovOps function
		"function govParams(bytes32 _param,uint256 _data)",
	];

	// Connect to your contract
	const contractGovOps = new ethers.Contract(
		contractAddressGovOps,
		abi,
		wallet
	);

	// Call the setGovOps function
	try {
		const tx1 = await contractGovOps.govParams(
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
