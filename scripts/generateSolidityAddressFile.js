const fs = require("fs");
const path = require("path");
const { ethers } = require("ethers");

function generateSolidityAddressFile() {
	const deployedContracts = require("./deployedContracts.json");
	const contractsDir = path.join(__dirname, "..", "contracts");
	const outputPath = path.join(contractsDir, "DeployedAddresses.sol");

	// Ensure the contracts directory exists
	if (!fs.existsSync(contractsDir)) {
		fs.mkdirSync(contractsDir, { recursive: true });
	}

	const solidityFileContent = `
  // SPDX-License-Identifier: UNLICENSED
  pragma solidity ^0.8.13;

  library DeployedAddresses {
      ${Object.entries(deployedContracts)
			.map(([key, value]) => {
				if (key === "providerUrl" || key === "explorerLink") {
					return `string constant ${key} = ${JSON.stringify(value)};`;
				} else if (ethers.utils.isAddress(value)) {
					// Apply checksumming to addresses
					const checksummedAddress = ethers.utils.getAddress(value);
					return `address constant ${key} = ${checksummedAddress};`;
				} else {
					return `${
						typeof value === "number" ? "uint" : "address"
					} constant ${key} = ${value};`;
				}
			})
			.join("\n")}
  }
  `;

	fs.writeFileSync(outputPath, solidityFileContent);
	console.log(`DeployedAddresses.sol has been generated at ${outputPath}`);
}

generateSolidityAddressFile();
