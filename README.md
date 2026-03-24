# Lendvest Smart Staking (LVLidoVault)

## Bug Bounty Program

This repository is part of an active bug bounty program. We invite security researchers to review the smart contracts and report vulnerabilities.

**Scope:** All Solidity contracts in `src/` are in scope. Deployment scripts, tests, and JavaScript files are out of scope.

**Severity Levels:**
| Severity | Description | Reward Range |
|----------|-------------|--------------|
| Critical | Loss of user funds, unauthorized minting/burning, vault drainage | Up to $30,000 |
| High | State manipulation, incorrect accounting, privilege escalation | Up to $5,000 |
| Medium | Griefing attacks, DoS vectors, economic inefficiencies | Up to $1,500 |
| Low | Gas optimizations, code quality, informational | Up to $500 |

**Reporting:** Submit findings via [HackenProof](https://hackenproof.com) or email security@lendvest.io with a clear description, reproduction steps, and recommended fix.

---

## Protocol Overview

LVLidoVault is a DeFi lending protocol that facilitates leveraged borrowing against Lido's Wrapped Staked Ether (wstETH). The vault orchestrates a matching engine between three participant types to create a capital-efficient lending market. Lendvest Smart Staking (LVLidoVault).

### Participants

- **Lenders** deposit WETH as quote tokens. Unutilized funds are automatically routed to a Morpho Blue vault to earn yield while waiting to be matched.
- **Borrowers** deposit wstETH collateral to borrow WETH, creating leveraged staking positions. Leverage is achieved via Morpho flash loans to amplify collateral before borrowing from the Ajna pool.
- **Collateral Lenders** provide additional wstETH to shield the vault from wstETH/stETH redemption rate drawdowns. They earn a fixed 0.5% APY from borrower proceeds as compensation.

### Epochs and Terms

- **Term:** The active borrowing period. The realized interest rate is calculated from on-chain Aave market data collected during the term (via Chainlink Functions + ZK proof verification). Losses cascade: borrower first, then collateral lender, then lender.
- **Epoch:** The full lifecycle of a lending round. Includes the term plus the Lido withdrawal delay (~1-10 days) and final settlement.

## Architecture

```
src/
  LVLidoVault.sol          -- Core vault: deposits, withdrawals, matching engine, flash loan leverage
  LVLidoVaultUtil.sol       -- Chainlink Automation + Functions: rate fetching, collateral monitoring
  LVLidoVaultUpkeeper.sol   -- Epoch closing logic (extracted for contract size limits)
  LVLidoVaultReader.sol     -- View-only getters (extracted for contract size limits)
  LiquidationProxy.sol      -- Ajna pool liquidation handling
  LVToken.sol               -- ERC-20 receipt tokens (LVWETH, LVWSTETH)
  LVLidoVaultUtilRescue.sol -- Emergency fund recovery utility
  libraries/VaultLib.sol     -- Shared structs and constants
  interfaces/               -- External protocol interfaces (Ajna, Aave, Lido, Morpho, Chainlink)
```

### External Integrations

| Protocol | Usage |
|----------|-------|
| **Ajna** | Collateralized lending pool (wstETH/WETH) for borrower positions |
| **Morpho Blue** | Flash loans for leverage; idle fund yield via ERC-4626 vault |
| **Lido** | wstETH staking, stETH withdrawal queue |
| **Chainlink Functions** | Fetches ZK-verified Aave rate data for interest rate calculation |
| **Chainlink Automation** | Automated epoch lifecycle: collateral top-ups, liquidation triggers, rate fetching, settlement |

### Automation Tasks

Chainlink Automation executes these tasks via `checkUpkeep()` / `performUpkeep()`:

| Task | Trigger | Action |
|------|---------|--------|
| 0 | Redemption rate drawdown | Add collateral to avoid Ajna liquidation |
| 3 | Max tranches exhausted | Enable lender kick (liquidation auction) |
| 221 | Term ended | Fetch final interest rate via Chainlink Functions |
| 1 | Rate received | Queue Lido withdrawals for collateral |
| 2 | Lido withdrawal finalized | Settle epoch: repay all parties, close epoch |

## Getting Started

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation) (forge, cast, anvil)
- Node.js v16+
- An Ethereum mainnet RPC URL (for fork testing)

### Setup

```bash
git clone git@github.com:Lendvest/lendvest-smart-staking.git
cd lendvest-smart-staking
forge install
npm install
```

### Configuration

Create a `.env` file:

```bash
RPC_URL=https://eth-mainnet.g.alchemy.com/v2/YOUR_KEY
ETHERSCAN_API_KEY=your_etherscan_key
```

### Build

```bash
forge build --skip test
```

Compiler settings (from `foundry.toml`):
- Solidity 0.8.28, EVM target Shanghai
- `via_ir = true`, optimizer runs = 200
- `cbor_metadata = false`, `bytecode_hash = "none"`

