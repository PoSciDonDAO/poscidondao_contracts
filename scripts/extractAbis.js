const fs = require("fs");
const path = require("path");

// Path to the artifacts directory
const artifactsDir = path.join(
	"/Users/marcohuberts/Library/Mobile Documents/com~apple~CloudDocs/Documents/Blockchain/PoSciDonDAO/dApp/poscidondao_contracts/artifacts/contracts"
);

// Path to the output ABI directory
const abiOutputDir = path.join(
	"/Users/marcohuberts/Library/Mobile Documents/com~apple~CloudDocs/Documents/Blockchain/PoSciDonDAO/dApp/poscidondao_contracts/abi"
);

// If ABI directory exists, delete it
if (fs.existsSync(abiOutputDir)) {
	fs.rmSync(abiOutputDir, { recursive: true, force: true });
	console.log(`Removed existing directory: ${abiOutputDir}`);
}

// Create the abi directory (and bytecode subdirectory)
fs.mkdirSync(abiOutputDir, { recursive: true });
const bytecodeOutputDir = path.join(abiOutputDir, "bytecode");
fs.mkdirSync(bytecodeOutputDir, { recursive: true });
console.log(`Created directories: ${abiOutputDir} and ${bytecodeOutputDir}`);

// Function to recursively read artifact files and extract ABIs and bytecodes, excluding interfaces and files starting with "I" (except for Impeachment)
function extractAbisAndBytecodes(dir) {
	const files = fs.readdirSync(dir);

	files.forEach((file) => {
		const fullPath = path.join(dir, file);
		const stat = fs.statSync(fullPath);

		// Skip the "interfaces" directory and files starting with "I" (except for Impeachment)
		if (stat.isDirectory()) {
			if (file.toLowerCase() == "interfaces") {
				console.log(`Skipping directory: ${fullPath}`);
				return;
			}
			// Recursively search in other subdirectories
			extractAbisAndBytecodes(fullPath);
		} else if (file.endsWith(".json")) {
			// Skip files starting with "I" unless the file name is "Impeachment"
			if (
				file.startsWith("I") &&
				path.basename(file, ".json") !== "Impeachment"
			) {
				console.log(`Skipping file starting with "I": ${file}`);
				return;
			}

			// Read the artifact JSON file
			const artifact = JSON.parse(fs.readFileSync(fullPath, "utf8"));

			// Extract ABI
			if (artifact.abi) {
				const contractName =
					artifact.contractName || path.basename(file, ".json");
				const abiFileName = `${contractName}.json`;
				const abiFilePath = path.join(abiOutputDir, abiFileName);

				// Write the ABI to the output file
				fs.writeFileSync(
					abiFilePath,
					JSON.stringify(artifact.abi, null, 2)
				);
				console.log(
					`Extracted ABI for ${contractName} to ${abiFilePath}`
				);
			}

			// Extract bytecode
			if (artifact.bytecode) {
				const contractName =
					artifact.contractName || path.basename(file, ".json");
				const bytecodeFileName = `${contractName}.bytecode.json`;
				const bytecodeFilePath = path.join(
					bytecodeOutputDir,
					bytecodeFileName
				);

				// Write the bytecode to the output file
				fs.writeFileSync(
					bytecodeFilePath,
					JSON.stringify({ bytecode: artifact.bytecode }, null, 2)
				);
				console.log(
					`Extracted bytecode for ${contractName} to ${bytecodeFilePath}`
				);
			}
		}
	});
}

// Start the ABI and bytecode extraction
extractAbisAndBytecodes(artifactsDir);

console.log("ABI and bytecode extraction complete.");
