require("dotenv").config();
const { ethers } = require("ethers");

async function main() {
	// Load environment variables
	const ALCHEMY_KEY = process.env.ALCHEMY_KEY ?? "";
	const ALCHEMY_URL = process.env.ALCHEMY_URL ?? "";
	const providerUrl = `${ALCHEMY_URL}${ALCHEMY_KEY}`;
	const privateKey = process.env.DEPLOYER_PRIVATE_KEY;
	const contractAddressStaking = "0xD800cBb54DBE5e126d21f859c4E2a6c8DE9986fB";
	const contractAddressGovRes = "0x3212504672D01ec8339B99fF7A12A332Af6bf08a";
	const contractAddressPo = "0xa69023aC575084D5aaa621f56AE3EC528F4D2794";
	const newGovOpsAddress = "0xe69836F4C1F690716C414F37CbC69D509418d714";

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
