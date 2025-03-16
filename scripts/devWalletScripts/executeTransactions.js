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
    "to": "0xCF245ea8A1f892e79453DcD884c87f91FEE8ab94",
    "value": "0",
    "data": "0x861228a20000000000000000000000009b974833d84263d6888e85c7ccf92aeb4bede203",
    "description": "Set GovernorExecutor for SciManager"
  },
  {
    "to": "0x73be5508Fd3860A8A87507F27922EEcFC1d48a0b",
    "value": "0",
    "data": "0x861228a20000000000000000000000009b974833d84263d6888e85c7ccf92aeb4bede203",
    "description": "Set GovernorExecutor for Research"
  },
  {
    "to": "0x8b557eEbe3B3e6563F6513D55C5B1ba7a6F9C39D",
    "value": "0",
    "data": "0x861228a20000000000000000000000009b974833d84263d6888e85c7ccf92aeb4bede203",
    "description": "Set GovernorExecutor for GovernorOperations"
  },
  {
    "to": "0x8b557eEbe3B3e6563F6513D55C5B1ba7a6F9C39D",
    "value": "0",
    "data": "0x613248b7000000000000000000000000738bcb53863423111efa74f919d5eba952e0e6f1",
    "description": "Set GovernorGuard for GovernorOperations"
  },
  {
    "to": "0x8b557eEbe3B3e6563F6513D55C5B1ba7a6F9C39D",
    "value": "0",
    "data": "0x5bb47808000000000000000000000000b3bd7d83f5ee6b1cf058601b21abe86638fa6754",
    "description": "Set ActionCloneFactory for GovernorOperations"
  },
  {
    "to": "0x73be5508Fd3860A8A87507F27922EEcFC1d48a0b",
    "value": "0",
    "data": "0x5bb478080000000000000000000000002b567a721c5944d1c1ef10ee63d3c6bc812f3c27",
    "description": "Set ActionCloneFactory for Research"
  },
  {
    "to": "0x73be5508Fd3860A8A87507F27922EEcFC1d48a0b",
    "value": "0",
    "data": "0x613248b7000000000000000000000000738bcb53863423111efa74f919d5eba952e0e6f1",
    "description": "Set GovernorGuard for Research"
  },
  {
    "to": "0x9f696aBEFA7f6de1225764eF6A4beDe97d74Dc2A",
    "value": "0",
    "data": "0xc1cc275e0000000000000000000000008b557eebe3b3e6563f6513d55c5b1ba7a6f9c39d",
    "description": "Set GovernorOperations for PO"
  },
  {
    "to": "0xCF245ea8A1f892e79453DcD884c87f91FEE8ab94",
    "value": "0",
    "data": "0xc1cc275e0000000000000000000000008b557eebe3b3e6563f6513d55c5b1ba7a6f9c39d",
    "description": "Set GovernorOperations for SciManager"
  },
  {
    "to": "0xCF245ea8A1f892e79453DcD884c87f91FEE8ab94",
    "value": "0",
    "data": "0x0a5db71500000000000000000000000073be5508fd3860a8a87507f27922eecfc1d48a0b",
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