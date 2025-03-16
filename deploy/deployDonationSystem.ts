import { ethers, run, hardhatArguments, network } from "hardhat";
import { ContractFactory, Signer } from "ethers";
import dotenv from "dotenv";
import fs from "fs";
import path from "path";
import { getEnv, sleep, shouldSkipVerification } from "./utils";
import { updateFrontendAddresses } from "./updateFrontendAddresses";
dotenv.config();

interface DeployedContracts {
  [key: string]: string | number;
}

// Interface for Safe Transaction Service format
interface SafeTransaction {
  to: string;
  value: string;
  data: string;
  operation: number; // 0 for Call, 1 for DelegateCall
  safeTxGas: string;
  baseGas: string;
  gasPrice: string;
  gasToken: string;
  refundReceiver: string;
  nonce: number;
}

/**
 * @notice Deployment script for the DON token and Donation contract
 * This script can be used with either a multisig wallet or an EOA/dev wallet
 * For multisig wallets, it generates transaction data that can be imported into Safe
 * For EOA/dev wallets, it executes the transactions directly
 */
async function main(): Promise<DeployedContracts> {
  console.log(`Running deployment script for DON token and Donation contract`);
  
  // Load wallet private key from env file
  const PRIVATE_KEY = process.env.DEPLOYER_PRIVATE_KEY || "";
  if (!PRIVATE_KEY) {
    throw new Error("⛔️ Private key not detected! Add it to the .env file!");
  }

  const [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with the account:", deployer.address);
  console.log("Account Balance:", (await deployer.getBalance()).toString());

  if (!hardhatArguments.network) {
    throw new Error("Please pass --network");
  }

  // Get network information
  const chainId = network.config.chainId;
  console.log(`Network: ${network.name} (${chainId})`);

  // Configuration parameters
  const uri = "";
  const admin = process.env.ADMIN_ADDRESS || deployer.address;
  const researchFundingWallet = process.env.RESEARCH_FUNDING_WALLET || "0x695f64829F0764FE1e95Fa32CD5c794A1a5034AF";
  const treasuryWallet = process.env.TREASURY_WALLET || admin;
  const usdc = process.env.USDC_ADDRESS || "0x08D39BBFc0F63668d539EA8BF469dfdeBAe58246";
  
  // Store deployed contract addresses
  const addresses: DeployedContracts = {
    chainId: chainId || 0,
  };

  // Helper function to deploy and verify contracts
  const deployAndVerify = async (
    contractName: string,
    constructorArgs: any[],
    contractKey: string
  ): Promise<void> => {
    console.log(`\nDeploying ${contractName}...`);
    
    const Contract: ContractFactory = await ethers.getContractFactory(contractName);
    
    // Estimate contract deployment fee
    const estimatedGas = await ethers.provider.estimateGas(
      Contract.getDeployTransaction(...constructorArgs)
    );

    // Fetch current gas price
    const gasPrice = await ethers.provider.getGasPrice();

    // Calculate the estimated deployment cost
    const estimatedCost = estimatedGas.mul(gasPrice);
    console.log(`Estimated deployment cost: ${ethers.utils.formatEther(estimatedCost)} ETH`);
    
    // Deploy the contract
    const contract = await Contract.deploy(...constructorArgs);
    await contract.deployed();
    
    console.log(`${contractName} deployed at:`, contract.address);
    addresses[contractKey] = contract.address;
    
    // Check if we should skip verification
    if (shouldSkipVerification(hardhatArguments.network)) {
      console.log(`Skipping verification for ${contractName} on Base Sepolia network`);
      return;
    }
    
    // Verify the contract on the block explorer
    console.log(`Verifying ${contractName} in 1 minute...`);
    await sleep(60000);
    try {
      await run("verify:verify", {
        address: contract.address,
        constructorArguments: constructorArgs,
      });
      console.log(`${contractName} verified successfully`);
    } catch (error) {
      console.error(`Error verifying ${contractName}:`, error);
    }
  };

  // Deploy DON token
  await deployAndVerify("Don", [uri, treasuryWallet], "don");
  
  // Deploy Donation contract
  await deployAndVerify(
    "Donation",
    [researchFundingWallet, treasuryWallet, usdc, addresses.don],
    "donation"
  );
  
  // Set the Donation address in the DON token
  console.log("\nSetting Donation address in DON token...");
  const donContract = await ethers.getContractAt("Don", addresses.don as string);
  
  try {
    // Check if the donation address is already set
    const donationAddress = await donContract.donationAddress();
    console.log(`Current donation address: ${donationAddress}`);
    
    // Set the donation address if it's not already set
    if (donationAddress.toLowerCase() === addresses.donation.toString().toLowerCase()) {
      console.log("Donation address is already set correctly.");
      generateAddressFiles(addresses);
      
      // Update frontend with deployed addresses
      await updateFrontendAddresses(
        addresses.don as string,
        addresses.donation as string
      );
      
      return addresses;
    }
    
    // For development environments, set the donation address directly
    // For production environments, don't set the donation address
    if (network.name !== "mainnet" && network.name !== "base") {
      console.log("Development environment detected. Setting donation address directly...");
      const setDonationTx = await donContract.setDonation(addresses.donation);
      await setDonationTx.wait();
      console.log(`Donation address set in DON token`);
    } else {
      console.log("Production environment detected. Not setting donation address directly.");
      console.log("Please use the generated configuration files to set the donation address.");
    }
    
    // Always generate both multisig and EOA admin configuration files
    console.log("Generating admin configuration files...");
    
    // Create transaction data for setting donation address
    const setDonationData = donContract.interface.encodeFunctionData(
      "setDonation",
      [addresses.donation]
    );
    
    // Generate multisig transaction file
    const multisigTransactions: SafeTransaction[] = [{
      to: addresses.don as string,
      value: "0",
      data: setDonationData,
      operation: 0, // Call
      safeTxGas: "0",
      baseGas: "0",
      gasPrice: "0",
      gasToken: "0x0000000000000000000000000000000000000000",
      refundReceiver: "0x0000000000000000000000000000000000000000",
      nonce: 0
    }];
    
    generateMultisigTransactionsFile(multisigTransactions, addresses);
    
    // Generate EOA admin script
    generateEoaAdminScript(addresses, setDonationData);
    
    // Generate files with deployed addresses
    generateAddressFiles(addresses);
    
    // Update frontend with deployed addresses
    await updateFrontendAddresses(
      addresses.don as string,
      addresses.donation as string
    );
    
    return addresses;
  } catch (error) {
    console.error("Error setting donation address:", error);
    throw error;
  }
}

/**
 * Generate files with deployed addresses for frontend and scripts
 */
function generateAddressFiles(deployedContracts: DeployedContracts): void {
  // Write to donationAddresses.json in the scripts folder
  const addressesPath = path.join(__dirname, "../scripts/donationAddresses.json");
  
  const addressData = {
    chainId: deployedContracts.chainId,
    don: deployedContracts.don,
    donation: deployedContracts.donation,
    deploymentTimestamp: new Date().toISOString()
  };
  
  fs.writeFileSync(addressesPath, JSON.stringify(addressData, null, 2));
  console.log(`Addresses written to ${addressesPath}`);
}

/**
 * Generate multisig transaction file for Safe Wallet
 */
function generateMultisigTransactionsFile(
  transactions: SafeTransaction[],
  deployedContracts: DeployedContracts
): void {
  // Use the existing multiSigWalletScripts folder
  const multisigDir = path.join(__dirname, "../scripts/multiSigWalletScripts");
  if (!fs.existsSync(multisigDir)) {
    fs.mkdirSync(multisigDir, { recursive: true });
  }

  // Write transactions to JSON file - use the same naming convention as in deploySystemWithFactory.ts
  const multisigPath = path.join(
    multisigDir,
    `donationSafeBatchTransaction.json`
  );
  
  // Create a format compatible with Safe Wallet
  const multisigData = {
    version: "1.0",
    chainId: deployedContracts.chainId,
    createdAt: new Date().toISOString(),
    meta: {
      name: "PoSciDonDAO Donation System Setup",
      description: "Transactions to configure the PoSciDonDAO Donation System",
    },
    transactions: transactions
  };
  
  fs.writeFileSync(multisigPath, JSON.stringify(multisigData, null, 2));
  console.log(`Multisig transaction file written to ${multisigPath}`);
}

/**
 * Generate EOA admin script for direct execution
 */
function generateEoaAdminScript(
  deployedContracts: DeployedContracts,
  setDonationData: string
): void {
  // Use the dev wallet scripts folder
  const scriptsDir = path.join(__dirname, "../scripts/devWalletScripts");
  if (!fs.existsSync(scriptsDir)) {
    fs.mkdirSync(scriptsDir, { recursive: true });
  }

  // Write JavaScript execution script
  const scriptPath = path.join(
    scriptsDir,
    `donationExecuteTransactions.js`
  );
  
  const scriptContent = `
const { ethers } = require("ethers");
require("dotenv").config();

/**
 * Execute Donation System configuration transactions
 * This script can be used to configure the Donation System with an EOA
 */
async function main() {
  console.log("Executing Donation System configuration transactions...");
  
  // Load configuration from donationAddresses.json
  const fs = require('fs');
  const path = require('path');
  const addressesPath = path.join(__dirname, '../donationAddresses.json');
  
  if (!fs.existsSync(addressesPath)) {
    console.error("Error: donationAddresses.json not found. Please run the deployment script first.");
    process.exit(1);
  }
  
  const addresses = JSON.parse(fs.readFileSync(addressesPath, 'utf8'));
  const donAddress = addresses.don;
  const donationAddress = addresses.donation;
  
  console.log("DON Token address:", donAddress);
  console.log("Donation contract address:", donationAddress);
  
  // Connect to provider
  const provider = new ethers.providers.JsonRpcProvider(process.env.RPC_URL);
  
  // Load wallet from private key
  const wallet = new ethers.Wallet(process.env.PRIVATE_KEY, provider);
  console.log("Using wallet address:", wallet.address);
  
  // Get contract instances
  const donAbi = ["function setDonation(address donation)", "function donationAddress() view returns (address)"];
  const donContract = new ethers.Contract(donAddress, donAbi, wallet);
  
  // Check current donation address
  const currentDonation = await donContract.donationAddress();
  console.log("Current donation address:", currentDonation);
  
  if (currentDonation.toLowerCase() === donationAddress.toLowerCase()) {
    console.log("Donation address already set correctly. No action needed.");
    return;
  }
  
  // Set donation address
  console.log("Setting donation address to:", donationAddress);
  const tx = await donContract.setDonation(donationAddress);
  console.log("Transaction sent:", tx.hash);
  
  // Wait for transaction to be mined
  const receipt = await tx.wait();
  console.log("Transaction confirmed in block:", receipt.blockNumber);
  console.log("Gas used:", receipt.gasUsed.toString());
  
  console.log("Donation System configuration completed successfully!");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("Error executing transactions:", error);
    process.exit(1);
  });
`;
  
  fs.writeFileSync(scriptPath, scriptContent);
  console.log(`EOA admin script written to ${scriptPath}`);
}

// Execute the script
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  }); 