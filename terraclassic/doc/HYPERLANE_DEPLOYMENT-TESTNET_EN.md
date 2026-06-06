# 📘 Complete Guide: Hyperlane Deployment and Configuration on Terra Classic Testnet

This guide documents the complete process of deploying and configuring Hyperlane contracts on Terra Classic Testnet (rebel-2).

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
- **Terra Classic Testnet Node**: Access to public RPC
- **Wallet**: Private key configured

### Environment Variables

```bash
export PRIVATE_KEY="your_private_key_hexadecimal"
```

---

### Generating a Private Key in Hex Format

The deployment and instantiation scripts require a **32-byte private key in hexadecimal format** (64 hex characters prefixed with `0x`).

This section shows how to generate or export that key for **Terra Classic** (Cosmos) and the **EVM/Solana** chains used alongside it.

---

#### Terra Classic (Cosmos / `terrad`)

Terra Classic uses the Cosmos key format. The private key is derived from a mnemonic phrase and exported as raw hex.

**Step 1 — Install `terrad`**

```bash
TERRA_VERSION="v3.0.1"
wget https://github.com/classic-terra/core/releases/download/${TERRA_VERSION}/terrad-${TERRA_VERSION}-linux-amd64
chmod +x terrad-${TERRA_VERSION}-linux-amd64
sudo mv terrad-${TERRA_VERSION}-linux-amd64 /usr/local/bin/terrad
terrad version
```

**Step 2 — Generate a new key**

```bash
# A keyring password will be prompted
terrad keys add deployer-key --keyring-backend file
```

> Save the 24-word mnemonic phrase immediately — it is the only way to recover the wallet.

**Step 3 — Export the private key in hex**

```bash
terrad keys export deployer-key --keyring-backend file --unarmored-hex --unsafe
```

**Step 4 — Save with `0x` prefix**

```bash
echo "0x$(terrad keys export deployer-key --keyring-backend file --unarmored-hex --unsafe)" \
  > ~/.terra-private-key
chmod 600 ~/.terra-private-key
```

**Step 5 — Get the Terra address**

```bash
terrad keys show deployer-key --keyring-backend file --address
# Example: terra12awgqgwm2evj05ndtgs0xa35uunlpc76d85pze
```

**Step 6 — Set the environment variable**

```bash
export PRIVATE_KEY="0xYOUR_64_CHAR_HEX_KEY"
```

**Import an existing key (if you already have a mnemonic):**

```bash
terrad keys add deployer-key --recover --keyring-backend file
# Type the 24-word mnemonic when prompted
```

---

#### Ethereum / BSC (EVM chains — `cast`)

EVM chains (Ethereum, Sepolia, BSC Testnet) use ECDSA secp256k1 — the same key format.

**Step 1 — Install Foundry**

```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
cast --version
```

**Step 2 — Generate a new key**

```bash
cast wallet new
```

Output:
```
Private Key: 0xabcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890
Address:     0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb0
```

**Alternative — generate with `openssl`:**

```bash
echo "0x$(openssl rand -hex 32)"
# Then derive the address:
cast wallet address --private-key 0xYOUR_GENERATED_KEY
```

---

#### Solana (`solana-keygen`)

Solana uses ED25519. The keypair JSON contains 64 bytes — the **first 32 are the private key**.

**Step 1 — Install Solana CLI**

```bash
sh -c "$(curl -sSfL https://release.solana.com/stable/install)"
solana-keygen --version
```

**Step 2 — Generate a new keypair**

```bash
solana-keygen new --outfile ./solana-keypair.json
chmod 600 ./solana-keypair.json
```

**Step 3 — Extract the private key as hex**

```bash
python3 << 'EOF'
import json
with open('./solana-keypair.json') as f:
    kp = json.load(f)
print(f"0x{bytes(kp[:32]).hex()}")
EOF
```

**Step 4 — Get the public address**

```bash
solana-keygen pubkey ./solana-keypair.json
```

---

#### Key Format Validation

All keys must follow this format before being used in scripts or config files:

| Chain | Algorithm | Expected format |
|-------|-----------|-----------------|
| Terra Classic | secp256k1 | `0x` + 64 hex chars |
| Ethereum / BSC | secp256k1 | `0x` + 64 hex chars |
| Solana | ED25519 | `0x` + 64 hex chars (first 32 bytes of keypair) |

**Validate your key:**

```bash
echo "0xYOUR_KEY" | wc -c
# Must return 67  (= 0x + 64 chars + newline)
```

> Never commit private keys to Git. Use `chmod 600` on all files containing keys.
> For detailed per-chain instructions see: [`HYPERLANE-PRIVATE-KEYS-HEX.md`](../../../../tc-hyperlane-validator/HYPERLANE-PRIVATE-KEYS-HEX.md)

---

### Install Dependencies

```bash
cd cw-hyperlane
yarn install
```

---

## 1️⃣ Verify Available Contracts

Before deploying, verify which contracts are available in the remote repository:

```bash
yarn cw-hpl upload remote-list -n terraclassic
```

**Expected output:**
```
Listing available contracts from remote repository...
- hpl_mailbox
- hpl_validator_announce
- hpl_ism_aggregate
- hpl_ism_multisig
- hpl_ism_pausable
- hpl_ism_routing
- hpl_igp
- hpl_igp_oracle
- hpl_hook_aggregate
- hpl_hook_fee
- hpl_hook_merkle
- hpl_hook_pausable
- hpl_hook_routing
- hpl_hook_routing_custom
- hpl_hook_routing_fallback
- hpl_test_mock_hook
- hpl_test_mock_ism
- hpl_test_mock_msg_receiver
- hpl_warp_cw20
- hpl_warp_native
```

### 📦 Available Releases

The compiled WASM contracts are available on GitHub Releases:

