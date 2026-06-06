# Updating Warp Route Settings on Solana — ISM, IGP, Oracle, Router

This guide explains how to update the configuration of an already-deployed
Hyperlane Warp Route on Solana without redeploying the program.

---

## Table of Contents

1. [Quick Start](#1-quick-start)
2. [What Can Be Updated](#2-what-can-be-updated)
3. [Using update-warp-solana.sh](#3-using-update-warp-solanaش)
4. [Action Reference](#4-action-reference)
   - [1 — Query Current State](#1--query-current-state)
   - [2 — Update ISM](#2--update-ism)
   - [3 — Update IGP](#3--update-igp)
   - [4 — Update Destination Gas Amount](#4--update-destination-gas-amount)
   - [5 — Update Gas Oracle](#5--update-gas-oracle)
   - [6 — Update Gas Overhead](#6--update-gas-overhead)
   - [7 — Enroll / Update Remote Router](#7--enroll--update-remote-router)
   - [8 — Transfer Ownership](#8--transfer-ownership)
5. [Manual Commands Reference](#5-manual-commands-reference)
6. [Architecture: ISM vs IGP vs Oracle](#6-architecture-ism-vs-igp-vs-oracle)

---

## 1. Quick Start

```bash
cd ~/tc-cw-hyperlane/terraclassic
./update-warp-solana.sh
```

Select the token, the network, and the action from the interactive menu.
All changes are logged to `log/update-warp-solana.log`.

---

## 2. What Can Be Updated

| Setting | What It Controls | Script Action |
|---------|-----------------|---------------|
| **ISM** | Which MultisigISM validates messages arriving from Terra Classic | 2 |
| **IGP program + account** | Which gas paymaster pays for cross-chain gas | 3 |
| **Destination gas amount** | How many gas units are attached to each message (token-level) | 4 |
| **Gas oracle** | Token exchange rate and gas price for a remote domain (IGP-level) | 5 |
| **Gas overhead** | Extra gas units added per message for a domain (Overhead IGP-level) | 6 |
| **Remote router** | The Terra Classic warp contract address registered on Solana | 7 |
| **Ownership** | Who can make admin changes to the warp program | 8 |

---

## 3. Using update-warp-solana.sh

```bash
./update-warp-solana.sh
```

**Menus:**
1. Select token (e.g., `igorfake`, `ustc`)
2. Select Solana network (e.g., `solanamainnet`)
3. Select action (1–8)

The script reads all addresses from `warp-sealevel-config.json` automatically.
After any update, the config file is updated to reflect the new values.

**No environment variables required** — the script uses the keypair configured
in `warp-sealevel-config.json` which must be the authority/owner of the program.

---

## 4. Action Reference

### 1 — Query Current State

Displays the full current configuration of the warp route, IGP, and ISM.

```
Output includes:
  - mailbox, ISM, IGP, decimals, owner
  - destination_gas per domain
  - remote_routers per domain
  - mint address
  - IGP oracle data (exchange rate, gas price)
  - ISM validators and threshold
```

### 2 — Update ISM

Changes which MultisigISM program validates messages coming from Terra Classic.

**When to use:**
- Upgrading to a new ISM with different validators or threshold
- Switching from a test ISM to a production ISM
- Disabling the ISM (set to `null` / no ISM — messages accepted without validation)

**Input:** New ISM program ID (base58)

**Example:**
```
New ISM program ID: LwNfVYMDzAe5dCJgA5CipTZcT34Eyf74zLr81K91jxk
```

**Effect:** Updates `warp-sealevel-config.json → .networks.<net>.ism.program_id`

---

### 3 — Update IGP

Changes the Interchain Gas Paymaster that handles gas payments for cross-chain messages.

**When to use:**
- Switching to a new IGP program or account
- Changing from a standard IGP to an Overhead IGP (or vice versa)

**Inputs:**
- New IGP program ID (base58)
- New IGP account (base58) — this is the specific IGP or OverheadIGP account
- IGP type: `igp` (standard) or `overhead-igp` (recommended for mainnet)

**IGP types explained:**
| Type | Description |
|------|-------------|
| `igp` | Standard IGP — pays exactly the oracle gas price |
| `overhead-igp` | Adds a fixed overhead on top of oracle price — use for mainnet |

**Example:**
```
New IGP program: BhNcatUDC2D5JTyeaqrdSukiVFsEHK7e3hVmKMztwefv
New IGP account: AkeHBbE5JkwVppujCQQ6WuxsVsJtruBAjUo6fDCFp6fF
Type: overhead-igp
```

**Effect:** Updates `warp-sealevel-config.json → .networks.<net>.igp.*`

---

### 4 — Update Destination Gas Amount

Sets how many gas units are sent with each cross-chain message to a specific domain.
This is stored on the **warp route program** (not the IGP).

**When to use:**
- Terra Classic transactions are failing with "out of gas"
- Optimizing gas costs (reducing the amount if messages consistently use less)

**Input:**
- Domain ID (Terra Classic = `1325`)
- Gas amount (e.g., `3000000` = 3 million gas units)

**Typical value:** `3000000` for Terra Classic

**Effect:** Updates `warp-sealevel-config.json → .networks.<net>.igp.destination_gas_terra`

---

### 5 — Update Gas Oracle

Sets the **token exchange rate** and **gas price** used by the IGP to calculate
how much SOL to charge the sender for a cross-chain message.

This is configured on the **IGP program** directly, not on the warp route.

**When to use:**
- Token prices have changed significantly (e.g., SOL/LUNC exchange rate)
- Gas prices on Terra Classic have changed
- Messages are being over- or under-charged

**Inputs:**
- Remote domain (Terra Classic = `1325`)
- Token exchange rate (integer, e.g., `1000000000000000000` = 1.0 in 18-decimal format)
- Gas price (in the remote chain's native token, e.g., `28325000000` for Terra Classic)
- Token decimals (18 for LUNC, 9 for SOL)

**How exchange rate works:**

The exchange rate represents `(SOL price / remote token price)` scaled to 18 decimals.

```
exchange_rate = (SOL_USD / LUNC_USD) × 10^18

Example: SOL = $150, LUNC = $0.0001
exchange_rate = (150 / 0.0001) × 10^18 = 1_500_000 × 10^18 = 1_500_000_000_000_000_000_000_000
```

**Note:** This command requires the environments directory in the monorepo to be
properly configured. It reads/writes configuration via the environments system.

---

### 6 — Update Gas Overhead

Sets a fixed overhead gas amount added on top of the oracle estimate for each
message to a specific domain. Only applies when using an **Overhead IGP**.

**When to use:**
- Tuning the gas buffer to account for execution variance
- Terra Classic executions consistently run over/under the oracle estimate

**Inputs:**
- Remote domain (Terra Classic = `1325`)
- Gas overhead amount (e.g., `200000`)

**Note:** This also uses the environments directory system in the monorepo.

---

### 7 — Enroll / Update Remote Router

Registers (or updates) the Terra Classic warp contract address on the Solana
warp program. This is the Solana → Terra Classic directional link.

**When to use:**
- Terra Classic warp contract was redeployed to a new address
- Adding a new remote domain (e.g., adding BSC support)
- Initial setup if enroll was skipped during deploy

**Inputs:**
- Remote domain (Terra Classic = `1325`)
- Remote router address in hex (0x format), e.g.:
  `0xdd2cbc22fdfb1ebfc9e2119565eb87eb67c87dcdad4bbfd29ceee9e83f38f921`

**Note:** The Terra Classic → Solana direction (`set_route`) must be done
separately on the Terra Classic side using `terrad` or the deploy script.

---

### 8 — Transfer Ownership

Transfers admin authority over the warp program to a new public key.

**Warning:** This is effectively irreversible. The new owner must sign any
future admin transactions. If you lose access to the new owner keypair,
the program settings cannot be updated.

**When to use:**
- Moving from a development keypair to a multisig
- Handing off program control to a DAO or governance contract

**Input:** New owner public key (base58)

---

## 5. Manual Commands Reference

If the script fails or you prefer the CLI directly:

```bash
CLIENT="$HOME/hyperlane-monorepo/rust/sealevel/target/release/hyperlane-sealevel-client"
KEY="/path/to/solana-keypair.json"
RPC="https://mainnet.helius-rpc.com/?api-key=YOUR_HELIUS_API_KEY"
PID="<WARP_PROGRAM_ID>"
```

### Query warp state
```bash
$CLIENT -k $KEY -u $RPC token query --program-id $PID synthetic
```

### Query IGP state
```bash
$CLIENT -k $KEY -u $RPC igp query \
  --program-id BhNcatUDC2D5JTyeaqrdSukiVFsEHK7e3hVmKMztwefv \
  --igp-account AkeHBbE5JkwVppujCQQ6WuxsVsJtruBAjUo6fDCFp6fF
```

### Query ISM (validators + threshold for a domain)
```bash
$CLIENT -k $KEY -u $RPC multisig-ism-message-id query \
  --program-id LwNfVYMDzAe5dCJgA5CipTZcT34Eyf74zLr81K91jxk \
  --domains 1325
```

### Update ISM
```bash
$CLIENT -k $KEY -u $RPC token set-interchain-security-module \
  --program-id $PID \
  --ism <NEW_ISM_PROGRAM_ID>
```

### Update IGP (overhead-igp type)
```bash
$CLIENT -k $KEY -u $RPC token igp \
  --program-id $PID \
  set <IGP_PROGRAM_ID> overhead-igp <OVERHEAD_IGP_ACCOUNT>
```

### Update IGP (standard igp type)
```bash
$CLIENT -k $KEY -u $RPC token igp \
  --program-id $PID \
  set <IGP_PROGRAM_ID> igp <IGP_ACCOUNT>
```

### Update destination gas (warp route level)
```bash
$CLIENT -k $KEY -u $RPC token set-destination-gas \
  --program-id $PID \
  1325 3000000
```

### Update gas oracle (IGP level)
```bash
ENV="mainnet3"
ENV_DIR="$HOME/hyperlane-monorepo/rust/sealevel/environments"

$CLIENT -k $KEY -u $RPC igp gas-oracle-config \
  --environment $ENV \
  --environments-dir $ENV_DIR \
  --chain-name solanamainnet \
  --remote-domain 1325 \
  set \
  --token-exchange-rate 1000000000000000000 \
  --gas-price 28325000000 \
  --token-decimals 18
```

### Update gas overhead (Overhead IGP level)
```bash
$CLIENT -k $KEY -u $RPC igp destination-gas-overhead \
  --environment $ENV \
  --environments-dir $ENV_DIR \
  --chain-name solanamainnet \
  --remote-domain 1325 \
  set \
  --gas-overhead 200000
```

### Enroll remote router
```bash
$CLIENT -k $KEY -u $RPC token enroll-remote-router \
  --program-id $PID \
  1325 0xdd2cbc22fdfb1ebfc9e2119565eb87eb67c87dcdad4bbfd29ceee9e83f38f921
```

### Transfer ownership
```bash
$CLIENT -k $KEY -u $RPC token transfer-ownership \
  --program-id $PID \
  <NEW_OWNER_PUBKEY>
```

---

## 6. Architecture: ISM vs IGP vs Oracle

```
┌──────────────────────────────────────────────────────────────┐
│                    WARP ROUTE PROGRAM                        │
│   (one per token per network — e.g., IGORFAKE on mainnet)   │
│                                                              │
│   ┌─────────────────┐   ┌──────────────────────────────┐    │
│   │  ISM (Script 2) │   │  Destination Gas (Script 4)  │    │
│   │  Which ISM       │   │  Gas units sent with each    │    │
│   │  validates msgs  │   │  message to Terra Classic    │    │
│   └────────┬────────┘   └──────────────────────────────┘    │
│            │                                                  │
│   ┌────────▼──────────────────────────────────────────────┐  │
│   │  IGP (Script 3) — Which gas paymaster to use          │  │
│   └────────┬──────────────────────────────────────────────┘  │
└────────────┼─────────────────────────────────────────────────┘
             │
             ▼
┌─────────────────────────────────────────────────────────────┐
│                  OVERHEAD IGP PROGRAM                        │
│   (shared across warp routes on the same network)           │
│                                                              │
│   ┌──────────────────────┐  ┌───────────────────────────┐   │
│   │ Gas Oracle (Script 5) │  │ Gas Overhead (Script 6)   │   │
│   │ exchange_rate         │  │ Fixed gas buffer added    │   │
│   │ gas_price             │  │ per domain                │   │
│   │ token_decimals        │  └───────────────────────────┘   │
│   └──────────────────────┘                                   │
└─────────────────────────────────────────────────────────────┘
```

**Key insight:** Actions 2, 3, 4, 7, 8 write to the **warp route program**.
Actions 5 and 6 write to the **IGP program** (shared infrastructure).

The ISM program itself is not changed here — you can only change *which ISM*
the warp route points to (action 2). To change ISM validators or threshold,
use `multisig-ism-message-id set-validators-and-threshold` directly on the ISM program.

### Updating ISM validators/threshold (advanced)

```bash
$CLIENT -k $KEY -u $RPC multisig-ism-message-id set-validators-and-threshold \
  --program-id LwNfVYMDzAe5dCJgA5CipTZcT34Eyf74zLr81K91jxk \
  --domain 1325 \
  --validators <VALIDATOR_PUBKEY_1>,<VALIDATOR_PUBKEY_2> \
  --threshold 1
```

Note: You must be the owner of the ISM program to call this.
