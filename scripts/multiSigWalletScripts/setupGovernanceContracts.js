// Script to execute transactions to set up governance contracts
// This script uses ethers.js v5
const { ethers } = require('ethers');
const fs = require('fs');
const path = require('path');
require('dotenv').config();

// Function to encode function call data
function encodeFunctionData(functionSignature, input) {
  const iface = new ethers.utils.Interface([`function ${functionSignature}`]);
  return iface.encodeFunctionData(functionSignature.split("(")[0], [input]);
}

const governorOperationsAddress = "0x87B5DEf0Bc3A7563782b1037A5aB5Fd30F43013F";
const governorResearchAddress = "0x8b4757468DE4488C96D30D64d72c432f5Cc48997";

// Get contract addresses from environment variables
function getContractAddresses() {
  // Use existing contract addresses from mainnet
  const addresses = {
    po: "0x418a1F35bB56FDd9bCcFb2ce7adD06faE447Cc54",
    sciManager: "0x032746d21e589f9c42b81d3EC77E389dbf4B96b2",
    governorOperations: governorOperationsAddress,
    governorResearch: governorResearchAddress,
    governorExecutor: "0x457dbd7DB724C550D62405c79d8cd7771A98b78c",
    governorGuard: "0xFaD6De67728f623B6132fFcd0A80bdC70564da4A",
    actionFactoryOperations: "0x5561A0F44D44A8625438385d04C3a63152EBc66d",
    actionFactoryResearch: "0x65d38b7f3d29f697b5DF5f9DCbD22C27302C81F2"
  };

  // Validate required addresses
  if (!addresses.governorOperations) {
    throw new Error("⛔️ GOVERNOR_OPERATIONS_ADDRESS environment variable not set! Add it to the .env file!");
  }

  if (!addresses.governorResearch) {
    throw new Error("⛔️ GOVERNOR_RESEARCH_ADDRESS environment variable not set! Add it to the .env file!");
  }

  return addresses;
}

// Save transactions to a file for Gnosis Safe import
async function saveSafeBatchTransactionFile(transactions) {
  const transactionDescriptions = [
    "Set GovernorExecutor for GovernorOperations",
    "Set GovernorExecutor for GovernorResearch",
    "Set GovernorGuard for GovernorOperations",
    "Set GovernorGuard for GovernorResearch",
    "Set ActionCloneFactory for GovernorOperations",
    "Set ActionCloneFactory for GovernorResearch",
    "Set GovernorOperations for PO",
    "Set GovernorOperations for SciManager",
    "Set GovernorResearch for SciManager"
  ];

  // Create transactions with descriptions
  const transactionsWithDescriptions = transactions.map((tx, index) => ({
    ...tx,
    description: transactionDescriptions[index] || `Transaction ${index + 1}`
  }));

  const safeBatchTransaction = {
    version: "1.0",
    chainId: 8453, // Default to Base mainnet
    createdAt: Date.now(),
    meta: {
      name: "Setting up new GovernorOperations and GovernorResearch contracts",
      description:
        "Batch transaction to set up newly deployed GovernorOperations and GovernorResearch contracts with existing contracts.",
      txBuilderVersion: "1.17.0",
      createdFromSafeAddress: "0x96f67a852f8d3bc05464c4f91f97aace060e247a",
      createdFromOwnerAddress: "",
    },
    transactions,
    checksum: ethers.utils.keccak256(
      ethers.utils.toUtf8Bytes(JSON.stringify(transactions))
    ),
  };

  const outputPath = path.join(__dirname, "setupGovernanceTransactions.json");
  if (fs.existsSync(outputPath)) {
    fs.unlinkSync(outputPath);
    console.log(`Existing file at ${outputPath} has been deleted.`);
  }
  
  fs.writeFileSync(
    outputPath,
    JSON.stringify(safeBatchTransaction, null, 2),
    "utf8"
  );
  
  console.log(`Batch transaction JSON successfully generated and saved at: ${outputPath}`);
  console.log(`\nTo use this file with Gnosis Safe:`);
  console.log(`1. Go to https://app.safe.global/`);
  console.log(`2. Connect to your Safe on Base network`);
  console.log(`3. Click on "New Transaction" -> "Transaction Builder"`);
  console.log(`4. Click on "Load JSON" and select the generated file`);
  console.log(`5. Review the transactions and execute them`);
}

