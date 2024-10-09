const { ethers } = require("ethers");
const fs = require("fs");
const path = require("path");

function encodeFunctionData(functionSignature, input) {
	const iface = new ethers.utils.Interface([`function ${functionSignature}`]);
	return iface.encodeFunctionData(functionSignature.split("(")[0], [input]);
}

const deployedContractsPath = path.join(__dirname, "../deployedContracts.json");
const deployedContracts = JSON.parse(
	fs.readFileSync(deployedContractsPath, "utf8")
);

const governorExecutorAddress = deployedContracts.governorExecutor;
const governorGuardAddress = deployedContracts.governorGuard;
const governorOperationsAddress = deployedContracts.governorOperations;
const stakingAddress = deployedContracts.staking;
const governorResearchAddress = deployedContracts.governorResearch;
const poTokenAddress = deployedContracts.poToken;

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
		to: poTokenAddress,
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
];

const safeBatchTransaction = {
	version: "1.0",
	chainId: "84532",
	createdAt: Date.now(),
	meta: {
		name: "Setting GovernorExecutor, GovernorGuard, and GovernorOperations addresses for Staking, Research, and PO Token Contracts",
		description:
			"Batch transaction to set the GovernorExecutor address across Staking, GovernorOperations, and Research contracts, set the GovernorGuard address for GovernorOperations and Research, and set the GovernorOperations address in the PO Token and Staking contracts.",
		txBuilderVersion: "1.17.0",
		createdFromSafeAddress: "0x96f67a852f8D3Bc05464C4F91F97aACE060e247A",
		createdFromOwnerAddress: "",
		checksum: ethers.utils.keccak256(
			ethers.utils.toUtf8Bytes("SafeBatchTransaction")
		),
	},
	transactions: transactions,
};

const outputPath = path.join(__dirname, "safeBatchTransaction.json");
fs.writeFileSync(
	outputPath,
	JSON.stringify(safeBatchTransaction, null, 2),
	"utf8"
);

console.log(
	`Batch transaction JSON successfully generated with the updated metadata at: ${outputPath}`
);
