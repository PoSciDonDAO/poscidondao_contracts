import { ethers, hardhatArguments, run } from "hardhat";
import { ContractFactory, Signer } from "ethers";
import dotenv from "dotenv";
import fs from "fs";
import path from "path";
import { sleep, shouldSkipVerification } from "./utils";
dotenv.config();

async function main() {
  console.log(`Running deploy script for GovernorExecutor and GovernorGuard contracts`);
  
  const PRIVATE_KEY = process.env.DEPLOYER_PRIVATE_KEY || "";
  if (!PRIVATE_KEY) {
    throw new Error("⛔️ Private key not detected! Add it to the .env file!");
  }

  const [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with the account:", await deployer.getAddress());
  console.log("Account Balance:", (await deployer.getBalance()).toString());

  if (!hardhatArguments.network) throw new Error("Please pass --network");

  // Constants from existing deployment
  const admin = "0x96f67a852f8d3bc05464c4f91f97aace060e247a";
  const govOps = "0x87B5DEf0Bc3A7563782b1037A5aB5Fd30F43013F";
  const govRes = "0x8b4757468DE4488C96D30D64d72c432f5Cc48997";
  const delay = 259200; // 3 days in seconds

  // Deploy GovernorExecutor
  const GovExec = await ethers.getContractFactory("GovernorExecutor");
  console.log("Deploying GovernorExecutor...");
  const govExec = await GovExec.deploy(admin, delay, govOps, govRes);
  await govExec.deployed();
  console.log("GovernorExecutor deployed to:", govExec.address);

  // Deploy GovernorGuard
  const GovGuard = await ethers.getContractFactory("GovernorGuard");
  console.log("Deploying GovernorGuard...");
  const govGuard = await GovGuard.deploy(admin, govOps, govRes);
  await govGuard.deployed();
  console.log("GovernorGuard deployed to:", govGuard.address);

  // Verify contracts if not on testnet
  if (!shouldSkipVerification(hardhatArguments.network)) {
    console.log("Waiting before verification...");
    await sleep(60000);

    try {
      await run("verify:verify", {
        address: govExec.address,
        constructorArguments: [admin, delay, govOps, govRes],
      });
      console.log("GovernorExecutor verified successfully");
    } catch (error) {
      console.error("Error verifying GovernorExecutor:", error);
    }

    try {
      await run("verify:verify", {
        address: govGuard.address,
        constructorArguments: [admin, govOps, govRes],
      });
      console.log("GovernorGuard verified successfully");
    } catch (error) {
      console.error("Error verifying GovernorGuard:", error);
    }
  }

  return {
    governorExecutor: govExec.address,
    governorGuard: govGuard.address,
  };
}

main()
  .then((addresses) => {
    console.log("Deployment completed. Addresses:", addresses);
    process.exit(0);
  })
  .catch((error) => {
    console.error(error);
    process.exit(1);
  }); 