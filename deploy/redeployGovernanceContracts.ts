import { ethers, hardhatArguments, run } from "hardhat";
import { ContractFactory, Signer } from "ethers";
import dotenv from "dotenv";
import fs from "fs";
import path from "path";
import { sleep, shouldSkipVerification } from "./utils";
dotenv.config();

// Environment variable validation and path setup
const POSCIDONDAO_ROOT = process.env.POSCIDONDAO_ROOT;
if (!POSCIDONDAO_ROOT) {
  throw new Error("⛔️ POSCIDONDAO_ROOT environment variable not set! Add it to the .env file!");
}

// Validate the root directory exists
if (!fs.existsSync(POSCIDONDAO_ROOT)) {
  throw new Error(`⛔️ POSCIDONDAO_ROOT directory does not exist: ${POSCIDONDAO_ROOT}`);
}

// Setup paths relative to POSCIDONDAO_ROOT
const FRONTEND_DIR = path.join(POSCIDONDAO_ROOT, "poscidondao_frontend");
const CONTRACTS_DIR = path.join(POSCIDONDAO_ROOT, "poscidondao_contracts");

// Validate project directories exist
if (!fs.existsSync(FRONTEND_DIR)) {
  throw new Error(`⛔️ Frontend directory does not exist: ${FRONTEND_DIR}`);
}
if (!fs.existsSync(CONTRACTS_DIR)) {
  throw new Error(`⛔️ Contracts directory does not exist: ${CONTRACTS_DIR}`);
}

// Define all paths relative to project directories
const artifactsDir = path.join(CONTRACTS_DIR, "artifacts/contracts");
const abiOutputDir = path.join(CONTRACTS_DIR, "abi");
const bytecodeOutputDir = path.join(abiOutputDir, "bytecode");
const frontendAbiDir = path.join(FRONTEND_DIR, "src/app/abi");
const frontendBytecodeDir = path.join(frontendAbiDir, "bytecode");

// Network-dependent addresses
const admin = hardhatArguments.network === "baseMainnet" ? "0x96f67a852f8d3bc05464c4f91f97aace060e247a" : "0x96f67a852f8d3bc05464c4f91f97aace060e247a";
const researchFundingWallet = hardhatArguments.network === "baseMainnet" ? "0x96f67a852f8d3bc05464c4f91f97aace060e247a" : "0x96f67a852f8d3bc05464c4f91f97aace060e247a";
const signer = "0x690BF2dB31D39EE0a88fcaC89117b66a588E865a";

// Existing contract addresses
const po = hardhatArguments.network === "baseMainnet" ? "0x418a1F35bB56FDd9bCcFb2ce7adD06faE447Cc54" : "YOUR_TEST_PO_ADDRESS";
const sciManager = hardhatArguments.network === "baseMainnet" ? "0x032746d21e589f9c42b81d3EC77E389dbf4B96b2" : "YOUR_TEST_SCIMANAGER_ADDRESS";

// Storage for deployed contracts
interface DeployedContracts {
  [key: string]: string | number | undefined;
}

// Ensure ABI and bytecode directories exist, remove old ones if necessary
function setupAbiAndBytecodeDirs() {
  // Remove backend ABI and bytecode directories
  if (fs.existsSync(abiOutputDir)) {
    fs.rmSync(abiOutputDir, { recursive: true, force: true });
    console.log(`Removed existing backend directory: ${abiOutputDir}`);
  }
  fs.mkdirSync(abiOutputDir, { recursive: true });
  fs.mkdirSync(bytecodeOutputDir, { recursive: true });
  console.log(`Created backend ABI and bytecode directories`);

  // Remove frontend ABI and bytecode directories
  if (fs.existsSync(frontendAbiDir)) {
    fs.rmSync(frontendAbiDir, { recursive: true, force: true });
    console.log(`Removed existing frontend ABI directory: ${frontendAbiDir}`);
  }
  fs.mkdirSync(frontendAbiDir, { recursive: true });
  fs.mkdirSync(frontendBytecodeDir, { recursive: true });
  console.log(`Created frontend ABI and bytecode directories`);
}

// Copy ABI files to frontend directory
function copyAbiFilesToFrontend() {
  const abiFiles = fs.readdirSync(abiOutputDir);
  abiFiles.forEach((file) => {
    const srcPath = path.join(abiOutputDir, file);
    const destPath = path.join(frontendAbiDir, file);
    if (fs.lstatSync(srcPath).isFile()) {
      fs.copyFileSync(srcPath, destPath);
      console.log(`Copied ABI ${file} to frontend directory`);
    }
  });
}

// Copy bytecode files to frontend directory
function copyBytecodeFilesToFrontend() {
  const bytecodeFiles = fs.readdirSync(bytecodeOutputDir);
  
  bytecodeFiles.forEach((file) => {
    const srcPath = path.join(bytecodeOutputDir, file);
    const destPath = path.join(frontendBytecodeDir, file);
    if (fs.lstatSync(srcPath).isFile()) {
      fs.copyFileSync(srcPath, destPath);
      console.log(`Copied bytecode ${file} to frontend directory`);
    }
  });
}

// Function to extract ABIs and bytecodes after deployment
function extractAbisAndBytecodes(dir: string) {
  const files = fs.readdirSync(dir);
  files.forEach((file) => {
    const fullPath = path.join(dir, file);
    const stat = fs.statSync(fullPath);
    if (stat.isDirectory()) {
      if (file.toLowerCase() === "interfaces") {
        console.log(`Skipping interfaces directory: ${fullPath}`);
        return;
      }
      extractAbisAndBytecodes(fullPath);
    } else if (file.endsWith(".json")) {
      const artifact = JSON.parse(fs.readFileSync(fullPath, "utf8"));
      if (artifact.abi) {
        const contractName =
          artifact.contractName || path.basename(file, ".json");
        const abiFileName = `${contractName}.json`;
        const abiFilePath = path.join(abiOutputDir, abiFileName);
        fs.writeFileSync(abiFilePath, JSON.stringify(artifact.abi, null, 2));
        console.log(`Extracted ABI for ${contractName} to ${abiFilePath}`);
      }
      if (artifact.bytecode) {
        const contractName =
          artifact.contractName || path.basename(file, ".json");
        const bytecodeFileName = `${contractName}.bytecode.json`;
        const bytecodeFilePath = path.join(bytecodeOutputDir, bytecodeFileName);
        fs.writeFileSync(
          bytecodeFilePath,
          JSON.stringify({ bytecode: artifact.bytecode }, null, 2)
        );
        console.log(
          `Extracted bytecode for ${contractName} to ${bytecodeFilePath}`
        );
      }
    }
  });
}

// Generate instructions for updating the serverConfig.ts file
function generateServerConfigUpdates(deployedContracts: DeployedContracts) {
  console.log("\n=== INSTRUCTIONS FOR UPDATING serverConfig.ts ===");
  console.log("Update these values in your frontend serverConfig.ts file:");
  console.log(`governorOperations: '${deployedContracts.governorOperations || "DEPLOYMENT_FAILED"}',`);
  console.log(`governorResearch: '${deployedContracts.governorResearch || "DEPLOYMENT_FAILED"}',`);

  // Create a formatted output text file for easy reference
  const outputDir = path.join(__dirname, "output");
  if (!fs.existsSync(outputDir)) {
    fs.mkdirSync(outputDir, { recursive: true });
  }

  const outputPath = path.join(outputDir, "serverConfig_updates_governance.txt");
  const content = `
// Update these values in your frontend serverConfig.ts file:
governorOperations: '${deployedContracts.governorOperations || "DEPLOYMENT_FAILED"}',
governorResearch: '${deployedContracts.governorResearch || "DEPLOYMENT_FAILED"}',
`;

  fs.writeFileSync(outputPath, content, "utf8");
  console.log(`\nConfig updates have been saved to: ${outputPath}`);
}

