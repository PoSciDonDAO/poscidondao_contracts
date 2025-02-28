import { ethers, run, hardhatArguments } from "hardhat";
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

  // Configuration parameters
  const uri = process.env.DON_BASE_URI || "https://metadata.poscidondao.org/don/";
  const admin = process.env.ADMIN_ADDRESS || deployer.address;
  const researchFundingWallet = process.env.RESEARCH_FUNDING_WALLET || "0x695f64829F0764FE1e95Fa32CD5c794A1a5034AF";
  const treasuryWallet = process.env.TREASURY_WALLET || admin;
  const usdc = process.env.USDC_ADDRESS || "0x08D39BBFc0F63668d539EA8BF469dfdeBAe58246";
  
  // Store deployed contract addresses
  const addresses: DeployedContracts = {};

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
    
    // If the donation address is already set correctly, we're done
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
    
    // Set the donation address
    console.log("Setting donation address...");
    const setDonationTx = await donContract.setDonation(addresses.donation);
    await setDonationTx.wait();
    console.log(`Donation address set in DON token`);
    
    // Optionally freeze the donation address if needed
    // Uncomment the following lines if you want to freeze the donation address after setting it
    /*
    console.log("Freezing donation address...");
    const freezeTx = await donContract.freezeDonation();
    await freezeTx.wait();
    console.log("Donation address frozen successfully.");
    */
  } catch (error) {
    console.error("Error interacting with DON token:", error);
  }
  
  // Generate files with deployed addresses
  generateAddressFiles(addresses);
  
  // Update frontend with deployed addresses
  await updateFrontendAddresses(
    addresses.don as string,
    addresses.donation as string
  );
  
  console.log("\nDeployment completed successfully!");
  console.log("DON token:", addresses.don);
  console.log("Donation contract:", addresses.donation);
  
  return addresses;
}

/**
 * Generate files with deployed addresses for frontend and scripts
 */
function generateAddressFiles(deployedContracts: DeployedContracts): void {
  // Generate Solidity file with addresses
  const outputPath = path.join(__dirname, "../contracts/DeployedDonationAddresses.sol");
  const solidityFileContent = `// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

/**
 * @title DeployedDonationAddresses
 * @dev Contains the addresses of deployed DON token and Donation contract
 */
library DeployedDonationAddresses {
    // Contract Addresses
    address constant don = ${deployedContracts.don};
    address constant donation = ${deployedContracts.donation};
}
`;

  fs.writeFileSync(outputPath, solidityFileContent);
  console.log(`DeployedDonationAddresses.sol has been generated at ${outputPath}`);
  
  // Generate JSON file with addresses for scripts
  const jsonOutputPath = path.join(__dirname, "../scripts/donationAddresses.json");
  const jsonContent = JSON.stringify({
    don: deployedContracts.don,
    donation: deployedContracts.donation,
    network: hardhatArguments.network,
    deploymentTimestamp: new Date().toISOString()
  }, null, 2);
  
  fs.writeFileSync(jsonOutputPath, jsonContent);
  console.log(`donationAddresses.json has been generated at ${jsonOutputPath}`);
}

// Execute the script
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  }); 