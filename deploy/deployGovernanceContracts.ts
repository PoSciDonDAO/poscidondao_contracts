// Script to deploy GovernorExecutor and GovernorGuard contracts
// This script uses ethers.js v5

const { ethers } = require('ethers');
const fs = require('fs');
const path = require('path');
require('dotenv').config();

// Import network info function
const { getNetworkInfo, getRpcUrl, getPrivateKey } = require('../../app/utils/serverConfig');

// ABI for GovernorExecutor and GovernorGuard
const governorExecutorAbi = [
  "constructor(address admin_, uint256 delay_, address govOps_, address govRes_)",
  "function addGovernor(address newGovernor) external",
  "function setDelay(uint56 newDelay) external",
  "function schedule(address action) external",
  "function cancel(address action) external",
  "function execution(address action) external",
];

const governorGuardAbi = [
  "constructor(address admin_, address govOps_, address govRes_)",
  "function renounceRole(bytes32 role, address account) public virtual",
  "function cancel(uint256 id) external",
];

// Function to deploy GovernorExecutor
async function deployGovernorExecutor(admin, delay, govOps, govRes, wallet) {
  console.log("\n=== Deploying GovernorExecutor ===");
  
  // Create contract factory
  const governorExecutorFactory = new ethers.ContractFactory(
    governorExecutorAbi,
    "0x608060405234801561001057600080fd5b5060405161091f38038061091f8339818101604052608081101561003357600080fd5b5080516020820151604083015160609093015190926000841461005557600080fd5b6000831461006257600080fd5b6000821461006f57600080fd5b603c821115806100805750610e10825b806100905750610e10821115156100935750604e826100a39250601e90565b600055600280546001600160a01b0319166001600160a01b038716179055610e1060015561011c7f38c4b9fd315b3401652ed9c7f4808aa1c2b7acafe7b71ec40e6f13ec40c68d9980546001600160a01b0319166001600160a01b038616179055565b61015f7f38c4b9fd315b3401652ed9c7f4808aa1c2b7acafe7b71ec40e6f13ec40c68d9980546001600160a01b0319166001600160a01b038516179055565b6101a27f38c4b9fd315b3401652ed9c7f4808aa1c2b7acafe7b71ec40e6f13ec40c68d9980546001600160a01b0319166001600160a01b0330179055565b6101e57f8f398c922064e6fd9792bd6b71620a54b3e9d173c76474272e14902de642d58580546001600160a01b0319166001600160a01b038716179055565b5050505050610726806101f96000396000f3fe",
    wallet
  );
  
  // Construct deployment transaction
  try {
    const deployTx = await governorExecutorFactory.getDeployTransaction(
      admin, 
      delay, 
      govOps,
      govRes
    );
    
    // Get gas estimate and current gas price
    const gasPrice = await wallet.provider.getGasPrice();
    const gasLimit = await wallet.provider.estimateGas({
      from: wallet.address,
      data: deployTx.data
    }).catch(error => {
      console.warn(`Gas estimation failed: ${error.message}`);
      return ethers.BigNumber.from(5000000); // Fallback gas limit
    });
    
    // Deploy with appropriate gas settings
    console.log(`Deploying GovernorExecutor with the following parameters:`);
    console.log(`- Admin: ${admin}`);
    console.log(`- Delay: ${delay} seconds (${delay / 3600} hours)`);
    console.log(`- GovernorOperations: ${govOps}`);
    console.log(`- GovernorResearch: ${govRes}`);
    console.log(`\nDeploying from address: ${wallet.address}`);
    console.log(`Estimated gas limit: ${gasLimit.toString()}`);
    
    // Create deployment transaction
    const tx = {
      from: wallet.address,
      data: deployTx.data,
      gasLimit: gasLimit.mul(ethers.BigNumber.from(12)).div(ethers.BigNumber.from(10)), // Add 20% buffer
      gasPrice: gasPrice
    };
    
    // Sign and send transaction
    const signedTx = await wallet.signTransaction(tx);
    const txResponse = await wallet.provider.sendTransaction(signedTx);
    
    console.log(`Transaction sent: ${txResponse.hash}`);
    console.log(`Waiting for deployment confirmation...`);
    
    // Wait for transaction to be mined
    const receipt = await txResponse.wait(2); // Wait for 2 confirmations
    
    // Get contract address from receipt
    const governorExecutorAddress = receipt.contractAddress;
    
    console.log(`GovernorExecutor deployed at: ${governorExecutorAddress}`);
    console.log(`Gas used: ${receipt.gasUsed.toString()}`);
    
    return governorExecutorAddress;
  } catch (error) {
    console.error(`Error deploying GovernorExecutor: ${error.message}`);
    console.error(error);
    throw error;
  }
}

