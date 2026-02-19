/**
 * @title Set Chainlink Functions Request
 * @notice This script calls setRequest() on an already-deployed LVLidoVaultUtil contract
 * @dev This is an alternative to the automatic setup in deployAll.s.sol
 * 
 * NOTE: You can now configure this automatically during deployment!
 *       See script/CHAINLINK_FUNCTIONS_SETUP.md for the new method.
 * 
 * This script is useful for:
 * - Updating the request on an existing deployment
 * - Manual configuration when AUTO_SET_REQUEST is disabled
 */

// const { ethers, network } = require("hardhat");
const fs = require("fs");
const path = require("path");
require("dotenv").config();
const ethers = require("ethers");
const contractAbi = require("./abi.json");
const {
  SecretsManager,
  simulateScript,
  buildRequestCBOR,
  ReturnType,
  decodeResult,
  Location,
  CodeLanguage,
} = require("@chainlink/functions-toolkit");

// Import necessary items from the toolkit if you were building CBOR manually
// (Not needed for calling setRequest, but would be needed if calling _sendRequest directly)
// const { buildRequestCBOR, Location, CodeLanguage } = require("@chainlink/functions-toolkit");

async function main() {
  // Ensure we are on the Sepolia network
  // if (network.name !== "sepolia") {
  //   throw new Error("Please run this script on the Sepolia network (`npx hardhat run scripts/setRequest.js --network sepolia`)");
  // }

  // --- Configuration ---
  const subscriptionId = process.env.SUBSCRIPTION_ID; // From createGist.js
  const contractAddress = process.env.CONTRACT_ADDRESS; // Set to deployed LVLidoVaultUtil contract address
  // const encryptedSecretsUrls = "0x312d1d6fb4ed63df7f50f1a49679a3cf03ade1620792d533b5d1361182f3e9a51ae81534def68249e5d58c22c7a12a44ac75cfaec713552be39127e4263d90d491d4ce425f9d2323e8e01d3e641ca445b9a12c7ea47f16707dbdabcfece7aa63bc1c1229bc826a5d91d016806186de045b4705c3b96a77f05d50e9b1632dfc623d3eb446a948af701740ca61100a6c7ee8e7c3e5614344864cf5b3da94cb08b441"; // Set from createGist.js output if using encrypted DON-hosted secrets.
  // const apiUrl = process.env.API_URL;
  // const apiToken = process.env.TOKEN; // Assuming TOKEN holds the SxT token/key
  const privateKey = process.env.PRIVATE_KEY; // fetch PRIVATE_KEY
  const rpcUrl = process.env.ETHEREUM_MAINNET_RPC_URL;
  const fulfillGasLimit = 300000; // From createGist.js
  // const reserveAddress =
  //   "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2".toLowerCase(); // WETH mainnet address
  const sourceFilePath = path.resolve(__dirname, "./risck-script.js"); // Assumes script is in root

  // --- Error Handling ---
  if (!contractAddress || contractAddress === "YOUR_CONTRACT_ADDRESS") {
    throw new Error(
      "Please replace 'YOUR_CONTRACT_ADDRESS' with your deployed contract address."
    );
  }
  // if (!apiUrl || !apiToken) {
  //   throw new Error(
  //     "API_URL or TOKEN environment variables not set in .env file."
  //   );
  // }
  // if (!encryptedSecretsUrls || encryptedSecretsUrls.length < 10) {
  //   // Basic check
  //   throw new Error(
  //     "Please replace the placeholder for encryptedSecretsUrls with the actual value from createGist.js output."
  //   );
  // }

  // --- Read the source code file ---
  let source;
  try {
    source = fs.readFileSync(sourceFilePath).toString();
  } catch (error) {
    console.error(`Error reading source file at ${sourceFilePath}:`, error);
    throw new Error(
      "Could not read query-SxT-update-rates.js. Make sure it exists in the project root."
    );
  }

  // --- Prepare the arguments array ---
  // const args = [apiUrl, apiToken, reserveAddress];

  if (!rpcUrl)
    throw new Error(`rpcUrl not provided  - check your environment variables`);

  const provider = new ethers.providers.JsonRpcProvider(rpcUrl);

  const wallet = new ethers.Wallet(privateKey);
  const signer = wallet.connect(provider);
  console.log(`Attaching to contract at ${contractAddress}...`);
  const contract = new ethers.Contract(contractAddress, contractAbi, signer);

  // --- Call the setRequest function ---
  console.log("Calling setRequest function with parameters:");
  console.log(`  Subscription ID: ${subscriptionId}`);
  console.log(`  Gas Limit: ${fulfillGasLimit}`);
  console.log(`  Source Code Length: ${source.length} characters`);
  // console.log(`  Args: ${JSON.stringify(args)}`);
  // console.log(`  Encrypted Secrets URL (bytes): ${encryptedSecretsUrls}`);

  const functionsRequestBytesHexString = buildRequestCBOR({
    codeLocation: Location.Inline, // Location of the source code - Only Inline is supported at the moment
    codeLanguage: CodeLanguage.JavaScript, // Code language - Only JavaScript is supported at the moment
    secretsLocation: Location.Remote, // Location of the encrypted secrets - DONHosted in this example
    source: source, // soure code
    // encryptedSecretsReference: encryptedSecretsUrls,
    args: ["https://api.nyccode.org/api/getproof"],
    bytesArgs: [], // bytesArgs - arguments can be encoded off-chain to bytes.
  });

  const tx = await contract.setRequest(
    functionsRequestBytesHexString,
    subscriptionId,
    fulfillGasLimit,
    // {
    //   gasLimit: 5000000, // Reduced gas limit to be more economical
    //   maxFeePerGas: ethers.utils.parseUnits("5", "gwei"), // Revert to Ethers v5 syntax
    // }
  );

  console.log(`
Transaction sent! Hash: ${tx.hash}`);
  console.log("Waiting for transaction confirmation...");

  const receipt = await tx.wait(1); // Wait for 1 confirmation

  console.log(`Transaction confirmed in block ${receipt.blockNumber}.`);
  console.log("Request parameters successfully set on the contract.");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
