
const { ethers } = require("ethers");
require("dotenv").config();

/**
 * Execute Donation System configuration transactions
 * This script can be used to configure the Donation System with an EOA
 */
async function main() {
  console.log("Executing Donation System configuration transactions...");
  
  // Load configuration from donationAddresses.json
  const fs = require('fs');
  const path = require('path');
  const addressesPath = path.join(__dirname, '../donationAddresses.json');
  
  if (!fs.existsSync(addressesPath)) {
    console.error("Error: donationAddresses.json not found. Please run the deployment script first.");
    process.exit(1);
  }
  
  const addresses = JSON.parse(fs.readFileSync(addressesPath, 'utf8'));
  const donAddress = addresses.don;
  const donationAddress = addresses.donation;
  
  console.log("DON Token address:", donAddress);
  console.log("Donation contract address:", donationAddress);
  
  // Connect to provider
  const provider = new ethers.providers.JsonRpcProvider(process.env.RPC_URL);
  
  // Load wallet from private key
  const wallet = new ethers.Wallet(process.env.PRIVATE_KEY, provider);
  console.log("Using wallet address:", wallet.address);
  
  // Get contract instances
  const donAbi = ["function setDonation(address donation)", "function donationAddress() view returns (address)"];
  const donContract = new ethers.Contract(donAddress, donAbi, wallet);
  
  // Check current donation address
  const currentDonation = await donContract.donationAddress();
  console.log("Current donation address:", currentDonation);
  
  if (currentDonation.toLowerCase() === donationAddress.toLowerCase()) {
    console.log("Donation address already set correctly. No action needed.");
    return;
  }
  
  // Set donation address
  console.log("Setting donation address to:", donationAddress);
  const tx = await donContract.setDonation(donationAddress);
  console.log("Transaction sent:", tx.hash);
  
  // Wait for transaction to be mined
  const receipt = await tx.wait();
  console.log("Transaction confirmed in block:", receipt.blockNumber);
  console.log("Gas used:", receipt.gasUsed.toString());
  
  console.log("Donation System configuration completed successfully!");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("Error executing transactions:", error);
    process.exit(1);
  });
