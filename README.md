# LVLidoVault

## Project Overview

This repository contains the `LVLidoVault`, a sophisticated DeFi protocol designed to facilitate leveraged borrowing against Lido's Wrapped Staked Ether (wstETH). The vault orchestrates a matching engine between lenders, borrowers, and collateral lenders to create a capital-efficient lending market.

### Key Participants

- **Lenders**: Provide liquidity in the form of quote tokens (WETH). To ensure capital is always productive, any unutilized funds are automatically deposited into a Morpho Blue vault to generate yield.
- **Borrowers**: Deposit collateral tokens (wstETH) to borrow WETH, enabling them to create leveraged positions on their staked assets.
- **Collateral Lenders**: Provide additional wstETH collateral to help shield the vault from potential losses caused by downward fluctuations in the wstETH/stETH redemption rate. In return for this service, they earn a portion of the borrower's rewards.

### Epochs vs. Terms

The vault's operation is structured around epochs and terms, which are distinct concepts:

- **Term**: A fixed period during which borrowing and lending activities occur. The final, realized interest rate for the **lender** is calculated based on market data recorded _during this term_, which is paid by the borrower. Collateral lenders receive a separate, hardcoded 0.5% APY from the borrower. In the event of a loss, the borrower's position is impacted first, followed by the collateral lender's, and finally the lender's, ensuring a tiered risk structure.
- **Epoch**: The full lifecycle of a lending round. It is a longer period that includes the **Term** plus the additional time required to settle everything. This includes the delay for withdrawing funds from the Lido protocol (which can be up to 10 days) and processing all final repayments and reward distributions.

## Chainlink Integration

This project integrates with Chainlink's decentralized oracle network to provide automated rate updates and liquidation protection.

### Contracts Using Chainlink

#### [LVLidoVault.sol](contracts/LVLidoVault.sol)

**Chainlink Functions** - Used to query optimal interest rates from Space and Time (SxT) database.

- **Purpose**: Fetches real-time interest rate data from Aave events logged in SxT to determine optimal rates for vault terms
- **Key Functions**:
  - `getRate()` - Sends Functions request to fetch rate data
  - `fulfillRequest()` - Processes aggregated rate data and calculates average APR
  - `setRequest()` - Configures Functions request parameters (subscription ID, gas limit, CBOR data)

#### [LVLidoVaultUtil.sol](contracts/LVLidoVaultUtil.sol)

**Chainlink Automation** - Provides automated vault management and liquidation protection.

- **Purpose**: Monitors vault health and executes automated actions based on a predefined schedule and triggers.
- **Automation Tasks (in order of execution)**:
  - `0` - **Add Collateral**: Triggered by a significant drop in the wstETH/stETH price to add collateral and prevent liquidation.
  - `3` - **Enable Liquidation (Kick)**: Triggered if collateral top-ups are exhausted (`MAX_TRANCHES` reached), allowing for a lender kick (auction) to begin.
  - `221` - **Fetch Final Interest Rate**: Triggered after a term ends. This queries Chainlink Functions to get the final, realized interest rate, which is used to calculate settlement amounts for the epoch.
  - `1` - **Queue Withdrawals**: Triggered at the end of a term to begin the withdrawal process from Lido for the underlying collateral.
  - `2` - **Settle Epoch**: Triggered after the Lido withdrawal delay has passed; it claims the funds, repays all parties (lenders, borrowers, collateral lenders), and finalizes the epoch.

**Key Functions**:

- `checkUpkeep()` - Monitors vault conditions and determines if automation is needed
- `performUpkeep()` - Executes the appropriate action based on task ID

### Vault Lifecycle with Chainlink

The vault operates in epochs, with Chainlink playing a critical role at each stage:

1.  **During an Epoch (Liquidation Protection)**: `LVLidoVaultUtil` uses Chainlink Automation to constantly monitor the collateralization ratio. If the price of wstETH drops, **Task `0`** is triggered to add more collateral. If all collateral tranches are used, **Task `3`** enables a lender kick (liquidation auction).

2.  **At Epoch End (Term Conclusion)**: Once the term duration is met, Chainlink Automation triggers several tasks in sequence:

    - **Task `221`** calls Chainlink Functions via `LVLidoVault` to fetch the final, realized interest rate for the current epoch (based on the days of the term).
    - **Task `1`** initiates the withdrawal of collateral from Lido, which involves a time delay.
    - **Task `2`** runs after the delay, claims the withdrawn ETH (now WETH), settles all accounts by repaying lenders and returning remaining collateral to borrowers, and formally ends the epoch.

## Getting Started

### Prerequisites

- **Foundry** - Ethereum development toolkit (install via `curl -L https://foundry.paradigm.xyz | bash`)
- **Node.js** (v16 or higher) and npm - For JavaScript dependencies and tooling
- **Solidity compiler** (v0.8.20) - Will be installed automatically with Foundry
- **IDE** with Solidity support (Cursor, VSCode with Solidity extensions, or similar)
- **Git** - For version control and cloning the repository
- **SSH key** configured with GitHub for repository access
- **RPC URL** - For blockchain network access (configured in `.env` file)
- **WSL2** (if on Windows) - For Linux development environment

### Installation Steps

1. In a terminal window, type `wsl` and then `cd` into any preferred folder if any.
2. Run `git clone -b ajna-interest-avoid-fee git@github.com:Lendvest/LVLidoVault.git`.
3. Navigate into LendvestVaults using `cd LendvestVaults` and open in IDE using `cursor .` or `code .`.
4. Run `forge compile` which should install dependencies.
5. Configure `.env` file using `.env.example` as reference.
6. Run `forge test --match-test testNameHere -vv --rpc-url $RPC_URL`

## Testing

### Flow Tests (Successfully Compiling)

- testManualRepay
- testIdealScenario
- testBorrowerLoss
- testCollateralLenderLoss

## License

This project is licensed under the BUSL-1.1 License - see the [LICENSE](LICENSE) file for details.

Author: Lendvest

forge test --match-contract GetterFunctionsTest --fork-url  $RPC_URL -vv
