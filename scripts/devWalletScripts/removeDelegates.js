require("dotenv").config();
const { ethers } = require("ethers");

async function main() {
	// Load environment variables
	const ALCHEMY_KEY = process.env.ALCHEMY_KEY ?? "";
	const ALCHEMY_URL = process.env.ALCHEMY_URL ?? "";
	const providerUrl = `${ALCHEMY_URL}${ALCHEMY_KEY}`;
	const privateKey = process.env.DEPLOYER_PRIVATE_KEY;
	const contractAddressStaking = "0x0B0464BBC11835EcF8F67Fcb2d98130304dcA162";
	const NULL_ADDRESS = "0x0000000000000000000000000000000000000000";

	const delegates = [
		// NULL_ADDRESS,
		// "0x2Cd5221188390bc6e3a3BAcF7EbB7BCC0FdFC3Fe",
		"0x690BF2dB31D39EE0a88fcaC89117b66a588E865a"
	];
	// Connect to the Ethereum network
	const provider = new ethers.providers.JsonRpcProvider(providerUrl);
	const wallet = new ethers.Wallet(`0x${privateKey}`, provider);

	// Define the smart contract interface (ABI) for the function you want to call
	const abi = [
		// Replace this with the actual ABI for your setGovOps function
		"function removeDelegate(address formerDelegate)",
	];

	// Connect to your contract
	const contractStaking = new ethers.Contract(
		contractAddressStaking,
		abi,
		wallet
	);

	// Call the setGovOps function
	try {
		for (let i = 0; i < delegates.length; i++) {
			const tx1 = await contractStaking.removeDelegate(delegates[i]);
			console.log("Transaction hash:", tx1.hash);
			const receipt1 = await tx1.wait();
			console.log(
				"Transaction confirmed in block:",
				receipt1.blockNumber
			);
		}
	} catch (error) {
		console.error("Error calling setGovOps:", error);
	}
}

main().catch(console.error);
