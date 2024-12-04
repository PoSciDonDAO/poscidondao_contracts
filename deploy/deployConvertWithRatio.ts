import { ethers, hardhatArguments } from "hardhat";
import dotenv from "dotenv";
import fs from "fs";
import path from "path";
dotenv.config();

async function main() {
	console.log(`Running deploy script for the Convert contract`);

	const PRIVATE_KEY = process.env.DEPLOYER_PRIVATE_KEY || "";

	if (!PRIVATE_KEY)
		throw new Error(
			"⛔️ Private key not detected! Add it to the .env file!"
		);

	const [deployer] = await ethers.getSigners();

	console.log("Deploying Contract with the account:", deployer.address);
	console.log("Account Balance:", (await deployer.getBalance()).toString());

	if (!hardhatArguments.network) {
		throw new Error("please pass --network");
	}
	const isMainnet = hardhatArguments.network === "baseMainnet";
	const admin = "0x96f67a852f8D3Bc05464C4F91F97aACE060e247A";
	const sci = isMainnet
		? "0x25E0A7767d03461EaF88b47cd9853722Fe05DFD3"
		: "0x8cC93105f240B4aBAF472e7cB2DeC836159AA311";
	const voucher = isMainnet
		? "0xc1709720bE448D8c0C829D3Ab1A4D661E94f327a"
		: "0x25Abb0438a8bf5702e0F109036Cec98a27592F85";
	const membersWhitelist = [
		"0x690BF2dB31D39EE0a88fcaC89117b66a588E865a",
		"0xb101a90f179d8eE815BDb0c8315d4C28f8FA5b99",
		"0xF7dd52707034696eFd21AcbDAbA4e3dE555BD488",
		"0xD2f8B7A8BA93eA9e14f7bc421a70118da8508E9b",
		"0xd8C98B84755056d193837a5e5b7814c8f6b10590",
		"0x3aBCDd4b604385659E34b186d5c0aDB9FFE0403C",
		"0x74da8f4b8a459dad4b7327f2efab2516d140a7ab",
		"0x39E39b63ac98b15407aBC057155d0fc296C11FE4",
		"0x23208D88Ea974cc4AA639E84D2b1074D4fb41ac9",
		"0x256ecFb23cF21af9F9E33745c77127892956a687",
		"0x82Dd06dDC43A4cC7f4eF68833D026C858524C2a9",
		"0xb42a22ec528810aE816482914824e47F4dc3F094",
		"0x91fd6Ceb1D67385cAeD16FE0bA06A1ABC5E1312e",
		"0xEcCF63e6577D8C75184c3Bd368c28e030eFf531A",
	];

	const constructorArguments = [
		admin,
		sci,
		voucher,
		membersWhitelist
	];

	const Contract = await ethers.getContractFactory("ConvertWithRatio");

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

	// Deploy the VoucherToTokenConversion contract
	const contract = await Contract.deploy(...constructorArguments);
	await contract.deployed();

	console.log(
		"Deployed ConvertWithLimit Contract Address:",
		contract.address
	);

	generateSolidityAddressFile(
		{
			convert: contract.address,
		},
		voucher,
		sci,
		admin
	);

	generateFrontendAddressesFile(sci, voucher, admin, contract.address);

	// Extract ABIs and bytecode for frontend and backend
	setupAbiAndBytecodeDirs();
	extractAbisAndBytecodes(artifactsDir);
	copyAbiFilesToFrontend();
	copyBytecodeFilesToFrontend();

	console.log(contract.address);
}

// Function to generate the Solidity file containing deployed addresses
function generateSolidityAddressFile(
	deployedContracts: {
		convert: string;
	},
	voucher: string,
	sci: string,
	admin: string
): void {
	const outputPath = path.join(
		__dirname,
		"../contracts/DeployedConversionAddresses.sol"
	);
	const solidityFileContent = `
  // SPDX-License-Identifier: UNLICENSED
  pragma solidity ^0.8.19;

  library DeployedConversionAddresses {
	  address constant admin = ${admin};
      address constant sci = ${sci};
      address constant voucher = ${voucher};
      address constant convert = ${deployedContracts.convert};
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
	sci: string,
	voucher: string,
	admin: string,
	convert: string
): void {
	const frontendDirPath = path.join(
		"/Users/marcohuberts/Library/Mobile Documents/com~apple~CloudDocs/Documents/Blockchain/PoSciDonDAO/dApp/poscidondao_frontend/src/app/utils"
	);
	const frontendAddressesFilePath = path.join(
		frontendDirPath,
		"serverConfig.ts"
	);

	if (!fs.existsSync(frontendDirPath)) {
		fs.mkdirSync(frontendDirPath, { recursive: true });
		console.log(`Created missing directory: ${frontendDirPath}`);
	}

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
			? "https://basescan.org/"
			: "https://sepolia.basescan.org"
	}',
    admin: '${admin}',
    voucher: '${voucher}',
    sci: '${sci}',
    convert: '${convert}'
  };
};
`;

	if (fs.existsSync(frontendAddressesFilePath)) {
		fs.unlinkSync(frontendAddressesFilePath);
		console.log(
			`Existing file at ${frontendAddressesFilePath} has been deleted.`
		);
	}

	fs.writeFileSync(frontendAddressesFilePath, fileContent, "utf8");
	console.log(
		`Swap contract addresses have been saved at ${frontendAddressesFilePath}`
	);
}

const artifactsDir = path.join(__dirname, "../artifacts/contracts");
const abiOutputDir = path.join(__dirname, "../abi");
const bytecodeOutputDir = path.join(__dirname, "../abi/bytecode");

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

function copyAbiFilesToFrontend() {
	const abiFiles = fs.readdirSync(abiOutputDir).filter((file) => {
		const fullPath = path.join(abiOutputDir, file);
		return fs.lstatSync(fullPath).isFile();
	});

	abiFiles.forEach((file) => {
		const srcPath = path.join(abiOutputDir, file);
		const destPath = path.join(frontendAbiDir, file);
		fs.copyFileSync(srcPath, destPath);
		console.log(`Copied ABI ${file} to frontend directory`);
	});
}

function copyBytecodeFilesToFrontend() {
	const bytecodeFiles = fs.readdirSync(bytecodeOutputDir).filter((file) => {
		const fullPath = path.join(bytecodeOutputDir, file);
		return fs.lstatSync(fullPath).isFile();
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
