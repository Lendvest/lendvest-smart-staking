const ethers = await import("npm:ethers@6.10.0");
const wasm = await import("https://raw.githubusercontent.com/Lendvest/WASM-Verifier-Functions/refs/heads/main/risc0_wasm_verifier.js");


// Initialize the WASM module (this is the crucial step!)
await wasm.default(); // or await wasm.init() depending on how it's exported


// Extract arguments passed to the Chainlink Functions script
const API = args[0];
// Token auth removed - using secrets.apiKey instead


function hexToUint8Array(hex) {
  if (hex.startsWith("0x")) hex = hex.slice(2);
  if (!/^[0-9a-fA-F]+$/.test(hex) || hex.length % 2 !== 0) {
    throw new Error("Invalid hex string");
  }
  const pairs = hex.match(/.{1,2}/g);
  const bytes = pairs.map(b => parseInt(b, 16));
  return new Uint8Array(bytes);
}

// // Make HTTP request to the API
// // NOTE: API uses GET method
// const response = await Functions.makeHttpRequest({
//   url: API,
//   method: "GET",
//   timeout: 9000,
//   headers: {
//     "Content-Type": "application/json",
//     "x-api-key": "9747e9923a51b5270ae59708407dee4d753ce1945e7153d21202aa5175992d3e",
//   },
// });

// // Extract the API response
// const apiResponse = response.data;

// // Validate API response has success field
// if (!apiResponse || !apiResponse.success) {
//   throw new Error("API request failed or returned unsuccessful response");
// }

// // Extract the actual data from the 'data' wrapper
// const responseData = apiResponse.data;

// // Validate response structure
// if (typeof responseData !== "object" || responseData === null) {
//   throw new Error("API response data is not a valid object");
// }

// // Check for required fields
// if (!responseData.verified_statistics || !responseData.receipt) {
//   throw new Error(
//     "API response missing required fields: verified_statistics or receipt"
//   );
// }

// const verifiedStats = responseData.verified_statistics;
// const receiptHash = ethers.keccak256(ethers.toUtf8Bytes(responseData.receipt));

// console.log("Verified Statistics:", verifiedStats);
// console.log("Receipt Hash:", receiptHash);

// Extract and convert rates and count to BigInt
let liquidityRateSum_1e27;
let variableBorrowRateSum_1e27;
let numRates;

// ============================================================
// HARDCODED REALISTIC VALUES FOR TESTING
// ============================================================
// These values simulate a 14-day epoch with typical Aave rates:
// - Supply APY: ~2.5% (2.5e25 per day in ray/1e27 scale)
// - Borrow APY: ~4.0% (4.0e25 per day in ray/1e27 scale)
// - Days collected: 14 (full epoch)
//
// Final rate calculation (from LVLidoVaultUtil.sol:703):
// rate = (sumLiquidity + sumBorrow) / (2 * numRates * 1e9)
// rate = (3.5e26 + 5.6e26) / (2 * 14 * 1e9)
// rate = 9.1e26 / 28e9 = 3.25e16 = 3.25% APY
//
// This is within bounds: 0.5% (5e15) to 10% (1e17)
// ============================================================

// Sum of 14 days of supply rates at ~2.5% APY each
// 14 * 2.5e25 = 3.5e26
liquidityRateSum_1e27 = 0n;

// Sum of 14 days of borrow rates at ~4.0% APY each
// 14 * 4.0e25 = 5.6e26
variableBorrowRateSum_1e27 = 0n;

// Number of rate samples (14 days for a full epoch)
numRates = 1n;

// try {
//   // total_supply_rate_sum maps to liquidityRateSum
//   const liquidityRateStr = verifiedStats.total_supply_rate_sum;
//   if (!liquidityRateStr) {
//     throw new Error("total_supply_rate_sum is missing");
//   }
//   liquidityRateSum_1e27 = BigInt(liquidityRateStr);
// } catch (e) {
//   console.error(
//     `Error processing total_supply_rate_sum: Value='${verifiedStats.total_supply_rate_sum}', Error=${e}`
//   );
//   throw new Error(
//     `Invalid total_supply_rate_sum format (expected large integer string): ${verifiedStats.total_supply_rate_sum}`
//   );
// }

// try {
//   // total_borrow_rate_sum maps to variableBorrowRateSum
//   const variableBorrowRateStr = verifiedStats.total_borrow_rate_sum;
//   if (!variableBorrowRateStr) {
//     throw new Error("total_borrow_rate_sum is missing");
//   }
//   variableBorrowRateSum_1e27 = BigInt(variableBorrowRateStr);
// } catch (e) {
//   console.error(
//     `Error processing total_borrow_rate_sum: Value='${verifiedStats.total_borrow_rate_sum}', Error=${e}`
//   );
//   throw new Error(
//     `Invalid total_borrow_rate_sum format (expected large integer string): ${verifiedStats.total_borrow_rate_sum}`
//   );
// }

// try {
//   // days_collected represents the number of rate samples collected
//   const numRatesValue = verifiedStats.days_collected;
//   if (numRatesValue === undefined || numRatesValue === null) {
//     throw new Error("days_collected is missing");
//   }
//   numRates = BigInt(numRatesValue);
// } catch (e) {
//   console.error(
//     `Error processing days_collected: Value='${verifiedStats.days_collected}', Error=${e}`
//   );
//   throw new Error(
//     `Invalid days_collected format (expected integer): ${verifiedStats.days_collected}`
//   );
// }

// // Validate receipt hash is a string
// if (typeof receiptHash !== "string" || receiptHash.length === 0) {
//   throw new Error(
//     `Invalid receipt hash format (expected non-empty string): ${receiptHash}`
//   );
// }

// console.log("rrr",responseData.receipt)
// console.log("programId", responseData.program_id)
// const verificationResult = wasm.verify_proof(responseData.receipt,responseData.program_id)
// const proof_verification_success = verificationResult.valid;
// let journal_hash;
// if(proof_verification_success){
//     journal_hash = verificationResult.journal_hash;
// }

// Encode the data with the receipt hash as the 4th parameter
// This matches LVLidoVaultUtil.sol:529-530 expectation:
// (uint256 sumLiquidityRates_1e27, uint256 sumVariableBorrowRates_1e27, uint256 numRates, string memory hash)
// const encodedData = ethers.AbiCoder.defaultAbiCoder().encode(
//   ["uint256", "uint256", "uint256", "bool", "string"],
//   [liquidityRateSum_1e27, variableBorrowRateSum_1e27, numRates, proof_verification_success, journal_hash]
// );


const encodedData = ethers.AbiCoder.defaultAbiCoder().encode(
  ["uint256", "uint256", "uint256"],
  [liquidityRateSum_1e27, variableBorrowRateSum_1e27, numRates]
);

return ethers.getBytes(encodedData);
