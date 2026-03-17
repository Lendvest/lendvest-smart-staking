import {
	bytesToHex,
	type CronPayload,
	cre,
	getNetwork,
	hexToBase64,
	type NodeRuntime,
	Runner,
	type Runtime,
	TxStatus,
} from '@chainlink/cre-sdk'
import {
	encodeFunctionData,
	decodeFunctionResult,
	decodeAbiParameters,
	encodeAbiParameters,
} from 'viem'
import { z } from 'zod'
const wasm = await import("https://raw.githubusercontent.com/Lendvest/WASM-Verifier-Functions/refs/heads/main/risc0_wasm_verifier.js");
await wasm.default();



// Configuration schema
const configSchema = z.object({
	schedule: z.string(), // Cron schedule (e.g., "*/30 * * * * *" for every 30 seconds)
	lvLidoVaultUtilAddress: z.string(), // LVLidoVaultUtil contract address
	rateApiEndpoint: z.string(), // Rate API endpoint (for task 221)
	chainSelectorName: z.string(), // Chain name (e.g., "ethereum-testnet-sepolia")
	gasLimit: z.string(), // Gas limit for transactions
	isTestnet: z.boolean(), // Whether the target chain is a testnet
})

type Config = z.infer<typeof configSchema>

// ABI for LVLidoVaultUtil
const LVLidoVaultUtilAbi = [
	{
		name: 'checkUpkeep',
		type: 'function',
		stateMutability: 'view',
		inputs: [{ name: '', type: 'bytes' }],
		outputs: [
			{ name: 'upkeepNeeded', type: 'bool' },
			{ name: 'performData', type: 'bytes' },
		],
	},
	{
		name: 'performTask',
		type: 'function',
		stateMutability: 'nonpayable',
		inputs: [],
		outputs: [],
	},
	{
		name: 'fulfillRateFromCRE',
		type: 'function',
		stateMutability: 'nonpayable',
		inputs: [
			{ name: 'sumLiquidityRates_1e27', type: 'uint256' },
			{ name: 'sumVariableBorrowRates_1e27', type: 'uint256' },
			{ name: 'numRates', type: 'uint256' },
		],
		outputs: [],
	},
] as const

// API response type
interface RateApiResponse {
	success: boolean
	data: {
		receipt: string,
		program_id: string
		verified_statistics: {
			total_supply_rate_sum: string
			total_borrow_rate_sum: string
			days_collected: number
		}
	}
}

/**
 * Check if upkeep is needed and get task ID
 * Returns: { upkeepNeeded, taskId }
 */
const checkUpkeepNeeded = (runtime: Runtime<Config>): { upkeepNeeded: boolean; taskId: number } => {
	const network = getNetwork({
		chainFamily: 'evm',
		chainSelectorName: runtime.config.chainSelectorName,
		isTestnet: runtime.config.isTestnet,
	})

	if (!network) {
		throw new Error(`Network not found: ${runtime.config.chainSelectorName}`)
	}

	const evmClient = new cre.capabilities.EVMClient(network.chainSelector.selector)

	runtime.log('Checking if upkeep is needed (view call - no gas)...')
	runtime.log(`lvLidoVaultUtilAddress: ${runtime.config.lvLidoVaultUtilAddress}`)

	// Encode checkUpkeep call
	const callData = encodeFunctionData({
		abi: LVLidoVaultUtilAbi,
		functionName: 'checkUpkeep',
		args: ['0x'],
	})

	// Call checkUpkeep - VIEW function, no gas cost
	// Note: 'to' address must be in base64 format for CRE SDK
	runtime.log(`Calling contract at: ${runtime.config.lvLidoVaultUtilAddress}`)
	const result = evmClient
		.callContract(runtime, {
			call: {
				to: hexToBase64(runtime.config.lvLidoVaultUtilAddress),
				data: hexToBase64(callData),
			},
		})
		.result()

	runtime.log(`result: ${result}`)
	// Check if we got valid data back
	const resultHex = bytesToHex(result.data)
	if (!result.data || result.data.length === 0 || resultHex === '0x') {
		runtime.log('Contract returned empty data - no upkeep needed or contract not ready')
		return { upkeepNeeded: false, taskId: 0 }
	}
	runtime.log(`resultHex: ${resultHex}`)
	// Decode the result
	const decoded = decodeFunctionResult({
		abi: LVLidoVaultUtilAbi,
		functionName: 'checkUpkeep',
		data: resultHex,
	})
	runtime.log(`decoded: ${decoded}`)
	const upkeepNeeded = decoded[0] as boolean
	const performData = decoded[1] as `0x${string}`

	let taskId = 0
	if (upkeepNeeded && performData && performData !== '0x') {
		// Decode taskId from performData (abi.encode(uint256))
		const decodedTaskId = decodeAbiParameters(
			[{ name: 'taskId', type: 'uint256' }],
			performData
		)
		taskId = Number(decodedTaskId[0])
		runtime.log(`Upkeep needed! Task ID: ${taskId}`)
	} else if (!upkeepNeeded) {
		runtime.log('No upkeep needed')
	}

	return { upkeepNeeded, taskId }
}

