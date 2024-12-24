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
		"0x9c97e57f315e2a8c04cce048edf55ce910401c08",
		"0x0be1032c92578ab7da645eac2dd1dcdc57b2d46a",
		"0x176e5976360aef0f40a62d194f0ef755180a5e03",
		"0x9f0e612e571b1fbc24a4a101e4a442e994ad278a",
		"0x9a5938703a1ce845d1fbeb7dbfe0a40b0c718e26",
		"0x07889806aa3ccf6fddb662c14da639b8120bba27",
		"0xb4d4b922797a2555ac1fcc2a3c5da92aa1691ad3",
		"0x78b08b4f198f4b78cc93015a7059f7766896761e",
		"0xd32128ed5e21cab1281565b9c16775a8b9bcc12b",
		"0x256ecfb23cf21af9f9e33745c77127892956a687",
		"0x14583be9fb5af19b4ef9dbfaf554e654ff62cd09",
		"0xbd572b08c3e83447ea64fecc08b0d527d44de883",
		"0x05dbd38b147a042fa17f75b4710a4d59452339d4",
		"0x13c1c5d2a573cbac9694a037de9e54e8922f9d01",
		"0x714d33800a45f5173fcb974eb7dedd7b346f6e09",
		"0x0b31d2df84b952cdf4aefb0373d8e65ad5d3d6c9",
		"0x3731d9cc71eaf31ae7071e9adb9f1539156fd391",
		"0x4b1e86ad2be9da1ad0cfd5d0337d34f6aa1f050f",
		"0x1ebae34f4772563a73721a88a98b22ba782d63e4",
		"0x15142bec2e7217fd13ed9b7a3b78d69220c5a513",
		"0xeb05d519bf7e4d2185dd088a9a246cbbef72e287",
		"0xbe6284b74cfb7bcaf93b80b1c23cfa26aa83faa2",
		"0xa3565c3f0c621b794115781ebd0814b27763b226",
		"0x609f92888e3832311b1c57b9cb947e45b4fc7b19",
		"0xeb1ac4ea065cb55944d86ea2a73a37af6c901c09",
		"0xd046ca10c6e60645c119c60571b241336cddd1b2",
		"0xa7c209df59d39bd25122f631e6ec5dfa2c7f5060",
		"0xb5674a21bda3db6b85fbd9103304f800da6dcb18",
		"0x16a0b61132c0be847059b56aab8d106be8fa4ee5",
		"0x2db2771bee9027eb8b4fd76d4ea82a40f47917ba",
		"0x3e865cfb274ec3100e5896faeaa466f7ea55f208",
		"0x8c2bc395cff63454ffc576e37e478f044e2a2b9e",
		"0xab7a4f6425240886e169eac0ae83adfd2641ba32",
		"0xaea5981c8b3d66118523549a9331908136a3e648",
		"0x0f1796c43e536c252b654a787d930673b8a5fd55",
		"0xec45415b0aace443c4a2a82c6b187bb5b342ff3a",
		"0x43b14267650d6de83be401cffa211e6a34b04a0f",
		"0xcec08941dcfcc6df840727f37febaa40017982c0",
		"0x03959b2c4f8e3b80cb8c2126b49fede6d2808b49",
		"0x3ecdcbda0d66d6f39f3243ad7f8068d58909a60a",
		"0x28d5d05379b1262cf72609f9adf45109753dbfc5",
		"0xe86e15e917667b08a5be75aad4b61899c8140c73",
		"0x294238ce0ed339e0b19f8569b78df6c5a207fcb4",
		"0x4685d461fbf836bdb50fcd63a6d277d63ec9cd6b",
		"0xfdf9a119041d11d15bca43ced1976f84f430a410",
		"0x84f396b19090515e7416d340b40572c125365543",
		"0xb207052b1af160b6c8fdfde72e220e8ef1597af3",
		"0xcda631215dad5b697a3f4ee648734c59ddfc065d",
		"0x1473abacf04052741e083e53baa8ecad95510ce3",
		"0xd22d6903c63a288cf37d0a28193d38177b2f95de",
		"0x385842c925d79fb09c9b76daca1b5dea2fc29f12",
		"0xb42a22ec528810ae816482914824e47f4dc3f094",
		"0x45b1ab9b0a1f3458a7f9d26f580e3dc258aeb2e0",
		"0x01c98c8faeef2ea1276bad3ae49d48d4482081c6",
		"0x4b45d650d0a08b4ce6f5c2e3ad6a6cd9ab29213e",
		"0x8e3bad52b9d3109196874a3bd01c39bbbe396e03",
		"0x23208d88ea974cc4aa639e84d2b1074d4fb41ac9",
		"0x9788ec32a839dda17135ebd563cf25d9aabe8e06",
		"0xa16281d33d92cbcb15b9989f4cc2386e28618830",
		"0x145ba0428c33cb6a38687d896e010649beb68630",
		"0x97d3d6f38d58f6d9069c7520828aee85aaeaf405",
		"0xf55cdb4adf43a42ff207e5e0aab975acd9fce3fc",
		"0x8fe48a715ad33690dde7dfab6c4d971c01c6c252",
		"0x19b30a77abcce9d649f2d72a51d5918fbe98b7ff",
		"0x2ea61392df463ee81344b0e7789a6649069c5853",
		"0x50c4fbcde3c4e47f552ec12d7e35b41b14a63d9b",
		"0xaa11b995ffded1982ffe10a59d834c45b547616d",
		"0xfeef239ae6d6361729fcb8b4ea60647344d87fee",
		"0x03b788ba236f975fa58d5c4be6fd5f02bb9221bd",
		"0xb1fab0b2f28462fe70ef64e0ac0f42e3dfa9a830",
		"0x90507f7540761c42194c0428f84cfbaa1b10a38a",
		"0xc9c439529eb8d58b8ac870f6bcc81a3dc4d4fd01",
		"0x0f8a515c02d13ef6e6a9f9d3c9d6802389664906",
		"0x09d01f8597122df72aa7884c109d27eba7a1ec8b",
		"0x6101a6deeeab4fedb8f97938179a0035969517d1",
		"0x46d223b529ec7ad190d2fff26474ddcf007c6cb3",
		"0xcdeaf506ba2eb74a213d9be1e1ed33a11d94573c",
		"0xac33566e539ed8ebe1229fcba93f90e9a7de3a79",
		"0xa338936272d6ff1887df36879e1d88c69a9d9a2f",
		"0x96b1fbaee2f7070d5333399fcec10ddc7ae50246",
		"0xed4e4147df59484d8a226bc3b561d5f21699a372",
		"0x333ded79447c08ff6cd434c1d056bcb7fd3d37cb",
		"0x33c6bf2be86eee3b01a1ff5adfd96d0da7c0fd2b",
		"0xd916c366532773f6979ae8c28709d1c8a97b8c01",
		"0xa52ca61794c1fbfee723b5e31ffd6724c8f88599",
		"0x9887fdc68a73dc59a76de10a062bd5ee49d202eb",
		"0x56ba732a6ae49d86003453823cc89730c2d2ef10",
		"0x2aac14d1e9438d860dbc850af86564ee122835ee",
		"0xd32470811f973c6cdda1753250dd968b9bf70d5c",
		"0xc0b6a0254d5f320e57e65784040f0316c71564ed",
		"0x2fee84edea60a85ec96ab110f021ea923a8c11d4",
		"0x756086bb71dfb11b03ebafc6cea0ce3b44c12e74",
		"0x747fdb8aaea0b35e3dff57e28fb767ad0b14c86e",
		"0x3553f4183782097e20c8ed94ffd4586ce8a9ece9",
		"0x88bd58b6105e74c94d788b32cd1f9f107ae532db",
		"0xcf4b0a55dd83c810b06bd7f5c901b65aa8567514",
		"0x6cb83aac6b7d98d4cb8432cbda9d2fc528effad1",
		"0xf96f91ef6e8151a40a01b48053d9b4f038139496",
		"0x468ee8124cd8591a2e3a5d4c669b7e2ba3306a79",
		"0x7a572cf23161bc118e36a2582e4ea74e5b878311",
		"0x5318d51d29259b7e3d434da845ffa5fa4b696815",
		"0x5e3bd1ce72668d073ba20013b039e25d27e5e6eb",
		"0xb6c3d4aa9bc01a540e939209f41141f5e9d460ed",
		"0x2c839ccf861887cd1de88cf4cda0f566ccc338b9",
		"0x68d2920a8723dfebb0d05762e98048f75a147fee",
		"0xf8f07455bfd03c4c4ffcc9da42e027808b35c2c1",
		"0x8fc23bdf5059df23192f2e0cd65bd8ac20915de8",
		"0x9ad67ef7f59a28cdc76f554d1c8fbe9c41d84360",
		"0xe8cfc64566ab91b21566fd9e5713c25e177f2a0c",
		"0xd72dbe658f087463d80047b18ed7a02c64abe104",
		"0x811ca7a06ff7e73517f0c870630e04b9de17430e",
		"0x5b34ef6898a28eb550710669541941678520afce",
		"0xb101a90f179d8ee815bdb0c8315d4c28f8fa5b99",
		"0x7cd3144ec78dfb72772c571d8d12fc102a7e2697",
		"0x731f6f962b9edbf6921d559d61530ada1fcf03d9",
		"0xb1973ece3f17a24abdfd20dc1b696e59e304798c",
		"0x56b8e0096ed43faf1fe4b97e21726be6505d8262",
		"0x74da8f4b8a459dad4b7327f2efab2516d140a7ab",
		"0xd1461bbe86987f41e204719d6b12b203e5a409d2",
		"0x1e74d5200fea16d8fde2715136194fb56e018275",
		"0x9e36483dfef4b173437512d49c090ae2b3190b85",
		"0x8de44114404da726353f24ff718012d21257f0d8",
		"0x7BB7e70De34008853613f5855DafEFCb178cCa2d",
	];

	const constructorArguments = [admin, sci, voucher, membersWhitelist];

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
  pragma solidity 0.8.28;

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
