"use client";

import { ethers, run, hardhatArguments } from "hardhat";
import { ContractFactory, Signer } from "ethers";
import dotenv from "dotenv";
import fs from "fs";
import path from "path";
dotenv.config();

interface DeployedContracts {
  [key: string]: string | number | undefined;
}

const usdc = "0x08D39BBFc0F63668d539EA8BF469dfdeBAe58246";
const admin = "0x96f67a852f8d3bc05464c4f91f97aace060e247a";
const sci = "0xff88CC162A919bdd3F8552D331544629A6BEC1BE";
const researchFundingWallet = "0x96f67a852f8d3bc05464c4f91f97aace060e247a";

const frontendAddressesFilePath =
  "/Users/marcohuberts/Library/Mobile Documents/com~apple~CloudDocs/Documents/Blockchain/PoSciDonDAO/dApp/poscidondao_frontend/src/app/utils/serverConfig.ts";

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
const graphApi = process.env.GRAPH_API_KEY ?? '';

export const getRpcUrl = () => {
  ${
    hardhatArguments.network === "baseMainnet"
      ? "return `https://base-mainnet.g.alchemy.com/v2/${ALCHEMY_KEY}`"
      : "return `https://base-sepolia.g.alchemy.com/v2/${ALCHEMY_KEY}`"
  };
};

export const getGraphGovOpsApi = () => {
  return \`\https://gateway.thegraph.com/api/\${graphApi}\/subgraphs/id/4NTVzVzJGVsQhbMUcW7oJJfAwu5yTMPUuXqdMajadY3r\`\;
}

export const getGraphGovResApi = () => {
  return \`\https://gateway.thegraph.com/api/\${graphApi}\/subgraphs/id/T6T8gJDMoivJAEg8u8cJjeYz8RzCynHt5RXaQ54d3KF\`\;
}

export const getPrivateKey = () => {
  return PRIVATE_KEY;
};

export const getNetworkInfo = () => {
  const rpcUrl = getRpcUrl();
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

// Paths for ABI and Bytecode directories
const artifactsDir = path.join(
  "/Users/marcohuberts/Library/Mobile Documents/com~apple~CloudDocs/Documents/Blockchain/PoSciDonDAO/dApp/poscidondao_contracts/artifacts/contracts"
);
const abiOutputDir = path.join(
  "/Users/marcohuberts/Library/Mobile Documents/com~apple~CloudDocs/Documents/Blockchain/PoSciDonDAO/dApp/poscidondao_contracts/abi"
);
const bytecodeOutputDir = path.join(abiOutputDir, "bytecode");

// Frontend paths for ABI and bytecode
const frontendAbiDir = path.join(
  "/Users/marcohuberts/Library/Mobile Documents/com~apple~CloudDocs/Documents/Blockchain/PoSciDonDAO/dApp/poscidondao_frontend/src/app/abi"
);
const frontendBytecodeDir = path.join(frontendAbiDir, "bytecode");

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
  const uri = "https://baseURI.example/";
  const signer = "0x690BF2dB31D39EE0a88fcaC89117b66a588E865a";
  const addresses: { [key: string]: string | number | undefined } = {};

  const deployAndVerify = async (
    contractName: string,
    constructorArgs: any[],
    contractKey: string
  ): Promise<string | undefined> => {
    try {
      const Contract: ContractFactory = await ethers.getContractFactory(contractName);
      const contract = await Contract.deploy(...constructorArgs);
      await contract.deployed();
      console.log(`${contractName} deployed at:`, contract.address);
      addresses[contractKey] = contract.address;
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
      await deployAndVerify("GovernorExecutor", [admin, 600, addresses.governorOperations, addresses.governorResearch], "governorExecutor");
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
  } catch (error) {
    console.error("Error generating safe batch transaction:", error);
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
