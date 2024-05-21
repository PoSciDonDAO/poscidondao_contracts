require("dotenv").config();
const { ethers } = require("ethers");

async function main() {
	// Load environment variables
	const INFURA_KEY = process.env.INFURA_KEY ?? "";

	const privateKey = process.env.DEPLOYER_PRIVATE_KEY;
	const providerUrl = `https://polygon-amoy.infura.io/v3/${INFURA_KEY}`;
    const contractAddressGovOps = "0x25fbFc486E057b136ea9C0658Ff2F3a4288cccDE";
    const contractAddressGovRes = "0xD00CA7F5a3c9EC6c67Ccc5890e4c7519b38447CA";
    const newStakingAddress = "0xF1a9241FC89E256A3CF18410e1515D3342331308";
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
