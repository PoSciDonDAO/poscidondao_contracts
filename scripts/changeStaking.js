require("dotenv").config();
const { ethers } = require("ethers");

async function main() {
	// Load environment variables
	const INFURA_KEY = process.env.INFURA_KEY ?? "";

	const privateKey = process.env.DEPLOYER_PRIVATE_KEY;
	const providerUrl = `https://polygon-amoy.infura.io/v3/${INFURA_KEY}`;
    const contractAddressGovOps = "0xCF1648C891c48dA4e388D0f3CC0370004D732258";
    const contractAddressGovRes = "0x9Ab8E08bFCc46961cb541c1cA6954D6757D3AD48";
    const newStakingAddress = "0x016ADa49EE0201D7DE802C31E4dA171f331dA0E2";
	// Connect to the Ethereum network
	const provider = new ethers.providers.JsonRpcProvider(providerUrl);
	const wallet = new ethers.Wallet(`0x${privateKey}`, provider);

	// Define the smart contract interface (ABI) for the function you want to call
	const abi = [
		// Replace this with the actual ABI for your setGovOps function
		"function setStakingAddress(address newStakingAddress)",
	];

	// Connect to your contract
	const contractGovOps = new ethers.Contract(
		contractAddressGovOps,
		abi,
		wallet
	);
	const contractGovRes = new ethers.Contract(
		contractAddressGovRes,
		abi,
		wallet
	);

	// Call the setGovOps function
	try {
		const tx1 = await contractGovOps.setStakingAddress(newStakingAddress);
		console.log("Transaction hash:", tx1.hash);
		const receipt1 = await tx1.wait();
		console.log("Transaction confirmed in block:", receipt1.blockNumber);
		const tx2 = await contractGovRes.setStakingAddress(newStakingAddress);
		console.log("Transaction hash:", tx2.hash);
		const receipt2 = await tx2.wait();
		console.log("Transaction confirmed in block:", receipt2.blockNumber);
	} catch (error) {
		console.error("Error calling setGovOps:", error);
	}
}

main().catch(console.error);
