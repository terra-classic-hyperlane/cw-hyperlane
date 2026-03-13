# 📚 Documentation Guide — Hyperlane Warp Routes Terra Classic

> **Index Document** — Quick guide to navigate the complete documentation for creating and using Warp Routes between Terra Classic ↔ EVM and Terra Classic ↔ Sealevel (Solana).

---

## 🚀 Quick Start

### 1. Installation and Setup

```bash
# 1. Clone the repository
git clone <repository-url>
cd cw-hyperlane

# 2. Install Node.js dependencies
yarn install

# 3. Configure private keys (optional, can be done during execution)
export TERRA_PRIVATE_KEY="your_hex_terra_key"
export ETH_PRIVATE_KEY="0x_your_hex_evm_key"
```

**Required dependencies:**
- `node` (≥ 16) — `node --version`
- `yarn` or `npm` — `yarn --version`
- `jq` — `sudo apt install jq`
- `curl` — usually already installed
- `python3` — usually already installed

### 2. Recommended First Steps

**If you're starting from scratch:**

1. **Read this document** (README.md) to understand the structure
2. **Choose your first use case:**
   - Terra Classic ↔ EVM (Sepolia/BSC)? → [`create-warp-evm-guide.md`](./create-warp-evm-guide.md)
   - Terra Classic ↔ Solana? → [`create-warp-sealevel-guide.md`](./create-warp-sealevel-guide.md)
3. **Follow the chosen guide step by step**
4. **Test with transfers** using the transfer guides

**If you already have Warp Routes created:**

1. Use [`transfer-remote-guide.md`](./transfer-remote-guide.md) to send tokens
2. Use [`transfer-remote-to-terra-guide.md`](./transfer-remote-to-terra-guide.md) to receive tokens
3. If you encounter "route not found" error, use [`enroll-terra-router-guide.md`](./enroll-terra-router-guide.md)

---

## 📖 Available Documents

### 🎯 **Main Documents (Complete Flow)**

#### 1. [`create-warp-evm-guide.md`](./create-warp-evm-guide.md)
**What it does:** Complete guide to create Warp Routes on **EVM** networks (Sepolia, BSC Testnet, etc.) connected to Terra Classic.

**When to use:**
- First time creating an EVM Warp Route
- Adding a new token to an EVM network
- Adding a new EVM network to the project

**What you'll do:**
1. Configure `warp-evm-config.json` and `config.yaml`
2. Run `./create-warp-evm.sh`
3. Automatic deployment of contracts (Mailbox, ISM, IGP, Warp Route)
4. Automatic configuration of hooks and bidirectional routes

**Estimated time:** 15-30 minutes per token/network

---

#### 2. [`create-warp-sealevel-guide.md`](./create-warp-sealevel-guide.md)
**What it does:** Complete guide to create Warp Routes on **Solana (Sealevel)** connected to Terra Classic.

**When to use:**
- First time creating a Solana Warp Route
- Adding a new token on Solana
- Migrating to Solana Mainnet

**What you'll do:**
1. Configure `warp-sealevel-config.json`
2. Prepare token metadata (JSON)
3. Run `./create-warp-sealevel.sh`
4. Automatic deployment of Solana programs (Warp, ISM, IGP)
5. Configuration of bidirectional routes

**Estimated time:** 20-40 minutes per token

---

#### 3. [`transfer-remote-guide.md`](./transfer-remote-guide.md)
**What it does:** Complete guide to send tokens from **Terra Classic → EVM/Sealevel**.

**When to use:**
- Send tokens from Terra Classic to Sepolia, BSC Testnet, or Solana
- Test transfers after creating Warp Routes
- Verify everything is configured correctly

**What you'll do:**
1. Configure `TERRA_PRIVATE_KEY`
2. Run `./transfer-remote-terra.sh`
3. Choose token and destination network (interactive or via variables)
4. Enter recipient address and amount
5. Confirm and send

**Estimated time:** 2-5 minutes per transfer

---

#### 4. [`transfer-remote-to-terra-guide.md`](./transfer-remote-to-terra-guide.md)
**What it does:** Complete guide to send tokens from **EVM/Sealevel → Terra Classic**.

**When to use:**
- Send tokens from Sepolia/BSC/Solana back to Terra Classic
- Test reverse flow after creating Warp Routes
- Verify token receipt on Terra Classic

