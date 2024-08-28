require("dotenv").config();
const { ethers } = require("ethers");

async function main() {
	const ALCHEMY_KEY = process.env.ALCHEMY_KEY ?? "";
	const ALCHEMY_URL = process.env.ALCHEMY_URL ?? "";
	const providerUrl = `${ALCHEMY_URL}${ALCHEMY_KEY}`;
	const privateKey = process.env.DEPLOYER_PRIVATE_KEY;
	const contractAddress = "0x99211a0dAf85D74B292EAE4433BC3D5311D22fe0";
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
