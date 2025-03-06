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
    "to": "0x0b137458f21b44b990dA8721a7C6BE2CF46Dd620",
    "value": "0",
    "data": "0x861228a200000000000000000000000031907fc8f454bab56c25f2885978acff8027a712",
    "description": "Set GovernorExecutor for SciManager"
  },
  {
    "to": "0x224789AD1b099f24a364Be6a13e0B90c9A29e910",
    "value": "0",
    "data": "0x861228a200000000000000000000000031907fc8f454bab56c25f2885978acff8027a712",
    "description": "Set GovernorExecutor for Research"
  },
  {
    "to": "0xAAe272015d2b1f18fD5D9DE3e76904f405F44D5C",
    "value": "0",
    "data": "0x861228a200000000000000000000000031907fc8f454bab56c25f2885978acff8027a712",
    "description": "Set GovernorExecutor for GovernorOperations"
  },
  {
    "to": "0xAAe272015d2b1f18fD5D9DE3e76904f405F44D5C",
    "value": "0",
    "data": "0x613248b7000000000000000000000000ffcd422f962d2080b7f65cec16e687f79e3b6755",
    "description": "Set GovernorGuard for GovernorOperations"
  },
  {
    "to": "0xAAe272015d2b1f18fD5D9DE3e76904f405F44D5C",
    "value": "0",
    "data": "0x5bb478080000000000000000000000000110e733c5233b4791ae253c5a4c2d2d56e6dc3d",
    "description": "Set ActionCloneFactory for GovernorOperations"
  },
  {
    "to": "0x224789AD1b099f24a364Be6a13e0B90c9A29e910",
    "value": "0",
    "data": "0x5bb47808000000000000000000000000a914fd18a8fbc61de7d0a29bbff30c07dffbbd40",
    "description": "Set ActionCloneFactory for Research"
  },
  {
    "to": "0x224789AD1b099f24a364Be6a13e0B90c9A29e910",
    "value": "0",
    "data": "0x613248b7000000000000000000000000ffcd422f962d2080b7f65cec16e687f79e3b6755",
    "description": "Set GovernorGuard for Research"
  },
  {
    "to": "0xa6Ebe170de63fE1Af95483b19cFaB83834cfC5A7",
    "value": "0",
    "data": "0xc1cc275e000000000000000000000000aae272015d2b1f18fd5d9de3e76904f405f44d5c",
    "description": "Set GovernorOperations for PO"
  },
  {
    "to": "0x0b137458f21b44b990dA8721a7C6BE2CF46Dd620",
    "value": "0",
    "data": "0xc1cc275e000000000000000000000000aae272015d2b1f18fd5d9de3e76904f405f44d5c",
    "description": "Set GovernorOperations for SciManager"
  },
  {
    "to": "0x0b137458f21b44b990dA8721a7C6BE2CF46Dd620",
    "value": "0",
    "data": "0x0a5db715000000000000000000000000224789ad1b099f24a364be6a13e0b90c9a29e910",
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