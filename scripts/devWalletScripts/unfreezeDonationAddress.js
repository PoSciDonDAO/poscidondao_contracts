// Script to unfreeze the donation address in an already deployed DON token
// This script uses ethers.js v5

const { ethers } = require('ethers');
const fs = require('fs');
const path = require('path');
require('dotenv').config();

async function main() {
  // Configuration
  const PRIVATE_KEY = process.env.PRIVATE_KEY;
  if (!PRIVATE_KEY) {
    console.error('Please set your PRIVATE_KEY in a .env file');
    process.exit(1);
  }

  // Connect to the network
  const provider = new ethers.providers.JsonRpcProvider(process.env.RPC_URL || 'https://base-sepolia.g.alchemy.com/v2/YOUR_API_KEY');
  const wallet = new ethers.Wallet(PRIVATE_KEY, provider);
  
  console.log(`Using wallet address: ${wallet.address}`);
  
  // Get DON token address
  const donAddress = process.env.DON_ADDRESS;
  if (!donAddress) {
    console.error('Please set DON_ADDRESS in your .env file');
    process.exit(1);
  }
  
  // Get Donation contract address (optional)
  const donationAddress = process.env.DONATION_ADDRESS;
  
  // Load DON token ABI
  const donAbiPath = path.join(__dirname, '../../artifacts/contracts/tokens/Don.sol/Don.json');
  const donAbi = JSON.parse(fs.readFileSync(donAbiPath, 'utf8')).abi;
  
  // Connect to DON token contract
  const donContract = new ethers.Contract(donAddress, donAbi, wallet);
  
  // Check if the caller is the admin
  const admin = await donContract.admin();
  if (admin.toLowerCase() !== wallet.address.toLowerCase()) {
    console.error(`Error: The wallet address ${wallet.address} is not the admin of the DON token.`);
    console.error(`Current admin is: ${admin}`);
    process.exit(1);
  }
  
  // Check current donation address and frozen status
  try {
    const currentDonationAddress = await donContract.donationAddress();
    console.log(`Current donation address: ${currentDonationAddress}`);
    
    // Check if donation is already set to the desired address
    if (donationAddress && currentDonationAddress.toLowerCase() === donationAddress.toLowerCase()) {
      console.log("Donation address is already set to the desired address.");
      process.exit(0);
    }
    
    // Try to set donation address to check if it's frozen
    let isFrozen = false;
    try {
      // We'll try to set it to the current address (no change) just to test if it's frozen
      const testTx = await donContract.setDonation(currentDonationAddress, { gasLimit: 100000 });
      await testTx.wait();
      console.log("Donation address is not frozen. No need to unfreeze.");
    } catch (error) {
      console.log("Donation address is frozen. Proceeding with unfreezing...");
      isFrozen = true;
    }
    
    if (isFrozen) {
      // Unfreeze the donation address
      console.log("Unfreezing donation address...");
      const unfreezeTx = await donContract.unfreezeDonation();
      await unfreezeTx.wait();
      console.log("Successfully unfrozen donation address setting!");
      
      // If a new donation address was provided, set it
      if (donationAddress && donationAddress !== ethers.constants.AddressZero) {
        console.log(`Setting donation address to: ${donationAddress}`);
        const setTx = await donContract.setDonation(donationAddress);
        await setTx.wait();
        console.log(`Successfully set donation address to: ${donationAddress}`);
      } else {
        console.log("No new donation address provided. You can now set it manually.");
      }
    }
  } catch (error) {
    console.error("Error:", error);
    process.exit(1);
  }
}

// Execute the script
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  }); 