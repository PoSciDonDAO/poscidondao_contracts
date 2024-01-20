import { ethers, hardhatArguments, run } from "hardhat";
import { getEnv, sleep } from "./utils";
import dotenv from "dotenv";
dotenv.config();

async function main() {
  console.log(`Running deploy script for the Staking contract`);
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

  const treasuryWallet = "0x690BF2dB31D39EE0a88fcaC89117b66a588E865a";
  const sciToken = "0xb28204EbF14f5B50eA04e925788a22aca85dC261";

  const constructorArguments = [treasuryWallet, sciToken];

  const Contract = await ethers.getContractFactory("Staking");
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