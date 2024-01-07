# PoSciDonDAO Protocol

## Overview
PoSciDonDAO is a Decentralized Autonomous Organization (DAO) dedicated to streamlining and democratizing the funding and management of personalized medicine research. Utilizing the advanced zkSync Era blockchain, PoSciDonDAO implements a suite of smart contracts designed to facilitate transparent, democratic, and efficient governance of DAO operations and funding of personalized medicine research.

## Contracts in the Repository
- **GovernorOperations.sol**: Manages operational aspects of the DAO, including administrative and financial proposals.
- **GovernorResearch.sol**: Focuses on scientific research proposals, particularly in personalized medicine.
- **Staking.sol**: Handles the staking of tokens necessary for participation in governance activities.
- **Participation.sol**: An ERC1155 token contract representing active engagement in DAO governance.
- **Sci.sol**: An ERC20 token contract serving as the primary utility token within the ecosystem.

## Features
- **Governance Proposals**: Create, vote, and manage proposals for both operational and research aspects of the DAO.
- **Token Staking**: Participate in governance by staking Sci tokens.
- **Token Management**: Utilize Participation and Sci tokens for various governance and operational activities.

## Prerequisites
- Node.js
- npm or yarn
- Foundry or Hardhat
- MetaMask or any Web3 wallet

## Installation
1. Clone the repository: ```git clone https://github.com/PoSciDonDAO/poscidon_contracts.git```
2. Navigate to the cloned directory: ```cd poscidon_contracts```
3. Install dependencies: ```npm install```

## Testing
The PoSciDonDAO smart contracts can be tested using Foundry and Hardhat, which are modern development tools for Ethereum.

### Testing with Foundry
1. **Install Foundry**:
```
curl -L https://foundry.paradigm.xyz | bash
foundryup
```
2. **Compile Contracts with Forge**: ```forge build```
3. **Run Tests**: ```forge test```

### Testing with Hardhat
1. Install Hardhat: ```npm install --save-dev hardhat```
2. Setting Up Hardhat Project: ```npx hardhat```
3. Compile Contracts: ```npx hardhat compile```
4. Run Tests: ```npx hardhat test```



