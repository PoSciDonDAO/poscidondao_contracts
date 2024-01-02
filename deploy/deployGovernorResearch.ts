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
  const stakingAddress = "0xc7d8Aa2683C39Fb81E9766e6810A6e8b8EBeD795";
  const treasuryWallet = "0x690BF2dB31D39EE0a88fcaC89117b66a588E865a";
  const donationWallet = "0x2Cd5221188390bc6e3a3BAcF7EbB7BCC0FdFC3Fe";
  const usdc = "0x07659EfbcB9C3D82C2B54Bf80d95cB870A612744";
  const sciToken = "0x937F6B427a687b91977Fe09b931e202D995d37B7";

  const deploymentFee = await deployer.estimateDeployFee(artifact, [stakingAddress, treasuryWallet, donationWallet, usdc, sciToken]);

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

  const govContract = await deployer.deploy(artifact, [stakingAddress, treasuryWallet, donationWallet, usdc, sciToken]);

  //obtain the Constructor Arguments
  console.log(
    "constructor args:" + govContract.interface.encodeDeploy([stakingAddress, treasuryWallet, donationWallet, usdc, sciToken])
  );

  // Show the contract info.
  const contractAddress = govContract.address;
  console.log(`${artifact.contractName} was deployed to ${contractAddress}`);
  await run("verify:verify", {
    address: contractAddress,
    constructorArguments: [stakingAddress, treasuryWallet, donationWallet, usdc, sciToken],
  });
}
