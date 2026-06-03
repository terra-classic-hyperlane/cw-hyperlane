# 📘 Complete Guide: Hyperlane Deployment and Configuration on Terra Classic Mainnet

This guide documents the complete process of deploying and configuring Hyperlane contracts on Terra Classic Mainnet (columbus-5).

---

## 📋 Table of Contents

1. [Prerequisites](#prerequisites)
   - [Generating a Private Key in Hex Format](#generating-a-private-key-in-hex-format)
2. [Verify Available Contracts](#verify-available-contracts)
3. [Contract Deployment (Upload)](#contract-deployment-upload)
4. [Contract Instantiation](#contract-instantiation)
5. [Configuration via Governance](#configuration-via-governance)
6. [Execution Verification](#execution-verification)
7. [Contract Addresses and Hexed](#contract-addresses-and-hexed)
8. [Troubleshooting](#troubleshooting)

---

## 🔧 Prerequisites

### System Requirements

- **Node.js**: v18+ or v20+
- **Yarn**: v4.1.0+
- **Terra Classic Mainnet Node**: Access to public RPC
- **Wallet**: Private key configured with LUNC for gas

### Environment Variables

```bash
export PRIVATE_KEY="your_private_key_hexadecimal"
```

### Install Dependencies

```bash
cd cw-hyperlane
yarn install
```

---

### Generating a Private Key in Hex Format

The deployment and instantiation scripts require a **32-byte private key in hexadecimal format** (64 hex characters prefixed with `0x`).

---

#### Terra Classic (Cosmos / `terrad`)

**Step 1 — Install `terrad`**

```bash
TERRA_VERSION="v3.0.1"
wget https://github.com/classic-terra/core/releases/download/${TERRA_VERSION}/terrad-${TERRA_VERSION}-linux-amd64
chmod +x terrad-${TERRA_VERSION}-linux-amd64
sudo mv terrad-${TERRA_VERSION}-linux-amd64 /usr/local/bin/terrad
terrad version
```

**Step 2 — List existing keys**

```bash
terrad keys list --keyring-backend file
```

**Step 3 — Generate a new key (if needed)**

```bash
terrad keys add deployer-key --keyring-backend file
```

> Save the 24-word mnemonic phrase immediately — it is the only way to recover the wallet.

**Step 4 — Export the private key in hex**

```bash
terrad keys export deployer-key --keyring-backend file --unarmored-hex --unsafe
```

**Step 5 — Save with `0x` prefix**

```bash
echo "0x$(terrad keys export deployer-key --keyring-backend file --unarmored-hex --unsafe)" \
  > ~/.terra-private-key
chmod 600 ~/.terra-private-key
```

**Step 6 — Get the Terra address**

```bash
terrad keys show deployer-key --keyring-backend file --address
```

**Step 7 — Set the environment variable**

```bash
export PRIVATE_KEY="0xYOUR_64_CHAR_HEX_KEY"
```

**Import an existing key from mnemonic:**

```bash
terrad keys add deployer-key --recover --keyring-backend file
```

---

#### Ethereum / BSC (EVM — `cast`)

```bash
# Install Foundry
curl -L https://foundry.paradigm.xyz | bash && foundryup

# Generate new key
cast wallet new
# Output: Private Key + Address
```

#### Solana (`solana-keygen`)

```bash
# Install
sh -c "$(curl -sSfL https://release.solana.com/stable/install)"

# Generate keypair
solana-keygen new --outfile ./solana-keypair.json

# Extract private key as hex (first 32 bytes)
python3 << 'EOF'
import json
with open('./solana-keypair.json') as f:
    kp = json.load(f)
print(f"0x{bytes(kp[:32]).hex()}")
EOF
```

**Validate your key:**

```bash
echo "0xYOUR_KEY" | wc -c
# Must return 67  (= 0x + 64 chars + newline)
```

> Never commit private keys to Git. Use `chmod 600` on all files containing keys.

---

## 1️⃣ Verify Available Contracts

Before deploying, verify which contracts are available in the remote repository:

```bash
yarn cw-hpl upload remote-list -n terraclassic
```

---

## 2️⃣ Contract Deployment (Upload)

### Upload to Blockchain

```bash
yarn cw-hpl upload remote v0.0.6-rc8 -n terraclassic
```

**What this command does:**
- 📥 **Downloads WASM files** from GitHub release
- 📤 Uploads to Terra Classic Mainnet blockchain (columbus-5)
- 💾 Stores the `code_id` of each contract
- 📝 Saves IDs in the context file (`context/terraclassic.json`)

### Contract Hashes (For Auditing)

The SHA-256 hashes below were generated during the mainnet upload and are **crucial for integrity verification**:

| Contract | SHA-256 Hash | Code ID | TX Hash |
|----------|--------------|---------|---------|
| **hpl_mailbox** | `b6d789c1a31ee79548fd736bad241dbcd3b8b319d66a776f31479743fe49eb01` | 11371 | `EE52306E16EB9A3D434219ECA0BDF838761B6ED7FDA4EBCA27E6072EAF7F3246` |
| **hpl_validator_announce** | `c3c42fda7aabb73ab59a6dba75e20a905a310f8876e801451fcebf1599e8167d` | 11372 | `EA29FACCCDFED7F54E5C7CC28E631C9DCD6EF3B6711BDED6611C6D6062E3C435` |
| **hpl_ism_aggregate** | `e33ccca03a9366c4020900e562febcd8311fc3449687ec876cc7ea8b84767f4f` | 11373 | `7DD1BDB4EC4B57DBAC835087E1328EB6B201EF07BB5C4C5850A92A9FE3B615AA` |
| **hpl_ism_multisig** | `32b07207c733ba7469f49d321c30cf00bacb8c9560dc92accd35df61e5e3a531` | 11374 | `B0F1C5CF22F5A55185E9CC79DFBF1DB97681BABAFC98ECC7F16F1EFF5AB3C1D1` |
| **hpl_ism_pausable** | `31fff431baa0d752f3f9f6c63400bef9c69363cff16d9064a1882fd697b0cacb` | 11375 | `6F5283B1D2FF2C2F8AB3E3F7209A3BDBA4E5916621B2C596A7A2946D07696A58` |
| **hpl_ism_routing** | `0881d65f470425290990e53b87044477eaf704e0f2da8481eb4150c6e8c8143c` | 11376 | `523D8DD5AADDFD533F8C61AC651F6DAC76E88E8625FE9364D8035381912E1A9A` |
| **hpl_igp** | `34313c90c9e08d2c342061412fafe4d064ad783f9be606255d0720590e6fad0b` | 11377 | `C81D18B9C7729209D379E929B85BFBC2FAF410748ADCF6F320541CFFBF19686E` |
| **hpl_hook_aggregate** | `9dfbe1ba3e0dde5ea82cb0daee819214e46afb2ac78075c4f26523e6879a5004` | 11378 | `97814830E9459ABE12A99C82F8B6D65AF28282EDEB1B56B5C27BA83A0F51F681` |
| **hpl_hook_fee** | `c981467b9af207d09aac90716598ed51c547526b8b82189148a24e1704e7956e` | 11379 | `4E08DA612B3E89AC5CA71CF3B4099B3B1B5800190B814EF65F92A7327B839C51` |
| **hpl_hook_merkle** | `f4258979caf115b1957a13f6b7ec59161b837e07b90828c2e6fc9e4e61e9f156` | 11380 | `F8004659796F3EED60623944C4A9C6938975FF72B0D626BE379BC994B7058D29` |
| **hpl_hook_pausable** | `0f53c4193be46b15eca53ff8cb2004dcc571bf74b345b2b7af2775b6fa99b6c2` | 11381 | `0694354D4312B965F45D4ED14372925D23AD6F0F1A217245E9EDFCFECE699F85` |
| **hpl_hook_routing** | `ff11e7535f07cb20123735b61f31bf1b60a428f67cb332faf64a2b7641d11ed3` | 11382 | `6799A20AFD9C69F7D3BB41B078EE4FBDC5241CC0B41C192721F9325B2A66696A` |
| **hpl_hook_routing_custom** | `34c947fbf2cc37df33237ab062265520fc28d5427745c669631590f22fd9d534` | 11383 | `56300AD82FB441094678272A34B1AF131AC69DF04277242FD17C1758F797E574` |
| **hpl_hook_routing_fallback** | `b4930c213cae2728b83ffee876d0d880030ed079cc0167fd7e69c98880315f89` | 11384 | `8B18DB2D65A81F40A4AB896E9C58E3BB9C251B272928575EC787EA13B20838D0` |
| **hpl_test_mock_hook** | `8dcdf5f9ef0f7632404b5310b9ed37e091c9854d6fe5e4c38ae3424948a9d3a1` | 11385 | `04F546649FC718DCBA701A9767395CEBD120C3DED9A266EE723F9751F60923D7` |
| **hpl_test_mock_ism** | `e283df5977a897e0c33f47540f2d50f43f735dfe6f31ef2614aefff225af8c8f` | 11386 | `EBEB7221C86FAD9C1449713357F78B14E10510AC87C0A46D0BC1EA717ABC4017` |
| **hpl_test_mock_msg_receiver** | `aa7fca1213b164cb1e8a1beefe32dce6d31f7ebe8add4b568db49283bbdb43af` | 11387 | `E1F27D012F1575BC54A4E0A2714FC1A967789BAA5210FCCF6515868D3F56579B` |
| **hpl_igp_oracle** | `3b0143755d322a7a8bcd2e6081c8a22f817644c557c85cfd4d570d69e08de1fc` | 11388 | `C367D2C70F87D6B10F3CFCF7B3105BCA774C22890B67CE69BB4F36DA759B7E9D` |
| **hpl_warp_cw20** | `25b100c1c1bec141c90f4fc0e556b52025921403d7ae2d25bad8cfec35c74be7` | 11389 | `AD2C0B4E55BA7A3D4817DE9D95CA17A3E6D9B72A61F70B98485C39412D778926` |
| **hpl_warp_native** | `34b5deb86937f51d4b04ddc572597b95ffd1b3ce094df8a73dc1cf20babc7e55` | 11390 | `F5BCFCDE48617B6B4A70E57B7F0B5376FC3B192B343D0A203F46F8627CF54D2D` |

#### 🔒 Integrity Verification

**Method 1: Verify against blockchain**

```bash
# Download WASM from code ID (example: hpl_mailbox with code_id 11371)
terrad query wasm code 11371 download.wasm \
  --node https://rpc.terra-classic.hexxagon.io:443 \
  --chain-id columbus-5

# Calculate SHA-256 hash
sha256sum download.wasm
# Expected: b6d789c1a31ee79548fd736bad241dbcd3b8b319d66a776f31479743fe49eb01
```

**Method 2: Verify against official release**

```bash
wget https://github.com/many-things/cw-hyperlane/releases/download/v0.0.6-rc8/cw-hyperlane-v0.0.6-rc8.zip
unzip cw-hyperlane-v0.0.6-rc8.zip
sha256sum -c checksums.txt
```

### Verify Code IDs

```bash
cat context/terraclassic.json
```

**Mainnet Code IDs:**
```json
{
  "artifacts": {
    "hpl_mailbox": 11371,
    "hpl_validator_announce": 11372,
    "hpl_ism_aggregate": 11373,
    "hpl_ism_multisig": 11374,
    "hpl_ism_pausable": 11375,
    "hpl_ism_routing": 11376,
    "hpl_igp": 11377,
    "hpl_hook_aggregate": 11378,
    "hpl_hook_fee": 11379,
    "hpl_hook_merkle": 11380,
    "hpl_hook_pausable": 11381,
    "hpl_hook_routing": 11382,
    "hpl_hook_routing_custom": 11383,
    "hpl_hook_routing_fallback": 11384,
    "hpl_test_mock_hook": 11385,
    "hpl_test_mock_ism": 11386,
    "hpl_test_mock_msg_receiver": 11387,
    "hpl_igp_oracle": 11388,
    "hpl_warp_cw20": 11389,
    "hpl_warp_native": 11390
  }
}
```

### Governance Module Address

```bash
# The governance module address on Terra Classic (mainnet and testnet):
terra10d07y265gmmuvt4z0w9aw880jnsr700juxf95n
```

---

## 3️⃣ Contract Instantiation

### Script: `CustomInstantiateWasm-mainnet.ts`

This script instantiates all contracts on the blockchain with their initial configurations.

> **Note:** The script is located at `terraclassic/CustomInstantiateWasm-mainnet.ts`.
> Run it from the **project root** (`/home/lunc/tc-cw-hyperlane`) to ensure Node.js dependencies are resolved correctly.

#### Execute Instantiation

```bash
cd /home/lunc/tc-cw-hyperlane
PRIVATE_KEY="0xYOUR_HEX_KEY" yarn tsx terraclassic/CustomInstantiateWasm-mainnet.ts
```

#### Script Configuration

The script is configured with:
- **RPC**: `https://rpc.terra-classic.hexxagon.io`
- **Chain ID**: `columbus-5`
- **Owner**: deployer wallet (transfer to governance after deployment — see `doc/TRANSFER-OWNERSHIP-TO-GOVERNANCE.md`)
- **Gas Price**: `28.5uluna`

### 📋 Instantiated Contracts

The script instantiates **14 contracts** supporting **3 chains** (Ethereum, BSC, Solana):

---

#### 1. 📮 MAILBOX - Main Cross-Chain Messaging Contract

```json
{
  "hrp": "terra",
  "domain": 1325,
  "owner": "YOUR_DEPLOYER_ADDRESS"
}
```

**Code ID:** `11371`  
**Instantiated Address:** `[TO BE FILLED AFTER INSTANTIATION]`

---

#### 2. 📢 VALIDATOR ANNOUNCE - Validator Registry

```json
{
  "hrp": "terra",
  "mailbox": "<MAILBOX_ADDRESS>"
}
```

**Code ID:** `11372`  
**Instantiated Address:** `[TO BE FILLED AFTER INSTANTIATION]`

---

#### 3. 🔐 ISM MULTISIG #1 - For Ethereum (Domain 1)

```json
{ "owner": "YOUR_DEPLOYER_ADDRESS" }
```

**Code ID:** `11374`  
**Validators (official mainnet — 6 of 9):**
- `03c842db86a6a3e524d4a6615390c1ea8e2b9541` — Abacus Works
- `94438a7de38d4548ae54df5c6010c4ebc5239eae` — DSRV
- `5450447aee7b544c462c9352bef7cad049b0c2dc` — Zee Prime
- `b3ac35d3988bca8c2ffd195b1c6bee18536b317b` — Staked
- `b683b742b378632a5f73a2a5a45801b3489bba44` — AVS: Luganodes
- `3786083ca59dc806d894104e65a13a70c2b39276` — Imperator
- `4f977a59fdc2d9e39f6d780a84d5b4add1495a36` — Mitosis
- `29d783efb698f9a2d3045ef4314af1f5674f52c5` — Substance Labs
- `36a669703ad0e11a0382b098574903d2084be22c` — Enigma

**Instantiated Address:** `[TO BE FILLED AFTER INSTANTIATION]`

---

#### 4. 🔐 ISM MULTISIG #2 - For BSC (Domain 56)

```json
{ "owner": "YOUR_DEPLOYER_ADDRESS" }
```

**Code ID:** `11374`  
**Validators (official mainnet — 4 of 6):**
- `570af9b7b36568c8877eebba6c6727aa9dab7268` — Abacus Works
- `5450447aee7b544c462c9352bef7cad049b0c2dc` — Zee Prime
- `0d4c1394a255568ec0ecd11795b28d1bda183ca4` — Tessellated
- `24c1506142b2c859aee36474e59ace09784f71e8` — Substance Labs
- `c67789546a7a983bf06453425231ab71c119153f` — Luganodes
- `2d74f6edfd08261c927ddb6cb37af57ab89f0eff` — Enigma

**Instantiated Address:** `[TO BE FILLED AFTER INSTANTIATION]`

---

#### 5. 🔐 ISM MULTISIG #3 - For Solana (Domain 1399811149)

```json
{ "owner": "YOUR_DEPLOYER_ADDRESS" }
```

**Code ID:** `11374`  
**Validators (official mainnet — 3 of 5):**
- `28464752829b3ea59a497fca0bdff575c534c3ff` — Abacus Works
- `2b7514a2f77bd86bbf093fe6bb67d8611f51c659` — Luganodes
- `cb6bcbd0de155072a7ff486d9d7286b0f71dcc2d` — Eclipse
- `4f977a59fdc2d9e39f6d780a84d5b4add1495a36` — Mitosis
- `5450447aee7b544c462c9352bef7cad049b0c2dc` — Zee Prime

**Instantiated Address:** `[TO BE FILLED AFTER INSTANTIATION]`

---

#### 6. 🗺️ ISM ROUTING - ISM Router

```json
{
  "owner": "YOUR_DEPLOYER_ADDRESS",
  "isms": [
    { "domain": 1,          "address": "<ISM_MULTISIG_ETH>" },
    { "domain": 56,         "address": "<ISM_MULTISIG_BSC>" },
    { "domain": 1399811149, "address": "<ISM_MULTISIG_SOL>" }
  ]
}
```

**Code ID:** `11376`  
**Instantiated Address:** `[TO BE FILLED AFTER INSTANTIATION]`

---

#### 7. 🌳 HOOK MERKLE

```json
{ "mailbox": "<MAILBOX_ADDRESS>" }
```

**Code ID:** `11380`  
**Instantiated Address:** `[TO BE FILLED AFTER INSTANTIATION]`

---

#### 8. ⛽ IGP - Interchain Gas Paymaster

```json
{
  "hrp": "terra",
  "owner": "YOUR_DEPLOYER_ADDRESS",
  "gas_token": "uluna",
  "beneficiary": "YOUR_DEPLOYER_ADDRESS",
  "default_gas_usage": "100000"
}
```

**Code ID:** `11377`  
**Instantiated Address:** `[TO BE FILLED AFTER INSTANTIATION]`

---

#### 9. 🔮 IGP ORACLE - Gas Price Oracle

```json
{ "owner": "YOUR_DEPLOYER_ADDRESS" }
```

**Code ID:** `11388`  
**Instantiated Address:** `[TO BE FILLED AFTER INSTANTIATION]`

> Gas prices and exchange rates for domains 1 (ETH), 56 (BSC), and 1399811149 (Solana) will be configured via governance after deployment.

---

#### 10. 🔗 HOOK AGGREGATE #1 - Aggregator (Merkle + IGP)

```json
{
  "owner": "YOUR_DEPLOYER_ADDRESS",
  "hooks": ["<HOOK_MERKLE>", "<IGP>"]
}
```

**Code ID:** `11378`  
**Instantiated Address:** `[TO BE FILLED AFTER INSTANTIATION]`

---

#### 11. ⏸️ HOOK PAUSABLE

```json
{ "owner": "YOUR_DEPLOYER_ADDRESS", "paused": false }
```

**Code ID:** `11381`  
**Instantiated Address:** `[TO BE FILLED AFTER INSTANTIATION]`

---

#### 12. 💰 HOOK FEE

```json
{
  "owner": "YOUR_DEPLOYER_ADDRESS",
  "fee": { "denom": "uluna", "amount": "283215" }
}
```

**Code ID:** `11379`  
**Instantiated Address:** `[TO BE FILLED AFTER INSTANTIATION]`

---

#### 13. 🔗 HOOK AGGREGATE #2 - Aggregator (Pausable + Fee)

```json
{
  "owner": "YOUR_DEPLOYER_ADDRESS",
  "hooks": ["<HOOK_PAUSABLE>", "<HOOK_FEE>"]
}
```

**Code ID:** `11378`  
**Instantiated Address:** `[TO BE FILLED AFTER INSTANTIATION]`

---

#### 14. ⚙️ MAILBOX CONFIGURATION

After instantiation, configure via governance proposal:
- **Default ISM**: ISM Routing address
- **Default Hook**: Hook Aggregate #1 (Merkle + IGP)
- **Required Hook**: Hook Aggregate #2 (Pausable + Fee)

---

### 🔄 Architecture Summary

```
┌─────────────────────────────────────────────────────────────┐
│                         MAILBOX                              │
│  (Central Contract - Manages Send/Receive)                  │
└─────────────┬───────────────────────────────┬────────────────┘
              │                               │
    ┌─────────▼─────────┐         ┌──────────▼──────────┐
    │  Default ISM      │         │   Hooks             │
    │  (ISM Routing)    │         │                     │
    │                   │         │  Required Hook:     │
    │  Routes to:       │         │  - Pausable         │
    │  - ISM Multisig   │         │  - Fee (0.283215    │
    │    (domain 1)     │         │    LUNC/msg)        │
    │  - ISM Multisig   │         │                     │
    │    (domain 56)    │         │  Default Hook:      │
    │  - ISM Multisig   │         │  - Merkle           │
    │    (domain        │         │  - IGP ──► Oracle   │
    │    1399811149)    │         └─────────────────────┘
    └───────────────────┘
```

> **⚠️ IMPORTANT:** After instantiation with your deployer wallet, transfer ownership to the governance module.
> See: [`TRANSFER-OWNERSHIP-TO-GOVERNANCE.md`](./TRANSFER-OWNERSHIP-TO-GOVERNANCE.md)

---

## 4️⃣ Configuration via Governance

After transferring ownership to the governance module, all configurations require governance proposals.

### Governance Proposal Messages

The proposal must execute **7 messages**:

#### MESSAGE 1: ISM Multisig Validators — Ethereum (Domain 1)

```json
{
  "set_validators": {
    "domain": 1,
    "threshold": 6,
    "validators": [
      "03c842db86a6a3e524d4a6615390c1ea8e2b9541",
      "94438a7de38d4548ae54df5c6010c4ebc5239eae",
      "5450447aee7b544c462c9352bef7cad049b0c2dc",
      "b3ac35d3988bca8c2ffd195b1c6bee18536b317b",
      "b683b742b378632a5f73a2a5a45801b3489bba44",
      "3786083ca59dc806d894104e65a13a70c2b39276",
      "4f977a59fdc2d9e39f6d780a84d5b4add1495a36",
      "29d783efb698f9a2d3045ef4314af1f5674f52c5",
      "36a669703ad0e11a0382b098574903d2084be22c"
    ]
  }
}
```

**Source:** [Hyperlane Official Mainnet ISM Validators](https://docs.hyperlane.xyz/docs/reference/addresses/validators/mainnet-default-ism-validators)

---

#### MESSAGE 2: ISM Multisig Validators — BSC (Domain 56)

```json
{
  "set_validators": {
    "domain": 56,
    "threshold": 4,
    "validators": [
      "570af9b7b36568c8877eebba6c6727aa9dab7268",
      "5450447aee7b544c462c9352bef7cad049b0c2dc",
      "0d4c1394a255568ec0ecd11795b28d1bda183ca4",
      "24c1506142b2c859aee36474e59ace09784f71e8",
      "c67789546a7a983bf06453425231ab71c119153f",
      "2d74f6edfd08261c927ddb6cb37af57ab89f0eff"
    ]
  }
}
```

---

#### MESSAGE 3: ISM Multisig Validators — Solana (Domain 1399811149)

```json
{
  "set_validators": {
    "domain": 1399811149,
    "threshold": 3,
    "validators": [
      "28464752829b3ea59a497fca0bdff575c534c3ff",
      "2b7514a2f77bd86bbf093fe6bb67d8611f51c659",
      "cb6bcbd0de155072a7ff486d9d7286b0f71dcc2d",
      "4f977a59fdc2d9e39f6d780a84d5b4add1495a36",
      "5450447aee7b544c462c9352bef7cad049b0c2dc"
    ]
  }
}
```

---

#### MESSAGE 4: IGP Oracle — Gas Data for All Chains

```json
{
  "set_remote_gas_data_configs": {
    "configs": [
      { "remote_domain": 1,          "token_exchange_rate": "1805936462255558", "gas_price": "50000000" },
      { "remote_domain": 56,         "token_exchange_rate": "1805936462255558", "gas_price": "50000000" },
      { "remote_domain": 1399811149, "token_exchange_rate": "57675000000000000", "gas_price": "1" }
    ]
  }
}
```

> Update `token_exchange_rate` and `gas_price` to reflect current market prices before submitting.

---

#### MESSAGE 5: IGP Routes to Oracle

```json
{
  "router": {
    "set_routes": {
      "set": [
        { "domain": 1,          "route": "<IGP_ORACLE_ADDRESS>" },
        { "domain": 56,         "route": "<IGP_ORACLE_ADDRESS>" },
        { "domain": 1399811149, "route": "<IGP_ORACLE_ADDRESS>" }
      ]
    }
  }
}
```

---

#### MESSAGE 6: Set Default ISM in Mailbox

```json
{ "set_default_ism": { "ism": "<ISM_ROUTING_ADDRESS>" } }
```

---

#### MESSAGE 7: Set Default Hook in Mailbox

```json
{ "set_default_hook": { "hook": "<HOOK_AGGREGATE_1_ADDRESS>" } }
```

---

#### MESSAGE 8: Set Required Hook in Mailbox

```json
{ "set_required_hook": { "hook": "<HOOK_AGGREGATE_2_ADDRESS>" } }
```

---

### Submit Proposal

```bash
terrad tx gov submit-proposal proposal.json \
  --from deployer-key \
  --chain-id columbus-5 \
  --node https://rpc.terra-classic.hexxagon.io:443 \
  --gas auto \
  --gas-adjustment 1.5 \
  --gas-prices 28.5uluna \
  --keyring-backend file \
  -y
```

### Vote YES

```bash
terrad tx gov vote <PROPOSAL_ID> yes \
  --from deployer-key \
  --chain-id columbus-5 \
  --node https://rpc.terra-classic.hexxagon.io:443 \
  --gas auto --gas-adjustment 1.5 --gas-prices 28.5uluna \
  --keyring-backend file -y
```

---

## 5️⃣ Execution Verification

After the proposal passes, verify all configurations:

```bash
LCD="https://lcd.terra-classic.hexxagon.io"

# ISM Multisig ETH — validators (domain 1)
terrad query wasm contract-state smart <ISM_MULTISIG_ETH> \
  '{"multisig_ism":{"enrolled_validators":{"domain":1}}}' \
  --node https://rpc.terra-classic.hexxagon.io:443 --chain-id columbus-5

# ISM Multisig BSC — validators (domain 56)
terrad query wasm contract-state smart <ISM_MULTISIG_BSC> \
  '{"multisig_ism":{"enrolled_validators":{"domain":56}}}' \
  --node https://rpc.terra-classic.hexxagon.io:443 --chain-id columbus-5

# ISM Multisig Solana — validators (domain 1399811149)
terrad query wasm contract-state smart <ISM_MULTISIG_SOL> \
  '{"multisig_ism":{"enrolled_validators":{"domain":1399811149}}}' \
  --node https://rpc.terra-classic.hexxagon.io:443 --chain-id columbus-5

# IGP Oracle — gas price BSC
terrad query wasm contract-state smart <IGP_ORACLE> \
  '{"oracle":{"get_exchange_rate_and_gas_price":{"dest_domain":56}}}' \
  --node https://rpc.terra-classic.hexxagon.io:443 --chain-id columbus-5

# Mailbox — default ISM
terrad query wasm contract-state smart <MAILBOX> \
  '{"mailbox":{"default_ism":{}}}' \
  --node https://rpc.terra-classic.hexxagon.io:443 --chain-id columbus-5

# Mailbox — default hook
terrad query wasm contract-state smart <MAILBOX> \
  '{"mailbox":{"default_hook":{}}}' \
  --node https://rpc.terra-classic.hexxagon.io:443 --chain-id columbus-5

# Mailbox — required hook
terrad query wasm contract-state smart <MAILBOX> \
  '{"mailbox":{"required_hook":{}}}' \
  --node https://rpc.terra-classic.hexxagon.io:443 --chain-id columbus-5
```

---

## 6️⃣ Contract Addresses and Hexed

> **Status:** Contracts uploaded. Addresses will be filled after instantiation.

| Contract | Address (Bech32) | Hexed (32 bytes) |
|----------|-----------------|------------------|
| **Mailbox** | `[TO BE FILLED]` | `[TO BE FILLED]` |
| **Validator Announce** | `[TO BE FILLED]` | `[TO BE FILLED]` |
| **ISM Multisig ETH** | `[TO BE FILLED]` | `[TO BE FILLED]` |
| **ISM Multisig BSC** | `[TO BE FILLED]` | `[TO BE FILLED]` |
| **ISM Multisig Solana** | `[TO BE FILLED]` | `[TO BE FILLED]` |
| **ISM Routing** | `[TO BE FILLED]` | `[TO BE FILLED]` |
| **Hook Merkle** | `[TO BE FILLED]` | `[TO BE FILLED]` |
| **IGP** | `[TO BE FILLED]` | `[TO BE FILLED]` |
| **IGP Oracle** | `[TO BE FILLED]` | `[TO BE FILLED]` |
| **Hook Aggregate 1** | `[TO BE FILLED]` | `[TO BE FILLED]` |
| **Hook Pausable** | `[TO BE FILLED]` | `[TO BE FILLED]` |
| **Hook Fee** | `[TO BE FILLED]` | `[TO BE FILLED]` |
| **Hook Aggregate 2** | `[TO BE FILLED]` | `[TO BE FILLED]` |

---

## 7️⃣ Troubleshooting

### Error: "insufficient fees"

```bash
--gas-prices 28.5uluna --gas-adjustment 2.0
```

### Error: "out of gas"

```bash
--gas 1000000
# or
--gas-adjustment 2.5
```

### Error: "contract not found"

```bash
terrad query wasm contract <ADDRESS> \
  --node https://rpc.terra-classic.hexxagon.io:443 --chain-id columbus-5
```

### RPC connection issues

Use an alternative mainnet RPC:
```bash
# Alternative RPCs for Terra Classic mainnet
https://terra-classic-rpc.publicnode.com:443
https://rpc.terraclassic.community
```

---

## 📚 Additional Resources

- [Hyperlane Docs](https://docs.hyperlane.xyz/)
- [Hyperlane Mainnet ISM Validators](https://docs.hyperlane.xyz/docs/reference/addresses/validators/mainnet-default-ism-validators)
- [Terra Classic Docs](https://docs.terra.money/)
- [CosmWasm Docs](https://docs.cosmwasm.com/)
- [Transfer Ownership to Governance](./TRANSFER-OWNERSHIP-TO-GOVERNANCE.md)

---

## ✅ Deployment Checklist

### Upload (✅ Completed)
- [x] Contracts uploaded — code IDs 11371–11390
- [x] SHA-256 hashes verified
- [x] TX hashes recorded

### Instantiation (⏳ Pending)
- [ ] Run `CustomInstantiateWasm-mainnet.ts`
- [ ] Save all contract addresses
- [ ] Fill the address table in section 6 of this document
- [ ] Verify all contracts were instantiated correctly

### Ownership Transfer
- [ ] Transfer ownership to governance — see [`TRANSFER-OWNERSHIP-TO-GOVERNANCE.md`](./TRANSFER-OWNERSHIP-TO-GOVERNANCE.md)

### Configuration (⏳ Pending governance)
- [ ] Create governance proposal with 8 messages
- [ ] Vote on proposal (obtain quorum)
- [ ] Wait for `PROPOSAL_STATUS_PASSED`
- [ ] Run all verification queries from section 5

### Post-Deployment
- [ ] Configure relayer with hexed contract addresses
- [ ] Configure validators
- [ ] Test cross-chain message sending
- [ ] Document final addresses for auditing

---

**Last updated:** 2026-06-03
**Contract Version:** v0.0.6-rc8
**Chain:** Terra Classic Mainnet (columbus-5)
**RPC:** https://rpc.terra-classic.hexxagon.io
**LCD:** https://lcd.terra-classic.hexxagon.io
**Governance Module:** `terra10d07y265gmmuvt4z0w9aw880jnsr700juxf95n`
**Supported Chains:** Ethereum (Domain 1), BSC (Domain 56), Solana (Domain 1399811149)
**Upload Status:** ✅ 20 contracts uploaded (code IDs 11371–11390)
**Instantiation Status:** ⏳ Pending
