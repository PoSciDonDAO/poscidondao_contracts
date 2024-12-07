const ethers = require("ethers");

// Replace with your contract ABI
const abi = ["function addMembersToWhitelist(address[])"];

// const contractAddress = "0xd0AB13e730cb266C66Df3FC6EdDFC2fD944ed87a";

// The addresses you want to add to the whitelist
const addressesToWhitelist = ["0x893ACc97158C51340313db289542460A2eD6f196"];

// Create an instance of the Interface
const iface = new ethers.utils.Interface(abi);

// Encode the data for the transaction
const data = iface.encodeFunctionData("addMembersToWhitelist", [
	addressesToWhitelist,
]);

console.log(data);