## Running Tests

All tests fork Ethereum mainnet and require `RPC_URL` to be set.

### Full Test Suite

```bash
forge test --fork-url $RPC_URL -vv
```

### By Category

**Epoch Lifecycle (end-to-end):**
```bash
forge test --match-contract E2EEpochLifecycle --fork-url $RPC_URL -vv
```

**Borrower APR Validation:**
```bash
forge test --match-contract E2EBorrowerAPR --fork-url $RPC_URL -vv
```

**Withdrawal Flow:**
```bash
forge test --match-contract E2EWithdrawalValidation --fork-url $RPC_URL -vv
forge test --match-contract MultiEpochWithdrawal --fork-url $RPC_URL -vv
```

**Liquidation & Collateral Protection:**
```bash
forge test --match-contract AjnaLiquidation --fork-url $RPC_URL -vv
forge test --match-contract CollateralAutomation --fork-url $RPC_URL -vv
forge test --match-contract LiquidationProxy --fork-url $RPC_URL -vv
```

**Chainlink Automation Integration:**
```bash
forge test --match-contract AutomationsIntegration --fork-url $RPC_URL -vv
forge test --match-contract PublicPerformTask --fork-url $RPC_URL -vv
```

**Security-Specific:**
```bash
forge test --match-contract ReentrancyFix --fork-url $RPC_URL -vv
forge test --match-contract EmergencyWithdrawal --fork-url $RPC_URL -vv
forge test --match-contract RateFallback --fork-url $RPC_URL -vv
```

**Queue & Matching:**
```bash
forge test --match-contract QueueArchitecture --fork-url $RPC_URL -vv
```

**Flash Loans:**
```bash
forge test --match-contract MorphoFlashLoan --fork-url $RPC_URL -vv
```

**Model Comparison:**
```bash
forge test --match-contract E2EModelComparison --fork-url $RPC_URL -vv
```

### Run a Single Test

```bash
forge test --match-test testFunctionName --fork-url $RPC_URL -vvvv
```

## Deployed Contracts (Ethereum Mainnet)

| Contract | Address |
|----------|---------|
| LVLidoVault | [`0xe3C272F793d32f4a885e4d748B8E5968f515c8D6`](https://etherscan.io/address/0xe3C272F793d32f4a885e4d748B8E5968f515c8D6) |
| LVLidoVaultUtil | [`0x5f01bc229629342f1B94c4a84C43f30eF8ef76Fe`](https://etherscan.io/address/0x5f01bc229629342f1B94c4a84C43f30eF8ef76Fe) |
| LVLidoVaultUpkeeper | [`0x9e5174475B1AB852EDc47D8FFfC983f65F691117`](https://etherscan.io/address/0x9e5174475B1AB852EDc47D8FFfC983f65F691117) |
| LVLidoVaultReader | [`0x4e66D9073AA97b9BCEa5f0123274f22aE42229FC`](https://etherscan.io/address/0x4e66D9073AA97b9BCEa5f0123274f22aE42229FC) |
| LiquidationProxy | [`0x5f113C3977d633859C1966E95a4Ec542f594365c`](https://etherscan.io/address/0x5f113C3977d633859C1966E95a4Ec542f594365c) |
| LVWETH (v11) | [`0x1745D52b537b9e2DC46CeeDD7375614b3D91CB8C`](https://etherscan.io/address/0x1745D52b537b9e2DC46CeeDD7375614b3D91CB8C) |
| LVWSTETH (v11) | [`0xEFe6E493184F48b5f5533a827C9b4A6b4fFC09dE`](https://etherscan.io/address/0xEFe6E493184F48b5f5533a827C9b4A6b4fFC09dE) |
| Ajna Pool (LVWSTETH/LVWETH) | [`0x4bb3e528dd71fc268fCb5AE7A19C88f9d4A85caC`](https://etherscan.io/address/0x4bb3e528dd71fc268fCb5AE7A19C88f9d4A85caC) |

All contracts are verified on Etherscan. Source code matches this repository.

## Known Issues

See [KNOWN_ISSUES.md](KNOWN_ISSUES.md) for the full list of 24 known issues and 10 fixed issues documented for the bug bounty program. Bug bounty submissions reporting known issues will be considered out of scope.

## Known Design Decisions

- **MAX_ORDERS_PER_EPOCH = 260** caps orders per epoch to prevent gas griefing on withdrawal loops.
- **Flash loan leverage** uses Morpho (not Aave) to avoid circular dependency on the same pool.
- **Tiered loss waterfall:** Borrower absorbs losses first, then collateral lender, then lender.
- **Ownership model:** Token ownership held by a 3-of-5 governance multisig. Vault ownership by deployer EOA (to be renounced after epoch 3).

## License

[BUSL-1.1](LICENSE)

Lendvest, 2026
