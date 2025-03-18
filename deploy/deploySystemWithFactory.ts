"use client";

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
const frontendAddressesFilePath = path.join(FRONTEND_DIR, "src/app/utils/serverConfig.ts");
const artifactsDir = path.join(CONTRACTS_DIR, "artifacts/contracts");
const abiOutputDir = path.join(CONTRACTS_DIR, "abi");
const bytecodeOutputDir = path.join(abiOutputDir, "bytecode");
const frontendAbiDir = path.join(FRONTEND_DIR, "src/app/abi");
const frontendBytecodeDir = path.join(frontendAbiDir, "bytecode");

interface DeployedContracts {
  [key: string]: string | number | undefined;
}

const usdc = hardhatArguments.network === "baseMainnet" ? "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913" : "0x08D39BBFc0F63668d539EA8BF469dfdeBAe58246";
const admin = hardhatArguments.network === "baseMainnet" ? "0x96f67a852f8d3bc05464c4f91f97aace060e247a" : "0x96f67a852f8d3bc05464c4f91f97aace060e247a";
const sci = hardhatArguments.network === "baseMainnet" ? "0x25E0A7767d03461EaF88b47cd9853722Fe05DFD3" : "0xff88CC162A919bdd3F8552D331544629A6BEC1BE";
const researchFundingWallet = hardhatArguments.network === "baseMainnet" ? "0x96f67a852f8d3bc05464c4f91f97aace060e247a" : "0x96f67a852f8d3bc05464c4f91f97aace060e247a";

function generateFrontendAddressesFile(
  usdc: string,
  sci: string,
  admin: string,
  researchFundingWallet: string,
  deployedContracts: DeployedContracts
): void {
  // Filter out undefined values and ensure required values are present
  const contracts = Object.entries(deployedContracts).reduce((acc, [key, value]) => {
    if (value !== undefined) {
      acc[key] = value;
    }
    return acc;
  }, {} as { [key: string]: string | number });

  const fileContent = `
'use server';

const ALCHEMY_KEY = process.env.ALCHEMY_KEY_PROTOCOL ?? '';
const PRIVATE_KEY = process.env.PRIVATE_KEY ?? '';

export async function getRpcUrl() {
  ${
    hardhatArguments.network === "baseMainnet"
      ? "return `https://base-mainnet.g.alchemy.com/v2/${ALCHEMY_KEY}`"
      : "return `https://base-sepolia.g.alchemy.com/v2/${ALCHEMY_KEY}`"
  };
};

export async function getPrivateKey() {
  return PRIVATE_KEY;
};

