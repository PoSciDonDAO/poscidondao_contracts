require("dotenv").config();
const { ethers } = require("ethers");

async function main() {
	// Load environment variables
	const ALCHEMY_KEY = process.env.ALCHEMY_KEY ?? "";
	const ALCHEMY_URL = process.env.ALCHEMY_URL ?? "";
	const providerUrl = `${ALCHEMY_URL}${ALCHEMY_KEY}`;
	const privateKey = process.env.DEPLOYER_PRIVATE_KEY;
	const contractAddress = "0xf5369906e03C0bA84956b7c214188cc38A11E9D3";
	// Connect to the Ethereum network
	const provider = new ethers.providers.JsonRpcProvider(providerUrl);
	const wallet = new ethers.Wallet(`0x${privateKey}`, provider);
	const members = ["0x690BF2dB31D39EE0a88fcaC89117b66a588E865a"];
	const abi = [
		// Replace this with the actual ABI for your setGovOps function
		"function removeMembersFromWhitelist(address[] members)",
	];

	// Connect to your contract
	const contract = new ethers.Contract(contractAddress, abi, wallet);

	try {
		const tx1 = await contract.removeMembersFromWhitelist(members);
		console.log("Transaction hash:", tx1.hash);
		const receipt1 = await tx1.wait();
		console.log("Transaction confirmed in block:", receipt1.blockNumber);
	} catch (error) {
		console.error("Error calling addMembersToWhitelist:", error);
	}
}

main().catch(console.error);
