require("dotenv").config();
const { ethers } = require("ethers");

async function main() {
	// Load environment variables
	const INFURA_KEY = process.env.INFURA_KEY ?? "";

	const privateKey = process.env.DEPLOYER_PRIVATE_KEY;
	const providerUrl = `https://polygon-amoy.infura.io/v3/${INFURA_KEY}`;
	const contractAddressStaking = "0x8ACFE27d85B2ead0bB457a39E60269b2eD364A3c";
	const contractAddressSci = "0x210268375372626a9ED4D1e14298B3ab4135ac02";
	const contractAddressGovRes = "0x2E1dD2068f17737E2052b4cb55CaAB7d41F7B41c";
	const contractAddressPo = "0x91a81E15401b9Cb546288e2583Bb72605d0e48D9";
	const newGovOpsAddress = "0xcd48E3b0a602CcbA811b02fec95F76ddEa3625C9";

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
