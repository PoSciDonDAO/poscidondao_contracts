const { ethers } = require('ethers');
const fs = require('fs');
const path = require('path');

// Contract address
const GOVERNOR_OPERATIONS_ADDRESS = '0xEe1C6D7A3Db1e629b605Da94f9BDD6b93d45Ce6b';

// Safe multisig address (using the same one from the reference script)
const SAFE_ADDRESS = '0x96f67a852f8d3bc05464c4f91f97aace060e247a';

// Parameter value - 6% of 3.284 million total supply
const QUORUM = ethers.utils.parseEther('200000'); // 200,000e18

// Function to create transaction data
function createTransactionData() {
    const interface = new ethers.utils.Interface([
        'function setGovernanceParameterByAdmin(bytes32 param, uint256 data)'
    ]);

    const paramBytes32 = ethers.utils.formatBytes32String('quorum');
    const data = interface.encodeFunctionData('setGovernanceParameterByAdmin', [
        paramBytes32,
        QUORUM
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
            name: "Setting quorum Parameter for GovernorOperations",
            description: "Transaction to set the quorum parameter to 567,300 SCI tokens (3% of total supply).",
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
const outputPath = path.join(__dirname, 'quorum-parameter-transaction.json');
fs.writeFileSync(
    outputPath, 
    JSON.stringify(transactionJSON, null, 2)
);

console.log('Transaction JSON generated successfully!');
console.log(`File saved to: ${outputPath}`);
console.log('Parameter: quorum');
console.log('New Value: 200,000 SCI tokens (6% of circulating supply)'); 