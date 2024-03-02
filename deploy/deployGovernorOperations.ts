import { ethers, hardhatArguments, run } from "hardhat";
import { getEnv, sleep } from "./utils";
import dotenv from "dotenv";
dotenv.config();

async function main() {
  console.log(`Running deploy script for the GovernorOperations contract`);
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

  const stakingAddress = "0x7177A5D2Bc6D50FE857B5E797907C45632C7c43c";
  const treasuryWallet = "0x690BF2dB31D39EE0a88fcaC89117b66a588E865a";
  const usdc = "0x578928B093423E9622c7F7e7d741eF9397701930";
  const sciToken = "0xfA5F4cFaBdD43c17e3D8Ca18446602270eC2D215";
  const poToken = "0x8Aed302331bE40532e0DCf780E33b9Bd3668434E";
  const hubAddress = "0x2aa822e264f8cc31a2b9c22f39e5551241e94dfb";

  const constructorArguments = [
		stakingAddress,
		treasuryWallet,
		usdc,
		sciToken,
		poToken,
		hubAddress,
  ];

  const Contract = await ethers.getContractFactory("GovernorOperations");
  // Estimate contract deployment fee
  const estimatedGas = await ethers.provider.estimateGas(
    Contract.getDeployTransaction(...constructorArguments)
  );

  // Fetch current gas price
  const gasPrice = await ethers.provider.getGasPrice();

  // Calculate the estimated deployment cost
  const estimatedCost = estimatedGas.mul(gasPrice);

  console.log(
    `Estimated deployment cost: ${ethers.utils.formatEther(estimatedCost)} MATIC`
  );

  const contract = await Contract.deploy(...constructorArguments);
  console.log("Deployed Contract Address:", contract.address);
  console.log("Verifying contract in 2 minutes...");
  await sleep(120000 * 1);
  await run("verify:verify", {
    address: contract.address,
    constructorArguments: [...constructorArguments],
  });
  console.log(`${contract.address} has been verified`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

