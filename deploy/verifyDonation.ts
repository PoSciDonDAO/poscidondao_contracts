import { ethers, run } from "hardhat";
import dotenv from "dotenv";

dotenv.config();

async function main() {
	console.log(`Running deploy script for the Donation contract`);

	// Load wallet private key from environment file
	const privateKey = process.env.DEPLOYER_PRIVATE_KEY || "";
	if (!privateKey) {
		throw new Error(
			"⛔️ Private key not detected! Add it to the .env file!"
		);
	}

	// Initialize wallet and provider
	const wallet = new ethers.Wallet(privateKey, ethers.provider);

	console.log("Verifying Contract with the account:", wallet.address);

	// Contract constructor arguments
	const donationWallet = "0x17F061d017FA5DF401326f1859779148aaA21831";
	const treasuryWallet = "0x681237e285d8630e992D2DbbDd8F2FAf1435bD36";
	const usdc = "0x235ae97b28466db30469b89a9fe4cff0659f82cb";
	const weth = "0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619";

	// Verification
	try {
		await run("verify:verify", {
			address: "0x578928B093423E9622c7F7e7d741eF9397701930",
			constructorArguments: [donationWallet, treasuryWallet, usdc, weth],
		});
		console.log(
			`0x578928B093423E9622c7F7e7d741eF9397701930 has been verified`
		);
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