export async function getNetworkInfo() {
  const rpcUrl = await getRpcUrl();
  return {
    chainId: ${hardhatArguments.network === "baseMainnet" ? 8453 : 84532},
    providerUrl: \`\${rpcUrl}\`,
    explorerLink: '${
      hardhatArguments.network === "baseMainnet"
        ? "https://basescan.org/"
        : "https://sepolia.basescan.org"
    }' ,
    admin: '${admin}',
    researchFundingWallet: '${researchFundingWallet}',
    usdc: '${usdc}',
    sci: '${sci}',
    swapAddress: '0x3Cc223D3A738eA81125689355F8C16A56768dF70',
    don: ${contracts.don ? `'${contracts.don}'` : 'undefined'},
    donation: ${contracts.donation ? `'${contracts.donation}'` : 'undefined'},
    po: ${contracts.po ? `'${contracts.po}'` : 'undefined'},
    poToSciExchange: ${contracts.poToSciExchange ? `'${contracts.poToSciExchange}'` : 'undefined'},
    sciManager: ${contracts.sciManager ? `'${contracts.sciManager}'` : 'undefined'},
    governorOperations: ${contracts.governorOperations ? `'${contracts.governorOperations}'` : 'undefined'},
    governorResearch: ${contracts.governorResearch ? `'${contracts.governorResearch}'` : 'undefined'},
    governorExecutor: ${contracts.governorExecutor ? `'${contracts.governorExecutor}'` : 'undefined'},
    governorGuard: ${contracts.governorGuard ? `'${contracts.governorGuard}'` : 'undefined'},
    transactionResearch: ${contracts.transactionResearch ? `'${contracts.transactionResearch}'` : 'undefined'},
    transactionOperations: ${contracts.transactionOperations ? `'${contracts.transactionOperations}'` : 'undefined'},
    election: ${contracts.election ? `'${contracts.election}'` : 'undefined'},
    impeachment: ${contracts.impeachment ? `'${contracts.impeachment}'` : 'undefined'},
    parameterChange: ${contracts.parameterChange ? `'${contracts.parameterChange}'` : 'undefined'},
    actionFactoryOperations: ${contracts.actionCloneFactoryOperations ? `'${contracts.actionCloneFactoryOperations}'` : 'undefined'},
    actionFactoryResearch: ${contracts.actionCloneFactoryResearch ? `'${contracts.actionCloneFactoryResearch}'` : 'undefined'},
  };
};
`;
  // If the file exists, remove it to replace with the new one
  if (fs.existsSync(frontendAddressesFilePath)) {
    fs.unlinkSync(frontendAddressesFilePath);
    console.log(`Existing file at ${frontendAddressesFilePath} has been deleted.`);
  }

  // Write the new addresses to the file
  fs.writeFileSync(frontendAddressesFilePath, fileContent, "utf8");
  console.log(
    `Governance system addresses have been saved at ${frontendAddressesFilePath}`
  );
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
  const requiredFiles = ['Don.bytecode.json', 'Donation.bytecode.json'];
  
  bytecodeFiles.forEach((file) => {
    const srcPath = path.join(bytecodeOutputDir, file);
    const destPath = path.join(frontendBytecodeDir, file);
    if (fs.lstatSync(srcPath).isFile()) {
      fs.copyFileSync(srcPath, destPath);
      console.log(`Copied bytecode ${file} to frontend directory`);
    }
  });

  // Verify required files were copied
  requiredFiles.forEach(file => {
    const destPath = path.join(frontendBytecodeDir, file);
    if (!fs.existsSync(destPath)) {
      console.error(`⚠️ Warning: Required bytecode file ${file} was not copied to frontend`);
    } else {
      console.log(`✅ Verified ${file} was copied to frontend successfully`);
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

function encodeFunctionData(functionSignature: string, input: any): string {
  const iface = new ethers.utils.Interface([`function ${functionSignature}`]);
  return iface.encodeFunctionData(functionSignature.split("(")[0], [input]);
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
  const outputPath: string = path.join(contractsDir, "DeployedAddresses.sol");

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

  library DeployedAddresses {
  ${Object.entries(filteredContracts)
    .map(([key, value]) => {
      if (!value) {
        console.warn(`Warning: Value for ${key} is undefined`);
        return `// Warning: Value for ${key} was undefined`;
      }
      
      if (key === "providerUrl" || key === "explorerLink") {
        return `string constant ${key} = ${JSON.stringify(value)};`;
      } else if (typeof value === 'string' && ethers.utils.isAddress(value)) {
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
  console.log(`DeployedAddresses.sol has been generated at ${outputPath}`);
};

// Add this function before main()
async function flattenContracts(
  contractNames: string[],
  deploymentVars: {
    uri: string;
    admin: string;
    sci: string;
    usdc: string;
    researchFundingWallet: string;
    signer: string;
  },
  addresses: DeployedContracts
): Promise<void> {
  console.log("\nFlattening contracts for manual verification...");
  
  const flattenedDir = path.join(__dirname, "../flattened");
  if (!fs.existsSync(flattenedDir)) {
    fs.mkdirSync(flattenedDir, { recursive: true });
  }

  // Contract path mapping
  const contractPaths: { [key: string]: string } = {
    "Don": "tokens/Don.sol",
    "Po": "tokens/Po.sol",
    "SciManager": "sciManager/SciManager.sol",
    "Donation": "donating/Donation.sol",
    "PoToSciExchange": "exchange/PoToSciExchange.sol",
    "GovernorOperations": "governance/GovernorOperations.sol",
    "GovernorResearch": "governance/GovernorResearch.sol",
    "GovernorExecutor": "governance/GovernorExecutor.sol",
    "GovernorGuard": "governance/GovernorGuard.sol",
    "Transaction": "executors/Transaction.sol",
    "Election": "executors/Election.sol",
    "Impeachment": "executors/Impeachment.sol",
    "ParameterChange": "executors/ParameterChange.sol",
    "ActionCloneFactoryResearch": "governance/ActionCloneFactoryResearch.sol",
    "ActionCloneFactoryOperations": "governance/ActionCloneFactoryOperations.sol"
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
      const constructorArgs = getConstructorArgs(contractName, deploymentVars, addresses);
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
    uri: string;
    admin: string;
    sci: string;
    usdc: string;
    researchFundingWallet: string;
    signer: string;
  },
  addresses: DeployedContracts
): string | null {
  const args: { [key: string]: any[] } = {
    "Don": [deploymentVars.uri, deploymentVars.admin],
    "Po": [deploymentVars.uri, deploymentVars.admin],
    "SciManager": [deploymentVars.admin, deploymentVars.sci],
    "Donation": [deploymentVars.researchFundingWallet, deploymentVars.admin, deploymentVars.usdc, addresses.don],
    "PoToSciExchange": [deploymentVars.admin, deploymentVars.sci, addresses.po],
    "GovernorOperations": [addresses.sciManager, deploymentVars.admin, addresses.po, deploymentVars.signer],
    "GovernorResearch": [addresses.sciManager, deploymentVars.admin, deploymentVars.researchFundingWallet],
    "GovernorExecutor": [deploymentVars.admin, 3600, addresses.governorOperations, addresses.governorResearch],
    "GovernorGuard": [deploymentVars.admin, addresses.governorOperations, addresses.governorResearch],
    "Transaction": [],
    "Election": [],
    "Impeachment": [],
    "ParameterChange": [],
    "ActionCloneFactoryResearch": [addresses.governorResearch, addresses.transactionResearch],
    "ActionCloneFactoryOperations": [addresses.governorOperations, addresses.transactionOperations, addresses.election, addresses.impeachment, addresses.parameterChange]
  };
  
  return args[contractName]?.join(", ") || null;
}

// Modify the main() function to include flattening at the end
async function main(): Promise<DeployedContracts> {
  const PRIVATE_KEY: string = process.env.DEPLOYER_PRIVATE_KEY || "";
  if (!PRIVATE_KEY)
    throw new Error("⛔️ Private key not detected! Add it to the .env file!");

  const [deployer]: Signer[] = await ethers.getSigners();
  console.log("Deploying contracts with the account:", await deployer.getAddress());
  console.log("Account Balance:", (await deployer.getBalance()).toString());

  if (!hardhatArguments.network) throw new Error("Please pass --network");

  const getRpcUrl = (): string => {
    return hardhatArguments.network === "baseMainnet"
      ? `https://base-mainnet.g.alchemy.com/v2/`
      : `https://base-sepolia.g.alchemy.com/v2/`;
  };

  const rpcUrl: string = getRpcUrl();
  const uri = "https://red-improved-cod-476.mypinata.cloud/ipfs/bafkreibmrcsilc2ojbu636rl2gz2vhlsy7pyi3uvzroccqwc7b3qucszum";
  const signer = "0x690BF2dB31D39EE0a88fcaC89117b66a588E865a";
  const addresses: { [key: string]: string | number | undefined } = {};

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
      addresses[contractKey] = contract.address;

      // Check if we should skip verification
      if (shouldSkipVerification(hardhatArguments.network)) {
        return contract.address;
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
      
      return contract.address;
    } catch (error) {
      console.error(`Error deploying ${contractName}:`, error);
      addresses[contractKey] = undefined;
      return undefined;
    }
  };

  // Deploy all contracts in sequence, ensuring dependencies are available
  try {
    // First wave - No dependencies
    const donAddress = await deployAndVerify("Don", [uri, admin], "don");
    const poAddress = await deployAndVerify("Po", [uri, admin], "po");
    const sciManagerAddress = await deployAndVerify("SciManager", [admin, sci], "sciManager");

    // Second wave - Depends on first wave
    if (donAddress) {
      await deployAndVerify("Donation", [researchFundingWallet, admin, usdc, donAddress], "donation");
    }
    
    if (poAddress) {
      await deployAndVerify("PoToSciExchange", [admin, sci, poAddress], "poToSciExchange");
    }

    if (sciManagerAddress && poAddress) {
      await deployAndVerify("GovernorOperations", [sciManagerAddress, admin, poAddress, signer], "governorOperations");
      await deployAndVerify("GovernorResearch", [sciManagerAddress, admin, researchFundingWallet], "governorResearch");
    }

    // Third wave - Depends on second wave
    if (addresses.governorOperations && addresses.governorResearch) {
      await deployAndVerify("GovernorExecutor", [admin, 3600, addresses.governorOperations, addresses.governorResearch], "governorExecutor");
      await deployAndVerify("GovernorGuard", [admin, addresses.governorOperations, addresses.governorResearch], "governorGuard");
    }

    // Fourth wave - Independent contracts
    const transactionResearchAddress = await deployAndVerify("Transaction", [], "transactionResearch");
    const transactionOperationsAddress = await deployAndVerify("Transaction", [], "transactionOperations");
    const electionAddress = await deployAndVerify("Election", [], "election");
    const impeachmentAddress = await deployAndVerify("Impeachment", [], "impeachment");
    const parameterChangeAddress = await deployAndVerify("ParameterChange", [], "parameterChange");

    // Fifth wave - Depends on fourth wave
    if (addresses.governorResearch && transactionResearchAddress) {
      await deployAndVerify("ActionCloneFactoryResearch", [addresses.governorResearch, transactionResearchAddress], "actionCloneFactoryResearch");
    }

    if (addresses.governorOperations && transactionOperationsAddress && electionAddress && impeachmentAddress && parameterChangeAddress) {
      await deployAndVerify(
        "ActionCloneFactoryOperations",
        [addresses.governorOperations, transactionOperationsAddress, electionAddress, impeachmentAddress, parameterChangeAddress],
        "actionCloneFactoryOperations"
      );
    }
  } catch (error) {
    console.error("Error in deployment sequence:", error);
  }

  // Continue with post-deployment steps, wrapping each in try-catch
  try {
    await generateSolidityAddressFile({
      chainId: hardhatArguments.network === "baseMainnet" ? 8453 : 84532,
      providerUrl: rpcUrl,
      explorerLink:
        hardhatArguments.network === "baseMainnet"
          ? "https://basescan.org"
          : "https://sepolia.basescan.org",
      admin: admin,
      researchFundingWallet: researchFundingWallet,
      usdc: usdc,
      sci: sci,
      don: addresses.don,
      donation: addresses.donation,
      po: addresses.po,
      poToSciExchange: addresses.poToSciExchange,
      sciManager: addresses.sciManager,
      governorOperations: addresses.governorOperations,
      governorResearch: addresses.governorResearch,
      governorExecutor: addresses.governorExecutor,
      governorGuard: addresses.governorGuard,
      actionFactoryResearch: addresses.actionCloneFactoryResearch,
      actionFactoryOperations: addresses.actionCloneFactoryOperations,
      transactionResearch: addresses.transactionResearch,
      transactionOperations: addresses.transactionOperations,
      election: addresses.election,
      impeachment: addresses.impeachment,
      parameterChange: addresses.parameterChange
    });
  } catch (error) {
    console.error("Error generating Solidity address file:", error);
  }

  try {
    setupAbiAndBytecodeDirs();
    extractAbisAndBytecodes(artifactsDir);
    copyAbiFilesToFrontend();
    copyBytecodeFilesToFrontend();
  } catch (error) {
    console.error("Error handling ABI and bytecode files:", error);
  }

  // Create transactions array only with successfully deployed contracts
  const transactions = [];
  
  if (addresses.don && addresses.donation) {
    transactions.push({
      to: addresses.don,
      value: "0",
      data: encodeFunctionData("setDonation(address)", addresses.donation),
    });
  }

  if (addresses.sciManager && addresses.governorExecutor) {
    transactions.push({
      to: addresses.sciManager,
      value: "0",
      data: encodeFunctionData("setGovExec(address)", addresses.governorExecutor),
    });
  }

  if (addresses.governorResearch && addresses.governorExecutor) {
    transactions.push({
      to: addresses.governorResearch,
      value: "0",
      data: encodeFunctionData("setGovExec(address)", addresses.governorExecutor),
    });
  }

  if (addresses.governorOperations && addresses.governorExecutor) {
    transactions.push({
      to: addresses.governorOperations,
      value: "0",
      data: encodeFunctionData("setGovExec(address)", addresses.governorExecutor),
    });
  }

  if (addresses.governorOperations && addresses.governorGuard) {
    transactions.push({
      to: addresses.governorOperations,
      value: "0",
      data: encodeFunctionData("setGovGuard(address)", addresses.governorGuard),
    });
  }

  if (addresses.governorOperations && addresses.actionCloneFactoryOperations) {
    transactions.push({
      to: addresses.governorOperations,
      value: "0",
      data: encodeFunctionData("setFactory(address)", addresses.actionCloneFactoryOperations),
    });
  }

  if (addresses.governorResearch && addresses.actionCloneFactoryResearch) {
    transactions.push({
      to: addresses.governorResearch,
      value: "0",
      data: encodeFunctionData("setFactory(address)", addresses.actionCloneFactoryResearch),
    });
  }

  if (addresses.governorResearch && addresses.governorGuard) {
    transactions.push({
      to: addresses.governorResearch,
      value: "0",
      data: encodeFunctionData("setGovGuard(address)", addresses.governorGuard),
    });
  }

  if (addresses.po && addresses.governorOperations) {
    transactions.push({
      to: addresses.po,
      value: "0",
      data: encodeFunctionData("setGovOps(address)", addresses.governorOperations),
    });
  }

  if (addresses.sciManager && addresses.governorOperations) {
    transactions.push({
      to: addresses.sciManager,
      value: "0",
      data: encodeFunctionData("setGovOps(address)", addresses.governorOperations),
    });
  }

  if (addresses.sciManager && addresses.governorResearch) {
    transactions.push({
      to: addresses.sciManager,
      value: "0",
      data: encodeFunctionData("setGovRes(address)", addresses.governorResearch),
    });
  }

  // Create transaction descriptions for better readability
  const transactionDescriptions = [
    "Set Donation address in DON token",
    "Set GovernorExecutor for SciManager",
    "Set GovernorExecutor for Research",
    "Set GovernorExecutor for GovernorOperations",
    "Set GovernorGuard for GovernorOperations",
    "Set ActionCloneFactory for GovernorOperations",
    "Set ActionCloneFactory for Research",
    "Set GovernorGuard for Research",
    "Set GovernorOperations for PO",
    "Set GovernorOperations for SciManager",
    "Set Research for SciManager"
  ];

  // Create transactions with descriptions for devWalletScripts
  const transactionsWithDescriptions = transactions.map((tx, index) => ({
    ...tx,
    description: transactionDescriptions[index] || `Transaction ${index + 1}`
  }));

  try {
    const safeBatchTransaction = {
      version: "1.0",
      chainId: hardhatArguments.network === "baseMainnet" ? 8453 : 84532,
      createdAt: Date.now(),
      meta: {
        name: "Setting GovernorExecutor, GovernorGuard, and GovernorOperations addresses for SciManager, Research, and PO Contracts",
        description:
          "Batch transaction to set the GovernorExecutor address across SciManager, GovernorOperations, and Research contracts, set the GovernorGuard address for GovernorOperations and Research, and set the GovernorOperations address in the PO and SciManager contracts.",
        txBuilderVersion: "1.17.0",
        createdFromSafeAddress: admin,
        createdFromOwnerAddress: "",
      },
      transactions,
      checksum: ethers.utils.keccak256(
        ethers.utils.toUtf8Bytes(JSON.stringify(transactions))
      ),
    };

    const outputDir = path.join(__dirname, "../scripts/multiSigWalletScripts");
    if (!fs.existsSync(outputDir)) {
      fs.mkdirSync(outputDir, { recursive: true });
      console.log(`Directory created: ${outputDir}`);
    }

    const outputPath = path.join(outputDir, "safeBatchTransaction.json");
    if (fs.existsSync(outputPath)) {
      fs.unlinkSync(outputPath);
      console.log(`Existing file at ${outputPath} has been deleted.`);
    }
    fs.writeFileSync(
      outputPath,
      JSON.stringify(safeBatchTransaction, null, 2),
      "utf8"
    );
    console.log(
      `Batch transaction JSON successfully generated and saved at: ${outputPath}`
    );

    // Update the executeTransactions.js file in devWalletScripts
    const devWalletScriptsDir = path.join(__dirname, "../scripts/devWalletScripts");
    const executeTransactionsPath = path.join(devWalletScriptsDir, "executeTransactions.js");
    
    // Create the executeTransactions.js content
    const executeTransactionsContent = `// Script to execute the same transactions as in safeBatchTransaction.json but using an EOA wallet
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

  // Base Chain (Chain ID: ${hardhatArguments.network === "baseMainnet" ? 8453 : 84532})
  const provider = new ethers.providers.JsonRpcProvider(process.env.RPC_URL || '${
    hardhatArguments.network === "baseMainnet"
      ? "https://base-mainnet.g.alchemy.com/v2/YOUR_API_KEY"
      : "https://base-sepolia.g.alchemy.com/v2/YOUR_API_KEY"
  }');
  const wallet = new ethers.Wallet(PRIVATE_KEY, provider);
  
  console.log(\`Using wallet address: \${wallet.address}\`);
  
  // Transaction data from safeBatchTransaction.json
  const transactions = ${JSON.stringify(transactionsWithDescriptions, null, 2)};

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
        chainId: ${hardhatArguments.network === "baseMainnet" ? 8453 : 84532} // Base Chain
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
  
  console.log('\\nAll transactions executed successfully!');
}

// Execute the script
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });`;

    // Write the executeTransactions.js file
    if (!fs.existsSync(devWalletScriptsDir)) {
      fs.mkdirSync(devWalletScriptsDir, { recursive: true });
      console.log(`Directory created: ${devWalletScriptsDir}`);
    }

    fs.writeFileSync(executeTransactionsPath, executeTransactionsContent, "utf8");
    console.log(`executeTransactions.js has been updated at: ${executeTransactionsPath}`);
  } catch (error) {
    console.error("Error generating transaction files:", error);
  }

  try {
    // Add this at the end of the main function, just before returning addresses
    console.log("\nPreparing flattened contracts for manual verification...");
    await flattenContracts(
      [
        "Don",
        "Po",
        "SciManager",
        "Donation",
        "PoToSciExchange",
        "GovernorOperations",
        "GovernorResearch",
        "GovernorExecutor",
        "GovernorGuard",
        "Transaction",
        "Election",
        "Impeachment",
        "ParameterChange",
        "ActionCloneFactoryResearch",
        "ActionCloneFactoryOperations"
      ],
      { uri, admin, sci, usdc, researchFundingWallet, signer },
      addresses
    );
    console.log("Contract flattening completed!");
  } catch (error) {
    console.error("Error during contract flattening:", error);
  }

  return addresses;
}

main()
  .then((deployedContracts) => {
    try {
      console.log("Deployment completed. Updated Object:", deployedContracts);
      generateFrontendAddressesFile(
        usdc,
        sci,
        admin,
        researchFundingWallet,
        deployedContracts
      );
    } catch (error) {
      console.error("Error generating frontend addresses file:", error);
    }
    process.exit(0);
  })
  .catch((error) => {
    console.error("Fatal error in main execution:", error);
    process.exit(1);
  });
