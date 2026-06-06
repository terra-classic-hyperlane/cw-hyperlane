# Hyperlane Warp Route — Solana ↔ Terra Classic Deployment Guide

This guide covers the full lifecycle of a Hyperlane Warp Route on Solana Mainnet:
deploying, configuring, and cancelling (closing) the program to recover SOL.

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Repository Structure](#2-repository-structure)
3. [Configuration Files](#3-configuration-files)
   - [warp-sealevel-config.json](#31-warp-sealevel-configjson)
   - [warp-evm-config.json](#32-warp-evm-configjson)
4. [Deployment](#4-deployment)
   - [Full Deploy](#41-full-deploy)
   - [What Each Step Does](#42-what-each-step-does)
   - [Environment Variables](#43-environment-variables)
   - [Skip Flags](#44-skip-flags)
5. [MEV Protection](#5-mev-protection)
6. [Verifying the Deployment](#6-verifying-the-deployment)
7. [Cancelling the Program (Recover SOL)](#7-cancelling-the-program-recover-sol)
   - [Using close-warp-program.sh](#71-using-close-warp-programsh)
   - [Manual Recovery](#72-manual-recovery)
8. [Resuming a Failed Deploy](#8-resuming-a-failed-deploy)
9. [Troubleshooting](#9-troubleshooting)

---

## 1. Prerequisites

| Tool | Version | Purpose |
|------|---------|---------|
| `solana-cli` | ≥ 1.18 | Deploy programs, check accounts |
| `node` | ≥ 18 | jito-warp-init.js (MEV-safe mint init) |
| `cargo` (Rust) | ≥ 1.76 | Hyperlane sealevel client |
| `jq` | any | JSON config parsing |
| `python3` | ≥ 3.8 | Base58/hex conversions |
| `spl-token` CLI | Hyperlane fork | Token-2022 metadata initialization |

**SOL balance required:** ~2.5 SOL minimum per program deployment
- ~1.1 SOL — program binary storage (318 KB)
- ~0.05 SOL — token storage, mint PDA, ATA payer rent
- ~0.005 SOL — priority fee tip for MEV-safe init

**Terra Classic private key** — required only for Step 8 (`set_route` TC → Solana).
The Solana keypair alone is sufficient for all other steps.

---

## 2. Repository Structure

```
terraclassic/
├── deploy-warp-solana-buffer.sh   # Main deploy script (this guide)
├── close-warp-program.sh          # Closes program and recovers SOL
├── jito-warp-init.js              # MEV-safe token init (Node.js)
├── warp-sealevel-config.json      # Solana network + token config
├── warp-evm-config.json           # Terra Classic tokens config
├── doc/
│   └── WARP-SOLANA-GUIDE.md      # This document
└── log/
    ├── deploy-warp-solana-buffer.log
    └── WARP-SOLANAMAINNET-<TOKEN>-BUFFER.txt  # Generated report
```

**Hyperlane monorepo** (read-only, do not modify):
```
/home/lunc/hyperlane-monorepo/rust/sealevel/
├── target/
│   ├── deploy/hyperlane_sealevel_token.so     # Compiled program binary
│   └── release/hyperlane-sealevel-client      # Pre-built CLI binary
└── environments/mainnet3/warp-routes/<token>/
    ├── hyperlane_sealevel_token.so             # Binary copy for this token
    └── keys/
        ├── hyperlane_sealevel_token-solanamainnet-keypair.json  # Program keypair
        └── hyperlane_sealevel_token-solanamainnet-buffer.json   # Buffer keypair
```

> ⚠️ **Important:** Never modify files inside `/home/lunc/hyperlane-monorepo`. It must
> remain as the original cloned repository.

---

## 3. Configuration Files

### 3.1 `warp-sealevel-config.json`

Controls all Solana network configurations and per-token warp route settings.

**Location:** `terraclassic/warp-sealevel-config.json`

```json
{
  "networks": {
    "solanamainnet": {
      "enabled": true,
      "display_name": "Solana Mainnet",
      "environment": "mainnet3",
      "domain": 1399811149,
      "rpc": "https://mainnet.helius-rpc.com/?api-key=YOUR_KEY",
      "rpc_fallbacks": ["..."],
      "mailbox": "E588QtVUvresuXq2KoNEwAmoifCzYGpRBdHByN9KQMbi",
      "explorer": "https://explorer.solana.com",
      "keypair": "/path/to/solana-keypair.json",
      "monorepo_dir": "/home/lunc/hyperlane-monorepo/rust/sealevel",
      "ism": {
        "program_id": "LwNfVYMDzAe5dCJgA5CipTZcT34Eyf74zLr81K91jxk",
        "threshold": 1
      },
      "igp": {
        "program_id": "BhNcatUDC2D5JTyeaqrdSukiVFsEHK7e3hVmKMztwefv",
        "account": "AkeHBbE5JkwVppujCQQ6WuxsVsJtruBAjUo6fDCFp6fF",
        "destination_gas_terra": 3000000
      },
      "warp_tokens": {
        "igorfake": {
          "deployed": false,
          "type": "synthetic",
          "program_id": "",
          "program_hex": "",
          "mint_address": "",
          "metadata_uri": "https://raw.githubusercontent.com/.../metadata-igorfake.json",
          "decimals": 6,
          "owner": "BirXd4QDxfq2vx9LGqgXXSgZrjT81rhoFGUbQRWDEf1j"
        }
      }
    }
  }
}
```

**Key fields explained:**

| Field | Description |
|-------|-------------|
| `enabled` | Set to `true` to include this network in the deploy menu |
| `domain` | Hyperlane domain ID for this chain |
| `rpc` | Primary Solana RPC endpoint |
| `mailbox` | Hyperlane Mailbox program address on Solana |
| `keypair` | Path to the Solana wallet keypair (pays all fees) |
| `monorepo_dir` | Path to the Hyperlane sealevel monorepo |
| `ism.program_id` | MultisigISM program that validates messages from Terra Classic |
| `igp.program_id` | IGP program that pays gas fees on the destination chain |
| `igp.account` | Overhead IGP account address |
| `igp.destination_gas_terra` | Gas units required for Terra Classic deliveries |
| `warp_tokens.<key>.deployed` | Auto-set to `true` after successful deployment |
| `warp_tokens.<key>.program_id` | Auto-set after deploy — Solana program address (base58) |
| `warp_tokens.<key>.program_hex` | Auto-set — program address as 32-byte hex (for TC route) |
| `warp_tokens.<key>.mint_address` | Auto-set after init — Token-2022 mint address |
| `warp_tokens.<key>.metadata_uri` | HTTPS URL to the token metadata JSON file |
| `warp_tokens.<key>.decimals` | Token decimal places (must match Terra Classic token) |
| `warp_tokens.<key>.owner` | Pubkey that will own the warp program (optional) |
| `warp_tokens.<key>.type` | Always `"synthetic"` for cross-chain bridged tokens |

---

### 3.2 `warp-evm-config.json`

Contains Terra Classic chain configuration and per-token Terra Classic warp contract addresses.

**Location:** `terraclassic/warp-evm-config.json`

```json
{
  "terra_classic": {
    "domain": 1325,
    "chain_id": "columbus-5",
    "rpc": "https://rpc.terra-classic.hexxagon.io",
    "tokens": {
      "igorfake": {
        "name": "IGORFAKE",
        "symbol": "IGORFAKE",
        "decimals": 6,
        "description": "Test token for Hyperlane warp route",
        "image": "https://...",
        "terra_warp": {
          "type": "cw20",
          "deployed": true,
          "warp_address": "terra1m5ktcg...",
          "warp_hexed": "0xdd2cbc22...",
          "collateral_address": "terra1abc..."
        }
      }
    }
  }
}
```

**Key fields explained:**

| Field | Description |
|-------|-------------|
| `terra_classic.domain` | Hyperlane domain ID for Terra Classic (1325) |
| `terra_classic.chain_id` | Terra Classic chain ID (`columbus-5`) |
| `terra_classic.rpc` | Terra Classic RPC endpoint |
| `tokens.<key>.terra_warp.deployed` | `true` if the Terra Classic warp contract is deployed |
| `tokens.<key>.terra_warp.warp_address` | Terra Classic warp contract address (bech32) |
| `tokens.<key>.terra_warp.warp_hexed` | Same address in 0x hex format (used by Solana enroll) |

---

## 4. Deployment

### 4.1 Full Deploy

```bash
cd ~/tc-cw-hyperlane/terraclassic

# Required: Terra Classic private key (hex, with or without 0x prefix)
export TERRA_PRIVATE_KEY="your_terra_private_key_hex"

# Run the deploy script
./deploy-warp-solana-buffer.sh
```

The interactive menu will ask you to select:
1. **Token** — which token to deploy (e.g., `igorfake`)
2. **Network** — which Solana network (e.g., `solanamainnet`)

Then it runs all steps automatically.

---

### 4.2 What Each Step Does

| Step | Name | Description |
|------|------|-------------|
| 1 | Get Binary | Downloads the `.so` program binary from an existing program or uses a local compiled one |
| 2 | Deploy Program | Uploads the binary to Solana via `solana program deploy`. Cost: ~1.1 SOL |
| 3 | Token Init (MEV-safe) | Calls `jito-warp-init.js` which sends warp_init + InitializeMint2 in a **single atomic transaction** — no MEV window |
| 4 | Configure ISM | Sets the MultisigISM that validates messages from Terra Classic |
| 5 | Configure IGP | Sets the Interchain Gas Paymaster for paying gas on destination chains |
| 6 | Destination Gas | Sets the gas amount (3,000,000 units) for Terra Classic deliveries |
| 7 | Enroll Router | Registers the Terra Classic warp address on the Solana program |
| 8 | Set Route (TC) | Calls the Terra Classic warp contract to register the Solana program address |
| 9 | Query + Ownership | Queries final state, optionally transfers program ownership |

---

### 4.3 Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `TERRA_PRIVATE_KEY` | For Step 8 only | — | Terra Classic wallet private key (hex) |
| `WARP_PROGRAM_ID` | No | — | Skip deploy and use existing program ID |
| `SOURCE_PROGRAM_ID` | No | TONY program | Program whose binary will be copied |
| `JITO_TIP_LAMPORTS` | No | `5000000` | Priority fee for MEV-safe init (0.005 SOL) |
| `DUMP_RPC` | No | mainnet-beta | RPC used for `solana program dump` |

---

### 4.4 Skip Flags

Set any of these to `1` to skip individual steps:

```bash
export SKIP_INIT=1       # Skip token init (Step 3) — token storage already exists
export SKIP_ISM=1        # Skip ISM configuration (Step 4)
export SKIP_IGP=1        # Skip IGP configuration (Step 5)
export SKIP_GAS=1        # Skip destination gas (Step 6)
export SKIP_ENROLL=1     # Skip enroll-remote-router (Step 7)
export SKIP_TC_ROUTE=1   # Skip Terra Classic set_route (Step 8)
```

**Example:** Resume after a deploy that completed Steps 1-5:
```bash
export TERRA_PRIVATE_KEY="your_key"
export WARP_PROGRAM_ID="YourProgramId..."
export SKIP_ISM=1
export SKIP_IGP=1
./deploy-warp-solana-buffer.sh
```

---

## 5. MEV Protection

The Hyperlane sealevel init instruction creates the mint PDA account as an uninitialized
Token-2022 account. If `InitializeMint2` is sent in a separate transaction, MEV bots can
insert `InitializeAccount3 + CloseAccount` between the two transactions to steal the SOL.

**Solution in `jito-warp-init.js`:** All 5 instructions are packed into a **single Solana transaction**:

```
Instruction 1: ComputeBudget (unit limit)
Instruction 2: ComputeBudget (priority fee)
Instruction 3: warp_init       → creates token_storage + mint_PDA (234 bytes, assigned to Token-2022)
Instruction 4: InitializeMetadataPointer → marks mint for inline metadata
Instruction 5: InitializeMint2 → initializes the mint with authority + decimals
```

A single Solana transaction is **atomically executed** — either all instructions succeed
or none do. There is no window between instructions for an MEV bot to act.

**Transaction size:** ~703 bytes (well under the 1232-byte Solana limit).

---

## 6. Verifying the Deployment

After a successful deploy, verify the full configuration:

```bash
CLIENT="/home/lunc/hyperlane-monorepo/rust/sealevel/target/release/hyperlane-sealevel-client"
KEY="/path/to/solana-keypair.json"
RPC="https://mainnet.helius-rpc.com/?api-key=YOUR_KEY"
PID="YourProgramId..."

$CLIENT -k "$KEY" -u "$RPC" token query --program-id "$PID" synthetic
```

Expected output includes:
```
mailbox: E588QtVUvresuXq2KoNEwAmoifCzYGpRBdHByN9KQMbi
interchain_security_module: Some(LwNfVYMDzAe5...)
interchain_gas_paymaster: Some((BhNcatU..., Igp(AkeHBb...)))
destination_gas: { 1325: 3000000 }
remote_routers: { 1325: 0xdd2cbc22... }
mint: <MINT_ADDRESS>
```

Verify the Terra Classic → Solana route:
```bash
terrad query wasm contract-state smart <TC_WARP_ADDR> \
  '{"router":{"get_route":{"domain":1399811149}}}' \
  --node https://rpc.terra-classic.hexxagon.io
```

---

## 7. Cancelling the Program (Recover SOL)

Closing a deployed Solana program reclaims the SOL locked in the program account
(typically ~2.22 SOL for the binary storage).

### 7.1 Using `close-warp-program.sh`

```bash
./close-warp-program.sh
```

The interactive menu lists all deployed tokens. Select the one to close.

The script will:
1. Close the on-chain program (reclaim ~2.22 SOL)
2. Close any orphaned buffer accounts
3. Delete local keypair files (program + buffer)
4. Reset `warp-sealevel-config.json`: `deployed=false`, `program_id=""`, `mint_address=""`
5. Remove the state file (`.warp-solana-buffer-state.json`)

**After closing, you are ready to deploy fresh** with `./deploy-warp-solana-buffer.sh`.

---

### 7.2 Manual Recovery

If `close-warp-program.sh` is not available, use the Solana CLI directly:

**Close the program:**
```bash
solana program close <PROGRAM_ID> \
  --bypass-warning \
  --keypair /path/to/solana-keypair.json \
  --url https://mainnet.helius-rpc.com/?api-key=YOUR_KEY
```

**Close all orphaned buffer accounts:**
```bash
solana program close --buffers \
  --keypair /path/to/solana-keypair.json \
  --url https://mainnet.helius-rpc.com/?api-key=YOUR_KEY
```

**Close a specific buffer (if the buffer pubkey is known):**
```bash
solana program close <BUFFER_PUBKEY> \
  --keypair /path/to/solana-keypair.json \
  --url https://mainnet.helius-rpc.com/?api-key=YOUR_KEY \
  --buffer
```

**List all programs and buffers owned by your keypair:**
```bash
solana program show --programs \
  --keypair /path/to/solana-keypair.json \
  --url https://mainnet.helius-rpc.com/?api-key=YOUR_KEY

solana program show --buffers \
  --keypair /path/to/solana-keypair.json \
  --url https://mainnet.helius-rpc.com/?api-key=YOUR_KEY
```

**After manual close, reset the config:**
```bash
cd ~/tc-cw-hyperlane/terraclassic

# Remove state file
rm -f .warp-solana-buffer-state.json

# Remove keypair files
rm -f /home/lunc/hyperlane-monorepo/rust/sealevel/environments/mainnet3/warp-routes/<TOKEN>/keys/*.json

# Reset warp-sealevel-config.json
python3 -c "
import json
with open('warp-sealevel-config.json') as f: cfg = json.load(f)
t = cfg['networks']['solanamainnet']['warp_tokens']['<TOKEN_KEY>']
t['deployed'] = False
t['program_id'] = ''
t['program_hex'] = ''
t['mint_address'] = ''
with open('warp-sealevel-config.json', 'w') as f: json.dump(cfg, f, indent=2)
print('Config reset.')
"
```

---

## 8. Resuming a Failed Deploy

If the deploy fails partway through (e.g., network timeout during binary upload):

**Option A: Just re-run the script.** The state file (`.warp-solana-buffer-state.json`)
remembers the program ID and mint address. The script resumes from where it left off.

**Option B: Skip to specific steps using environment variables:**
```bash
export WARP_PROGRAM_ID="YourProgramId..."   # already deployed
export SKIP_INIT=1                           # init already done
export TERRA_PRIVATE_KEY="your_key"
./deploy-warp-solana-buffer.sh
```

**Option C: Reset and start fresh** (only if you also close the program first):
```bash
./close-warp-program.sh   # reclaim SOL
rm -f .warp-solana-buffer-state.json
./deploy-warp-solana-buffer.sh
```

---

## 9. Troubleshooting

### Buffer error: "not an upgradeable loader buffer account"

The buffer keypair file exists but the on-chain buffer account was already closed.

**Fix:** Delete the stale buffer file and re-run:
```bash
rm -f /home/lunc/hyperlane-monorepo/rust/sealevel/environments/mainnet3/warp-routes/<TOKEN>/keys/hyperlane_sealevel_token-solanamainnet-buffer.json
./deploy-warp-solana-buffer.sh
```

---

### State file loads old (closed) program ID

The `.warp-solana-buffer-state.json` persists the last program ID. If that program
was closed, the init fails silently (Jito bundle is dropped).

**Fix:** Delete the state file before running:
```bash
rm -f .warp-solana-buffer-state.json
./deploy-warp-solana-buffer.sh
```

---

### "Insufficient balance" during deploy

The binary upload costs ~1.1 SOL. Check your balance:
```bash
solana balance /path/to/keypair.json \
  --url https://mainnet.helius-rpc.com/?api-key=YOUR_KEY
```

You need at least **2.5 SOL** for a full deployment (binary + rent + fees + tip).

---

### ISM/IGP/Gas/Enroll steps show errors

These steps can be re-run independently without re-deploying:

```bash
CLIENT="/home/lunc/hyperlane-monorepo/rust/sealevel/target/release/hyperlane-sealevel-client"
KEY="/path/to/keypair.json"
RPC="https://mainnet.helius-rpc.com/?api-key=YOUR_KEY"
PID="YourProgramId..."

# ISM
$CLIENT -k $KEY -u $RPC token set-interchain-security-module \
  --program-id $PID --ism LwNfVYMDzAe5dCJgA5CipTZcT34Eyf74zLr81K91jxk

# IGP
$CLIENT -k $KEY -u $RPC token igp \
  --program-id $PID set BhNcatUDC2D5JTyeaqrdSukiVFsEHK7e3hVmKMztwefv igp AkeHBbE5JkwVppujCQQ6WuxsVsJtruBAjUo6fDCFp6fF

# Destination gas (Terra Classic domain = 1325)
$CLIENT -k $KEY -u $RPC token set-destination-gas \
  --program-id $PID 1325 3000000

# Enroll remote router
$CLIENT -k $KEY -u $RPC token enroll-remote-router \
  --program-id $PID 1325 0xdd2cbc22fdfb1ebfc9e2119565eb87eb67c87dcdad4bbfd29ceee9e83f38f921
```

---

### Terra Classic set_route pending

If you didn't have `TERRA_PRIVATE_KEY` set during deploy, run the set_route manually:
```bash
export TERRA_PRIVATE_KEY="your_hex_key"
export WARP_PROGRAM_ID="YourProgramId..."
export SKIP_ISM=1 SKIP_IGP=1 SKIP_GAS=1 SKIP_ENROLL=1
./deploy-warp-solana-buffer.sh
```

Or use `terrad` directly:
```bash
terrad tx wasm execute "terra1m5ktcg..." \
  '{"router":{"set_route":{"set":{"domain":1399811149,"route":"ee348fd7..."}}}}' \
  --from <KEY_NAME> \
  --chain-id columbus-5 \
  --node https://rpc.terra-classic.hexxagon.io \
  --gas auto --gas-adjustment 1.5 \
  --fees 12000000uluna --yes
```
