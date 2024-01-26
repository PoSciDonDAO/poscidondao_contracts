"use strict";
// convertStringToBytes32.ts
Object.defineProperty(exports, "__esModule", { value: true });
var ethers_1 = require("ethers");
var readline = require("readline");
var rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout
});
var convertToBytes32 = function (inputString) {
    return ethers_1.ethers.utils.formatBytes32String(inputString);
};
rl.question('Enter the string to convert to bytes32: ', function (input) {
    try {
        var bytes32 = convertToBytes32(input);
        console.log("Bytes32 format: ".concat(bytes32));
    }
    catch (error) {
        console.error('Error converting string to bytes32:', error);
    }
    rl.close();
});
