const ethers = await import("npm:ethers@6.10.0");
const wasm = await import("https://raw.githubusercontent.com/Lendvest/WASM-Verifier-Functions/refs/heads/main/risc0_wasm_verifier.js");

// Helper function to return fallback values on error
function returnFallback(errorMsg) {
  console.error("Error occurred, returning fallback values (0, 0, 1):", errorMsg);
  const fallbackData = ethers.AbiCoder.defaultAbiCoder().encode(
    ["uint256", "uint256", "uint256"],
    [0n, 0n, 1n]
  );
  return ethers.getBytes(fallbackData);
}

try {
  // Initialize the WASM module (this is the crucial step!)
  await wasm.default(); // or await wasm.init() depending on how it's exported

  // Extract arguments passed to the Chainlink Functions script
  const API = args[0];
  // Token auth removed - using secrets.apiKey instead

  // Make HTTP request to the API
  // NOTE: API uses GET method
  const response = await Functions.makeHttpRequest({
    url: API,
    method: "GET",
    timeout: 9000,
    headers: {
      "Content-Type": "application/json",
      "x-api-key": secrets.apiKey,
    },
  });

  // Extract the API response
  const apiResponse = response.data;

  // Validate API response has success field
  if (!apiResponse || !apiResponse.success) {
    return returnFallback("API request failed or returned unsuccessful response");
  }

  // Extract the actual data from the 'data' wrapper
  const responseData = apiResponse.data;

  // Validate response structure
  if (typeof responseData !== "object" || responseData === null) {
    return returnFallback("API response data is not a valid object");
  }

  // Check for required fields
  if (!responseData.verified_statistics || !responseData.receipt) {
    return returnFallback("API response missing required fields: verified_statistics or receipt");
  }

  const verifiedStats = responseData.verified_statistics;
  const receiptHash = ethers.keccak256(ethers.toUtf8Bytes(responseData.receipt));

  console.log("Verified Statistics:", verifiedStats);
  console.log("Receipt Hash:", receiptHash);

  // Extract and convert rates and count to BigInt
  let liquidityRateSum_1e27;
  let variableBorrowRateSum_1e27;
  let numRates;

  try {
    // total_supply_rate_sum maps to liquidityRateSum
    const liquidityRateStr = verifiedStats.total_supply_rate_sum;
    if (!liquidityRateStr) {
      throw new Error("total_supply_rate_sum is missing");
    }
    liquidityRateSum_1e27 = BigInt(liquidityRateStr);
  } catch (e) {
    console.error(
      `Error processing total_supply_rate_sum: Value='${verifiedStats.total_supply_rate_sum}', Error=${e}`
    );
    return returnFallback(`Invalid total_supply_rate_sum format: ${verifiedStats.total_supply_rate_sum}`);
  }

  try {
    // total_borrow_rate_sum maps to variableBorrowRateSum
    const variableBorrowRateStr = verifiedStats.total_borrow_rate_sum;
    if (!variableBorrowRateStr) {
      throw new Error("total_borrow_rate_sum is missing");
    }
    variableBorrowRateSum_1e27 = BigInt(variableBorrowRateStr);
  } catch (e) {
    console.error(
      `Error processing total_borrow_rate_sum: Value='${verifiedStats.total_borrow_rate_sum}', Error=${e}`
    );
    return returnFallback(`Invalid total_borrow_rate_sum format: ${verifiedStats.total_borrow_rate_sum}`);
  }

  try {
    // days_collected represents the number of rate samples collected
    const numRatesValue = verifiedStats.days_collected;
    if (numRatesValue === undefined || numRatesValue === null) {
      throw new Error("days_collected is missing");
    }
    numRates = BigInt(numRatesValue);
  } catch (e) {
    console.error(
      `Error processing days_collected: Value='${verifiedStats.days_collected}', Error=${e}`
    );
    return returnFallback(`Invalid days_collected format: ${verifiedStats.days_collected}`);
  }

  // Validate receipt hash is a string
  if (typeof receiptHash !== "string" || receiptHash.length === 0) {
    return returnFallback(`Invalid receipt hash format: ${receiptHash}`);
  }

  // console.log("rrr",responseData.receipt)
  // console.log("programId", responseData.program_id)
  const verificationResult = wasm.verify_proof(responseData.receipt,responseData.program_id)
  const proof_verification_success = verificationResult.valid;
  
  if(!proof_verification_success){
      // journal_hash = verificationResult.journal_hash;
    return returnFallback('rate verification Failed')
  }

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

} catch (error) {
  // Catch any unexpected errors and return fallback values
  return returnFallback(`Unexpected error: ${error.message || error}`);
}
