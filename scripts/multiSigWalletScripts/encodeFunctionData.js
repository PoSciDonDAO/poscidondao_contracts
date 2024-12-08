const ethers = require("ethers");

// Replace with your contract ABI
const abi = ["function addMembersToWhitelist(address[])"];

// const contractAddress = "0xd0AB13e730cb266C66Df3FC6EdDFC2fD944ed87a";

// The addresses you want to add to the whitelist
const addressesToWhitelist = [
	"0x2034988e8666ddb29a9a39348036cb13d1598aaa",
	"0xf0ec7d1fbbf5ee3b82d1ea6e34d3c08f0fa21dfc",
];

// Create an instance of the Interface
const iface = new ethers.utils.Interface(abi);

// Encode the data for the transaction
const data = iface.encodeFunctionData("addMembersToWhitelist", [
	addressesToWhitelist,
]);

console.log(data);