// Function to deploy GovernorGuard
async function deployGovernorGuard(admin, govOps, govRes, wallet) {
  console.log("\n=== Deploying GovernorGuard ===");
  
  // Create contract factory
  const governorGuardFactory = new ethers.ContractFactory(
    governorGuardAbi,
    "0x608060405234801561001057600080fd5b50604051610521380380610521833981810160405260608110156100335760006000fd5b5080516020820151604090920151909190600090841461005357600080fd5b6000831461006057600080fd5b6000821461006d57600080fd5b600380546001600160a01b0319166001600160a01b0387169081179091556100ba907f8f398c922064e6fd9792bd6b71620a54b3e9d173c76474272e14902de642d58590829055565b600180546001600160a01b03199081166001600160a01b038681169182179092556002805490921693831693909317909155505050610425806101006000396000f3fe",
    wallet
  );
  
  // Construct deployment transaction
  try {
    const deployTx = await governorGuardFactory.getDeployTransaction(
      admin, 
      govOps,
      govRes
    );
    
    // Get gas estimate and current gas price
    const gasPrice = await wallet.provider.getGasPrice();
    const gasLimit = await wallet.provider.estimateGas({
      from: wallet.address,
      data: deployTx.data
    }).catch(error => {
      console.warn(`Gas estimation failed: ${error.message}`);
      return ethers.BigNumber.from(3000000); // Fallback gas limit
    });
    
    // Deploy with appropriate gas settings
    console.log(`Deploying GovernorGuard with the following parameters:`);
    console.log(`- Admin: ${admin}`);
    console.log(`- GovernorOperations: ${govOps}`);
    console.log(`- GovernorResearch: ${govRes}`);
    console.log(`\nDeploying from address: ${wallet.address}`);
    console.log(`Estimated gas limit: ${gasLimit.toString()}`);
    
    // Create deployment transaction
    const tx = {
      from: wallet.address,
      data: deployTx.data,
      gasLimit: gasLimit.mul(ethers.BigNumber.from(12)).div(ethers.BigNumber.from(10)), // Add 20% buffer
      gasPrice: gasPrice
    };
    
    // Sign and send transaction
    const signedTx = await wallet.signTransaction(tx);
    const txResponse = await wallet.provider.sendTransaction(signedTx);
    
    console.log(`Transaction sent: ${txResponse.hash}`);
    console.log(`Waiting for deployment confirmation...`);
    
    // Wait for transaction to be mined
    const receipt = await txResponse.wait(2); // Wait for 2 confirmations
    
    // Get contract address from receipt
    const governorGuardAddress = receipt.contractAddress;
    
    console.log(`GovernorGuard deployed at: ${governorGuardAddress}`);
    console.log(`Gas used: ${receipt.gasUsed.toString()}`);
    
    return governorGuardAddress;
  } catch (error) {
    console.error(`Error deploying GovernorGuard: ${error.message}`);
    console.error(error);
    throw error;
  }
}