**What you'll do:**
1. Configure `ETH_PRIVATE_KEY` (EVM) or Solana keypair
2. Run `./transfer-remote-to-terra.sh`
3. Choose token and source network
4. Enter Terra Classic recipient address
5. Confirm and send

**Estimated time:** 2-5 minutes per transfer

---

#### 5. [`enroll-terra-router-guide.md`](./enroll-terra-router-guide.md)
**What it does:** Guide to register EVM routes in the Terra Classic Warp contract (resolves "route not found" error).

**When to use:**
- `route not found` error when executing `transfer_remote`
- Deployment was done without `TERRA_PRIVATE_KEY` configured
- Adding a new EVM network to an existing token
- Preventive check before transferring

**What you'll do:**
1. Run `./enroll-terra-router.sh`
2. Choose token and EVM network
3. Confirm and execute `set_route` on Terra Classic contract

**Estimated time:** 1-2 minutes

---

### 🔧 **Support Documents**

#### 6. [`HYPERLANE_DEPLOYMENT-TESTNET.md`](./HYPERLANE_DEPLOYMENT-TESTNET.md)
**What it does:** Technical documentation about Hyperlane contract deployment on testnets.

**When to use:**
- Understand Hyperlane contract architecture
- Manual contract deployment (without scripts)
- Advanced troubleshooting

---

#### 7. [`submit-proposal-guide.md`](./submit-proposal-guide.md)
**What it does:** Guide to create and submit governance proposals on Terra Classic.

**When to use:**
- Update configurations via governance
- Modify parameters of deployed contracts
- Advanced administrative operations

---

#### 8. [`UPDATE-IGP-ORACLE-GOVERNANCE.md`](./UPDATE-IGP-ORACLE-GOVERNANCE.md)
**What it does:** Specific guide to update the IGP Oracle via governance.

**When to use:**
- Update IGP gas rates
- Modify exchange rates
- Gas paymaster system maintenance

---

### 🛡️ **Security Documents**

#### 9. [`SAFE-SCRIPTS-GUIDE.md`](./SAFE-SCRIPTS-GUIDE.md)
**What it does:** Guide to use scripts with Safe (multisig) for secure operations.

**When to use:**
- Production operations
- Requiring multiple signatures
- Critical infrastructure operations

---

#### 10. [`QUICK-START-SAFE.md`](./QUICK-START-SAFE.md)
**What it does:** Quick start to configure Safe multisig.

**When to use:**
- First Safe configuration
- Quick multisig setup for testing

---

#### 11. [`README-SAFE-EXECUTE.md`](./README-SAFE-EXECUTE.md)
**What it does:** Documentation about executing transactions via Safe.

**When to use:**
- Execute multisig transactions
- Understand Safe approval flow

---

## 🔄 Complete Workflow

### Scenario 1: Create EVM Warp Route (Terra Classic ↔ Sepolia)

```
1. Installation
   └─ yarn install

2. Configuration
   ├─ Edit warp-evm-config.json (add token/network)
   └─ Edit config.yaml (gas prices, owner, etc.)

3. Deployment
   └─ ./create-warp-evm.sh
      ├─ Deploy EVM Warp Route
      ├─ Deploy Custom IGP
      ├─ Configure AggregationHook
      └─ Register route on Terra Classic (set_route)

4. Testing
   ├─ Terra → EVM: ./transfer-remote-terra.sh
   └─ EVM → Terra: ./transfer-remote-to-terra.sh
```

**Required documents:**
- [`create-warp-evm-guide.md`](./create-warp-evm-guide.md) — Steps 1-3
- [`transfer-remote-guide.md`](./transfer-remote-guide.md) — Step 4 (Terra → EVM)
- [`transfer-remote-to-terra-guide.md`](./transfer-remote-to-terra-guide.md) — Step 4 (EVM → Terra)

---

### Scenario 2: Create Sealevel Warp Route (Terra Classic ↔ Solana)

```
1. Installation
   └─ yarn install

2. Configuration
   ├─ Edit warp-sealevel-config.json
   ├─ Create token metadata JSON
   └─ Configure Solana keypair

3. Deployment
   └─ ./create-warp-sealevel.sh
      ├─ Deploy Solana Warp Program
      ├─ Deploy ISM and IGP
      └─ Register bidirectional routes

4. Testing
   ├─ Terra → Solana: ./transfer-remote-terra.sh
   └─ Solana → Terra: ./transfer-remote-to-terra.sh
```

