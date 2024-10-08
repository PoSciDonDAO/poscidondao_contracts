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
const functionSignatureArray = "addMembersToWhitelist(address[])";
const addresses = [
	"0xb101a90f179d8eE815BDb0c8315d4C28f8FA5b99",
	"0xF7dd52707034696eFd21AcbDAbA4e3dE555BD488",
	"0xD784862aaA7848Be9C0dcA50958Da932969ef41d",
	"0xFF77ABCA900514BE62374b3F86bacEa033365088",
	"0xD2f8B7A8BA93eA9e14f7bc421a70118da8508E9b",
	"0xd8C98B84755056d193837a5e5b7814c8f6b10590",
	"0x51d93270eA1aD2ad0506c3BE61523823400E114C",
	"0x8b672551D687256BFaB5e447550200Eb625891De",
	"0x9bd74d27c123ff1ac9fe82132f45662865a51c43",
	"0x0F22D9e9421C02E60fFF8823e3d0Ccc4780F5750",
	"0xe4c4E389ffF80E18C63df4691a16ec575781Ca0A",
	"0x3aBCDd4b604385659E34b186d5c0aDB9FFE0403C",
	"0x74da8f4b8a459dad4b7327f2efab2516d140a7ab",
	"0x2E3fe68Bee7922e94EEfc643b1F04E71C6294E93",
	"0xc3d7F06db7E0863DbBa355BaC003344887EEe455",
	"0x39E39b63ac98b15407aBC057155d0fc296C11FE4",
	"0x7DDAfD8EDEaf1182BBF7983c4D778C046a17D9f1",
	"0x23208D88Ea974cc4AA639E84D2b1074D4fb41ac9",
	"0x62B9c3eDef0aDBE15224c8a3f8824DBDEB334e9f",
	"0xFeEf239AE6D6361729fcB8b4Ea60647344d87FEE",
	"0x256ecFb23cF21af9F9E33745c77127892956a687",
	"0x507b0AB4d904A38Dd8a9852239020A5718157EF6",
	"0xAEa5981C8B3D66118523549a9331908136a3e648",
	"0x82Dd06dDC43A4cC7f4eF68833D026C858524C2a9",
	"0xb42a22ec528810aE816482914824e47F4dc3F094",
	"0xe1966f09BD13e92a5aCb18C486cE4c696347A25c",
	"0x1c033d7cb3f57d6772438f95dF8068080Ef23dc9",
	"0x91fd6Ceb1D67385cAeD16FE0bA06A1ABC5E1312e",
	"0x083BcEEb941941e15a8a2870D5a4922b5f07Cc81",
	"0xe5E3aa6188Bd53Cf05d54bB808c0F69B3E658087",
];

const encodedInputDataArray = encodeFunctionData(
	functionSignatureArray,
	addresses
);
console.log(encodedInputDataArray);