- **Latest Release**: [v0.0.6-rc8](https://github.com/many-things/cw-hyperlane/releases/tag/v0.0.6-rc8)
- **Direct Download**: https://github.com/many-things/cw-hyperlane/releases/download/v0.0.6-rc8/cw-hyperlane-v0.0.6-rc8.zip
- **All Versions**: https://github.com/many-things/cw-hyperlane/releases

---

## 2️⃣ Contract Deployment (Upload)

### Upload to Blockchain

Execute the command to upload all contracts of the specified version:

```bash
yarn cw-hpl upload remote v0.0.6-rc8 -n terraclassic
```

**What this command does:**
- 📥 **Downloads WASM files** from GitHub release
- 📤 Uploads to Terra Classic Testnet blockchain
- 💾 Stores the `code_id` of each contract
- 📝 Saves IDs in the context file (`context/terraclassic.json`)

### Contract Hashes (For Auditing)

During upload, each contract generates a **SHA-256 hash** of the WASM file. These hashes are **crucial for auditing** and ensure that binaries have not been tampered with:

| Contract | SHA-256 Hash | Code ID (Testnet) | TX Hash |
|----------|--------------|-------------------|---------|
| **hpl_mailbox** | `12e1eb4266faba3cc99ccf40dd5e65aed3e03a8f9133c4b28fb57b2195863525` | 1981 | `E5D465100CDAE4A8E9CF91996D0F79CDB0818FE959A9DE26AB0731001A0FE74A` |
| **hpl_validator_announce** | `87cf4cbe4f5b6b3c7a278b4ae0ae980d96c04192f07aa70cc80bd7996b31c6a8` | 1982 | `781048E6DB6ADF70F132F7823F729BE185C994A4FF93051EB0CD8D5DEE44653A` |
| **hpl_ism_aggregate** | `fae4d22afede6578ce8b4dbfaa185d43a303b8707386a924232aa24632d00f7b` | 1983 | `5C66E34A32812F4AB9EA4927FA775160FD3855D5396A931D05B53D90EBCCE34A` |
| **hpl_ism_multisig** | `d1f4705e19414e724d3721edad347003934775313922b7ca183ca6fa64a9e076` | 1984 | `CE0EF5E9C74B6AFD7A4DFFEA72F09CDC9641B7580EA66201EA4E3B59929771E8` |
| **hpl_ism_pausable** | `a6e8cc30b5abf13a032c8cb70128fcd88305eea8133fd2163299cf60298e0e7f` | 1985 | `3D188F0BFB7A96C37586A33EDB8B2FA1FBC6CC60CAEB444BA27BDB9DA9D7BD3E` |
| **hpl_ism_routing** | `a0b29c373cb5428ef6e8a99908e0e94b62d719c65434d133b14b4674ee937202` | 1986 | `F0DEA9FEEE0923A159181A06AF7392F4906931AC86F8E4F491B5444F9CBB77B9` |
| **hpl_igp** | `99e42faf05c446170167bdf0521eaaeebe33658972d056c4d0dc607d99186044` | 1987 | `7BB862772DE9769E21FEDDC2A32EF928A1E752B433549F353D70B146C2EC5051` |
| **hpl_hook_aggregate** | `2ee718217253630b087594a92a6770f8d040a99b087e38deafef2e4685b23e8f` | 1988 | `9C7C6C2399F7F687D75F7CFDEC2D5D442C3A7F36BB3A7690042658A5F8198188` |
| **hpl_hook_fee** | `8beeb594aa33ae3ce29f169ac73e2c11c80a7753a2c92518e344b86f701d50fd` | 1989 | `6E43F59DB33637770BDC482177847AE87BA36CC143E06E02651F48C390F39B42` |
| **hpl_hook_merkle** | `1de731062f05b83aaf44e4abb37f566bb02f0cd7c6ecf58d375cbce25ff53076` | 1990 | `B466AE86528BA0F01AFE06FF0D5275AEA73399DE3E064CCABC8500A2F0487194` |
| **hpl_hook_pausable** | `8ea810f57c31bd754ba21ac87cfc361f1d6cc55974eefd8ad2308b69bd63d6bf` | 1991 | `D9454A2C9D58E81791134D9F06D58652A3A3592DFDD84F8781668169FAF70C5D` |
| **hpl_hook_routing** | `cbf712a3ed6881e267ad3b7a82df362c02ae9cb98b68e12c316005d928f611cf` | 1992 | `788968FF912DB6C84B846C2C64A114BCB6B9B6D8F26BF91B05944F46ACECAD52` |
| **hpl_hook_routing_custom** | `f2ffb3a6444da867d7cd81726cb0362ac3cc7ba2e8eef11dcb50f96e6725d09a` | 1993 | `7E72C154E743E6A57D7AED43BE99751D72B48A85EEF54C308539D68021F68952` |
| **hpl_hook_routing_fallback** | `d701bb43e1aea05ae8bdb3fcbe68b449b6e6d9448420b229a651ed9628a3d309` | 1994 | `FF2C219C59B2DF6500F8F40E563247F6F78C66E7852C57794A7BCC6805227DCC` |
| **hpl_test_mock_hook** | `15b7b62a78ce535239443228a0dc625408941182d1b09b338b55d778101e7913` | 1995 | `E797929E1C41151A6B3892E75583B48DB766155CA36F15B4E206A3F212EA9EFA` |
| **hpl_test_mock_ism** | `a5d07479b6d246402438b6e8a5f31adaafa18c2cd769b6dc821f21428ad560ab` | 1996 | `F20D52763BFDD7B18888CCF667CFED053B445BB2E4F0310F67D6FC48DC426B8B` |
| **hpl_test_mock_msg_receiver** | `35862c951117b77514f959692741d9cabc21ce7c463b9682965fce983140f0c1` | 1997 | `C40928D341D14A8C9EAC9EC086FC644273AE9392A90DDB50495517B68524F899` |
| **hpl_igp_oracle** | `a628d5e0e6d8df3b41c60a50aeaee58734ae21b03d443383ebe4a203f1c86609` | 1998 | `A65B92159B6CD64F6BE58B7E8626B066F6F386AB6C540F05FAC0B76E64889765` |
| **hpl_warp_cw20** | `a97d87804fae105d95b916d1aee72f555dd431ece752a646627cf1ac21aa716d` | 1999 | `18FD9952226B3B834BB63BDD095D2129D2BE24C9A750455C0289CBAC03B2C1D4` |
| **hpl_warp_native** | `5aa1b379e6524a3c2440b61c08c6012cc831403fae0c825b966ceabecfdb172b` | 2000 | `5D8E697027851176A4FE0AB5B6C5FF32EE28D609D4F934DA3AC4A0BBB6B24812` |

#### 🔒 Integrity Verification

The SHA-256 hashes above allow you to **verify the integrity** of contracts:

**Method 1: Verify against blockchain**

```bash
# Download WASM from code ID (example: hpl_mailbox with code_id 1981)
terrad query wasm code 1981 download.wasm \
  --node https://rpc.luncblaze.com:443 \
  --chain-id rebel-2

# Calculate SHA-256 hash
sha256sum download.wasm

# Compare with hash from table above
# For hpl_mailbox should be: 12e1eb4266faba3cc99ccf40dd5e65aed3e03a8f9133c4b28fb57b2195863525
```

**Method 2: Verify against official release**

```bash
# Download official release
wget https://github.com/many-things/cw-hyperlane/releases/download/v0.0.6-rc8/cw-hyperlane-v0.0.6-rc8.zip
unzip cw-hyperlane-v0.0.6-rc8.zip

# Verify all checksums
sha256sum -c checksums.txt

# Or verify a specific contract
sha256sum hpl_mailbox.wasm
# Output: 12e1eb4266faba3cc99ccf40dd5e65aed3e03a8f9133c4b28fb57b2195863525
```

### Verify Code IDs

The `code_id` values are saved in:
```bash
cat context/terraclassic.json
```

**Example content:**
```json
{
  "artifacts": {
    "hpl_mailbox": 1981,
    "hpl_validator_announce": 1982,
    "hpl_ism_aggregate": 1983,
    "hpl_ism_multisig": 1984,
    "hpl_ism_pausable": 1985,
    "hpl_ism_routing": 1986,
    "hpl_igp": 1987,
    "hpl_hook_aggregate": 1988,
    "hpl_hook_fee": 1989,
    "hpl_hook_merkle": 1990,
    "hpl_hook_pausable": 1991,
    "hpl_hook_routing": 1992,
    "hpl_hook_routing_custom": 1993,
    "hpl_hook_routing_fallback": 1994,
    "hpl_test_mock_hook": 1995,
    "hpl_test_mock_ism": 1996,
    "hpl_test_mock_msg_receiver": 1997,
    "hpl_igp_oracle": 1998,
    "hpl_warp_cw20": 1999,
    "hpl_warp_native": 2000
  }
}
```

### Identifying the Governance Module

To verify the governance module address on your network:

```bash
# View governance information
terrad query gov params \
  --node https://rpc.luncblaze.com:443 \
  --chain-id rebel-2

# The governance module usually has the address:
# terra10d07y265gmmuvt4z0w9aw880jnsr700juxf95n (Terra Classic)
```

---

## 3️⃣ Contract Instantiation

### Script: `CustomInstantiateWasm-testnet.ts`

This script instantiates all contracts on the blockchain with their initial configurations.

#### Execute Instantiation

```bash
cd /home/lunc/cw-hyperlane
PRIVATE_KEY="your_key_hex" yarn tsx script/CustomInstantiateWasm-testnet.ts
```

#### Script Configuration

The script is configured with:
- **RPC**: `https://rpc.luncblaze.com`
- **Chain ID**: `rebel-2`
- **Admin/Owner**: `terra10d07y265gmmuvt4z0w9aw880jnsr700juxf95n` ⚠️
- **Gas Price**: `28.5uluna`

### 📋 Instantiated Contracts - Detailed Explanation

The script instantiates **12 contracts** in the following order:

---

#### 1. 📮 MAILBOX - Main Cross-Chain Messaging Contract

**Function:** The Mailbox is the central contract that manages sending and receiving cross-chain messages. It coordinates ISMs, Hooks, and maintains message nonce.

**Instantiation Parameters:**
```json
{
  "hrp": "terra",
  "domain": 13253,
  "owner": "terra10d07y265gmmuvt4z0w9aw880jnsr700juxf95n"
}
```

**Parameter Explanation:**
- `hrp` (string): Human-readable part of Bech32 address - chain prefix (e.g., "terra" for Terra Classic)
- `domain` (u32): Unique chain domain ID in Hyperlane protocol. Terra Classic Testnet = 13253
- `owner` (string): Address that will have admin control of the contract (governance module)

**Code ID:** `1981`

**Instantiated Address:**
- **Address**: `terra1rqg3qfkfg5upad9xu6zj5jhl626qy053s7rn08829rgqzv2wu39s5la8yf`
- **Hexed**: `18111026c945381eb4a6e6852a4affd2b4023e918787379cea28d001314ee44b`

---

#### 2. 📢 VALIDATOR ANNOUNCE - Validator Registry

**Function:** Allows validators to announce their endpoints and locations so relayers can discover how to obtain signatures.

**Instantiation Parameters:**
```json
{
  "hrp": "terra",
  "mailbox": "terra1rqg3qfkfg5upad9xu6zj5jhl626qy053s7rn08829rgqzv2wu39s5la8yf"
}
```

**Parameter Explanation:**
- `hrp` (string): Bech32 chain prefix
- `mailbox` (string): Mailbox address associated with this announcer

**Code ID:** `1982`

**Instantiated Address:**
- **Address**: `terra10szy9ppjpgt8xk3tkywu3dhss8s5scsga85f4cgh452p6mwd092qdzfyup`
- **Hexed**: `7c044284320a16735a2bb11dc8b6f081e1486208e9e89ae117ad141d6dcd7954`

---

#### 3. 🔐 ISM MULTISIG #1 - For BSC Testnet (Domain 97)

**Function:** ISM that validates messages using signatures from multiple validators. Requires a minimum threshold of signatures to approve a message.

**Instantiation Parameters:**
```json
{
  "owner": "terra10d07y265gmmuvt4z0w9aw880jnsr700juxf95n"
}
```

**Parameter Explanation:**
- `owner` (string): Address that can configure validators and threshold (governance module)

**Note:** Validators and threshold will be configured later via governance.

**Code ID:** `1984`

**Instantiated Address:**
- **Address**: `terra1rrt0kepmazvavmkusvz6589l5yg4mqjk49netqfqttnmf2y4exmqxhp0hv`
- **Hexed**: `18d6fb643be899d66edc8305aa1cbfa1115d8256a9679581205ae7b4a895c9b6`

---

#### 4. 🔐 ISM MULTISIG #2 - For Solana Testnet (Domain 1399811150)

**Function:** ISM that validates messages using signatures from multiple validators for Solana Testnet.

**Instantiation Parameters:**
```json
{
  "owner": "terra10d07y265gmmuvt4z0w9aw880jnsr700juxf95n"
}
```

**Code ID:** `1984`

**Instantiated Address:**
- **Address**: `terra1d7a52pxu309jcgv8grck7jpgwlfw7cy0zen9u42rqdr39tef9g7qc8gp4a`
- **Hexed**: `6fbb4504dc8bcb2c218740f16f482877d2ef608f16665e5543034712af292a3c`

---

#### 5. 🗺️ ISM ROUTING - ISM Router

**Function:** Allows using different ISMs for different domains (chains). Useful for having customized security policies per source chain.

**Instantiation Parameters:**
```json
{
  "owner": "terra10d07y265gmmuvt4z0w9aw880jnsr700juxf95n",
  "isms": [
    {
      "domain": 97,
      "address": "terra1rrt0kepmazvavmkusvz6589l5yg4mqjk49netqfqttnmf2y4exmqxhp0hv"
    },
    {
      "domain": 1399811150,
      "address": "terra1d7a52pxu309jcgv8grck7jpgwlfw7cy0zen9u42rqdr39tef9g7qc8gp4a"
    }
  ]
}
```

**Parameter Explanation:**
- `owner` (string): Address that can add/remove ISM routes
- `isms` (array): List of domain → ISM mappings
  - `domain` (u32): Source chain domain ID
    - Domain 97 = BSC Testnet
    - Domain 1399811150 = Solana Testnet
  - `address` (string): ISM address to be used for messages from this domain

**Code ID:** `1986`

**Instantiated Address:**
- **Address**: `terra1h4sd8fyxhde7dc9w9y9zhc2epphgs75q7zzfg3tfynm8qvpe3jlsd7sauh`
- **Hexed**: `bd60d3a486bb73e6e0ae290a2be159086e887a80f08494456924f67030398cbf`

---

#### 6. 🌳 HOOK MERKLE - Merkle Tree for Proofs

**Function:** Maintains a Merkle tree of sent messages. This allows efficient inclusion proofs for message validation on the destination chain.

**Instantiation Parameters:**
```json
{
  "mailbox": "terra1rqg3qfkfg5upad9xu6zj5jhl626qy053s7rn08829rgqzv2wu39s5la8yf"
}
```

**Parameter Explanation:**
- `mailbox` (string): Mailbox address associated with this hook

**Code ID:** `1990`

**Instantiated Address:**
- **Address**: `terra1x9ftmmyj0t9n0ql78r2vdfk9stxg5z6vnwnwjym9m7py6lvxz8ls7sa3df`
- **Hexed**: `3152bdec927acb3783fe38d4c6a6c582cc8a0b4c9ba6e91365df824d7d8611ff`

---

#### 7. ⛽ IGP - Interchain Gas Paymaster

**Function:** Manages gas payments for message execution on the destination chain. Users pay gas on the source chain, and relayers are reimbursed on the destination chain.

**Instantiation Parameters:**
```json
{
  "hrp": "terra",
  "owner": "terra10d07y265gmmuvt4z0w9aw880jnsr700juxf95n",
  "gas_token": "uluna",
  "beneficiary": "terra10d07y265gmmuvt4z0w9aw880jnsr700juxf95n",
  "default_gas_usage": "100000"
}
```

**Parameter Explanation:**
- `hrp` (string): Bech32 prefix
- `owner` (string): Contract admin
- `gas_token` (string): Token used for gas payment (micro-luna = uluna)
- `beneficiary` (string): Address that receives accumulated fees
- `default_gas_usage` (string): Default estimated gas amount for execution (100000 = 100k gas units)

**Code ID:** `1987`

**Instantiated Address:**
- **Address**: `terra1n70g3vg7xge6q8m44rudm4y6fm6elpspwsgfmfphs3teezpak6cs6wxlk9`
- **Hexed**: `9f9e88b11e3233a01f75a8f8ddd49a4ef59f860174109da43784579c883db6b1`

---

#### 8. 🔮 IGP ORACLE - Gas Price Oracle

**Function:** Provides token exchange rates and gas prices for remote chains. Essential for calculating how much gas to charge at origin to cover destination costs.

**Instantiation Parameters:**
```json
{
  "owner": "terra10d07y265gmmuvt4z0w9aw880jnsr700juxf95n"
}
```

**Parameter Explanation:**
- `owner` (string): Address that can update exchange rates and gas prices

**Note:** Exchange rates and gas prices will be configured via governance.

**Code ID:** `1998`

**Instantiated Address:**
- **Address**: `terra18tyqe79yktac6p3alv3f49k06xqna2q52twyaflrz55qka9emhrs30k3hg`
- **Hexed**: `3ac80cf8a4b2fb8d063dfb229a96cfd1813ea81452dc4ea7e315280b74b9ddc7`

---

#### 9. 🔗 HOOK AGGREGATE #1 - Aggregator (Merkle + IGP)

**Function:** Combines multiple hooks into one. This first aggregator executes:
- **Hook Merkle**: registers message in Merkle tree
- **IGP**: processes gas payment

**Instantiation Parameters:**
```json
{
  "owner": "terra10d07y265gmmuvt4z0w9aw880jnsr700juxf95n",
  "hooks": [
    "terra1x9ftmmyj0t9n0ql78r2vdfk9stxg5z6vnwnwjym9m7py6lvxz8ls7sa3df",
    "terra1n70g3vg7xge6q8m44rudm4y6fm6elpspwsgfmfphs3teezpak6cs6wxlk9"
  ]
}
```

**Parameter Explanation:**
- `owner` (string): Contract admin
- `hooks` (array): List of hook addresses to be executed in sequence
  - Hook 1: Merkle Tree
  - Hook 2: IGP

**Note:** This hook will be set as `default_hook` in the Mailbox.

**Code ID:** `1988`

**Instantiated Address:**
- **Address**: `terra14qjm9075m8djus4tl86lc5n2xnsvuazesl52vqyuz6pmaj4k5s5qu5q6jh`
- **Hexed**: `a825b2bfd4d9db2e42abf9f5fc526a34e0ce745987e8a6009c1683becab6a428`

---

#### 10. ⏸️ HOOK PAUSABLE - Hook with Pause Capability

**Function:** Allows pausing message sending in case of emergency. Useful for maintenance or responding to security incidents.

**Instantiation Parameters:**
```json
{
  "owner": "terra10d07y265gmmuvt4z0w9aw880jnsr700juxf95n",
  "paused": false
}
```

**Parameter Explanation:**
- `owner` (string): Address that can pause/unpause
- `paused` (boolean): Initial state (false = not paused, true = paused)

**Code ID:** `1991`

**Instantiated Address:**
- **Address**: `terra1j04kamuwssgckj7592w5v3hlttmlqlu9cqkzvvxsjt8rqyt3stps0xan5l`
- **Hexed**: `93eb6eef8e84118b4bd42a9d4646ff5af7f07f85c02c2630d092ce30117182c3`

---

#### 11. 💰 HOOK FEE - Fixed Fee Charging Hook

**Function:** Charges a fixed fee per message sent. Can be used for:
- Protocol monetization
- Spam prevention
- Operations funding

**Instantiation Parameters:**
```json
{
  "owner": "terra10d07y265gmmuvt4z0w9aw880jnsr700juxf95n",
  "fee": {
    "denom": "uluna",
    "amount": "283215"
  }
}
```

**Parameter Explanation:**
- `owner` (string): Contract admin
- `fee` (object): Fee configuration
  - `denom` (string): Token denomination (micro-luna = uluna)
  - `amount` (string): Fee amount (283215 uluna = 0.283215 LUNC)

**Note:** Fee of 0.283215 LUNC per message sent.

**Code ID:** `1989`

**Instantiated Address:**
- **Address**: `terra13y6vseryqqj09uu9aagk8xks4dr9fr2p0xr3w6gngdzjd362h54sz5fr3j`
- **Hexed**: `8934c864640024f2f385ef51639ad0ab46548d417987176913434526c74abd2b`

---

#### 12. 🔗 HOOK AGGREGATE #2 - Aggregator (Pausable + Fee)

**Function:** Second aggregator that combines:
- **Hook Pausable**: allows pausing message sending
- **Hook Fee**: charges fee per message

**Instantiation Parameters:**
```json
{
  "owner": "terra10d07y265gmmuvt4z0w9aw880jnsr700juxf95n",
  "hooks": [
    "terra1j04kamuwssgckj7592w5v3hlttmlqlu9cqkzvvxsjt8rqyt3stps0xan5l",
    "terra13y6vseryqqj09uu9aagk8xks4dr9fr2p0xr3w6gngdzjd362h54sz5fr3j"
  ]
}
```

**Parameter Explanation:**
- `owner` (string): Contract admin
- `hooks` (array): List of hooks
  - Hook 1: Pausable
  - Hook 2: Fee

**Note:** This hook will be set as `required_hook` in the Mailbox.

**Code ID:** `1988`

**Instantiated Address:**
- **Address**: `terra1xdpah0ven023jzd80qw0nkp4ndjxy4d7g5y99dhpfwetyal6q6jqpk42rj`
- **Hexed**: `3343dbbd999bd51909a7781cf9d8359b646255be450852b6e14bb2b277fa06a4`

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
    │  - ISM Multisig   │         │  - Fee              │
    │    (domain 97)    │         │                     │
    │  - ISM Multisig   │         │  Default Hook:      │
    │    (domain        │         │  - Merkle           │
    │    1399811150)    │         │  - IGP ──► Oracle   │
    └───────────────────┘         └─────────────────────┘
```

**Send Flow:**
1. User calls `dispatch()` on Mailbox
2. **Required Hook** is executed (Pausable checks if not paused, Fee charges fee)
3. **Default Hook** is executed (Merkle registers, IGP processes payment via Oracle)
4. Message is emitted as event

**Receive Flow:**
1. Relayer submits message + metadata
2. Mailbox queries **Default ISM** (ISM Routing)
3. ISM Routing directs to appropriate **ISM Multisig** (BSC or Solana)
4. ISM Multisig validates signatures (configured threshold)
5. If valid, message is processed

> **🔒 IMPORTANT - Governance Module:**
> 
> The address `terra10d07y265gmmuvt4z0w9aw880jnsr700juxf95n` is the **governance module** of the blockchain.
> 
> **Security Implications:**
> - ✅ **After instantiation**, only governance can change configurations
> - ✅ **No individual person** has control of contracts
> - ✅ **All changes** must pass community voting
> - ✅ **Decentralization guaranteed** from the first moment
> - 🔐 **Contracts are immutable** except through approved governance proposals

---

## 4️⃣ Configuration via Governance

### Script: `submit-proposal-testnet.ts`

After instantiation, contracts need to be configured. Since the **owner/admin is the governance module**, all configurations must be done through **governance proposals**.

### 📝 Execution Messages - Detailed Explanation

The governance proposal executes **7 messages** to configure the Hyperlane system with support for **2 chains** (BSC Testnet and Solana Testnet):

---

#### MESSAGE 1: Configure ISM Multisig Validators for BSC Testnet

**Objective:** Defines the set of validators that will sign messages from domain 97 (BSC Testnet). A threshold of 2 means at least 2 of 3 validators must sign for a message to be considered valid.

**Target Contract:** ISM Multisig (`terra1rrt0kepmazvavmkusvz6589l5yg4mqjk49netqfqttnmf2y4exmqxhp0hv`)

**Executed Message:**
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

**Parameter Explanation:**
- `domain` (u32): BSC Testnet domain ID in Hyperlane protocol (97 = BSC Testnet)
- `threshold` (u8): Minimum number of signatures required (2 of 3 validators)
- `validators` (array of HexBinary): Array of 3 hexadecimal addresses (20 bytes each) of validators

**Security:** With threshold 2/3, the system tolerates up to 1 validator offline or malicious while still validating messages.

---

#### MESSAGE 2: Configure ISM Multisig Validators for Solana Testnet

**Objective:** Defines the set of validators that will sign messages from domain 1399811150 (Solana Testnet). A threshold of 1 means at least 1 of 1 validators must sign for a message to be considered valid.

**Target Contract:** ISM Multisig (`terra1d7a52pxu309jcgv8grck7jpgwlfw7cy0zen9u42rqdr39tef9g7qc8gp4a`)

**Executed Message:**
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

**Parameter Explanation:**
- `domain` (u32): Solana Testnet domain ID in Hyperlane protocol (1399811150 = Solana Testnet)
- `threshold` (u8): Minimum number of signatures required (1 of 1 validators)
- `validators` (array of HexBinary): Array of 1 hexadecimal address (20 bytes) of validator

---

#### MESSAGE 3: Configure Remote Gas Data in IGP Oracle (BSC and Solana Testnet)

**Objective:** Defines token exchange rate and gas price for domains 97 (BSC Testnet) and 1399811150 (Solana Testnet). This allows IGP to calculate how much gas to charge on the source chain (Terra) to cover execution costs on destination chains.

**Target Contract:** IGP Oracle (`terra18tyqe79yktac6p3alv3f49k06xqna2q52twyaflrz55qka9emhrs30k3hg`)

**Executed Message:**
```json
{
  "set_remote_gas_data_configs": {
    "configs": [
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

**Parameter Explanation:**
- `remote_domain` (u32): Remote chain domain ID
  - Domain 97 = BSC Testnet
  - Domain 1399811150 = Solana Testnet
- `token_exchange_rate` (Uint128): Exchange rate between LUNC and destination chain token
- `gas_price` (Uint128): Gas price on destination chain

---

#### MESSAGE 4: Define IGP Routes to Oracle (BSC and Solana Testnet)

**Objective:** Configures IGP to use IGP Oracle when calculating gas costs for domains 97 (BSC Testnet) and 1399811150 (Solana Testnet). These routes connect IGP to the Oracle that provides updated price and exchange rate data.

**Target Contract:** IGP (`terra1n70g3vg7xge6q8m44rudm4y6fm6elpspwsgfmfphs3teezpak6cs6wxlk9`)

**Executed Message:**
```json
{
  "router": {
    "set_routes": {
      "set": [
        {
          "domain": 97,
          "route": "terra18tyqe79yktac6p3alv3f49k06xqna2q52twyaflrz55qka9emhrs30k3hg"
        },
        {
          "domain": 1399811150,
          "route": "terra18tyqe79yktac6p3alv3f49k06xqna2q52twyaflrz55qka9emhrs30k3hg"
        }
      ]
    }
  }
}
```

---

#### MESSAGE 5: Define Default ISM in Mailbox

**Objective:** Configures the default ISM (Interchain Security Module) that will be used by the Mailbox to validate received messages. ISM Routing allows using different validation strategies per origin domain.

**Target Contract:** Mailbox (`terra1rqg3qfkfg5upad9xu6zj5jhl626qy053s7rn08829rgqzv2wu39s5la8yf`)

**Executed Message:**
```json
{
  "set_default_ism": {
    "ism": "terra1h4sd8fyxhde7dc9w9y9zhc2epphgs75q7zzfg3tfynm8qvpe3jlsd7sauh"
  }
}
```

---

#### MESSAGE 6: Define Default Hook in Mailbox

**Objective:** Configures the default hook that will be executed when sending messages. Hook Aggregate #1 combines Merkle Tree Hook (for proofs) and IGP (for payment).

**Target Contract:** Mailbox (`terra1rqg3qfkfg5upad9xu6zj5jhl626qy053s7rn08829rgqzv2wu39s5la8yf`)

**Executed Message:**
```json
{
  "set_default_hook": {
    "hook": "terra14qjm9075m8djus4tl86lc5n2xnsvuazesl52vqyuz6pmaj4k5s5qu5q6jh"
  }
}
```

---

#### MESSAGE 7: Define Required Hook in Mailbox

**Objective:** Configures the mandatory hook that will ALWAYS be executed when sending messages, regardless of custom hooks specified by the sender. Hook Aggregate #2 combines Hook Pausable (emergency) and Hook Fee (monetization).

**Target Contract:** Mailbox (`terra1rqg3qfkfg5upad9xu6zj5jhl626qy053s7rn08829rgqzv2wu39s5la8yf`)

**Executed Message:**
```json
{
  "set_required_hook": {
    "hook": "terra1xdpah0ven023jzd80qw0nkp4ndjxy4d7g5y99dhpfwetyal6q6jqpk42rj"
  }
}
```

---

### 📊 Proposal 162 - Status and Details

The configuration proposal was submitted and approved successfully:

**Proposal ID:** `162`

**Status:** `PROPOSAL_STATUS_PASSED`

**Votes:**
- **Yes**: `82020035955749071`
- **No**: `0`
- **Abstentions**: `0`
- **Veto**: `0`

**Timestamps:**
- **Submitted**: `2025-12-01T17:16:48.606969070Z`
- **Deposit End**: `2025-12-04T17:16:48.606969070Z`
- **Voting Start**: `2025-12-01T17:16:48.606969070Z`
- **Voting End**: `2025-12-02T05:16:48.606969070Z`

**Title:** `Hyperlane Contracts Configuration - Testnet Multi-Chain`

**Summary:** `Proposal to configure Hyperlane contracts for BSC Testnet and Solana Testnet: set ISM validators (BSC 2/3, Solana 1/1), configure IGP Oracle for testnet chains, set IGP routes, configure default ISM and hooks (default and required) in Mailbox`

**Proposer:** `terra12awgqgwm2evj05ndtgs0xa35uunlpc76d85pze`

**Total Deposit:** `10000000 uluna`

---

## 5️⃣ Execution Verification

### Queries to Verify Configurations

After the proposal is approved (`PROPOSAL_STATUS_PASSED`), verify that configurations were applied.

#### 1. ✅ ISM Multisig BSC - Validators Configured

**What it verifies:** Confirms that 3 validators were registered in ISM Multisig for domain 97 (BSC Testnet) with threshold of 2 signatures.

**Query:**
```bash
terrad query wasm contract-state smart terra1rrt0kepmazvavmkusvz6589l5yg4mqjk49netqfqttnmf2y4exmqxhp0hv \
  '{"multisig_ism":{"enrolled_validators":{"domain":97}}}' \
  --node https://rpc.luncblaze.com:443 \
  --chain-id rebel-2
```

**Expected:**
```yaml
data:
  threshold: 2                              # Minimum of 2 signatures required
  validators:                               # List of 3 validators (hex addresses 20 bytes)
  - 242d8a855a8c932dec51f7999ae7d1e48b10c95e  # Validator 1
  - f620f5e3d25a3ae848fec74bccae5de3edcd8796  # Validator 2
  - 1f030345963c54ff8229720dd3a711c15c554aeb  # Validator 3
```

---

#### 2. ✅ ISM Multisig Solana - Validators Configured

**What it verifies:** Confirms that the validator was registered in ISM Multisig for domain 1399811150 (Solana Testnet) with threshold of 1 signature.

**Query:**
```bash
terrad query wasm contract-state smart terra1d7a52pxu309jcgv8grck7jpgwlfw7cy0zen9u42rqdr39tef9g7qc8gp4a \
  '{"multisig_ism":{"enrolled_validators":{"domain":1399811150}}}' \
  --node https://rpc.luncblaze.com:443 \
  --chain-id rebel-2
```

---

#### 3. ✅ IGP Oracle - Gas Price Configured

**What it verifies:** Confirms that the Oracle has gas price and exchange rate data configured for BSC Testnet (domain 97) and Solana Testnet (domain 1399811150).

**Query:**
```bash
# For BSC Testnet
terrad query wasm contract-state smart terra18tyqe79yktac6p3alv3f49k06xqna2q52twyaflrz55qka9emhrs30k3hg \
  '{"oracle":{"get_exchange_rate_and_gas_price":{"dest_domain":97}}}' \
  --node https://rpc.luncblaze.com:443 \
  --chain-id rebel-2

# For Solana Testnet
terrad query wasm contract-state smart terra18tyqe79yktac6p3alv3f49k06xqna2q52twyaflrz55qka9emhrs30k3hg \
  '{"oracle":{"get_exchange_rate_and_gas_price":{"dest_domain":1399811150}}}' \
  --node https://rpc.luncblaze.com:443 \
  --chain-id rebel-2
```

---

#### 4. ✅ IGP - Route Configured

**What it verifies:** Confirms that IGP has routes configured pointing to the Oracle.

**Query:**
```bash
# For BSC Testnet
terrad query wasm contract-state smart terra1n70g3vg7xge6q8m44rudm4y6fm6elpspwsgfmfphs3teezpak6cs6wxlk9 \
  '{"router":{"get_route":{"domain":97}}}' \
  --node https://rpc.luncblaze.com:443 \
  --chain-id rebel-2

# For Solana Testnet
terrad query wasm contract-state smart terra1n70g3vg7xge6q8m44rudm4y6fm6elpspwsgfmfphs3teezpak6cs6wxlk9 \
  '{"router":{"get_route":{"domain":1399811150}}}' \
  --node https://rpc.luncblaze.com:443 \
  --chain-id rebel-2
```

---

#### 5. ✅ Mailbox - Default ISM

**What it verifies:** Confirms that the Mailbox has an ISM configured to validate received messages.

**Query:**
```bash
terrad query wasm contract-state smart terra1rqg3qfkfg5upad9xu6zj5jhl626qy053s7rn08829rgqzv2wu39s5la8yf \
  '{"mailbox":{"default_ism":{}}}' \
  --node https://rpc.luncblaze.com:443 \
  --chain-id rebel-2
```

**Expected:**
```yaml
data:
  default_ism: terra1h4sd8fyxhde7dc9w9y9zhc2epphgs75q7zzfg3tfynm8qvpe3jlsd7sauh  # ISM Routing address
```

---

#### 6. ✅ Mailbox - Default Hook

**What it verifies:** Confirms that the Mailbox has a hook configured to process message sends.

**Query:**
```bash
terrad query wasm contract-state smart terra1rqg3qfkfg5upad9xu6zj5jhl626qy053s7rn08829rgqzv2wu39s5la8yf \
  '{"mailbox":{"default_hook":{}}}' \
  --node https://rpc.luncblaze.com:443 \
  --chain-id rebel-2
```

**Expected:**
```yaml
data:
  default_hook: terra14qjm9075m8djus4tl86lc5n2xnsvuazesl52vqyuz6pmaj4k5s5qu5q6jh  # Hook Aggregate #1 address
```

---

#### 7. ✅ Mailbox - Required Hook

**What it verifies:** Confirms that the Mailbox has a mandatory hook that will ALWAYS be executed when sending messages.

**Query:**
```bash
terrad query wasm contract-state smart terra1rqg3qfkfg5upad9xu6zj5jhl626qy053s7rn08829rgqzv2wu39s5la8yf \
  '{"mailbox":{"required_hook":{}}}' \
  --node https://rpc.luncblaze.com:443 \
  --chain-id rebel-2
```

**Expected:**
```yaml
data:
  required_hook: terra1xdpah0ven023jzd80qw0nkp4ndjxy4d7g5y99dhpfwetyal6q6jqpk42rj  # Hook Aggregate #2 address
```

---

### Complete Verification Script

Use the `query-proposal-status.ts` script for automated verification:

```bash
npx tsx script/query-proposal-status.ts 162
```

This script automatically verifies all configurations above.

---

## 6️⃣ Contract Addresses and Hexed

### Address Table

| Contract | Address (Bech32) | Hexed (32 bytes) |
|----------|-------------------|------------------|
| **Mailbox** | `terra1rqg3qfkfg5upad9xu6zj5jhl626qy053s7rn08829rgqzv2wu39s5la8yf` | `18111026c945381eb4a6e6852a4affd2b4023e918787379cea28d001314ee44b` |
| **Validator Announce** | `terra10szy9ppjpgt8xk3tkywu3dhss8s5scsga85f4cgh452p6mwd092qdzfyup` | `7c044284320a16735a2bb11dc8b6f081e1486208e9e89ae117ad141d6dcd7954` |
| **ISM Multisig BSC** | `terra1rrt0kepmazvavmkusvz6589l5yg4mqjk49netqfqttnmf2y4exmqxhp0hv` | `18d6fb643be899d66edc8305aa1cbfa1115d8256a9679581205ae7b4a895c9b6` |
| **ISM Multisig Solana** | `terra1d7a52pxu309jcgv8grck7jpgwlfw7cy0zen9u42rqdr39tef9g7qc8gp4a` | `6fbb4504dc8bcb2c218740f16f482877d2ef608f16665e5543034712af292a3c` |
| **ISM Routing** | `terra1h4sd8fyxhde7dc9w9y9zhc2epphgs75q7zzfg3tfynm8qvpe3jlsd7sauh` | `bd60d3a486bb73e6e0ae290a2be159086e887a80f08494456924f67030398cbf` |
| **Hook Merkle** | `terra1x9ftmmyj0t9n0ql78r2vdfk9stxg5z6vnwnwjym9m7py6lvxz8ls7sa3df` | `3152bdec927acb3783fe38d4c6a6c582cc8a0b4c9ba6e91365df824d7d8611ff` |
| **IGP** | `terra1n70g3vg7xge6q8m44rudm4y6fm6elpspwsgfmfphs3teezpak6cs6wxlk9` | `9f9e88b11e3233a01f75a8f8ddd49a4ef59f860174109da43784579c883db6b1` |
| **IGP Oracle** | `terra18tyqe79yktac6p3alv3f49k06xqna2q52twyaflrz55qka9emhrs30k3hg` | `3ac80cf8a4b2fb8d063dfb229a96cfd1813ea81452dc4ea7e315280b74b9ddc7` |
| **Hook Aggregate 1** | `terra14qjm9075m8djus4tl86lc5n2xnsvuazesl52vqyuz6pmaj4k5s5qu5q6jh` | `a825b2bfd4d9db2e42abf9f5fc526a34e0ce745987e8a6009c1683becab6a428` |
| **Hook Pausable** | `terra1j04kamuwssgckj7592w5v3hlttmlqlu9cqkzvvxsjt8rqyt3stps0xan5l` | `93eb6eef8e84118b4bd42a9d4646ff5af7f07f85c02c2630d092ce30117182c3` |
| **Hook Fee** | `terra13y6vseryqqj09uu9aagk8xks4dr9fr2p0xr3w6gngdzjd362h54sz5fr3j` | `8934c864640024f2f385ef51639ad0ab46548d417987176913434526c74abd2b` |
| **Hook Aggregate 2** | `terra1xdpah0ven023jzd80qw0nkp4ndjxy4d7g5y99dhpfwetyal6q6jqpk42rj` | `3343dbbd999bd51909a7781cf9d8359b646255be450852b6e14bb2b277fa06a4` |

### Complete JSON

```json
{
  "hpl_mailbox": "terra1rqg3qfkfg5upad9xu6zj5jhl626qy053s7rn08829rgqzv2wu39s5la8yf",
  "hpl_validator_announce": "terra10szy9ppjpgt8xk3tkywu3dhss8s5scsga85f4cgh452p6mwd092qdzfyup",
  "hpl_ism_multisig_bsc": "terra1rrt0kepmazvavmkusvz6589l5yg4mqjk49netqfqttnmf2y4exmqxhp0hv",
  "hpl_ism_multisig_sol": "terra1d7a52pxu309jcgv8grck7jpgwlfw7cy0zen9u42rqdr39tef9g7qc8gp4a",
  "hpl_ism_routing": "terra1h4sd8fyxhde7dc9w9y9zhc2epphgs75q7zzfg3tfynm8qvpe3jlsd7sauh",
  "hpl_hook_merkle": "terra1x9ftmmyj0t9n0ql78r2vdfk9stxg5z6vnwnwjym9m7py6lvxz8ls7sa3df",
  "hpl_igp": "terra1n70g3vg7xge6q8m44rudm4y6fm6elpspwsgfmfphs3teezpak6cs6wxlk9",
  "hpl_igp_oracle": "terra18tyqe79yktac6p3alv3f49k06xqna2q52twyaflrz55qka9emhrs30k3hg",
  "hpl_hook_aggregate_default": "terra14qjm9075m8djus4tl86lc5n2xnsvuazesl52vqyuz6pmaj4k5s5qu5q6jh",
  "hpl_hook_pausable": "terra1j04kamuwssgckj7592w5v3hlttmlqlu9cqkzvvxsjt8rqyt3stps0xan5l",
  "hpl_hook_fee": "terra13y6vseryqqj09uu9aagk8xks4dr9fr2p0xr3w6gngdzjd362h54sz5fr3j",
  "hpl_hook_aggregate_required": "terra1xdpah0ven023jzd80qw0nkp4ndjxy4d7g5y99dhpfwetyal6q6jqpk42rj"
}
```

### Address Usage

**For Relayer:**
```yaml
mailbox: "0x18111026c945381eb4a6e6852a4affd2b4023e918787379cea28d001314ee44b"
validatorAnnounce: "0x7c044284320a16735a2bb11dc8b6f081e1486208e9e89ae117ad141d6dcd7954"
```

**For Validators:**
```yaml
mailbox: "0x18111026c945381eb4a6e6852a4affd2b4023e918787379cea28d001314ee44b"
merkleTreeHook: "0x3152bdec927acb3783fe38d4c6a6c582cc8a0b4c9ba6e91365df824d7d8611ff"
```

**For Warp Routes (interchainSecurityModule / messageIdMultisigIsm):**

The hex addresses of ISM Multisig contracts are used when you need to reference `interchainSecurityModule` in Warp Route configurations:

**BSC Testnet (Domain 97):**
```yaml
interchainSecurityModule:
  type: messageIdMultisigIsm
  # The hex address of ISM Multisig BSC is:
  address: "0x18d6fb643be899d66edc8305aa1cbfa1115d8256a9679581205ae7b4a895c9b6"
  # Or use configuration with validators:
  validators:
    - "242d8a855a8c932dec51f7999ae7d1e48b10c95e"
    - "f620f5e3d25a3ae848fec74bccae5de3edcd8796"
    - "1f030345963c54ff8229720dd3a711c15c554aeb"
  threshold: 2
```

**Solana Testnet (Domain 1399811150):**
```yaml
interchainSecurityModule:
  type: messageIdMultisigIsm
  # The hex address of ISM Multisig Solana is:
  address: "0x6fbb4504dc8bcb2c218740f16f482877d2ef608f16665e5543034712af292a3c"
  # Or use configuration with validators:
  validators:
    - "d4ce8fa138d4e083fc0e480cca0dbfa4f5f30bd5"
  threshold: 1
```

**Note:** In Warp Route configurations, you typically specify `validators` and `threshold` directly, and the Hyperlane CLI creates or references the appropriate ISM. The hex address above is the address of the ISM Multisig contract instantiated on Terra Classic Testnet.

---

## 7️⃣ Troubleshooting

### Error: "insufficient fees"

**Problem:** Gas fee too low.

**Solution:** Increase gas price:
```bash
--gas-prices 28.5uluna
--gas-adjustment 2.0
```

### Error: "out of gas"

**Problem:** Estimated gas limit too low.

**Solution:** Use fixed gas or increase adjustment:
```bash
--gas 1000000
# or
--gas-adjustment 2.5
```

### Error: "contract not found"

**Problem:** Contract was not instantiated or address is incorrect.

**Solution:** Verify the address:
```bash
terrad query wasm contract <ADDRESS> \
  --node https://rpc.luncblaze.com:443 \
  --chain-id rebel-2
```

### Proposal does not execute automatically

**Problem:** Voting period has not ended yet.

**Solution:** Wait for `voting_end_time`:
```bash
terrad query gov proposal 162 \
  --node https://rpc.luncblaze.com:443 \
  --chain-id rebel-2 | grep voting_end_time
```

### Query returns schema error

**Problem:** Incorrect query for the contract.

**Solution:** Use queries documented in the [Execution Verification](#5️⃣-execution-verification) section.

---

## 📚 Additional Resources

### Official Documentation

- [Hyperlane Docs](https://docs.hyperlane.xyz/)
- [Terra Classic Docs](https://docs.terra.money/)
- [CosmWasm Docs](https://docs.cosmwasm.com/)

### Repository and Releases

- **GitHub Repository**: https://github.com/many-things/cw-hyperlane
- **Releases**: https://github.com/many-things/cw-hyperlane/releases
- **Latest Release (v0.0.6-rc8)**:
  - Tag: https://github.com/many-things/cw-hyperlane/releases/tag/v0.0.6-rc8
  - Download: https://github.com/many-things/cw-hyperlane/releases/download/v0.0.6-rc8/cw-hyperlane-v0.0.6-rc8.zip
  - Checksums: Included in ZIP file

### Configuration Files

- `script/CustomInstantiateWasm-testnet.ts` - Instantiation script (testnet)
- `script/submit-proposal-testnet.ts` - Governance configuration script (testnet)
- `script/query-proposal-status.ts` - Proposal verification script
- `config.yaml` - Network configuration
- `context/terraclassic.json` - Deployment context

### Useful Scripts

```bash
# List available contracts
yarn cw-hpl upload remote-list -n terraclassic

# Upload contracts
yarn cw-hpl upload remote v0.0.6-rc8 -n terraclassic

# Instantiate contracts (testnet)
yarn tsx script/CustomInstantiateWasm-testnet.ts

# Create governance proposal (testnet)
yarn tsx script/submit-proposal-testnet.ts

# Verify proposal status
npx tsx script/query-proposal-status.ts 162
```

---

## ✅ Deployment Checklist

### Pre-Deployment
- [ ] Verify available contracts (`yarn cw-hpl upload remote-list`)
- [ ] Download and verify WASM checksums
- [ ] Confirm that admin/owner will be the governance module

### Deployment
- [ ] Upload contracts (`yarn cw-hpl upload remote`)
- [ ] Verify code IDs in `context/terraclassic.json`
- [ ] Instantiate contracts (`CustomInstantiateWasm-testnet.ts`)
- [ ] **CRITICAL**: Verify that owner is the governance module
- [ ] Save contract addresses

### Configuration
- [ ] Create configuration proposal (`submit-proposal-testnet.ts`)
- [ ] Vote on proposal (obtain quorum)
- [ ] Wait for proposal approval
- [ ] Verify that status = `PROPOSAL_STATUS_PASSED`
- [ ] Verify configurations applied (all queries or use script)

### Security Verification
- [ ] ✅ Confirm that all contracts have governance as owner
- [ ] ✅ Verify that no one can change contracts directly
- [ ] ✅ Validate contract hashes on blockchain
- [ ] ✅ Compare addresses with official documentation

### Post-Deployment
- [ ] Configure relayer with hexed addresses
- [ ] Configure validators
- [ ] Test message sending
- [ ] Document all addresses and code IDs
- [ ] Publish information for auditing

---

## 🔒 Security and Governance

### On-Chain Governance Model

Hyperlane contracts are **governed by the community** through Terra Classic's governance module:

#### Security Features

1. **Decentralized Control**
   - ✅ No single entity controls contracts
   - ✅ Admin/Owner = Governance Module
   - ✅ All changes require voting

2. **Change Process**
   ```
   Proposal → Voting Period → Approval → Automatic Execution
   ```

3. **Total Transparency**
   - 📊 All proposals are public
   - 🗳️ All votes are recorded on blockchain
   - 📝 Complete history of changes
   - 🔍 Auditable by anyone

4. **Protection Against Attacks**
   - 🛡️ Impossible to change contracts without community approval
   - 🛡️ Voting period allows analysis and discussion
   - 🛡️ Quorum and threshold prevent manipulation
   - 🛡️ Community veto for malicious proposals

### Ownership Verification

**Always verify** that contracts are under governance control:

```bash
# Verify owner of each contract
for contract in \
  terra1rqg3qfkfg5upad9xu6zj5jhl626qy053s7rn08829rgqzv2wu39s5la8yf \
  terra1rrt0kepmazvavmkusvz6589l5yg4mqjk49netqfqttnmf2y4exmqxhp0hv \
  terra1h4sd8fyxhde7dc9w9y9zhc2epphgs75q7zzfg3tfynm8qvpe3jlsd7sauh
do
  echo "Verifying: $contract"
  terrad query wasm contract-state smart $contract \
    '{"ownable":{"owner":{}}}' \
    --node https://rpc.luncblaze.com:443 \
    --chain-id rebel-2
done

# All should return:
# owner: terra10d07y265gmmuvt4z0w9aw880jnsr700juxf95n
```

### For Auditors

When auditing this deployment, verify:

1. ✅ **WASM Hashes** match official releases
2. ✅ **Owner/Admin** is the governance module
3. ✅ **Code IDs** are documented correctly
4. ✅ **Configurations** were applied via governance (Proposal 162)
5. ✅ **No backdoor** or privileged function beyond governance

---

## 📞 Support

For problems or questions:
1. Check execution logs
2. Consult troubleshooting above
3. Review official Hyperlane documentation
4. Verify contracts on blockchain using queries
5. Confirm that ownership is correct (governance module)
6. Use `query-proposal-status.ts` script for automated verification

---

**Last updated:** 2025-12-02  
**Contract Version:** v0.0.6-rc8  
**Chain:** Terra Classic Testnet (rebel-2)  
**RPC:** https://rpc.luncblaze.com  
**Governance:** Terra Classic On-Chain Governance  
**Admin/Owner:** `terra10d07y265gmmuvt4z0w9aw880jnsr700juxf95n` (Governance Module)  
**Configuration Proposal:** #162 (APPROVED)  
**Supported Chains:** BSC Testnet (Domain 97), Solana Testnet (Domain 1399811150)

