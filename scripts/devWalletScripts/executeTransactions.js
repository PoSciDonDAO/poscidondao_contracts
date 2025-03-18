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

  // Base Chain (Chain ID: 8453)
  const provider = new ethers.providers.JsonRpcProvider(process.env.RPC_URL || 'https://base-mainnet.g.alchemy.com/v2/YOUR_API_KEY');
  const wallet = new ethers.Wallet(PRIVATE_KEY, provider);
  
  console.log(`Using wallet address: ${wallet.address}`);
  
  // Transaction data from safeBatchTransaction.json
  const transactions = [
  {
    "to": "0xF1B2a841C410a33ba4203E1042e02a458AcD835b",
    "value": "0",
    "data": "0x68e432b20000000000000000000000005688cfece0ad0a797a2bb4ef574e60872c5069f7",
    "description": "Set Donation address in DON token"
  },
  {
    "to": "0x032746d21e589f9c42b81d3EC77E389dbf4B96b2",
    "value": "0",
    "data": "0x861228a2000000000000000000000000457dbd7db724c550d62405c79d8cd7771a98b78c",
    "description": "Set GovernorExecutor for SciManager"
  },
  {
    "to": "0x5a06b21D5AF5DEAfBFCF0Cd528F02DAEE9976aD6",
    "value": "0",
    "data": "0x861228a2000000000000000000000000457dbd7db724c550d62405c79d8cd7771a98b78c",
    "description": "Set GovernorExecutor for Research"
  },
  {
    "to": "0xEe1C6D7A3Db1e629b605Da94f9BDD6b93d45Ce6b",
    "value": "0",
    "data": "0x861228a2000000000000000000000000457dbd7db724c550d62405c79d8cd7771a98b78c",
    "description": "Set GovernorExecutor for GovernorOperations"
  },
  {
    "to": "0xEe1C6D7A3Db1e629b605Da94f9BDD6b93d45Ce6b",
    "value": "0",
    "data": "0x613248b7000000000000000000000000fad6de67728f623b6132ffcd0a80bdc70564da4a",
    "description": "Set GovernorGuard for GovernorOperations"
  },
  {
    "to": "0xEe1C6D7A3Db1e629b605Da94f9BDD6b93d45Ce6b",
    "value": "0",
    "data": "0x5bb478080000000000000000000000009ff3c70d653aa760850235dd88b9485ec9dedf6d",
    "description": "Set ActionCloneFactory for GovernorOperations"
  },
  {
    "to": "0x5a06b21D5AF5DEAfBFCF0Cd528F02DAEE9976aD6",
    "value": "0",
    "data": "0x5bb47808000000000000000000000000b3ab2080a20462b4fa0f4b352514eb9cdeaf1a8a",
    "description": "Set ActionCloneFactory for Research"
  },
  {
    "to": "0x5a06b21D5AF5DEAfBFCF0Cd528F02DAEE9976aD6",
    "value": "0",
    "data": "0x613248b7000000000000000000000000fad6de67728f623b6132ffcd0a80bdc70564da4a",
    "description": "Set GovernorGuard for Research"
  },
  {
    "to": "0x418a1F35bB56FDd9bCcFb2ce7adD06faE447Cc54",
    "value": "0",
    "data": "0xc1cc275e000000000000000000000000ee1c6d7a3db1e629b605da94f9bdd6b93d45ce6b",
    "description": "Set GovernorOperations for PO"
  },
  {
    "to": "0x032746d21e589f9c42b81d3EC77E389dbf4B96b2",
    "value": "0",
    "data": "0xc1cc275e000000000000000000000000ee1c6d7a3db1e629b605da94f9bdd6b93d45ce6b",
    "description": "Set GovernorOperations for SciManager"
  },
  {
    "to": "0x032746d21e589f9c42b81d3EC77E389dbf4B96b2",
    "value": "0",
    "data": "0x0a5db7150000000000000000000000005a06b21d5af5deafbfcf0cd528f02daee9976ad6",
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
        chainId: 8453 // Base Chain
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