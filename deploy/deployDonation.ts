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
  console.log(`Running deploy script for the Donation contract`);

  // Initialize the wallet.
  const wallet = new Wallet(PRIVATE_KEY);

  // Create deployer object and load the artifact of the contract you want to deploy.
  const deployer = new Deployer(hre, wallet);
  const artifact = await deployer.loadArtifact("Donation");

  // Estimate contract deployment fee
  const usdc = "0x0faF6df7054946141266420b43783387A78d82A9";
  const donationWallet = "0x690bf2db31d39ee0a88fcac89117b66a588e865a";
  const treasuryWallet = "0x2Cd5221188390bc6e3a3BAcF7EbB7BCC0FdFC3Fe";
  const deploymentFee = await deployer.estimateDeployFee(artifact, [usdc, donationWallet, treasuryWallet]);

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

  const donContract = await deployer.deploy(artifact, [usdc, donationWallet, treasuryWallet]);

  //obtain the Constructor Arguments
  console.log(
    "constructor args:" + donContract.interface.encodeDeploy([usdc, donationWallet, treasuryWallet])
  );

  // Show the contract info.
  const contractAddress = donContract.address;
  console.log(`${artifact.contractName} was deployed to ${contractAddress}`);
  await run("verify:verify", {
    address: contractAddress,
    constructorArguments: [usdc, donationWallet, treasuryWallet],
  });
}
