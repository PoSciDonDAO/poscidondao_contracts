const { ethers } = require('ethers');
const fs = require('fs');
const path = require('path');

// Contract address
const GOVERNOR_OPERATIONS_ADDRESS = '0xEe1C6D7A3Db1e629b605Da94f9BDD6b93d45Ce6b';

// Safe multisig address (using the same one from the reference script)
const SAFE_ADDRESS = '0x96f67a852f8d3bc05464c4f91f97aace060e247a';

// Parameter value
const MAX_LOCKED_TOKEN_MULTIPLIER = 30; // Assuming we want to set it to 30

// Function to create transaction data
function createTransactionData() {
    const interface = new ethers.utils.Interface([
        'function setGovernanceParameterByAdmin(bytes32 param, uint256 data)'
    ]);

    const paramBytes32 = ethers.utils.formatBytes32String('maxLockedTokenMultiplier');
    const data = interface.encodeFunctionData('setGovernanceParameterByAdmin', [
        paramBytes32,
        MAX_LOCKED_TOKEN_MULTIPLIER
    ]);
    
    return [{
        to: GOVERNOR_OPERATIONS_ADDRESS,
        value: "0",
        data: data
    }];
}

// Create the full transaction JSON
function createTransactionJSON() {
    const timestamp = Date.now();
    
    const txJSON = {
        version: "1.0",
        chainId: 8453,
        createdAt: timestamp,
        meta: {
            name: "Setting maxLockedTokenMultiplier Parameter for GovernorOperations",
            description: "Transaction to set the maxLockedTokenMultiplier parameter to 100.",
            txBuilderVersion: "1.17.0",
            createdFromSafeAddress: SAFE_ADDRESS,
            createdFromOwnerAddress: ""
        },
        transactions: createTransactionData()
    };

    // Calculate checksum
    const checksum = ethers.utils.id(JSON.stringify(txJSON.transactions));
    txJSON.checksum = checksum;

    return txJSON;
}

// Generate and save the JSON file
const transactionJSON = createTransactionJSON();
const outputPath = path.join(__dirname, 'maxLockedTokenMultiplier-parameter-transaction.json');
fs.writeFileSync(
    outputPath, 
    JSON.stringify(transactionJSON, null, 2)
);

console.log('Transaction JSON generated successfully!');
console.log(`File saved to: ${outputPath}`);
console.log('Parameter: maxLockedTokenMultiplier');
console.log(`New Value: ${MAX_LOCKED_TOKEN_MULTIPLIER}`); 