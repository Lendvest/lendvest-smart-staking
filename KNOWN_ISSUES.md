# Lendvest Smart Staking — Known Issues

Bug bounty submissions reporting these issues will be considered **out of scope**.

## Known Issues (Accepted)

| # | Issue | Severity | Category | Details / Mitigation |
|---|-------|----------|----------|----------------------|
| KI-01 | **Lendvest Router API in Chainlink Functions** | Medium | Oracle | Chainlink Functions calls Lendvest API for interest rate data. API compromise risk accepted. Rate bounds validation (0.5%–10%) enforced on-chain. Out-of-bounds rates fall back to Aave. |
| KI-02 | **Loss of Precision in Interest Calculations** | Low | Math | Minor precision loss in interest calculations due to integer division. Economically insignificant (<1 wei per calculation). Minimum epoch duration expected operationally. |
| KI-03 | **Insufficient Gas for Aave Withdrawal at Epoch End** | Medium | Gas | With many depositors in Aave, the epoch-close Aave withdrawal loops may exceed block gas limits. Emergency withdrawal functions available via UI as part of the withdraw button. 3-day delay for emergency path (`emergencyAaveWithdrawDelay`). |
| KI-04 | **Epoch Full Griefing (Storage Bloat DoS)** | Medium | DoS | Minimum order size enforced (`MIN_ORDER_SIZE = 0.01 ETH`), `MAX_ORDERS_PER_USER = 10`, `MAX_ORDERS_PER_EPOCH = 260`. An attacker using many addresses could still fill the epoch, rendering it unusable for other participants. Accepted as market behavior — costs attacker ~2.6 ETH minimum to fill. |
| KI-05 | **Admin Multi-Sig Controlled** | Medium | Access Control | Protocol is admin (governance multisig) controlled until the start of the third epoch, when admin control will be revoked. All admin functions are documented. |
| KI-06 | **Admin Permissions (All Documented)** | Medium | Access Control | All admin permissions are known and documented. This includes: setting proxy addresses, setting forwarder, setting rate bounds, setting upkeeper, flash loan fee threshold. Attacks requiring owner/admin access are out of scope. |
| KI-07 | **Lido Withdrawal Time and Claim Delay** | Medium | Timing | Lido withdrawals take ~7 days. During this period, interest continues to accrue. If Lido or Chainlink automation is delayed beyond the 7-day buffer, additional interest accrues that may not be fully captured. Collateral lender funds can cover the gap; borrower balance subtracted accordingly. Rescue contract available as fallback. |
| KI-08 | **Aave Withdrawal Rounding Dust** | Low | Math | Proportional share calculations `(userDeposit * withdrawn) / totalDeposits` round down, leaving <$1 dust in the contract. Economically insignificant. |
| KI-09 | **No Pause Mechanism** | Medium | Architecture | Core contracts do not implement OpenZeppelin Pausable. Owner can set proxy addresses to zero to effectively block operations in an emergency. |
| KI-10 | **Centralized Token Burn Capability** | Medium | Access Control | LVToken allows owner/allowed addresses to burn tokens from any address without holder approval. Required for protocol operation (test token minting/burning during epoch lifecycle). Owner-controlled. |
| KI-11 | **performTask / onReport Forwarder Address Swap** | Medium | Access Control | `performTask()` and `onReport()` temporarily set `s_forwarderAddress = address(this)` to allow self-calls to `performUpkeep`. Internal call pattern with no external callback risk. Both functions are permissionless by design. |
| KI-12 | **Front-Running on startEpoch (Redemption Rate)** | Low | MEV | startEpoch reads the wstETH redemption rate at execution time. An attacker could front-run with large stETH/wstETH swaps to affect matching ratios. Rate impact limited. MEV accepted as market behavior. |
| KI-13 | **LIFO Matching MEV Exposure** | Low | MEV | LIFO matching allows prediction of array state. Attackers can front-run for preferential matching position. Accepted as market behavior. |
| KI-14 | **External Protocol Dependencies** | Medium | Architecture | Protocol depends on Morpho Blue, Aave V3, Lido, Ajna, and Chainlink all being operational. If any external protocol pauses or fails, Lendvest operations may be blocked. Inherent to DeFi composability. Bugs in external protocols are out of scope. |
| KI-15 | **Aave Rate Flash Loan Manipulation** | Medium | Oracle | Interest rates fetched from Aave can be manipulated via flash loans. Rate bounds (0.5%–10%) enforced via Chainlink Functions validation. Out-of-bounds rates rejected. |
| KI-16 | **Hardcoded Collateral Lender APY (0.14%)** | Low | Design | CL APY is hardcoded as `14e14` (0.14%). Cannot adjust to market conditions without contract redeployment. Design decision; upgrade path exists. |
| KI-17 | **Hardcoded Bucket Index 7388** | Low | Design | Ajna pool bucket index is hardcoded. Optimal for current pool parameters. Would require redeployment to change. |
| KI-18 | **Missing Zero Address in setLVLidoVaultUtilAddress** | Low | Validation | Owner-only function. Operational care expected. `setLVLidoVaultUpkeeperAddress` does have the check. |
| KI-19 | **Missing Event for Upkeeper Address Change** | Low | Monitoring | `setLVLidoVaultUpkeeperAddress` does not emit an event. Minor monitoring impact. |
| KI-20 | **Unbounded Loops in Epoch Functions** | Medium | Gas | `startEpoch()` and `closeEpoch()` contain loops over order arrays. Bounded by `MAX_ORDERS_PER_EPOCH = 260`, `MAX_ORDERS_PER_USER = 10`. Tested to fit within block gas limits at 260 orders. |
| KI-21 | **setAllowKick Access Control Pattern** | Low | Access Control | `LiquidationProxy.setAllowKick` is `onlyOwner`, but vault calls it expecting to be owner. Coordinated setup required. Working as designed. |
| KI-22 | **Inconsistent Access Control Patterns** | Low | Code Quality | Codebase mixes `require(msg.sender == owner())` checks with `onlyOwner` modifiers. Functional but inconsistent. Not a vulnerability. |
| KI-23 | **UpkeepAdmin Missing Access Control** | Low | Access Control | `UpkeepAdmin.sol` is out of scope (admin utility). `acceptUpkeepAdmin()` and `transferLinkToken()` are permissionless but only affect Chainlink automation admin, not user funds. |
| KI-24 | **Lido Withdrawal Timing Dependency** | Medium | Timing | Epoch closing depends on Lido withdrawals being claimable. Delays in Lido queue can block `closeEpoch()`. Rescue contract (`LVLidoVaultUtilRescue.sol`) available for manual intervention. Emergency Aave withdrawal path has 3-day delay. |

