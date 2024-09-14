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
  const constructorArguments = [treasuryWallet, sci, usdc];

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
