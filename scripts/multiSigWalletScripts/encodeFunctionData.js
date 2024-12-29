const ethers = require("ethers");

// Replace with your contract ABI
const abi = ["function setMinDelegationPeriod(uint256)"];

// const contractAddress = "0xd0AB13e730cb266C66Df3FC6EdDFC2fD944ed87a";

// The addresses you want to add to the whitelist
// const input = [
// 	"0xFB122889163C7246eac1B7e7d96747f64d20C258",
// 	"0x6546C9e88cC16051e09014f8DFf11737A1977A50",
// ];
const input = 300;

// Create an instance of the Interface
const iface = new ethers.utils.Interface(abi);

// Encode the data for the transaction
const data = iface.encodeFunctionData("setMinDelegationPeriod", [
	input,
]);

console.log(data);
