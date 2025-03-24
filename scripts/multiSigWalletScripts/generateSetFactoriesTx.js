import { ethers } from "ethers";
import dotenv from "dotenv";
import fs from "fs";
import path from "path";
import { fileURLToPath } from 'url';

dotenv.config();

// ES Module equivalent of __dirname
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Function to encode function data for setFactory call
function encodeFunctionData(
  functionSignature,
  input
){
  const iface = new ethers.utils.Interface([`function ${functionSignature}`]);
  return iface.encodeFunctionData(functionSignature.split("(")[0], [input]);
}

// Main function to generate transaction files
async function main() {
  // Hardcoded new factory addresses
  const newActionCloneFactoryOperations = "0x5561A0F44D44A8625438385d04C3a63152EBc66d";
  const newActionCloneFactoryResearch = "0x65d38b7f3d29f697b5DF5f9DCbD22C27302C81F2";

  console.log("Generating transaction files with:");
  console.log(`- ActionCloneFactoryOperations: ${newActionCloneFactoryOperations}`);
  console.log(`- ActionCloneFactoryResearch: ${newActionCloneFactoryResearch}`);

  // Governor contract addresses
  const governorOperations = "0xEe1C6D7A3Db1e629b605Da94f9BDD6b93d45Ce6b";
  const governorResearch = "0x5a06b21D5AF5DEAfBFCF0Cd528F02DAEE9976aD6";
  const admin = "0x96f67a852f8d3bc05464c4f91f97aace060e247a";

  // Create transactions
  const transactions = [
    {
      to: governorOperations,
      value: "0",
      data: encodeFunctionData("setFactory(address)", newActionCloneFactoryOperations),
      description: "Set new ActionCloneFactoryOperations in GovernorOperations"
    },
    {
      to: governorResearch,
      value: "0",
      data: encodeFunctionData("setFactory(address)", newActionCloneFactoryResearch),
      description: "Set new ActionCloneFactoryResearch in GovernorResearch"
    }
  ];

  // Create Safe multisig transaction format
  const safeBatchTransaction = {
    version: "1.0",
    chainId: 8453, // Base Mainnet
    createdAt: Date.now(),
    meta: {
      name: "Update Factory Addresses in Governor Contracts",
      description: "Sets new ActionCloneFactory addresses in GovernorOperations and GovernorResearch contracts",
      txBuilderVersion: "1.17.0",
      createdFromSafeAddress: admin,
      createdFromOwnerAddress: "",
    },
    transactions: transactions.map(tx => ({
      to: tx.to,
      value: tx.value,
      data: tx.data
    })),
    checksum: "",
  };

  // Add checksum
  safeBatchTransaction.checksum = ethers.utils.keccak256(
    ethers.utils.toUtf8Bytes(JSON.stringify(safeBatchTransaction.transactions))
  );

  // Create output directories
  const outputDir = path.join(__dirname, "output");
  if (!fs.existsSync(outputDir)) {
    fs.mkdirSync(outputDir, { recursive: true });
  }

  // Write Safe transaction to file
  const safeOutputPath = path.join(outputDir, "updateFactories_safeTx.json");
  fs.writeFileSync(
    safeOutputPath,
    JSON.stringify(safeBatchTransaction, null, 2),
    "utf8"
  );
  console.log(`\nSafe Multisig transaction JSON saved to: ${safeOutputPath}`);

  // Create EOA execution script
  const eoaScript = `// Script to execute setFactory() calls using an EOA wallet
// Uses ethers.js v5

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
  
  console.log(\`Using wallet address: \${wallet.address}\`);
  
  // Transaction data
  const transactions = ${JSON.stringify(transactions, null, 2)};

  // Execute transactions sequentially
  for (let i = 0; i < transactions.length; i++) {
    const tx = transactions[i];
    console.log(\`\\nExecuting transaction \${i + 1}/\${transactions.length}: \${tx.description}\`);
    console.log(\`Target: \${tx.to}\`);
    
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
        console.warn(\`Gas estimation failed: \${error.message}\`);
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
      
      console.log(\`Gas limit: \${transaction.gasLimit.toString()}\`);
      
      // Sign and send transaction
      const signedTx = await wallet.signTransaction(transaction);
      const txResponse = await provider.sendTransaction(signedTx);
      
      console.log(\`Transaction sent: \${txResponse.hash}\`);
      console.log(\`Waiting for confirmation...\`);
      
      // Wait for transaction to be mined
      const receipt = await txResponse.wait();
      console.log(\`Transaction confirmed in block \${receipt.blockNumber}\`);
      console.log(\`Gas used: \${receipt.gasUsed.toString()}\`);
    } catch (error) {
      console.error(\`Error executing transaction \${i + 1}: \${error.message}\`);
      console.error(error);
      process.exit(1);
    }
  }
  
  console.log('\\nAll transactions executed successfully!');
}

// Execute the script
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });`;

  // Write EOA script to file
  const eoaScriptPath = path.join(outputDir, "executeSetFactories.js");
  fs.writeFileSync(eoaScriptPath, eoaScript, "utf8");
  console.log(`EOA execution script saved to: ${eoaScriptPath}`);

  console.log("\n=== TRANSACTION GENERATION COMPLETED ===");
  console.log("To execute these transactions:");
  console.log("1. Upload the Safe JSON file to your multisig wallet on app.safe.global");
  console.log("2. OR run the EOA script with 'node scripts/output/executeSetFactories.js'");
  console.log("   (Make sure to set PRIVATE_KEY and RPC_URL in your .env file first)");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("Error:", error);
    process.exit(1);
  }); 