const { ethers } = require("ethers");
const fs = require("fs");
const path = require("path");

async function main() {
  // Hardcoded deployed addresses
  const govExecAddress = '0xf13831A3b24e7886c5D70a47EF8A2DFF483159A1';
  const govGuardAddress = '0x9e55655fB56A4DfDc67B3C8067265F74dd56De9D';

  // Existing contract addresses
  const govOps = "0x87B5DEf0Bc3A7563782b1037A5aB5Fd30F43013F";
  const govRes = "0x8b4757468DE4488C96D30D64d72c432f5Cc48997";
  const sciManager = "0x032746d21e589f9c42b81d3EC77E389dbf4B96b2";
  const admin = "0x96f67a852f8d3bc05464c4f91f97aace060e247a";

  // Create the transactions array
  const transactions = [
    {
      to: govOps,
      value: "0",
      data: new ethers.utils.Interface(["function setGovExec(address)"]).encodeFunctionData("setGovExec", [govExecAddress]),
      description: "Set new GovernorExecutor in GovernorOperations"
    },
    {
      to: govRes,
      value: "0",
      data: new ethers.utils.Interface(["function setGovExec(address)"]).encodeFunctionData("setGovExec", [govExecAddress]),
      description: "Set new GovernorExecutor in GovernorResearch"
    },
    {
      to: sciManager,
      value: "0",
      data: new ethers.utils.Interface(["function setGovExec(address)"]).encodeFunctionData("setGovExec", [govExecAddress]),
      description: "Set new GovernorExecutor in SciManager"
    },
    {
      to: govOps,
      value: "0",
      data: new ethers.utils.Interface(["function setGovGuard(address)"]).encodeFunctionData("setGovGuard", [govGuardAddress]),
      description: "Set new GovernorGuard in GovernorOperations"
    },
    {
      to: govRes,
      value: "0",
      data: new ethers.utils.Interface(["function setGovGuard(address)"]).encodeFunctionData("setGovGuard", [govGuardAddress]),
      description: "Set new GovernorGuard in GovernorResearch"
    }
  ];

  // Create Safe transaction batch
  const safeBatchTransaction = {
    version: "1.0",
    chainId: 8453, // Base Mainnet
    createdAt: Date.now(),
    meta: {
      name: "Update GovernorExecutor and GovernorGuard Addresses",
      description: "Batch transaction to update the GovernorExecutor and GovernorGuard addresses across the system",
      txBuilderVersion: "1.17.0",
      createdFromSafeAddress: admin,
      createdFromOwnerAddress: "",
    },
    transactions,
    checksum: ethers.utils.keccak256(
      ethers.utils.toUtf8Bytes(JSON.stringify(transactions))
    ),
  };

  // Write Safe transaction batch
  fs.writeFileSync(
    path.join(__dirname, "updateGovExecAndGuardBatch.json"),
    JSON.stringify(safeBatchTransaction, null, 2)
  );
  console.log("Safe batch transaction file created successfully!");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  }); 