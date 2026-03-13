# Guide — `transfer-remote-to-terra.sh`

Send tokens **EVM → Terra Classic** and **Sealevel (Solana) → Terra Classic** via Hyperlane Warp Routes.

---

## Table of Contents

1. [Overview](#1-overview)
2. [Prerequisites](#2-prerequisites)
3. [File structure](#3-file-structure)
4. [Interactive mode](#4-interactive-mode)
5. [Non-interactive mode](#5-non-interactive-mode)
6. [Environment variables](#6-environment-variables)
7. [EVM → Terra Classic flow](#7-evm--terra-classic-flow)
8. [Sealevel → Terra Classic flow](#8-sealevel--terra-classic-flow)
   - [Import keypair from Phantom](#import-keypair-from-a-phantom-wallet)
9. [How to verify delivery](#9-how-to-verify-delivery)
10. [Query balances](#10-query-balances)
11. [Logs and reports](#11-logs-and-reports)
12. [Contract references](#12-contract-references)
13. [Troubleshooting](#13-troubleshooting)

---

## 1. Overview

The `transfer-remote-to-terra.sh` script executes a cross-chain transfer from **any source network** (EVM or Solana) to **Terra Classic** using Hyperlane Warp infrastructure.

```
EVM (Sepolia / BSC Testnet)          Terra Classic
   Warp HypERC20 Synthetic   ──────►   Warp CW20 Collateral
   transferRemote()                      (tokens released)
```

```
Solana Testnet                        Terra Classic
   Warp SealevelHypSynthetic ──────►   Warp CW20 Collateral
   token transfer-remote                 (tokens released)
```

**What the script does automatically:**
- Reads deployed contracts from `warp-evm-config.json` and `warp-sealevel-config.json` files
- Converts the Terra Classic address (bech32) to the `bytes32` format required by Hyperlane
- Queries the IGP fee via `quoteGasPayment()` (EVM) or via configuration (Sealevel)
- Displays summary and asks for confirmation before sending
- Writes report to `log/TRANSFER-TO-TERRA-<NETWORK>-<TOKEN>-<timestamp>.txt`

---

## 2. Prerequisites

### Common dependencies

| Tool | How to install |
|------------|--------------|
| `jq`       | `sudo apt install jq` |
| `curl`     | `sudo apt install curl` |
| `python3`  | `sudo apt install python3` |
| `python3-bech32` | `pip3 install bech32` |

### For EVM (Sepolia / BSC Testnet)

| Tool | How to install |
|------------|--------------|
| `cast` (Foundry) | `curl -L https://foundry.paradigm.xyz \| bash && foundryup` |
| EVM private key with balance | See section [7](#7-evm--terra-classic-flow) |

### For Sealevel (Solana)

| Tool | How to install |
|------------|--------------|
| `hyperlane-sealevel-client` | `cd /home/lunc/hyperlane-monorepo/rust/sealevel && cargo build` |
| Solana keypair (`.json`) | `solana-keygen new -o ~/my-wallet.json` |
| SOL balance for IGP fee | Available via faucet: https://faucet.solana.com |

---

## 3. File structure

```
terraclassic/
├── transfer-remote-to-terra.sh        ← this script
├── warp-evm-config.json               ← deployed EVM contracts
├── warp-sealevel-config.json          ← deployed Sealevel programs
└── log/
    ├── transfer-remote-to-terra.log   ← summary history of all transfers
    └── TRANSFER-TO-TERRA-<NETWORK>-<TOKEN>-<timestamp>.txt  ← individual report
```

---

## 4. Interactive mode

Run without environment variables. The script presents a numbered menu with all available tokens and networks:

```bash
cd ~/cw-hyperlane/terraclassic
./transfer-remote-to-terra.sh
```

**Example displayed menu:**

```
🌉  TRANSFER REMOTE — Other Network → Terra Classic

Select the token and source network:

  [1]   LUNC ← Ethereum Sepolia Testnet  (domain 11155111)
  [2]   XPTO ← Ethereum Sepolia Testnet  (domain 11155111)
  [3]   XPTV ← Ethereum Sepolia Testnet  (domain 11155111)
  [4]   LUNC ← BSC Testnet               (domain 97)
  [5]   XPV  ← BSC Testnet               (domain 97)
  [6]   LUNC ← Solana Testnet            (domain 1399811150)
  [7]   JURIS ← Solana Testnet           (domain 1399811150)
  [8]   XPTO ← Solana Testnet            (domain 1399811150)

  Option [1-8]:
```

The script asks sequentially:
1. **Option** — token/network number
2. **Recipient** — Terra Classic address (`terra1...`)
3. **Amount** — in minimum units (e.g.: `1000000` = 1 XPTO with 6 decimals)
4. **Gas fee** — queried automatically; if it fails, asks manually
5. **Private key** — EVM (`ETH_PRIVATE_KEY`) or Solana keypair path
6. **Confirmation** — `[y/N]` before sending

---

## 5. Non-interactive mode

Pass all information via environment variables for automation or CI scripts.

### EVM → Terra Classic

```bash
cd ~/cw-hyperlane/terraclassic

export ETH_PRIVATE_KEY="0xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxab"

TOKEN_KEY=xpto \
SOURCE_NETWORK=sepolia \
RECIPIENT="terra18lr7ujd9nsgyr49930ppaajhadzrezam70j39k" \
AMOUNT=1000000 \
AUTO_CONFIRM=s \
./transfer-remote-to-terra.sh
```

### Sealevel → Terra Classic

```bash
cd ~/cw-hyperlane/terraclassic

TOKEN_KEY=xpto \
SOURCE_NETWORK=solanatestnet \
RECIPIENT="terra18lr7ujd9nsgyr49930ppaajhadzrezam70j39k" \
AMOUNT=1000000 \
SOL_KEYPAIR="/home/lunc/keys/solana-keypair-BirXd4QDxfq2vx9LGqgXXSgZrjT81rhoFGUbQRWDEf1j.json" \
AUTO_CONFIRM=s \
./transfer-remote-to-terra.sh
```

> **⚠️ Security:** Never put real private keys in shell history. Use `export` before running or pass the variable in the command itself and clear it right after: `unset ETH_PRIVATE_KEY`.

---

## 6. Environment variables

| Variable | Required | Description |
|----------|-------------|-----------|
| `TOKEN_KEY` | No (interactive) | Token key in config, e.g.: `xpto`, `wlunc`, `xpv` |
| `SOURCE_NETWORK` | No (interactive) | Source network, e.g.: `sepolia`, `bsctestnet`, `solanatestnet` |
| `RECIPIENT` | No (interactive) | Destination Terra Classic address (`terra1...`) |
| `AMOUNT` | No (interactive) | Value in minimum units (no decimals), e.g.: `1000000` |
| `ETH_PRIVATE_KEY` | EVM: yes | EVM wallet private key, with `0x` prefix |
| `SOL_KEYPAIR` | Sealevel: optional | Path to the Solana keypair `.json` file |
| `AUTO_CONFIRM` | No | `s` to confirm without interaction |

---

## 7. EVM → Terra Classic flow

### What happens internally

```
1. cast call <WARP_EVM> "quoteGasPayment(uint32)" 1325
   → Returns the fee in wei required to pay the IGP

2. cast send <WARP_EVM> "transferRemote(uint32,bytes32,uint256)"
   <TC_DOMAIN=1325>  <RECIPIENT_B32>  <AMOUNT>
   --value <FEE_WEI>
   --private-key <ETH_PRIVATE_KEY>
   --rpc-url <RPC>
```

### EVM contract addresses (testnet)

| Network | Token | Warp Contract | Domain |
|------|-------|--------------|--------|
| Sepolia | LUNC | `0x224a4419D7FA69D3bEbAbce574c7c84B48D829b4` | 11155111 |
| Sepolia | XPTO | `0xbF43aA4878f5Ad0fcAC12Cd3A835DD3506981048` | 11155111 |
| Sepolia | XPTV | `0x7d92c2E01933F1C651845152DBd4222d475Bd9f0` | 11155111 |
| BSC Testnet | LUNC | `0x2144Be4477202ba2d50c9A8be3181241878cf7D8` | 97 |
| BSC Testnet | XPV  | `0x11D6aa52d60611a513ab783842Dc397C86E7fff0` | 97 |

### Convert Terra Classic address to bytes32 manually

If you need to calculate the `bytes32` of an address manually:

```python
import bech32

addr = "terra18lr7ujd9nsgyr49930ppaajhadzrezam70j39k"
hrp, data = bech32.bech32_decode(addr)
raw = bytes(bech32.convertbits(data, 5, 8, False))
print(raw.hex().zfill(64))
# → 0000000000000000000000003fc7ee49a59c1041d4a58bc21ef657eb443c8bbb
```

### Query gas fee manually

```bash
# Sepolia → Terra Classic (domain 1325)
cast call 0xbF43aA4878f5Ad0fcAC12Cd3A835DD3506981048 \
    "quoteGasPayment(uint32)(uint256)" 1325 \
    --rpc-url https://ethereum-sepolia-rpc.publicnode.com

# BSC Testnet → Terra Classic
cast call 0x11D6aa52d60611a513ab783842Dc397C86E7fff0 \
    "quoteGasPayment(uint32)(uint256)" 1325 \
    --rpc-url https://bsc-testnet-rpc.publicnode.com
```

### Check EVM token balance (HypERC20 Synthetic)

```bash
# XPTO balance on Sepolia
cast call 0xbF43aA4878f5Ad0fcAC12Cd3A835DD3506981048 \
    "balanceOf(address)(uint256)" \
    "0xYOUR_EVM_WALLET" \
    --rpc-url https://ethereum-sepolia-rpc.publicnode.com
```

---

## 8. Sealevel → Terra Classic flow

### What happens internally

```
hyperlane-sealevel-client \
  --url <SOL_RPC> \
  --keypair <KEYPAIR_PATH> \
  token transfer-remote \
  <SENDER_PUBKEY> <AMOUNT> <TC_DOMAIN=1325> <RECIPIENT_B32> synthetic \
  --program-id <PROGRAM_ID>
```

The `RECIPIENT_B32` is the `terra1...` address converted to 64-character hex (without `0x`).

### Sealevel program addresses (testnet)

| Network | Token | Program ID | Mint Address |
|------|-------|-----------|-------------|
| Solana Testnet | JURIS | `G3eEYHv2GrBJ6KTS3XQhRd7QYdwnfWjisQrSVWedQK4y` | `ExzEij8z7xc71kvjuMHmejRkmM4ACgKjDWuEaXdDubRa` |
| Solana Testnet | XPTO  | `jNkiNLXQetj9L2tDX6xTgx9QP1tgtNgYXamouNbbwx9` | `Db8VbMerYxksYwSSdetpy6Jhp2BrE4hk9Sh9dYJT5dQ2` |

### Check SPL balance before sending

```bash
# XPTO (SPL) token balance on Solana Testnet
# Correct syntax: <MINT_ADDRESS> --owner <OWNER> --url <RPC>
spl-token balance Db8VbMerYxksYwSSdetpy6Jhp2BrE4hk9Sh9dYJT5dQ2 \
    --owner BirXd4QDxfq2vx9LGqgXXSgZrjT81rhoFGUbQRWDEf1j \
    --url https://api.testnet.solana.com

# Native SOL balance (needed to pay IGP fee)
solana balance BirXd4QDxfq2vx9LGqgXXSgZrjT81rhoFGUbQRWDEf1j \
    --url https://api.testnet.solana.com
```

> **ℹ️ Note about token accounts:** If the command returns `Could not find token account`, it means the wallet has not yet received this token and therefore cannot send it. You must first receive the token via a TC → Solana transfer.

### Solana keypair configured in the script

The `keypair` field in `warp-sealevel-config.json` defines the default keypair path:

```json
"solanatestnet": {
  "keypair": "/home/lunc/keys/solana-keypair-BirXd4QDxfq2vx9LGqgXXSgZrjT81rhoFGUbQRWDEf1j.json",
  ...
}
```

To use a different keypair, pass `SOL_KEYPAIR=/path/to/keypair.json` as an environment variable.

---

### Import keypair from a Phantom wallet

If you have SPL tokens in a wallet created by **Phantom** (or another browser wallet), you can export the private key and convert it to the JSON format that the Solana CLI and `hyperlane-sealevel-client` expect.

#### Step 1 — Export the key from Phantom

1. Open **Phantom** and select the desired account
2. Click the **3 dots** (`···`) next to the account name → **Account Details**
3. Click **Show Private Key**
4. Confirm the wallet password
5. Copy the displayed string — it is a key in **base58** format (e.g.: `5K...abc`)

#### Step 2 — Convert to keypair JSON

Create the conversion script:

```bash
cat << 'EOF' > /tmp/convert-phantom-key.py
import sys, json, base58

if len(sys.argv) < 2:
    print("Usage: python3 convert-phantom-key.py <BASE58_PRIVATE_KEY>")
    sys.exit(1)

private_key_b58 = sys.argv[1].strip()
try:
    key_bytes = base58.b58decode(private_key_b58)
    if len(key_bytes) == 64:
        keypair_array = list(key_bytes)
    elif len(key_bytes) == 32:
        try:
            from nacl.signing import SigningKey
            sk = SigningKey(key_bytes)
            vk = sk.verify_key
            keypair_array = list(key_bytes) + list(bytes(vk))
        except ImportError:
            keypair_array = list(key_bytes) + [0]*32
            print("WARNING: nacl not available, install with: pip3 install pynacl")
    else:
        print(f"Unexpected size: {len(key_bytes)} bytes"); sys.exit(1)
    print(json.dumps(keypair_array))
except Exception as e:
    print(f"Error: {e}"); sys.exit(1)
EOF
```

Run the conversion (replace `PASTE_YOUR_KEY` with the key exported from Phantom):

```bash
# Install dependencies if needed
pip3 install base58 pynacl

# Convert and save (replace BirXd4... with your wallet pubkey)
python3 /tmp/convert-phantom-key.py "PASTE_YOUR_KEY" \
    > /home/lunc/keys/solana-keypair-BirXd4QDxfq2vx9LGqgXXSgZrjT81rhoFGUbQRWDEf1j.json

# Verify — should display the correct pubkey of your wallet
solana-keygen pubkey /home/lunc/keys/solana-keypair-BirXd4QDxfq2vx9LGqgXXSgZrjT81rhoFGUbQRWDEf1j.json
```

#### Step 3 — Update the config

Edit `warp-sealevel-config.json` and point the `keypair` field to the new file:

```json
"solanatestnet": {
  "keypair": "/home/lunc/keys/solana-keypair-BirXd4QDxfq2vx9LGqgXXSgZrjT81rhoFGUbQRWDEf1j.json",
  ...
}
```

> **⚠️ Security:** The keypair `.json` file contains the full private key. Keep it with restricted permissions (`chmod 600`) and never share or commit it to repositories.

```bash
chmod 600 /home/lunc/keys/solana-keypair-BirXd4QDxfq2vx9LGqgXXSgZrjT81rhoFGUbQRWDEf1j.json
```

#### Why use a Phantom wallet instead of a CLI-generated one?

A wallet created with `solana-keygen new` starts empty — it has no token accounts created for any SPL token. To send XPTO from Solana → TC, the wallet **must have XPTO** previously received (via a TC → Solana transfer). A Phantom wallet that has already received tokens has the token accounts created and the balance available to burn in the cross-chain transfer.

---

## 9. How to verify delivery

After sending, the message travels through:

```
Origin → Validator (signs) → Relayer (delivers) → Terra Classic Mailbox → Warp CW20 (releases tokens)
```

Estimated time: **1 to 5 minutes** depending on congestion.

### Step 1 — Verify the transaction on the source network

**EVM (Sepolia):**
```
https://sepolia.etherscan.io/tx/<TX_HASH>
```

**Solana Testnet:**
```
https://explorer.solana.com/tx/<TX_SIGNATURE>?cluster=testnet
```

### Step 2 — Track the message in the Hyperlane Explorer

```
https://explorer.hyperlane.xyz/message/<MESSAGE_ID>
```

The `MESSAGE_ID` is emitted as an event in the source transaction. In EVM transactions, it appears in the Mailbox event log.

### Step 3 — Verify delivery in the Terra Classic Mailbox

```bash
# Check if the message_id was delivered
terrad query wasm contract-state smart \
    terra1rqg3qfkfg5upad9xu6zj5jhl626qy053s7rn08829rgqzv2wu39s5la8yf \
    '{"mailbox":{"message_delivered":{"id":"<MESSAGE_ID_WITHOUT_0x>"}}}' \
    --node https://rpc.terra-classic.hexxagon.dev
```

> **Note:** The `MESSAGE_ID` must be provided without the `0x` prefix.

### Step 4 — Check CW20 balance at destination

```bash
# XPTO balance at the recipient address
terrad query wasm contract-state smart \
    terra1zle6pwm9aztwu228e0spxrydlvmhj2qrq8ap3x2wrjc52kdvu4fs20rkch \
    '{"balance":{"address":"terra18lr7ujd9nsgyr49930ppaajhadzrezam70j39k"}}' \
    --node https://rpc.terra-classic.hexxagon.dev
```

---

## 10. Query balances

### CW20 balance on Terra Classic

```bash
terrad query wasm contract-state smart \
    <CONTRATO_CW20> \
    '{"balance":{"address":"<TERRA_WALLET>"}}' \
    --node https://rpc.terra-classic.hexxagon.dev
```

**Real example — XPTO:**
```bash
terrad query wasm contract-state smart \
    terra1zle6pwm9aztwu228e0spxrydlvmhj2qrq8ap3x2wrjc52kdvu4fs20rkch \
    '{"balance":{"address":"terra18lr7ujd9nsgyr49930ppaajhadzrezam70j39k"}}' \
    --node https://rpc.terra-classic.hexxagon.dev
```

The response has the format:
```json
{"data":{"balance":"1000000"}}
```

### Native LUNC balance

```bash
terrad query bank balances terra18lr7ujd9nsgyr49930ppaajhadzrezam70j39k \
    --node https://rpc.terra-classic.hexxagon.dev
```

### Query multiple tokens in a loop

```bash
#!/usr/bin/env bash
WALLET="terra18lr7ujd9nsgyr49930ppaajhadzrezam70j39k"
NODE="https://rpc.terra-classic.hexxagon.dev"

declare -A TOKENS=(
    ["XPTO"]="terra1zle6pwm9aztwu228e0spxrydlvmhj2qrq8ap3x2wrjc52kdvu4fs20rkch"
    ["XPTV"]="terra1dnflusc7slapvals97em3fj4vrfyx90npr3znq6y45qjy7hhd6jqchqsgx"
    ["XPV"]="terra1d6e9mxaupf2zx2jj5kcayr5epz3q6g2fzm2u83w9fjqvzgz7v34qqdspxx"
    ["JURIS"]="terra1e8zhvt5g5vzy9d8x3dkxr0uxnfhk3lgaqx6l22szecpf4kxt3c4qktzknm"
)

for sym in "${!TOKENS[@]}"; do
    RESULT=$(terrad query wasm contract-state smart "${TOKENS[$sym]}" \
        "{\"balance\":{\"address\":\"${WALLET}\"}}" \
        --node "$NODE" --output json 2>/dev/null | jq -r '.data.balance // "0"')
    echo "$sym: $RESULT"
done
```

### SPL balance on Solana Testnet

```bash
# XPTO (SPL) balance
spl-token balance \
    --address Db8VbMerYxksYwSSdetpy6Jhp2BrE4hk9Sh9dYJT5dQ2 \
    --owner <YOUR_SOLANA_WALLET> \
    --url https://api.testnet.solana.com

# Native SOL balance
solana balance <YOUR_SOLANA_WALLET> \
    --url https://api.testnet.solana.com
```

---

## 11. Logs and reports

After each successful execution, the script writes:

| File | Content |
|---------|----------|
| `log/transfer-remote-to-terra.log` | One line per transfer: date, network, token, amount, tx hash |
| `log/TRANSFER-TO-TERRA-<NETWORK>-<TOKEN>-<timestamp>.txt` | Full report with all parameters |

**Report example:**
```
TRANSFER REMOTE — SEPOLIA → Terra Classic
Date           : Thu Mar 12 15:30:00 UTC 2026
Token          : XPTO / XPTO
Source         : SEPOLIA  (evm, domain 11155111)
Destination    : Terra Classic  (domain 1325)
Recipient TC   : terra18lr7ujd9nsgyr49930ppaajhadzrezam70j39k
Recipient b32  : 0000000000000000000000003fc7ee49a59c1041d4a58bc21ef657eb443c8bbb
Amount         : 1000000
Warp source    : 0xbF43aA4878f5Ad0fcAC12Cd3A835DD3506981048
Gas fee (wei)  : 109030327234501
TX Hash        : 0xabc123...
```

**View history:**
```bash
cat ~/cw-hyperlane/terraclassic/log/transfer-remote-to-terra.log
```

**List all reports:**
```bash
ls ~/cw-hyperlane/terraclassic/log/TRANSFER-TO-TERRA-*.txt
```

---

## 12. Contract references

### Terra Classic (rebel-2)

| Contract | Address |
|----------|---------|
| Mailbox | `terra1rqg3qfkfg5upad9xu6zj5jhl626qy053s7rn08829rgqzv2wu39s5la8yf` |
| ISM Routing | `terra1h4sd8fyxhde7dc9w9y9zhc2epphgs75q7zzfg3tfynm8qvpe3jlsd7sauh` |
| IGP | `terra1e7fkst7mzsucl0jka2yf5vw9h07s9uvf2yy53z4r4mshqnkktl8q78h0zd` |
| Warp LUNC (native) | `terra1zlm0h2xu6rhnjchn29hxnpvr74uxxqetar9y75zcehyx2mqezg9slj09ml` |
| Warp XPTO (CW20) | `terra16ql6l4fuudg0fxarcm4ukxlw0jalg5ljv8kg6h8f7dk9t2e7y6ssq2hqrm` |
| Warp XPTV (CW20) | `terra1vd8lgn2l38dzl2xhd4fph5cdtflm3e0exls9aeyl30d9e52sfpaq9zzp4c` |
| CW20 XPTO | `terra1zle6pwm9aztwu228e0spxrydlvmhj2qrq8ap3x2wrjc52kdvu4fs20rkch` |
| CW20 XPTV | `terra1dnflusc7slapvals97em3fj4vrfyx90npr3znq6y45qjy7hhd6jqchqsgx` |

### Useful links

| Resource | URL |
|---------|-----|
| Terra Classic Explorer | https://finder.hexxagon.io/rebel-2 |
| Sepolia Etherscan | https://sepolia.etherscan.io |
| BSC Testnet Explorer | https://testnet.bscscan.com |
| Solana Testnet Explorer | https://explorer.solana.com/?cluster=testnet |
| Hyperlane Explorer | https://explorer.hyperlane.xyz |
| TC S3 Validator | https://hyperlane-validator-signatures-igorveras-terraclassic.s3.us-east-1.amazonaws.com/ |
| Sepolia S3 Validator | https://hyperlane-validator-signatures-igorveras-sepolia.s3.us-east-1.amazonaws.com/ |
| BSC S3 Validator | https://hyperlane-validator-signatures-igorveras-bsctestnet.s3.us-east-1.amazonaws.com/ |

---

## 13. Troubleshooting

### ❌ `quoteGasPayment failed`

The script automatically tries all RPCs configured in `rpc_urls`. If all fail, it asks for the value manually.

**Historical values (reference):**

| Source network | Approximate gas fee |
|-------------|-------------------|
| Sepolia → TC | `109030327234501` wei (~0.00011 ETH) |
| BSC Testnet → TC | `1` wei (symbolic value) |

To query manually:
```bash
cast call <WARP_CONTRACT> "quoteGasPayment(uint32)(uint256)" 1325 \
    --rpc-url <RPC_URL>
```

---

### ❌ `ERR: address must start with terra1`

The provided recipient is not a valid Terra Classic address. Verify that it starts with `terra1` and has the correct length (44 characters).

---

### ❌ `insufficient funds` (EVM)

The wallet does not have sufficient ETH/BNB balance to pay the gas fee + transaction fee.

```bash
# Check ETH wallet balance
cast balance <SUA_CARTEIRA_EVM> --rpc-url https://ethereum-sepolia-rpc.publicnode.com

# Testnet faucets
# Sepolia: https://sepoliafaucet.com
# BSC Testnet: https://testnet.bnbchain.org/faucet-smart
```

---

### ❌ `NO SPL BALANCE — TRANSFER CANCELLED` (Sealevel)

The script detected that the wallet has no SPL tokens of the desired token. This happens when:

1. **The wallet has never received this token** — the token account does not exist yet
2. **The balance is zero** — all tokens were burned in previous transfers

**Diagnosis:**
```bash
# Correct syntax for spl-token balance (mint + owner + url)
spl-token balance Db8VbMerYxksYwSSdetpy6Jhp2BrE4hk9Sh9dYJT5dQ2 \
    --owner BirXd4QDxfq2vx9LGqgXXSgZrjT81rhoFGUbQRWDEf1j \
    --url https://api.testnet.solana.com
```

**Fix:** First send tokens from Terra Classic to Solana:
```bash
# Step 1: TC → Solana (mint tokens in the Solana wallet)
TOKEN_KEY=xpto DEST_NETWORK=solanatestnet \
  RECIPIENT="BirXd4QDxfq2vx9LGqgXXSgZrjT81rhoFGUbQRWDEf1j" \
  AMOUNT=2000000 AUTO_CONFIRM=s \
  ./transfer-remote-terra.sh

# Step 2: after arriving (~2-5 min), send Solana → TC
TOKEN_KEY=xpto SOURCE_NETWORK=solanatestnet \
  RECIPIENT="terra18lr7ujd9nsgyr49930ppaajhadzrezam70j39k" \
  AMOUNT=1000000 AUTO_CONFIRM=s \
  ./transfer-remote-to-terra.sh
```

---

### ❌ `InvalidAccountData` / `BurnChecked` failure (Sealevel)

More detailed error indicating the same problem: non-existent token account or zero balance.

```
Transaction simulation failed: Error processing Instruction 1: invalid account data for instruction
Program log: Instruction: BurnChecked
Program log: Error: InvalidAccountData
```

**Cause:** The wallet does not have a token account created for the mint in question.  
**Fix:** Same as the case above — first receive tokens via TC → Solana.

---

### ❌ Using a wallet created via `solana-keygen` vs Phantom

Wallets created with `solana-keygen new` start completely empty — with no SPL token accounts. To send tokens Solana → TC, the wallet **must have tokens** previously received.

If you have a Phantom wallet with balance, import it as described in [section 8 — Import keypair from Phantom](#import-keypair-from-a-phantom-wallet).

---

### ❌ Message sent but tokens did not arrive at Terra Classic

1. **Confirm the transaction at origin** — check in the Explorer if the tx was confirmed
2. **Check if the validator made a checkpoint** — access the validator S3 and check for new files
3. **Wait for the relayer** — can take up to 5 minutes
4. **Verify delivery in the Mailbox:**
   ```bash
   terrad query wasm contract-state smart \
       terra1rqg3qfkfg5upad9xu6zj5jhl626qy053s7rn08829rgqzv2wu39s5la8yf \
       '{"mailbox":{"message_delivered":{"id":"<MESSAGE_ID_WITHOUT_0x>"}}}' \
       --node https://rpc.terra-classic.hexxagon.dev
   ```
5. **Check CW20 balance** — section [10](#10-query-balances)

---

### ❌ `hyperlane-sealevel-client not found`

The Rust binary needs to be compiled:

```bash
cd /home/lunc/hyperlane-monorepo/rust/sealevel
cargo build
# Binary generated at: target/debug/hyperlane-sealevel-client
```

---

### ❌ TOKEN_KEY + SOURCE_NETWORK combination not found

The values of `TOKEN_KEY` and `SOURCE_NETWORK` must exactly match the keys in the configuration files.

**Valid values for EVM (`warp-evm-config.json`):**

| `SOURCE_NETWORK` | Available `TOKEN_KEY` values |
|------------------|------------------------|
| `sepolia` | `wlunc`, `xpto`, `xptv` |
| `bsctestnet` | `wlunc`, `xpv` |

**Valid values for Sealevel (`warp-sealevel-config.json`):**

| `SOURCE_NETWORK` | Available `TOKEN_KEY` values |
|------------------|------------------------|
| `solanatestnet` | `wlunc`, `juris`, `xpto` |
