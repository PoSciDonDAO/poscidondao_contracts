import { ethers, hardhatArguments } from "hardhat";
import dotenv from "dotenv";
import fs from "fs";
import path from "path";
dotenv.config();

async function main() {
	console.log(
		`Running deploy script for the VoucherToTokenConversion contract`
	);

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

    const admin = "0x96f67a852f8d3bc05464c4f91f97aace060e247a";
    const usdc = "0x08D39BBFc0F63668d539EA8BF469dfdeBAe58246";
	const sci = "0x8cC93105f240B4aBAF472e7cB2DeC836159AA311";
    const voucherSci = "0x4DF145c2923fa6B2a6841DeF6Ee5ACa033C7b1A2";
    const swapAddress = "0x07cBe6be3F045A51048B0C30f607A2F80352aeBa";
	const membersWhitelist: string[] = [
		"0x690BF2dB31D39EE0a88fcaC89117b66a588E865a",
	];

	const constructorArguments = [admin, sci, voucherSci, membersWhitelist];

	const Contract = await ethers.getContractFactory(
		"VoucherToSciConversion"
	);

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
		"Deployed VoucherToTokenConversion Contract Address:",
		contract.address
	);

	// Writing the deployed address into a Solidity file
	generateSolidityAddressFile({
		voucherToSciConversionAddress: contract.address,
	}, swapAddress, voucherSci, sci );


    generateFrontendAddressesFile(
        usdc,
		sci,
		voucherSci,
		admin,
		swapAddress,
		contract.address
	);

	// Extract ABIs and bytecode for frontend and backend
	setupAbiAndBytecodeDirs();
	extractAbisAndBytecodes(artifactsDir);
	copyAbiFilesToFrontend();
	copyBytecodeFilesToFrontend();

	console.log(contract.address);
}

// Function to generate the Solidity file containing deployed addresses
function generateSolidityAddressFile(deployedContracts: {
	voucherToSciConversionAddress: string;
}, swapAddress: string, voucher: string, sci: string): void {
	const outputPath = path.join(
		__dirname,
		"../contracts/DeployedPresaleAddresses.sol"
	);
	const solidityFileContent = `
  // SPDX-License-Identifier: UNLICENSED
  pragma solidity ^0.8.19;

  library DeployedPresaleAddresses {
      address constant sci = ${sci};
      address constant voucher = ${voucher};
      address constant swap = ${swapAddress};
      address constant voucherToSciConversion = ${deployedContracts.voucherToSciConversionAddress};
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
	sci: string,
	voucherSci: string,
	admin: string,
	swapAddress: string,
	voucherToSciConversionAddress: string
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

const ALCHEMY_KEY = process.env.NEXT_PUBLIC_ALCHEMY_KEY ?? '';
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
    usdc: '${usdc}',
    voucherSci: '${voucherSci}',
    sci: '${sci}',
    swapAddress: '${swapAddress}',
    voucherToSciConversionAddress: '${voucherToSciConversionAddress}'
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
