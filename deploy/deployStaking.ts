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
  console.log(`Running deploy script for the Staking contract`);

  // Initialize the wallet.
  const wallet = new Wallet(PRIVATE_KEY);

  // Create deployer object and load the artifact of the contract you want to deploy.
  const deployer = new Deployer(hre, wallet);
  const artifact = await deployer.loadArtifact("Staking");

  // Estimate contract deployment fee
  const donToken = "0xe47c408E9BEDAe9e4F567767Bd27ed6B6A81b1ff";
  const daoAddress = "0x690BF2dB31D39EE0a88fcaC89117b66a588E865a";
  const deploymentFee = await deployer.estimateDeployFee(artifact, [donToken, daoAddress]);

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

  const govResContract = await deployer.deploy(artifact, [donToken, daoAddress]);

  //obtain the Constructor Arguments
  console.log(
    "constructor args:" + govResContract.interface.encodeDeploy([donToken, daoAddress])
  );

  // Show the contract info.
  const contractAddress = govResContract.address;
  console.log(`${artifact.contractName} was deployed to ${contractAddress}`);
  await run("verify:verify", {
    address: contractAddress,
    constructorArguments: [donToken, daoAddress],
  });
}
