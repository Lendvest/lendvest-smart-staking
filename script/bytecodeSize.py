# SPDX-License-Identifier: BUSL-1.1
# Author: Lendvest
'''import json
import os

# Get the directory where this script is located
script_dir = os.path.dirname(os.path.abspath(__file__))
# Construct the path to the JSON file relative to the script location
json_path = os.path.join(os.path.dirname(script_dir), 'out', 'LVLidoVault.sol', 'LVLidoVault.json')
json_path_util = os.path.join(os.path.dirname(script_dir), 'out', 'LVLidoVaultUtil.sol', 'LVLidoVaultUtil.json')
json_path_liquidation_proxy = os.path.join(os.path.dirname(script_dir), 'out', 'LiquidationProxy.sol', 'LiquidationProxy.json')
json_path_lvweth = os.path.join(os.path.dirname(script_dir), 'out', 'LVWETH.sol', 'LVWETH.json')
json_path_lvtoken = os.path.join(os.path.dirname(script_dir), 'out', 'LVToken.sol', 'LVToken.json')
# Check if file exists
if not os.path.exists(json_path):
    print(f"Error: File not found in directory: {json_path}")
    exit(1)
if not os.path.exists(json_path_util):
    print(f"Error: File not found in directory: {json_path_util}")
    exit(1)
if not os.path.exists(json_path_liquidation_proxy):
    print(f"Error: File not found in directory: {json_path_liquidation_proxy}")
    exit(1)
if not os.path.exists(json_path_lvweth):
    print(f"Error: File not found in directory: {json_path_lvweth}")
    exit(1)
if not os.path.exists(json_path_lvtoken):
    print(f"Error: File not found in directory: {json_path_lvtoken}")
    exit(1)

# Read the JSON file
with open(json_path, 'r') as f:
    data = json.load(f)

with open(json_path_util, 'r') as f:    
    data_util = json.load(f)

with open(json_path_liquidation_proxy, 'r') as f:
    data_liquidation_proxy = json.load(f)

with open(json_path_lvweth, 'r') as f:
    data_lvweth = json.load(f)

with open(json_path_lvtoken, 'r') as f:
    data_lvtoken = json.load(f)
    
# Get the bytecode from the JSON (nested under bytecode.object)
bytecode = data.get('bytecode', {}).get('object', '')
bytecode_util = data_util.get('bytecode', {}).get('object', '')
bytecode_liquidation_proxy = data_liquidation_proxy.get('bytecode', {}).get('object', '')
bytecode_lvweth = data_lvweth.get('bytecode', {}).get('object', '')
bytecode_lvtoken = data_lvtoken.get('bytecode', {}).get('object', '')
if not bytecode:
    print("Error: No bytecode found in the JSON file")
    exit(1)
if not bytecode_util:
    print("Error: No bytecode found in the JSON file")
    exit(1)
if not bytecode_liquidation_proxy:
    print("Error: No bytecode found in the JSON file")
    exit(1)
if not bytecode_lvweth:
    print("Error: No bytecode found in the JSON file")
    exit(1)
if not bytecode_lvtoken:
    print("Error: No bytecode found in the JSON file")
    exit(1)
# Calculate the size (subtract 2 for '0x' prefix and divide by 2 for hex characters)
size = (len(bytecode) - 2) // 2
size_util = (len(bytecode_util) - 2) // 2
size_liquidation_proxy = (len(bytecode_liquidation_proxy) - 2) // 2
size_lvweth = (len(bytecode_lvweth) - 2) // 2
size_lvtoken = (len(bytecode_lvtoken) - 2) // 2
print(f"Bytecode size of LVLidoVault: {size} bytes")
print(f"Bytecode size of LVLidoVaultUtil: {size_util} bytes")
print(f"Bytecode size of LiquidationProxy: {size_liquidation_proxy} bytes")
print(f"Bytecode size of LVWETH: {size_lvweth} bytes")
print(f"Bytecode size of LvToken: {size_lvtoken} bytes")
print("--------------------------------")
print(f"Total bytecode size: {size + size_util + size_liquidation_proxy + size_lvweth + size_lvtoken} bytes")
print("--------------------------------")
'''
import json
import os
import requests
from web3 import Web3
from dotenv import load_dotenv

# Load environment variables from .env file
load_dotenv()
ETHEREUM_RPC = os.getenv("RPC_URL")

if not ETHEREUM_RPC:
    print("Error: ETHEREUM_RPC not set in .env file")
    exit(1)

# Setup Web3 and constants
web3 = Web3(Web3.HTTPProvider(ETHEREUM_RPC))
GAS_PER_BYTE = 200  # Conservative estimate of gas per byte for deployment

# Fetch gas price in gwei and convert to wei
gas_price_wei = web3.eth.gas_price
gas_price_gwei = gas_price_wei / 1e9
print(f"Current gas price: {gas_price_gwei:.2f} gwei")

# Optional: Fetch ETH price from CoinGecko
def fetch_eth_price():
    try:
        res = requests.get("https://api.coingecko.com/api/v3/simple/price?ids=ethereum&vs_currencies=usd")
        return res.json()['ethereum']['usd']
    except:
        return None

eth_price_usd = fetch_eth_price()
if eth_price_usd:
    print(f"ETH price (USD): ${eth_price_usd:.2f}")
else:
    print("Warning: Could not fetch ETH price from CoinGecko")

# Load JSON file paths
script_dir = os.path.dirname(os.path.abspath(__file__))
base_out = os.path.join(os.path.dirname(script_dir), 'out')

json_files = {
    "LVLidoVault": 'LVLidoVault.sol/LVLidoVault.json',
    "LVLidoVaultUtil": 'LVLidoVaultUtil.sol/LVLidoVaultUtil.json',
    "LiquidationProxy": 'LiquidationProxy.sol/LiquidationProxy.json',
    "LVWETH": 'LVWETH.sol/LVWETH.json',
    "LVToken": 'LVToken.sol/LVToken.json'
}

total_size = 0
print("--------------------------------")
for name, path in json_files.items():
    full_path = os.path.join(base_out, path)
    if not os.path.exists(full_path):
        print(f"Error: {name} file not found at {full_path}")
        exit(1)
    
    with open(full_path, 'r') as f:
        data = json.load(f)
    
    bytecode = data.get('bytecode', {}).get('object', '')
    if not bytecode:
        print(f"Error: No bytecode in {name}")
        exit(1)

    size = (len(bytecode) - 2) // 2
    total_size += size
    gas_estimate = size * GAS_PER_BYTE
    cost_in_eth = web3.from_wei(gas_estimate * gas_price_wei, 'ether')
    cost_in_usd = float(cost_in_eth) * eth_price_usd if eth_price_usd else None
    
    print(f"{name}:")
    print(f"  Bytecode size: {size} bytes")
    print(f"  Estimated Gas: {gas_estimate:,} units")
    print(f"  Estimated Cost: {cost_in_eth:.6f} ETH", end="")
    if cost_in_usd:
        print(f" (${cost_in_usd:.2f})")
    else:
        print()
    print()

print("--------------------------------")
print(f"Total bytecode size: {total_size} bytes")
print(f"Total estimated gas: {total_size * GAS_PER_BYTE:,} units")