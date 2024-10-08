import { ethers, hardhatArguments, run } from "hardhat";
import { getEnv, sleep } from "./utils";
import dotenv from "dotenv";
dotenv.config();

async function main() {
	console.log(`Running deploy script for the Swap contract`);
	// load wallet private key from env file
	const PRIVATE_KEY = process.env.DEPLOYER_PRIVATE_KEY || "";

	if (!PRIVATE_KEY)
		throw "⛔️ Private key not detected! Add it to the .env file!";

	const [deployer] = await ethers.getSigners();

	console.log("Deploying Contract with the account:", deployer.address);
	console.log("Account Balance:", (await deployer.getBalance()).toString());

	if (!hardhatArguments.network) {
		throw new Error("please pass --network");
	}

	const treasuryWallet = "0x96f67a852f8d3bc05464c4f91f97aace060e247a";
	const sci = "0x8cC93105f240B4aBAF472e7cB2DeC836159AA311";
	const usdc = "0x08D39BBFc0F63668d539EA8BF469dfdeBAe58246";
	const membersWhitelist = [
		"0xb101a90f179d8eE815BDb0c8315d4C28f8FA5b99",
		"0xF7dd52707034696eFd21AcbDAbA4e3dE555BD488",
		"0xD784862aaA7848Be9C0dcA50958Da932969ef41d",
		"0xFF77ABCA900514BE62374b3F86bacEa033365088",
		"0xD2f8B7A8BA93eA9e14f7bc421a70118da8508E9b",
		"0xd8C98B84755056d193837a5e5b7814c8f6b10590",
		"0x51d93270eA1aD2ad0506c3BE61523823400E114C",
		"0x8b672551D687256BFaB5e447550200Eb625891De",
		"0x9bd74d27c123ff1ac9fe82132f45662865a51c43",
		"0x0F22D9e9421C02E60fFF8823e3d0Ccc4780F5750",
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
		"0x1a1c7aB8C4824d4219dc475932b3B8150E04a79C", //nft scouser
  ];
  
	const constructorArguments = [treasuryWallet, sci, usdc, membersWhitelist];

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

	const contract = await Contract.deploy(...constructorArguments);
	console.log("Deployed Contract Address:", contract.address);
	// console.log("Verifying contract in 2 minutes...");
	// await sleep(120000 * 1);
	// await run("verify:verify", {
	//   address: contract.address,
	//   constructorArguments: [...constructorArguments],
	// });
	// console.log(`${contract.address} has been verified`);
}

main()
	.then(() => process.exit(0))
	.catch((error) => {
		console.error(error);
		process.exit(1);
	});
