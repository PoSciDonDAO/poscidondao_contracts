// convertStringToBytes32.ts

import { ethers } from 'ethers';
import * as readline from 'readline';

const rl = readline.createInterface({
  input: process.stdin,
  output: process.stdout
});

const convertToBytes32 = (inputString: string): string => {
  return ethers.utils.formatBytes32String(inputString);
};

rl.question('Enter the string to convert to bytes32: ', (input) => {
  try {
    const bytes32 = convertToBytes32(input);
    console.log(`Bytes32 format: ${bytes32}`);
  } catch (error) {
    console.error('Error converting string to bytes32:', error);
  }
  rl.close();
});
