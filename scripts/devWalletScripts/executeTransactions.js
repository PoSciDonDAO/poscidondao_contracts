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
    "to": "0xb09d33CDa5D3F275f2a2507F3de24b256F633b5e",
    "value": "0",
    "data": "0x861228a20000000000000000000000000de047857db6043964c82a04234d5127f9d3a894",
    "description": "Set GovernorExecutor for SciManager"
  },
  {
    "to": "0x9A22CaD9CB46A41DBDf444a0972170E2D96d4A8E",
    "value": "0",
    "data": "0x861228a20000000000000000000000000de047857db6043964c82a04234d5127f9d3a894",
    "description": "Set GovernorExecutor for Research"
  },
  {
    "to": "0x87F6c82F3AF219E85b83584Ad34D8f4741feE300",
    "value": "0",
    "data": "0x861228a20000000000000000000000000de047857db6043964c82a04234d5127f9d3a894",
    "description": "Set GovernorExecutor for GovernorOperations"
  },
  {
    "to": "0x87F6c82F3AF219E85b83584Ad34D8f4741feE300",
    "value": "0",
    "data": "0x613248b700000000000000000000000087a11d6c886066f06259d8343935e0124f5a5a04",
    "description": "Set GovernorGuard for GovernorOperations"
  },
  {
    "to": "0x87F6c82F3AF219E85b83584Ad34D8f4741feE300",
    "value": "0",
    "data": "0x5bb47808000000000000000000000000044df47243f96962f6ae742870265066e6548d35",
    "description": "Set ActionCloneFactory for GovernorOperations"
  },
  {
    "to": "0x9A22CaD9CB46A41DBDf444a0972170E2D96d4A8E",
    "value": "0",
    "data": "0x5bb47808000000000000000000000000422bceaedbf53060ffe48ff32efa4ca9a543ecaa",
    "description": "Set ActionCloneFactory for Research"
  },
  {
    "to": "0x9A22CaD9CB46A41DBDf444a0972170E2D96d4A8E",
    "value": "0",
    "data": "0x613248b700000000000000000000000087a11d6c886066f06259d8343935e0124f5a5a04",
    "description": "Set GovernorGuard for Research"
  },
  {
    "to": "0xb4A706d6B55181bBBD0D7E012d1d9bC0Ec36bd73",
    "value": "0",
    "data": "0xc1cc275e00000000000000000000000087f6c82f3af219e85b83584ad34d8f4741fee300",
    "description": "Set GovernorOperations for PO"
  },
  {
    "to": "0xb09d33CDa5D3F275f2a2507F3de24b256F633b5e",
    "value": "0",
    "data": "0xc1cc275e00000000000000000000000087f6c82f3af219e85b83584ad34d8f4741fee300",
    "description": "Set GovernorOperations for SciManager"
  },
  {
    "to": "0xb09d33CDa5D3F275f2a2507F3de24b256F633b5e",
    "value": "0",
    "data": "0x0a5db7150000000000000000000000009a22cad9cb46a41dbdf444a0972170e2d96d4a8e",
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