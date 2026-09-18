# 📘 Complete Guide: Hyperlane Deployment and Configuration on Terra Classic Mainnet

This guide documents the complete process of deploying and configuring Hyperlane contracts on Terra Classic Mainnet (columbus-5).

> ✅ **Audit status — re-verified on-chain 2026-08-31** (sampled: 8 of the 20
> upload hashes — codes 11371, 11374, 11376, 11378, 11380, 11388, 11389, 11390 —
> match the chain's `data_hash` byte for byte; all 20 matched in the full
> 2026-08-28 audit); the mailbox
> wiring (§7: `default_ism` = ISM Routing, `default_hook`/`required_hook` = the two
> Aggregation hooks) and the inbound ISM validator sets (§6: ETH **6-of-9** ·
> BSC **4-of-6** · Solana **3-of-5**) are all live and unchanged since
> instantiation; LUNC/USTC warp instances confirmed on-chain (code 11390,
> `hpl_warp_native`). Deployed **after** this record: cw20 code **11392** (test
> token, discontinued 2026-08-29) and the LUNC/USTC warp instances — the always-current full inventory
> (including the synthetics' warp/ISM/IGP hashes on BSC/ETH/Solana) lives in
> [`install/DEPLOY-HASHES.md`](install/DEPLOY-HASHES.md).

---

## 📋 Table of Contents

1. [Prerequisites](#prerequisites)
   - [Generating a Private Key in Hex Format](#generating-a-private-key-in-hex-format)
2. [Verify Available Contracts](#verify-available-contracts)
3. [Contract Deployment (Upload)](#contract-deployment-upload)
4. [Contract Instantiation](#contract-instantiation)
5. [Configuration via Governance](#configuration-via-governance)
6. [IGP Oracle — Updating Gas Prices](#igp-oracle--updating-gas-prices)
7. [Execution Verification](#execution-verification)
8. [Contract Addresses and Hexed](#contract-addresses-and-hexed)
9. [Warp Routes — LUNC and USTC on the 4 chains](#-warp-routes--lunc-and-ustc-on-the-4-chains)
10. [Current fees](#-current-fees-2026-09-18)
11. [Ownership & admin summary](#-ownership--admin-summary-terra-classic-core-2026-09-18)
12. [Troubleshooting](#troubleshooting)

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
yarn cw-hpl upload remote v0.0.7-rc0 -n terraclassic
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
wget https://github.com/many-things/cw-hyperlane/releases/download/v0.0.7-rc0/cw-hyperlane-v0.0.7-rc0.zip
unzip cw-hyperlane-v0.0.7-rc0.zip
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

### Script: `CustomInstantiateWasm-mainnet-v2.ts`

> **v2 — 2026-06-09:** Re-deployed with **domainId 132556** (replaces 1325 which conflicted with testnet).
> Original deploy (2026-06-03, domain 1325) is preserved in `archive/scripts/CustomInstantiateWasm-mainnet.ts` for reference.

This script instantiates **all 13 contracts** AND performs the post-instantiation configuration (ISM validators + mailbox hooks + IGP oracle) in a single run.

**File location:** `terraclassic/CustomInstantiateWasm-mainnet-v2.ts`

> **Important:** Always run from the **project root** (`/home/lunc/tc-cw-hyperlane`).

#### Execute

```bash
cd /home/lunc/tc-cw-hyperlane
PRIVATE_KEY="0xYOUR_HEX_KEY" yarn tsx terraclassic/CustomInstantiateWasm-mainnet-v2.ts
```

#### What the script does (17 steps)

| Step | Action | Why critical |
|---|---|---|
| 1–13 | Instantiate all Hyperlane contracts (Mailbox, ISMs, IGP, Hooks) | Creates contracts |
| **14** | **Set ISM validators** — official Hyperlane validators for ETH/BSC/SOL | **Without this, inbound messages (EVM → TC) cannot be validated — messages get stuck** |
| **15** | **Configure Mailbox** — `set_default_ism`, `set_default_hook`, `set_required_hook` | **Without this, `transfer_remote` fails with `default_hook not set`** |
| 16 | Configure IGP Oracle — gas rates for domains 1/56/1399811149 | Users pay correct LUNC fee |

> All 17 steps run automatically in a single execution. The system is fully ready afterwards.

#### Environment Variables

| Variable | Required | Description |
|---|---|---|
| `PRIVATE_KEY` | ✅ | Deployer private key hex (`0x...` or no prefix) |

### 📋 Instantiated Contracts

The script instantiates **13 contracts** supporting **3 chains** (Ethereum, BSC, Solana):

---

#### 1. 📮 MAILBOX - Main Cross-Chain Messaging Contract

```json
{
  "hrp": "terra",
  "domain": 132556,
  "owner": "terra1run9wz09uhh6pu7ggcwwetrgye4wu7wn26mawp"
}
```

**Code ID:** `11371`
**Instantiated Address:** `terra1fwg35n5esjgny7d8pxnz8usjpwsvpguk0txsy6cnqxy58x9fdlksjpx3p9`

---

#### 2. 📢 VALIDATOR ANNOUNCE - Validator Registry

```json
{
  "hrp": "terra",
  "mailbox": "terra1fwg35n5esjgny7d8pxnz8usjpwsvpguk0txsy6cnqxy58x9fdlksjpx3p9"
}
```

**Code ID:** `11372`
**Instantiated Address:** `terra1gtnmdevekgxpvzej3wfy20e2n335gm3muwj6geduxxa86j3x70cq00asmy`

---

#### 3. 🔐 ISM MULTISIG #1 - For Ethereum (Domain 1)

```json
{ "owner": "terra1run9wz09uhh6pu7ggcwwetrgye4wu7wn26mawp" }
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

**Instantiated Address:** `terra187rzjc3dznfxqtqqrwh796e5q4khmvp5av8mka6zhp98zjfk2z2qneldar`

---

#### 4. 🔐 ISM MULTISIG #2 - For BSC (Domain 56)

```json
{ "owner": "terra1run9wz09uhh6pu7ggcwwetrgye4wu7wn26mawp" }
```

**Code ID:** `11374`
**Validators (official mainnet — 4 of 6):**
- `570af9b7b36568c8877eebba6c6727aa9dab7268` — Abacus Works
- `5450447aee7b544c462c9352bef7cad049b0c2dc` — Zee Prime
- `0d4c1394a255568ec0ecd11795b28d1bda183ca4` — Tessellated
- `24c1506142b2c859aee36474e59ace09784f71e8` — Substance Labs
- `c67789546a7a983bf06453425231ab71c119153f` — Luganodes
- `2d74f6edfd08261c927ddb6cb37af57ab89f0eff` — Enigma

**Instantiated Address:** `terra1nqj7qlnt2sty0dgnu3ss5z4u6wr7hjfea7cn6wpwjt2uymts8ucsmuj9xw`

---

#### 5. 🔐 ISM MULTISIG #3 - For Solana (Domain 1399811149)

```json
{ "owner": "terra1run9wz09uhh6pu7ggcwwetrgye4wu7wn26mawp" }
```

**Code ID:** `11374`
**Validators (official mainnet — 3 of 5):**
- `28464752829b3ea59a497fca0bdff575c534c3ff` — Abacus Works
- `2b7514a2f77bd86bbf093fe6bb67d8611f51c659` — Luganodes
- `cb6bcbd0de155072a7ff486d9d7286b0f71dcc2d` — Eclipse
- `4f977a59fdc2d9e39f6d780a84d5b4add1495a36` — Mitosis
- `5450447aee7b544c462c9352bef7cad049b0c2dc` — Zee Prime

**Instantiated Address:** `terra10s3p36tjek8amhlc4krxpzln6g8n0qy9jq82wyda434l3rv89wfsucl50t`

---

#### 6. 🗺️ ISM ROUTING - ISM Router

```json
{
  "owner": "terra1run9wz09uhh6pu7ggcwwetrgye4wu7wn26mawp",
  "isms": [
    { "domain": 1,          "address": "terra187rzjc3dznfxqtqqrwh796e5q4khmvp5av8mka6zhp98zjfk2z2qneldar" },
    { "domain": 56,         "address": "terra1nqj7qlnt2sty0dgnu3ss5z4u6wr7hjfea7cn6wpwjt2uymts8ucsmuj9xw" },
    { "domain": 1399811149, "address": "terra10s3p36tjek8amhlc4krxpzln6g8n0qy9jq82wyda434l3rv89wfsucl50t" }
  ]
}
```

**Code ID:** `11376`
**Instantiated Address:** `terra1uhzzvt9x3u8hjnkp695hklexx2uywjvfqv454d93ds92sgtpwk7qrpxdg0`

---

#### 7. 🌳 HOOK MERKLE

```json
{ "mailbox": "terra1fwg35n5esjgny7d8pxnz8usjpwsvpguk0txsy6cnqxy58x9fdlksjpx3p9" }
```

**Code ID:** `11380`
**Instantiated Address:** `terra183lq6yqp8km3p34cxgk6k3u78uy4plqahey6rne7n9gy98delr9qyp0n2p`

---

#### 8. ⛽ IGP - Interchain Gas Paymaster

```json
{
  "hrp": "terra",
  "owner": "terra1run9wz09uhh6pu7ggcwwetrgye4wu7wn26mawp",
  "gas_token": "uluna",
  "beneficiary": "terra1run9wz09uhh6pu7ggcwwetrgye4wu7wn26mawp",
  "default_gas_usage": "100000"
}
```

**Code ID:** `11377`
**Instantiated Address:** `terra1taunhg629rssf3g939nqr0h594q5mssrzdj5lkx2hygmxmh72ghqeqqnvz`

**Current on-chain state (2026-09-18):**
- Owner: `terra1run9wz09uhh6pu7ggcwwetrgye4wu7wn26mawp` · Beneficiary (receives the gas payments): `terra1gqkrh2va5mqdrlp90ez6lc2hgagxqju6fc7md4kldlz8lap9w4usduzc2q`
- Default gas: `100000` · Gas per destination (`gas_for_domain`): Ethereum (1) `5394480`, BSC (56) `4803897`, Solana (1399811149) `40158741`
- Oracle route for all three domains → IGP Oracle below

> The per-domain gas amounts are **tuned so that the LUNC fee tracks a target of ≈ $0.08–0.10 per transfer** (the relayer's pass-through tariff), not the raw gas usage of the destination. See [Current fees](#current-fees-2026-09-18).

---

#### 9. 🔮 IGP ORACLE - Gas Price Oracle

```json
{ "owner": "terra1run9wz09uhh6pu7ggcwwetrgye4wu7wn26mawp" }
```

**Code ID:** `11388`
**Instantiated Address:** `terra1j8xzgzk7vds5uzrplmnln4vcz6f205t9atdyflypzrr43cd5eh7scwqj0d`

> Gas prices configured automatically by the script (domains 1/56/1399811149) and kept up to date by the tariff updater.
> **Current owner: `terra1z7jmlky2cmsd9aslm4uxrsase2yjwz8k9rlk00ga8s7pxgljczjq9sv4hj`** (oracle updater wallet); contract admin remains the deployer `terra1run9wz09uhh6pu7ggcwwetrgye4wu7wn26mawp`.

---

#### 10. 🔗 HOOK AGGREGATE #1 - Aggregator (Merkle + IGP)

```json
{
  "owner": "terra1run9wz09uhh6pu7ggcwwetrgye4wu7wn26mawp",
  "hooks": ["<HOOK_MERKLE>", "<IGP>"]
}
```

**Code ID:** `11378`
**Instantiated Address:** `terra1026v947k2jn58t09ppw003xujj92vp3lxv0fg3xk8ccz42r8d2sqvnmvel`

---

#### 11. ⏸️ HOOK PAUSABLE

```json
{ "owner": "terra1run9wz09uhh6pu7ggcwwetrgye4wu7wn26mawp", "paused": false }
```

**Code ID:** `11381`
**Instantiated Address:** `terra1x8s9qtw9355pfckywkns4e8f9zyfjaf8w5e5s8vh28ph5gzwwlks9tjcnf`

---

#### 12. 💰 HOOK FEE

```json
{
  "owner": "terra1run9wz09uhh6pu7ggcwwetrgye4wu7wn26mawp",
  "fee": { "denom": "uluna", "amount": "283215" }
}
```

**Code ID:** `11379`
**Instantiated Address:** `terra1sud5xyknr93wmxem6kxdfd0vxcju47wuh7zdm5uecavrm36w669sp7j8ag`

---

#### 13. 🔗 HOOK AGGREGATE #2 - Aggregator (Pausable + Fee)

```json
{
  "owner": "terra1run9wz09uhh6pu7ggcwwetrgye4wu7wn26mawp",
  "hooks": ["<HOOK_PAUSABLE>", "<HOOK_FEE>"]
}
```

**Code ID:** `11378`
**Instantiated Address:** `terra1xmdd7yhu3qdlfhrcku8srfvtday6efymj54gqz0daxsmn8pvqygq0nxq04`

---

#### 14. ⚙️ MAILBOX CONFIGURATION

After instantiation, configured automatically by the script:
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

### `submit-proposal-mainnet.ts` — Governance proposal script

```bash
# Generate proposal JSON (no key needed)
yarn tsx terraclassic/submit-proposal-mainnet.ts
# → creates proposal_mainnet.json + exec_msgs_mainnet.json

# Execute directly as owner (without governance, for testing)
MODE=direct PRIVATE_KEY="0xYOUR_KEY" yarn tsx terraclassic/submit-proposal-mainnet.ts

# Submit via terrad after ownership transfer to governance
terrad tx gov submit-proposal proposal_mainnet.json \
  --from YOUR_KEY --chain-id columbus-5 \
  --node https://rpc.terra-classic.hexxagon.io:443 \
  --gas auto --gas-adjustment 1.5 --gas-prices 28.5uluna -y
```

### Governance Proposal Messages (8 total)

#### MESSAGE 1: ISM Multisig Validators — Ethereum (Domain 1) ✅ *configured 2026-06-09*

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

#### MESSAGE 2: ISM Multisig Validators — BSC (Domain 56) ✅ *configured 2026-06-09*

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

#### MESSAGE 3: ISM Multisig Validators — Solana (Domain 1399811149) ✅ *configured 2026-06-09*

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
      { "remote_domain": 1,          "token_exchange_rate": "CALCULATE_BEFORE_SUBMIT", "gas_price": "10000000000" },
      { "remote_domain": 56,         "token_exchange_rate": "CALCULATE_BEFORE_SUBMIT", "gas_price": "3000000000"  },
      { "remote_domain": 1399811149, "token_exchange_rate": "CALCULATE_BEFORE_SUBMIT", "gas_price": "1"           }
    ]
  }
}
```

> **Always recalculate before submitting.** See [Section 6](#igp-oracle--updating-gas-prices) for the formula and the `update-igp-oracle.sh` script.
>
> Formula: `token_exchange_rate = (LUNC_USD / NATIVE_USD) * 1e12`
> - Solana uses `gas_price=1` (lamport model) with `exchange_rate = (LUNC_USD / SOL_USD) * 1e15`

**Current on-chain values (2026-09-18):**

| Domain | Chain | exchange_rate | gas_price | gas (IGP `gas_for_domain`) | Fee per transfer |
|---|---|---|---|---|---|
| 1 | Ethereum | 454 | 5879273683 (≈5.9 gwei) | 5,394,480 | 1,439.89 LUNC (≈ $0.074) |
| 56 | BSC mainnet | 1,265 | 3000000000 (3 gwei) | 4,803,897 | 1,823.08 LUNC (≈ $0.094) |
| 1399811149 | Solana | 488,893,709,620 | 1 (lamport) | 40,158,741 | 1,963.34 LUNC (≈ $0.101) |

Prices used for the USD column: LUNC=$0.00005139, ETH=$2517.88, BNB=$752.62, SOL=$106.58 (Binance, 2026-09-18).
`fee_uluna = gas × gas_price × exchange_rate / 1e10` — e.g. BSC: 4,803,897 × 3,000,000,000 × 1,265 / 1e10 = 1,823,078,911 uluna.

> Historical values at first configuration (2026-06-09): ETH rate 376 / 10 gwei, BSC rate 1,098 / 3 gwei, Solana rate 383,001,553,014 / 1.

---

#### MESSAGE 5: IGP Routes to Oracle

```json
{
  "router": {
    "set_routes": {
      "set": [
        { "domain": 1,          "route": "terra1j8xzgzk7vds5uzrplmnln4vcz6f205t9atdyflypzrr43cd5eh7scwqj0d" },
        { "domain": 56,         "route": "terra1j8xzgzk7vds5uzrplmnln4vcz6f205t9atdyflypzrr43cd5eh7scwqj0d" },
        { "domain": 1399811149, "route": "terra1j8xzgzk7vds5uzrplmnln4vcz6f205t9atdyflypzrr43cd5eh7scwqj0d" }
      ]
    }
  }
}
```

---

#### MESSAGE 6: Set Default ISM in Mailbox ✅ *already configured 2026-06-09*

```json
{ "set_default_ism": { "ism": "terra1uhzzvt9x3u8hjnkp695hklexx2uywjvfqv454d93ds92sgtpwk7qrpxdg0" } }
```

---

#### MESSAGE 7: Set Default Hook in Mailbox ✅ *already configured 2026-06-09*

```json
{ "set_default_hook": { "hook": "terra1026v947k2jn58t09ppw003xujj92vp3lxv0fg3xk8ccz42r8d2sqvnmvel" } }
```

> Without this message, `transfer_remote` fails with `panicked at state.rs: default_hook not set`.

---

#### MESSAGE 8: Set Required Hook in Mailbox ✅ *already configured 2026-06-09*

```json
{ "set_required_hook": { "hook": "terra1xmdd7yhu3qdlfhrcku8srfvtday6efymj54gqz0daxsmn8pvqygq0nxq04" } }
```

> The required hook charges **0.283215 LUNC** per outbound message (protocol fee).
> Include this fee in `transfer_remote` funds: `total_fee = IGP_fee + 283215 uluna`.

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

## 5️⃣ IGP Oracle — Updating Gas Prices

The IGP Oracle stores the exchange rate and gas price for each destination chain. It must be updated when:
- Adding a new destination chain (ETH, Solana, etc.)
- Token prices change significantly (>20%)
- Destination network gas prices change

### How it works

The Terra Classic Mailbox charges the sender a fee in **LUNC** to cover gas on the destination chain. The oracle provides the conversion data:

```
fee_uluna = gas_amount × gas_price_dest × exchange_rate / 1e10

Where:
  gas_amount     = the IGP's gas_for_domain for the destination (fallback: default_gas)
  gas_price_dest = destination gas price in the smallest native unit (wei / lamport)
  exchange_rate  = destination-native → uluna conversion, scaled by 1e10
                   (TOKEN_EXCHANGE_RATE_SCALE in cw-hyperlane is 10^10)

Verified against the live contracts (2026-09-18):
  BSC:      4,803,897 × 3,000,000,000 × 1,265           / 1e10 = 1,823,078,911 uluna = 1,823.08 LUNC
  Ethereum: 5,394,480 × 5,879,273,683 × 454             / 1e10 = 1,439,889,343 uluna = 1,439.89 LUNC
  Solana:  40,158,741 × 1             × 488,893,709,620 / 1e10 = 1,963,335,586 uluna = 1,963.34 LUNC
```

**Solana** uses `gas_price = 1` (lamport model); everything else is the same formula.

> In practice the three parameters are tuned together so that the LUNC fee tracks a **target of ≈ $0.08–0.10 per transfer** — the amount the relayer needs on the destination chain plus a margin. The relayer's reward equals the tariff paid (pass-through). When LUNC or the destination gas price moves, only the oracle needs to be updated; the IGP gas amounts rarely change.

### Quick update — `update-igp-oracle.sh`

```bash
cd /home/lunc/tc-cw-hyperlane/terraclassic

# Interactive mode (as owner)
export TERRA_PRIVATE_KEY="your_hex_key"
./update-igp-oracle.sh

# Non-interactive — configure all chains
export TERRA_PRIVATE_KEY="your_hex_key"
LUNC_USD=0.00006824  ETH_USD=3500  BNB_USD=617.38  SOL_USD=150 \
DOMAINS="1,56,1399811149" ./update-igp-oracle.sh

# Generate governance proposal only (no key needed)
MODE=governance LUNC_USD=0.00006824 ETH_USD=3500 BNB_USD=617.38 SOL_USD=150 \
DOMAINS="1,56,1399811149" ./update-igp-oracle.sh
# → generates log/oracle-update-proposal-TIMESTAMP.json
```

### Exchange rate reference table

| Date | LUNC | ETH | BNB | SOL | rate_ETH | rate_BSC | rate_SOL |
|---|---|---|---|---|---|---|---|
| 2026-06-09 (first config) | $0.00006782 | $1803.18 | $617.38 | $70.83 | 376 | 1,098 | 383,001,553,014 |
| 2026-09-18 (on-chain) | $0.00005139 | $2517.88 | $752.62 | $106.58 | 454 | 1,265 | 488,893,709,620 |

> Update this table after each oracle configuration change.
> Run `./update-igp-oracle.sh` to recalculate and apply new rates.

---

## 6️⃣ Execution Verification

After the proposal passes, verify all configurations:

```bash
LCD="https://lcd.terra-classic.hexxagon.io"

# ISM Multisig ETH — validators (domain 1)
terrad query wasm contract-state smart terra187rzjc3dznfxqtqqrwh796e5q4khmvp5av8mka6zhp98zjfk2z2qneldar \
  '{"multisig_ism":{"enrolled_validators":{"domain":1}}}' \
  --node https://rpc.terra-classic.hexxagon.io:443 --chain-id columbus-5

# ISM Multisig BSC — validators (domain 56)
terrad query wasm contract-state smart terra1nqj7qlnt2sty0dgnu3ss5z4u6wr7hjfea7cn6wpwjt2uymts8ucsmuj9xw \
  '{"multisig_ism":{"enrolled_validators":{"domain":56}}}' \
  --node https://rpc.terra-classic.hexxagon.io:443 --chain-id columbus-5

# ISM Multisig Solana — validators (domain 1399811149)
terrad query wasm contract-state smart terra10s3p36tjek8amhlc4krxpzln6g8n0qy9jq82wyda434l3rv89wfsucl50t \
  '{"multisig_ism":{"enrolled_validators":{"domain":1399811149}}}' \
  --node https://rpc.terra-classic.hexxagon.io:443 --chain-id columbus-5

# IGP Oracle — gas price BSC
terrad query wasm contract-state smart terra1j8xzgzk7vds5uzrplmnln4vcz6f205t9atdyflypzrr43cd5eh7scwqj0d \
  '{"oracle":{"get_exchange_rate_and_gas_price":{"dest_domain":56}}}' \
  --node https://rpc.terra-classic.hexxagon.io:443 --chain-id columbus-5

# Mailbox — local domain (must return 132556)
terrad query wasm contract-state smart terra1fwg35n5esjgny7d8pxnz8usjpwsvpguk0txsy6cnqxy58x9fdlksjpx3p9 \
  '{"mailbox":{"local_domain":{}}}' \
  --node https://rpc.terra-classic.hexxagon.io:443 --chain-id columbus-5

# Mailbox — default ISM
terrad query wasm contract-state smart terra1fwg35n5esjgny7d8pxnz8usjpwsvpguk0txsy6cnqxy58x9fdlksjpx3p9 \
  '{"mailbox":{"default_ism":{}}}' \
  --node https://rpc.terra-classic.hexxagon.io:443 --chain-id columbus-5

# Mailbox — default hook
terrad query wasm contract-state smart terra1fwg35n5esjgny7d8pxnz8usjpwsvpguk0txsy6cnqxy58x9fdlksjpx3p9 \
  '{"mailbox":{"default_hook":{}}}' \
  --node https://rpc.terra-classic.hexxagon.io:443 --chain-id columbus-5

# Mailbox — required hook
terrad query wasm contract-state smart terra1fwg35n5esjgny7d8pxnz8usjpwsvpguk0txsy6cnqxy58x9fdlksjpx3p9 \
  '{"mailbox":{"required_hook":{}}}' \
  --node https://rpc.terra-classic.hexxagon.io:443 --chain-id columbus-5

# Mailbox — nonce (messages dispatched)
terrad query wasm contract-state smart terra1fwg35n5esjgny7d8pxnz8usjpwsvpguk0txsy6cnqxy58x9fdlksjpx3p9 \
  '{"mailbox":{"nonce":{}}}' \
  --node https://rpc.terra-classic.hexxagon.io:443 --chain-id columbus-5
```

---

## 7️⃣ Contract Addresses and Hexed

> **Status:** ✅ v2 Instantiated on 2026-06-09 — columbus-5 mainnet — **domain 132556**

| Contract | Address (Bech32) | Hexed (32 bytes) |
|----------|-----------------|------------------|
| **Mailbox** | `terra1fwg35n5esjgny7d8pxnz8usjpwsvpguk0txsy6cnqxy58x9fdlksjpx3p9` | `0x4b911a4e9984913279a709a623f2120ba0c0a3967acd026b1301894398a96fed` |
| **Validator Announce** | `terra1gtnmdevekgxpvzej3wfy20e2n335gm3muwj6geduxxa86j3x70cq00asmy` | `0x42e7b6e599b20c160b328b92453f2a9c63446e3be3a5a465bc31ba7d4a26f3f0` |
| **ISM Multisig ETH** | `terra187rzjc3dznfxqtqqrwh796e5q4khmvp5av8mka6zhp98zjfk2z2qneldar` | `0x3f8629622d14d2602c001bafe2eb34056d7db034eb0fbb7742b84a7149365094` |
| **ISM Multisig BSC** | `terra1nqj7qlnt2sty0dgnu3ss5z4u6wr7hjfea7cn6wpwjt2uymts8ucsmuj9xw` | `0x9825e07e6b541647b513e4610a0abcd387ebc939efb13d382e92d5c26d703f31` |
| **ISM Multisig Solana** | `terra10s3p36tjek8amhlc4krxpzln6g8n0qy9jq82wyda434l3rv89wfsucl50t` | `0x7c2218e972cd8fdddff8ad86608bf3d20f378085900ea711bdac6bf88d872b93` |
| **ISM Routing** | `terra1uhzzvt9x3u8hjnkp695hklexx2uywjvfqv454d93ds92sgtpwk7qrpxdg0` | `0xe5c4262ca68f0f794ec1d1697b7f2632b8474989032b4ab4b16c0aa8216175bc` |
| **Hook Merkle** | `terra183lq6yqp8km3p34cxgk6k3u78uy4plqahey6rne7n9gy98delr9qyp0n2p` | `0x3c7e0d10013db710c6b8322dab479e3f0950fc1dbe49a1cf3e9950429db9f8ca` |
| **IGP** | `terra1taunhg629rssf3g939nqr0h594q5mssrzdj5lkx2hygmxmh72ghqeqqnvz` | `0x5f793ba34a28e104c505896601bef42d414dc20313654fd8cab911b36efe522e` |
| **IGP Oracle** | `terra1j8xzgzk7vds5uzrplmnln4vcz6f205t9atdyflypzrr43cd5eh7scwqj0d` | `0x91cc240ade63614e0861fee7f9d5981692a7d165eada44fc8110c758e1b4cdfd` |
| **Hook Aggregate 1 (default)** | `terra1026v947k2jn58t09ppw003xujj92vp3lxv0fg3xk8ccz42r8d2sqvnmvel` | `0x7ab4c2d7d654a743ade5085cf7c4dc948aa6063f331e9444d63e302aa8676aa0` |
| **Hook Pausable** | `terra1x8s9qtw9355pfckywkns4e8f9zyfjaf8w5e5s8vh28ph5gzwwlks9tjcnf` | `0x31e0502dc58d2814e2c475a70ae4e928889975277533481d9751c37a204e77ed` |
| **Hook Fee** | `terra1sud5xyknr93wmxem6kxdfd0vxcju47wuh7zdm5uecavrm36w669sp7j8ag` | `0x871b4312d31962ed9b3bd58cd4b5ec3625caf9dcbf84ddd399c7583dc74ed68b` |
| **Hook Aggregate 2 (required)** | `terra1xmdd7yhu3qdlfhrcku8srfvtday6efymj54gqz0daxsmn8pvqygq0nxq04` | `0x36dadf12fc881bf4dc78b70f01a58b6f49aca49b952a8009ede9a1b99c2c0110` |

### For Relayer / Agent Config

```yaml
mailbox: "0x4b911a4e9984913279a709a623f2120ba0c0a3967acd026b1301894398a96fed"
validatorAnnounce: "0x42e7b6e599b20c160b328b92453f2a9c63446e3be3a5a465bc31ba7d4a26f3f0"
merkleTreeHook: "0x3c7e0d10013db710c6b8322dab479e3f0950fc1dbe49a1cf3e9950429db9f8ca"
interchainGasPaymaster: "0x5f793ba34a28e104c505896601bef42d414dc20313654fd8cab911b36efe522e"
domainId: 132556
```

### Complete JSON

```json
{
  "hpl_mailbox": "terra1fwg35n5esjgny7d8pxnz8usjpwsvpguk0txsy6cnqxy58x9fdlksjpx3p9",
  "hpl_validator_announce": "terra1gtnmdevekgxpvzej3wfy20e2n335gm3muwj6geduxxa86j3x70cq00asmy",
  "hpl_ism_multisig_eth": "terra187rzjc3dznfxqtqqrwh796e5q4khmvp5av8mka6zhp98zjfk2z2qneldar",
  "hpl_ism_multisig_bsc": "terra1nqj7qlnt2sty0dgnu3ss5z4u6wr7hjfea7cn6wpwjt2uymts8ucsmuj9xw",
  "hpl_ism_multisig_sol": "terra10s3p36tjek8amhlc4krxpzln6g8n0qy9jq82wyda434l3rv89wfsucl50t",
  "hpl_ism_routing": "terra1uhzzvt9x3u8hjnkp695hklexx2uywjvfqv454d93ds92sgtpwk7qrpxdg0",
  "hpl_hook_merkle": "terra183lq6yqp8km3p34cxgk6k3u78uy4plqahey6rne7n9gy98delr9qyp0n2p",
  "hpl_igp": "terra1taunhg629rssf3g939nqr0h594q5mssrzdj5lkx2hygmxmh72ghqeqqnvz",
  "hpl_igp_oracle": "terra1j8xzgzk7vds5uzrplmnln4vcz6f205t9atdyflypzrr43cd5eh7scwqj0d",
  "hpl_hook_aggregate_default": "terra1026v947k2jn58t09ppw003xujj92vp3lxv0fg3xk8ccz42r8d2sqvnmvel",
  "hpl_hook_pausable": "terra1x8s9qtw9355pfckywkns4e8f9zyfjaf8w5e5s8vh28ph5gzwwlks9tjcnf",
  "hpl_hook_fee": "terra1sud5xyknr93wmxem6kxdfd0vxcju47wuh7zdm5uecavrm36w669sp7j8ag",
  "hpl_hook_aggregate_required": "terra1xmdd7yhu3qdlfhrcku8srfvtday6efymj54gqz0daxsmn8pvqygq0nxq04"
}
```

---

## 🌉 Warp Routes — LUNC and USTC on the 4 chains

> Live on-chain inventory as of **2026-09-18**. Everything below is also published in the
> [official Hyperlane registry](https://github.com/hyperlane-xyz/hyperlane-registry) (PR [#1559](https://github.com/hyperlane-xyz/hyperlane-registry/pull/1559) chain onboarding, PR [#1687](https://github.com/hyperlane-xyz/hyperlane-registry/pull/1687) LUNC/USTC warp routes) and on
> [terra-classic.io/docs/develop/hyperlane/contracts](https://terra-classic.io/docs/develop/hyperlane/contracts). Deployment approved by governance proposals
> [12200](https://validator.info/terra-classic/governance/12200) and [12222](https://validator.info/terra-classic/governance/12222).
> Live status (relayer, balances, validators, fees, ownership): **https://github.com/terra-classic-hyperlane/hyperlane-monitoring**.

### Terra Classic (domain 132556) — native / collateral side

| Token | Contract (bech32) | Hexed (32 bytes) | Type | Code ID | Owner | Admin |
|---|---|---|---|---|---|---|
| **LUNC** | `terra1m7jcqxfn4hd7q4sywhw508nxshaf078c4vh83y0ts43y9tlp9dcs50cggy` | `0xdfa5801933addbe0560475dd479e6685fa97f8f8ab2e7891eb856242afe12b71` | `hpl_warp_native` (uluna) | 11390 | `terra1run9wz09uhh6pu7ggcwwetrgye4wu7wn26mawp` | none (immutable) |
| **USTC** | `terra1qu3x6vhk4y6w6erhmedzfp2ug53qm5nwpyarxveqa7tvwg0telxqvd3ccf` | `0x07226d32f6a934ed6477de5a24855c45220dd26e093a333320ef96c721ebcfcc` | `hpl_warp_native` (uusd) | 11390 | `terra1run9wz09uhh6pu7ggcwwetrgye4wu7wn26mawp` | none (immutable) |

The TC warps use the mailbox defaults (no per-contract ISM/hook override): default ISM = ISM Routing, default hook = Hook Aggregate #1 (Merkle + IGP), required hook = Hook Aggregate #2 (Pausable + Fee 0.283215 LUNC).

Enrolled remote routers (LUNC): Ethereum → `0xA4bc47a4…`, BSC → `0x481095ec…`, Solana → `Dd3ajD8W…`. (USTC): Ethereum → `0xf49408be…`, BSC → `0xfC067fd9…`, Solana → `7CUdBt1Q…`.

### BNB Smart Chain (domain 56) — synthetic side

| Contract | Address | Owner | Admin |
|---|---|---|---|
| Warp **LUNC** (HypERC20 proxy, 6 dec) | `0x481095ecEd7A907e7f390b6226F53a66D379e6e2` | `0x8f085bAD1a15ee9ceeE58C83EFFFa72518975291` | ProxyAdmin `0x002a1821aff44c12084bc13f3c5cf442720c127c` |
| Warp **USTC** (HypERC20 proxy, 6 dec) | `0xfC067fd98FD123fC2cAd72d040AF60a523274339` | `0x8f085bAD1a15ee9ceeE58C83EFFFa72518975291` | ProxyAdmin `0x60c92c612d0e7befd188043d557756fef07f725f` |
| Warp ISM (StorageMessageIdMultisigIsm, TC origin, **3-of-4**) | `0xF6b0cDD33A7d2895a3F18b85569Ed9A8278cD151` | `0x8f085bAD1a15ee9ceeE58C83EFFFa72518975291` | — |
| Warp hook (StaticAggregationHook: Merkle + IGP) | `0xD2c82583C261fce94cD3F97f1dFF9B20a9338164` | — (static) | — |
| Warp IGP | `0xEdEd7a4f6FEe4B474B9d7730Bf3465E35E2a4923` | `0x8f085bAD1a15ee9ceeE58C83EFFFa72518975291` | — |
| IGP beneficiary | `0x34E06a7793877EC5251b1dC230aD7cD577d231f4` | | |
| Mailbox (Hyperlane canonical) | `0x2971b9Aec44bE4eb673DF1B88cDB57b96eefe8a4` | `0x7379D7bB2ccA68982E467632B6554fD4e72e9431` (Hyperlane) | ProxyAdmin `0x65993af9d0d3a64ec77590db7ba362d6eb78ef70` |
| Validator announce / Merkle tree hook (canonical) | `0x7024078130D9c2100fEA474DAD009C2d1703aCcd` / `0xFDb9Cd5f9daAA2E4474019405A328a88E7484f26` | `0xa7ECcdb9Be08178f896c26b7BbD8C3D4E844d9Ba` (Hyperlane) | — |

### Ethereum (domain 1) — synthetic side

| Contract | Address | Owner | Admin |
|---|---|---|---|
| Warp **LUNC** (HypERC20 proxy, 6 dec) | `0xA4bc47a4C5461eB0E59A585a21A1222EF7544Ac6` | `0xEF8181201Ce6C83120035Ffbcc11945E67Ba00ae` | ProxyAdmin `0x8c7a816d2c5d4dd480d7267caa46769a3c9fa2b5` |
| Warp **USTC** (HypERC20 proxy, 6 dec) | `0xf49408beb319aeCe3E8B3550a5C750C19b3F1e51` | `0xEF8181201Ce6C83120035Ffbcc11945E67Ba00ae` | ProxyAdmin `0xfbb065fcb26a7a74e5c1f187ae9a45a7d80a51c1` |
| Warp ISM (StorageMessageIdMultisigIsm, TC origin, **3-of-4**) | `0x3ba17675f0D319C89D70722f6eb07790DF0B254B` | `0xEF8181201Ce6C83120035Ffbcc11945E67Ba00ae` | — |
| Warp hook (StaticAggregationHook: Merkle + IGP) | `0x912c4d91D9eD04B16B83dA79dbe7a209c8Fd0aA8` | — (static) | — |
| Warp IGP | `0x9650F1f8DB492750323172145e67Df4e89E964Aa` | `0xEF8181201Ce6C83120035Ffbcc11945E67Ba00ae` | — |
| IGP beneficiary | `0x04096dCBbBB0FA58a312761c38E1d3B9F64631F1` | | |
| Mailbox (Hyperlane canonical) | `0xc005dc82818d67AF737725bD4bf75435d065D239` | `0x562Dfaac27A84be6C96273F5c9594DA1681C0DA7` (Hyperlane) | ProxyAdmin `0x75ee15ee1b4a75fa3e2fdf5df3253c25599cc659` |
| Validator announce / Merkle tree hook (canonical) | `0xCe74905e51497b4adD3639366708b821dcBcff96` / `0x48e6c30B97748d1e2e03bf3e9FbE3890ca5f8CCA` | `0xa7ECcdb9Be08178f896c26b7BbD8C3D4E844d9Ba` (Hyperlane) | — |

### Solana (domain 1399811149) — synthetic side

| Program / account | Address | Owner | Upgrade authority |
|---|---|---|---|
| Warp **LUNC** program | `Dd3ajD8WbEyx7z3HqPnDyvUgFqEBzvF1VePjYd1NGnbr` | `BirXd4QDxfq2vx9LGqgXXSgZrjT81rhoFGUbQRWDEf1j` | `BirXd4QDxfq2vx9LGqgXXSgZrjT81rhoFGUbQRWDEf1j` |
| LUNC mint (Token-2022, 6 dec) | `8dxTo5reLtvRDx3Q8WEP33Uj2C5u6372EygJdNbsLFKG` | mint authority = program PDA | metadata update authority `BirXd4QD…` |
| Warp **USTC** program | `7CUdBt1Qn2R2StE7MDPhQW2EhmnGg8zKK8oJXwAGEoyf` | `BirXd4QDxfq2vx9LGqgXXSgZrjT81rhoFGUbQRWDEf1j` | `BirXd4QDxfq2vx9LGqgXXSgZrjT81rhoFGUbQRWDEf1j` |
| USTC mint (Token-2022, 6 dec) | `GNUbsF5mrurtDzNc65HipN5Fyzzzqbj5UonLNhj9frjF` | mint authority = program PDA | metadata update authority `BirXd4QD…` |
| Warp ISM program (multisig, TC origin, shared by LUNC/USTC) | `4MzF7HCfxuwj4EFHqZSEpvkcZZvv1mF37DP4pDHwR5VQ` | — | `BirXd4QDxfq2vx9LGqgXXSgZrjT81rhoFGUbQRWDEf1j` |
| IGP program | `FLZuKRsfdovLqd8n1AYhPCwLqBjfFyZY3A2edgnjdJoR` | — | — |
| Overhead IGP account (used by the warps) | `FXacR73HiuNyvW7x34KYCDyv8XxM86pz31Ap8t2v3RCJ` | `BirXd4QDxfq2vx9LGqgXXSgZrjT81rhoFGUbQRWDEf1j` | — |
| Inner IGP account (gas oracle for domain 132556) | `FPTvDsowMHXFKktoLgy2a2qfr5yL6846JHKwvk2mYKFk` | `4sZAfqDqEmR7LMWjrdNmoEkv8S6BDdnDkh5mfADenaaA` | beneficiary `Eq1mJGTSbLb8s6gfoyg5aovxFAhXpnVudXXSAmbDwb9w` |
| Mailbox program (Hyperlane canonical) | `E588QtVUvresuXq2KoNEwAmoifCzYGpRBdHByN9KQMbi` | `3oocunLfAgATEqoRyW7A5zirsQuHJh6YjD4kReiVVKLa` (Hyperlane) | `3oocunLfAgATEqoRyW7A5zirsQuHJh6YjD4kReiVVKLa` |
| Validator announce program (canonical) | `pRgs5vN4Pj7WvFbxf6QDHizo2njq2uksqEUbaSghVA8` | — | `3oocunLfAgATEqoRyW7A5zirsQuHJh6YjD4kReiVVKLa` |

### Validator sets in force

| Messages from | Verified by | Validators (threshold) |
|---|---|---|
| **Terra Classic** → BSC / Ethereum / Solana | Warp ISMs above (BSC `0xF6b0…`, Ethereum `0x3ba1…`, Solana `4MzF7…`) | **3-of-4**: Igor Veras `0x71b2b8c36a0c76b74be92eb7915e26a69b3b03eb`, TCV `0x1afd3d07abd2aaa19a9f7993f334a926e253b90c`, DarkSun `0xe6bb040164a0ebbcb7e2d584f066c8b57dd74383`, BurnItAll `0x5c374754892ebac52702475726b67f822efdfacc`. (LuncGoblins `0x0c737caf…` is announced on the TC ValidatorAnnounce but not enrolled.) |
| BSC → Terra Classic | ISM Multisig BSC `terra1nqj7q…` | 4-of-6 Hyperlane default validators (section 3) |
| Ethereum → Terra Classic | ISM Multisig ETH `terra187rzj…` | 6-of-9 Hyperlane default validators (section 3) |
| Solana → Terra Classic | ISM Multisig SOL `terra10s3p3…` | 3-of-5 Hyperlane default validators (section 3) |

---

## 💸 Current fees (2026-09-18)

Fee paid by the user on the **origin** chain for one transfer, quoted from the live contracts
(`igp.quote_gas_payment` on TC, `quoteDispatch` of the warp hook on EVM, IGP `QuoteGasPayment` simulation on Solana).
USD at Binance spot: LUNC $0.00005139, BNB $752.62, ETH $2517.88, SOL $106.58.

| Route | Gas fee (IGP) | ≈ USD | Plus |
|---|---|---|---|
| Terra Classic → BSC | 1,823.08 LUNC | $0.094 | required hook fee 0.283215 LUNC |
| Terra Classic → Ethereum | 1,439.89 LUNC | $0.074 | required hook fee 0.283215 LUNC |
| Terra Classic → Solana | 1,963.34 LUNC | $0.101 | required hook fee 0.283215 LUNC |
| BSC → Terra Classic | 0.000111561 BNB | $0.084 | — |
| Ethereum → Terra Classic | 0.0000330973 ETH | $0.083 | — |
| Solana → Terra Classic | 0.000786 SOL (3,000,000 gas + 8,660,148 overhead) | $0.081 | — |

Notes:
- The BSC/Ethereum warp IGPs have **no gas oracle for domain 132556**; the fee comes from the hook's `quoteDispatch` and is a flat pass-through tariff.
- The relayer (`terra1run9wz…` on TC, `0x8f085bAD…` on BSC, `0xEF818120…` on Ethereum, `PbEo7Fn2…` on Solana) pays the destination gas and is reimbursed by these tariffs.
- These numbers move with token prices and oracle updates; the monitor shows them live.

---

## 🔑 Ownership & admin summary (Terra Classic core, 2026-09-18)

| Contract | Owner | Contract admin (migrate) |
|---|---|---|
| Mailbox, ISM Routing, ISM Multisig ETH/BSC/SOL, IGP, Hook Fee, Hook Pausable, Hook Aggregate #1/#2 | `terra1run9wz09uhh6pu7ggcwwetrgye4wu7wn26mawp` | `terra1run9wz09uhh6pu7ggcwwetrgye4wu7wn26mawp` |
| IGP Oracle | `terra1z7jmlky2cmsd9aslm4uxrsase2yjwz8k9rlk00ga8s7pxgljczjq9sv4hj` | `terra1run9wz09uhh6pu7ggcwwetrgye4wu7wn26mawp` |
| Validator Announce, Hook Merkle | — (no owner) | `terra1run9wz09uhh6pu7ggcwwetrgye4wu7wn26mawp` |
| Warp LUNC / USTC | `terra1run9wz09uhh6pu7ggcwwetrgye4wu7wn26mawp` | none (immutable) |

> Ownership transfer of the core contracts to the governance module (`terra10d07y265gmmuvt4z0w9aw880jnsr700juxf95n`) is **still pending** — see the checklist.

---

## 8️⃣ Troubleshooting

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

### Upload (✅ Completed — 2026-06-03)
- [x] Contracts uploaded — code IDs 11371–11390
- [x] SHA-256 hashes verified
- [x] TX hashes recorded

### Instantiation v2 (✅ Complete — 2026-06-09) — domain 132556
- [x] Run `CustomInstantiateWasm-mainnet-v2.ts`
- [x] All 13 contracts instantiated successfully
- [x] Address table filled (section 7)

### Ownership Transfer
- [ ] Transfer ownership to governance — see [`TRANSFER-OWNERSHIP-TO-GOVERNANCE.md`](./TRANSFER-OWNERSHIP-TO-GOVERNANCE.md)

### IGP Oracle Configuration ✅ (2026-06-09)
- [x] Domain 1 (Ethereum): exchange_rate=37611, gas_price=10gwei
- [x] Domain 56 (BSC mainnet): exchange_rate=110531, gas_price=3gwei
- [x] Domain 1399811149 (Solana): exchange_rate=38300155301425, gas_price=1

### Mailbox Configuration ✅ (2026-06-09)
- [x] `set_default_ism`   → ISM Routing
- [x] `set_default_hook`  → Hook Agg [Merkle + IGP]
- [x] `set_required_hook` → Hook Agg [Pausable + Fee (0.283215 LUNC)]

### ISM Validators ✅ (2026-06-09)
- [x] ISM Multisig ETH (domain 1): 9 validators, threshold 6 — TX `2308D53B...`
- [x] ISM Multisig BSC (domain 56): 6 validators, threshold 4 — TX `B04D610A...`
- [x] ISM Multisig SOL (domain 1399811149): 5 validators, threshold 3 — TX `9C053296...`

### Configuration via Governance (for re-applying after ownership transfer)
- [ ] Run `yarn tsx terraclassic/submit-proposal-mainnet.ts` — generates `proposal_mainnet.json`
- [ ] Submit and vote when needed after transferring ownership to governance module

### Post-Deployment ✅
- [x] Update relayer agent-config with new addresses (hyperlane-agent/agent-config.json)
- [x] Update EVM/Solana warp route configs for new domain 132556
- [x] Re-deploy warp routes (new mailbox address) — LUNC/USTC on BSC, Ethereum, Solana
- [x] Test cross-chain message sending (82 messages dispatched from TC as of 2026-09-18, all delivered)
- [x] Document final addresses for auditing — see "Warp Routes" and "Ownership & admin summary"
- [x] Registered in the official Hyperlane registry (PR #1559, PR #1687) and published at terra-classic.io/docs
- [x] Public monitor: https://github.com/terra-classic-hyperlane/hyperlane-monitoring

---

**Last updated:** 2026-09-18 (contracts, owners/admins, fees and warp routes re-verified on-chain)
**Contract Version:** v0.0.7-rc0
**Chain:** Terra Classic Mainnet (columbus-5)
**Domain ID:** 132556 (v2 — replaces 1325 which conflicted with testnet)
**RPC:** https://rpc.terra-classic.hexxagon.io
**LCD:** https://lcd.terra-classic.hexxagon.io
**Governance Module:** `terra10d07y265gmmuvt4z0w9aw880jnsr700juxf95n`
**Supported Chains:** Ethereum (Domain 1), BSC (Domain 56), Solana (Domain 1399811149)
**Upload Status:** ✅ 20 contracts uploaded (code IDs 11371–11390)
**Instantiation Status:** ✅ Complete v2 — 2026-06-09
