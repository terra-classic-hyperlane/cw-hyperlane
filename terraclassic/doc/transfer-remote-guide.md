# Transfer Remote — Terra Classic → EVM / Sealevel

Complete guide for the `transfer-remote-terra.sh` script, which sends tokens via Hyperlane Warp Route
from **Terra Classic** to EVM networks (Sepolia, BSC Testnet) and Sealevel (Solana Testnet).

---

## Table of Contents

1. [Prerequisites](#1--prerequisites)
2. [File structure](#2--file-structure)
3. [Configure private key](#3--configure-private-key)
4. [Interactive mode](#4--interactive-mode)
5. [Non-interactive mode](#5--non-interactive-mode)
6. [Available options (token × network)](#6--available-options-token--network)
7. [Recipient address formats](#7--recipient-address-formats)
8. [IGP Fee (destination gas)](#8--igp-fee-destination-gas)
9. [Output and report](#9--output-and-report)
10. [How to verify delivery](#10--how-to-verify-delivery)
    - [Confirm the send on Terra Classic](#1-confirm-the-send-on-terra-classic)
    - [Track in Hyperlane Explorer](#2-track-the-message-in-the-hyperlane-explorer)
    - [Verify receipt on destination network](#3-verify-receipt-on-the-destination-network)
    - [Query CW20 balance via terrad](#4-check-cw20-balance-before-sending-terra-classic)
    - [Query native LUNC balance via terrad](#5-query-native-lunc-balance-of-a-wallet)
    - [Query multiple CW20 in loop](#6-query-balance-of-multiple-cw20-tokens-all-at-once-via-loop)
11. [Contract reference](#11--contract-reference)
12. [Troubleshooting](#12--troubleshooting)

---

## 1 — Prerequisites

| Dependency | Check | Install |
|---|---|---|
| `node` (≥ 16) | `node --version` | `nvm install 18` |
| `jq` | `jq --version` | `sudo apt install jq` |
| `curl` | `curl --version` | `sudo apt install curl` |
| `python3` | `python3 --version` | available by default on Ubuntu |
| `@cosmjs` (node_modules) | automatic | `cd ~/cw-hyperlane && yarn install` |

The script automatically locates `node_modules` by traversing parent directories until it finds a `package.json`.

---

## 2 — File structure

```
terraclassic/
├── transfer-remote-terra.sh        ← main script
├── warp-evm-config.json            ← EVM config + Terra Classic tokens
├── warp-sealevel-config.json       ← Solana Testnet config
└── log/
    ├── transfer-remote-terra.log   ← cumulative log of all executions
    └── TRANSFER-REMOTE-<NETWORK>-<TOKEN>-<timestamp>.txt  ← report per send
```

The script reads both JSON files to build the list of available options. Only token × network
combinations marked as `"deployed": true` appear in the menu.

---

## 3 — Configure private key

The private key is for the **sender account on Terra Classic**. Must be in hexadecimal format
(32 bytes = 64 hex characters, with or without `0x` prefix).

```bash
export TERRA_PRIVATE_KEY="xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
```

If not set, the script will prompt interactively (hidden input).

> ⚠️ **Never commit your private key to repositories.**  
> Use environment variables or `.env` files outside version control.

---

## 4 — Interactive mode

The simplest mode: the script guides step by step.

```bash
cd ~/cw-hyperlane/terraclassic

export TERRA_PRIVATE_KEY="your_key_hex"
./transfer-remote-terra.sh
```

### Execution flow

**Step 1 — Selection menu**

```
Select the token and destination network:

  [1]   LUNC → Ethereum Sepolia Testnet  (domain 11155111)
  [2]   XPTO → Ethereum Sepolia Testnet  (domain 11155111)
  [3]   XPTV → Ethereum Sepolia Testnet  (domain 11155111)
  [4]   LUNC → BSC Testnet  (domain 97)
  [5]   XPV  → BSC Testnet  (domain 97)
  [6]   LUNC → Solana Testnet  (domain 1399811150)
  [7]   JURIS → Solana Testnet  (domain 1399811150)
  [8]   XPTO → Solana Testnet  (domain 1399811150)

  Option [1-8]:
```

**Step 2 — Recipient address**

```
  EVM format: 0x... (e.g.: 0x867f9ce9f0d7218b016351cb6122406e6d247a5e)
  Recipient address:
```

For Solana:
```
  Solana format: Base58 (e.g.: EMAYGfEyhywUyEX6kfG5FZZMfznmKXM8PbWpkJhJ9Jjd)
  Recipient address:
```

**Step 3 — Amount**

```
  Decimals: 6 — e.g.: 1 XPTO = 1000000
  Amount (in minimum units, e.g.: 10000000):
```

**Step 4 — Summary and confirmation**

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Transfer Summary
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Token          : XPTO  (cw20)
  Destination    : SEPOLIA  (domain 11155111)
  Recipient      : 0x867f9ce9f0d7218b016351cb6122406e6d247a5e
  Recipient b32  : 000000000000000000000000867f9ce9f0d7218b016351cb6122406e6d247a5e
  Amount         : 10000000
  Fee IGP        : 1780832150 uluna
  Warp TC        : terra16ql6l4fuudg0fxarcm4ukxlw0jalg5ljv8kg6h8f7dk9t2e7y6ssq2hqrm
  Collateral CW20: terra1zle6pwm9aztwu228e0spxrydlvmhj2qrq8ap3x2wrjc52kdvu4fs20rkch

  Confirm and send? [y/N]:
```

Type `y` to confirm.

---

## 5 — Non-interactive mode

Useful for automation and scripts. Pass all variables before the call:

```bash
export TERRA_PRIVATE_KEY="your_key_hex"

TOKEN_KEY=xpto \
DEST_NETWORK=sepolia \
RECIPIENT="0x867f9ce9f0d7218b016351cb6122406e6d247a5e" \
AMOUNT=10000000 \
AUTO_CONFIRM=s \
./transfer-remote-terra.sh
```

### Available variables

| Variable | Required | Description | Example |
|---|---|---|---|
| `TERRA_PRIVATE_KEY` | ✅ | Sender hex private key | `xxxxxxxx...` |
| `TOKEN_KEY` | — | Token identifier | `xpto`, `xptv`, `xpv`, `juris`, `wlunc` |
| `DEST_NETWORK` | — | Destination network | `sepolia`, `bsctestnet`, `solanatestnet` |
| `RECIPIENT` | — | Recipient address | `0x867f...` or Base58 |
| `AMOUNT` | — | Value in minimum units | `10000000` |
| `IGP_FEE_ULUNA` | — | Manual fee in uluna (overrides automatic query) | `1780832150` |
| `AUTO_CONFIRM` | — | `s` to skip confirmation | `s` |

If `TOKEN_KEY` and `DEST_NETWORK` are omitted → interactive mode with menu.  
If `RECIPIENT` is omitted → prompted interactively.  
If `AMOUNT` is omitted → prompted interactively.

---

## 6 — Available options (token × network)

Menu options are dynamically generated from the configuration JSONs.
Only combinations with `"deployed": true` appear.

| # | Token | Network | Domain | Type |
|---|---|---|---|---|
| 1 | LUNC | Ethereum Sepolia Testnet | 11155111 | native |
| 2 | XPTO | Ethereum Sepolia Testnet | 11155111 | CW20 |
| 3 | XPTV | Ethereum Sepolia Testnet | 11155111 | CW20 |
| 4 | LUNC | BSC Testnet | 97 | native |
| 5 | XPV  | BSC Testnet | 97 | CW20 |
| 6 | LUNC | Solana Testnet | 1399811150 | native |
| 7 | JURIS | Solana Testnet | 1399811150 | CW20 |
| 8 | XPTO | Solana Testnet | 1399811150 | CW20 |

### Adding a new token/network to the menu

For a new warp to appear in the menu, ensure in `warp-evm-config.json` or
`warp-sealevel-config.json` that:

```json
// warp-evm-config.json → networks.<network>.warp_tokens.<token>
{
  "deployed": true,
  "address": "0xWarpAddressOnEVMNetwork"
}
```

```json
// warp-sealevel-config.json → networks.<network>.warp_tokens.<token>
{
  "deployed": true,
  "program_id": "ProgramIdBase58",
  "program_hex": "0xprogramhex64chars"
}
```

And that the token is in `warp-evm-config.json → terra_classic.tokens.<token>.terra_warp` with `warp_address` filled in.

---

## 7 — Recipient address formats

### EVM (Sepolia, BSC Testnet)

Accepts the standard `0x` format of 20 bytes (40 hex chars):

```
0x867f9ce9f0d7218b016351cb6122406e6d247a5e
```

The script automatically converts to **bytes32** (64 hex chars with left-zero padding):

```
000000000000000000000000867f9ce9f0d7218b016351cb6122406e6d247a5e
```

### Sealevel (Solana Testnet)

Accepts three formats:

1. **Base58** (standard Solana format):
   ```
   EMAYGfEyhywUyEX6kfG5FZZMfznmKXM8PbWpkJhJ9Jjd
   ```

2. **64-char hex without `0x`**:
   ```
   c6525508893d49539a9ae57421ec470517a5c815780b21b93a78e79569c0d01c
   ```

3. **64-char hex with `0x`**:
   ```
   0xc6525508893d49539a9ae57421ec470517a5c815780b21b93a78e79569c0d01c
   ```

> 💡 To find the hex address of a Solana Base58 wallet, use:
> ```bash
> node -e "
> const bs58 = require('node_modules/bs58');
> console.log(Buffer.from(bs58.decode('YOUR_BASE58_ADDRESS')).toString('hex'));
> "
> ```

---

## 8 — IGP Fee (destination gas)

The IGP (Interchain Gas Paymaster) on Terra Classic charges a fee in **uluna** to cover gas
on the destination chain. The script tries to calculate it automatically and uses default values as fallback.

### Automatic calculation

The script queries the IGP contract on Terra Classic via LCD:

```
Contrato : terra1n70g3vg7xge6q8m44rudm4y6fm6elpspwsgfmfphs3teezpak6cs6wxlk9
Query    : quote_gas_payment { dest_domain, gas_amount: "300000" }
```

Tries multiple LCD endpoints in sequence.

### Default values (fallback)

If all LCDs fail, uses real historical values from the project:

| Network | Domain | Default fee (uluna) | Approx LUNC |
|---|---|---|---|
| Sepolia | 11155111 | 1,780,832,150 | ~1.78 LUNC |
| BSC Testnet | 97 | 500,000,000 | ~0.50 LUNC |
| Solana Testnet | 1399811150 | 300,000 | ~0.0003 LUNC |

### Manual override

```bash
IGP_FEE_ULUNA=2000000000 ./transfer-remote-terra.sh
```

> ⚠️ If the fee is insufficient, the transaction fails with a gas error. Increase `IGP_FEE_ULUNA`.

---

## 9 — Output and report

### Success

```
╔═══════════════════════════════════════════════════════════╗
║  ✅  TRANSFER SENT SUCCESSFULLY!                          ║
╚═══════════════════════════════════════════════════════════╝

  TX Hash :  EA8C0788EDF6194BE96C08844045D16189737A38...
  Explorer:  https://finder.hexxagon.io/rebel-2/tx/EA8C...

  The message will be relayed by the Hyperlane Relayer.
  Estimated delivery time: 1-5 minutes.

  Report    : log/TRANSFER-REMOTE-SEPOLIA-XPTO-20260312-120000.txt
```

### Generated files

| File | Content |
|---|---|
| `log/transfer-remote-terra.log` | One line per execution: date, token, network, amount, fee, txhash |
| `log/TRANSFER-REMOTE-<NETWORK>-<TOKEN>-<timestamp>.txt` | Full transfer report |

Report example:
```
TRANSFER REMOTE — Terra Classic → SEPOLIA
Date          : Thu Mar 12 12:00:00 UTC 2026
Token         : XPTO  (cw20)
Destination   : SEPOLIA  (domain 11155111)
Recipient     : 0x867f9ce9f0d7218b016351cb6122406e6d247a5e
Recipient b32 : 000000000000000000000000867f9ce9f0d7218b016351cb6122406e6d247a5e
Amount        : 10000000
Fee IGP       : 1780832150 uluna
Warp TC       : terra16ql6l4fuudg0fxarcm4ukxlw0jalg5ljv8kg6h8f7dk9t2e7y6ssq2hqrm
Collateral    : terra1zle6pwm9aztwu228e0spxrydlvmhj2qrq8ap3x2wrjc52kdvu4fs20rkch
TX Hash       : EA8C0788EDF6194BE96C08844045D16189737A38...
Explorer      : https://finder.hexxagon.io/rebel-2/tx/EA8C...
```

---

## 10 — How to verify delivery

### 1. Confirm the send on Terra Classic

```
https://finder.hexxagon.io/rebel-2/tx/<TX_HASH>
```

Check in the contract events:
- `wasm-HplMessage.dispatched` → message dispatched by Mailbox
- `wasm-HplIgp.gas_payment` → IGP fee paid
- `message_id` → message ID (bytes32 hex)

### 2. Track the message in the Hyperlane Explorer

```
https://explorer.hyperlane.xyz/message/<MESSAGE_ID>
```

The status should progress through:
1. **Dispatched** → message sent
2. **Signed** → validator signed
3. **Relayed** → relayer delivered to destination

### 3. Verify receipt on the destination network

**EVM (Sepolia / BSC Testnet):**

Access the recipient address in the destination network explorer and check the Warp ERC-20 token balance.

- Sepolia Explorer: `https://sepolia.etherscan.io/address/<RECIPIENT>`
- BSC Testnet: `https://testnet.bscscan.com/address/<RECIPIENT>`

**Solana Testnet:**

```bash
spl-token accounts --owner <RECIPIENT_BASE58> --url https://api.testnet.solana.com
```

Ou no explorer:
```
https://explorer.solana.com/address/<RECIPIENT>?cluster=testnet
```

### 4. Check CW20 balance before sending (Terra Classic)

**Via `terrad` (recommended):**

```bash
terrad query wasm contract-state smart \
  <CW20_ADDRESS> \
  '{"balance":{"address":"<YOUR_WALLET>"}}' \
  --node https://rpc.terra-classic.hexxagon.dev:443
```

Exemplo real com XPTO:

```bash
terrad query wasm contract-state smart \
  terra1zle6pwm9aztwu228e0spxrydlvmhj2qrq8ap3x2wrjc52kdvu4fs20rkch \
  '{"balance":{"address":"terra18lr7ujd9nsgyr49930ppaajhadzrezam70j39k"}}' \
  --node https://rpc.terra-classic.hexxagon.dev:443
```

Expected response:

```yaml
data:
  balance: "10000000"
```

**Via `curl` (without terrad installed):**

```bash
curl -s "https://lcd.terra-classic.hexxagon.dev/cosmwasm/wasm/v1/contract/<CW20_ADDRESS>/smart/$(
  python3 -c "import json,base64; print(base64.b64encode(json.dumps({'balance':{'address':'<YOUR_WALLET>'}}).encode()).decode())"
)" | jq '.data.balance'
```

### 5. Query native LUNC balance of a wallet

```bash
terrad query bank balances <SUA_CARTEIRA> \
  --node https://rpc.terra-classic.hexxagon.dev:443
```

Example:

```bash
terrad query bank balances terra18lr7ujd9nsgyr49930ppaajhadzrezam70j39k \
  --node https://rpc.terra-classic.hexxagon.dev:443
```

Expected response:

```yaml
balances:
- amount: "5000000000"
  denom: uluna
```

> 💡 `uluna` is the minimum unit of LUNC. Divide by `1,000,000` to get the value in LUNC.  
> Example: `5000000000 uluna` = `5000 LUNC`

### 6. Query balance of multiple CW20 tokens (all at once via loop)

```bash
# List of CW20 contracts and names (adapt to your tokens)
declare -A CW20_TOKENS=(
  ["XPTO"]="terra1zle6pwm9aztwu228e0spxrydlvmhj2qrq8ap3x2wrjc52kdvu4fs20rkch"
  ["XPTV"]="terra19ujvy60tjeyehjrwlrdpqlp0gxmtt4qv452nwjqc6w6m38pm8xmq22lux3"
  ["XPV"]="terra1f2jw36hc7fzeu7dz2fhk250ezec7e80c2s6uxt3ry5ujjjslf9nqwvpu88"
  ["JURIS"]="terra1w7d0jqehn0ja3hkzsm0psk6z2hjz06lsq0nxnwkzkkq4fqwgq6tqa5te8e"
)
WALLET="terra18lr7ujd9nsgyr49930ppaajhadzrezam70j39k"
NODE="https://rpc.terra-classic.hexxagon.dev:443"

echo "Balances for $WALLET"
for TOKEN in "${!CW20_TOKENS[@]}"; do
  ADDR="${CW20_TOKENS[$TOKEN]}"
  BAL=$(terrad query wasm contract-state smart "$ADDR" \
    "{\"balance\":{\"address\":\"$WALLET\"}}" \
    --node "$NODE" -o json 2>/dev/null | jq -r '.data.balance // "0"')
  echo "  $TOKEN: $BAL"
done
```

---

## 11 — Contract reference

### Terra Classic — Warp Contracts

| Token | Type | CW20 Collateral | Warp Contract |
|---|---|---|---|
| LUNC (WLUNC) | native | — | `terra1zlm0h2xu6rhnjchn29hxnpvr74uxxqetar9y75zcehyx2mqezg9slj09ml` |
| JURIS | CW20 | `terra1w7d0jqehn0ja3hkzsm0psk6z2hjz06lsq0nxnwkzkkq4fqwgq6tqa5te8e` | `terra1stu3cl7mhtsc2mf9cputawfd6v6e4a2nkmhhphh47lsrr3j6ktdqlcfe2l` |
| XPTO | CW20 | `terra1zle6pwm9aztwu228e0spxrydlvmhj2qrq8ap3x2wrjc52kdvu4fs20rkch` | `terra16ql6l4fuudg0fxarcm4ukxlw0jalg5ljv8kg6h8f7dk9t2e7y6ssq2hqrm` |
| XPTV | CW20 | `terra19ujvy60tjeyehjrwlrdpqlp0gxmtt4qv452nwjqc6w6m38pm8xmq22lux3` | `terra1n8y4sj9lrqq66pf7je0nm7s6nhln5z4s3accw9g2aassdh8dzqts9y0928` |
| XPV  | CW20 | `terra1f2jw36hc7fzeu7dz2fhk250ezec7e80c2s6uxt3ry5ujjjslf9nqwvpu88` | `terra1dnflusc7slapvals97em3fj4vrfyx90npr3znq6y45qjy7hhd6jqchqsgx` |

### Terra Classic — Hyperlane Contracts

| Contract | Address |
|---|---|
| Mailbox | `terra1rqg3qfkfg5upad9xu6zj5jhl626qy053s7rn08829rgqzv2wu39s5la8yf` |
| IGP | `terra1n70g3vg7xge6q8m44rudm4y6fm6elpspwsgfmfphs3teezpak6cs6wxlk9` |
| ISM Routing | `terra1h4sd8fyxhde7dc9w9y9zhc2epphgs75q7zzfg3tfynm8qvpe3jlsd7sauh` |

### Sepolia (domain 11155111)

| Token | Warp ERC-20 |
|---|---|
| LUNC | `0x224a4419D7FA69D3bEbAbce574c7c84B48D829b4` |
| XPTO | `0xbF43aA4878f5Ad0fcAC12Cd3A835DD3506981048` |
| XPTV | `0x7d92c2E01933F1C651845152DBd4222d475Bd9f0` |

### BSC Testnet (domain 97)

| Token | Warp ERC-20 |
|---|---|
| LUNC | `0x2144Be4477202ba2d50c9A8be3181241878cf7D8` |
| XPV  | `0x11D6aa52d60611a513ab783842Dc397C86E7fff0` |

### Solana Testnet (domain 1399811150)

| Token | Program ID |
|---|---|
| LUNC | `5BuTS1oZhUKJgpgwXJyz5VRdTq99SMvHm7hrPMctJk6x` |
| JURIS | `G3eEYHv2GrBJ6KTS3XQhRd7QYdwnfWjisQrSVWedQK4y` |
| XPTO | `jNkiNLXQetj9L2tDX6xTgx9QP1tgtNgYXamouNbbwx9` |

---

## 12 — Troubleshooting

### ❌ `Account '...' does not exist on chain`

The sender account does not exist or has never received funds on Terra Classic.

```
Cause  : wallet never used or incorrect private key
Fix    : check the address at https://finder.hexxagon.io/rebel-2
         make sure the account has a LUNC balance
```

### ❌ `route not found`

The Terra Classic warp contract has no route configured for the destination network.

```
Cause  : enrollRemoteRouter was not executed or route points to old address
Fix    : run create-warp-evm.sh or create-warp-sealevel.sh to reconfigure
         or use enroll-terra-router.sh to do it manually
```

### ❌ `insufficient funds` / `out of gas`

```
Cause  : insufficient LUNC balance or underestimated IGP fee
Fix    : check balance with:
           curl -s "https://lcd.terra-classic.hexxagon.dev/cosmos/bank/v1beta1/balances/<WALLET>"
         increase the fee with:
           IGP_FEE_ULUNA=3000000000 ./transfer-remote-terra.sh
```

### ❌ `No deployed token/network combination found`

```
Cause  : warp-evm-config.json or warp-sealevel-config.json has no token
         with "deployed": true and valid address
Fix    : check the configuration files and confirm the warp was deployed
```

### ❌ Message sent but does not arrive at destination

**Step-by-step diagnosis:**

1. Confirm the TX went through on Terra Classic:
   ```
   https://finder.hexxagon.io/rebel-2/tx/<TX_HASH>
   ```

2. Check the relayer/validator in the Hyperlane Explorer:
   ```
   https://explorer.hyperlane.xyz/message/<MESSAGE_ID>
   ```
   The `message_id` appears in TX events as `wasm-HplMessage.dispatched`.

3. Confirm the validator is generating checkpoints:
   - Terra Classic: `https://hyperlane-validator-signatures-igorveras-terraclassic.s3.us-east-1.amazonaws.com/`

4. Verify the reverse route is configured (destination → Terra Classic):
   - The warp on the destination network must have `enrollRemoteRouter` pointing to the Terra Classic warp.

### ❌ `Invalid EVM address` or `Invalid Solana address`

```
EVM   : use exactly 40 hex chars with 0x (e.g.: 0xAbCd...1234)
Solana: use standard Base58 (e.g.: EMAYGf...) or exactly 64 hex chars without 0x
```

### ❌ `node_modules/@cosmjs/cosmwasm-stargate not found`

```bash
cd ~/cw-hyperlane
yarn install
```

---

## Useful links

| Resource | URL |
|---|---|
| Terra Classic Explorer | https://finder.hexxagon.io/rebel-2 |
| Hyperlane Explorer (messages) | https://explorer.hyperlane.xyz |
| Sepolia Etherscan | https://sepolia.etherscan.io |
| BSC Testnet Explorer | https://testnet.bscscan.com |
| Solana Testnet Explorer | https://explorer.solana.com/?cluster=testnet |
| Terra Classic Mailbox | https://finder.hexxagon.io/rebel-2/address/terra1rqg3qfkfg5upad9xu6zj5jhl626qy053s7rn08829rgqzv2wu39s5la8yf |
| Terra Classic S3 Validator | https://hyperlane-validator-signatures-igorveras-terraclassic.s3.us-east-1.amazonaws.com/ |
| Sepolia S3 Validator | https://hyperlane-validator-signatures-igorveras-sepolia.s3.us-east-1.amazonaws.com/ |
| BSC Testnet S3 Validator | https://hyperlane-validator-signatures-igorveras-bsctestnet.s3.us-east-1.amazonaws.com/ |
