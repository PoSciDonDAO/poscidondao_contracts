const { ethers } = require("ethers");
const fs = require("fs");
const path = require("path");

// Path to the Solidity file
const deployedAddressesPath = path.join(
	__dirname,
	"../../contracts/DeployedAddresses.sol"
);

// Read and parse the Solidity file
const parseSolidityAddresses = (filePath) => {
	const fileContent = fs.readFileSync(filePath, "utf8");
	const regex = /address constant (\w+) = ([^;]+);/g;
	const addresses = {};
	let match;
	while ((match = regex.exec(fileContent)) !== null) {
		const [, key, value] = match;
		// Remove unnecessary characters and trim
		const address = value.replace(/"/g, "").trim();
		addresses[key] = address;
	}
	return addresses;
};

// Parse addresses from DeployedAddresses.sol
const deployedContracts = parseSolidityAddresses(deployedAddressesPath);

// Extract required contract addresses
const governorExecutorAddress = deployedContracts.governorExecutor;
const governorGuardAddress = deployedContracts.governorGuard;
const governorOperationsAddress = deployedContracts.governorOperations;
const stakingAddress = deployedContracts.sciManager;
const governorResearchAddress = deployedContracts.governorResearch;
const poAddress = deployedContracts.po;

if (
	!governorExecutorAddress ||
	!governorGuardAddress ||
	!governorOperationsAddress ||
	!stakingAddress ||
	!governorResearchAddress ||
	!poAddress
) {
	throw new Error(
		"One or more contract addresses are missing in DeployedAddresses.sol. Please check the file."
	);
}

// Helper function to encode function data
function encodeFunctionData(functionSignature, input) {
	const iface = new ethers.utils.Interface([`function ${functionSignature}`]);
	return iface.encodeFunctionData(functionSignature.split("(")[0], [input]);
}

// Define transactions based on the extracted addresses
const transactions = [
	{
		to: stakingAddress,
		value: "0",
		data: encodeFunctionData(
			"setGovExec(address)",
			governorExecutorAddress
		),
		contractMethod: null,
		contractInputsValues: null,
	},
	{
		to: governorResearchAddress,
		value: "0",
		data: encodeFunctionData(
			"setGovExec(address)",
			governorExecutorAddress
		),
		contractMethod: null,
		contractInputsValues: null,
	},
	{
		to: governorOperationsAddress,
		value: "0",
		data: encodeFunctionData(
			"setGovExec(address)",
			governorExecutorAddress
		),
		contractMethod: null,
		contractInputsValues: null,
	},
	{
		to: governorOperationsAddress,
		value: "0",
		data: encodeFunctionData("setGovGuard(address)", governorGuardAddress),
		contractMethod: null,
		contractInputsValues: null,
	},
	{
		to: governorResearchAddress,
		value: "0",
		data: encodeFunctionData("setGovGuard(address)", governorGuardAddress),
		contractMethod: null,
		contractInputsValues: null,
	},
	{
		to: poAddress,
		value: "0",
		data: encodeFunctionData(
			"setGovOps(address)",
			governorOperationsAddress
		),
		contractMethod: null,
		contractInputsValues: null,
	},
	{
		to: stakingAddress,
		value: "0",
		data: encodeFunctionData(
			"setGovOps(address)",
			governorOperationsAddress
		),
		contractMethod: null,
		contractInputsValues: null,
	},
	{
		to: stakingAddress,
		value: "0",
		data: encodeFunctionData(
			"setGovRes(address)",
			governorResearchAddress
		),
		contractMethod: null,
		contractInputsValues: null,
	}
];


// Create the Safe batch transaction object
const safeBatchTransaction = {
	version: "1.0",
	chainId: "84532",
	createdAt: Date.now(),
	meta: {
		name: "Setting GovernorExecutor, GovernorGuard, and GovernorOperations addresses for SciManager, Research, and PO Contracts",
		description:
			"Batch transaction to set the GovernorExecutor address across SciManager, GovernorOperations, and Research contracts, set the GovernorGuard address for GovernorOperations and Research, and set the GovernorOperations address in the PO and SciManager contracts.",
		txBuilderVersion: "1.17.0",
		createdFromSafeAddress: "0x96f67a852f8D3Bc05464C4F91F97aACE060e247A",
		createdFromOwnerAddress: "",
	},
	transactions: transactions,
};

// Calculate the checksum for the transactions
const checksum = ethers.utils.keccak256(
	ethers.utils.toUtf8Bytes(JSON.stringify(safeBatchTransaction.transactions))
);
safeBatchTransaction.meta.checksum = checksum;

// Define the output file path for the batch transaction JSON
const outputPath = path.join(__dirname, "safeBatchTransaction.json");

try {
	if (fs.existsSync(outputPath)) {
		console.log(
			`Existing file found at ${outputPath}, it will be replaced.`
		);
	}
	fs.writeFileSync(
		outputPath,
		JSON.stringify(safeBatchTransaction, null, 2),
		"utf8"
	);
	console.log(
		`Batch transaction JSON successfully generated and saved at: ${outputPath}`
	);
} catch (err) {
	console.error("Error writing the file:", err);
}
