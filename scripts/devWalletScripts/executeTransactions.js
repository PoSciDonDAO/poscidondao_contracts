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
    "to": "0xc9B6D9e461520BDCcF114a1D732c29DDa14571B7",
    "value": "0",
    "data": "0x68e432b2000000000000000000000000f4a9bfe64bd1d25081b9a84df6b76681a0bd2b20",
    "description": "Set Donation address in DON token"
  },
  {
    "to": "0x26E10Ca7Bbe1f25333F95Dc3c498F6f405F8F6B0",
    "value": "0",
    "data": "0x861228a2000000000000000000000000ed3f4ce4f426dfb5c33dd8e68c08c2002bb4fafb",
    "description": "Set GovernorExecutor for SciManager"
  },
  {
    "to": "0x626ce45d43f136e0d775499F5b4E7e9086bd16B9",
    "value": "0",
    "data": "0x861228a2000000000000000000000000ed3f4ce4f426dfb5c33dd8e68c08c2002bb4fafb",
    "description": "Set GovernorExecutor for Research"
  },
  {
    "to": "0xB9A5B1aF1EcbC23a11D1D06f9804c1debC7846bB",
    "value": "0",
    "data": "0x861228a2000000000000000000000000ed3f4ce4f426dfb5c33dd8e68c08c2002bb4fafb",
    "description": "Set GovernorExecutor for GovernorOperations"
  },
  {
    "to": "0xB9A5B1aF1EcbC23a11D1D06f9804c1debC7846bB",
    "value": "0",
    "data": "0x613248b700000000000000000000000037b72311c318fdf0c3fb01f9d442c6e4e3c96fc9",
    "description": "Set GovernorGuard for GovernorOperations"
  },
  {
    "to": "0xB9A5B1aF1EcbC23a11D1D06f9804c1debC7846bB",
    "value": "0",
    "data": "0x5bb478080000000000000000000000002baf41b1b36db8b772fe5af932a9610508379dbe",
    "description": "Set ActionCloneFactory for GovernorOperations"
  },
  {
    "to": "0x626ce45d43f136e0d775499F5b4E7e9086bd16B9",
    "value": "0",
    "data": "0x5bb478080000000000000000000000007e2c25401eee24d2b4c22e5289af0ddd0af5298e",
    "description": "Set ActionCloneFactory for Research"
  },
  {
    "to": "0x626ce45d43f136e0d775499F5b4E7e9086bd16B9",
    "value": "0",
    "data": "0x613248b700000000000000000000000037b72311c318fdf0c3fb01f9d442c6e4e3c96fc9",
    "description": "Set GovernorGuard for Research"
  },
  {
    "to": "0x2bd09Da36560A71D2102c17eBE5bF4f7E211745A",
    "value": "0",
    "data": "0xc1cc275e000000000000000000000000b9a5b1af1ecbc23a11d1d06f9804c1debc7846bb",
    "description": "Set GovernorOperations for PO"
  },
  {
    "to": "0x26E10Ca7Bbe1f25333F95Dc3c498F6f405F8F6B0",
    "value": "0",
    "data": "0xc1cc275e000000000000000000000000b9a5b1af1ecbc23a11d1d06f9804c1debc7846bb",
    "description": "Set GovernorOperations for SciManager"
  },
  {
    "to": "0x26E10Ca7Bbe1f25333F95Dc3c498F6f405F8F6B0",
    "value": "0",
    "data": "0x0a5db715000000000000000000000000626ce45d43f136e0d775499f5b4e7e9086bd16b9",
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