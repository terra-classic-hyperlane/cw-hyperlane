# Documentation Guide — Hyperlane Warp Routes Terra Classic

> Index document for all Warp Route scripts and guides for Terra Classic ↔ EVM and Terra Classic ↔ Sealevel (Solana).

**Last updated:** 2026-06-05 — Solana Devnet full Hyperlane infrastructure deployed; `close-warp-program.sh` script added; `create-warp-sealevel.sh` upgraded (pre-built binary reuse, spl-token image validation, metadata URL fixes).

---

## Table of Contents

1. [Quick Start](#1-quick-start)
2. [Architecture Overview](#2-architecture-overview)
3. [Gas Oracle — Custom Oracle Pattern](#3-gas-oracle--custom-oracle-pattern)
4. [Deployed Contracts Reference](#4-deployed-contracts-reference)
5. [Available Documents](#5-available-documents)
6. [Complete Workflow](#6-complete-workflow)
7. [File Structure](#7-file-structure)
8. [Troubleshooting Quick Reference](#8-troubleshooting-quick-reference)

---

## 1. Quick Start

### Required tools

| Tool | Min version | Install |
|---|---|---|
| `node` / `npm` | 18+ | [nodejs.org](https://nodejs.org) |
| `yarn` | 1+ | `npm install -g yarn` |
| `jq` | 1.6+ | `sudo apt install jq` |
| `python3` | 3.6+ | `sudo apt install python3` |
| `hyperlane CLI` | **26+** | `npm install -g @hyperlane-xyz/cli` |
| `forge` + `cast` | 1.x | `curl -L https://foundry.paradigm.xyz \| bash && foundryup` |

### Setup

```bash
cd cw-hyperlane
yarn install

export ETH_PRIVATE_KEY="0xYOUR_EVM_KEY"
export TERRA_PRIVATE_KEY="YOUR_TERRA_HEX_KEY"   # no 0x prefix

cd terraclassic
./create-warp-evm.sh
```

### Skip already-deployed steps

```bash
export WARP_ADDRESS="0x..."    # skip Warp deploy (Step 2)
export IGP_ADDRESS="0x..."     # skip IGP deploy (Step 3)
export ORACLE_ADDRESS="0x..."  # skip oracle deploy (Step 4)
export SKIP_ENROLL="1"         # skip enrollRemoteRouter (Step 7)
./create-warp-evm.sh
```

---

## 2. Architecture Overview

A Warp Route bridges tokens between Terra Classic and an EVM chain. Each direction requires its own set of contracts:

```
Terra Classic (columbus-5)                    BSC Mainnet (chain 56)
──────────────────────────                    ──────────────────────
hpl_warp_cw20 / hpl_warp_native               HypERC20 (synthetic)
  └─ locks/releases collateral                  └─ mints/burns synthetic

hpl_mailbox (dispatch/process)                Mailbox (dispatch/process)
  └─ domain 132556                               └─ domain 56

hpl_hook_aggregate                            AggregationHook
  ├─ hpl_hook_merkle                            ├─ MerkleTreeHook (validator signs)
  └─ hpl_igp (pay LUNC for EVM gas)            └─ TerraClassicIGP (pay BNB for TC gas)

hpl_ism_routing → hpl_ism_multisig_bsc        messageIdMultisigIsm
  └─ verifies BSC validator signatures           └─ verifies TC validator signatures
```

**Message flow (Terra Classic → BSC):**

```
1. User calls transfer_remote on Terra Classic Warp
2. Mailbox dispatches message + hooks execute (merkle + IGP payment)
3. Validator signs the Terra Classic checkpoint → stores on S3
4. Relayer reads signatures, calls Mailbox.process() on BSC
5. BSC ISM verifies validator signature → approves
6. BSC Warp mints synthetic ZTT to recipient
```

---

## 3. IGP Oracle — Gas Price Configuration

### Two-sided oracle architecture

There are **two separate oracle systems** in this project:

```
Terra Classic side (payment in LUNC):        EVM side (payment in BNB/ETH):
────────────────────────────────             ──────────────────────────────────
hpl_igp_oracle (CosmWasm)                    TerraClassicOracle.sol (Solidity)
  └─ owner: terra1run9...                      └─ owner: 0x8f085bAD...
  └─ set_remote_gas_data_configs               └─ setRemoteGasData()
  └─ domains: 1 (ETH), 56 (BSC), SOL           └─ domain: 132556 (Terra Classic)

Used when: sending TC → EVM/Solana            Used when: sending EVM → TC
User pays: LUNC for EVM gas                  User pays: BNB/ETH for TC gas
```

### TC IGP Oracle — `update-igp-oracle.sh`

Configures/updates the Terra Classic IGP oracle for each destination chain.

**Exchange rate formula (EVM chains):**
```
exchange_rate = (LUNC_USD / NATIVE_USD) × 1e12   (Solana uses 1e15)

Examples (2026-06-04):
  BSC mainnet:  (0.00006824 / 617.38) × 1e12 = 110,531    ✅ configured
  Ethereum:     (0.00006782 / 1803.18) × 1e12 = 37,611    ✅ configured (2026-06-04)
  Solana:       (0.00006782 / SOL_USD) × 1e15               ✅ see table below
```

> **Two oracle systems:** `exchange_rate` in the **TC oracle** = `LUNC_USD/NATIVE_USD × 1e12` (pay LUNC for EVM gas).  
> `exchange_rate` in the **EVM TerraClassicOracle.sol** = `NATIVE_USD/LUNC_USD` (e.g. 26,585,078 for ETH) — used to price TC gas in ETH/BNB when sending EVM→TC.

**Payment formula:**
```
fee_uluna = gas_amount × gas_price × exchange_rate / 1e12
```

**Usage:**
```bash
# Interactive (as owner)
export TERRA_PRIVATE_KEY="hex_key"
./update-igp-oracle.sh

# Configure all domains non-interactively
LUNC_USD=0.00006824 ETH_USD=3500 BNB_USD=617 SOL_USD=150 \
DOMAINS="1,56,1399811149" ./update-igp-oracle.sh

# Generate governance proposal (no key needed)
MODE=governance LUNC_USD=0.00006824 ETH_USD=3500 BNB_USD=617 SOL_USD=150 \
DOMAINS="1,56,1399811149" ./update-igp-oracle.sh
```

**Current oracle state (columbus-5) — 2026-06-04:**

| Domain | Chain | exchange_rate | gas_price | Fee ~300k gas | Status |
|---|---|---|---|---|---|
| **1** | **Ethereum** | **37,611** | **10 gwei** | **~113 LUNC** | **✅ 2026-06-04** |
| **56** | **BSC mainnet** | **110,531** | **3 gwei** | **~99 LUNC** | **✅ 2026-06-04** |
| **1399811149** | **Solana** | **38,300,155,301,425** | **1 lamport** | **~11 LUNC** | **✅ 2026-06-04** |

Prices used: LUNC=$0.00006782, ETH=$1803.18, BNB=$617.38, SOL=$70.83

---

## 3b. EVM IGP Oracle — Custom Oracle Pattern

### Why a custom oracle is needed

The official Hyperlane `StorageGasOracle` on each EVM chain is owned by Hyperlane and only has gas data for officially supported chains. Terra Classic (domain 132556) is **not** in Hyperlane's official supported list, so the official oracle returns `(0, 0)` for domain 132556 — meaning `quoteDispatch` returns zero, breaking gas payment.

### Solution: TerraClassicOracle.sol

`TerraClassicOracle.sol` is a minimal oracle contract you own and control:

```solidity
function getExchangeRateAndGasPrice(uint32) external view returns (uint128, uint128) {
    return (exchangeRate, gasPrice);
}

function setRemoteGasData(uint32, uint128 _exchangeRate, uint128 _gasPrice) external onlyOwner {
    exchangeRate = _exchangeRate;
    gasPrice = _gasPrice;
}
```

### Auto-deploy flow (Step 4 of create-warp-evm.sh)

The script handles this automatically:

```
Step 4: setRemoteGasData on official oracle
   ├─ Success → uses official oracle (done)
   └─ Fails (not owner) → deploys TerraClassicOracle
         ├─ forge compiles TerraClassicOracle.sol
         ├─ cast send --create deploys it
         ├─ calls setGasOracle(newOracle, overhead) on the custom IGP
         └─ saves oracle_custom address in warp-evm-config.json
```

### Updating gas rates

When BNB or LUNC price changes significantly, update the oracle:

```bash
# Calculate new exchange_rate = BNB_USD / LUNC_USD
# Example: BNB=$617 LUNC=$0.00006824 → exchange_rate = 617.38/0.00006824 = 9047190

cast send 0xYOUR_ORACLE_ADDRESS \
  "setRemoteGasData(uint32,uint128,uint128)" \
  132556 NEW_EXCHANGE_RATE NEW_GAS_PRICE \
  --rpc-url https://bsc.publicnode.com \
  --private-key $ETH_PRIVATE_KEY --legacy
```

Update `warp-evm-config.json` after:
```json
"igp": {
  "terra_classic_config": {
    "exchange_rate": 9047190,
    "gas_price_wei": 10000000000
  }
}
```

### Verifying gas pricing

```bash
RPC="https://bsc.publicnode.com"
ORACLE="0xYOUR_ORACLE"
IGP="0xYOUR_IGP"

# Verify oracle rates
cast call $ORACLE "exchangeRate()(uint128)" --rpc-url $RPC
cast call $ORACLE "gasPrice()(uint128)" --rpc-url $RPC

# Verify IGP points to correct oracle
cast call $IGP "gasOracle()(address)" --rpc-url $RPC

# Simulate gas cost for a transfer
cast call $IGP "quoteDispatch(bytes,bytes)(uint256)" \
  "0x$(python3 -c "print('0001' + '00'*32 + format(250000,'064x') + '00'*20)")" \
  "0x$(python3 -c "print('00'*41 + format(1325,'08x') + '00'*100)")" \
  --rpc-url $RPC
```

---

## 4. Deployed Contracts Reference

### Terra Classic Mainnet — columbus-5 (domain 132556)

Deployed 2026-06-09 via `CustomInstantiateWasm-mainnet-v2.ts` (v2 — domain 132556 replaces 1325).

| Contract | Address |
|---|---|
| **Mailbox** | `terra1fwg35n5esjgny7d8pxnz8usjpwsvpguk0txsy6cnqxy58x9fdlksjpx3p9` |
| **Validator Announce** | `terra1gtnmdevekgxpvzej3wfy20e2n335gm3muwj6geduxxa86j3x70cq00asmy` |
| **ISM Routing** | `terra1uhzzvt9x3u8hjnkp695hklexx2uywjvfqv454d93ds92sgtpwk7qrpxdg0` |
| ISM Multisig ETH | `terra187rzjc3dznfxqtqqrwh796e5q4khmvp5av8mka6zhp98zjfk2z2qneldar` |
| ISM Multisig BSC | `terra1nqj7qlnt2sty0dgnu3ss5z4u6wr7hjfea7cn6wpwjt2uymts8ucsmuj9xw` |
| ISM Multisig SOL | `terra10s3p36tjek8amhlc4krxpzln6g8n0qy9jq82wyda434l3rv89wfsucl50t` |
| **Hook Merkle** | `terra183lq6yqp8km3p34cxgk6k3u78uy4plqahey6rne7n9gy98delr9qyp0n2p` |
| **IGP** | `terra1taunhg629rssf3g939nqr0h594q5mssrzdj5lkx2hygmxmh72ghqeqqnvz` |
| IGP Oracle | `terra1j8xzgzk7vds5uzrplmnln4vcz6f205t9atdyflypzrr43cd5eh7scwqj0d` |
| Hook Agg Default | `terra1026v947k2jn58t09ppw003xujj92vp3lxv0fg3xk8ccz42r8d2sqvnmvel` |
| Hook Pausable | `terra1x8s9qtw9355pfckywkns4e8f9zyfjaf8w5e5s8vh28ph5gzwwlks9tjcnf` |
| Hook Fee | `terra1sud5xyknr93wmxem6kxdfd0vxcju47wuh7zdm5uecavrm36w669sp7j8ag` |

**Warp contracts (columbus-5):**

| Token | Warp Address | Hex bytes32 |
|---|---|---|
| **ZTT** | `terra13uhhpfzfxx0t0w2adxm75vkufe4f4m8stmv23nc806gahw6jd3psadyjl2` | `0x8f2f70a449319eb7b95d69b7ea32dc4e6a9aecf05ed8a8cf077e91dbbb526c43` |
| **LUNC** (native `uluna`) | `terra1m7jcqxfn4hd7q4sywhw508nxshaf078c4vh83y0ts43y9tlp9dcs50cggy` | `0xdfa5801933addbe0560475dd479e6685fa97f8f8ab2e7891eb856242afe12b71` |
| **USTC** (native `uusd`) | `terra1qu3x6vhk4y6w6erhmedzfp2ug53qm5nwpyarxveqa7tvwg0telxqvd3ccf` | `0x07226d32f6a934ed6477de5a24855c45220dd26e093a333320ef96c721ebcfcc` |

---

### BSC Mainnet — chain 56 (domain 56)

**Hyperlane core contracts (official):**

| Contract | Address |
|---|---|
| Mailbox | `0x2971b9Aec44bE4eb673DF1B88cDB57b96eefe8a4` |
| MerkleTreeHook | `0xFDb9Cd5f9daAA2E4474019405A328a88E7484f26` |
| AggregationHookFactory | `0xe70E86a7D1e001D419D71F960Cb6CaD59b6A3dB6` |
| StorageGasOracle (official) | `0x91d23D603d60445411C06e6443d81395593B7940` |
| InterchainGasPaymaster (official) | `0x78E25e7f84416e69b9339B0A6336EB6EFfF6b451` |
| ISM MultisigFactory | `0xEb9FcFDC9EfDC17c1EC5E1dc085B98485da213D6` |

**Deployed Warp Routes:**

| Token | Warp Route | Custom IGP | Custom Oracle | AggHook | ISM |
|---|---|---|---|---|---|
| **ZTT** | [`0x6AB3EaF4dC64496BB435D221563C5e3e1132A592`](https://bscscan.com/address/0x6AB3EaF4dC64496BB435D221563C5e3e1132A592) | [`0x5Ea49420DFCa83ca8E7eddA9160A3009F6aE6a7B`](https://bscscan.com/address/0x5Ea49420DFCa83ca8E7eddA9160A3009F6aE6a7B) | [`0x38fC50ecC1D21e45705be7441cc1Ff9bcDDec488`](https://bscscan.com/address/0x38fC50ecC1D21e45705be7441cc1Ff9bcDDec488) | [`0x0Eb97DFC380fD71F62C9d42498CC0C1135A910b7`](https://bscscan.com/address/0x0Eb97DFC380fD71F62C9d42498CC0C1135A910b7) | [`0xa82087B8eea0394B1476f716B91c10531025Ef42`](https://bscscan.com/address/0xa82087B8eea0394B1476f716B91c10531025Ef42) |

**ZTT exchange_rate**: `9047190` (BNB $617.38 / LUNC $0.00006824 — 2026-06-04)

---

### Ethereum Mainnet — chain 1 (domain 1)

**Hyperlane core contracts (official):**

| Contract | Address |
|---|---|
| Mailbox | `0xc005dc82818d67AF737725bD4bf75435d065D239` |
| MerkleTreeHook | `0x48e6c30B97748d1e2e03bf3e9FbE3890ca5f8CCA` |
| AggregationHookFactory | `0x6D2555A8ba483CcF4409C39013F5e9a3285D3C9E` |
| StorageGasOracle (official) | `0xc9a103990A8dB11b4f627bc5CD1D0c2685484Ec5` |
| InterchainGasPaymaster (official) | `0x9e6B1022bE9BBF5aFd152483DAD9b88911bC8611` |
| ISM MultisigFactory | `0xfA21D9628ADce86531854C2B7ef00F07394B0B69` |

**Deployed Warp Routes (production, 2026-08-29):**

| Token | Warp Route (BSC) | IGP (prod) | AggHook (prod) |
|---|---|---|---|
| **LUNC** | [`0x481095ecEd7A907e7f390b6226F53a66D379e6e2`](https://bscscan.com/address/0x481095ecEd7A907e7f390b6226F53a66D379e6e2) | `0xEdEd7a4f6FEe4B474B9d7730Bf3465E35E2a4923` | `0xD2c82583C261fce94cD3F97f1dFF9B20a9338164` |
| **USTC** | [`0xfC067fd98FD123fC2cAd72d040AF60a523274339`](https://bscscan.com/address/0xfC067fd98FD123fC2cAd72d040AF60a523274339) | `0xEdEd7a4f6FEe4B474B9d7730Bf3465E35E2a4923` | `0xD2c82583C261fce94cD3F97f1dFF9B20a9338164` |

Ethereum synthetics: LUNC `0xA4bc47a4C5461eB0E59A585a21A1222EF7544Ac6`, USTC
`0xf49408beb319aeCe3E8B3550a5C750C19b3F1e51` (IGP `0x9650F1f8DB492750323172145e67Df4e89E964Aa`,
hook `0x912c4d91D9eD04B16B83dA79dbe7a209c8Fd0aA8`). Full record: `install/DEPLOY-HASHES.md` §5/§6.

> **RPC note:** `rpc.ankr.com/eth` and `1rpc.io/eth` can rate-limit during deploys. Use `ethereum-rpc.publicnode.com` for Step 8 verification.

---

### Solana Devnet (domain 1399811151)

Deployed 2026-06-05. Full Hyperlane core infrastructure deployed from source.

**Core contracts:**

| Contract | Program ID |
|---|---|
| **Mailbox** | `21i5MDw3PPVbkS9X1L1Jw78gyrZB7zYB8yTzzfopp1Rc` |
| **MultisigISM MessageID** | `GBzvJRqNrTwEEMpaCppvKc9ZWAPp63rPmjLKCfvqSZyQ` |
| **IGP Program** | `3jwBeFqf2NSj3gSRLNDx4HP2E1t3zrNoERd6MnzRXx7n` |
| **IGP Account** | `9TmpKr5LiHpuG9K12bH4VDgLfJM2YeFxhSb2AVhQf9Qw` |
| **IGP Overhead Account** | `DZviyMfWebpQep9fyiPNeH2tgwYNmBsdArNbodj9FzMq` |
| **Validator Announce** | `FM1hB4GMPHCBP9xMy44hwZAXw3x97fVUrsnognBVEGYf` |

**Warp Routes:**

| Token | Program ID | Mint (Token-2022) |
|---|---|---|
| **USTC** | *(reset for testing)* | *(reset for testing)* |

> Deploys via `./create-warp-sealevel.sh` → rede **[1] solanadevnet**.
> See `log/DEVNET-HYPERLANE-ADDRESSES.txt` for full details.

---

### Solana Testnet (domain 1399811150)

**Warp Routes:**

| Token | Program ID | Mint |
|---|---|---|
| **wLUNC** | `5BuTS1oZhUKJgpgwXJyz5VRdTq99SMvHm7hrPMctJk6x` | — |
| **JURIS** | `G3eEYHv2GrBJ6KTS3XQhRd7QYdwnfWjisQrSVWedQK4y` | `ExzEij8z7xc71kvjuMHmejRkmM4ACgKjDWuEaXdDubRa` |
| **USTC** | `BWJm6tjxEY1uzyFvNZsy211mooeVZdph3SMoz4HPKV4B` | `5ZTL6NPun4dmgwXex84MnAucdCtfAoz2s2Te8XsA5FPr` |

> ISM: `5FgXjCJ8hw1hDbYhvwMB7PFN6oBhVcHuLo3ABoYynMZh`  
> IGP: `5p7Hii6CJL4xGBYYTGEQmH9LnUSZteFJUu9AVLDExZX2` / Account: `E9i32KsKGQZMYTguZ81VHUueNvpTGh7nb9J5bRif4xT1`

---

### BSC Testnet — chain 97 (domain 97)

| Contract | Address |
|---|---|
| Mailbox | `0xF9F6F5646F478d5ab4e20B0F910C92F1CCC9Cc6D` |
| MerkleTreeHook | `0xc6cbF39A747f5E28d1bDc8D9dfDAb2960Abd5A8f` |
| AggregationHookFactory | `0xa1145B39F1c7Ef9aA593BC1DB1634b00CC020942` |
| StorageGasOracle | `0x124EBCBC018A5D4Efe639f02ED86f95cdC3f6498` |

*(nenhuma rota ativa — tokens de teste descontinuados em 29/08/2026)*

---

### Sepolia Testnet — chain 11155111 (domain 11155111)

| Contract | Address |
|---|---|
| Mailbox | `0xfFAEF09B3cd11D9b20d1a19bECca54EEC2884766` |
| MerkleTreeHook | `0x4917a9746A7B6E0A57159cCb7F5a6744247f2d0d` |
| AggregationHookFactory | `0x160C28C92cA453570aD7C031972b58d5Dd128F72` |
| StorageGasOracle | `0x7113Df4d1D8B230e6339011d10277a6E5AC4eC9c` |

*(nenhuma rota ativa — tokens de teste descontinuados em 29/08/2026)*

---

## 5. Available Documents and Scripts

### Scripts

| Script | Purpose |
|---|---|
| `create-warp-evm.sh` | Deploy Warp Route on EVM network (Sepolia, BSC, etc.) — auto-deploys EVM oracle if needed |
| `create-warp-sealevel.sh` | **Deploy Warp Route on Solana** (testnet, devnet, mainnet) — interactive menu |
| `close-warp-program.sh` | **Close a Solana Warp program, recover SOL, reset config** — use before re-deploying |
| `update-igp-oracle.sh` | Update TC IGP Oracle for ETH/BSC/Solana — direct or governance mode |
| `transfer-remote-terra.sh` | Send tokens Terra Classic → EVM/Solana |
| `transfer-remote-to-terra.sh` | Send tokens EVM/Solana → Terra Classic |
| `enroll-terra-router.sh` | Register EVM route in Terra Classic Warp |
| `deploy-warp-solana-buffer.sh` | Deploy Solana program binary via buffer (manual alternative) |
| `CustomInstantiateWasm-mainnet.ts` | **Full mainnet install** — 13 contracts + mailbox config + IGP oracle (Steps 1–15) |
| `submit-proposal-mainnet.ts` | **Governance proposal** — ISM validators + all mailbox/oracle configs |

### Documentation

| Document | Purpose |
|---|---|
| [`create-warp-evm-guide.md`](./create-warp-evm-guide.md) | Complete EVM deploy guide — oracle auto-deploy, all 8 steps |
| [`HYPERLANE_DEPLOYMENT-MAINNET_EN.md`](./HYPERLANE_DEPLOYMENT-MAINNET_EN.md) | Core contracts on Terra Classic mainnet, **oracle update guide (Section 6)** |
| [`transfer-remote-guide.md`](./transfer-remote-guide.md) | Send tokens Terra Classic → EVM/Solana |
| [`transfer-remote-to-terra-guide.md`](./transfer-remote-to-terra-guide.md) | Send tokens EVM/Solana → Terra Classic |
| [`enroll-terra-router-guide.md`](./enroll-terra-router-guide.md) | Register EVM route in Terra Classic Warp |
| [`create-warp-sealevel-guide.md`](./create-warp-sealevel-guide.md) | Complete Solana deploy guide |
| [`HYPERLANE_DEPLOYMENT-TESTNET_EN.md`](./HYPERLANE_DEPLOYMENT-TESTNET_EN.md) | Core contracts on Terra Classic testnet |
| [`submit-proposal-guide.md`](./submit-proposal-guide.md) | Governance proposals on Terra Classic |
| [`UPDATE-IGP-ORACLE-GOVERNANCE.md`](./UPDATE-IGP-ORACLE-GOVERNANCE.md) | Oracle update via governance (legacy manual guide) |
| [`SAFE-SCRIPTS-GUIDE.md`](./SAFE-SCRIPTS-GUIDE.md) | Using Safe multisig for production operations |

---

## 6. Complete Workflow

### New token on BSC Mainnet

```bash
# 1. Add token to warp-evm-config.json:
#    terra_classic.tokens.MYTOKEN → collateral_address, type, owner
#    networks.bsc.warp_tokens.MYTOKEN → deployed: false

# 2. Run script
export ETH_PRIVATE_KEY="0xEVM_KEY"
export TERRA_PRIVATE_KEY="TERRA_HEX_KEY"
./create-warp-evm.sh
# → Select token: MYTOKEN
# → Select network: bsc (BSC Mainnet)

# Script auto-executes:
# Step 1: generates warp/warp-bsc-MYTOKEN.yaml
# Step 2: hyperlane warp deploy → creates synthetic ERC20
# Step 3: deploys TerraClassicIGPStandalone (hookType=4)
# Step 4: tries setRemoteGasData on official oracle
#         └─ fails (not owner) → deploys TerraClassicOracle
#            └─ calls setGasOracle on IGP → points to custom oracle
# Step 5: deploys AggregationHook[MerkleTree+IGP] → sets as Warp hook
# Step 6: sets custom ISM on Warp (if deployed_address configured)
# Step 7: enrollRemoteRouter on EVM (registers TC warp as authorized)
# Step 7B: set_route on TC (registers BSC warp as authorized)
# Step 8: final on-chain verification
```

### Adding a new EVM network

```json
// warp-evm-config.json → networks section
"mynewchain": {
  "enabled": true,
  "display_name": "My New Chain",
  "chain_id": 12345,
  "domain": 12345,
  "is_testnet": false,
  "native_token": { "symbol": "ETH", "decimals": 18 },
  "rpc_urls": ["https://rpc.mynewchain.com"],
  "explorer": "https://explorer.mynewchain.com",
  "mailbox": { "address": "0x..." },
  "ism": {
    "type": "messageIdMultisigIsm",
    "factory": "0x...",
    "deployed_address": "",
    "validators": ["0xYOUR_TC_VALIDATOR_SIGNING_KEY"],
    "threshold": 1
  },
  "hook": {
    "merkle_tree": "0x...",
    "agg_hook_factory": "0x..."
  },
  "igp": {
    "official_address": "0x...",
    "gas_oracle": "0x...",
    "overhead_default": 200000,
    "terra_classic_config": {
      "exchange_rate": 0,
      "gas_price_wei": 0
    }
  },
  "warp_tokens": {}
}
```

> Get official addresses: `cat node_modules/@hyperlane-xyz/sdk/dist/consts/environments/mainnet.json | python3 -c "import json,sys; d=json.load(sys.stdin); print(json.dumps(d.get('mynewchain',{}), indent=2))"`

### ISM validator — which address to use

The `validators` array in the ISM config contains the **EVM signing key** of the validator that watches the **Terra Classic Mailbox**. This is NOT a validator of the EVM chain — it is the Hyperlane validator agent that monitors Terra Classic and signs checkpoints.

The same Terra Classic validator key can serve multiple destination chains simultaneously. It just needs to be listed in each chain's ISM config.

```
Your validator agent:
  - Watches: Terra Classic Mailbox (columbus-5)
  - Signing key: 0xYOUR_VALIDATOR_KEY
  - Announces on: each EVM chain's ValidatorAnnounce contract
  - Stores checkpoints: S3 bucket (read by relayer)

BSC ISM:  validators: ["0xYOUR_VALIDATOR_KEY"]  ← same key
Sepolia ISM: validators: ["0xYOUR_VALIDATOR_KEY"]  ← same key
```

---

## 7. File Structure

```
terraclassic/
├── doc/                                    ← documentation
│   ├── README.md                           ← this document
│   ├── create-warp-evm-guide.md            ← full EVM deploy guide
│   ├── create-warp-sealevel-guide.md       ← full Solana deploy guide
│   ├── transfer-remote-guide.md
│   ├── transfer-remote-to-terra-guide.md
│   └── enroll-terra-router-guide.md
│
├── create-warp-evm.sh                      ← EVM deploy (BSC, ETH, Sepolia)
├── create-warp-sealevel.sh                 ← Solana deploy (devnet/testnet/mainnet)
├── close-warp-program.sh                   ← close program + recover SOL + reset config
├── deploy-warp-solana-buffer.sh            ← manual Solana buffer deploy
├── enroll-terra-router.sh                  ← register route on Terra Classic
├── transfer-remote-terra.sh                ← send TC → EVM/Solana
├── transfer-remote-to-terra.sh             ← send EVM/Solana → TC
├── update-igp-oracle.sh                    ← update TC IGP oracle rates
│
├── warp-evm-config.json                    ← EVM networks + tokens config
├── warp-sealevel-config.json               ← Solana networks + tokens config
├── TerraClassicIGPStandalone-Sepolia.sol   ← custom IGP (hookType=4)
├── TerraClassicOracle.sol                  ← custom gas oracle (auto-deployed)
│
├── warp/
│   ├── solana/
│   │   ├── metadata-lunc.json              ← Token-2022 metadata files
│   │   ├── metadata-ustc.json
│   │   └── metadata-*.json
│   ├── warp-bsc-ztt.yaml                   ← generated per EVM deploy
│   └── terraclassic-cw20-ztt.json          ← generated for TC deploy
│
└── log/
    ├── create-warp-evm.log
    ├── create-warp-sealevel.log
    ├── DEVNET-HYPERLANE-ADDRESSES.txt      ← Solana devnet core contracts
    ├── WARP-SOLANADEVNET-*.txt             ← devnet warp deploy reports
    ├── WARP-SOLANATESTNET-*.txt            ← testnet warp deploy reports
    └── WARP-BSC-*.txt / WARP-ETHEREUM-*.txt
```

**Files managed automatically (do not edit manually):**
- `warp/*.yaml` — generated by the script for each `hyperlane warp deploy`
- `warp/terraclassic-*.json` — generated for `yarn cw-hpl warp create`
- `.warp-evm-state.json` — resume state (delete to restart from scratch)
- `log/` — execution logs and reports

---

## 8. Post-Install Checklist (new mainnet deployment)

After running `CustomInstantiateWasm-mainnet.ts`, verify these items before first transfer:

```bash
node -e "
const p=require('path'),nm=p.join('/home/lunc/tc-cw-hyperlane','node_modules');
const {CosmWasmClient}=require(p.join(nm,'@cosmjs/cosmwasm-stargate'));
(async()=>{
  const c=await CosmWasmClient.connect('https://rpc.terra-classic.hexxagon.io');
  const mb='terra1fwg35n5esjgny7d8pxnz8usjpwsvpguk0txsy6cnqxy58x9fdlksjpx3p9';
  const oracle='terra1j8xzgzk7vds5uzrplmnln4vcz6f205t9atdyflypzrr43cd5eh7scwqj0d';
  // Mailbox
  const ism=await c.queryContractSmart(mb,{mailbox:{default_ism:{}}});
  const hook=await c.queryContractSmart(mb,{mailbox:{default_hook:{}}});
  const req=await c.queryContractSmart(mb,{mailbox:{required_hook:{}}});
  console.log(ism.default_ism ? '✅ default_ism set' : '❌ default_ism NOT SET — cannot receive msgs');
  console.log(hook.default_hook ? '✅ default_hook set' : '❌ default_hook NOT SET — transfer_remote FAILS');
  console.log(req.required_hook ? '✅ required_hook set' : '❌ required_hook NOT SET');
  // Oracle
  for (const d of [1,56,1399811149]) {
    try { const r=await c.queryContractSmart(oracle,{oracle:{get_exchange_rate_and_gas_price:{dest_domain:d}}});
          console.log('✅ IGP oracle domain '+d+': rate='+r.exchange_rate); }
    catch(e) { console.log('❌ IGP oracle domain '+d+': NOT CONFIGURED'); }
  }
})();" 2>/dev/null
```

| Item | Status (2026-06-04) | Fix if missing |
|---|---|---|
| ISM validators ETH/BSC/SOL | ✅ configured (Step 14) | `CustomInstantiateWasm` Step 14 or `submit-proposal-mainnet.ts` Messages 1–3 |
| Mailbox `default_hook` | ✅ configured (Step 15) | Step 15 or Message 7 — **critical: without this transfer_remote fails** |
| Mailbox `required_hook` | ✅ configured (Step 15) | Step 15 or Message 8 — adds 283215 uluna fee per msg |
| IGP oracle domains 1/56/1399811149 | ✅ configured (Step 16) | `update-igp-oracle.sh` or Message 4 |

> **Root cause of BSC→TC stuck messages (2026-06-04):** ISM validators were not set after instantiation.
> Validators are now part of Step 14 in `CustomInstantiateWasm-mainnet.ts`.

---

## 9. Troubleshooting Quick Reference

| Error | Cause | Fix |
|---|---|---|
| `mailbox contract not yet deployed` | `context/terraclassic.json` has empty `deployments` | Fill `deployments.core.mailbox` with the deployed Mailbox address |
| `setRemoteGasData failed (not owner)` | Official EVM oracle is owned by Hyperlane | Script auto-deploys `TerraClassicOracle.sol` and updates IGP — check Step 4 output |
| `destination not supported` (EVM→TC) | EVM IGP oracle returned (0,0) for domain 132556 | Run Step 4 again with `ORACLE_ADDRESS` env; or redeploy with `export ORACLE_ADDRESS=0x...` |
| TC IGP fee query returns 0 or fails | TC IGP oracle not configured for destination domain | Run `./update-igp-oracle.sh` to configure the domain |
| `fee is too low` / transfer stuck | TC IGP oracle exchange_rate is stale (prices changed) | Run `./update-igp-oracle.sh` to recalculate with current prices |
| `route not found` | Terra Classic Warp has no route for the EVM domain | Run `./enroll-terra-router.sh` |
| `insufficient funds` | Not enough native token (BNB/ETH/SOL) | Top up wallet; check `cast balance WALLET --rpc-url RPC --ether` |
| `invalid_enum_value` (hyperlane CLI) | CLI version below 26 | `npm install -g @hyperlane-xyz/cli@latest` |
| Wrong network selected (EVM script) | Menu order is **alphabetical** — not JSON order | `bsc=[1], bsctestnet=[2], sepolia=[3]` |
| TC deploy reads wrong network | `config.yaml` and `warp-evm-config.json` mismatch | `config.yaml` must point to the same chain as `terra_classic.chain_id` |
| Validator not signing messages | Hook does not include MerkleTreeHook | Re-run script — Step 5 deploys `AggregationHook=[MerkleTree+IGP]` automatically |
| **Solana: mint NOT FOUND after deploy** | `dan/create-token-for-mint` fork bug on mainnet | Run `./close-warp-program.sh` to recover SOL and redeploy — devnet/testnet use `create-token` (correct) |
| **Solana: `Max retries exceeded`** | RPC throttling + CLI gives up re-signing each write tx after 5 attempts (default `--max-sign-attempts`) — raising the priority fee does NOT fix it | Use a private RPC **and** `--max-sign-attempts 200` (built into `create-warp-sealevel.sh` since 2026-08-29); public RPCs that 403 `sendTransaction` (e.g. publicnode) must not be in `rpc_fallbacks` |
| **Solana: `Image URL` panic** | metadata `image` URL returns 404 | Script validates image HTTP status; URI auto-omitted if invalid |
| **Solana: `Chain config not found`** | Network key in `warp-sealevel-config.json` not in registry | Must match registry name: `solanamainnet`, `solanatestnet`, `solanadevnet` |
| **Solana: `429 Too Many Requests`** | Public testnet RPC rate limit | Wait 1–2 min and retry; script handles gracefully |
| **Solana: `run_sealevel: No such file`** | `timeout` called on shell function | Fixed in current script — use latest version |
| **Solana: program builds take 10+ min** | First-time `cargo build` compilation | Script detects pre-built binary and calls it directly (fast on subsequent runs) |

### Checking oracle state (quick reference)

```bash
# TC IGP Oracle — check all domains
node -e "
const p=require('path'),nm=p.join('/home/lunc/tc-cw-hyperlane','node_modules');
const {CosmWasmClient}=require(p.join(nm,'@cosmjs/cosmwasm-stargate'));
(async()=>{
  const c=await CosmWasmClient.connect('https://rpc.terra-classic.hexxagon.io');
  const oracle='terra1j8xzgzk7vds5uzrplmnln4vcz6f205t9atdyflypzrr43cd5eh7scwqj0d';
  for(const d of [1,56,1399811149]){
    try{const r=await c.queryContractSmart(oracle,{oracle:{get_exchange_rate_and_gas_price:{dest_domain:d}}});
        console.log('domain '+d+':',r);}
    catch(e){console.log('domain '+d+': NOT CONFIGURED');}
  }
})();" 2>/dev/null

# EVM IGP Oracle (BSC mainnet) — check rates
cast call 0x38fC50ecC1D21e45705be7441cc1Ff9bcDDec488 \
  "exchangeRate()(uint128)" --rpc-url https://bsc.publicnode.com

# Update TC oracle for ETH and Solana
export TERRA_PRIVATE_KEY="your_key"
LUNC_USD=0.00006824 ETH_USD=3500 SOL_USD=150 DOMAINS="1,1399811149" \
./update-igp-oracle.sh
```

### Check oracle is working

```bash
RPC="https://bsc.publicnode.com"
ORACLE="0xYOUR_ORACLE"
IGP="0xYOUR_IGP"

# 1. Oracle returns correct rates
cast call $ORACLE "getExchangeRateAndGasPrice(uint32)(uint128,uint128)" 132556 --rpc-url $RPC
# Expected: (9047190, 10000000000) or your configured values — NOT (0, 0)

# 2. IGP points to your oracle
cast call $IGP "gasOracle()(address)" --rpc-url $RPC
# Expected: your oracle address

# 3. Warp hook is AggregationHook (not IGP directly)
WARP="0xYOUR_WARP"
cast call $WARP "hook()(address)" --rpc-url $RPC
# Expected: AggregationHook address (NOT the IGP address directly)

# 4. IGP hookType
cast call $IGP "hookType()(uint8)" --rpc-url $RPC
# Expected: 4
```

### Manually update oracle rates

```bash
cast send $ORACLE \
  "setRemoteGasData(uint32,uint128,uint128)" \
  132556 NEW_EXCHANGE_RATE NEW_GAS_PRICE \
  --rpc-url https://bsc.publicnode.com \
  --private-key $ETH_PRIVATE_KEY --legacy
```

### Re-run only gas oracle step (oracle already deployed)

```bash
export ETH_PRIVATE_KEY="0xYOUR_KEY"
export WARP_ADDRESS="0xWARP"
export IGP_ADDRESS="0xIGP"
export ORACLE_ADDRESS="0xORACLE"   # skips oracle deploy, updates rates only
./create-warp-evm.sh
# → select token and network → script skips Warp+IGP+Oracle deploy
```

---

---

## 10. Solana Quick Reference

### Deploy a new Warp Route (Solana)

```bash
cd ~/tc-cw-hyperlane/terraclassic
./create-warp-sealevel.sh
# → Select token and network interactively
```

### Close a program and recover SOL

```bash
./close-warp-program.sh
# → Lists all deployed programs, select one to close
# → Closes program + buffers, resets config, removes keypairs
```

### Deploy Hyperlane core contracts on devnet (one-time setup)

```bash
# Build programs (run once)
cd ~/hyperlane-monorepo/rust/sealevel/programs
bash build-programs.sh core

# Deploy core contracts
SEALEVEL_BIN=~/hyperlane-monorepo/rust/sealevel/target/release/hyperlane-sealevel-client
$SEALEVEL_BIN -k <KEYPAIR> -u https://api.devnet.solana.com \
  core deploy \
  --local-domain 1399811151 \
  --environment devnet \
  --environments-dir ~/hyperlane-monorepo/rust/sealevel/environments \
  --chain solanadevnet \
  --built-so-dir ~/hyperlane-monorepo/rust/sealevel/target/deploy \
  --gas-oracle-config-file ~/hyperlane-monorepo/rust/sealevel/environments/devnet/gas-oracle-configs.json
```

### Network menu order (create-warp-sealevel.sh)

Networks are listed **alphabetically** by key:

| # | Key | Network |
|---|---|---|
| 1 | `solanadevnet` | Solana Devnet |
| 2 | `solanamainnet` | Solana Mainnet |
| 3 | `solanatestnet` | Solana Testnet |

### Monorepo (never modify source)

```
/home/lunc/hyperlane-monorepo/   ← NEVER modify source files
  rust/sealevel/
    target/
      deploy/       ← compiled .so programs
      release/      ← hyperlane-sealevel-client binary
    environments/
      devnet/       ← devnet env (created by deploy)
      testnet4/     ← testnet reference configs
      mainnet3/     ← mainnet reference configs
```

---

**Explorer links:**
- BSC Mainnet: https://bscscan.com
- BSC Testnet: https://testnet.bscscan.com
- Sepolia: https://sepolia.etherscan.io
- Solana Devnet: https://explorer.solana.com/?cluster=devnet
- Solana Testnet: https://explorer.solana.com/?cluster=testnet
- Solana Mainnet: https://explorer.solana.com
- Terra Classic (hexxagon): https://finder.hexxagon.io/columbus-5
- Hyperlane Explorer: https://explorer.hyperlane.xyz
