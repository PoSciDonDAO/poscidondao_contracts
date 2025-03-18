const { ethers } = require('ethers');
const fs = require('fs');

// Contract addresses
const GOVERNOR_OPERATIONS_ADDRESS = '0xEe1C6D7A3Db1e629b605Da94f9BDD6b93d45Ce6b';
const GOVERNOR_RESEARCH_ADDRESS = '0x5a06b21D5AF5DEAfBFCF0Cd528F02DAEE9976aD6';

// Safe multisig address
const SAFE_ADDRESS = '0x96f67a852f8d3bc05464c4f91f97aace060e247a';

// Define governance parameters with ordering to handle dependencies
// IMPORTANT: Order is critical for dependent parameters:
// - voteLockTime must be >= proposalLifetime
// - When increasing proposalLifetime, set voteLockTime first
// - When decreasing voteLockTime, set proposalLifetime first

// Current values from the contract:
// governanceParams.proposalLifetime = 7 days (604800 seconds)
// governanceParams.voteLockTime = 8 days (691200 seconds)

const governorOperationsParamsOrder = [
  // Set non-dependent parameters first
  "opThreshold",
  "quorum",
  "maxVotingStreak",
  "proposeLockTime",
  "voteChangeTime",
  "voteChangeCutOff",
  "votingRightsThreshold",
  "votingDelay",
  "lockedTokenMultiplierBase",
  "maxLockedTokenMultiplier",
  
  // Set dependent parameters in correct order
  // If increasing proposalLifetime: set voteLockTime first
  // If decreasing voteLockTime: set proposalLifetime first
  "voteLockTime",      // Set this first if you're increasing it
  "proposalLifetime"   // Set this first if you're decreasing it
];

const governorResearchParamsOrder = [
  // Set non-dependent parameters first
  "ddThreshold",
  "quorum",
  "proposeLockTime",
  "voteChangeTime",
  "voteChangeCutOff",
  
  // Set dependent parameters in correct order
  "voteLockTime",      // Set this first if you're increasing it
  "proposalLifetime"   // Set this first if you're decreasing it
];

// Parameter values (same as before)
const governorOperationsParams = {
  "opThreshold": "5000000000000000000000",
  "quorum": "367300000000000000000000",
  "maxVotingStreak": "5",
  "proposalLifetime": "604800",
  "voteLockTime": "691200",
  "proposeLockTime": "1209600",
  "voteChangeTime": "86400",
  "voteChangeCutOff": "172800",
  "votingRightsThreshold": "1000000000000000000",
  "votingDelay": "300",
  "lockedTokenMultiplierBase": "2500000000000000000000",
  "maxLockedTokenMultiplier": "50"
};

const governorResearchParams = {
  "ddThreshold": "1000000000000000000000",
  "proposalLifetime": "604800",
  "quorum": "1",
  "voteLockTime": "691200",
  "proposeLockTime": "691200",
  "voteChangeTime": "86400",
  "voteChangeCutOff": "172800"
};

// Function to create transaction data with proper ordering
function createTransactionData() {
  const transactions = [];
  const interface = new ethers.utils.Interface([
    'function setGovernanceParameterByAdmin(bytes32 param, uint256 data)'
  ]);

  // Add GovernorOperations transactions in the specified order
  for (const param of governorOperationsParamsOrder) {
    if (param in governorOperationsParams) {
      const paramBytes32 = ethers.utils.formatBytes32String(param);
      const data = interface.encodeFunctionData('setGovernanceParameterByAdmin', [
        paramBytes32,
        governorOperationsParams[param]
      ]);
      
      transactions.push({
        to: GOVERNOR_OPERATIONS_ADDRESS,
        value: "0",
        data: data
      });
    }
  }

  // Add GovernorResearch transactions in the specified order
  for (const param of governorResearchParamsOrder) {
    if (param in governorResearchParams) {
      const paramBytes32 = ethers.utils.formatBytes32String(param);
      const data = interface.encodeFunctionData('setGovernanceParameterByAdmin', [
        paramBytes32,
        governorResearchParams[param]
      ]);
      
      transactions.push({
        to: GOVERNOR_RESEARCH_ADDRESS,
        value: "0",
        data: data
      });
    }
  }

  return transactions;
}

// Create the full transaction JSON
function createTransactionJSON() {
  const timestamp = Date.now();
  
  const txJSON = {
    version: "1.0",
    chainId: 8453,
    createdAt: timestamp,
    meta: {
      name: "Setting Governance Parameters for GovernorOperations and GovernorResearch",
      description: "Batch transaction to set all governance parameters for both contracts. Order: (1) GovernorOperations non-dependent params, (2) GovernorOperations dependent params (voteLockTime then proposalLifetime to respect voteLockTime >= proposalLifetime), (3) GovernorResearch non-dependent params, (4) GovernorResearch dependent params (same ordering constraint).",
      txBuilderVersion: "1.17.0",
      createdFromSafeAddress: SAFE_ADDRESS,
      createdFromOwnerAddress: ""
    },
    transactions: createTransactionData()
  };

  // Calculate checksum (actual implementation would use keccak256)
  const checksum = ethers.utils.id(JSON.stringify(txJSON.transactions));
  txJSON.checksum = checksum;

  return txJSON;
}

// Generate and save the JSON file
const transactionJSON = createTransactionJSON();
fs.writeFileSync(
  'governance-parameters-transaction.json', 
  JSON.stringify(transactionJSON, null, 2)
);

console.log('Transaction JSON generated successfully!');
console.log('NOTE: This script properly orders parameter updates to respect the constraint that voteLockTime >= proposalLifetime');
console.log('Transaction order:');
console.log('(1) GovernorOperations non-dependent params');
console.log('(2) GovernorOperations dependent params (voteLockTime then proposalLifetime)');
console.log('(3) GovernorResearch non-dependent params');
console.log('(4) GovernorResearch dependent params (same ordering constraint)'); 