## Fixed Issues (Resolved)

These were identified during audit and have been fixed. Included for transparency.

| ID | Issue | Severity | Fix |
|----|-------|----------|-----|
| FIX-01 | CEI Violation in onMorphoFlashLoan | High | State updates moved before external calls |
| FIX-02 | No Minimum Order Size (Storage Bloat DoS) | High | `MIN_ORDER_SIZE = 0.01 ETH` enforced + `MAX_ORDERS_PER_USER = 10` |
| FIX-03 | Oracle Staleness Not Checked | High | `PRICE_STALENESS_THRESHOLD = 1 hour` + revert on stale prices |
| FIX-04 | Unsafe int256 to uint256 Cast | High | Price > 0 validation before casting |
| FIX-05 | Arithmetic Underflow in totalLenderQTUnutilized | High | Underflow protection with AccountingDrift event |
| FIX-06 | Division by Zero in closeEpoch | High | Zero-check before division in `_processMatchesAndCreateOrders` |
| FIX-07 | Unchecked Transfer in claimBond | High | `SafeERC20.safeTransfer` used in LiquidationProxy |
| FIX-08 | Missing Reentrancy on settle/take | Medium | `nonReentrant` modifier added |
| FIX-09 | Missing Return in mintForProxy/burnForProxy | Medium | `else revert VaultLib.InvalidInput()` added |
| FIX-10 | Zero Address Check in setLVLidoVaultUpkeeperAddress | Low | `require != address(0)` added |

## Summary

| Category | Count |
|----------|-------|
| Known Issues (Accepted) | 24 |
| Fixed Issues (Resolved) | 10 |
| **Total Documented** | **34** |

| Known Issue Severity | Count |
|----------------------|-------|
| Medium | 13 |
| Low | 11 |
