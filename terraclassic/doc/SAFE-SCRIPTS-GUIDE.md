# Safe CLI and Python Scripts Usage Guide

This guide explains how to install and use the official Safe CLI (Node.js) and also the alternative Python scripts to manage transactions in Safe multisig.

## 🚀 Quick Summary - Create and Execute Transaction

1. **Install:** `npm install -g @safe-global/safe-cli`
2. **Configure chain:** `safe config chains add` (Chain ID: 97, Short name: `tbnb`)
3. **Import wallet:** `safe wallet import --private-key 0xKEY --name "Wallet"`
4. **Open Safe:** `safe account open tbnb:0xYOUR_SAFE --name "Safe"`
5. **Create transaction:** `safe tx create` (provide to, value, data)
6. **Sign:** Choose "Yes" when asked
7. **Execute:** If you get GS013 error, use `cast` directly (see section [GS013 Error](#gs013-error-when-executing-transaction))

**⚠️ IMPORTANT:** 
- For BSC Testnet, you may need to execute via `cast` after approving the hash on-chain due to Safe CLI limitations without Safe Transaction Service configured.
- **To update Warp Route ISM:** The current ISM is immutable. You need to create a new ISM via factory and update the Warp Route (see [Example 1: Update ISM](#example-1-update-warp-route-ism)).

## 🎯 Official Safe CLI Installation (Recommended)

### ⚠️ Why use the Node.js version?

The Python Safe CLI (`safe-cli` via pip) **no longer works** because:
- The `safe-eth-py` package was removed/discontinued
- The Python Safe CLI depends on this package
- No available version contains the expected module
- The repository was discontinued

**✅ Solution: Use the official Node.js Safe CLI**

### 📦 Installation (100% Working)

#### Step 1: Remove any old installation (if any)

```bash
# Deactivate old Python virtualenv (if exists)
deactivate 2>/dev/null
rm -rf safe-cli-env
```

#### Step 2: Install the official Node.js CLI

```bash
npm install -g @safe-global/safe-cli
```

#### Step 3: Verify installation

```bash
safe --version
# or
safe version
```

**Expected output:**
```
safe-cli version 0.1.0
```

#### Step 4: Check available commands

```bash
safe help
```

**Saída esperada:**
```
Usage: safe [options] [command]

Modern CLI for Safe Smart Account management

Commands:
  config                  Manage CLI configuration
  wallet                  Manage wallets and signers
  account                 Manage Safe accounts
  tx                      Manage Safe transactions
  help [command]          display help for command
```

### 🔧 Basic Safe CLI Commands

**⚠️ IMPORTANT:** The Safe CLI uses the **EIP-3770** format: `shortName:address`

The format is: `shortName:0xADDRESS` (without `--address` or `--chain-id`)

#### 1. List available Safe accounts

```bash
safe account list
```

#### 2. Open/Add an existing Safe

**EIP-3770 format (recommended):**
```bash
safe account open shortName:0xYOUR_SAFE --name "Safe Name"
```

**Example for BSC Testnet:**
```bash
safe account open tbnb:0xa047DCd69249fd082B4797c29e5D80781Cb7f5ee --name "BSC Testnet Safe"
```

**Expected output:**
```
✓ Safe Added to Workspace!

Name:  BSC Testnet Safe

Safe Information:
  Address:  0xa047...f5ee
  Chain:    BSC Testnet
  Version:  1.4.1
  Owners:   2
  Threshold: 1 / 2
  Nonce:    0
  Balance:  0.0200 BNB

Safe ready to use
```

**Note:** Use the EIP-3770 format (`shortName:address`) to specify the chain correctly.

#### 3. Query complete Safe information

**Correct format (EIP-3770):**
```bash
safe account info shortName:0xYOUR_SAFE
```

**Examples:**
```bash
# BSC Mainnet (chain ID 56)
safe account info bnb:0xa047DCd69249fd082B4797c29e5D80781Cb7f5ee

# BSC Testnet (chain ID 97) - after adding the chain
safe account info tbnb:0xYOUR_SAFE

# Ethereum Mainnet
safe account info eth:0xYOUR_SAFE

# Sepolia Testnet
safe account info sep:0xYOUR_SAFE
```

**Returns:**
- Address
- Chain
- Status (Deployed/Not deployed)
- Version (contract version)
- Nonce (transaction counter)
- Owners
- Threshold (minimum number of approvals)
- Explorer (link to block explorer)

**JSON format (for auditing):**
```bash
safe account info bnb:0xYOUR_SAFE --json
```

#### 4. List transactions

```bash
# List all transactions
safe tx list

# List transactions from a specific Safe
safe tx list bnb:0xYOUR_SAFE
```

#### 5. View transaction status

```bash
safe tx status <SAFE_TX_HASH>
```

#### 6. Manage owners

```bash
# Add owner
safe account add-owner bnb:0xYOUR_SAFE 0xNEW_OWNER --threshold 2

# Remove owner
safe account remove-owner bnb:0xYOUR_SAFE 0xOWNER_TO_REMOVE

# Change threshold
safe account change-threshold bnb:0xYOUR_SAFE
```

#### 7. Manage transactions

**⚠️ IMPORTANT:** Before creating transactions, you need:
1. Have a wallet imported: `safe wallet import --private-key 0xKEY --name "Wallet"`
2. Have a Safe opened: `safe account open tbnb:0xYOUR_SAFE --name "Safe"`

```bash
# Create transaction (interactive)
safe tx create

# Sign transaction
safe tx sign <SAFE_TX_HASH>

# Execute transaction
safe tx execute <SAFE_TX_HASH>

# List Safe transactions
safe tx list tbnb:0xYOUR_SAFE

# View transaction status
safe tx status <SAFE_TX_HASH>
```

### 📝 Complete Process: Create and Execute Transaction

#### Step 1: Import Wallet

```bash
safe wallet import --private-key 0xYOUR_PRIVATE_KEY --name "My Wallet"
```

#### Step 2: Open Safe

```bash
safe account open tbnb:0xYOUR_SAFE --name "BSC Testnet Safe"
```

#### Step 3: Create Transaction

```bash
safe tx create
```

The CLI will open an interactive assistant. Follow the steps:

**3.1. Select Safe to create transaction for**
- The CLI will show available Safes
- Select the desired Safe (e.g., `BSC Testnet Safe (tbnb:0xa047DCd69249fd082B4797c29e5D80781Cb7f5ee)`)
- Press Enter

**3.2. To address (supports EIP-3770 format: shortName:address)**
- Enter the destination contract address
- Use EIP-3770 format: `tbnb:0x2b31a08d397b7e508cbE0F5830E8a9182C88b6cA`
- Press Enter

**Note:** If the contract is detected, the CLI will try to fetch the ABI automatically. If not found, it will continue with manual input.

**3.3. Value in wei (0 for token transfer)**
- For function calls, it's usually `0`
- Type `0` and press Enter

**3.4. Transaction data (hex)**
- Paste the calldata generated with `cast`
- Example: `0x46c9aba8000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000003000000000000000000000000242d8a855a8c932dec51f7999ae7d1e48b10c95e000000000000000000000000f620f5e3d25a3ae848fec74bccae5de3edcd87960000000000000000000000001f030345963c54ff8229720dd3a711c15c554aeb`
- Press Enter

**Generate calldata with cast (before creating the transaction):**
```bash
# Example: Update ISM
cast calldata "setInterchainSecurityModule(address)" 0xNEW_ISM

# Example: Pause contract
cast calldata "pause()"

# Example: Add validators (Hyperlane ISM Multisig)
# Correct signature: setValidators(uint32 domain, uint8 threshold, address[] validators)
cast calldata "setValidators(uint32,uint8,address[])" 97 2 "[0xADDR1,0xADDR2,0xADDR3]"
# Parameters: domain (97 for BSC Testnet), threshold (2), validators (array)
```

**3.5. Operation type**
- Choose between:
  - `Call` (Standard transaction call) - **Recommended for most cases**
  - `DelegateCall` - Use only if you know what you're doing
- Use arrows to select and press Enter

**3.6. Transaction nonce (leave empty for default)**
- Leave empty and press Enter (the CLI will use the current nonce automatically)
- Or enter a specific nonce if needed

**Expected output:**
```
✓ Transaction created successfully!

  Safe TX Hash: 0x90a0006f32b660ddeaa3f984010a59ded306529fb57e9acec2706a29d0301d08
```

**⚠️ IMPORTANT:** Save the **Safe TX Hash** - you'll need it for the next steps!

#### Step 4: Sign Transaction

After creating the transaction, the CLI will ask:

**"Would you like to sign this transaction now?"**
- Choose **Yes** (use arrows and press Enter)

The CLI will open the signing screen:

**4.1. Enter wallet password**
- If you set `SAFE_WALLET_PASSWORD`, the CLI will use it automatically
- Otherwise, type the wallet password and press Enter
- The password will not be displayed on screen (will appear as `▪▪▪▪▪▪▪▪▪▪▪`)

**To avoid typing the password every time, set the environment variable:**
```bash
export SAFE_WALLET_PASSWORD="your_password"
```

**Expected output:**
```
✓ Signature added (1/1 required)

✓ Transaction is ready to execute!
```

**Note:** If the threshold is greater than 1, you'll need other owners to also sign the transaction.

#### Step 5: Execute Transaction

After signing, the CLI will ask:

**"What would you like to do?"**
- **Execute transaction on-chain (Recommended)** - Tries to execute immediately
- **Push to Safe Transaction Service** - Only sends to the service (doesn't execute)
- **Skip for now** - Doesn't do anything now

Choose **Execute transaction on-chain**.

The CLI will show the transaction details and ask:

**"Execute this transaction on-chain?"**
- Choose **Yes**

You'll need to enter the wallet password again (or it will be used automatically if `SAFE_WALLET_PASSWORD` is set).

**⚠️ COMMON PROBLEM:** The Safe CLI may fail with **GS013** error when executing transactions on BSC Testnet when the Safe Transaction Service is not configured correctly or when there are issues with signature formatting.

**If the GS013 error occurs, use the solution below:**

**Solution:** Execute directly via `cast` after approving the hash on-chain:

##### 5.1. Approve Hash On-Chain

```bash
cast send 0xYOUR_SAFE "approveHash(bytes32)" <SAFE_TX_HASH> \
  --private-key 0xYOUR_PRIVATE_KEY \
  --rpc-url https://data-seed-prebsc-1-s1.binance.org:8545 \
  --legacy \
  --gas-price 100000000
```

##### 5.2. Verify Approval

```bash
cast call 0xYOUR_SAFE "approvedHashes(address,bytes32)(uint256)" \
  0xYOUR_ADDRESS 0xSAFE_TX_HASH \
  --rpc-url https://data-seed-prebsc-1-s1.binance.org:8545
```

Should return `1` if approved.

##### 5.3. Execute Transaction via Cast

```bash
cast send 0xYOUR_SAFE "execTransaction(address,uint256,bytes,uint8,uint256,uint256,uint256,address,address,bytes)" \
  0xTO_ADDRESS \
  0 \
  0xCALLDATA \
  0 \
  200000 \
  0 \
  100000000 \
  0x0000000000000000000000000000000000000000 \
  0x0000000000000000000000000000000000000000 \
  0x000000000000000000000000YOUR_ADDRESS000000000000000000000000000000000000000000000000000000000000000001 \
  --private-key 0xYOUR_PRIVATE_KEY \
  --rpc-url https://data-seed-prebsc-1-s1.binance.org:8545 \
  --legacy \
  --gas-price 100000000
```

**Important parameters:**
- `safeTxGas`: `200000` (or higher if needed)
- `gasPrice`: `100000000` (or the network minimum)
- `signatures`: Format `0x000000000000000000000000YOUR_ADDRESS000000000000000000000000000000000000000000000000000000000000000001`
  - Owner address (20 bytes)
  - `v = 0x01` (1 byte) when hash was approved via `approveHash`
  - `r` and `s` = zeros (64 bytes)

**⚠️ IMPORTANT - Common Problems:**

1. **"execution reverted" error after successful Safe execution:**
   - Verify if the Safe is the **owner** of the destination contract
   - If not, transfer ownership first: `cast send CONTRACT "transferOwnership(address)" 0xYOUR_SAFE --private-key 0xKEY --rpc-url URL`

2. **Incorrect function signature:**
   - For Hyperlane ISM Multisig, use: `setValidators(uint32,uint8,address[])`
   - **DO NOT** use: `setValidators(address[],uint8)` (incorrect signature)
   - Correct parameters: `domain` (uint32), `threshold` (uint8), `validators` (address[])

3. **Gas price error in cast:**
   - Use `--legacy` when using `--gas-price` to avoid conflicts with EIP-1559

**Complete example:**
```bash
# 1. Approve hash
cast send 0xa047DCd69249fd082B4797c29e5D80781Cb7f5ee \
  "approveHash(bytes32)" 0x90a0006f32b660ddeaa3f984010a59ded306529fb57e9acec2706a29d0301d08 \
  --private-key 0xYOUR_PRIVATE_KEY \
  --rpc-url https://data-seed-prebsc-1-s1.binance.org:8545 \
  --legacy \
  --gas-price 100000000

# 2. Execute (example with correct setValidators for Hyperlane ISM Multisig)
# Correct calldata: setValidators(uint32,uint8,address[])
cast send 0xa047DCd69249fd082B4797c29e5D80781Cb7f5ee \
  "execTransaction(address,uint256,bytes,uint8,uint256,uint256,uint256,address,address,bytes)" \
  0x63B2f9C469F422De8069Ef6FE382672F16a367d3 \
  0 \
  0xa50e0bb40000000000000000000000000000000000000000000000000000000000000061000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000003000000000000000000000000242d8a855a8c932dec51f7999ae7d1e48b10c95e000000000000000000000000f620f5e3d25a3ae848fec74bccae5de3edcd87960000000000000000000000001f030345963c54ff8229720dd3a711c15c554aeb \
  0 \
  200000 \
  0 \
  100000000 \
  0x0000000000000000000000000000000000000000 \
  0x0000000000000000000000000000000000000000 \
  0x0000000000000000000000008BD456605473ad4727ACfDCA0040a0dBD4be2DEA000000000000000000000000000000000000000000000000000000000000000001 \
  --private-key 0xYOUR_PRIVATE_KEY \
  --rpc-url https://data-seed-prebsc-1-s1.binance.org:8545 \
  --legacy \
  --gas-price 100000000
```

#### 8. Configure chains

```bash
# List configured chains
safe config chains list

# Add new chain
safe config chains add

# View current configuration
safe config show
```

### 📝 Practical Examples with Safe CLI

#### Example: Query multisig information on BSC Mainnet

```bash
# EIP-3770 format: shortName:address
safe account info bnb:0xa047DCd69249fd082B4797c29e5D80781Cb7f5ee
```

#### Example: List transactions from a Safe

```bash
safe tx list bnb:0xa047DCd69249fd082B4797c29e5D80781Cb7f5ee
```

#### Example: View transaction status

```bash
safe tx status 0x73b17378c1d8d5a48dd32dc483faa17aa6e23538ff5e68473f634b91cfe49367
```

#### Example: Add an owner

```bash
safe account add-owner bnb:0xYOUR_SAFE 0xNEW_OWNER --threshold 2
```

**⚠️ Note about BSC Testnet (Chain ID 97):**
- BSC Testnet may not be configured by default
- You'll need to add it using `safe config chains add` (see section [Configure Chains](#-configure-chains-add-bsc-testnet))
- After adding, use the chosen short name in EIP-3770 format (e.g., `tbnb:0xYOUR_SAFE`)

### 💡 Advantages of Node.js Safe CLI

- ✅ Works perfectly (officially maintained version)
- ✅ Queries contract directly (transparent and auditable)
- ✅ No problematic Python dependencies
- ✅ Simple and intuitive commands
- ✅ Support for multiple chains
- ✅ JSON format for automation

### ⚙️ Configure Chains (Add BSC Testnet)

By default, the Safe CLI comes with several chains configured, but may not include BSC Testnet (Chain ID 97). To add:

#### List configured chains

```bash
safe config chains list
```

#### Add BSC Testnet

Run the interactive command:

```bash
safe config chains add
```

**Values for BSC Testnet:**

When prompted, enter:

- **Chain ID:** `97`
- **Chain name:** `BSC Testnet`
- **Short name (EIP-3770):** `tbnb` (or another name of your preference, e.g., `bsc-testnet`)
- **RPC URL:** `https://data-seed-prebsc-1-s1.binance.org:8545`
- **Block explorer URL (optional):** `https://testnet.bscscan.com`
- **Native currency symbol:** `BNB`
- **Safe Transaction Service URL (optional):** `https://safe-transaction-bsc.safe.global` (use BSC Mainnet's, but may not work for testnet)

**Example output:**
```
✓ Chain Added Successfully!

Name:      BSC Testnet
Chain ID:  97

Chain configuration saved
```

**After adding, you can use:**
```bash
# Open Safe on BSC Testnet
safe account open tbnb:0xYOUR_SAFE --name "BSC Testnet Safe"

# Query Safe on BSC Testnet
safe account info tbnb:0xYOUR_SAFE

# List transactions
safe tx list tbnb:0xYOUR_SAFE
```

**Note:** The short name you choose (e.g., `tbnb`) will be used in EIP-3770 format to identify the chain.

#### Configure Safe Transaction Service (Optional)

**⚠️ IMPORTANT:** The Safe Transaction Service may not be available for BSC Testnet. If configured, you can use the BSC Mainnet URL, but it may not work correctly for testnet.

To add/edit the Transaction Service URL:

```bash
# Edit chain configuration
safe config chains edit
```

Look for chain ID 97 (BSC Testnet) and add:
```json
"transactionServiceUrl": "https://safe-transaction-bsc.safe.global"
```

**Note:** Even with the Transaction Service configured, you may need to execute transactions directly via `cast` due to limitations with BSC Testnet.

#### Verify configuration

```bash
# View all configured chains
safe config chains list

# View complete configuration
safe config show
```

---

## 📋 Python Scripts (Alternative)

If you prefer to use Python scripts or need specific functionality, you can use the Python scripts below. **Note:** These scripts depend on Python libraries that may have compatibility issues.

### 1. Install Python Dependencies (Optional)

```bash
# Install required Python libraries
pip3 install safe-eth-py web3 eth-account

# Verify installation
python3 -c "from safe_eth_py import Safe; print('✅ safe-eth-py installed')"
```

**⚠️ WARNING:** The `safe-eth-py` may not work correctly due to compatibility issues. We recommend using the Node.js Safe CLI above.

### 2. Have `cast` (Foundry) Installed

To encode function calls, you need `cast`:

```bash
# Check if cast is installed
cast --version

# If not, install Foundry:
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

## 🔧 Configuration

The scripts are configured to use:
- **Safe Address**: `0xa047DCd69249fd082B4797c29e5D80781Cb7f5ee`
- **RPC URL**: `https://data-seed-prebsc-1-s1.binance.org:8545` (BSC Testnet)

To change, edit the variables at the beginning of each script.

---

## 📝 Script 1: `safe-propose-direct.py` - Create Proposal

This script creates a new transaction proposal in the Safe.

### Syntax

```bash
python3 script/safe-propose-direct.py <PRIVATE_KEY> <TO_ADDRESS> <CALLDATA>
```

### Parameters

- **PRIVATE_KEY**: Owner's private key (with `0x`)
- **TO_ADDRESS**: Destination contract address (e.g., Warp Route)
- **CALLDATA**: Encoded function data (generated with `cast`)

### Complete Example

#### Step 1: Encode the Function

First, you need to encode the function call using `cast`:

```bash
# Example 1: Update ISM
CALLDATA=$(cast calldata "setInterchainSecurityModule(address)" 0xe4245cCB6427Ba0DC483461bb72318f5DC34d090)

# Example 2: Add validators (Hyperlane ISM Multisig)
# Correct signature: setValidators(uint32 domain, uint8 threshold, address[] validators)
CALLDATA=$(cast calldata "setValidators(uint32,uint8,address[])" 97 2 "[0x242d8a855a8c932dec51f7999ae7d1e48b10c95e,0xf620f5e3d25a3ae848fec74bccae5de3edcd8796,0x1f030345963c54ff8229720dd3a711c15c554aeb]")
# Parameters: domain (97 for BSC Testnet), threshold (2), validators (array of 3 addresses)

# Example 3: Pause contract
CALLDATA=$(cast calldata "pause()")

# Example 4: Unpause contract
CALLDATA=$(cast calldata "unpause()")
```

#### Step 2: Create the Proposal

```bash
# Replace with your actual values
python3 script/safe-propose-direct.py \
  0x819b680e3578eac4f79b8fde643046e... \
  0x2b31a08d397b7e508cbE0F5830E8a9182C88b6cA \
  $CALLDATA
```

### Expected Output

```
✅ Connected to BSC Testnet
   Chain ID: 97

✅ Account: 0x8BD456605473ad4727ACfDCA0040a0dBD4be2DEA
✅ Safe loaded: 0xa047DCd69249fd082B4797c29e5D80781Cb7f5ee

📝 Creating transaction proposal...
   To: 0x2b31a08d397b7e508cbE0F5830E8a9182C88b6cA
   Value: 0
   Data: 0xa50e0bb4...

✅ Safe transaction created!
   Safe TX Hash: 0xabc123def456...

🔐 Signing transaction off-chain...
✅ Transaction signed!

📤 Approving hash (creating proposal)...
================================================================================
✅ PROPOSAL CREATED SUCCESSFULLY!
================================================================================
TX_HASH: 0xf74c6109158ab607d7312a7ddfc7a541d1465fabe25b8ce57018fe7d9201cb72
Safe TX Hash: 0xabc123def456...

📋 Share the Safe TX Hash with other owners:
   0xabc123def456...

🔗 View on BscScan:
   https://testnet.bscscan.com/tx/0xf74c6109158ab607d7312a7ddfc7a541d1465fabe25b8ce57018fe7d9201cb72

💡 Next steps:
   1. Other owners should confirm using:
      python3 safe-confirm.py <PRIVATE_KEY> <SAFE_TX_HASH>
   2. After threshold reached, execute the transaction
================================================================================
```

**⚠️ IMPORTANT:** Save the **Safe TX Hash** - you'll need it for the next steps!

---

## ✅ Script 2: `safe-confirm.py` - Confirm Proposal

This script allows other owners to confirm an existing proposal.

### Syntax

```bash
python3 script/safe-confirm.py <PRIVATE_KEY> <SAFE_TX_HASH>
```

### Parameters

- **PRIVATE_KEY**: Private key of the owner confirming (with `0x`)
- **SAFE_TX_HASH**: The Safe transaction hash returned by the `safe-propose-direct.py` script

### Complete Example

```bash
# Owner 1 confirms (can be the same one who created the proposal)
python3 script/safe-confirm.py \
  0x819b680e3578eac4f79b8fde643046e... \
  0xabc123def4567890123456789012345678901234567890123456789012345678

# Owner 2 confirms (if threshold is 2 or more)
python3 script/safe-confirm.py \
  0x867f9CE9F0D7218b016351CB6122406E6D247a5e... \
  0xabc123def4567890123456789012345678901234567890123456789012345678
```

### Expected Output

```
✅ Connected to BSC Testnet
✅ Account: 0x8BD456605473ad4727ACfDCA0040a0dBD4be2DEA
✅ Safe loaded: 0xa047DCd69249fd082B4797c29e5D80781Cb7f5ee
📊 Threshold: 1
✅ Owners who have already approved: 1/1
   - 0x8BD456605473ad4727ACfDCA0040a0dBD4be2DEA

🔐 Confirming proposal...
================================================================================
✅ CONFIRMATION SENT!
================================================================================
TX_HASH: 0x1234567890abcdef...

🔗 View on BscScan:
   https://testnet.bscscan.com/tx/0x1234567890abcdef...

⏳ Waiting for confirmation...
✅ Confirmation confirmed!

📊 Current approvals: 2/2

🎉 THRESHOLD REACHED! The proposal is ready for execution!
   Execute with: python3 safe-execute.py <PRIVATE_KEY> <SAFE_TX_HASH>
================================================================================
```

---

## 🚀 Script 3: `safe-execute.py` - Execute Transaction

**⚠️ NOTE**: Executing Safe transactions via script is complex as it requires collecting all owner signatures. This script is currently just a placeholder.

### Options to Execute

#### Option 1: Use Web Interface (Recommended)

1. Access https://app.safe.global/
2. Connect your wallet (one of the owners)
3. Go to "Queue" or "History"
4. Find the pending transaction
5. Click "Execute"

#### Option 2: Use safe-eth-py Directly (Advanced)

You would need to create a custom script that:
1. Collects all owner signatures
2. Builds the transaction with all signatures
3. Executes using `safe_tx.execute()`

---

## 📚 Complete Practical Examples

### Example 1: Update Warp Route ISM

#### ⚠️ Why create a new ISM?

The current Warp Route ISM is typically a `StaticMessageIdMultisigIsm` (immutable), created via `StaticMessageIdMultisigIsmFactory`. This type of contract:

- **Cannot be updated**: Validators are defined at deployment and stored in the proxy metadata
- **Does not have `setValidatorsAndThreshold` function**: Attempting to call this function will result in an error
- **Does not have owner**: There is no `owner()` function because the contract is immutable

**Solution:** Create a new ISM via factory with the new validators and update the Warp Route to use the new ISM.

#### 📝 Note about Warp Route Owner

**When deploying the Warp Route:**
- The `owner` specified in the configuration file (`warp-config.yaml`) becomes the owner of the Warp Route contract
- **Recommendation:** Use the Safe address as owner in the configuration file:
  ```yaml
  bsctestnet:
    owner: "0xa047DCd69249fd082B4797c29e5D80781Cb7f5ee"  # Safe address
    # ... other configurations ...
  ```
- This allows the Safe to manage the Warp Route (update ISM, pause, etc.)
- **Verify current owner:**
  ```bash
  cast call 0xWARP_ROUTE_ADDRESS "owner()(address)" --rpc-url https://data-seed-prebsc-1-s1.binance.org:8545
  ```

#### Complete Process

To update the ISM validators, you need:
1. **Create a new ISM** via factory with the new validators
2. **Update the Warp Route** to use the new ISM

#### Step 1: Create New ISM via Factory

The `StaticMessageIdMultisigIsmFactory` factory creates immutable ISM contracts. Execute directly (not via Safe):

```bash
# Create new ISM with 3 validators and threshold 2
cast send 0x0D96aF0c01c4bbbadaaF989Eb489c8783F35B763 \
  "deploy(address[],uint8)" \
  "[0x242d8a855a8c932dec51f7999ae7d1e48b10c95e,0xf620f5e3d25a3ae848fec74bccae5de3edcd8796,0x1f030345963c54ff8229720dd3a711c15c554aeb]" \
  2 \
  --private-key 0xYOUR_PRIVATE_KEY \
  --rpc-url https://data-seed-prebsc-1-s1.binance.org:8545 \
  --legacy \
  --gas-price 100000000
```

**Expected output:**
```
status: 1 (success)
transactionHash: 0x...
```

**Get the new ISM address:**
```bash
# The factory returns the new contract address
cast call 0x0D96aF0c01c4bbbadaaF989Eb489c8783F35B763 \
  "deploy(address[],uint8)(address)" \
  "[0x242d8a855a8c932dec51f7999ae7d1e48b10c95e,0xf620f5e3d25a3ae848fec74bccae5de3edcd8796,0x1f030345963c54ff8229720dd3a711c15c554aeb]" \
  2 \
  --rpc-url https://data-seed-prebsc-1-s1.binance.org:8545
# Returns: 0xABeCf81b2Bd1E1d700E2f3B2ECcfb04e75dD7aB2 (example)
```

**Verify if the new ISM was created correctly:**
```bash
cast call 0xABeCf81b2Bd1E1d700E2f3B2ECcfb04e75dD7aB2 \
  "validatorsAndThreshold(bytes)(address[],uint8)" \
  0x \
  --rpc-url https://data-seed-prebsc-1-s1.binance.org:8545
# Should return the configured validators and threshold
```

#### Passo 2: Atualizar ISM no Warp Route

**⚠️ IMPORTANTE - Owner do Warp Route:**
Ao fazer o deploy do Warp Route usando `hyperlane warp deploy`, o `owner` especificado no arquivo de configuração (`warp-config.yaml`) se torna o owner do contrato Warp Route. Se você especificou o endereço do Safe como owner, então o Safe pode atualizar o ISM. Verifique o owner atual:

```bash
cast call 0x63B2f9C469F422De8069Ef6FE382672F16a367d3 \
  "owner()(address)" \
  --rpc-url https://data-seed-prebsc-1-s1.binance.org:8545
```

Agora atualize o Warp Route para usar o novo ISM. Você tem **duas opções**:

##### Opção A: Executar via Safe CLI (Recomendado quando funciona)

```bash
# 1. Gerar calldata para setInterchainSecurityModule
cast calldata "setInterchainSecurityModule(address)" 0xABeCf81b2Bd1E1d700E2f3B2ECcfb04e75dD7aB2
# Retorna: 0x0e72cc06000000000000000000000000abecf81b2bd1e1d700e2f3b2eccfb04e75dd7ab2

# 2. Criar transação no Safe
safe tx create
```

**Preencher os campos no Safe CLI:**

1. **Select Safe**: Escolha `BSC Testnet Safe (tbnb:0xa047DCd69249fd082B4797c29e5D80781Cb7f5ee)`

2. **To address**: 
   ```
   tbnb:0x63B2f9C469F422De8069Ef6FE382672F16a367d3
   ```
   (Endereço do contrato Warp Route)

3. **Value in wei**: 
   ```
   0
   ```

4. **Transaction data (hex)**: Cole o calldata gerado:
   ```
   0x0e72cc06000000000000000000000000abecf81b2bd1e1d700e2f3b2eccfb04e75dd7ab2
   ```

5. **Operation type**: `Call`

6. **Transaction nonce**: Deixe vazio (ou use o próximo nonce)

7. **Would you like to sign this transaction now?**: Choose `Yes` and provide the password

8. **What would you like to do?**: Choose `Execute transaction on-chain`

9. **Execute this transaction on-chain?**: Choose `Yes` and provide the password again

**Expected output (success):**
```
✓ Transaction Executed Successfully!

Tx Hash:  0x924d3e95cb44972e5ed08d0a119ede11a78a99c5a19f12a3c8329a04e87e22c1

Transaction confirmed on-chain
```

**Se der erro GS013:** Use a Opção B abaixo.

##### Opção B: Executar via Cast (Quando Safe CLI falha com GS013)

Se o Safe CLI falhar com erro GS013, você pode aprovar o hash e executar separadamente via `cast`:

**Passo 2.1: Criar e assinar transação no Safe CLI**

```bash
# Criar transação (mesmo processo da Opção A, mas NÃO execute)
safe tx create
# ... preencha os campos ...
# Quando perguntar "What would you like to do?", escolha "Exit" ou "Cancel"
# Salve o Safe TX Hash que foi gerado
```

**Exemplo de Safe TX Hash gerado:**
```
Safe TX Hash: 0xe27c3468f397c7ee4019f7ee3a839ba1c35f406542481ad8e8d971405374128a
```

**Passo 2.2: Aprovar Hash On-Chain via Cast**

```bash
# Aprovar o hash da transação no contrato Safe
cast send 0xa047DCd69249fd082B4797c29e5D80781Cb7f5ee \
  "approveHash(bytes32)" 0xe27c3468f397c7ee4019f7ee3a839ba1c35f406542481ad8e8d971405374128a \
  --private-key 0x819b680e3578eac4f79b8fde643046e88f3f9bb10a3ce1424e3642798ef39b42 \
  --rpc-url https://data-seed-prebsc-1-s1.binance.org:8545 \
  --legacy \
  --gas-price 100000000
```

**Verificar aprovação:**
```bash
cast call 0xa047DCd69249fd082B4797c29e5D80781Cb7f5ee \
  "approvedHashes(address,bytes32)(uint256)" \
  0x8BD456605473ad4727ACfDCA0040a0dBD4be2DEA \
  0xe27c3468f397c7ee4019f7ee3a839ba1c35f406542481ad8e8d971405374128a \
  --rpc-url https://data-seed-prebsc-1-s1.binance.org:8545
# Deve retornar: 1 (se aprovado)
```

**Passo 2.3: Executar Transação via Cast**

```bash
# Executar a transação diretamente via cast
cast send 0xa047DCd69249fd082B4797c29e5D80781Cb7f5ee \
  "execTransaction(address,uint256,bytes,uint8,uint256,uint256,uint256,address,address,bytes)" \
  0x63B2f9C469F422De8069Ef6FE382672F16a367d3 \
  0 \
  0x0e72cc06000000000000000000000000abecf81b2bd1e1d700e2f3b2eccfb04e75dd7ab2 \
  0 \
  200000 \
  0 \
  100000000 \
  0x0000000000000000000000000000000000000000 \
  0x0000000000000000000000000000000000000000 \
  0x0000000000000000000000008BD456605473ad4727ACfDCA0040a0dBD4be2DEA000000000000000000000000000000000000000000000000000000000000000001 \
  --private-key 0x819b680e3578eac4f79b8fde643046e88f3f9bb10a3ce1424e3642798ef39b42 \
  --rpc-url https://data-seed-prebsc-1-s1.binance.org:8545 \
  --legacy \
  --gas-price 100000000
```

**Parâmetros importantes:**
- `to`: `0x63B2f9C469F422De8069Ef6FE382672F16a367d3` (Warp Route address)
- `data`: `0x0e72cc06000000000000000000000000abecf81b2bd1e1d700e2f3b2eccfb04e75dd7ab2` (calldata for `setInterchainSecurityModule`)
- `safeTxGas`: `200000` (gas for internal execution)
- `gasPrice`: `100000000` (gas price on BSC Testnet)
- `signatures`: Special format when hash was approved via `approveHash`
  - Owner address: `0x8BD456605473ad4727ACfDCA0040a0dBD4be2DEA` (20 bytes)
  - `v = 0x01` (1 byte) - indicates hash approved
  - `r` and `s` = zeros (64 bytes)

**Expected output:**
```
status: 1 (success)
transactionHash: 0x...
```

**⚠️ Nota:** A Opção B é necessária quando o Safe CLI falha com erro GS013 na BSC Testnet. A Opção A (Safe CLI) é mais simples e deve ser tentada primeiro.

#### Process Summary

1. ✅ **Create new ISM** via factory (direct execution, not via Safe)
2. ✅ **Verify new ISM** (validators and threshold correct)
3. ✅ **Update Warp Route** via Safe CLI using `setInterchainSecurityModule(address)`
4. ✅ **Verify update** (optional: verify current ISM of Warp Route)

### Example 2: Add Validators

```bash
# 1. Encode function (Hyperlane ISM Multisig)
# Correct signature: setValidators(uint32 domain, uint8 threshold, address[] validators)
CALLDATA=$(cast calldata "setValidators(uint32,uint8,address[])" \
  97 \
  2 \
  "[0x242d8a855a8c932dec51f7999ae7d1e48b10c95e,0xf620f5e3d25a3ae848fec74bccae5de3edcd8796]")
# Parameters: domain (97 for BSC Testnet), threshold (2), validators (array)

# 2. Create proposal
python3 script/safe-propose-direct.py \
  0xOWNER1_PRIVATE_KEY \
  0xWARP_ROUTE_ADDRESS \
  $CALLDATA

# 3. Other owners confirm
python3 script/safe-confirm.py 0xOWNER2_PRIVATE_KEY <SAFE_TX_HASH>
```

### Example 3: Pause Warp Route

```bash
# 1. Encode pause function
CALLDATA=$(cast calldata "pause()")

# 2. Create proposal
python3 script/safe-propose-direct.py \
  0xOWNER1_PRIVATE_KEY \
  0xWARP_ROUTE_ADDRESS \
  $CALLDATA

# 3. Confirm and execute
```

---

## 🔍 How to Discover Contract Methods

### Method 1: Use BscScan

1. Access https://testnet.bscscan.com/address/0xWARP_ROUTE_ADDRESS
2. Click on the "Contract" tab
3. Click on "Read Contract" or "Write Contract"
4. See the available functions

### Method 2: Use `cast`

```bash
# List contract functions (if it has ABI)
cast interface 0xWARP_ROUTE_ADDRESS --rpc-url https://data-seed-prebsc-1-s1.binance.org:8545
```

### Method 3: Check Hyperlane Documentation

Consult the Hyperlane documentation for Warp Route contracts:
- https://docs.hyperlane.xyz/

---

## ⚠️ Troubleshooting

### Safe CLI doesn't work / Python installation error

**Problem:** The Python Safe CLI (`safe-cli` via pip) no longer works.

**Solution:** Use the official Node.js Safe CLI:

```bash
# Remove old Python installation
deactivate 2>/dev/null
rm -rf safe-cli-env

# Install official Node.js version
npm install -g @safe-global/safe-cli

# Verify
safe --version
```

### Error: "ModuleNotFoundError: No module named 'safe_eth_py'"

**If you're using Python scripts:**

```bash
# Install in the correct environment
pip3 install safe-eth-py web3 eth-account

# Or in a venv
python3 -m venv safe-env
source safe-env/bin/activate
pip install safe-eth-py web3 eth-account
```

**⚠️ Note:** Even after installing, `safe-eth-py` may not work due to compatibility issues. **We recommend using the Node.js Safe CLI** (see installation section above).

### Error: "Could not connect to RPC"

- Verify if the RPC URL is correct
- Try an alternative RPC:
  ```bash
  # For BSC Testnet, try:
  https://bsc-testnet.publicnode.com
  https://data-seed-prebsc-1-s1.binance.org:8545
  ```

### Error: "Error loading account"

- Verify if the private key is in the correct format (with `0x`)
- Make sure the private key has BNB for gas

### Error: "Threshold not reached"

- Check how many owners have already confirmed using:
  ```bash
  safe account info bnb:0xYOUR_SAFE
  ```
- Make sure all required owners have confirmed
- Check the transaction status:
  ```bash
  safe tx status <SAFE_TX_HASH>
  ```

### Error: "unknown option '--address'"

**Problem:** The Safe CLI does not use `--address` or `--chain-id` as options.

**Solution:** Use the EIP-3770 format: `shortName:address`

```bash
# ❌ WRONG
safe account info --address 0xYOUR_SAFE --chain-id 97

# ✅ CORRECT
safe account info bnb:0xYOUR_SAFE
```

### Error: GS013 when executing transaction

**Problem:** The Safe CLI fails to execute transactions on BSC Testnet with GS013 error.

**Cause:** The Safe CLI does not format signatures correctly when the Safe Transaction Service is not available for the chain.

**Solution:** Execute directly via `cast` after approving the hash on-chain:

1. **Approve hash on-chain:**
```bash
cast send 0xYOUR_SAFE "approveHash(bytes32)" <SAFE_TX_HASH> \
  --private-key 0xYOUR_PRIVATE_KEY \
  --rpc-url https://data-seed-prebsc-1-s1.binance.org:8545 \
  --legacy \
  --gas-price 100000000
```

2. **Verify approval:**
```bash
cast call 0xYOUR_SAFE "approvedHashes(address,bytes32)(uint256)" \
  0xYOUR_ADDRESS <SAFE_TX_HASH> \
  --rpc-url https://data-seed-prebsc-1-s1.binance.org:8545
```

3. **Execute via cast with correct parameters:**
```bash
cast send 0xYOUR_SAFE "execTransaction(address,uint256,bytes,uint8,uint256,uint256,uint256,address,address,bytes)" \
  0xTO_ADDRESS 0 0xCALLDATA 0 200000 0 100000000 \
  0x0000000000000000000000000000000000000000 \
  0x0000000000000000000000000000000000000000 \
  0x000000000000000000000000YOUR_ADDRESS000000000000000000000000000000000000000000000000000000000000000001 \
  --private-key 0xYOUR_PRIVATE_KEY \
  --rpc-url https://data-seed-prebsc-1-s1.binance.org:8545 \
  --legacy \
  --gas-price 100000000
```

**Important parameters:**
- `safeTxGas`: Use `200000` or higher
- `gasPrice`: Use `100000000` (or the network minimum)
- `signatures`: Format `address (20 bytes) + v (0x01) + r (32 bytes zeros) + s (32 bytes zeros)`

### Error: GS025 when executing transaction

**Problem:** Insufficient `safeTxGas`.

**Solution:** Increase the `safeTxGas` value to `200000` or higher.

### Error: "transaction gas price below minimum"

**Problem:** Gas price too low.

**Solution:** Specify a higher gas price:
```bash
cast send ... --gas-price 100000000
```

### Error: "execution reverted" in internal call

**Problem:** The Safe transaction was executed successfully, but the internal call to the destination contract reverted.

**Possible causes:**
1. The Safe is not the owner of the destination contract
2. The function does not exist or has a different signature
3. Invalid parameters (e.g., threshold greater than number of validators)
4. Some validation failed within the function

**How to verify:**

1. **Verify if the Safe is the owner:**
```bash
# Try different variations of the owner function
cast call 0xCONTRACT "owner()" --rpc-url https://data-seed-prebsc-1-s1.binance.org:8545
cast call 0xCONTRACT "getOwner()" --rpc-url https://data-seed-prebsc-1-s1.binance.org:8545
cast call 0xCONTRACT "owner(address)" 0xYOUR_SAFE --rpc-url https://data-seed-prebsc-1-s1.binance.org:8545
```

2. **Verify if the function exists:**
```bash
# Check the contract code on BscScan
# https://testnet.bscscan.com/address/0xCONTRACT#code
```

3. **Verify the parameters:**
- Threshold cannot be greater than the number of validators
- Addresses must be valid
- Function must exist in the contract

**Solution:**
- Check on BscScan if the Safe is the owner of the contract
- Confirm that the function exists and has the correct signature
- Verify if the parameters are correct
- If necessary, transfer ownership to the Safe first

### How to find the shortName of a chain

```bash
# List all configured chains
safe config chains list

# View complete configuration
safe config show
```

Common shortNames:
- BSC Mainnet (56): `bnb`
- BSC Testnet (97): `tbnb` (or another name you choose when adding)
- Ethereum Mainnet (1): `eth`
- Sepolia Testnet (11155111): `sep`

**To add BSC Testnet, see the [Configure Chains](#-configure-chains-add-bsc-testnet) section**

### Safe CLI command not found

If the `safe` command is not found after installation:

```bash
# Check if npm is installed
npm --version

# Check if npm global path is in PATH
npm config get prefix

# Add to PATH if necessary (add to ~/.bashrc or ~/.zshrc)
export PATH="$(npm config get prefix)/bin:$PATH"
```

---

## 📝 Usage Checklist

### For Node.js Safe CLI (Recommended)

- [ ] Node.js and npm installed
- [ ] Safe CLI installed (`npm install -g @safe-global/safe-cli`)
- [ ] Safe CLI working (`safe --version`)
- [ ] BSC Testnet chain configured (`safe config chains add`)
- [ ] Wallet imported (`safe wallet import`)
- [ ] Safe opened in CLI (`safe account open`)
- [ ] Safe address known
- [ ] Correct Chain ID (97 for BSC Testnet, 56 for BSC Mainnet)
- [ ] `cast` installed (Foundry) to generate calldata and execute when needed

### For Python Scripts (Alternative)

- [ ] Python dependencies installed (`safe-eth-py`, `web3`, `eth-account`)
- [ ] `cast` installed (Foundry)
- [ ] Owner private keys available
- [ ] Accounts have sufficient BNB for gas
- [ ] Destination contract address known
- [ ] Function to be called identified
- [ ] Calldata generated with `cast`
- [ ] Safe TX Hash saved after creating proposal
- [ ] All owners confirmed (threshold reached)
- [ ] Transaction executed (via web or script)

---

## 🔗 Useful Links

- **Safe CLI Node.js (Official)**: https://www.npmjs.com/package/@safe-global/safe-cli
- **Safe Web Interface**: https://app.safe.global/
- **BscScan Testnet**: https://testnet.bscscan.com
- **BscScan Mainnet**: https://bscscan.com
- **Hyperlane Docs**: https://docs.hyperlane.xyz/
- **Foundry (cast)**: https://book.getfoundry.sh/
- **Node.js**: https://nodejs.org/

---

## 💡 Tips

1. **Always test on testnet first** before using on mainnet
2. **Save the Safe TX Hash** - you'll need it to confirm and execute
3. **Check the Safe threshold** before creating proposals
4. **Use a password manager** to store private keys securely
5. **Check BNB balance** before creating proposals (needs gas)
6. **Confirm function names** in the contract before encoding
7. **For BSC Testnet**, be prepared to execute via `cast` if Safe CLI fails with GS013

## 📋 Complete Flow Summary

### Initial Setup (Once)

```bash
# 1. Install Safe CLI
npm install -g @safe-global/safe-cli

# 2. Add BSC Testnet
safe config chains add
# Enter: Chain ID: 97, Name: BSC Testnet, Short name: tbnb, RPC: https://data-seed-prebsc-1-s1.binance.org:8545

# 3. Import wallet
safe wallet import --private-key 0xYOUR_PRIVATE_KEY --name "My Wallet"

# 4. Open Safe
safe account open tbnb:0xYOUR_SAFE --name "BSC Testnet Safe"
```

### Create and Execute Transaction

```bash
# 1. Generate calldata
CALLDATA=$(cast calldata "functionName(type)" parameter)

# 2. Create transaction
safe tx create
# Enter: to (tbnb:0xADDRESS), value (0), data ($CALLDATA), operation (Call), nonce (empty)

# 3. Sign (when asked, choose Yes)
# Set password: export SAFE_WALLET_PASSWORD="your_password"

# 4. If execution fails with GS013, execute via cast:
# 4.1. Approve hash on-chain
cast send 0xYOUR_SAFE "approveHash(bytes32)" <SAFE_TX_HASH> \
  --private-key 0xYOUR_PRIVATE_KEY \
  --rpc-url https://data-seed-prebsc-1-s1.binance.org:8545 \
  --legacy \
  --gas-price 100000000

# 4.2. Execute transaction
cast send 0xYOUR_SAFE "execTransaction(address,uint256,bytes,uint8,uint256,uint256,uint256,address,address,bytes)" \
  0xTO_ADDRESS 0 0xCALLDATA 0 200000 0 100000000 \
  0x0000000000000000000000000000000000000000 \
  0x0000000000000000000000000000000000000000 \
  0x000000000000000000000000YOUR_ADDRESS000000000000000000000000000000000000000000000000000000000000000001 \
  --private-key 0xYOUR_PRIVATE_KEY \
  --rpc-url https://data-seed-prebsc-1-s1.binance.org:8545 \
  --legacy \
  --gas-price 100000000
```

