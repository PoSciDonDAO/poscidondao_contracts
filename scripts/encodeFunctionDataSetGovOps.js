const { ethers } = require("ethers");

function encodeFunctionData(functionSignature, inputs) {
	// Step 1: Compute the function selector (first 4 bytes of the keccak256 hash)
	const functionSelector = ethers.utils
		.keccak256(ethers.utils.toUtf8Bytes(functionSignature))
		.slice(0, 10);

	// Step 2: Prepare the encoded data based on the input type
	let encodedData;

	if (Array.isArray(inputs)) {
		// If the input is an array
		const encodedLength = ethers.utils.hexZeroPad(
			ethers.utils.hexlify(inputs.length),
			32
		);

		const encodedElements = inputs
			.map((input) => {
				return ethers.utils.hexZeroPad(input, 32).slice(2); // Remove '0x' prefix after padding
			})
			.join("");

		const offset =
			"0000000000000000000000000000000000000000000000000000000000000020"; // fixed offset for dynamic data

		encodedData =
			functionSelector + offset + encodedLength + encodedElements;
	} else {
		// If the input is a single value (not an array)
		const encodedInput = ethers.utils.hexZeroPad(inputs, 32).slice(2); // Remove '0x' prefix after padding
		encodedData = functionSelector + encodedInput;
	}

	return encodedData;
}

// Example usage with an array of addresses
const functionSignatureArray = "setGovOps(address)";
const functionInput = "0x0c21dc404a3B634c0EF64919a388Ec1f9686F0ED";

const encodedInputDataArray = encodeFunctionData(
	functionSignatureArray,
	functionInput
);
console.log(encodedInputDataArray);

