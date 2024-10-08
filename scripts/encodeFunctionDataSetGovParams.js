const { ethers } = require("ethers");

function encodeFunctionData(functionSignature, inputs) {
	// Step 1: Compute the function selector (first 4 bytes of the keccak256 hash)
	const functionSelector = ethers.utils
		.keccak256(ethers.utils.toUtf8Bytes(functionSignature))
		.slice(0, 10); // Function selector is the first 4 bytes (8 hex chars)

	// Step 2: Prepare the encoded data based on the input types
	const abiCoder = new ethers.utils.AbiCoder();
	const encodedData = abiCoder.encode(
		["bytes32", "uint256"], // Adjust the parameter types according to the function signature
		inputs
	);

	// Step 3: Combine function selector and encoded data
	return functionSelector + encodedData.slice(2); // Remove '0x' prefix from encoded data
}

function convertToTimestamp(value, unit) {
	const now = Math.floor(Date.now() / 1000); // Current time in Unix timestamp (seconds)
	let timePeriodInSeconds = 0;

	switch (unit) {
		case "hours":
			timePeriodInSeconds = value * 60 * 60;
			break;
		case "days":
			timePeriodInSeconds = value * 24 * 60 * 60;
			break;
		case "weeks":
			timePeriodInSeconds = value * 7 * 24 * 60 * 60;
			break;
		case "months":
			timePeriodInSeconds = value * 30 * 24 * 60 * 60;
			break;
		default:
			throw new Error(
				'Invalid time unit. Use "hours", "days", "weeks", or "months".'
			);
	}


	return timePeriodInSeconds;
}

// Example usage with an array of inputs
const functionSignature = "setGovParams(bytes32,uint256)";
const functionInputBytes32 =
	"0x70726f706f73616c4c69666554696d6500000000000000000000000000000000"; // ProposalLifeTime in bytes32
const functionInputUint256 = convertToTimestamp(7, "days"); // Convert to timestamp (e.g., 7 days)
const encodedInputData = encodeFunctionData(functionSignature, [
	functionInputBytes32,
	functionInputUint256,
]);

console.log(encodedInputData);
