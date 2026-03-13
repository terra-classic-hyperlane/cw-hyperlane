# Guide — Hyperlane Governance Proposal Submission (Terra Classic Testnet)

> **Script**: `submit-proposal-testnet.ts`  
> **Location**: `/home/lunc/cw-hyperlane/terraclassic/submit-proposal-testnet.ts`  
> **Network**: Terra Classic Testnet (`rebel-2`)

---

## Table of Contents

1. [Overview](#1--overview)
2. [Prerequisites](#2--prerequisites)
3. [File Structure](#3--file-structure)
4. [Execution Modes](#4--execution-modes)
5. [How to Run](#5--how-to-run)
6. [What the Script Configures](#6--what-the-script-configures)
   - [MSG 1 — ISM Multisig BSC Testnet](#msg-1--ism-multisig-bsc-testnet-domain-97)
   - [MSG 2 — ISM Multisig Sepolia](#msg-2--ism-multisig-sepolia-domain-11155111)
   - [MSG 3 — ISM Multisig Solana](#msg-3--ism-multisig-solana-domain-1399811150)
   - [MSG 4 — IGP Oracle (Exchange Rate and Gas Price)](#msg-4--igp-oracle-exchange-rate-and-gas-price)
   - [MSG 5 — IGP Routes to Oracle](#msg-5--igp-routes-to-oracle)
   - [MSG 6 — ISM Routing for Sepolia](#msg-6--ism-routing-for-sepolia)
   - [MSG 7 — Mailbox: Default ISM](#msg-7--mailbox-default-ism)
   - [MSG 8 — Mailbox: Default Hook](#msg-8--mailbox-default-hook)
   - [MSG 9 — Mailbox: Required Hook](#msg-9--mailbox-required-hook)
7. [Configured Contracts](#7--configured-contracts)
8. [How to Change ISM (Validators)](#8--how-to-change-ism-validators)
9. [How to Change IGP (Exchange Rate and Gas Price)](#9--how-to-change-igp-exchange-rate-and-gas-price)
10. [How to Change Hooks](#10--how-to-change-hooks)
11. [How to Add a New Network](#11--how-to-add-a-new-network)
12. [Submit Proposal via CLI](#12--submit-proposal-via-cli)
13. [Vote on the Proposal](#13--vote-on-the-proposal)
14. [Verify Execution](#14--verify-execution)
15. [Generated Files](#15--generated-files)
16. [Troubleshooting](#16--troubleshooting)
17. [Useful Links](#17--useful-links)

---

## 1 — Overview

The `submit-proposal-testnet.ts` script is used to **configure Hyperlane contracts on Terra Classic Testnet** safely via governance proposal, or directly for quick tests.

### What it does

The script packages 9 contract execution messages into a **governance proposal** (or executes directly), configuring:

| Component | What it configures |
|---|---|
| **ISM Multisig** | Which validators sign messages from each remote network |
| **ISM Routing** | Which ISM Multisig to use for each origin domain |
| **IGP Oracle** | LUNC ↔ remote token exchange rate + gas price |
| **IGP** | Routes to query Oracle when calculating gas fees |
| **Mailbox** | Default ISM, default hook, and required hook |

### Flow diagram (incoming message)

```
Message arrives (e.g.: Sepolia → TC)
       ↓
  Mailbox queries ISM Routing
       ↓
  ISM Routing directs to ISM_MULTISIG_SEP
       ↓
  ISM Multisig validates Sepolia validator signatures
       ↓
  Message delivered to destination contract (Warp)
```

### Flow diagram (outgoing message)

```
transfer_remote() called on Warp (TC → destination)
       ↓
  Mailbox executes Required Hook (Pausable + Fee)
       ↓
  Mailbox executes Default Hook (Merkle + IGP)
       ↓
  IGP calculates fee → queries Oracle → charges LUNC from sender
  Merkle registers the message in the tree for the validator to sign
       ↓
  Message emitted as event
       ↓
  Validator signs the checkpoint → Relayer delivers to destination
```

---

## 2 — Prerequisites

### Software

```bash
# Node.js 18+
node --version

# npx + tsx
npm install -g tsx

# Project dependencies (install in the script folder)
cd ~/cw-hyperlane/terraclassic
npm install @cosmjs/cosmwasm-stargate @cosmjs/proto-signing @cosmjs/stargate
```

### Wallet

You need a Terra Classic wallet with:
- LUNC balance to pay transaction fees
- In `proposal` mode: at least **10 LUNC** for the proposal initial deposit

### Private key

The private key must be set via environment variable:

```bash
export TERRA_PRIVATE_KEY="xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
# or
export PRIVATE_KEY="xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
```

> ⚠️ **NEVER** put the private key directly in the script or in versioned configuration files!

---

## 3 — File Structure

```
terraclassic/
├── submit-proposal-testnet.ts     ← Main script
├── exec_msgs_testnet.json         ← Generated: individual messages
├── proposal_testnet.json          ← Generated: proposal formatted for terrad
└── docs/
    └── submit-proposal-guide.md  ← This document
```

---

## 4 — Execution Modes

The script has two modes controlled by the `MODE` environment variable:

### Mode `proposal` (default — recommended for production)

Generates JSON files with the formatted proposal and displays the `terrad` command to submit it. **Does not execute any contract directly**.

```bash
# MODE=proposal is the default, no need to define
export TERRA_PRIVATE_KEY="xxxxxxxx..."
npx tsx submit-proposal-testnet.ts
```

### Mode `direct` (for quick tests)

Executes messages directly on the blockchain, without going through governance. Use only in testnet/development.

```bash
export MODE=direct
export TERRA_PRIVATE_KEY="xxxxxxxx..."
npx tsx submit-proposal-testnet.ts
```

> ⚠️ The `direct` mode only works if the wallet is the **owner/admin** of the contracts. In production, contracts are managed by the governance module (`terra10d07y265gmmuvt4z0w9aw880jnsr700juxf95n`).

---

## 5 — How to Run

### Step 1 — Install dependencies

```bash
cd ~/cw-hyperlane/terraclassic
npm install @cosmjs/cosmwasm-stargate @cosmjs/proto-signing @cosmjs/stargate
```

### Step 2 — Set the private key

```bash
export TERRA_PRIVATE_KEY="xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
```

### Step 3 — Run the script

```bash
npx tsx submit-proposal-testnet.ts
```

### Expected output (`proposal` mode)

```
================================================================================
PREPARING HYPERLANE GOVERNANCE PROPOSAL - TESTNET MULTI-CHAIN
================================================================================

📋 PROPOSAL INFORMATION:
────────────────────────────────────────────────────────────────────────────────
Title: Hyperlane Contracts Configuration - Testnet Multi-Chain

🌐 SUPPORTED CHAINS (TESTNET):
  • Sepolia Testnet (Domain 11155111) - 1/1 validator
  • BSC Testnet (Domain 97) - 2/3 validators
  • Solana Testnet (Domain 1399811150) - 1/1 validator

📝 EXECUTION MESSAGES (9 messages):
...

💾 SAVING FILES...
  ✓ exec_msgs_testnet.json
  ✓ proposal_testnet.json

🚀 COMMAND TO SUBMIT VIA CLI:
terrad tx gov submit-proposal proposal_testnet.json \
  --from hyperlane-testnet \
  --chain-id rebel-2 \
  --gas auto \
  --gas-adjustment 1.5 \
  --gas-prices 28.5uluna \
  --node https://rpc.luncblaze.com:443 \
  -y
```

---

## 6 — What the Script Configures

### General flow of the 9 messages

```
MSG 1  → ISM_MULTISIG_BSC   → set_validators (BSC, domain 97)
MSG 2  → ISM_MULTISIG_SEP   → set_validators (Sepolia, domain 11155111)
MSG 3  → ISM_MULTISIG_SOL   → set_validators (Solana, domain 1399811150)
MSG 4  → IGP_ORACLE          → set_remote_gas_data_configs (3 networks)
MSG 5  → IGP                 → set_routes (3 networks → Oracle)
MSG 6  → ISM_ROUTING         → set (Sepolia → ISM_MULTISIG_SEP)
MSG 7  → MAILBOX             → set_default_ism (ISM Routing)
MSG 8  → MAILBOX             → set_default_hook (Merkle + IGP)
MSG 9  → MAILBOX             → set_required_hook (Pausable + Fee)
```

---

### MSG 1 — ISM Multisig BSC Testnet (Domain 97)

**Contract**: `terra1rrt0kepmazvavmkusvz6589l5yg4mqjk49netqfqttnmf2y4exmqxhp0hv`

**What it does**: Registers the 3 validators that sign messages coming from BSC Testnet. The threshold of **2/3** means at least 2 of the 3 must sign.

```json
{
  "set_validators": {
    "domain": 97,
    "threshold": 2,
    "validators": [
      "242d8a855a8c932dec51f7999ae7d1e48b10c95e",
      "f620f5e3d25a3ae848fec74bccae5de3edcd8796",
      "1f030345963c54ff8229720dd3a711c15c554aeb"
    ]
  }
}
```

**How to find BSC validators**: Check the validator's S3:
```
https://hyperlane-validator-signatures-igorveras-bsctestnet.s3.us-east-1.amazonaws.com/announcement.json
```

---

### MSG 2 — ISM Multisig Sepolia (Domain 11155111)

**Contract**: `terra1mzkakdts4958dyks72saw9wgas2eqmmxpuqc8gut2jvt9xuj8qzqc03vxa`

**What it does**: Registers 1 validator for messages coming from Sepolia. Threshold **1/1**.

```json
{
  "set_validators": {
    "domain": 11155111,
    "threshold": 1,
    "validators": [
      "133fd7f7094dbd17b576907d052a5acbd48db526"
    ]
  }
}
```

**How to find the Sepolia validator**:
```
https://hyperlane-validator-signatures-igorveras-sepolia.s3.us-east-1.amazonaws.com/announcement.json
```

The `validator` field in the announcement JSON is the validator address (without `0x`).

---

### MSG 3 — ISM Multisig Solana (Domain 1399811150)

**Contract**: `terra1d7a52pxu309jcgv8grck7jpgwlfw7cy0zen9u42rqdr39tef9g7qc8gp4a`

**What it does**: Registers 1 validator for messages coming from Solana Testnet. Threshold **1/1**.

```json
{
  "set_validators": {
    "domain": 1399811150,
    "threshold": 1,
    "validators": [
      "d4ce8fa138d4e083fc0e480cca0dbfa4f5f30bd5"
    ]
  }
}
```

**How to find the Solana validator**:
```
https://hyperlane-validator-signatures-igorveras-terraclassic.s3.us-east-1.amazonaws.com/
```
> The Solana validator that signs for TC is in the announcement on the Terra Classic side.

---

### MSG 4 — IGP Oracle (Exchange Rate and Gas Price)

**Contract**: `terra18tyqe79yktac6p3alv3f49k06xqna2q52twyaflrz55qka9emhrs30k3hg`

**What it does**: Configures the gas price and exchange rate between LUNC and the native token of each destination network. The IGP uses this data to calculate how much to charge the sender.

```json
{
  "set_remote_gas_data_configs": {
    "configs": [
      {
        "remote_domain": 11155111,
        "token_exchange_rate": "10000000000000000",
        "gas_price": "10000000000"
      },
      {
        "remote_domain": 97,
        "token_exchange_rate": "1805936462255558",
        "gas_price": "50000000"
      },
      {
        "remote_domain": 1399811150,
        "token_exchange_rate": "57675000000000000",
        "gas_price": "1"
      }
    ]
  }
}
```

**Cost calculation formula**:
```
Cost in LUNC = (gas_used_on_destination × gas_price × token_exchange_rate) / 1e10
```

**How to find updated values**:

| Network | Check gas price at |
|---|---|
| Sepolia | https://sepolia.etherscan.io/gastracker |
| BSC Testnet | https://testnet.bscscan.com/gastracker |
| Solana Testnet | https://explorer.solana.com/?cluster=testnet |

For LUNC/ETH exchange rate:
```bash
# Via CoinGecko (example)
curl "https://api.coingecko.com/api/v3/simple/price?ids=terra-luna,ethereum&vs_currencies=usd"
```

> The `token_exchange_rate` is calculated as: `(LUNC_price / destination_token_price) × 1e18`  
> Example: LUNC = $0.000088, ETH = $1800 → rate = (0.000088/1800) × 1e18 ≈ 4.9e10

---

### MSG 5 — IGP Routes to Oracle

**Contract**: `terra1n70g3vg7xge6q8m44rudm4y6fm6elpspwsgfmfphs3teezpak6cs6wxlk9`

**What it does**: Configures the IGP to query the IGP Oracle when calculating gas fees for each remote domain.

```json
{
  "router": {
    "set_routes": {
      "set": [
        { "domain": 11155111, "route": "terra18tyqe79yktac6p3alv3f49k06xqna2q52twyaflrz55qka9emhrs30k3hg" },
        { "domain": 97,       "route": "terra18tyqe79yktac6p3alv3f49k06xqna2q52twyaflrz55qka9emhrs30k3hg" },
        { "domain": 1399811150, "route": "terra18tyqe79yktac6p3alv3f49k06xqna2q52twyaflrz55qka9emhrs30k3hg" }
      ]
    }
  }
}
```

---

### MSG 6 — ISM Routing for Sepolia

**Contract**: `terra1h4sd8fyxhde7dc9w9y9zhc2epphgs75q7zzfg3tfynm8qvpe3jlsd7sauh`

**What it does**: Registers in the ISM Routing that messages from domain `11155111` (Sepolia) must be validated by `ISM_MULTISIG_SEP`.

```json
{
  "set": {
    "ism": {
      "domain": 11155111,
      "address": "terra1mzkakdts4958dyks72saw9wgas2eqmmxpuqc8gut2jvt9xuj8qzqc03vxa"
    }
  }
}
```

> **Note**: BSC and Solana are already configured in ISM Routing by previous scripts. This step adds Sepolia.

---

### MSG 7 — Mailbox: Default ISM

**Contract**: `terra1rqg3qfkfg5upad9xu6zj5jhl626qy053s7rn08829rgqzv2wu39s5la8yf`

**What it does**: Sets ISM Routing as the default security module of the Mailbox. Every incoming message will be validated by ISM Routing, which directs to the correct ISM Multisig based on the origin domain.

```json
{
  "set_default_ism": {
    "ism": "terra1h4sd8fyxhde7dc9w9y9zhc2epphgs75q7zzfg3tfynm8qvpe3jlsd7sauh"
  }
}
```

---

### MSG 8 — Mailbox: Default Hook

**Contract**: `terra1rqg3qfkfg5upad9xu6zj5jhl626qy053s7rn08829rgqzv2wu39s5la8yf`

**What it does**: Sets **Hook Aggregate #1** as the default hook for outgoing messages. This hook combines:
- **Merkle Hook**: Adds the message to the Merkle tree so the validator can sign the checkpoint
- **IGP Hook**: Processes the gas payment for execution at the destination

```json
{
  "set_default_hook": {
    "hook": "terra14qjm9075m8djus4tl86lc5n2xnsvuazesl52vqyuz6pmaj4k5s5qu5q6jh"
  }
}
```

> ⚠️ **Important**: The Merkle Hook is essential! If the default hook does not include the Merkle Hook, the validator will not be able to sign checkpoints and messages will never be delivered.

---

### MSG 9 — Mailbox: Required Hook

**Contract**: `terra1rqg3qfkfg5upad9xu6zj5jhl626qy053s7rn08829rgqzv2wu39s5la8yf`

**What it does**: Sets **Hook Aggregate #2** as the required hook (always executed, cannot be bypassed). This hook combines:
- **Hook Pausable**: Allows pausing message sending in emergencies
- **Hook Fee**: Charges a fixed fee of ~0.283215 LUNC per message (anti-spam)

```json
{
  "set_required_hook": {
    "hook": "terra1xdpah0ven023jzd80qw0nkp4ndjxy4d7g5y99dhpfwetyal6q6jqpk42rj"
  }
}
```

---

## 7 — Configured Contracts

### Address table (Testnet `rebel-2`)

| Contract | Address | Function |
|---|---|---|
| **Mailbox** | `terra1rqg3qfkfg5upad9xu6zj5jhl626qy053s7rn08829rgqzv2wu39s5la8yf` | Central message hub |
| **ISM Routing** | `terra1h4sd8fyxhde7dc9w9y9zhc2epphgs75q7zzfg3tfynm8qvpe3jlsd7sauh` | Directs to correct ISM per domain |
| **ISM Multisig BSC** | `terra1rrt0kepmazvavmkusvz6589l5yg4mqjk49netqfqttnmf2y4exmqxhp0hv` | Validates msgs from BSC Testnet (2/3) |
| **ISM Multisig Sepolia** | `terra1mzkakdts4958dyks72saw9wgas2eqmmxpuqc8gut2jvt9xuj8qzqc03vxa` | Validates msgs from Sepolia (1/1) |
| **ISM Multisig Solana** | `terra1d7a52pxu309jcgv8grck7jpgwlfw7cy0zen9u42rqdr39tef9g7qc8gp4a` | Validates msgs from Solana (1/1) |
| **IGP** | `terra1n70g3vg7xge6q8m44rudm4y6fm6elpspwsgfmfphs3teezpak6cs6wxlk9` | Processes gas payment |
| **IGP Oracle** | `terra18tyqe79yktac6p3alv3f49k06xqna2q52twyaflrz55qka9emhrs30k3hg` | Provides gas prices per network |
| **Hook Aggregate 1** | `terra14qjm9075m8djus4tl86lc5n2xnsvuazesl52vqyuz6pmaj4k5s5qu5q6jh` | Default hook (Merkle + IGP) |
| **Hook Aggregate 2** | `terra1xdpah0ven023jzd80qw0nkp4ndjxy4d7g5y99dhpfwetyal6q6jqpk42rj` | Required hook (Pausable + Fee) |
| **Governance Module** | `terra10d07y265gmmuvt4z0w9aw880jnsr700juxf95n` | Contract owner in production |

---

## 8 — How to Change ISM (Validators)

### Scenario: Add new validator to BSC (change from 2/3 to 3/4)

**In the script** (`submit-proposal-testnet.ts`), locate MSG 1 and modify:

```typescript
// Before (2/3)
set_validators: {
  domain: 97,
  threshold: 2,
  validators: [
    '242d8a855a8c932dec51f7999ae7d1e48b10c95e',
    'f620f5e3d25a3ae848fec74bccae5de3edcd8796',
    '1f030345963c54ff8229720dd3a711c15c554aeb',
  ],
},

// After (3/4)
set_validators: {
  domain: 97,
  threshold: 3,
  validators: [
    '242d8a855a8c932dec51f7999ae7d1e48b10c95e',
    'f620f5e3d25a3ae848fec74bccae5de3edcd8796',
    '1f030345963c54ff8229720dd3a711c15c554aeb',
    'NEW_VALIDATOR_WITHOUT_0X_PREFIX',              // ← new
  ],
},
```

### Scenario: Check current validators on the contract

```bash
# Query validators configured for BSC (domain 97)
terrad query wasm contract-state smart \
  terra1rrt0kepmazvavmkusvz6589l5yg4mqjk49netqfqttnmf2y4exmqxhp0hv \
  '{"get_validators":{"domain":97}}' \
  --node https://rpc.terra-classic.hexxagon.dev

# Query validators configured for Sepolia (domain 11155111)
terrad query wasm contract-state smart \
  terra1mzkakdts4958dyks72saw9wgas2eqmmxpuqc8gut2jvt9xuj8qzqc03vxa \
  '{"get_validators":{"domain":11155111}}' \
  --node https://rpc.terra-classic.hexxagon.dev
```

### Scenario: Add support for a new network (e.g.: Avalanche Fuji, domain 43113)

1. **Find the validator address** — Check the Avalanche validator's S3:
   ```
   https://hyperlane-validator-signatures-<name>-avalanchefuji.s3.us-east-1.amazonaws.com/announcement.json
   ```

2. **Create a new ISM Multisig contract** for the domain (via governance or deploy script)

3. **Add a new constant to the script**:
   ```typescript
   const ISM_MULTISIG_AVAX = 'terra1...new_contract...';
   ```

4. **Add a new set_validators MSG**:
   ```typescript
   {
     contractAddress: ISM_MULTISIG_AVAX,
     description: 'Configure multisig validators for Avalanche Fuji (domain 43113)',
     msg: {
       set_validators: {
         domain: 43113,
         threshold: 1,
         validators: ['VALIDATOR_ADDRESS_WITHOUT_0X'],
       },
     },
   },
   ```

5. **Add ISM Routing MSG** to map the new domain to ISM_MULTISIG_AVAX

---

## 9 — How to Change IGP (Exchange Rate and Gas Price)

### Concepts

| Field | Unit | Description |
|---|---|---|
| `token_exchange_rate` | `1e18` base | Ratio between the LUNC price and the destination native token |
| `gas_price` | wei / lamports | Gas price on the destination network |

### Formula to calculate `token_exchange_rate`

```
token_exchange_rate = (LUNC_price_USD / destination_token_price_USD) × 1e18
```

**Examples**:
- LUNC = $0.000088, ETH = $1800 → rate = (0.000088/1800) × 1e18 ≈ `49000000000000`
- LUNC = $0.000088, BNB = $250 → rate = (0.000088/250) × 1e18 ≈ `352000000000000`
- LUNC = $0.000088, SOL = $130 → rate = (0.000088/130) × 1e18 ≈ `677000000000000`

### How to change in the script

Locate MSG 4 in `submit-proposal-testnet.ts` and edit the values:

```typescript
{
  contractAddress: IGP_ORACLE,
  msg: {
    set_remote_gas_data_configs: {
      configs: [
        {
          remote_domain: 11155111,
          token_exchange_rate: '49000000000000',  // ← update
          gas_price: '15000000000',               // ← 15 Gwei
        },
        // ...
      ],
    },
  },
},
```

### Change manually via `terrad` (without proposal)

If you are the admin/owner of the contract:

```bash
terrad tx wasm execute terra18tyqe79yktac6p3alv3f49k06xqna2q52twyaflrz55qka9emhrs30k3hg \
  '{
    "set_remote_gas_data_configs": {
      "configs": [
        {
          "remote_domain": 11155111,
          "token_exchange_rate": "49000000000000",
          "gas_price": "15000000000"
        }
      ]
    }
  }' \
  --from <your-wallet> \
  --chain-id rebel-2 \
  --gas auto \
  --gas-adjustment 1.5 \
  --gas-prices 28.5uluna \
  --node https://rpc.luncblaze.com:443 \
  -y
```

### Check current Oracle configuration

```bash
# Query gas data for Sepolia (11155111)
terrad query wasm contract-state smart \
  terra18tyqe79yktac6p3alv3f49k06xqna2q52twyaflrz55qka9emhrs30k3hg \
  '{"get_remote_gas_data":{"domain":11155111}}' \
  --node https://rpc.terra-classic.hexxagon.dev

# Query gas data for BSC (97)
terrad query wasm contract-state smart \
  terra18tyqe79yktac6p3alv3f49k06xqna2q52twyaflrz55qka9emhrs30k3hg \
  '{"get_remote_gas_data":{"domain":97}}' \
  --node https://rpc.terra-classic.hexxagon.dev
```

---

## 10 — How to Change Hooks

### What is a Hook?

A Hook is executed every time a message is **sent** by the Mailbox. There are two types:
- **Default Hook**: Executed for all messages (contains Merkle + IGP)
- **Required Hook**: Always executed before the default (contains Pausable + Fee)

### Scenario: Check current hooks

```bash
# Check default ISM
terrad query wasm contract-state smart \
  terra1rqg3qfkfg5upad9xu6zj5jhl626qy053s7rn08829rgqzv2wu39s5la8yf \
  '{"default_ism":{}}' \
  --node https://rpc.terra-classic.hexxagon.dev

# Check default hook
terrad query wasm contract-state smart \
  terra1rqg3qfkfg5upad9xu6zj5jhl626qy053s7rn08829rgqzv2wu39s5la8yf \
  '{"default_hook":{}}' \
  --node https://rpc.terra-classic.hexxagon.dev

# Check required hook
terrad query wasm contract-state smart \
  terra1rqg3qfkfg5upad9xu6zj5jhl626qy053s7rn08829rgqzv2wu39s5la8yf \
  '{"required_hook":{}}' \
  --node https://rpc.terra-classic.hexxagon.dev
```

### Scenario: Change the Default Hook

In the script, locate MSG 8 and change the hook address:

```typescript
{
  contractAddress: MAILBOX,
  msg: {
    set_default_hook: {
      hook: 'terra1...new_hook_address...',  // ← new address
    },
  },
},
```

> ⚠️ **Warning**: The new hook must **always include the Merkle Hook** (`terra1x9ftmmyj0t9n0ql78r2vdfk9stxg5z6vnwnwjym9m7py6lvxz8ls7sa3df`). Without it, the validator cannot sign checkpoints and messages will not be delivered.

### Change hook manually via `terrad`

```bash
terrad tx wasm execute terra1rqg3qfkfg5upad9xu6zj5jhl626qy053s7rn08829rgqzv2wu39s5la8yf \
  '{"set_default_hook":{"hook":"terra1...new_hook..."}}' \
  --from <your-wallet> \
  --chain-id rebel-2 \
  --gas auto \
  --gas-adjustment 1.5 \
  --gas-prices 28.5uluna \
  --node https://rpc.luncblaze.com:443 \
  -y
```

### Individual hook addresses (reference)

| Hook | Address | Function |
|---|---|---|
| **Merkle Hook** | `terra1x9ftmmyj0t9n0ql78r2vdfk9stxg5z6vnwnwjym9m7py6lvxz8ls7sa3df` | Registers msgs in Merkle tree |
| **Hook Pausable** | `terra1j04kamuwssgckj7592w5v3hlttmlqlu9cqkzvvxsjt8rqyt3stps0xan5l` | Pauses sending in emergencies |
| **Hook Fee** | `terra13y6vseryqqj09uu9aagk8xks4dr9fr2p0xr3w6gngdzjd362h54sz5fr3j` | Charges fixed fee per message |
| **Hook Agg #1** | `terra14qjm9075m8djus4tl86lc5n2xnsvuazesl52vqyuz6pmaj4k5s5qu5q6jh` | Merkle + IGP (default) |
| **Hook Agg #2** | `terra1xdpah0ven023jzd80qw0nkp4ndjxy4d7g5y99dhpfwetyal6q6jqpk42rj` | Pausable + Fee (required) |

---

## 11 — How to Add a New Network

To add support for a new EVM network (e.g.: Polygon Mumbai, domain `80001`):

### Step 1 — Get the validator address

```bash
curl https://hyperlane-validator-signatures-<name>-mumbai.s3.us-east-1.amazonaws.com/announcement.json
# The "validator" field contains the address (without 0x)
```

### Step 2 — Create ISM Multisig for the new network

```bash
# Via Hyperlane CLI (on EVM) or cw-hpl CLI (on TC)
# Or check if there is an existing reusable contract
```

### Step 3 — Update the script

```typescript
// 1. Add constant
const ISM_MULTISIG_MUMBAI = 'terra1...new_contract...';

// 2. Add MSG for set_validators
{
  contractAddress: ISM_MULTISIG_MUMBAI,
  description: 'Configure multisig for Mumbai (domain 80001)',
  msg: {
    set_validators: {
      domain: 80001,
      threshold: 1,
      validators: ['VALIDATOR_ADDRESS_WITHOUT_0X'],
    },
  },
},

// 3. Add to IGP Oracle (MSG 4)
{
  remote_domain: 80001,
  token_exchange_rate: '...',  // LUNC/MATIC exchange rate × 1e18
  gas_price: '...',
},

// 4. Add to IGP routes (MSG 5)
{ domain: 80001, route: IGP_ORACLE },

// 5. Add to ISM Routing (new MSG)
{
  contractAddress: ISM_ROUTING,
  msg: {
    set: {
      ism: {
        domain: 80001,
        address: ISM_MULTISIG_MUMBAI,
      },
    },
  },
},
```

---

## 12 — Submit Proposal via CLI

After running the script in `proposal` mode, two files are generated. Use them to submit the proposal:

```bash
# 1. Review the proposal file
cat proposal_testnet.json

# 2. Submit the proposal
terrad tx gov submit-proposal proposal_testnet.json \
  --from hyperlane-testnet \
  --chain-id rebel-2 \
  --gas auto \
  --gas-adjustment 1.5 \
  --gas-prices 28.5uluna \
  --node https://rpc.luncblaze.com:443 \
  -y

# 3. Note the PROPOSAL_ID shown in the output
# Look for: proposal_id: "XX"
```

> 💡 To submit you need at least **10 LUNC** in your wallet for the initial deposit.

---

## 13 — Vote on the Proposal

```bash
# List active proposals
terrad query gov proposals \
  --status voting_period \
  --node https://rpc.luncblaze.com:443

# Vote YES on the proposal (replace <ID> with the number)
terrad tx gov vote <ID> yes \
  --from hyperlane-testnet \
  --chain-id rebel-2 \
  --gas auto \
  --gas-adjustment 1.5 \
  --gas-prices 28.5uluna \
  --node https://rpc.luncblaze.com:443 \
  -y

# Check voting result
terrad query gov proposal <ID> \
  --node https://rpc.luncblaze.com:443
```

---

## 14 — Verify Execution

After the proposal is approved, verify that the contracts have been correctly configured:

### Check default ISM in Mailbox

```bash
terrad query wasm contract-state smart \
  terra1rqg3qfkfg5upad9xu6zj5jhl626qy053s7rn08829rgqzv2wu39s5la8yf \
  '{"default_ism":{}}' \
  --node https://rpc.terra-classic.hexxagon.dev
# Should return the ISM Routing address
```

### Check BSC validators

```bash
terrad query wasm contract-state smart \
  terra1rrt0kepmazvavmkusvz6589l5yg4mqjk49netqfqttnmf2y4exmqxhp0hv \
  '{"get_validators":{"domain":97}}' \
  --node https://rpc.terra-classic.hexxagon.dev
```

### Check oracle for Sepolia

```bash
terrad query wasm contract-state smart \
  terra18tyqe79yktac6p3alv3f49k06xqna2q52twyaflrz55qka9emhrs30k3hg \
  '{"get_remote_gas_data":{"domain":11155111}}' \
  --node https://rpc.terra-classic.hexxagon.dev
```

### Check Mailbox default hook

```bash
terrad query wasm contract-state smart \
  terra1rqg3qfkfg5upad9xu6zj5jhl626qy053s7rn08829rgqzv2wu39s5la8yf \
  '{"default_hook":{}}' \
  --node https://rpc.terra-classic.hexxagon.dev
# Should return the Hook Aggregate #1 address
```

---

## 15 — Generated Files

| File | Description |
|---|---|
| `exec_msgs_testnet.json` | Array with all individual execution messages |
| `proposal_testnet.json` | Complete proposal formatted for `terrad` |

### Example `proposal_testnet.json`

```json
{
  "messages": [
    {
      "@type": "/cosmwasm.wasm.v1.MsgExecuteContract",
      "sender": "terra10d07y265gmmuvt4z0w9aw880jnsr700juxf95n",
      "contract": "terra1rrt0kepmazvavmkusvz6589l5yg4mqjk49netqfqttnmf2y4exmqxhp0hv",
      "msg": { "set_validators": { "domain": 97, "threshold": 2, "validators": ["..."] } },
      "funds": []
    }
  ],
  "metadata": "Initial configuration of Hyperlane contracts for testnet multi-chain support",
  "deposit": "10000000uluna",
  "title": "Hyperlane Contracts Configuration - Testnet Multi-Chain",
  "summary": "...",
  "expedited": false
}
```

---

## 16 — Troubleshooting

### ❌ `ERROR: Set the PRIVATE_KEY environment variable.`

**Cause**: The private key was not configured.

**Solution**:
```bash
export TERRA_PRIVATE_KEY="xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
# or
export PRIVATE_KEY="xxxxxxxx..."
```

---

### ❌ `Error: Account 'terra1...' does not exist on chain`

**Cause**: The wallet associated with the private key has no balance or has not been activated on the network.

**Solution**: Send LUNC to the wallet:
```bash
terrad query bank balances terra1... --node https://rpc.terra-classic.hexxagon.dev
```

---

### ❌ `out of gas in location: wasm contract`

**Cause**: Insufficient gas to execute all 9 messages in sequence.

**Solution** (direct mode): The script uses `'auto'` to automatically estimate gas. Make sure you have sufficient balance.

**Solution** (via terrad CLI): Increase `--gas-adjustment`:
```bash
terrad tx gov submit-proposal proposal_testnet.json \
  --gas auto \
  --gas-adjustment 2.0 \
  ...
```

---

### ❌ `failed to execute message: unauthorized`

**Cause**: The wallet does not have permission to execute contracts directly (`direct` mode).

**Solution**: In production, use `proposal` mode to submit via governance. Contracts only accept messages with `sender = terra10d07y265gmmuvt4z0w9aw880jnsr700juxf95n` (governance module).

---

### ❌ `Cannot find module '@cosmjs/cosmwasm-stargate'`

**Cause**: Dependencies not installed.

**Solution**:
```bash
cd ~/cw-hyperlane/terraclassic
npm install @cosmjs/cosmwasm-stargate @cosmjs/proto-signing @cosmjs/stargate
```

---

### ❌ Proposal approved but contracts were not configured

**Cause**: There may be an error in the message format in `proposal_testnet.json`, or the contract rejected the execution.

**Diagnosis**: Check the TX hash of the proposal execution in the explorer:
```
https://finder.hexxagon.io/rebel-2/
```

---

## 17 — Useful Links

### Explorers

| Network | Explorer |
|---|---|
| Terra Classic Testnet | https://finder.hexxagon.io/rebel-2/ |
| Sepolia | https://sepolia.etherscan.io |
| BSC Testnet | https://testnet.bscscan.com |
| Solana Testnet | https://explorer.solana.com/?cluster=testnet |

### On-chain Contracts (Testnet)

| Contract | Explorer Link |
|---|---|
| Mailbox | https://finder.hexxagon.io/rebel-2/address/terra1rqg3qfkfg5upad9xu6zj5jhl626qy053s7rn08829rgqzv2wu39s5la8yf |
| ISM Routing | https://finder.hexxagon.io/rebel-2/address/terra1h4sd8fyxhde7dc9w9y9zhc2epphgs75q7zzfg3tfynm8qvpe3jlsd7sauh |
| ISM Multisig BSC | https://finder.hexxagon.io/rebel-2/address/terra1rrt0kepmazvavmkusvz6589l5yg4mqjk49netqfqttnmf2y4exmqxhp0hv |
| ISM Multisig Sepolia | https://finder.hexxagon.io/rebel-2/address/terra1mzkakdts4958dyks72saw9wgas2eqmmxpuqc8gut2jvt9xuj8qzqc03vxa |
| ISM Multisig Solana | https://finder.hexxagon.io/rebel-2/address/terra1d7a52pxu309jcgv8grck7jpgwlfw7cy0zen9u42rqdr39tef9g7qc8gp4a |
| IGP | https://finder.hexxagon.io/rebel-2/address/terra1n70g3vg7xge6q8m44rudm4y6fm6elpspwsgfmfphs3teezpak6cs6wxlk9 |
| IGP Oracle | https://finder.hexxagon.io/rebel-2/address/terra18tyqe79yktac6p3alv3f49k06xqna2q52twyaflrz55qka9emhrs30k3hg |

### Validator S3 Storage

| Validator | URL |
|---|---|
| Terra Classic | https://hyperlane-validator-signatures-igorveras-terraclassic.s3.us-east-1.amazonaws.com/ |
| Sepolia | https://hyperlane-validator-signatures-igorveras-sepolia.s3.us-east-1.amazonaws.com/ |
| BSC Testnet | https://hyperlane-validator-signatures-igorveras-bsctestnet.s3.us-east-1.amazonaws.com/ |

### Hyperlane Documentation

- https://docs.hyperlane.xyz/docs/reference/messaging/messaging-interface
- https://docs.hyperlane.xyz/docs/reference/ISM/multisig-ISM
- https://docs.hyperlane.xyz/docs/reference/hooks/interchain-gas

### Terra Classic RPC Nodes

| Endpoint | Provider |
|---|---|
| `https://rpc.terra-classic.hexxagon.dev` | Hexxagon |
| `https://rpc.luncblaze.com:443` | LuncBlaze |
| `https://terra-classic-rpc.publicnode.com` | PublicNode |
