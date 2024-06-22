require("dotenv").config();
const { ethers } = require("ethers");

async function main() {
	// Load environment variables
	const ALCHEMY_KEY = process.env.ALCHEMY_KEY ?? "";

	const privateKey = process.env.DEPLOYER_PRIVATE_KEY;
	const providerUrl = `https://base-sepolia.g.alchemy.com/v2/${ALCHEMY_KEY}`;
	const contractAddressStaking = "0x0D9666506da4ace5ef4aa10863992853158BB6e2";
	const contractAddressSci = "0x25E0A7767d03461EaF88b47cd9853722Fe05DFD3";
	const contractAddressGovRes = "0x2E1dD2068f17737E2052b4cb55CaAB7d41F7B41c";
	const contractAddressPo = "0xc1709720bE448D8c0C829D3Ab1A4D661E94f327a";
	const newGovOpsAddress = "0xe5cc88F15029b825565B5d7Fc88742F156C47e04";

	// Connect to the Ethereum network
	const provider = new ethers.providers.JsonRpcProvider(providerUrl);
	const wallet = new ethers.Wallet(`0x${privateKey}`, provider);

	const abi = [
		"function setGovOps(address newGovOpsAddress)",
	];

	const contractStaking = new ethers.Contract(
		contractAddressStaking,
		abi,
		wallet
	);
	const contractSci = new ethers.Contract(
		contractAddressSci,
		abi,
		wallet
	);
	const contractGovRes = new ethers.Contract(
		contractAddressGovRes,
		abi,
		wallet
	);

	const contractPo = new ethers.Contract(
		contractAddressPo,
		abi,
		wallet
	);

	// Call the setGovOps function
	try {
		const tx1 = await contractStaking.setGovOps(newGovOpsAddress);
		console.log("Transaction hash:", tx1.hash);
		const receipt1 = await tx1.wait();
		console.log("Transaction confirmed in block:", receipt1.blockNumber);
		const tx2 = await contractPo.setGovOps(newGovOpsAddress);
		console.log("Transaction hash:", tx2.hash);
		const receipt2 = await tx2.wait();
		console.log("Transaction confirmed in block:", receipt2.blockNumber);
		const tx3 = await contractGovRes.setGovOps(newGovOpsAddress);
		console.log("Transaction hash:", tx3.hash);
		const receipt3 = await tx3.wait();
		console.log("Transaction confirmed in block:", receipt3.blockNumber);
		const tx4 = await contractSci.setGovOps(newGovOpsAddress);
		console.log("Transaction hash:", tx4.hash);
		const receipt4 = await tx4.wait();
		console.log("Transaction confirmed in block:", receipt4.blockNumber);
	} catch (error) {
		console.error("Error calling setGovOps:", error);
	}
}

main().catch(console.error);
