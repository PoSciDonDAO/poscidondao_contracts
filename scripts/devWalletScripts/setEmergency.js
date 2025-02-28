const { ethers } = require("ethers");
require('dotenv').config();

async function main() {
    // Load and validate environment variables
    const RPC_URL = process.env.RPC_URL;
    if (!RPC_URL) {
        throw new Error("RPC_URL environment variable is not set");
    }

    const privateKey = process.env.PRIVATE_KEY;
    if (!privateKey) {
        throw new Error("PRIVATE_KEY environment variable is not set");
    }

    // Ensure private key has the correct format
    const formattedPrivateKey = privateKey.startsWith('0x') ? privateKey : `0x${privateKey}`;
    const contractAddress = "0xC7974b70B9577317426A19c788a69eA1aB29aaEb";

    // Connect to the network
    const provider = new ethers.providers.JsonRpcProvider(RPC_URL);
    const wallet = new ethers.Wallet(formattedPrivateKey, provider);

    // Define the contract interface (ABI) for the function
    const abi = [
        "function setEmergency()",
    ];

    // Connect to the contract
    const contract = new ethers.Contract(contractAddress, abi, wallet);

    try {
        console.log("Sending setEmergency transaction...");
        // Call setEmergency
        const tx = await contract.setEmergency();
        console.log("Transaction hash:", tx.hash);
        
        console.log("Waiting for transaction confirmation...");
        // Wait for the transaction to be mined
        const receipt = await tx.wait();
        console.log("Transaction confirmed in block:", receipt.blockNumber);
    } catch (error) {
        console.error("Error calling setEmergency:", error.message);
        process.exit(1);
    }
}

main().catch((error) => {
    console.error("Script failed:", error.message);
    process.exit(1);
});