// Script to generate a JSON file for Gnosis Safe multisig transactions
// Updates governor addresses in ActionCloneFactory contracts

const fs = require('fs');
const ethers = require('ethers');

// Contract addresses
const ADDRESSES = {
  // Governance contracts
  governorOperations: '0x87B5DEf0Bc3A7563782b1037A5aB5Fd30F43013F',
  governorResearch: '0x8b4757468DE4488C96D30D64d72c432f5Cc48997',
  
  // Factory contracts
  actionFactoryOperations: '0x5561A0F44D44A8625438385d04C3a63152EBc66d',
  actionFactoryResearch: '0x65d38b7f3d29f697b5DF5f9DCbD22C27302C81F2',
  
  // Admin
  admin: '0x96f67a852f8d3bc05464c4f91f97aace060e247a'
};

// ABI fragments for the functions we need to call
const FACTORY_ABI = [
  // ActionCloneFactoryOperations.setGovOps
  {
    "inputs": [
      { "internalType": "address", "name": "newGovOps", "type": "address" }
    ],
    "name": "setGovOps",
    "outputs": [],
    "stateMutability": "nonpayable",
    "type": "function"
  },
  // ActionCloneFactoryResearch.setGovRes
  {
    "inputs": [
      { "internalType": "address", "name": "newGovRes", "type": "address" }
    ],
    "name": "setGovRes",
    "outputs": [],
    "stateMutability": "nonpayable",
    "type": "function"
  }
];

// Encode function data for transactions
function encodeFunctionData(functionName, ...args) {
  const iface = new ethers.utils.Interface(FACTORY_ABI);
  return iface.encodeFunctionData(functionName, args);
}

// Main function to generate transaction files
function main() {
  console.log("Generating transaction file for updating governor addresses in factory contracts...");

  // Create transactions
  const transactions = [
    {
      to: ADDRESSES.actionFactoryOperations,
      value: "0",
      data: encodeFunctionData("setGovOps", ADDRESSES.governorOperations),
      description: "Set new GovernorOperations address in ActionCloneFactoryOperations"
    },
    {
      to: ADDRESSES.actionFactoryResearch,
      value: "0",
      data: encodeFunctionData("setGovRes", ADDRESSES.governorResearch),
      description: "Set new GovernorResearch address in ActionCloneFactoryResearch"
    }
  ];

  // Create Safe multisig transaction format
  const safeBatchTransaction = {
    version: "1.0",
    chainId: 8453, // Base Mainnet
    createdAt: Date.now(),
    meta: {
      name: "Update Governor Addresses in Factory Contracts",
      description: "Sets new Governor addresses in ActionCloneFactoryOperations and ActionCloneFactoryResearch contracts",
      txBuilderVersion: "1.17.0",
      createdFromSafeAddress: ADDRESSES.admin,
      createdFromOwnerAddress: "",
    },
    transactions: transactions.map(tx => ({
      to: tx.to,
      value: tx.value,
      data: tx.data,
      contractMethod: {
        name: tx.to === ADDRESSES.actionFactoryOperations ? "setGovOps" : "setGovRes"
      },
      contractInputsValues: {
        newGovOps: tx.to === ADDRESSES.actionFactoryOperations ? ADDRESSES.governorOperations : undefined,
        newGovRes: tx.to === ADDRESSES.actionFactoryResearch ? ADDRESSES.governorResearch : undefined
      }
    }))
  };

  // Write the transaction file
  const fileName = "update-governor-addresses.json";
  fs.writeFileSync(fileName, JSON.stringify(safeBatchTransaction, null, 2));
  
  console.log(`Transaction file generated: ${fileName}`);
  console.log("This file can be imported into the Gnosis Safe UI to execute the transactions.");
  
  // Print transaction summary
  console.log("\nTransaction Summary:");
  transactions.forEach((tx, i) => {
    console.log(`${i + 1}. ${tx.description}`);
    console.log(`   To: ${tx.to}`);
    console.log(`   Data: ${tx.data}`);
  });
}

// Run the main function
main(); 