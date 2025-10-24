# USDD Peg Stability Module (PSM)

A **multi-chain peg stability module** that enables 1:1 swaps between USDD and major stablecoins (USDT/USDC) with configurable fees, built on **TRON mainnet** and compatible with other EVM networks.

## Technology Stack

- **Blockchain**: TRON Mainnet + EVM-compatible chains
- **Smart Contracts**: Solidity ^0.6.12
- **Testing**: Foundry framework with Forge
- **Development**: Foundry, OpenZeppelin libraries, ds-math/ds-test
- **Integration**: ChainLog registry system for contract discovery

## Supported Networks

- **Ethereum Mainnet** (Chain ID: 1)
- **BNB Smart Chain Mainnet** (Chain ID: 56)
- **TRON Mainnet**

## Contract Addresses

### Mainnet Contracts (Ethereum)

| Component | Contract Type | Address | Description |
|-----------|---------------|---------|-------------|
| USDT PSM | UsddPsm | Retrieved via ChainLog `MCD_PSM_USDT_A` | Main PSM for USDT ↔ USDD swaps |
| USDC PSM | UsddPsm | Retrieved via ChainLog `MCD_PSM_USDC_A` | Main PSM for USDC ↔ USDD swaps |
| USDT Join | AuthGemJoin | Retrieved via PSM | USDT deposit/withdrawal adapter |
| USDC Join | AuthGemJoin | Retrieved via PSM | USDC deposit/withdrawal adapter |
| USDD Join | UsddJoin | Retrieved via ChainLog | USDD minting/burning adapter |

### Quoter Contracts

| Network | USDT Quoter | USDC Quoter | Description |
|---------|-------------|-------------|-------------|
| Mainnet | *Deploy via script* | *Deploy via script* | Read-only price quoters |
| Testnet | *Deploy via script* | *Deploy via script* | Read-only price quoters |

## Features

- **1:1 Stablecoin Swaps**: Direct conversion between USDD and major stablecoins (USDT/USDC)
- **Configurable Fees**: Separate tin (sell) and tout (buy) fees with governance control
- **Multi-decimal Support**: Handles different token decimals (USDT/USDC: 6, USDD: 18)
- **Read-only Quoters**: Gas-efficient price discovery without state changes
- **Emergency Controls**: Pausable sell/buy functionality for security
- **MakerDAO Integration**: Built on proven DSS (Dai Stablecoin System) architecture
- **Governance Ready**: Administrative functions controlled by authorized entities
