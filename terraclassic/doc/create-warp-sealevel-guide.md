# Complete Guide: `create-warp-sealevel.sh`

> Interactive script to create and configure Hyperlane Warp Routes on **Solana (Sealevel)** connected to Terra Classic.  
> Fully portable — just copy the `terraclassic/` folder to any `cw-hyperlane` project.

---

## 📋 Table of Contents

1. [What the script does](#1-what-the-script-does)
2. [Sealevel vs EVM differences](#2-sealevel-vs-evm-differences)
3. [Prerequisites](#3-prerequisites)
4. [File structure](#4-file-structure)
5. [Configuring `warp-sealevel-config.json`](#5-configuring-warp-sealevel-configjson)
   - [Section `networks`](#51-section-networks)
   - [Section `warp_tokens`](#52-section-warp_tokens)
   - [Adding a new token](#53-adding-a-new-token)
   - [Enabling Solana Mainnet](#54-enabling-solana-mainnet)
6. [Configuring `warp-evm-config.json` (Terra Classic tokens)](#6-configuring-warp-evm-configjson-terra-classic-tokens)
7. [Token metadata (Solana)](#7-token-metadata-solana)
8. [Running the script](#8-running-the-script)
   - [Full execution (from scratch)](#81-full-execution-from-scratch)
   - [Skipping already executed steps](#82-skipping-already-executed-steps)
   - [Resuming after failure](#83-resuming-after-failure)
9. [What the script configures — Detailed steps](#9-what-the-script-configures--detailed-steps)
10. [Updating the JSON after deploy](#10-updating-the-json-after-deploy)
11. [Manual deploy and configuration (without the script)](#11-manual-deploy-and-configuration-without-the-script)
12. [How to verify state after deploy](#12-how-to-verify-state-after-deploy)
13. [How to find Hyperlane addresses on Solana](#13-how-to-find-hyperlane-addresses-on-solana)
14. [How to verify token receipt after transfer](#14-how-to-verify-token-receipt-after-transfer)
15. [Troubleshooting](#15-troubleshooting)
16. [Deployed address reference](#16-deployed-address-reference)
17. [Useful links](#17-useful-links)

---

## 1. What the script does

The `create-warp-sealevel.sh` automates the full deploy and configuration of a Hyperlane Warp Route on **Solana (Sealevel)**, connected to Terra Classic.

For each chosen **token + Solana network** pair, the script automatically executes:

| Step | Component | What it is | Why it is needed |
|-------|-----------|---------|---------------------|
| 1 | **Warp Route (Program)** | Solana SPL program deployed via `warp-route deploy` | Entry/exit point on Solana |
| 2 | **ISM** | MultisigISM (`multisig-ism-message-id`) | Validates that messages came from Terra Classic |
| 3 | **IGP** | Interchain Gas Paymaster (Overhead IGP) | Estimates and charges gas for execution on Terra Classic |
| 4 | **Destination Gas** | `set-destination-gas-amount` | Configures gas cost for the Terra Classic domain |
| 5 | **enrollRemoteRouter** | Enrolls the Terra Classic Warp on Solana | Authorizes Solana to accept messages from Terra Classic |
| 6 | **set_route (Terra)** | Calls `router.set_route` on the Terra Classic Warp | Authorizes Terra Classic to send to Solana |

---

## 2. Sealevel vs EVM differences

| Aspect | EVM (Sepolia, BSC...) | Sealevel (Solana) |
|---------|----------------------|-------------------|
| Warp Deploy | `hyperlane warp deploy` (TS CLI) | `warp-route deploy` (Rust client) |
| Router address | 20-byte hex address (EVM address) | Program ID base58 (32 bytes) |
| Hook | AggregationHook = MerkleTree + IGP | No AggregationHook — IGP configured directly |
| ISM | `messageIdMultisigIsm` (EVM contract) | `multisig-ism-message-id` (Solana program) |
| IGP | `TerraClassicIGPStandalone.sol` | Native Overhead IGP of Hyperlane Solana |
| SPL Token | — | Mint Address automatically created during deploy |
| Tools | Foundry (cast/forge), hyperlane CLI | Rust (cargo), solana-cli |
| Image metadata | Not required | URL must exist and be accessible (or empty string `""`) |

> **Important:** On Sealevel, the **AggregationHook is not needed**. The Solana validator uses `MerkleTree` internally — the IGP is configured as a separate program, not as a Warp hook.

---

## 3. Prerequisites

### Required tools

| Tool | Min version | Installation |
|-----------|--------------|-----------|
| `bash` | 4+ | native on Linux/macOS |
| `jq` | 1.6+ | `apt install jq` |
| `python3` | 3.8+ | native on Linux |
| `node` + `npm` | Node 18+ | `nvm install 18` |
| `cargo` (Rust) | 1.70+ | `curl https://sh.rustup.rs -sSf \| sh` |
| `solana` CLI | 1.18+ | [https://docs.solana.com/cli/install-solana-cli-tools](https://docs.solana.com/cli/install-solana-cli-tools) |

### Required Node.js packages

The script uses `@cosmjs/cosmwasm-stargate` to execute transactions on Terra Classic.  
Install at the root of the `cw-hyperlane` project:

```bash
cd ~/cw-hyperlane
npm install @cosmjs/cosmwasm-stargate @cosmjs/proto-signing
```

### Sealevel Rust client binary

The Solana Warp deploy uses the Hyperlane Monorepo Rust client:

```bash
cd /home/lunc/hyperlane-monorepo/rust/sealevel
cargo build --release -p hyperlane-sealevel-client
# Binário: target/release/hyperlane-sealevel-client
```

### Solana Keypair

You need a Solana keypair JSON file with sufficient balance (minimum ~1 SOL for deploy):

```bash
solana-keygen new --outfile /home/lunc/keys/solana-keypair-MEU_PUBKEY.json
solana airdrop 2 --url https://api.testnet.solana.com MEU_PUBKEY
```

### Terra Classic private key

Export before running the script:

```bash
export TERRA_PRIVATE_KEY="your_terra_private_key_in_hex"
```

---

## 4. File structure

```
terraclassic/
├── create-warp-sealevel.sh       # Main script
├── warp-sealevel-config.json     # Solana networks config + warp tokens
├── warp-evm-config.json          # Terra Classic tokens config (shared with EVM)
├── .warp-sealevel-state.json     # Last deploy state (automatically generated)
├── log/
│   ├── create-warp-sealevel.log      # Execution log
│   └── WARP-SOLANATESTNET-XPTO.txt   # Final report generated after deploy (example)
└── docs/
    └── create-warp-sealevel-guide.md  # This document

warp/solana/
├── metadata-xpto.json            # SPL metadata for XPTO
├── metadata-xptv.json            # SPL metadata for XPTV
├── metadata-xpv.json             # SPL metadata for XPV
├── metadata-ustc.json            # SPL metadata for USTC
└── metadata.json                 # SPL metadata for wLUNC
```

---

## 5. Configuring `warp-sealevel-config.json`

This file centralizes all configuration for Solana networks and deployed Warp tokens.

### 5.1 Section `networks`

```json
{
  "networks": {
    "solanatestnet": {
      "enabled": true,
      "display_name": "Solana Testnet",
      "environment": "testnet",
      "domain": 1399811150,
      "rpc": "https://api.testnet.solana.com",
      "explorer": "https://explorer.solana.com/?cluster=testnet",
      "keypair": "/path/to/solana-keypair.json",
      "monorepo_dir": "/home/lunc/hyperlane-monorepo/rust/sealevel",
      "ism": {
        "program_id": "5FgXjCJ8hw1hDbYhvwMB7PFN6oBhVcHuLo3ABoYynMZh",
        "threshold": 1
      },
      "igp": {
        "program_id": "5p7Hii6CJL4xGBYYTGEQmH9LnUSZteFJUu9AVLDExZX2",
        "account": "E9i32KsKGQZMYTguZ81VHUueNvpTGh7nb9J5bRif4xT1",
        "destination_gas_terra": 3000000
      },
      "warp_tokens": { ... }
    }
  }
}
```

| Field | Description |
|-------|-----------|
| `enabled` | `true` to enable the network in the menu. Use `false` to hide |
| `domain` | Hyperlane domain of the network. Solana Testnet = `1399811150`, Mainnet = `1399811149` |
| `keypair` | Absolute path to the Solana keypair `.json` file |
| `monorepo_dir` | Path to `hyperlane-monorepo/rust/sealevel` (where the binary lives) |
| `ism.program_id` | MultisigISM Program ID that validates messages from Terra Classic |
| `ism.threshold` | Minimum number of validators to accept the message |
| `igp.program_id` | Overhead IGP Program ID |
| `igp.account` | Public IGP account (used as `interchainGasPaymaster` in token-config) |
| `igp.destination_gas_terra` | Gas units used on Terra Classic (default: `3000000`) |

### 5.2 Section `warp_tokens`

```json
"warp_tokens": {
  "xpto": {
    "deployed": true,
    "type": "synthetic",
    "program_id": "FNzjjdex7mx5CpcA5NmWtUcL4wZ1J2xctT4qbQ1RrSrq",
    "program_hex": "0xd5a618e0c5bcb84675444410b4981e512af1bf3e04ac9dbdbe3618e0496c11b6",
    "mint_address": "FmSCs8FcQPwXdw5Y4uvAPLfGAXqg8iQpwuiqUxosiu4M",
    "metadata_uri": "https://raw.githubusercontent.com/igorv43/cw-hyperlane/refs/heads/main/warp/solana/metadata-xpto.json",
    "decimals": 6,
    "owner": "EMAYGfEyhywUyEX6kfG5FZZMfznmKXM8PbWpkJhJ9Jjd"
  }
}
```

| Field | Description |
|-------|-----------|
| `deployed` | `true` after successful deploy. Script skips deploy if `true` and `program_id` is filled |
| `type` | `"synthetic"` for CW20/native tokens that become SPL on Solana |
| `program_id` | Base58 Program ID of the Warp Route on Solana (filled after deploy) |
| `program_hex` | Same Program ID in hex bytes32 with `0x` (filled automatically) |
| `mint_address` | Base58 address of the created SPL token (filled after deploy) |
| `metadata_uri` | URL of the token JSON metadata (see section 7). Can be `""` to omit |
| `decimals` | Token decimals (must match the token on Terra Classic) |
| `owner` | Pubkey of the Solana owner/deployer |

### 5.3 Adding a new token

1. Add the entry in `warp-evm-config.json` → `.terra_classic.tokens.MY_TOKEN` (see [section 6](#6-configuring-warp-evm-configjson-terra-classic-tokens))

2. Add in `warp-sealevel-config.json` → `.networks.solanatestnet.warp_tokens`:

```json
"meu_token": {
  "_comment": "MY_TOKEN CW20 → synthetic token on Solana",
  "deployed": false,
  "type": "synthetic",
  "program_id": "",
  "program_hex": "",
  "mint_address": "",
  "metadata_uri": "https://raw.githubusercontent.com/YOUR_USER/YOUR_REPO/main/warp/solana/metadata-my_token.json",
  "decimals": 6,
  "owner": "YOUR_SOLANA_PUBKEY"
}
```

3. Create the metadata file `warp/solana/metadata-my_token.json` (see [section 7](#7-token-metadata-solana))

4. Run the script normally.

### 5.4 Enabling Solana Mainnet

1. Fill all fields of the `"solana"` section in `warp-sealevel-config.json` with real mainnet addresses
2. Change `"enabled": false` to `"enabled": true`
3. Configure `keypair` with a path to a Solana Mainnet keypair with balance
4. The script will show the network in the menu automatically

---

## 6. Configuring `warp-evm-config.json` (Terra Classic tokens)

The script uses `warp-evm-config.json` to get Terra Classic token data (TC Warp address, domain, token type, etc.). This is the same file shared with the EVM script.

Relevant structure for Sealevel:

```json
{
  "terra_classic": {
    "domain": 1325,
    "chain_id": "rebel-2",
    "rpc": "https://rpc.terra-classic.hexxagon.dev",
    "lcd": "https://terra-classic-lcd.publicnode.com",
    "tokens": {
      "xpto": {
        "name": "XPTO Token",
        "symbol": "XPTO",
        "decimals": 6,
        "image": "https://...",
        "terra_warp": {
          "type": "cw20",
          "mode": "collateral",
          "deployed": true,
          "warp_address": "terra16ql6l4fuudg0fxarcm4ukxlw0jalg5ljv8kg6h8f7dk9t2e7y6ssq2hqrm",
          "warp_hexed":   "0xd03fafd53ce350f49ba3c6ebcb1bee7cbbf453f261ec8d5ce9f36c55ab3e26a1",
          "collateral_address": "terra1zle6pwm9aztwu228e0spxrydlvmhj2qrq8ap3x2wrjc52kdvu4fs20rkch",
          "owner": "terra12awgqgwm2evj05ndtgs0xa35uunlpc76d85pze"
        }
      }
    }
  }
}
```

> The Terra Classic Warp (`warp_address`) must be deployed before running the Sealevel script, since the script needs to register the Solana ↔ Terra route on both sides.

---

## 7. Token metadata (Solana)

The Rust client validates the metadata when deploying the SPL token. The file must be available via HTTP(S).

### File format (`warp/solana/metadata-xpto.json`)

```json
{
  "name": "XPTO Token",
  "symbol": "XPTO",
  "description": "XPTO Token via Hyperlane Warp Route",
  "image": "",
  "attributes": []
}
```

| Field | Required | Description |
|-------|-------------|-----------|
| `name` | ✅ Yes | Full token name |
| `symbol` | ✅ Yes | Symbol (ticker) |
| `description` | ✅ Yes | Brief description |
| `image` | ❌ Optional | Image URL (PNG/SVG). Can be `""` to omit |
| `attributes` | ❌ Optional | Array of additional attributes |

> **Note:** If `image` is `""` (empty string), the Rust client accepts it without validation (behavior fixed in the local patch). If you want a logo, use a direct public URL (e.g.: raw.githubusercontent.com).

### The script auto-detects URI accessibility

- If `metadata_uri` returns **HTTP 200** → the `uri` field is included in `token-config.json` → SPL token will have on-chain metadata
- If `metadata_uri` returns **HTTP 404** or is **empty** → the `uri` field is **omitted** → SPL token is created without on-chain metadata (you can update later)

To host the metadata on GitHub, commit the file and use the raw URL:

```
https://raw.githubusercontent.com/SEU_USUARIO/SEU_REPO/refs/heads/main/warp/solana/metadata-TOKEN.json
```

---

## 8. Running the script

### 8.1 Full execution (from scratch)

```bash
cd ~/cw-hyperlane/terraclassic

# Export keys
export TERRA_PRIVATE_KEY="your_terra_private_key_hex"
# (ETH_PRIVATE_KEY not needed — the script is Solana + Terra Classic only)

chmod +x create-warp-sealevel.sh
./create-warp-sealevel.sh
```

The script will:
1. Check tools and configurations
2. Display menu to select the **token** (from Terra Classic)
3. Display menu to select the **Solana network**
4. Execute the 6 steps automatically
5. Write a report `log/WARP-SOLANATESTNET-TOKEN.txt`

### 8.2 Skipping already executed steps

Use environment variables to skip specific steps:

| Variable | Effect |
|----------|--------|
| `export WARP_PROGRAM_ID="Base58ID"` | Skips Solana Warp deploy (uses existing program) |
| `export SKIP_ISM="1"` | Skips ISM configuration |
| `export SKIP_IGP="1"` | Skips IGP configuration |
| `export SKIP_GAS="1"` | Skips `set-destination-gas-amount` |
| `export SKIP_ENROLL="1"` | Skips `enroll-remote-router` (Solana → Terra Classic) |
| `export SKIP_TC_ROUTE="1"` | Skips `set_route` on Terra Classic (Terra → Solana) |

Example: token already deployed, only reconfigure the Terra Classic route:

```bash
export TERRA_PRIVATE_KEY="..."
export WARP_PROGRAM_ID="FNzjjdex7mx5CpcA5NmWtUcL4wZ1J2xctT4qbQ1RrSrq"
export SKIP_ISM="1"
export SKIP_IGP="1"
export SKIP_GAS="1"
export SKIP_ENROLL="1"
./create-warp-sealevel.sh
```

### 8.3 Resuming after failure

The script saves state in `.warp-sealevel-state.json`. If there is a failure, the state is automatically restored on the next execution **for the same token + network**.

To discard the state and start from scratch:

```bash
rm -f ~/cw-hyperlane/terraclassic/.warp-sealevel-state.json
```

---

## 9. What the script configures — Detailed steps

### Step 1 — Deploy Warp Route on Solana

The script generates a `token-config.json` and calls:

```bash
hyperlane-sealevel-client \
  -k /caminho/keypair.json \
  -u https://api.testnet.solana.com \
  warp-route deploy \
  --warp-route-name TOKEN \
  --environment testnet \
  --environments-dir .../environments \
  --token-config-file .../token-config.json \
  --built-so-dir .../target/deploy \
  --registry ~/.hyperlane/registry \
  --ata-payer-funding-amount 5000000
```

**Result:** Program ID + Mint Address of the SPL token.

The generated `token-config.json` has the format:

```json
{
  "solanatestnet": {
    "type": "synthetic",
    "name": "XPTO Token",
    "symbol": "XPTO",
    "decimals": 6,
    "totalSupply": "0",
    "interchainGasPaymaster": "E9i32KsKGQZMYTguZ81VHUueNvpTGh7nb9J5bRif4xT1",
    "uri": "https://raw.githubusercontent.com/..."
  }
}
```

### Step 2 — Configure ISM

Defines which ISM program the Warp Route should use to validate received messages. The script uses the `token set-interchain-security-module` command of the Rust client:

```bash
hyperlane-sealevel-client \
  -k /caminho/keypair.json \
  -u https://api.testnet.solana.com \
  token set-interchain-security-module \
  --program-id WARP_PROGRAM_ID \
  --ism ISM_PROGRAM_ID
```

> **Important difference:** This command associates the ISM *with the Warp token*, it does not register validators in the ISM. The Solana ISM (`5FgXjCJ8hw1hDbYhvwMB7PFN6oBhVcHuLo3ABoYynMZh`) must already have the Terra Classic validators pre-registered via `multisig-ism-message-id enroll-validators` (done once, separately, when setting up the Hyperlane infrastructure).

### Step 3 — Configure IGP

Associates the IGP program and IGP account with the Warp Route, so gas calculation is done correctly on the Solana side:

```bash
hyperlane-sealevel-client \
  -k /caminho/keypair.json \
  -u https://api.testnet.solana.com \
  token igp \
  --program-id WARP_PROGRAM_ID \
  set IGP_PROGRAM_ID igp IGP_ACCOUNT
```

### Step 4 — Destination Gas

Defines the gas amount (in Terra Classic units) that the Solana Warp will estimate for messages going to Terra Classic:

```bash
hyperlane-sealevel-client \
  -k /caminho/keypair.json \
  -u https://api.testnet.solana.com \
  token set-destination-gas \
  --program-id WARP_PROGRAM_ID \
  TERRA_DOMAIN DEST_GAS_AMOUNT
# e.g.: TERRA_DOMAIN = 1325, DEST_GAS_AMOUNT = 3000000
```

### Step 5 — Enroll Remote Router (Solana → Terra Classic)

Registers the Terra Classic Warp as an authorized route on the Solana Warp:

```bash
hyperlane-sealevel-client \
  -k /caminho/keypair.json \
  -u https://api.testnet.solana.com \
  token enroll-remote-router \
  --program-id WARP_PROGRAM_ID \
  TERRA_DOMAIN 0xTERRA_WARP_HEX_32BYTES
# e.g.: 1325 0xd03fafd53ce350f49ba3c6ebcb1bee7cbbf453f261ec8d5ce9f36c55ab3e26a1
```

### Step 6 — Set Route (Terra Classic → Solana)

Registers the Solana Warp as an authorized route on the Terra Classic Warp (via Node.js + CosmJS):

```js
// Message executed on the terra_warp_address contract
// ⚠️ IMPORTANT: the "route" field must be 32-byte hex WITHOUT the "0x" prefix
{
  "router": {
    "set_route": {
      "set": {
        "domain": 1399811150,
        "route": "0adafdae59c217a1b7409f65ca81505f9991c257be80af8902ebed96d8801ba6"
      }
    }
  }
}
```

> **Note:** The Terra Classic CosmWasm contract **rejects** the `0x` prefix in the route — use only the 64 hex characters without prefix.

> **Smart verification:** The script checks not only whether the route exists, but also whether it points to the correct Program ID. If it points to an old Program ID (from a previous failed deploy), the route is **automatically updated**.

---

## 10. Updating the JSON after deploy

After a successful deploy, **update `warp-sealevel-config.json`** to record the addresses:

```json
"xpto": {
  "deployed": true,
  "type": "synthetic",
  "program_id": "jNkiNLXQetj9L2tDX6xTgx9QP1tgtNgYXamouNbbwx9",
  "program_hex": "0x0adafdae59c217a1b7409f65ca81505f9991c257be80af8902ebed96d8801ba6",
  "mint_address": "Db8VbMerYxksYwSSdetpy6Jhp2BrE4hk9Sh9dYJT5dQ2",
  "metadata_uri": "https://raw.githubusercontent.com/igorv43/cw-hyperlane/refs/heads/main/warp/solana/metadata-xpto.json",
  "decimals": 6,
  "owner": "EMAYGfEyhywUyEX6kfG5FZZMfznmKXM8PbWpkJhJ9Jjd"
}
```

> The script writes a report `log/WARP-SOLANATESTNET-TOKEN.txt` with all addresses. Use it as a reference.

---

## 11. Manual deploy and configuration (without the script)

### 11.1 Generate token-config.json manually

```json
{
  "solanatestnet": {
    "type": "synthetic",
    "name": "NOME_TOKEN",
    "symbol": "SYM",
    "decimals": 6,
    "totalSupply": "0",
    "interchainGasPaymaster": "IGP_ACCOUNT_BASE58",
    "uri": "https://METADATA_URL.json"
  }
}
```

Save to: `environments/testnet/warp-routes/TOKEN/token-config.json`

### 11.2 Deploy Solana Warp

```bash
cd /home/lunc/hyperlane-monorepo/rust/sealevel

./target/release/hyperlane-sealevel-client \
  -k /caminho/keypair.json \
  -u https://api.testnet.solana.com \
  warp-route deploy \
  --warp-route-name TOKEN \
  --environment testnet \
  --environments-dir ./environments \
  --token-config-file ./environments/testnet/warp-routes/TOKEN/token-config.json \
  --built-so-dir ./target/deploy \
  --registry ~/.hyperlane/registry \
  --ata-payer-funding-amount 5000000
```

After deploy, the Program ID and Mint Address are saved in:
```
environments/testnet/warp-routes/TOKEN/program-ids.json
```

### 11.3 Configure ISM manually

```bash
./target/release/hyperlane-sealevel-client \
  -k /caminho/keypair.json \
  -u https://api.testnet.solana.com \
  multisig-ism-message-id enroll-validators \
  --program-id 5FgXjCJ8hw1hDbYhvwMB7PFN6oBhVcHuLo3ABoYynMZh \
  --domains 1325 \
  --validators 0xTERRA_VALIDATOR_ADDRESS \
  --threshold 1
```

> To find the Terra Classic validator address:  
> Consult `ValidatorAnnounce` on Terra Classic or see `agent-config.json`.

### 11.4 Configure Destination Gas manually

```bash
./target/release/hyperlane-sealevel-client \
  -k /caminho/keypair.json \
  -u https://api.testnet.solana.com \
  igp set-destination-gas-amount \
  --program-id 5p7Hii6CJL4xGBYYTGEQmH9LnUSZteFJUu9AVLDExZX2 \
  --destination-domain 1325 \
  --gas-amount 3000000
```

### 11.5 Enroll Remote Router (Solana → Terra Classic) manually

```bash
./target/release/hyperlane-sealevel-client \
  -k /caminho/keypair.json \
  -u https://api.testnet.solana.com \
  warp-route enroll-remote-router \
  --program-id PROGRAM_ID_DO_WARP_SOLANA \
  --destination-domain 1325 \
  --router 0xTERRA_WARP_HEX_32BYTES
```

> The Terra Classic Warp hex can be obtained from `warp-evm-config.json` → `terra_classic.tokens.TOKEN.terra_warp.warp_hexed`  
> Or converting manually:
> ```bash
> python3 -c "
> import bech32
> _, data = bech32.decode('terra', 'terra16ql...')
> print('0x' + bytes(bech32.convertbits(data, 5, 8, False)).hex().zfill(64))
> "
> ```

### 11.6 Set Route (Terra Classic → Solana) manually

> ⚠️ **Important:** The `route` field must be the 32-byte hex of the Solana Program ID **without the `0x` prefix**. The CosmWasm contract rejects the `0x...` format with an `invalid hex` error.

To convert the base58 Program ID to hex without `0x`:

```bash
python3 -c "
import base58
program_id = 'jNkiNLXQetj9L2tDX6xTgx9QP1tgtNgYXamouNbbwx9'
print(base58.b58decode(program_id).hex())
# output: 0adafdae59c217a1b7409f65ca81505f9991c257be80af8902ebed96d8801ba6
"
```

Using Node.js directly (no keyring key needed — recommended method):

```bash
export TERRA_PRIVATE_KEY="your_private_key_hex"

node - <<'EOF'
const { SigningCosmWasmClient } = require("@cosmjs/cosmwasm-stargate");
const { DirectSecp256k1Wallet } = require("@cosmjs/proto-signing");
const { GasPrice } = require("@cosmjs/stargate");

async function main() {
  const privkeyHex = process.env.TERRA_PRIVATE_KEY;
  const privkeyBytes = Buffer.from(privkeyHex, "hex");
  const wallet = await DirectSecp256k1Wallet.fromKey(privkeyBytes, "terra");
  const [account] = await wallet.getAccounts();
  const client = await SigningCosmWasmClient.connectWithSigner(
    "https://rpc.terra-classic.hexxagon.dev",
    wallet,
    { gasPrice: GasPrice.fromString("0.015uluna") }
  );

  // ⚠️ route = 32-byte hex WITHOUT "0x"
  const programHex = "0adafdae59c217a1b7409f65ca81505f9991c257be80af8902ebed96d8801ba6";

  const result = await client.execute(
    account.address,
    "TERRA_WARP_ADDRESS",                           // e.g.: terra16ql6l4fu...
    { router: { set_route: { set: { domain: 1399811150, route: programHex } } } },
    "auto",
    "set_route TC → Solana"
  );
  console.log("TX:", result.transactionHash);
}
main().catch(e => { console.error(e); process.exit(1); });
EOF
```

Verify if the route was saved correctly:

```bash
terrad query wasm contract-state smart TERRA_WARP_ADDRESS \
  '{"router":{"get_route":{"domain":1399811150}}}' \
  --node https://rpc.terra-classic.hexxagon.dev
# Expected output: route: "0adafdae..." (without 0x, or with 0x depending on contract version)
```

> To verify using the full route list:
> ```bash
> terrad query wasm contract-state smart TERRA_WARP_ADDRESS \
>   '{"router":{"list_routes":{}}}' \
>   --node https://rpc.terra-classic.hexxagon.dev
> ```

---

## 12. How to verify state after deploy

### Verify Solana Warp (token query)

```bash
cd /home/lunc/hyperlane-monorepo/rust/sealevel

./target/release/hyperlane-sealevel-client \
  -k /caminho/keypair.json \
  -u https://api.testnet.solana.com \
  token query \
  --program-id PROGRAM_ID_BASE58 \
  synthetic
```

**Expected output:** Name, symbol, decimals, mint address, ISM program.

### Verify Solana ISM

```bash
./target/release/hyperlane-sealevel-client \
  -k /caminho/keypair.json \
  -u https://api.testnet.solana.com \
  multisig-ism-message-id query \
  --program-id 5FgXjCJ8hw1hDbYhvwMB7PFN6oBhVcHuLo3ABoYynMZh \
  --domains 1325
```

**Expected output:** Threshold = 1, registered validator = Terra Classic validator address.

### Verify route on Terra Classic

```bash
terrad query wasm contract-state smart TERRA_WARP_ADDRESS \
  '{"router":{"get_route":{"domain":1399811150}}}' \
  --node https://rpc.terra-classic.hexxagon.dev
```

**Expected output:** `route: "0adafdae59c217a1b7409f65ca81505f9991c257be80af8902ebed96d8801ba6"` (32-byte hex of the Solana Program ID).

> ⚠️ **Attention:** Verify that the returned hex corresponds to the **real Program ID on Solana** (not a previous failed deploy). To confirm:
> ```bash
> solana account PROGRAM_ID_BASE58 --url https://api.testnet.solana.com
> # Should return account data. "AccountNotFound" = deploy did not happen.
> ```
> If the route points to an old Program ID, fix it using the manual method in section 11.6.

### Verify route on Solana Warp (Remote Router)

In the Solana Explorer, access the Warp Program ID and check the associated accounts.  
Or use the Rust query:

```bash
./target/release/hyperlane-sealevel-client \
  -k /caminho/keypair.json \
  -u https://api.testnet.solana.com \
  warp-route query \
  --program-id PROGRAM_ID_BASE58
```

---

## 13. How to find Hyperlane addresses on Solana

### Using the Hyperlane Registry

The Hyperlane Registry is at `~/.hyperlane/registry/` after installing the CLI:

```bash
npm install -g @hyperlane-xyz/cli@latest
```

To list Solana Testnet addresses:

```bash
hyperlane registry list
# or querying directly:
cat ~/.hyperlane/registry/chains/solanatestnet/addresses.yaml
```

### Official Solana Testnet addresses (Hyperlane)

| Contract | Program ID |
|---------|-----------|
| Mailbox | `692KZJaoe2KRcD6uhCTDTeHbkoxHSFDMm5TKAwA7v2fE` |
| IGP (Overhead) | `5p7Hii6CJL4xGBYYTGEQmH9LnUSZteFJUu9AVLDExZX2` |
| IGP Account | `E9i32KsKGQZMYTguZ81VHUueNvpTGh7nb9J5bRif4xT1` |
| MultisigISM | `5FgXjCJ8hw1hDbYhvwMB7PFN6oBhVcHuLo3ABoYynMZh` |
| ValidatorAnnounce | `DH43ae1LwemXAboWwSh8zc9pG8j72gKUEXNi57w8SPSN` |

### Hyperlane Domains

| Network | Domain ID |
|------|-----------|
| Terra Classic (rebel-2) | `1325` |
| Solana Testnet | `1399811150` |
| Solana Mainnet | `1399811149` |
| Sepolia | `11155111` |
| BSC Testnet | `97` |

> Official source: [https://docs.hyperlane.xyz/docs/reference/domains](https://docs.hyperlane.xyz/docs/reference/domains)

---

## 14. How to verify token receipt after transfer

> ⚠️ **Attention:** Tokens arriving via Warp Route are **CW20 tokens** (Terra Classic) or **SPL tokens** (Solana). They **do not appear as native balance** (LUNA / SOL) in the wallet — you need to query the specific contract.

---

### 14.1 Check CW20 balance on Terra Classic (destination: Solana → Terra Classic)

When you send tokens from Solana to Terra Classic, the tokens arrive as CW20 in the Warp Collateral (the collateral address that was locked before).

**Verify via terminal:**

```bash
# Replace:
# - CW20_CONTRACT = CW20 contract address (terra1zle6...)
# - RECIPIENT      = recipient address on Terra Classic

terrad query wasm contract-state smart \
  CW20_CONTRACT \
  '{"balance":{"address":"RECIPIENT"}}' \
  --node https://rpc.terra-classic.hexxagon.dev:443
```

**Real example (XPTO):**

```bash
terrad query wasm contract-state smart \
  terra1zle6pwm9aztwu228e0spxrydlvmhj2qrq8ap3x2wrjc52kdvu4fs20rkch \
  '{"balance":{"address":"terra18lr7ujd9nsgyr49930ppaajhadzrezam70j39k"}}' \
  --node https://rpc.terra-classic.hexxagon.dev:443
# Output: data: { balance: "99515999100" }
#         = 99,515.999 XPTO (divide by 10^6 for decimals=6)
```

**Verify via Explorer:**

Access `https://finder.hexxagon.io/rebel-2/address/RECIPIENT` and look for the **"CW20 Tokens"** or **"Token Balances"** tab.

---

### 14.2 Check SPL balance on Solana (destination: Terra Classic → Solana)

When you send tokens from Terra Classic to Solana, the tokens arrive as SPL in the associated account (ATA — Associated Token Account) of the recipient.

**Verify via terminal:**

```bash
# List all SPL tokens of a Solana account
spl-token accounts --owner DESTINATARIO_PUBKEY --url https://api.testnet.solana.com

# Or check balance of a specific Mint
spl-token balance --owner DESTINATARIO_PUBKEY MINT_ADDRESS --url https://api.testnet.solana.com
```

**Real example (XPTO):**

```bash
spl-token balance \
  --owner EMAYGfEyhywUyEX6kfG5FZZMfznmKXM8PbWpkJhJ9Jjd \
  Db8VbMerYxksYwSSdetpy6Jhp2BrE4hk9Sh9dYJT5dQ2 \
  --url https://api.testnet.solana.com
```

**Verify via Explorer:**

Access `https://explorer.solana.com/address/RECIPIENT?cluster=testnet` and look for the **"Tokens"** tab.

---

### 14.3 Verify if the message was delivered to the Terra Classic Mailbox

To confirm that the message was processed (regardless of the wallet):

```bash
MAILBOX="terra1s4jwfe0tcaztpfsct5wzj02esxyjy7e7lhkcwn5dp04yvly82rwsvzyqmm"
MESSAGE_ID="YOUR_MESSAGE_ID_WITHOUT_0x"  # e.g.: 830a1e166747001c54097299...

terrad query wasm contract-state smart "$MAILBOX" \
  "{\"mailbox\":{\"message_delivered\":{\"id\":\"${MESSAGE_ID}\"}}}" \
  --node https://rpc.terra-classic.hexxagon.dev:443
# Output: data: { delivered: true }  ← message delivered successfully
# Output: data: { delivered: false } ← still pending (relayer has not processed)
```

---

### 14.4 Trace a message step by step

Given the **message ID** of a Solana → Terra Classic transfer, check in order:

| Step | Verification | URL / Command |
|-------|-------------|--------------|
| 1 | TX on Solana | `https://explorer.solana.com/tx/TX_HASH?cluster=testnet` |
| 2 | TC validator checkpoints | `https://hyperlane-validator-signatures-igorveras-terraclassic.s3.us-east-1.amazonaws.com/` |
| 3 | Delivery in TC Mailbox | `terrad query wasm ... message_delivered {id: "..."}` |
| 4 | CW20 balance at recipient | `terrad query wasm ... balance {address: "..."}` |

> **Tip:** If `delivered: true` but the balance does not appear in the wallet — the token arrived! The wallet may not display CW20 tokens. Use the `terrad query wasm` command to confirm.

---

## 15. Troubleshooting

### ❌ `RelativeUrlWithoutBase` when validating metadata

**Cause:** The `image` field in the JSON metadata is `""` (empty string) and the Rust client tried to `GET("")`.

**Fix:** The repository contains a patch in `warp_route.rs` that makes the `image` field optional. To reapply if the monorepo is updated:

```rust
// warp_route.rs, validate() function
// Replace the image validation block with:
if let Some(image_url) = &self.image {
    if !image_url.is_empty() {
        let image = reqwest::blocking::get(image_url).unwrap();
        assert!(image.status().is_success(), ...);
    }
}
```

Then recompile:

```bash
cd /home/lunc/hyperlane-monorepo/rust/sealevel
cargo build --release -p hyperlane-sealevel-client
```

### ❌ `Failed to parse metadata JSON: reqwest::Error { kind: Decode ... integer 404 }`

**Cause:** The configured `metadata_uri` returns HTTP 404 (file does not exist on GitHub yet).

**Fix:** The script detects the HTTP code and automatically omits the `uri` field from `token-config.json`. The deploy proceeds without on-chain metadata. To add the metadata later, commit the JSON file to GitHub and re-run only the metadata step.

### ❌ `error: Found argument '--use-rpc' which wasn't expected`

**Cause:** The installed Solana CLI is **older than v1.16** and does not recognize the `--use-rpc` flag that the Hyperlane Rust client adds by default. The deploy fails on all attempts, but the script may have generated a `log/WARP-*.txt` with local Program IDs **that never reached the testnet** (the addresses are from locally generated keypairs, not real on-chain accounts).

**How to verify if the deploy really happened:**

```bash
solana account PROGRAM_ID --url https://api.testnet.solana.com
# If it returns "AccountNotFound" → deploy did not happen
```

**Fix — Patch in the Rust code (does not require CLI update):**

```bash
# 1. Edit the file
nano /home/lunc/hyperlane-monorepo/rust/sealevel/client/src/cmd_utils.rs
# Find and remove the line:   "--use-rpc",

# 2. Recompile
cd /home/lunc/hyperlane-monorepo/rust/sealevel
cargo build --release -p hyperlane-sealevel-client

# 3. Clean up keypairs from the failed deploy
rm -f environments/testnet/warp-routes/TOKEN/keys/*.json

# 4. Reset the state and config
rm -f ~/cw-hyperlane/terraclassic/.warp-sealevel-state.json
# In warp-sealevel-config.json: set deployed:false, program_id:"", mint_address:""

# 5. Re-run the script
./create-warp-sealevel.sh
```

> **Alternative:** Update the Solana CLI to v1.16+:
> ```bash
> sh -c "$(curl -sSfL https://release.solana.com/stable/install)"
> ```

---

### ❌ `warp-route deploy failed (exit 101)`

**Cause:** Could be:
1. Insufficient balance in the Solana keypair
2. Invalid `token-config.json` file
3. `.so` (program bytecode) not compiled

**Diagnosis:**

```bash
# Check balance
solana balance PUBKEY --url https://api.testnet.solana.com

# Check if the .so exists
ls /home/lunc/hyperlane-monorepo/rust/sealevel/target/deploy/*.so

# View full log
cat ~/cw-hyperlane/terraclassic/log/create-warp-sealevel.log
```

**Fix for missing .so:**

```bash
cd /home/lunc/hyperlane-monorepo/rust/sealevel
cargo build-bpf   # ou: cargo build-sbf
```

### ❌ `account sequence mismatch` on Terra Classic

**Cause:** The Terra Classic RPC is outdated.

**Fix:** Use the synchronized RPC:

```bash
# In warp-evm-config.json:
"rpc": "https://rpc.terra-classic.hexxagon.dev"
```

### ❌ Message sent (Solana → Terra Classic) but does not arrive

**Diagnosis:**
1. Check if the relayer has Solana configured in `relayChains`
2. Check if the Terra Classic ISM has the Solana validator registered
3. Check if the Solana validator is making checkpoints on S3

```bash
# Check validator announcement (replace with your S3 URL)
curl https://hyperlane-validator-signatures-SEU_BUCKET.s3.us-east-1.amazonaws.com/announcement.json
```

### ❌ Message sent (Terra Classic → Solana) but does not arrive

**Diagnosis — checklist in order:**

**1. Verify if the route on Terra Classic points to the CORRECT Program ID**

This is the most common error after a silently failed deploy. The `set_route` may have registered the Program ID from a previous deploy (that does not exist on-chain):

```bash
# Get the current route on Terra Classic
terrad query wasm contract-state smart terra16ql6l4fuudg0fxarcm4ukxlw0jalg5ljv8kg6h8f7dk9t2e7y6ssq2hqrm \
  '{"router":{"list_routes":{}}}' \
  --node https://rpc.terra-classic.hexxagon.dev

# Confirm if the Program ID exists on Solana
solana account PROGRAM_ID_BASE58 --url https://api.testnet.solana.com
```

If `AccountNotFound` → the route points to an invalid program. Fix as per section 11.6.

**2. Verify if the Solana ISM has the Terra Classic validator registered**

```bash
cd /home/lunc/hyperlane-monorepo/rust/sealevel
./target/release/hyperlane-sealevel-client \
  -k /caminho/keypair.json \
  -u https://api.testnet.solana.com \
  multisig-ism-message-id query \
  --program-id 5FgXjCJ8hw1hDbYhvwMB7PFN6oBhVcHuLo3ABoYynMZh \
  --domains 1325
```

Expected output: `threshold: 1`, validator = Terra Classic validator address.

**3. Verify if the Terra Classic validator is making checkpoints**

```bash
# Replace with the S3 URL of your Terra Classic validator
curl https://hyperlane-validator-signatures-NOME.s3.us-east-1.amazonaws.com/announcement.json
# Should return a JSON with "validator", "mailbox_address", "storage_location"
```

**4. Verify if the relayer is monitoring Terra Classic**

Confirm that `relayChains` in the relayer config includes `terraclassic` or domain `1325`.

### ❌ Route on Terra Classic points to old/invalid Program ID

**Symptom:** Messages leave Terra Classic without error, but never reach Solana. The route exists in the contract but points to a program that does not exist on-chain.

**Cause:** A previous deploy was started but failed silently (e.g.: `--use-rpc` error), generating a local Program ID that was never published. The `set_route` registered this invalid ID.

**How to identify:**

```bash
# List all routes configured on the Terra Classic Warp
terrad query wasm contract-state smart TERRA_WARP_ADDRESS \
  '{"router":{"list_routes":{}}}' \
  --node https://rpc.terra-classic.hexxagon.dev

# For each found route, verify on Solana
solana account PROGRAM_ID_BASE58 --url https://api.testnet.solana.com
# "AccountNotFound" = Invalid Program ID
```

**How to fix — run `set_route` with the correct Program ID:**

```bash
export TERRA_PRIVATE_KEY="your_private_key_hex"

node - <<'EOF'
const { SigningCosmWasmClient } = require("@cosmjs/cosmwasm-stargate");
const { DirectSecp256k1Wallet } = require("@cosmjs/proto-signing");
const { GasPrice } = require("@cosmjs/stargate");

async function main() {
  const wallet = await DirectSecp256k1Wallet.fromKey(
    Buffer.from(process.env.TERRA_PRIVATE_KEY, "hex"), "terra"
  );
  const [account] = await wallet.getAccounts();
  const client = await SigningCosmWasmClient.connectWithSigner(
    "https://rpc.terra-classic.hexxagon.dev",
    wallet,
    { gasPrice: GasPrice.fromString("0.015uluna") }
  );

  // Solana Program ID in 32-byte hex, WITHOUT "0x"
  const programHex = "0adafdae59c217a1b7409f65ca81505f9991c257be80af8902ebed96d8801ba6";
  const warpAddr   = "terra16ql6l4fuudg0fxarcm4ukxlw0jalg5ljv8kg6h8f7dk9t2e7y6ssq2hqrm";
  const domain     = 1399811150;

  const result = await client.execute(
    account.address, warpAddr,
    { router: { set_route: { set: { domain, route: programHex } } } },
    "auto", "fix set_route TC → Solana"
  );
  console.log("TX:", result.transactionHash);
}
main().catch(e => { console.error(e); process.exit(1); });
EOF
```

> **The `create-warp-sealevel.sh` script prevents this problem** by automatically verifying whether the existing route points to the correct Program ID before skipping the step.

---

### ❌ `invalid hex` when running `set_route` on Terra Classic

**Cause:** The `route` field was passed with the `0x` prefix. The Terra Classic CosmWasm contract only accepts pure hex (64 characters without prefix).

**Fix:** Remove the `0x` from the `route` field value:

```
❌  "route": "0x0adafdae59c217a1b7409f65ca81505f9991c257be80af8902ebed96d8801ba6"
✅  "route": "0adafdae59c217a1b7409f65ca81505f9991c257be80af8902ebed96d8801ba6"
```

---

### ❌ `gasPriceAmount.multiply is not a function` in Node.js

**Cause:** Incorrect use of `GasPrice` when building the CosmJS client.

**Fix:** Use `GasPrice.fromString(...)` instead of passing a literal object:

```js
// ❌ Wrong:
{ gasPrice: { amount: "28.325", denom: "uluna" } }

// ✅ Correct:
const { GasPrice } = require("@cosmjs/stargate");
{ gasPrice: GasPrice.fromString("0.015uluna") }
```

---

### ❌ `TERRA_PRIVATE_KEY not set`

**Fix:**

```bash
export TERRA_PRIVATE_KEY="your_private_key_hex_without_0x"
./create-warp-sealevel.sh
```

---

## 16. Deployed address reference

### XPTO — Solana Testnet ↔ Terra Classic

> ✅ **Status: Working in production** — bidirectional transfers confirmed (Solana → Terra Classic and Terra Classic → Solana).

| Field | Value |
|-------|-------|
| **Program ID (Solana)** | `jNkiNLXQetj9L2tDX6xTgx9QP1tgtNgYXamouNbbwx9` |
| **Program Hex (32b)** | `0x0adafdae59c217a1b7409f65ca81505f9991c257be80af8902ebed96d8801ba6` |
| **Route (sem 0x, para set_route)** | `0adafdae59c217a1b7409f65ca81505f9991c257be80af8902ebed96d8801ba6` |
| **Mint Address (SPL)** | `Db8VbMerYxksYwSSdetpy6Jhp2BrE4hk9Sh9dYJT5dQ2` |
| **Solana Mailbox (used by Warp)** | `75HBBLae3ddeneJVrZeyrDfv6vb7SMC3aCpBucSXS5aR` |
| **ISM Program** | `5FgXjCJ8hw1hDbYhvwMB7PFN6oBhVcHuLo3ABoYynMZh` |
| **IGP Program** | `5p7Hii6CJL4xGBYYTGEQmH9LnUSZteFJUu9AVLDExZX2` |
| **IGP Account** | `E9i32KsKGQZMYTguZ81VHUueNvpTGh7nb9J5bRif4xT1` |
| **Warp Terra Classic (bech32)** | `terra16ql6l4fuudg0fxarcm4ukxlw0jalg5ljv8kg6h8f7dk9t2e7y6ssq2hqrm` |
| **Warp Terra Hex** | `0xd03fafd53ce350f49ba3c6ebcb1bee7cbbf453f261ec8d5ce9f36c55ab3e26a1` |
| **CW20 Collateral (Terra)** | `terra1zle6pwm9aztwu228e0spxrydlvmhj2qrq8ap3x2wrjc52kdvu4fs20rkch` |
| **Mailbox Terra Classic** | `terra1s4jwfe0tcaztpfsct5wzj02esxyjy7e7lhkcwn5dp04yvly82rwsvzyqmm` |
| **ISM Routing Terra Classic** | `terra1na6ljyf4m5x2u7llfvvxxe2nyq0t8628qyk0vnwu4ttpq86tt0cse47t68` |
| **Multisig ISM Terra Classic** | `terra18gh7nl0tk047ykrvy0a8z2lhv0rvl65wu95texyawrj879qenysq02p98f` |
| **Metadata URI** | `https://raw.githubusercontent.com/igorv43/cw-hyperlane/refs/heads/main/warp/solana/metadata-xpto.json` |
| **Domain Solana Testnet** | `1399811150` |
| **Domain Terra Classic** | `1325` |
| **Deployer (keypair)** | `EMAYGfEyhywUyEX6kfG5FZZMfznmKXM8PbWpkJhJ9Jjd` |

**Verify on-chain:**

```bash
# Solana Warp — confirm the program exists
solana account jNkiNLXQetj9L2tDX6xTgx9QP1tgtNgYXamouNbbwx9 --url https://api.testnet.solana.com

# SPL Mint — confirm the token exists
solana account Db8VbMerYxksYwSSdetpy6Jhp2BrE4hk9Sh9dYJT5dQ2 --url https://api.testnet.solana.com

# Terra Classic → Solana route
terrad query wasm contract-state smart terra16ql6l4fuudg0fxarcm4ukxlw0jalg5ljv8kg6h8f7dk9t2e7y6ssq2hqrm \
  '{"router":{"get_route":{"domain":1399811150}}}' \
  --node https://rpc.terra-classic.hexxagon.dev
```

---

## 17. Useful links

| Resource | URL |
|---------|-----|
| Solana Testnet Explorer | https://explorer.solana.com/?cluster=testnet |
| Terra Classic Explorer | https://finder.hexxagon.io/rebel-2 |
| Hyperlane Docs | https://docs.hyperlane.xyz |
| Hyperlane Domínios | https://docs.hyperlane.xyz/docs/reference/domains |
| Solana CLI | https://docs.solana.com/cli/install-solana-cli-tools |
| Solana Testnet Faucet | https://faucet.solana.com |
| Terra Classic Faucet | https://faucet.terra.dev |
| **Validators — S3 (checkpoints)** | |
| Terra Classic S3 Validator | https://hyperlane-validator-signatures-igorveras-terraclassic.s3.us-east-1.amazonaws.com/announcement.json |
| Sepolia S3 Validator | https://hyperlane-validator-signatures-igorveras-sepolia.s3.us-east-1.amazonaws.com/announcement.json |
| BSC Testnet S3 Validator | https://hyperlane-validator-signatures-igorveras-bsctestnet.s3.us-east-1.amazonaws.com/announcement.json |
| **On-chain contracts (XPTO)** | |
| Terra Classic Mailbox | `terra1s4jwfe0tcaztpfsct5wzj02esxyjy7e7lhkcwn5dp04yvly82rwsvzyqmm` |
| Terra Classic Warp XPTO | `terra16ql6l4fuudg0fxarcm4ukxlw0jalg5ljv8kg6h8f7dk9t2e7y6ssq2hqrm` |
| CW20 XPTO (collateral) | `terra1zle6pwm9aztwu228e0spxrydlvmhj2qrq8ap3x2wrjc52kdvu4fs20rkch` |
| Solana XPTO Program | `jNkiNLXQetj9L2tDX6xTgx9QP1tgtNgYXamouNbbwx9` |
| XPTO SPL Mint | `Db8VbMerYxksYwSSdetpy6Jhp2BrE4hk9Sh9dYJT5dQ2` |
| **Repositories** | |
| Hyperlane Registry GitHub | https://github.com/hyperlane-xyz/hyperlane-registry |
| Hyperlane Monorepo | https://github.com/hyperlane-xyz/hyperlane-monorepo |
| cw-hyperlane (Solana metadata) | https://github.com/igorv43/cw-hyperlane/tree/main/warp/solana |
