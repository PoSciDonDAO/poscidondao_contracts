import { ethers, run, hardhatArguments } from "hardhat";
import { sleep, shouldSkipVerification } from "./utils";
import dotenv from "dotenv";
import fs from "fs";
import path from "path";

dotenv.config();

interface DeployedContracts {
  [key: string]: string | number | undefined;
}

async function main() {
  console.log("Starting verification of all deployed contracts...");

  if (!hardhatArguments.network) {
    throw new Error("Please pass --network");
  }

  // Check if we should skip verification
  if (shouldSkipVerification(hardhatArguments.network)) {
    console.log(`Skipping verification on Base Sepolia network`);
    return;
  }

  // Load the deployed addresses from the frontend config file
  const POSCIDONDAO_ROOT = process.env.POSCIDONDAO_ROOT;
  if (!POSCIDONDAO_ROOT) {
    throw new Error("⛔️ POSCIDONDAO_ROOT environment variable not set!");
  }

  const FRONTEND_DIR = path.join(POSCIDONDAO_ROOT, "poscidondao_frontend");
  const frontendAddressesFilePath = path.join(FRONTEND_DIR, "src/app/utils/serverConfig.ts");

  if (!fs.existsSync(frontendAddressesFilePath)) {
    throw new Error(`Frontend addresses file not found at: ${frontendAddressesFilePath}`);
  }

  // Read and parse the frontend config file
  const fileContent = fs.readFileSync(frontendAddressesFilePath, 'utf8');
  
  // Extract addresses using regex
  const addresses: { [key: string]: string } = {};
  const addressRegex = /'([^']+)'/g;
  const lines = fileContent.split('\n');
  
  for (const line of lines) {
    if (line.includes("'0x")) {
      const match = line.match(/'(0x[a-fA-F0-9]{40})'/);
      if (match) {
        const key = line.trim().split(':')[0].trim();
        addresses[key] = match[1];
      }
    }
  }

  const uri = "https://red-improved-cod-476.mypinata.cloud/ipfs/bafkreibmrcsilc2ojbu636rl2gz2vhlsy7pyi3uvzroccqwc7b3qucszum";
  const admin = hardhatArguments.network === "baseMainnet" ? "0x96f67a852f8d3bc05464c4f91f97aace060e247a" : "0x96f67a852f8d3bc05464c4f91f97aace060e247a";
  const sci = hardhatArguments.network === "baseMainnet" ? "0x25E0A7767d03461EaF88b47cd9853722Fe05DFD3" : "0xff88CC162A919bdd3F8552D331544629A6BEC1BE";
  const researchFundingWallet = hardhatArguments.network === "baseMainnet" ? "0x96f67a852f8d3bc05464c4f91f97aace060e247a" : "0x96f67a852f8d3bc05464c4f91f97aace060e247a";
  const usdc = hardhatArguments.network === "baseMainnet" ? "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913" : "0x08D39BBFc0F63668d539EA8BF469dfdeBAe58246";
  const signer = "0x690BF2dB31D39EE0a88fcaC89117b66a588E865a";

  // Define verification tasks with their constructor arguments
  const verificationTasks = [
    {
      name: "Don",
      address: addresses.don,
      constructorArgs: [uri, admin]
    },
    {
      name: "Po",
      address: addresses.po,
      constructorArgs: [uri, admin]
    },
    {
      name: "SciManager",
      address: addresses.sciManager,
      constructorArgs: [admin, sci]
    },
    {
      name: "Donation",
      address: addresses.donation,
      constructorArgs: [researchFundingWallet, admin, usdc, addresses.don]
    },
    {
      name: "PoToSciExchange",
      address: addresses.poToSciExchange,
      constructorArgs: [admin, sci, addresses.po]
    },
    {
      name: "GovernorOperations",
      address: addresses.governorOperations,
      constructorArgs: [addresses.sciManager, admin, addresses.po, signer]
    },
    {
      name: "GovernorResearch",
      address: addresses.governorResearch,
      constructorArgs: [addresses.sciManager, admin, researchFundingWallet]
    },
    {
      name: "GovernorExecutor",
      address: addresses.governorExecutor,
      constructorArgs: [admin, 3600, addresses.governorOperations, addresses.governorResearch]
    },
    {
      name: "GovernorGuard",
      address: addresses.governorGuard,
      constructorArgs: [admin, addresses.governorOperations, addresses.governorResearch]
    },
    {
      name: "Transaction",
      address: addresses.transactionResearch,
      constructorArgs: []
    },
    {
      name: "Transaction",
      address: addresses.transactionOperations,
      constructorArgs: []
    },
    {
      name: "Election",
      address: addresses.election,
      constructorArgs: []
    },
    {
      name: "Impeachment",
      address: addresses.impeachment,
      constructorArgs: []
    },
    {
      name: "ParameterChange",
      address: addresses.parameterChange,
      constructorArgs: []
    },
    {
      name: "ActionCloneFactoryResearch",
      address: addresses.actionFactoryResearch,
      constructorArgs: [addresses.governorResearch, addresses.transactionResearch]
    },
    {
      name: "ActionCloneFactoryOperations",
      address: addresses.actionFactoryOperations,
      constructorArgs: [addresses.governorOperations, addresses.transactionOperations, addresses.election, addresses.impeachment, addresses.parameterChange]
    }
  ];

  // Verify each contract
  for (const task of verificationTasks) {
    if (!task.address) {
      console.log(`Skipping ${task.name} - address not found`);
      continue;
    }

    console.log(`\nVerifying ${task.name} at ${task.address}`);
    try {
      await run("verify:verify", {
        address: task.address,
        constructorArguments: task.constructorArgs
      });
      console.log(`✅ ${task.name} verified successfully`);
      
      // Add delay between verifications to avoid rate limiting
      console.log("Waiting 30 seconds before next verification...");
      await sleep(30000);
    } catch (error: any) {
      if (error.message.includes("Already Verified")) {
        console.log(`Contract ${task.name} is already verified`);
      } else {
        console.error(`❌ Error verifying ${task.name}:`, error);
      }
    }
  }

  console.log("\nVerification process completed!");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  }); 