**Required documents:**
- [`create-warp-sealevel-guide.md`](./create-warp-sealevel-guide.md) — Steps 1-3
- [`transfer-remote-guide.md`](./transfer-remote-guide.md) — Step 4 (Terra → Solana)
- [`transfer-remote-to-terra-guide.md`](./transfer-remote-to-terra-guide.md) — Step 4 (Solana → Terra)

---

### Scenario 3: Resolve "route not found" Error

```
1. Identify problem
   └─ transfer_remote fails with "route not found"

2. Verify configuration
   └─ Check if route exists on Terra Classic

3. Register route
   └─ ./enroll-terra-router.sh
      └─ Executes set_route on Terra Classic contract

4. Test again
   └─ ./transfer-remote-terra.sh
```

**Required documents:**
- [`enroll-terra-router-guide.md`](./enroll-terra-router-guide.md)

---

## 📁 Important File Structure

```
terraclassic/
├── doc/                          ← You are here
│   ├── README.md                 ← This document (index)
│   ├── create-warp-evm-guide.md
│   ├── create-warp-sealevel-guide.md
│   ├── transfer-remote-guide.md
│   ├── transfer-remote-to-terra-guide.md
│   └── enroll-terra-router-guide.md
│
├── create-warp-evm.sh            ← Main EVM script
├── create-warp-sealevel.sh       ← Main Solana script
├── transfer-remote-terra.sh      ← Send Terra → Others
├── transfer-remote-to-terra.sh   ← Send Others → Terra
├── enroll-terra-router.sh        ← Register routes
│
├── warp-evm-config.json          ← EVM config + Terra tokens
├── warp-sealevel-config.json     ← Solana config
└── config.yaml                   ← Terra Classic config (gas, owner, etc.)
```

---

## 🎯 Quick Decision: Which Document to Use?

| Situation | Document |
|----------|----------|
| First time creating EVM Warp Route | [`create-warp-evm-guide.md`](./create-warp-evm-guide.md) |
| First time creating Solana Warp Route | [`create-warp-sealevel-guide.md`](./create-warp-sealevel-guide.md) |
| Send tokens Terra → EVM/Solana | [`transfer-remote-guide.md`](./transfer-remote-guide.md) |
| Send tokens EVM/Solana → Terra | [`transfer-remote-to-terra-guide.md`](./transfer-remote-to-terra-guide.md) |
| "route not found" error | [`enroll-terra-router-guide.md`](./enroll-terra-router-guide.md) |
| Understand Hyperlane architecture | [`HYPERLANE_DEPLOYMENT-TESTNET.md`](./HYPERLANE_DEPLOYMENT-TESTNET.md) |
| Operations via governance | [`submit-proposal-guide.md`](./submit-proposal-guide.md) |
| Use Safe multisig | [`SAFE-SCRIPTS-GUIDE.md`](./SAFE-SCRIPTS-GUIDE.md) |

---

## ⚠️ Quick Troubleshooting

### Error: "route not found"
→ Use [`enroll-terra-router-guide.md`](./enroll-terra-router-guide.md)

### Error: "insufficient fees"
→ Check `gasPrice` in `config.yaml` (should be `28.325uluna`)

### Error: "insufficient balance"
→ Verify you have tokens in your wallet before transferring

### Error: "node_modules not found"
→ Run `yarn install` at the project root

### Script can't find configuration
→ Verify that `warp-evm-config.json` or `warp-sealevel-config.json` exist and are correct

---

## 📞 Next Steps

1. **If it's your first time:** Start with [`create-warp-evm-guide.md`](./create-warp-evm-guide.md) or [`create-warp-sealevel-guide.md`](./create-warp-sealevel-guide.md)

2. **If you already have Warp Routes created:** Use [`transfer-remote-guide.md`](./transfer-remote-guide.md) to test transfers

3. **If you're having issues:** Check the Troubleshooting section of each specific guide

---

## 📝 Important Notes

- **All scripts are interactive** — you can run without parameters and choose options
- **Non-interactive mode available** — use environment variables for automation
- **Logs saved automatically** — in `terraclassic/log/`
- **Centralized configurations** — everything in easy-to-edit JSON/YAML files

---

**Last updated:** 2026-03-13  
**Version:** 1.0
