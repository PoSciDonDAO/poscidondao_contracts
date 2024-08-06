require("dotenv").config();
const { ethers } = require("ethers");

async function main() {
	// Load environment variables
	const ALCHEMY_KEY = process.env.ALCHEMY_KEY ?? "";

	const privateKey = process.env.DEPLOYER_PRIVATE_KEY;
	const providerUrl = `https://base-sepolia.g.alchemy.com/v2/${ALCHEMY_KEY}`;
	const contractAddress = "0xcC7b82AD381DB7acE9D5d6d6C4D1Ec75334eB55a";
	// Connect to the Ethereum network
	const provider = new ethers.providers.JsonRpcProvider(providerUrl);
	const wallet = new ethers.Wallet(`0x${privateKey}`, provider);
    const members = [
		"0x690BF2dB31D39EE0a88fcaC89117b66a588E865a",
		"0x2Cd5221188390bc6e3a3BAcF7EbB7BCC0FdFC3Fe",
		"0x96f67a852f8D3Bc05464C4F91F97aACE060e247A",
		"0x2cAa8A69F17b415B4De7e3bD9878767221791828",
	];
	const abi = [
		// Replace this with the actual ABI for your setGovOps function
		"function addMembersToWhitelist(address[] members)",
	];

	// Connect to your contract
	const contract = new ethers.Contract(contractAddress, abi, wallet);

	try {
		const tx1 = await contract.addMembersToWhitelist(members);
		console.log("Transaction hash:", tx1.hash);
		const receipt1 = await tx1.wait();
		console.log("Transaction confirmed in block:", receipt1.blockNumber);
	} catch (error) {
		console.error("Error calling addMembersToWhitelist:", error);
	}
}

main().catch(console.error);
