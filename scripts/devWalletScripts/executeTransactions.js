// Script to execute the same transactions as in safeBatchTransaction.json but using an EOA wallet
// This script uses ethers.js v5

const { ethers } = require('ethers');
require('dotenv').config();

async function main() {
  // Configuration
  const PRIVATE_KEY = process.env.PRIVATE_KEY;
  if (!PRIVATE_KEY) {
    console.error('Please set your PRIVATE_KEY in a .env file');
    process.exit(1);
  }

  // Base Chain (Chain ID: 84532)
  const provider = new ethers.providers.JsonRpcProvider(process.env.RPC_URL || 'https://base-sepolia.g.alchemy.com/v2/YOUR_API_KEY');
  const wallet = new ethers.Wallet(PRIVATE_KEY, provider);
  
  console.log(`Using wallet address: ${wallet.address}`);
  
  // Transaction data from safeBatchTransaction.json
  const transactions = [
  {
    "to": "0xA1591e7fd5c25eD657f265A1780E6ccEA3f04ECD",
    "value": "0",
    "data": "0x861228a20000000000000000000000008286b98b8c59653ec282385dc7f3d835fb1caa44",
    "description": "Set GovernorExecutor for SciManager"
  },
  {
    "to": "0x235bf747A0Ce3f2f2A6dAfd080C7577fba0A563e",
    "value": "0",
    "data": "0x861228a20000000000000000000000008286b98b8c59653ec282385dc7f3d835fb1caa44",
    "description": "Set GovernorExecutor for Research"
  },
  {
    "to": "0xc53F885B7121A6d44f02192eDEC77ebb8B35f5Ae",
    "value": "0",
    "data": "0x861228a20000000000000000000000008286b98b8c59653ec282385dc7f3d835fb1caa44",
    "description": "Set GovernorExecutor for GovernorOperations"
  },
  {
    "to": "0xc53F885B7121A6d44f02192eDEC77ebb8B35f5Ae",
    "value": "0",
    "data": "0x613248b7000000000000000000000000e8414cf1730efdf7baa7a81eb7302fe7f025781d",
    "description": "Set GovernorGuard for GovernorOperations"
  },
  {
    "to": "0xc53F885B7121A6d44f02192eDEC77ebb8B35f5Ae",
    "value": "0",
    "data": "0x5bb4780800000000000000000000000044ea012a01b8ff7b5dd6e267fad60efdb3deba6e",
    "description": "Set ActionCloneFactory for GovernorOperations"
  },
  {
    "to": "0x235bf747A0Ce3f2f2A6dAfd080C7577fba0A563e",
    "value": "0",
    "data": "0x5bb478080000000000000000000000004fab79796851a7b10c2ef1910d7945f1f3f7413a",
    "description": "Set ActionCloneFactory for Research"
  },
  {
    "to": "0x235bf747A0Ce3f2f2A6dAfd080C7577fba0A563e",
    "value": "0",
    "data": "0x613248b7000000000000000000000000e8414cf1730efdf7baa7a81eb7302fe7f025781d",
    "description": "Set GovernorGuard for Research"
  },
  {
    "to": "0x853532dD7A507074319c39BF2eD0cA09Efb53F77",
    "value": "0",
    "data": "0xc1cc275e000000000000000000000000c53f885b7121a6d44f02192edec77ebb8b35f5ae",
    "description": "Set GovernorOperations for PO"
  },
  {
    "to": "0xA1591e7fd5c25eD657f265A1780E6ccEA3f04ECD",
    "value": "0",
    "data": "0xc1cc275e000000000000000000000000c53f885b7121a6d44f02192edec77ebb8b35f5ae",
    "description": "Set GovernorOperations for SciManager"
  },
  {
    "to": "0xA1591e7fd5c25eD657f265A1780E6ccEA3f04ECD",
    "value": "0",
    "data": "0x0a5db715000000000000000000000000235bf747a0ce3f2f2a6dafd080c7577fba0a563e",
    "description": "Set Research for SciManager"
  }
];

  // Execute transactions sequentially
  for (let i = 0; i < transactions.length; i++) {
    const tx = transactions[i];
    console.log(`\nExecuting transaction ${i + 1}/${transactions.length}: ${tx.description}`);
    console.log(`Target: ${tx.to}`);
    
    try {
      // Get current nonce
      const nonce = await wallet.getTransactionCount();
      
      // Get gas price
      const gasPrice = await provider.getGasPrice();
      
      // Estimate gas limit
      const gasLimit = await provider.estimateGas({
        from: wallet.address,
        to: tx.to,
        data: tx.data,
        value: ethers.utils.parseEther(tx.value || "0")
      }).catch(error => {
        console.warn(`Gas estimation failed: ${error.message}`);
        return ethers.BigNumber.from(300000); // Fallback gas limit
      });
      
      // Prepare transaction
      const transaction = {
        from: wallet.address,
        to: tx.to,
        data: tx.data,
        value: ethers.utils.parseEther(tx.value || "0"),
        nonce: nonce,
        gasLimit: gasLimit.mul(ethers.BigNumber.from(12)).div(ethers.BigNumber.from(10)), // Add 20% buffer
        gasPrice: gasPrice,
        chainId: 84532 // Base Chain
      };
      
      console.log(`Gas limit: ${transaction.gasLimit.toString()}`);
      
      // Sign and send transaction
      const signedTx = await wallet.signTransaction(transaction);
      const txResponse = await provider.sendTransaction(signedTx);
      
      console.log(`Transaction sent: ${txResponse.hash}`);
      console.log(`Waiting for confirmation...`);
      
      // Wait for transaction to be mined
      const receipt = await txResponse.wait();
      console.log(`Transaction confirmed in block ${receipt.blockNumber}`);
      console.log(`Gas used: ${receipt.gasUsed.toString()}`);
    } catch (error) {
      console.error(`Error executing transaction ${i + 1}: ${error.message}`);
      console.error(error);
      
      // Ask user if they want to continue with the next transaction
      const readline = require('readline').createInterface({
        input: process.stdin,
        output: process.stdout
      });
      
      const answer = await new Promise(resolve => {
        readline.question('Continue with next transaction? (y/n): ', resolve);
      });
      
      readline.close();
      
      if (answer.toLowerCase() !== 'y') {
        console.log('Execution stopped by user.');
        process.exit(1);
      }
    }
  }
  
  console.log('\nAll transactions executed successfully!');
}

// Execute the script
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });