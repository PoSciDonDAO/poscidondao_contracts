import { ethers, hardhatArguments, run } from "hardhat";
import { Contract, ContractFactory, Signer } from "ethers";
import dotenv from "dotenv";
import fs from "fs";
import path from "path";
import { sleep } from "./utils";
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
const frontendAbiDir = path.join(FRONTEND_DIR, "src/app/abi");

// Existing contract addresses
const governorOperations = "0xEe1C6D7A3Db1e629b605Da94f9BDD6b93d45Ce6b";
const governorResearch = "0x5a06b21D5AF5DEAfBFCF0Cd528F02DAEE9976aD6";
const election = "0x7489F2b7e997bEE4D8BFD771C29d0e300a2e2eEb";
const impeachment = "0xA2cF37B3d04640b0e22bBe229148919d7eCf8Ac1";
const parameterChange = "0x71308C317B645b2e77812482806b786E8766399a";

// Storage for newly deployed contracts
interface DeployedContracts {
  [key: string]: string | undefined;
}

const deployedContracts: DeployedContracts = {};

// Setup ABI and bytecode directories
function setupAbiDir() {
  // Remove backend ABI directory
  if (fs.existsSync(abiOutputDir)) {
    fs.rmSync(abiOutputDir, { recursive: true, force: true });
    console.log(`Removed existing backend directory: ${abiOutputDir}`);
  }
  fs.mkdirSync(abiOutputDir, { recursive: true });
  console.log(`Created backend ABI directory`);

  // Remove frontend ABI directory
  if (fs.existsSync(frontendAbiDir)) {
    fs.rmSync(frontendAbiDir, { recursive: true, force: true });
    console.log(`Removed existing frontend ABI directory: ${frontendAbiDir}`);
  }
  fs.mkdirSync(frontendAbiDir, { recursive: true });
  console.log(`Created frontend ABI directory`);
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

// Function to extract ABIs after deployment
function extractAbis(dir: string) {
  const files = fs.readdirSync(dir);
  files.forEach((file) => {
    const fullPath = path.join(dir, file);
    const stat = fs.statSync(fullPath);
    if (stat.isDirectory()) {
      if (file.toLowerCase() === "interfaces") {
        console.log(`Skipping interfaces directory: ${fullPath}`);
        return;
      }
      extractAbis(fullPath);
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
    }
  });
}

// Deploy and verify a contract
async function deployAndVerify(
  contractName: string,
  constructorArgs: any[],
  contractKey: string
): Promise<string | undefined> {
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

    // Verify the contract on the block explorer if on mainnet
    if (hardhatArguments.network === "baseMainnet") {
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
    }
    
    return contract.address;
  } catch (error) {
    console.error(`Error deploying ${contractName}:`, error);
    deployedContracts[contractKey] = undefined;
    return undefined;
  }
}

// Generate instructions for updating the serverConfig.ts file
function generateServerConfigUpdates() {
  console.log("\n=== INSTRUCTIONS FOR UPDATING serverConfig.ts ===");
  console.log("Update these values in your frontend serverConfig.ts file:");
  console.log(`transactionResearch: '${deployedContracts.transactionResearch || "DEPLOYMENT_FAILED"}',`);
  console.log(`transactionOperations: '${deployedContracts.transactionOperations || "DEPLOYMENT_FAILED"}',`);
  console.log(`actionFactoryOperations: '${deployedContracts.actionCloneFactoryOperations || "DEPLOYMENT_FAILED"}',`);
  console.log(`actionFactoryResearch: '${deployedContracts.actionCloneFactoryResearch || "DEPLOYMENT_FAILED"}',`);

  // Create a formatted output text file for easy reference
  const outputDir = path.join(__dirname, "output");
  if (!fs.existsSync(outputDir)) {
    fs.mkdirSync(outputDir, { recursive: true });
  }

  const outputPath = path.join(outputDir, "serverConfig_updates.txt");
  const content = `
// Update these values in your frontend serverConfig.ts file:
transactionResearch: '${deployedContracts.transactionResearch || "DEPLOYMENT_FAILED"}',
transactionOperations: '${deployedContracts.transactionOperations || "DEPLOYMENT_FAILED"}',
actionFactoryOperations: '${deployedContracts.actionCloneFactoryOperations || "DEPLOYMENT_FAILED"}',
actionFactoryResearch: '${deployedContracts.actionCloneFactoryResearch || "DEPLOYMENT_FAILED"}',
`;

  fs.writeFileSync(outputPath, content, "utf8");
  console.log(`\nConfig updates have been saved to: ${outputPath}`);
}

// Main function for deployment sequence
async function main() {
  const PRIVATE_KEY: string = process.env.DEPLOYER_PRIVATE_KEY || "";
  if (!PRIVATE_KEY)
    throw new Error("⛔️ Private key not detected! Add it to the .env file!");

  const [deployer]: Signer[] = await ethers.getSigners();
  console.log("Deploying contracts with the account:", await deployer.getAddress());
  console.log("Account Balance:", (await deployer.getBalance()).toString());

  if (!hardhatArguments.network) throw new Error("Please pass --network");
  console.log(`Deploying to network: ${hardhatArguments.network}`);

  try {
    // Setup ABI directories
    setupAbiDir();

    // Deploy Transaction contracts for research and operations
    console.log("\n=== DEPLOYING TRANSACTION CONTRACTS ===");
    const transactionResearchAddress = await deployAndVerify("Transaction", [], "transactionResearch");
    const transactionOperationsAddress = await deployAndVerify("Transaction", [], "transactionOperations");

    if (!transactionResearchAddress || !transactionOperationsAddress) {
      throw new Error("Failed to deploy Transaction contracts");
    }

    // Deploy ActionCloneFactory contracts
    console.log("\n=== DEPLOYING ACTION CLONE FACTORY CONTRACTS ===");
    
    // ActionCloneFactoryResearch
    await deployAndVerify(
      "ActionCloneFactoryResearch",
      [governorResearch, transactionResearchAddress],
      "actionCloneFactoryResearch"
    );

    // ActionCloneFactoryOperations
    await deployAndVerify(
      "ActionCloneFactoryOperations",
      [governorOperations, transactionOperationsAddress, election, impeachment, parameterChange],
      "actionCloneFactoryOperations"
    );

    // Extract ABIs and copy to frontend
    console.log("\n=== EXTRACTING AND COPYING ABIS ===");
    // extractAbis(artifactsDir);
    // copyAbiFilesToFrontend();

    // Output instructions for updating serverConfig.ts
    generateServerConfigUpdates();

  } catch (error) {
    console.error("Error in deployment process:", error);
    process.exit(1);
  }
}

main()
  .then(() => {
    console.log("\n=== DEPLOYMENT COMPLETED SUCCESSFULLY ===");
    process.exit(0);
  })
  .catch((error) => {
    console.error("Fatal error:", error);
    process.exit(1);
  }); 