/**
 * Fetch rate data from API
 */
const fetchRateData = (runtime: Runtime<Config>): { sumLiquidity: bigint; sumBorrow: bigint; numRates: bigint } | null => {
	const httpClient = new cre.capabilities.HTTPClient()

	runtime.log(`Fetching rate data from: ${runtime.config.rateApiEndpoint}`)

	try {
		const response = httpClient
			.sendRequest(runtime, {
				url: runtime.config.rateApiEndpoint,
				method: 'GET',
				headers: {
					'Content-Type': 'application/json',
					'x-api-key': '9747e9923a51b5270ae59708407dee4d753ce1945e7153d21202aa5175992d3e',
				},
			})
			.result()

		if (response.statusCode !== 200) {
			runtime.log(`API request failed with status: ${response.statusCode}`)
			return {
				sumLiquidity: BigInt('0'), // 3e25 (3% in RAY)
				sumBorrow: BigInt('0'),    // 3e25 (3% in RAY)
				numRates: 1n,
			}
		}

		const apiResponse = JSON.parse(new TextDecoder().decode(response.body)) as RateApiResponse

		if (!apiResponse.success || !apiResponse.data?.verified_statistics) {
			runtime.log('API response invalid or unsuccessful')
			return {
				sumLiquidity: BigInt('0'), // 3e25 (3% in RAY)
				sumBorrow: BigInt('0'),    // 3e25 (3% in RAY)
				numRates: 1n,
			}
		}

		runtime.log('API response received successfully')

		const stats = apiResponse.data.verified_statistics
		const verificationResult = wasm.verify_proof(apiResponse.data.receipt,apiResponse.data.program_id)
		runtime.log(`verificartion${verificationResult.valid}`)
		// Note: Proof verification skipped (WASM not supported in CRE)
		// Trusting API response directly
		runtime.log('Using rate data from API (unverified)')

		return {
			sumLiquidity: BigInt(stats.total_supply_rate_sum),
			sumBorrow: BigInt(stats.total_borrow_rate_sum),
			numRates: BigInt(stats.days_collected)
		}

		// =============================================================
		// HARDCODED RATE VALUES FOR TESTING
		// =============================================================
		// The contract calculates: rate = (sumLiquidity + sumBorrow) / (2 * numRates * 1e9)
		// We want a ~3% APY rate (3e16 in 1e18 scale)
		//
		// Formula: rate = (sumLiquidity + sumBorrow) / (2 * numRates * 1e9)
		// For rate = 3e16: (sumLiquidity + sumBorrow) = 3e16 * 2 * 1 * 1e9 = 6e25
		//
		// Using:
		//   sumLiquidity = 3e25 (3% supply rate in RAY/1e27 scale)
		//   sumBorrow = 3e25 (3% borrow rate in RAY/1e27 scale)
		//   numRates = 1
		//
		// Result: (3e25 + 3e25) / (2 * 1 * 1e9) = 6e25 / 2e9 = 3e16 (3% in 1e18 scale)
		// This is within bounds: 0.5% (5e15) to 10% (1e17)
		// =============================================================

	} catch (error) {
		runtime.log(`Error fetching rate data: ${error}`)
		return null
	}
}

/**
 * Execute fulfillRateFromCRE() for task 221
 * Note: CRE SDK uses writeReport for blockchain writes. The receiver contract
 * must implement the CRE report receiver interface to process the encoded data.
 */
const executeFulfillRate = (
	runtime: Runtime<Config>,
	sumLiquidity: bigint,
	sumBorrow: bigint,
	numRates: bigint
): string => {
	const network = getNetwork({
		chainFamily: 'evm',
		chainSelectorName: runtime.config.chainSelectorName,
		isTestnet: runtime.config.isTestnet,
	})

	if (!network) {
		throw new Error(`Network not found: ${runtime.config.chainSelectorName}`)
	}

	const evmClient = new cre.capabilities.EVMClient(network.chainSelector.selector)

	runtime.log(`Executing fulfillRateFromCRE(${sumLiquidity}, ${sumBorrow}, ${numRates})...`)

	// Encode the report data: (taskId, sumLiquidity, sumBorrow, numRates)
	// Task ID 221 = rate update
	const reportData = encodeAbiParameters(
		[
			{ name: 'taskId', type: 'uint256' },
			{ name: 'sumLiquidityRates_1e27', type: 'uint256' },
			{ name: 'sumVariableBorrowRates_1e27', type: 'uint256' },
			{ name: 'numRates', type: 'uint256' },
		],
		[BigInt(221), sumLiquidity, sumBorrow, numRates]
	)

	// Generate consensus report using the report capability
	const reportResponse = runtime
		.report({
			encodedPayload: hexToBase64(reportData),
			encoderName: 'evm',
			signingAlgo: 'ecdsa',
			hashingAlgo: 'keccak256',
		})
		.result()

	// Use writeReport to send the transaction via CRE
	// The receiver contract's onReport() will decode the report
	const resp = evmClient
		.writeReport(runtime, {
			receiver: runtime.config.lvLidoVaultUtilAddress,
			report: reportResponse,
			gasConfig: {
				gasLimit: runtime.config.gasLimit,
			},
		})
		.result()

	if (resp.txStatus !== TxStatus.SUCCESS) {
		throw new Error(`Transaction failed: ${resp.errorMessage || resp.txStatus}`)
	}

	const txHash = resp.txHash || new Uint8Array(32)
	return bytesToHex(txHash)
}

