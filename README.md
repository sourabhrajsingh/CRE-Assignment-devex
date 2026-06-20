# CRE-Assignment-devex

A complete project combining a **Chainlink CRE workflow** with a **Foundry-based smart contract** that receives and stores price data on-chain.

The CRE workflow listens for HTTP triggers, fetches data, and writes the result to a `PriceSnapshot` contract on Ethereum Sepolia using the EVM Write capability.


## Features

- **CRE Workflow**: HTTP-triggered workflow that fetches data and writes to blockchain
- **Secure On-chain Consumer**: Uses `ReceiverTemplate` for verified report delivery
- **Price Storage**: Stores latest token prices with block number and timestamp
- **Full Testing**: Comprehensive Foundry tests including forwarder validation
- **Easy Deployment**: Script for deploying the contract
- **Easy Interaction**:Foundry CLI - cast 

## Prerequisites

- [Foundry](https://book.getfoundry.sh/)
- [Bun](https://bun.sh/) or Node.js
- Chainlink CRE CLI (`cre`)
- Sepolia ETH + RPC URL

## Getting Started

### 1. Clone & Install Dependencies

```
git clone https://github.com/sourabhrajsingh/CRE-Assignment-devex.git
cd CRE-Assignment-devex

# Install Foundry dependencies
forge install
forge install OpenZeppelin/openzeppelin-contracts
```
### 2. Environment Setup 
#### create a `.env` file 

```
cd CRE-Assignment-devex
cp .env.example .env
```
#### Add the following variables

```
PRIVATE_KEY=0xYOUR_PRIVATE_KEY
SEPOLIA_RPC_URL=https://eth-sepolia.g.alchemy.com/v2/your_api_key
FORWARDER_ADDRESS=0xCRE_SEPOLIA_FORWARDER_ADDRESS
```
#### Run Tests

```
forge test PriceSnapshot.t.sol -vvv
```
### 3. Deploy the Smart Contract

```
source .env

forge script script/DeployPriceSnapshot.s.sol \
  --rpc-url $SEPOLIA_RPC_URL \
  --broadcast 
```
simulate the deployment by removing the `--broadcast` flag

copy the `Address` of the deployed smart contract

#### Call `snapshot` function to read the latest data

```
cast call <CONTRACT_ADDRESS> \
  "snapshot(string)(string,uint256,uint256,uint256)" \
  "ETH" \
  --rpc-url $SEPOLIA_RPC_URL
```
the data entries should be `0` , we haven't run the cre workflow

## CRE WORKFLOW
### 1. Environment Varibales
#### create a `.env` file 
```
cd ./cre-http-to-chain

cp .env.example .env
```
#### add the following variables

```
CRE_ETH_PRIVATE_KEY=YOUR_PRIVATE_KEY
CRE_ETHERSCAN_API_KEY=YOUR_ETHERSCAN_API_KEY
```
### 2. Install dependencies

```
cd ./httpTriggerToChain
bun install
```
### 3. Update `config.json` file

#### add the deployed smart contract `Address` to `config.staging.json`

```
 "targetContract": {
    "address": "0xyourSnapshotContractAddress",
    "chainSelectorName": "ethereum-testnet-sepolia",
    
    }

```


### 4. Simulate and Run Workflow

#### Simulate workflow

```
cd cre-http-to-chain/

cre workflow simulate httpTriggerToChain --target staging-settings --non-interactive --trigger-index 0 --http-payload '{"token": "ETH"}'
```

#### Run workflow

```
cre workflow simulate httpTriggerToChain --target staging-settings --non-interactive --trigger-index 0 --http-payload '{"token": "ETH"}' --broadcast
```
#### observe the cre workflow output and also check the output onchain tx

### 5. Read the latest data

```
cd CRE-Assignment-devex/

cast call <CONTRACT_ADDRESS> \
  "snapshot(string)(string,uint256,uint256,uint256)" \
  "ETH" \
  --rpc-url $SEPOLIA_RPC_URL
```
#### latest data should match the cre workflow output
