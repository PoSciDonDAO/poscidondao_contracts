import { Wallet, utils } from "zksync-web3";
import * as ethers from "ethers";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { Deployer } from "@matterlabs/hardhat-zksync-deploy";
import { run } from "hardhat";

// load env file
import dotenv from "dotenv";
dotenv.config();

// load wallet private key from env file
const PRIVATE_KEY = process.env.WALLET_PRIVATE_KEY || "";

if (!PRIVATE_KEY)
  throw "⛔️ Private key not detected! Add it to the .env file!";

// An example of a deploy script that will deploy and call a simple contract.
export default async function (hre: HardhatRuntimeEnvironment) {
  console.log(`Running deploy script for the GovernorResearch contract`);

  // Initialize the wallet.
  const wallet = new Wallet(PRIVATE_KEY);

  // Create deployer object and load the artifact of the contract you want to deploy.
  const deployer = new Deployer(hre, wallet);
  const artifact = await deployer.loadArtifact("GovernorResearch");

  // Estimate contract deployment fee
  const stakingAddress = "0xF6e2d4A4Bb1FD30358023604E931A1ac918C51cD";
  const treasuryWallet = "0x2Cd5221188390bc6e3a3BAcF7EbB7BCC0FdFC3Fe";
  const usdc = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48";

  const deploymentFee = await deployer.estimateDeployFee(artifact, [stakingAddress, treasuryWallet, usdc]);

  // ⚠️ OPTIONAL: You can skip this block if your account already has funds in L2
  // const depositHandle = await deployer.zkWallet.deposit({
  //   to: deployer.zkWallet.address,
  //   token: utils.ETH_ADDRESS,
  //   amount: deploymentFee.mul(2),
  // });
  // // Wait until the deposit is processed on zkSync
  // await depositHandle.wait();

  // Deploy this contract. The returned object will be of a `Contract` type, similarly to ones in `ethers`.
  // `greeting` is an argument for contract constructor.
  const parsedFee = ethers.utils.formatEther(deploymentFee.toString());
  console.log(`The deployment is estimated to cost ${parsedFee} ETH`);

  const govResContract = await deployer.deploy(artifact, [stakingAddress, treasuryWallet, usdc]);

  //obtain the Constructor Arguments
  console.log(
    "constructor args:" + govResContract.interface.encodeDeploy([stakingAddress, treasuryWallet, usdc])
  );

  // Show the contract info.
  const contractAddress = govResContract.address;
  console.log(`${artifact.contractName} was deployed to ${contractAddress}`);
  await run("verify:verify", {
    address: contractAddress,
    constructorArguments: [stakingAddress, treasuryWallet, usdc],
  });
}