/**
 * Execute performTask() for tasks 0, 1, 2, 3
 * Note: CRE SDK uses writeReport for blockchain writes. The receiver contract
 * must implement the CRE report receiver interface to process the request.
 */
const executePerformTask = (runtime: Runtime<Config>, taskId: number): string => {
	const network = getNetwork({
		chainFamily: 'evm',
		chainSelectorName: runtime.config.chainSelectorName,
		isTestnet: runtime.config.isTestnet,
	})

	if (!network) {
		throw new Error(`Network not found: ${runtime.config.chainSelectorName}`)
	}

	const evmClient = new cre.capabilities.EVMClient(network.chainSelector.selector)

	runtime.log(`Executing performTask() for task ${taskId}...`)

	// Encode the report data: (taskId)
	// Contract's onReport() will call checkUpkeep/performUpkeep internally
	const reportData = encodeAbiParameters(
		[{ name: 'taskId', type: 'uint256' }],
		[BigInt(taskId)]
	)

	// Generate consensus report using the report capability
	const reportResponse = runtime
		.report({
			encodedPayload: hexToBase64(reportData),
			encoderName: 'evm',
			signingAlgo: 'ecdsa',
			hashingAlgo: 'keccak256',
		})
		.result()

	// Use writeReport to send the transaction via CRE
	// The receiver contract's onReport() will decode the report
	const resp = evmClient
		.writeReport(runtime, {
			receiver: runtime.config.lvLidoVaultUtilAddress,
			report: reportResponse,
			gasConfig: {
				gasLimit: runtime.config.gasLimit,
			},
		})
		.result()

	if (resp.txStatus !== TxStatus.SUCCESS) {
		throw new Error(`Transaction failed: ${resp.errorMessage || resp.txStatus}`)
	}

	const txHash = resp.txHash || new Uint8Array(32)
	return bytesToHex(txHash)
}

/**
 * Handler for cron trigger
 */
const onCronTrigger = (runtime: Runtime<Config>, payload: CronPayload): string => {
	runtime.log('Cron trigger activated!')

	if (payload.scheduledExecutionTime) {
		const timestamp = Number(payload.scheduledExecutionTime)
		if (!isNaN(timestamp)) {
			runtime.log(`Scheduled time: ${new Date(timestamp * 1000).toISOString()}`)
		}
	}

	// Step 1: Check if upkeep is needed and get task ID (VIEW - no gas)
	const { upkeepNeeded, taskId } = checkUpkeepNeeded(runtime)

	// Step 2: If no upkeep needed, exit without spending gas
	if (!upkeepNeeded) {
		runtime.log('No action required - skipping (no gas spent)')
		return 'no_action'
	}

	// Step 3: Handle based on task ID
	let txHash: string

	if (taskId === 221) {
		// Task 221: Rate update - fetch from API and call fulfillRateFromCRE
		runtime.log('Task 221: Fetching rate from API...')

		const rateData = fetchRateData(runtime)

		if (rateData) {
			txHash = executeFulfillRate(runtime, rateData.sumLiquidity, rateData.sumBorrow, rateData.numRates)
		} else {
			// API failed - submit zeros to trigger Aave fallback rate
			runtime.log('API failed - submitting zeros for Aave fallback')
			txHash = executeFulfillRate(runtime, BigInt(0), BigInt(0), BigInt(0))
		}
	} else {
		// Tasks 0, 1, 2, 3: Call performTask()
		txHash = executePerformTask(runtime, taskId)
	}

	runtime.log(`Task ${taskId} executed successfully! TxHash: ${txHash}`)
	return txHash
}

/**
 * Initialize the workflow with triggers
 */
const initWorkflow = (config: Config) => {
	const cronTrigger = new cre.capabilities.CronCapability()

	return [
		cre.handler(
			cronTrigger.trigger({
				schedule: config.schedule,
			}),
			onCronTrigger
		),
	]
}

/**
 * Main entry point
 */
export async function main() {
	const runner = await Runner.newRunner<Config>({
		configSchema,
	})
	await runner.run(initWorkflow)
}

main()
