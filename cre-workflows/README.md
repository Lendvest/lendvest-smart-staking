# Lendvest CRE Epoch Monitor

Chainlink CRE workflow that replaces Chainlink Automation + Functions for LVLidoVault.

## How It Works

```
Every 30 seconds:
  1. checkUpkeep()  --- VIEW call (FREE, no gas)
  2. upkeepNeeded?
     |-- false ---------> Exit (no gas spent)
     |-- true ─────────> Decode taskId from performData
                         |
                         |-- taskId 221 ──> Fetch rate from API
                         |                  Call fulfillRateFromCRE() (PAYS GAS)
                         |
                         |-- other tasks ─> Call performTask() (PAYS GAS)
```

## Tasks Handled

| Task ID | Trigger | Action |
|---------|---------|--------|
| 0 | Price drop >1% | Add collateral (avoid liquidation) |
| 1 | Term expired | Queue Lido withdrawal |
| 2 | Lido finalized | Close epoch, distribute funds |
| 3 | All tranches exhausted | Allow liquidation kicks |
| 221 | Term expired + debt | Fetch rate from API, update vault |

## Structure

```
cre-workflows/
|-- project.yaml              # RPC settings
|-- README.md
|-- workflow/
    |-- main.ts               # Main workflow
    |-- package.json
    |-- tsconfig.json
    |-- config.json           # Staging (Sepolia)
    |-- config.production.json # Production (Mainnet)
    |-- workflow.yaml
```

## Setup

1. Install dependencies:
```bash
cd workflow
bun install
```

2. Update config files with your contract address and API endpoint:
- `config.json` - for Sepolia testnet
- `config.production.json` - for Mainnet

3. Set RPC URLs in project.yaml or environment variables

4. Set API key secret:
```bash
cre secret set RATE_API_KEY <your-api-key>
```

## Deployment

### Staging (Sepolia)
```bash
cre deploy --target staging-settings
```

### Production (Mainnet)
```bash
cre workflow deploy ./workflow --target production-settings

cre workflow pause ./workflow --target production-settings

cre workflow delete ./workflow --target production-settings

cre workflow simulate ./workflow --target production-settings

```

## Configuration

| Field | Description |
|-------|-------------|
| `schedule` | Cron expression (e.g., `*/30 * * * * *` = every 30s) |
| `lvLidoVaultUtilAddress` | Deployed LVLidoVaultUtil contract |
| `rateApiEndpoint` | URL of rate data API (for task 221) |
| `chainSelectorName` | Chain name for CRE |
| `gasLimit` | Gas limit for transactions |
| `isTestnet` | true for testnets, false for mainnet |

## Solidity Changes Required

Added `fulfillRateFromCRE()` function to `LVLidoVaultUtil.sol`:
```solidity
function fulfillRateFromCRE(
    uint256 sumLiquidityRates_1e27,
    uint256 sumVariableBorrowRates_1e27,
    uint256 numRates
) external onlyForwarder;
```

Set the CRE forwarder address:
```solidity
lvLidoVaultUtil.setForwarderAddress(creForwarderAddress);
```

## Gas Optimization

- **VIEW calls first**: `checkUpkeep()` is free, no gas spent
- **Only pay when needed**: Transactions only sent when upkeep is actually required
- **Task 221 handled directly**: Rate fetched via HTTP, no Chainlink Functions overhead
