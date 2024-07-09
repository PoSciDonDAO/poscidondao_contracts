require("dotenv").config();
const { ethers } = require("ethers");

async function main() {
	// Load environment variables
	const INFURA_KEY = process.env.INFURA_KEY ?? "";

	const privateKey = process.env.DEPLOYER_PRIVATE_KEY;
	const providerUrl = `https://polygon-amoy.infura.io/v3/${INFURA_KEY}`;
	const contractAddressGovRes = "0x8798C06cb431557EbB048Ed8F984b06Ae7fee729";

	const newDueDiligenceMembers = [
		// NULL_ADDRESS,
		// "0x2Cd5221188390bc6e3a3BAcF7EbB7BCC0FdFC3Fe",
		"0x59041d70deAEfe849A48E77e0b273DdD072eA9e4",
		// "0x8a7ad9a192cbb31679d0d468c25546f2949c8bb1",
	];
	// Connect to the Ethereum network
	const provider = new ethers.providers.JsonRpcProvider(providerUrl);
	const wallet = new ethers.Wallet(`0x${privateKey}`, provider);

	// Define the smart contract interface (ABI) for the function you want to call
	const abi = [
		// Replace this with the actual ABI for your setGovOps function
		"function grantDueDiligenceRole(address member)",
	];

	// Connect to your contract
	const contractGovRes = new ethers.Contract(
		contractAddressGovRes,
		abi,
		wallet
	);

	// Call the function, 1000 SCI tokens need to be staked
	try {
		for (let i = 0; i < newDueDiligenceMembers.length; i++) {
			const tx1 = await contractGovRes.grantDueDiligenceRole(
				newDueDiligenceMembers[i]
			);
			console.log("Transaction hash:", tx1.hash);
			const receipt1 = await tx1.wait();
			console.log(
				"Transaction confirmed in block:",
				receipt1.blockNumber
			);
		}
	} catch (error) {
		console.error("Error calling Grant Due Diligence Role:", error);
	}
}

main().catch(console.error);
