// Script to generate transaction data for unfreezing the donation address in a DON token
// This script is useful for multisig wallets or when you need to prepare transactions offline

const { ethers } = require('ethers');
const fs = require('fs');
const path = require('path');
require('dotenv').config();

async function main() {
  // Configuration
  const donAddress = process.env.DON_ADDRESS;
  if (!donAddress) {
    console.error('Please set DON_ADDRESS in your .env file');
    process.exit(1);
  }

  // Optional: new donation address to set after unfreezing
  const donationAddress = process.env.DONATION_ADDRESS;
  
  // Load DON token ABI
  const donAbiPath = path.join(__dirname, '../artifacts/contracts/tokens/Don.sol/Don.json');
  const donAbi = JSON.parse(fs.readFileSync(donAbiPath, 'utf8')).abi;
  
  // Create contract interface
  const donInterface = new ethers.utils.Interface(donAbi);
  
  // Generate transaction data for unfreezing donation address
  const unfreezeTxData = donInterface.encodeFunctionData('unfreezeDonation', []);
  
  console.log('\n===== TRANSACTION DATA FOR UNFREEZING DONATION ADDRESS =====');
  console.log('To address:', donAddress);
  console.log('Data:', unfreezeTxData);
  console.log('Gas limit (recommended):', 100000);
  console.log('Value:', 0);
  
  // If a donation address was provided, also generate transaction data for setting it
  if (donationAddress) {
    const setDonationTxData = donInterface.encodeFunctionData('setDonation', [donationAddress]);
    
    console.log('\n===== TRANSACTION DATA FOR SETTING DONATION ADDRESS =====');
    console.log('To address:', donAddress);
    console.log('Data:', setDonationTxData);
    console.log('Gas limit (recommended):', 100000);
    console.log('Value:', 0);
    console.log('\nNote: Execute this transaction AFTER the unfreeze transaction has been confirmed');
  }
  
  // Save transaction data to a JSON file
  const txData = {
    donTokenAddress: donAddress,
    unfreezeTxData: {
      to: donAddress,
      data: unfreezeTxData,
      gasLimit: 100000,
      value: 0
    }
  };
  
  if (donationAddress) {
    txData.setDonationTxData = {
      to: donAddress,
      data: donInterface.encodeFunctionData('setDonation', [donationAddress]),
      gasLimit: 100000,
      value: 0
    };
  }
  
  const jsonOutputPath = path.join(__dirname, 'unfreezeDonationTxData.json');
  fs.writeFileSync(jsonOutputPath, JSON.stringify(txData, null, 2));
  console.log(`\nTransaction data saved to: ${jsonOutputPath}`);
  
  console.log('\n===== INSTRUCTIONS =====');
  console.log('1. Use the transaction data above to create and submit a transaction to unfreeze the donation address');
  console.log('2. Wait for the unfreeze transaction to be confirmed');
  if (donationAddress) {
    console.log('3. Then submit the second transaction to set the donation address');
  } else {
    console.log('3. Then create a new transaction to set the donation address using the setDonation function');
  }
}

// Execute the script
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  }); 