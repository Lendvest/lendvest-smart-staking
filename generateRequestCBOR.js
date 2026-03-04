/**
 * @title Generate Chainlink Functions Request CBOR
 * @notice This script generates the CBOR-encoded request bytes needed for setRequest()
 * @dev Run this script to generate the FUNCTIONS_REQUEST_CBOR value for your deployment
 * 
 * Usage:
 *   node script/generateRequestCBOR.js
 * 
 * Output:
 *   - Prints the hex-encoded CBOR bytes to console
 *   - Optionally saves to .env file
 */

const fs = require("fs");
const path = require("path");
require("dotenv").config();

const {
  buildRequestCBOR,
  Location,
  CodeLanguage,
} = require("@chainlink/functions-toolkit");

async function main() {
  console.log("=== Chainlink Functions Request CBOR Generator ===\n");

  // --- Configuration ---
  const sourceFilePath = path.resolve(__dirname, "./risck-script.js");
  const apiEndpoint = process.env.API_ENDPOINT || "https://api.nyccode.org/api/getproof";

  // --- Validate source file exists ---
  if (!fs.existsSync(sourceFilePath)) {
    throw new Error(
      `Source file not found at ${sourceFilePath}. Make sure risck-script.js exists in the project root.`
    );
  }

  // --- Read the source code file ---
  console.log(`Reading source code from: ${sourceFilePath}`);
  const source = fs.readFileSync(sourceFilePath).toString();
  console.log(`Source code length: ${source.length} characters\n`);

  // --- Build the CBOR-encoded request ---
  console.log("Building CBOR-encoded request...");
  const functionsRequestBytesHexString = buildRequestCBOR({
    codeLocation: Location.Inline,
    codeLanguage: CodeLanguage.JavaScript,
    secretsLocation: Location.Remote,
    source: source,
    args: [apiEndpoint],
    bytesArgs: [],
  });

  console.log("\n=== GENERATED CBOR REQUEST ===");
  console.log(`Hex String: ${functionsRequestBytesHexString}`);
  console.log(`Length: ${functionsRequestBytesHexString.length / 2 - 1} bytes`);

  // --- Instructions for use ---
  console.log("\n=== USAGE INSTRUCTIONS ===");
  console.log("1. Copy the hex string above");
  console.log("2. In your deployAll.s.sol, set:");
  console.log(`   FUNCTIONS_REQUEST_CBOR = ${functionsRequestBytesHexString};`);
  console.log("\n   OR set in your .env file (if using vm.envBytes()):");
  console.log(`   FUNCTIONS_REQUEST_CBOR=${functionsRequestBytesHexString}`);
  console.log("\n3. Set your Chainlink Functions subscription ID:");
  console.log("   FUNCTIONS_SUBSCRIPTION_ID = <your_subscription_id>;");
  console.log("\n4. Run your deployment script:");
  console.log("   forge script script/deployAll.s.sol --broadcast --verify");

  // --- Optionally save to a file ---
  const outputPath = path.resolve(__dirname, "../.cbor-output.txt");
  fs.writeFileSync(outputPath, functionsRequestBytesHexString);
  console.log(`\n✓ CBOR bytes also saved to: ${outputPath}`);
}

main()
  .then(() => {
    console.log("\n✓ CBOR generation completed successfully!");
    process.exit(0);
  })
  .catch((error) => {
    console.error("\n✗ Error generating CBOR:");
    console.error(error);
    process.exit(1);
  });

