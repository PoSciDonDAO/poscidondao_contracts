// Script to generate transactions for deploying the DON token and Donation contract using a multisig wallet
// This script generates a JSON file that can be imported into Safe multisig interface

const { ethers } = require('ethers');
const fs = require('fs');
const path = require('path');
require('dotenv').config();

// Helper function to encode constructor data
function encodeConstructorData(abi, bytecode, constructorArgs) {
  const iface = new ethers.utils.Interface(abi);
  const constructorFragment = iface.fragments.find(fragment => fragment.type === 'constructor');
  
  if (!constructorFragment) {
    // If no constructor is defined, just return the bytecode
    return bytecode;
  }
  
  // Encode constructor parameters
  const encodedParams = ethers.utils.defaultAbiCoder.encode(
    constructorFragment.inputs.map(input => input.type),
    constructorArgs
  );
  
  // Remove the '0x' prefix from encodedParams
  return bytecode + encodedParams.slice(2);
}

async function main() {
  console.log('Generating transactions for DON token and Donation contract deployment...');
  
  // Configuration parameters
  const uri = process.env.DON_BASE_URI || "https://metadata.poscidondao.org/don/";
  const admin = process.env.ADMIN_ADDRESS || "0x96f67a852f8d3bc05464c4f91f97aace060e247a";
  const researchFundingWallet = process.env.RESEARCH_FUNDING_WALLET || "0x695f64829F0764FE1e95Fa32CD5c794A1a5034AF";
  const treasuryWallet = process.env.TREASURY_WALLET || admin;
  const usdc = process.env.USDC_ADDRESS || "0x08D39BBFc0F63668d539EA8BF469dfdeBAe58246";
  
  // Placeholder for the DON token address (to be replaced after deployment)
  const DON_ADDRESS_PLACEHOLDER = "{{DON_ADDRESS}}";
  
  // Load contract ABIs and bytecode
  const donAbiPath = path.join(__dirname, '../../artifacts/contracts/tokens/Don.sol/Don.json');
  const donationAbiPath = path.join(__dirname, '../../artifacts/contracts/donating/Donation.sol/Donation.json');
  
  const donArtifact = JSON.parse(fs.readFileSync(donAbiPath, 'utf8'));
  const donationArtifact = JSON.parse(fs.readFileSync(donationAbiPath, 'utf8'));
  
  const donAbi = donArtifact.abi;
  const donationAbi = donationArtifact.abi;
  const donBytecode = donArtifact.bytecode;
  const donationBytecode = donationArtifact.bytecode;
  
  // Encode constructor data for DON token
  const donConstructorData = encodeConstructorData(donAbi, donBytecode, [uri, treasuryWallet]);
  
  // Encode constructor data for Donation contract
  const donationConstructorData = encodeConstructorData(donationAbi, donationBytecode, [
    researchFundingWallet,
    treasuryWallet,
    usdc,
    DON_ADDRESS_PLACEHOLDER
  ]);
  
  // Create interface for Don contract
  const donInterface = new ethers.utils.Interface(donAbi);
  
  // Encode function data for unfreezing donation address in DON token
  // Note: We need to create a custom function to modify the _frozenDonation state variable
  // Since there's no direct function to unfreeze, we'll need to create a custom transaction
  // This is a placeholder - in reality, you would need to create a function in the Don contract
  // or use a more complex approach like a delegate call or proxy
  const unfreezeDonationData = "0x"; // This is a placeholder
  
  // Encode function data for setting Donation address in DON token
  const setDonationData = donInterface.encodeFunctionData("setDonation", ["{{DONATION_ADDRESS}}"]);
  
  // Create transactions array
  const transactions = [
    {
      to: "0x0000000000000000000000000000000000000000", // Contract creation
      value: "0",
      data: donConstructorData,
      description: "Deploy DON token contract"
    },
    {
      to: "0x0000000000000000000000000000000000000000", // Contract creation
      value: "0",
      data: donationConstructorData,
      description: "Deploy Donation contract (replace {{DON_ADDRESS}} with actual DON token address)"
    },
    {
      to: "{{DON_ADDRESS}}", // To be replaced with actual DON token address
      value: "0",
      data: setDonationData,
      description: "Set Donation address in DON token (replace {{DON_ADDRESS}} and {{DONATION_ADDRESS}} with actual addresses). NOTE: This will fail if _frozenDonation is true."
    }
  ];
  
  // Save transactions to JSON file
  const outputPath = path.join(__dirname, 'safeDonationSystemTransactions.json');
  fs.writeFileSync(outputPath, JSON.stringify(transactions, null, 2));
  
  console.log(`\nTransactions generated and saved to: ${outputPath}`);
  console.log('\nIMPORTANT: Before importing to Safe multisig interface:');
  console.log('1. Deploy the DON token contract (first transaction)');
  console.log('2. Replace {{DON_ADDRESS}} in the second and third transactions with the actual DON token address');
  console.log('3. Deploy the Donation contract (second transaction)');
  console.log('4. Replace {{DONATION_ADDRESS}} in the third transaction with the actual Donation contract address');
  console.log('5. IMPORTANT: The third transaction will fail if _frozenDonation is true in the DON token contract.');
  console.log('   You will need to modify the DON contract to include a function to unfreeze the donation address,');
  console.log('   or deploy a new version of the DON contract with _frozenDonation set to false initially.');
}

// Execute the script
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  }); 