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

// Create the abi directory if it doesn't exist
if (!fs.existsSync(abiOutputDir)) {
	fs.mkdirSync(abiOutputDir, { recursive: true });
	console.log(`Created directory: ${abiOutputDir}`);
}

// Function to recursively read artifact files and extract ABIs, excluding interfaces and files starting with "I" (except for Impeachment)
function extractAbis(dir) {
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
			extractAbis(fullPath);
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

			// Check if the artifact has an ABI
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
		}
	});
}

// Start the ABI extraction
extractAbis(artifactsDir);

console.log("ABI extraction complete.");
