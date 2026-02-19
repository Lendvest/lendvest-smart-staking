const wasm = await import("https://raw.githubusercontent.com/Lendvest/risc-zero-verifier-deno/refs/heads/main/risc_zero_verifier.js")
const ethers = await import("npm:ethers@6.10.0");

function hexToUint8Array(hex) {
  if (hex.startsWith("0x")) hex = hex.slice(2);
  if (!/^[0-9a-fA-F]+$/.test(hex) || hex.length % 2 !== 0) {
    throw new Error("Invalid hex string");
  }
  const pairs = hex.match(/.{1,2}/g);
  const bytes = pairs.map(b => parseInt(b, 16));
  return new Uint8Array(bytes);
}

// const url="http://89.169.108.194:3000/get-cached-proof"
// const proofRequest = Functions.makeHttpRequest({
//   url: url,
//   headers: {
//     "Content-Type": "application/json",
//   }
// });


// const verifyRequest = Functions.makeHttpRequest({
//   url: "http://89.169.108.194:3000/verify-proof",
//   method: "POST",
//   headers: {
//     "Content-Type": "application/json",
//   },
//   data: {
    
//   },
// });

// Execute the API request (Promise)
// const proofResponse = await proofRequest;
// console.log(proofResponse)
const receiptBinary = "0200000000010000000000001c66b29af823ef7137202de666da5e63ed5d2029cf5fe7ea5943a7b562f653c2135efcd0ac75840785bf860bfcf5fb2fb3bde0eb3af3dbb465afdc3ff35c909224f1e1ac3fcaf67907e73382dd1a22792be1e08a424ee405e26a7d302e2235a10e4533f012ecf93027d160157c6a6348c4ee5fe97097025f9ceb8af1a32a3fe6108bc5cc42aabd7391ec309784534c5593ad9d3d10a9e79068abd0f11af1ec0d1dd815ba6835540bd8e5598a54fefa13fc79399ab56827e99ef8d2483a5db5f0142ad6b09252fba64b3fa4899c51634cb494805ddfd57d8031f883f732876ff627ef00a8af0d4ea325c1c3166535655a635ddd94dfb328f1adbcb500cc07c10400000000000000000000000061a9b03658b4ae34ad94710236d46a433e2d95127321883425149b07edb8920e00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000000000000000000010000000000010000000000000001000000000000000000000000000000000000000000000000000068ac13076f8977323de222da7e7b671f9a606d3341605b15f121558f87ffb9b7598b1b069a223c7ca04c969f1cacbe5b8db44c308b2c53390505d3d48c834ed4469fc83900000000000000000000000000000000000000000000000000000000000000bb00000000000000000000000000000000000000000000000000000000000000fe0000000000000000000000000000000000000000001ee3571763334d69bbb17d00000000000000000000000000000000000000000029fa52a5c8b942861a36740000000000000000000000000000000000000000000000000000000000000002000000000000000000000000bb001d444841d70e8bc0c7d034b349044bf3cf0117afb702b2f1e898b7dd13cc00010000000000000001000000000000000000000000000000000000000000000000000068ac13076f8977323de222da7e7b671f9a606d3341605b15f121558f87ffb9b7598b1b069a223c7ca04c969f1cacbe5b8db44c308b2c53390505d3d48c834ed4469fc83900000000000000000000000000000000000000000000000000000000000000bb00000000000000000000000000000000000000000000000000000000000000fe0000000000000000000000000000000000000000001ee3571763334d69bbb17d00000000000000000000000000000000000000000029fa52a5c8b942861a36740000000000000000000000000000000000000000000000000000000000000002bb001d444841d70e8bc0c7d034b349044bf3cf0117afb702b2f1e898b7dd13cc"

// proofResponse.data.receipt
const guestCodeId = "2f507e53091ff36fcaeb91eaedc88312b324ee13165ddb380d70793d44798c83"
// proofResponse.data.program_id;

console.log('RISC Zero verifier version:', wasm.get_risc0_version());




const bytes = hexToUint8Array(receiptBinary);


console.log('Attempting binary verification...');

const result = wasm.verify_receipt_binary(guestCodeId, bytes);

console.log('Verification result:', result);

const hash = ethers.keccak256(bytes);
console.log("Hash:", hash);

// ABI encoding
const encoded = ethers.AbiCoder.defaultAbiCoder().encode(
  ["bool", "string"],
  [result["verified"], hash]
);

// return the encoded data as Uint8Array
return ethers.getBytes(encoded);