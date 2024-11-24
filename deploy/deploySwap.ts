import { ethers, hardhatArguments } from "hardhat";
import dotenv from "dotenv";
import fs from "fs";
import path from "path";
dotenv.config();

async function main() {
	console.log(`Running deploy script for the Swap contract`);

	const PRIVATE_KEY = process.env.DEPLOYER_PRIVATE_KEY || "";

	if (!PRIVATE_KEY)
		throw "⛔️ Private key not detected! Add it to the .env file!";

	const [deployer] = await ethers.getSigners();

	console.log("Deploying Contract with the account:", deployer.address);
	console.log("Account Balance:", (await deployer.getBalance()).toString());

	if (!hardhatArguments.network) {
		throw new Error("please pass --network");
	}

	const isMainnet =
		hardhatArguments.network === "baseMainnet";

	const admin = "0x96f67a852f8d3bc05464c4f91f97aace060e247a";
	const voucher = isMainnet
		? "0xc1709720bE448D8c0C829D3Ab1A4D661E94f327a"
		: "0x25Abb0438a8bf5702e0F109036Cec98a27592F85";
	const usdc = isMainnet
		? "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913"
		: "0x08D39BBFc0F63668d539EA8BF469dfdeBAe58246";
	
	const currentEtherPrice = 3400;
	
	const membersWhitelist = [
		"0xcD1BCDB51BcDe6771f26F6D7334BD4382F3becA8",
		"0x2Cd5221188390bc6e3a3BAcF7EbB7BCC0FdFC3Fe",
		"0xEcCF63e6577D8C75184c3Bd368c28e030eFf531A",
		"0x2cAa8A69F17b415B4De7e3bD9878767221791828",
		"0x690BF2dB31D39EE0a88fcaC89117b66a588E865a",
		"0xb101a90f179d8eE815BDb0c8315d4C28f8FA5b99",
		"0xF7dd52707034696eFd21AcbDAbA4e3dE555BD488",
		"0xD784862aaA7848Be9C0dcA50958Da932969ef41d",
		"0xFF77ABCA900514BE62374b3F86bacEa033365088",
		"0xD2f8B7A8BA93eA9e14f7bc421a70118da8508E9b",
		"0xd8C98B84755056d193837a5e5b7814c8f6b10590",
		"0x51d93270eA1aD2ad0506c3BE61523823400E114C",
		"0x8b672551D687256BFaB5e447550200Eb625891De",
		"0x9bd74d27c123ff1ac9fe82132f45662865a51c43",
		"0xe4c4E389ffF80E18C63df4691a16ec575781Ca0A",
		"0x3aBCDd4b604385659E34b186d5c0aDB9FFE0403C",
		"0x74da8f4b8a459dad4b7327f2efab2516d140a7ab",
		"0x2E3fe68Bee7922e94EEfc643b1F04E71C6294E93",
		"0xc3d7F06db7E0863DbBa355BaC003344887EEe455",
		"0x39E39b63ac98b15407aBC057155d0fc296C11FE4",
		"0x7DDAfD8EDEaf1182BBF7983c4D778C046a17D9f1",
		"0x23208D88Ea974cc4AA639E84D2b1074D4fb41ac9",
		"0x62B9c3eDef0aDBE15224c8a3f8824DBDEB334e9f",
		"0xFeEf239AE6D6361729fcB8b4Ea60647344d87FEE",
		"0x256ecFb23cF21af9F9E33745c77127892956a687",
		"0x507b0AB4d904A38Dd8a9852239020A5718157EF6",
		"0xAEa5981C8B3D66118523549a9331908136a3e648",
		"0x82Dd06dDC43A4cC7f4eF68833D026C858524C2a9",
		"0xb42a22ec528810aE816482914824e47F4dc3F094",
		"0xe1966f09BD13e92a5aCb18C486cE4c696347A25c",
		"0x1c033d7cb3f57d6772438f95dF8068080Ef23dc9",
		"0x91fd6Ceb1D67385cAeD16FE0bA06A1ABC5E1312e",
		"0x083BcEEb941941e15a8a2870D5a4922b5f07Cc81",
		"0xe5E3aa6188Bd53Cf05d54bB808c0F69B3E658087",
		"0x1a1c7aB8C4824d4219dc475932b3B8150E04a79C",
	];

	const constructorArguments = [
		admin,
		voucher,
		usdc,
		membersWhitelist,
		currentEtherPrice,
	];

	const Contract = await ethers.getContractFactory("Swap");

	// Estimate contract deployment fee
	const estimatedGas = await ethers.provider.estimateGas(
		Contract.getDeployTransaction(...constructorArguments)
	);

	// Fetch current gas price
	const gasPrice = await ethers.provider.getGasPrice();

	// Calculate the estimated deployment cost
	const estimatedCost = estimatedGas.mul(gasPrice);

	console.log(
		`Estimated deployment cost: ${ethers.utils.formatEther(
			estimatedCost
		)} ETH`
	);

	// Deploy the Swap contract
	const contract = await Contract.deploy(...constructorArguments);
	await contract.deployed();

	console.log("Deployed Swap Contract Address:", contract.address);

	generateSolidityAddressFile({
		swapAddress: contract.address,
	}, voucher);

	generateFrontendAddressesFile(usdc, voucher, admin, contract.address);

	setupAbiAndBytecodeDirs();
	extractAbisAndBytecodes(artifactsDir);
	copyAbiFilesToFrontend();
	copyBytecodeFilesToFrontend();

	console.log(contract.address);
}