async function updateFrontendAddresses(governorExecutorAddress, governorGuardAddress) {
  console.log("\nUpdating frontend with deployed contract addresses...");

  // Define the path for the server utility file
  const serverUtilPath = path.join(__dirname, "../../../poscidondao_frontend/src/app/utils/serverConfig.ts");
  
  // Check if the server config file exists
  if (!fs.existsSync(serverUtilPath)) {
    console.log(`Server config file not found at ${serverUtilPath}`);
    console.log("Skipping frontend update. Please update the frontend manually.");
    return;
  }
  
  // Read the existing server config file
  console.log(`Reading existing server config file from: ${serverUtilPath}`);
  let serverConfigContent = fs.readFileSync(serverUtilPath, 'utf8');
  
  // Add a comment to indicate the file was updated
  const updateComment = `// Updated by deployGovernanceContracts script on ${new Date().toISOString()}`;
  if (!serverConfigContent.includes('// Updated by deployGovernanceContracts')) {
    // Add the comment after the first line (which should be 'use server')
    const lines = serverConfigContent.split('\n');
    lines.splice(1, 0, updateComment);
    serverConfigContent = lines.join('\n');
  } else {
    // Replace the existing update comment
    serverConfigContent = serverConfigContent.replace(
      /\/\/ Updated by deployGovernanceContracts script on .*/,
      updateComment
    );
  }
  
  // Update the governorExecutor address
  const executorRegex = /(governorExecutor\s*:\s*['"])([^'"]*)(["'])/;
  if (executorRegex.test(serverConfigContent)) {
    serverConfigContent = serverConfigContent.replace(executorRegex, `$1${governorExecutorAddress}$3`);
  } else {
    console.log("Could not find governorExecutor address in the server config file.");
    console.log("Please update the governorExecutor address manually.");
  }
  
  // Update the governorGuard address
  const guardRegex = /(governorGuard\s*:\s*['"])([^'"]*)(["'])/;
  if (guardRegex.test(serverConfigContent)) {
    serverConfigContent = serverConfigContent.replace(guardRegex, `$1${governorGuardAddress}$3`);
  } else {
    console.log("Could not find governorGuard address in the server config file.");
    console.log("Please update the governorGuard address manually.");
  }
  
  // Write the updated server config file
  fs.writeFileSync(serverUtilPath, serverConfigContent);
  console.log(`Updated server config file at: ${serverUtilPath}`);
  console.log(`- GovernorExecutor address updated to: ${governorExecutorAddress}`);
  console.log(`- GovernorGuard address updated to: ${governorGuardAddress}`);
}

// Main function
async function main() {
  console.log("=== PoSciDonDAO Governance Contracts Deployment ===");
  
  try {
    // Get network information
    const networkInfo = await getNetworkInfo();
    console.log(`Using network with chain ID: ${networkInfo.chainId}`);
    console.log(`Explorer: ${networkInfo.explorerLink}`);
    
    // Get RPC URL and private key
    const rpcUrl = await getRpcUrl();
    const privateKey = await getPrivateKey();
    
    if (!privateKey) {
      console.error('Private key not set in environment variables!');
      process.exit(1);
    }
    
    // Connect provider and wallet
    const provider = new ethers.providers.JsonRpcProvider(rpcUrl);
    const wallet = new ethers.Wallet(privateKey, provider);
    console.log(`Connected wallet: ${wallet.address}`);
    
    // Get account balance
    const balance = await provider.getBalance(wallet.address);
    console.log(`Wallet balance: ${ethers.utils.formatEther(balance)} ETH`);
    
    if (balance.eq(0)) {
      console.error('Wallet has no ETH! Please fund it before deployment.');
      process.exit(1);
    }
    
    // Default delay is 24 hours (in seconds)
    const delay = process.env.GOVERNOR_DELAY_SECONDS || 24 * 60 * 60;

    // Get required addresses
    const adminAddress = networkInfo.admin;
    const governorOperationsAddress = networkInfo.governorOperations;
    const governorResearchAddress = networkInfo.governorResearch;
    
    // Deploy GovernorExecutor
    const governorExecutorAddress = await deployGovernorExecutor(
      adminAddress,
      delay,
      governorOperationsAddress,
      governorResearchAddress,
      wallet
    );
    
    // Deploy GovernorGuard
    const governorGuardAddress = await deployGovernorGuard(
      adminAddress,
      governorOperationsAddress,
      governorResearchAddress,
      wallet
    );
    
    // Save addresses to file
    const deploymentInfo = {
      timestamp: new Date().toISOString(),
      network: networkInfo.chainId,
      explorer: networkInfo.explorerLink,
      governorExecutor: governorExecutorAddress,
      governorGuard: governorGuardAddress
    };
    
    const outputDir = path.join(__dirname, '../output');
    if (!fs.existsSync(outputDir)) {
      fs.mkdirSync(outputDir, { recursive: true });
    }
    
    const outputPath = path.join(outputDir, `governance_deployment_${Date.now()}.json`);
    fs.writeFileSync(outputPath, JSON.stringify(deploymentInfo, null, 2));
    console.log(`\nDeployment information saved to: ${outputPath}`);
    
    // Update frontend addresses if needed
    await updateFrontendAddresses(governorExecutorAddress, governorGuardAddress);
    
    console.log("\n=== Deployment Summary ===");
    console.log(`GovernorExecutor deployed at: ${governorExecutorAddress}`);
    console.log(`GovernorGuard deployed at: ${governorGuardAddress}`);
    console.log(`\nNext steps:`);
    console.log(`1. Verify the contracts on Basescan`);
    console.log(`2. Run the setupGovernanceMultiSigTransactions.js script to generate the Safe transactions`);
    console.log(`3. Import the generated JSON into the Safe interface to complete the setup`);
    
  } catch (error) {
    console.error(`Error in deployment: ${error.message}`);
    console.error(error);
    process.exit(1);
  }
}

// Execute main function
main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  }); 