// Function to generate the Solidity file containing deployed addresses
const generateSolidityAddressFile = async (
  deployedContracts: DeployedContracts
): Promise<void> => {
  // Filter out undefined values
  const filteredContracts: { [key: string]: string | number } = {};
  for (const [key, value] of Object.entries(deployedContracts)) {
    if (value !== undefined) {
      filteredContracts[key] = value;
    }
  }

  const contractsDir: string = path.join(__dirname, "..", "contracts");
  const outputPath: string = path.join(contractsDir, "GovernanceAddresses.sol");

  if (!fs.existsSync(contractsDir)) {
    fs.mkdirSync(contractsDir, { recursive: true });
  }

  if (fs.existsSync(outputPath)) {
    fs.unlinkSync(outputPath);
    console.log(`Existing file at ${outputPath} has been deleted.`);
  }

  const solidityFileContent: string = `
  // SPDX-License-Identifier: UNLICENSED
  pragma solidity 0.8.19;

  library GovernanceAddresses {
  ${Object.entries(filteredContracts)
    .map(([key, value]) => {
      if (!value) {
        console.warn(`Warning: Value for ${key} is undefined`);
        return `// Warning: Value for ${key} was undefined`;
      }
      
      if (typeof value === 'string' && ethers.utils.isAddress(value)) {
        const checksummedAddress: string = ethers.utils.getAddress(value);
        return `address constant ${key} = ${checksummedAddress};`;
      } else if (typeof value === "number") {
        return `uint constant ${key} = ${value};`;
      } else {
        return `address constant ${key} = ${value};`;
      }
    })
    .join("\n")}
  }
  `;

  fs.writeFileSync(outputPath, solidityFileContent);
  console.log(`GovernanceAddresses.sol has been generated at ${outputPath}`);
};

// Add this function before main()
async function flattenContracts(
  contractNames: string[],
  deploymentVars: {
    admin: string;
    sciManager: string;
    po: string;
    researchFundingWallet: string;
    signer: string;
  }
): Promise<void> {
  console.log("\nFlattening contracts for manual verification...");
  
  const flattenedDir = path.join(__dirname, "../flattened");
  if (!fs.existsSync(flattenedDir)) {
    fs.mkdirSync(flattenedDir, { recursive: true });
  }

  // Contract path mapping
  const contractPaths: { [key: string]: string } = {
    "GovernorOperations": "governance/GovernorOperations.sol",
    "GovernorResearch": "governance/GovernorResearch.sol"
  };

  for (const contractName of contractNames) {
    try {
      const contractPath = contractPaths[contractName];
      if (!contractPath) {
        console.log(`⚠️ Path mapping not found for ${contractName}, skipping...`);
        continue;
      }
      
      const sourcePath = path.join(__dirname, "../contracts", contractPath);
      if (!fs.existsSync(sourcePath)) {
        console.log(`⚠️ Source file not found for ${contractName} at ${sourcePath}, skipping...`);
        continue;
      }

      console.log(`Flattening ${contractName}...`);
      const flattenedCode = await run("flatten:get-flattened-sources", {
        files: [sourcePath],
      });

      // Remove duplicate SPDX license identifiers and pragma statements
      const cleaned = flattenedCode
        .split('\n')
        .filter((line: string, index: number, arr: string[]) => {
          if (line.includes('SPDX-License-Identifier')) {
            return index === arr.findIndex((l: string) => l.includes('SPDX-License-Identifier'));
          }
          if (line.includes('pragma')) {
            return index === arr.findIndex((l: string) => l.includes('pragma'));
          }
          return true;
        })
        .join('\n');

      const outputPath = path.join(flattenedDir, `${contractName}_flattened.sol`);
      fs.writeFileSync(outputPath, cleaned);
      console.log(`✅ Flattened contract saved to: ${outputPath}`);
      
      // Also save the constructor arguments for easy reference
      const constructorArgs = getConstructorArgs(contractName, deploymentVars);
      if (constructorArgs) {
        const argsPath = path.join(flattenedDir, `${contractName}_constructor_args.txt`);
        fs.writeFileSync(argsPath, constructorArgs);
        console.log(`✅ Constructor arguments saved to: ${argsPath}`);
      }
    } catch (error) {
      console.error(`❌ Error flattening ${contractName}:`, error);
    }
  }
}

// Helper function to get constructor arguments for each contract
function getConstructorArgs(
  contractName: string,
  deploymentVars: {
    admin: string;
    sciManager: string;
    po: string;
    researchFundingWallet: string;
    signer: string;
  }
): string | null {
  const args: { [key: string]: any[] } = {
    "GovernorOperations": [deploymentVars.sciManager, deploymentVars.admin, deploymentVars.po, deploymentVars.signer],
    "GovernorResearch": [deploymentVars.sciManager, deploymentVars.admin, deploymentVars.researchFundingWallet]
  };
  
  return args[contractName]?.join(", ") || null;
}

async function main(): Promise<DeployedContracts> {
  const PRIVATE_KEY: string = process.env.DEPLOYER_PRIVATE_KEY || "";
  if (!PRIVATE_KEY)
    throw new Error("⛔️ Private key not detected! Add it to the .env file!");

  const [deployer]: Signer[] = await ethers.getSigners();
  console.log("Deploying contracts with the account:", await deployer.getAddress());
  console.log("Account Balance:", (await deployer.getBalance()).toString());

  if (!hardhatArguments.network) throw new Error("Please pass --network");
  console.log(`Deploying to network: ${hardhatArguments.network}`);

  const deployedContracts: DeployedContracts = {};

  const deployAndVerify = async (
    contractName: string,
    constructorArgs: any[],
    contractKey: string
  ): Promise<string | undefined> => {
    try {
      const Contract: ContractFactory = await ethers.getContractFactory(contractName);
      
      // Estimate contract deployment fee
      const estimatedGas = await ethers.provider.estimateGas(
        Contract.getDeployTransaction(...constructorArgs)
      );

      // Fetch current gas price
      const gasPrice = await ethers.provider.getGasPrice();

      // Calculate the estimated deployment cost
      const estimatedCost = estimatedGas.mul(gasPrice);
      console.log(`Estimated deployment cost for ${contractName}: ${ethers.utils.formatEther(estimatedCost)} ETH`);
      
      const contract = await Contract.deploy(...constructorArgs);
      await contract.deployed();
      console.log(`${contractName} deployed at:`, contract.address);
      deployedContracts[contractKey] = contract.address;

      // Check if we should skip verification
      if (shouldSkipVerification(hardhatArguments.network)) {
        return contract.address;
      }
      
      // Verify the contract on the block explorer
      console.log(`Verifying ${contractName} in 1 minute...`);
      await sleep(60000); // Wait for the block explorer to index the contract
      try {
        await run("verify:verify", {
          address: contract.address,
          constructorArguments: constructorArgs,
        });
        console.log(`${contractName} verified successfully`);
      } catch (error) {
        console.error(`Error verifying ${contractName}:`, error);
      }
      
      return contract.address;
    } catch (error) {
      console.error(`Error deploying ${contractName}:`, error);
      deployedContracts[contractKey] = undefined;
      return undefined;
    }
  };

  try {
    // Deploy governance contracts
    console.log("\n=== DEPLOYING GOVERNANCE CONTRACTS ===");
    
    // Deploy GovernorOperations
    await deployAndVerify(
      "GovernorOperations",
      [sciManager, admin, po, signer],
      "governorOperations"
    );
    
    // Deploy GovernorResearch
    await deployAndVerify(
      "GovernorResearch",
      [sciManager, admin, researchFundingWallet],
      "governorResearch"
    );

    // Setup ABI directories and extract ABIs
    setupAbiAndBytecodeDirs();
    extractAbisAndBytecodes(artifactsDir);
    copyAbiFilesToFrontend();
    copyBytecodeFilesToFrontend();

    // Generate Solidity address file
    await generateSolidityAddressFile({
      deploymentTimestamp: Math.floor(Date.now() / 1000),
      governorOperations: deployedContracts.governorOperations,
      governorResearch: deployedContracts.governorResearch
    });

    // Generate server config updates
    generateServerConfigUpdates(deployedContracts);

    // Flatten contracts for verification
    await flattenContracts(
      ["GovernorOperations", "GovernorResearch"],
      { admin, sciManager, po, researchFundingWallet, signer }
    );
    
  } catch (error) {
    console.error("Error in deployment process:", error);
  }

  return deployedContracts;
}

main()
  .then((deployedContracts) => {
    console.log("\n=== DEPLOYMENT COMPLETED SUCCESSFULLY ===");
    console.log("Deployed Contracts:", deployedContracts);
    process.exit(0);
  })
  .catch((error) => {
    console.error("Fatal error:", error);
    process.exit(1);
  });