// Function to generate the Solidity file containing deployed addresses
function generateSolidityAddressFile(deployedContracts: {
	[key: string]: string;
}, voucher: string): void {
	const outputPath = path.join(
		__dirname,
		"../contracts/DeployedSwapAddress.sol"
	);
	const solidityFileContent = `
  // SPDX-License-Identifier: UNLICENSED
  pragma solidity ^0.8.19;

  library DeployedSwapAddress {
      address constant swap = ${deployedContracts.swapAddress};
	  address constant voucher = ${voucher}; 
  }
  `;

	if (fs.existsSync(outputPath)) {
		fs.unlinkSync(outputPath);
	}
	fs.writeFileSync(outputPath, solidityFileContent);
	console.log(`DeployedSwapAddress.sol has been generated at ${outputPath}`);
}

// Function to generate the frontend address file
function generateFrontendAddressesFile(
	usdc: string,
	voucher: string,
	admin: string,
	swapAddress: string
): void {
	// Define the path to the frontend file
	const frontendDirPath = path.join(
		"/Users/marcohuberts/Library/Mobile Documents/com~apple~CloudDocs/Documents/Blockchain/PoSciDonDAO/dApp/poscidondao_frontend/src/app/utils"
	);
	const frontendAddressesFilePath = path.join(
		frontendDirPath,
		"serverConfig.ts"
	);

	// Check if the directory exists; if not, create it
	if (!fs.existsSync(frontendDirPath)) {
		fs.mkdirSync(frontendDirPath, { recursive: true });
		console.log(`Created missing directory: ${frontendDirPath}`);
	}

	// Define the content of the serverConfig.ts file
	const fileContent = `
'use server';

const ALCHEMY_KEY = process.env.ALCHEMY_KEY ?? '';
const PRIVATE_KEY = process.env.PRIVATE_KEY ?? '';

export const getRpcUrl = () => {
  ${
		hardhatArguments.network === "baseMainnet"
			? "return `https://base-mainnet.g.alchemy.com/v2/${ALCHEMY_KEY}`"
			: "return `https://base-sepolia.g.alchemy.com/v2/${ALCHEMY_KEY}`"
  };
};

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
			? "https://basescan.org"
			: "https://sepolia.basescan.org"
	}',
    admin: '${admin}',
    usdc: '${usdc}',
    voucher: '${voucher}',
    swapAddress: '${swapAddress}',
  };
};
`;

	// If the file exists, remove it to replace with the new one
	if (fs.existsSync(frontendAddressesFilePath)) {
		fs.unlinkSync(frontendAddressesFilePath);
		console.log(
			`Existing file at ${frontendAddressesFilePath} has been deleted.`
		);
	}

	// Write the new addresses to the file
	fs.writeFileSync(frontendAddressesFilePath, fileContent, "utf8");
	console.log(
		`Swap contract addresses have been saved at ${frontendAddressesFilePath}`
	);
}

// Directories for ABI and Bytecode
const artifactsDir = path.join(__dirname, "../artifacts/contracts");
const abiOutputDir = path.join(__dirname, "../abi");
const bytecodeOutputDir = path.join(__dirname, "../abi/bytecode");

// Frontend paths for ABI and bytecode
const frontendAbiDir = path.join(
	"/Users/marcohuberts/Library/Mobile Documents/com~apple~CloudDocs/Documents/Blockchain/PoSciDonDAO/dApp/poscidondao_frontend/src/app/abi"
);
const frontendBytecodeDir = path.join(frontendAbiDir, "bytecode");

// Setup directories for ABI and Bytecode
function setupAbiAndBytecodeDirs() {
	if (fs.existsSync(abiOutputDir)) {
		fs.rmSync(abiOutputDir, { recursive: true });
	}
	fs.mkdirSync(abiOutputDir, { recursive: true });
	fs.mkdirSync(bytecodeOutputDir, { recursive: true });

	if (fs.existsSync(frontendAbiDir)) {
		fs.rmSync(frontendAbiDir, { recursive: true });
	}
	fs.mkdirSync(frontendAbiDir, { recursive: true });
	fs.mkdirSync(frontendBytecodeDir, { recursive: true });
}

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
				fs.writeFileSync(
					abiFilePath,
					JSON.stringify(artifact.abi, null, 2)
				);
				console.log(
					`Extracted ABI for ${contractName} to ${abiFilePath}`
				);
			}
			if (artifact.bytecode) {
				const contractName =
					artifact.contractName || path.basename(file, ".json");
				const bytecodeFileName = `${contractName}.bytecode.json`;
				const bytecodeFilePath = path.join(
					bytecodeOutputDir,
					bytecodeFileName
				);
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

// Copy ABI files to frontend directory
function copyAbiFilesToFrontend() {
	const abiFiles = fs.readdirSync(abiOutputDir).filter((file) => {
		const fullPath = path.join(abiOutputDir, file);
		return fs.lstatSync(fullPath).isFile(); // Ensure it's a file
	});

	abiFiles.forEach((file) => {
		const srcPath = path.join(abiOutputDir, file);
		const destPath = path.join(frontendAbiDir, file);
		fs.copyFileSync(srcPath, destPath);
		console.log(`Copied ABI ${file} to frontend directory`);
	});
}

// Copy bytecode files to frontend directory
function copyBytecodeFilesToFrontend() {
	const bytecodeFiles = fs.readdirSync(bytecodeOutputDir).filter((file) => {
		const fullPath = path.join(bytecodeOutputDir, file);
		return fs.lstatSync(fullPath).isFile(); // Ensure it's a file
	});

	bytecodeFiles.forEach((file) => {
		const srcPath = path.join(bytecodeOutputDir, file);
		const destPath = path.join(frontendBytecodeDir, file);
		fs.copyFileSync(srcPath, destPath);
		console.log(`Copied bytecode ${file} to frontend directory`);
	});
}

main()
	.then(() => process.exit(0))
	.catch((error) => {
		console.error(error);
		process.exit(1);
	});
