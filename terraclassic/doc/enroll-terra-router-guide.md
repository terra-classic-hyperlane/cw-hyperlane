# Guide: `enroll-terra-router.sh`

> Interactive script to register the EVM route in the **Terra Classic** Warp contract.  
> Resolves the `route not found` error when calling `transfer_remote` and ensures the bidirectional Warp Route link.

---

## 📋 Table of Contents

1. [What the script does](#1-what-the-script-does)
2. [When to use](#2-when-to-use)
3. [Prerequisites](#3-prerequisites)
4. [How to run](#4-how-to-run)
5. [What happens under the hood](#5-what-happens-under-the-hood)
6. [Understanding the bidirectional link](#6-understanding-the-bidirectional-link)
7. [Checking the current state](#7-checking-the-current-state)
8. [Troubleshooting](#8-troubleshooting)
9. [Useful links](#9-useful-links)

---

## 1. What the script does

The `enroll-terra-router.sh` calls the `router.set_route` function on the **Terra Classic** Warp contract to register the address of a Warp contract on an EVM network (e.g.: Sepolia) as an authorized router.

Without this registration, any `transfer_remote` call from Terra Classic will fail with:

```
route not found: wasmvm error
```

The script:
1. Reads configuration from `warp-evm-config.json`
2. Shows menus to select the **token** and the destination **EVM network**
3. Converts the EVM address to `bytes32` (format required by the Warp contract)
4. Displays a summary and asks for confirmation
5. Executes the transaction via Node.js + `@cosmjs`
6. Checks if the route was already configured (avoids duplicates)

---

## 2. When to use

| Situation | Action |
|---|---|
| `transfer_remote` fails with `route not found` | Run this script |
| Deploy completed without `TERRA_PRIVATE_KEY` (Step 7B skipped) | Run this script |
| EVM Warp was re-deployed at a new address | Run this script to update the route |
| First time adding an EVM network to an existing token | Run this script after the EVM deploy |
| Preventive check before transferring | Use the [Checking the current state](#7-checking-the-current-state) section |

> **Context:** The `create-warp-evm.sh` executes this step automatically (Step 7B) when `TERRA_PRIVATE_KEY` is set. Use `enroll-terra-router.sh` only when you need to run it manually afterwards.

---

## 3. Prerequisites

| Requirement | Check |
|---|---|
| `node` 18+ | `node --version` |
| `jq` | `jq --version` |
| `@cosmjs` packages installed | `ls node_modules/@cosmjs/cosmwasm-stargate` |
| `TERRA_PRIVATE_KEY` with LUNA balance | owner of the Terra Classic Warp contract |
| `warp-evm-config.json` updated | token with `warp_address` filled in + network with `warp_tokens.<token>.deployed: true` |

### Check if data is in the config:

```bash
# XPTO token — check if warp_address is filled
jq '.terra_classic.tokens.xpto.terra_warp' terraclassic/warp-evm-config.json

# Sepolia network — check if xpto warp is deployed
jq '.networks.sepolia.warp_tokens.xpto' terraclassic/warp-evm-config.json
```

---

## 4. How to run

```bash
# 1. Enter the terraclassic folder
cd ~/cw-hyperlane/terraclassic

# 2. Grant permission (first time only)
chmod +x enroll-terra-router.sh

# 3. Set the Terra Classic private key
export TERRA_PRIVATE_KEY="your_hex_key"   # without 0x prefix

# 4. Run
./enroll-terra-router.sh
```

### Execution example

```
╔══════════════════════════════════════════════════════╗
║   enrollRemoteRouter — TERRA CLASSIC (set_route)    ║
╚══════════════════════════════════════════════════════╝

📌 Select the TOKEN to link:

  [1] XPTO — terra16ql6l4fuudg0fxarcm4ukxlw0jalg5ljv8kg6h8f7dk9t2e7y6ssq2hqrm
  [2] JURIS — terra1stu3c...

▶ Enter the number: 1

📌 Select the destination EVM network:

  [1] Ethereum Sepolia Testnet (domain 11155111) — 0xbF43aA4878f5Ad0fcAC12Cd3A835DD3506981048

▶ Enter the number: 1

📋 Operation parameters:
   Token         : XPTO (xpto)
   Terra Warp    : terra16ql6l4fuudg0fxarcm4ukxlw0jalg5ljv8kg6h8f7dk9t2e7y6ssq2hqrm
   EVM Network   : Ethereum Sepolia Testnet (domain 11155111)
   EVM Warp      : 0xbF43aA4878f5Ad0fcAC12Cd3A835DD3506981048
   EVM bytes32   : 000000000000000000000000bf43aa4878f5ad0fcac12cd3a835dd3506981048
   Terra RPC     : https://rpc.terra-classic.hexxagon.dev

CosmWasm message to be executed:
{
  "router": {
    "set_route": {
      "set": {
        "domain": 11155111,
        "route": "000000000000000000000000bf43aa4878f5ad0fcac12cd3a835dd3506981048"
      }
    }
  }
}

▶ Confirm? [y/N]: y

⏳ Sending transaction...

╔══════════════════════════════════════════════════════╗
║    ✅ set_route EXECUTED SUCCESSFULLY!               ║
╚══════════════════════════════════════════════════════╝

📦 Transaction:
   TX Hash   : D24446E27DAB952ED26B538358AF687BE19CA8DE98B89BC8A601D617AD8DD8A5
   Block     : 24571234
   Gas used  : 180000
   Sender    : terra12awgqgwm2evj05ndtgs0xa35uunlpc76d85pze

   🔗 Explorer:
   https://finder.hexxagon.io/rebel-2/tx/D24446E27DAB952...
```

---

## 5. What happens under the hood

### 5.1 EVM address → bytes32 conversion

The Terra Classic Warp contract stores routers as `bytes32`. The EVM address (20 bytes) is converted to `bytes32` with left-zero padding:

```
EVM address (20 bytes / 40 hex chars):
  0xbF43aA4878f5Ad0fcAC12Cd3A835DD3506981048

bytes32 (32 bytes / 64 hex chars):
  000000000000000000000000bf43aa4878f5ad0fcac12cd3a835dd3506981048
  ^^^^^^^^^^^^^^^^^^^^^^^^  ← 24 zeros of padding (12 bytes)
```

The script uses:
```bash
EVM_WARP_HEX="${EVM_WARP_ADDR#0x}"
EVM_WARP_B32=$(printf '%064s' "$EVM_WARP_HEX" | tr ' ' '0')
```

### 5.2 Existing route check

Before sending the transaction, the script queries `router.list_routes` to check if the route already exists:

```javascript
const { routes } = await client.queryContractSmart(terraWarp, {
    router: { list_routes: {} }
});
const existing = routes.find(r => r.domain === evmDomain);
if (existing && existing.route) {
    // route already configured — do not re-send
}
```

> ⚠️ **Do not use `router.get_route`** for this check. When the domain does not exist, it returns
> `{"route": null}` instead of an error, causing false positives. `list_routes` is reliable.

### 5.3 Execution via @cosmjs

The transaction is sent using `SigningCosmWasmClient.execute` from the `@cosmjs/cosmwasm-stargate` package:

```javascript
const result = await client.execute(
    senderAddress,
    terraWarpContract,
    { router: { set_route: { set: { domain: evmDomain, route: evmRouteHex } } } },
    "auto",   // automatic gas estimation
    "enrollRemoteRouter via enroll-terra-router.sh"
);
```

---

## 6. Understanding the bidirectional link

A Hyperlane Warp Route requires configuration on **both sides** to work:

```
Terra Classic → Sepolia:
  Terra Classic Warp contract knows domain 11155111 uses address 0xbF43aA...
  (configured by this script via router.set_route)

Sepolia → Terra Classic:
  Sepolia Warp contract knows domain 1325 uses address terra16ql6l...
  (configured by create-warp-evm.sh in Step 7 via enrollRemoteRouter)
```

### On-chain verification of both sides:

```bash
RPC="https://ethereum-sepolia-rpc.publicnode.com"

# Sepolia side: routers(1325) should be the hex of the Terra Classic Warp
cast call 0xbF43aA4878f5Ad0fcAC12Cd3A835DD3506981048 \
  "routers(uint32)(bytes32)" 1325 --rpc-url $RPC
# Expected: 0xd03fafd53ce350f49ba3c6ebcb1bee7cbbf453f261ec8d5ce9f36c55ab3e26a1

# Terra Classic side: list_routes should contain domain 11155111
node -e "
const p=require('path'), nm=p.join('/home/lunc/cw-hyperlane','node_modules');
const {CosmWasmClient}=require(p.join(nm,'@cosmjs/cosmwasm-stargate'));
(async()=>{
  const c=await CosmWasmClient.connect('https://rpc.terra-classic.hexxagon.dev');
  const r=await c.queryContractSmart(
    'terra16ql6l4fuudg0fxarcm4ukxlw0jalg5ljv8kg6h8f7dk9t2e7y6ssq2hqrm',
    {router:{list_routes:{}}}
  );
  console.log(JSON.stringify(r.routes, null, 2));
})();"
# Expected: [{ domain: 11155111, route: "000000000000000000000000bf43aa4878..." }]
```

---

## 7. Checking the current state

Before running the script, check if the route is already configured:

```bash
cd ~/cw-hyperlane

# Query all routes registered on the XPTO Terra Classic Warp
node --no-warnings -e "
const p=require('path'), nm=p.join(process.cwd(),'node_modules');
const {CosmWasmClient}=require(p.join(nm,'@cosmjs/cosmwasm-stargate'));
(async()=>{
  const c=await CosmWasmClient.connect('https://rpc.terra-classic.hexxagon.dev');
  const r=await c.queryContractSmart(
    'terra16ql6l4fuudg0fxarcm4ukxlw0jalg5ljv8kg6h8f7dk9t2e7y6ssq2hqrm',
    {router:{list_routes:{}}}
  );
  if(!r.routes || r.routes.length === 0) {
    console.log('❌ No routes configured!');
  } else {
    r.routes.forEach(rt => console.log('domain', rt.domain, '→', rt.route));
  }
})().catch(e=>console.log('Error:', e.message));"
```

**Expected result (everything configured):**
```
domain 11155111 → 000000000000000000000000bf43aa4878f5ad0fcac12cd3a835dd3506981048
```

**Result that indicates a problem:**
```
❌ No routes configured!
```
or
```
domain 11155111 → null
```

---

## 8. Troubleshooting

### ❌ `No token with warp_address configured`

**Cause:** The `terra_warp.warp_address` field is empty in `warp-evm-config.json`.

**Solution:** Fill in the Terra Classic Warp address after the deploy:

```json
"xpto": {
  "terra_warp": {
    "warp_address": "terra16ql6l4fuudg0fxarcm4ukxlw0jalg5ljv8kg6h8f7dk9t2e7y6ssq2hqrm",
    "warp_hexed":   "0xd03fafd53ce350f49ba3c6ebcb1bee7cbbf453f261ec8d5ce9f36c55ab3e26a1",
    "deployed":     true
  }
}
```

---

### ❌ `No EVM network with TOKEN deployed`

**Cause:** `warp_tokens.<token>.deployed` is `false` or the `address` field is empty.

**Solution:** After the EVM deploy, update the JSON:

```json
"warp_tokens": {
  "xpto": {
    "deployed": true,
    "address":  "0xbF43aA4878f5Ad0fcAC12Cd3A835DD3506981048"
  }
}
```

---

### ❌ `Invalid private key`

**Cause:** The key format is wrong.

**Solution:** The key must be hexadecimal without the `0x` prefix:

```bash
# ✅ Correct:
export TERRA_PRIVATE_KEY="xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"

# ❌ With 0x — the script removes it automatically, but check for extra spaces:
export TERRA_PRIVATE_KEY="0xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
```

---

### ❌ `out of gas` or insufficient gas

**Cause:** The estimated gas (`"auto"`) was not enough, or the configured price is too low.

**Solution:** The script uses `28.325uluna` as gasPrice, which is the standard for Terra Classic testnet. If the network is congested, you may need to increase it:

```javascript
// Inside the script, change the line:
const gasPrice = GasPrice.fromString("28.325uluna");
// To:
const gasPrice = GasPrice.fromString("50uluna");
```

---

### ❌ `account sequence mismatch`

**Cause:** The RPC is lagging or another transaction was sent simultaneously.

**Solution:** Wait a few blocks and try again. Check if the RPC is synchronized:

```bash
curl -s "https://rpc.terra-classic.hexxagon.dev/status" | jq '.result.sync_info.latest_block_height'
```

> Always use the `hexxagon` RPC — it is the most synchronized for rebel-2.

---

### ✅ Route already configured (`already_set`) but `transfer_remote` still fails

**Possible causes:**

1. **The EVM side is not configured** — check `routers(1325)` on the Sepolia Warp:
   ```bash
   cast call $WARP_EVM "routers(uint32)(bytes32)" 1325 \
     --rpc-url https://ethereum-sepolia-rpc.publicnode.com
   # Must be != 0x000...
   ```

2. **Incorrect domain in `transfer_remote`** — confirm you are passing `11155111` (Sepolia) and not another value.

3. **Registered EVM address is outdated** — if the EVM Warp was re-deployed, the route points to the old address. Re-run the script to update.

---

## 9. Useful links

| Resource | URL |
|---|---|
| Hyperlane Explorer | [explorer.hyperlane.xyz](https://explorer.hyperlane.xyz) |
| Terra Classic Finder (testnet) | [finder.hexxagon.io/rebel-2](https://finder.hexxagon.io/rebel-2) |
| Terra Classic Finder (mainnet) | [finder.terra.money](https://finder.terra.money) |
| Sepolia Etherscan | [sepolia.etherscan.io](https://sepolia.etherscan.io) |
| Hyperlane Warp Routes Documentation | [docs.hyperlane.xyz/docs/protocol/warp-routes](https://docs.hyperlane.xyz/docs/protocol/warp-routes/overview) |
| Main guide (`create-warp-evm.sh`) | [`create-warp-evm-guide.md`](./create-warp-evm-guide.md) |
