import { ethers, run } from "hardhat";
import dotenv from "dotenv";

dotenv.config();

async function main() {
	console.log(`Running deploy script for the Donation contract`);

	const privateKey = process.env.DEPLOYER_PRIVATE_KEY || "";
	if (!privateKey) {
		throw new Error(
			"⛔️ Private key not detected! Add it to the .env file!"
		);
	}

	const wallet = new ethers.Wallet(privateKey, ethers.provider);
	console.log("Verifying Contract with the account:", wallet.address);

	const admin = "0x96f67a852f8d3bc05464c4f91f97aace060e247a";
	const initialMintAmount = 18910000;

  const constructorArguments = [admin, initialMintAmount];
	console.log("Constructor Arguments:", { admin, initialMintAmount });

	try {
		await run("verify:verify", {
			address: "0xc1709720bE448D8c0C829D3Ab1A4D661E94f327a",
			constructorArguments: [...constructorArguments],
			contract: "contracts/tokens/Voucher.sol:Voucher",
		});
		console.log("Verification successful!");
	} catch (error) {
		console.error("Verification failed:", error);
	}
}

main()
	.then(() => process.exit(0))
	.catch((error) => {
		console.error(error);
		process.exit(1);
	});
