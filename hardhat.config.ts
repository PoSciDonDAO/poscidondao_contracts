
import "@matterlabs/hardhat-zksync-verify";
import "@matterlabs/hardhat-zksync-solc";
import "@matterlabs/hardhat-zksync-deploy";

module.exports = {
  zksolc: {
      version: "1.3.11",
      compilerSource: "binary",
      settings: {
        //compilerPath: "zksolc",  // optional. Ignored for compilerSource "docker". Can be used if compiler is located in a specific folder
        libraries:{}, // optional. References to non-inlinable libraries
        isSystem: false, // optional.  Enables Yul instructions available only for zkSync system contracts and libraries
        forceEvmla: false, // optional. Falls back to EVM legacy assembly if there is a bug with Yul
        optimizer: {
          enabled: true, // optional. True by default
          mode: '3' // optional. 3 by default, z to optimize bytecode size
        } 
      }
  },
  defaultNetwork: "zkTestnet",
  networks: {
    goerli: {
      url: `https://goerli.infura.io/v3/${process.env.INFURA_KEY}`, // The Ethereum Web3 RPC URL (optional).
      zksync: false, // Set to false to target other networks.
    },
    zkTestnet: {
      url: "https://zksync2-testnet.zksync.dev", // The testnet RPC URL of zkSync Era network.
      ethNetwork: "goerli", // The Ethereum Web3 RPC URL, or the identifier of the network (e.g. `mainnet` or `goerli`)
    zksync: true,
    verifyURL: 'https://zksync2-testnet-explorer.zksync.dev/contract_verification'
    },
  },
  // defaultNetwork: "zkTestnet", // optional (if not set, use '--network zkTestnet')
  solidity: {
      version: "0.8.20",
  },
  etherscan: {
    apiKey: {
        mainnet: process.env.ETHERSCAN_API_KEY,
        goerli: process.env.ETHERSCAN_API_KEY,
    }    
  },
}

