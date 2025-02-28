// Script to manage the donation address in the DON token
// This script allows setting a new donation address and optionally freezing it
// It also provides functionality to unfreeze the donation address if needed

const { ethers } = require('ethers');
const fs = require('fs');
const path = require('path');
const readline = require('readline');
require('dotenv').config();

// Create readline interface for user input
const rl = readline.createInterface({
  input: process.stdin,
  output: process.stdout
});

// Promisify the question function
function question(query) {
  return new Promise(resolve => {
    rl.question(query, resolve);
  });
}

async function main() {
  try {
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
    
    // Load DON token address from JSON file
    let donAddress;
    try {
      const addressesPath = path.join(__dirname, '../donationAddresses.json');
      const addresses = JSON.parse(fs.readFileSync(addressesPath, 'utf8'));
      donAddress = addresses.don;
      console.log(`Loaded DON token address from file: ${donAddress}`);
    } catch (error) {
      console.log('Could not load addresses from file, please enter DON token address manually:');
      donAddress = await question('DON token address: ');
    }
    
    // Load DON token ABI
    const donAbiPath = path.join(__dirname, '../../artifacts/contracts/tokens/Don.sol/Don.json');
    const donAbi = JSON.parse(fs.readFileSync(donAbiPath, 'utf8')).abi;
    
    // Connect to DON token contract
    const donContract = new ethers.Contract(donAddress, donAbi, wallet);
    
    // Check current donation address
    const currentDonationAddress = await donContract.donationAddress();
    console.log(`Current donation address: ${currentDonationAddress || 'Not set'}`);
    
    // Check if donation address is frozen
    let isFrozen = false;
    try {
      // We'll try to set the donation address to the current one to check if it's frozen
      // This will revert if the donation address is frozen
      await donContract.callStatic.setDonation(currentDonationAddress || wallet.address);
      console.log('Donation address is NOT frozen.');
    } catch (error) {
      if (error.message.includes('Frozen')) {
        isFrozen = true;
        console.log('Donation address is currently FROZEN.');
      } else {
        console.log('Error checking if donation address is frozen:', error.message);
      }
    }
    
    // Ask user what action they want to take
    console.log('\nWhat would you like to do?');
    console.log('1. Set a new donation address');
    if (isFrozen) {
      console.log('2. Unfreeze the donation address');
    } else {
      console.log('2. Freeze the donation address');
    }
    console.log('3. Exit');
    
    const action = await question('Enter your choice (1-3): ');
    
    if (action === '1') {
      // Set a new donation address
      const newDonationAddress = await question('Enter the new donation address: ');
      
      if (!ethers.utils.isAddress(newDonationAddress)) {
        console.error('Invalid Ethereum address');
        process.exit(1);
      }
      
      if (isFrozen) {
        console.log('Donation address is frozen. Unfreezing first...');
        const unfreezeTx = await donContract.unfreezeDonation();
        await unfreezeTx.wait();
        console.log('Donation address unfrozen successfully.');
      }
      
      console.log(`Setting donation address to ${newDonationAddress}...`);
      const setDonationTx = await donContract.setDonation(newDonationAddress);
      await setDonationTx.wait();
      console.log('Donation address set successfully.');
      
      // Ask if user wants to freeze the donation address
      const shouldFreeze = await question('Do you want to freeze the donation address? (y/n): ');
      if (shouldFreeze.toLowerCase() === 'y') {
        console.log('Freezing donation address...');
        const freezeTx = await donContract.freezeDonation();
        await freezeTx.wait();
        console.log('Donation address frozen successfully.');
      }
    } else if (action === '2') {
      if (isFrozen) {
        // Unfreeze the donation address
        console.log('Unfreezing donation address...');
        const unfreezeTx = await donContract.unfreezeDonation();
        await unfreezeTx.wait();
        console.log('Donation address unfrozen successfully.');
      } else {
        // Freeze the donation address
        console.log('Freezing donation address...');
        const freezeTx = await donContract.freezeDonation();
        await freezeTx.wait();
        console.log('Donation address frozen successfully.');
      }
    } else {
      console.log('Exiting...');
    }
    
  } catch (error) {
    console.error('Error:', error);
  } finally {
    rl.close();
  }
}

// Execute the script
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  }); 