// Execute transactions directly using an EOA wallet
async function executeTransactionsDirectly(transactions) {
  console.log(`\n=== EXECUTING TRANSACTIONS DIRECTLY ===`);
  
  // Configuration
  const PRIVATE_KEY = process.env.PRIVATE_KEY;
  if (!PRIVATE_KEY) {
    console.error('Please set your PRIVATE_KEY in a .env file');
    process.exit(1);
  }

  // Set up provider and wallet
  const provider = new ethers.providers.JsonRpcProvider(process.env.RPC_URL_MAINNET);
  const wallet = new ethers.Wallet(PRIVATE_KEY, provider);
  
  console.log(`Using wallet address: ${wallet.address}`);
  
  // Execute transactions sequentially
  for (let i = 0; i < transactions.length; i++) {
    const tx = transactions[i];
    console.log(`\nExecuting transaction ${i + 1}/${transactions.length}`);
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
        chainId: 8453 // Default to Base mainnet
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
  
  console.log('\n=== ALL TRANSACTIONS EXECUTED SUCCESSFULLY ===');
}

async function main() {
  console.log("Setting up governance contracts...");

  // Check if environment has required variables
//   if (!process.env.GOVERNOR_OPERATIONS_ADDRESS || !process.env.GOVERNOR_RESEARCH_ADDRESS) {
//     console.log(`
// ===============================================================
//   GOVERNANCE CONTRACT SETUP - REQUIRED ENVIRONMENT VARIABLES
// ===============================================================

// This script requires the following environment variables:
// - GOVERNOR_OPERATIONS_ADDRESS: The address of the new GovernorOperations contract
// - GOVERNOR_RESEARCH_ADDRESS: The address of the new GovernorResearch contract

// Optional environment variables:
// - PRIVATE_KEY: Required only if executing transactions directly
// - RPC_URL: URL of the RPC provider (defaults to Alchemy Base mainnet)
// - CHAIN_ID: Chain ID (defaults to 8453 for Base mainnet)
// - SAFE_ADDRESS: Address of the Gnosis Safe (defaults to admin address)

// You can set these in a .env file in the root directory or pass them directly:
// GOVERNOR_OPERATIONS_ADDRESS=0x... GOVERNOR_RESEARCH_ADDRESS=0x... node scripts/multiSigWalletScripts/setupGovernanceContracts.js
//     `);
//     process.exit(1);
//   }

  try {
    // Get contract addresses
    const addresses = getContractAddresses();
    console.log("\nUsing the following contract addresses:");
    console.log(JSON.stringify(addresses, null, 2));

    // Create transaction array
    const transactions = [
      {
        to: addresses.governorOperations,
        value: "0",
        data: encodeFunctionData("setGovExec(address)", addresses.governorExecutor),
      },
      {
        to: addresses.governorResearch,
        value: "0",
        data: encodeFunctionData("setGovExec(address)", addresses.governorExecutor),
      },
      {
        to: addresses.governorOperations,
        value: "0",
        data: encodeFunctionData("setGovGuard(address)", addresses.governorGuard),
      },
      {
        to: addresses.governorResearch,
        value: "0",
        data: encodeFunctionData("setGovGuard(address)", addresses.governorGuard),
      },
      {
        to: addresses.governorOperations,
        value: "0",
        data: encodeFunctionData("setFactory(address)", addresses.actionFactoryOperations),
      },
      {
        to: addresses.governorResearch,
        value: "0",
        data: encodeFunctionData("setFactory(address)", addresses.actionFactoryResearch),
      },
      {
        to: addresses.po,
        value: "0",
        data: encodeFunctionData("setGovOps(address)", addresses.governorOperations),
      },
      {
        to: addresses.sciManager,
        value: "0",
        data: encodeFunctionData("setGovOps(address)", addresses.governorOperations),
      },
      {
        to: addresses.sciManager,
        value: "0",
        data: encodeFunctionData("setGovRes(address)", addresses.governorResearch),
      }
    ];

    // Save batch transaction file for Gnosis Safe
    await saveSafeBatchTransactionFile(transactions);

    // Ask user if they want to execute the transactions directly
    const readline = require('readline');
    const rl = readline.createInterface({
      input: process.stdin,
      output: process.stdout,
    });
    
    const answer = await new Promise((resolve) => {
      rl.question('\nDo you want to execute these transactions directly? (y/n): ', resolve);
    });
    
    rl.close();
    
    if (answer.toLowerCase() === 'y') {
      await executeTransactionsDirectly(transactions);
    } else {
      console.log('\nTransactions NOT executed. Use the generated files to execute them later.');
    }
  } catch (error) {
    console.error("Error:", error.message);
    process.exit(1);
  }
}

// Execute the script
main()
  .then(() => {
    console.log("\n=== SETUP COMPLETED ===");
    process.exit(0);
  })
  .catch((error) => {
    console.error("Fatal error:", error);
    process.exit(1);
  }); 