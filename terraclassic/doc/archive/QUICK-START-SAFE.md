# Quick Start Guide - Execute Safe Transaction

## ⚡ Quick Safe CLI Installation (Recommended)

Before using Python scripts, consider installing the official Node.js Safe CLI:

```bash
# Install official Safe CLI
npm install -g @safe-global/safe-cli

# Verify installation
safe --version

# Query Safe information (EIP-3770 format: shortName:address)
safe account info bnb:0xYOUR_SAFE

# List pending transactions
safe tx list bnb:0xYOUR_SAFE

# View transaction status
safe tx status <SAFE_TX_HASH>
```

**⚠️ IMPORTANT:** The Safe CLI uses EIP-3770 format (`shortName:address`), not `--address` or `--chain-id`.

**Common ShortNames:**
- BSC Mainnet (56): `bnb`
- BSC Testnet (97): `tbnb` (add with `safe config chains add`)
- Ethereum Mainnet (1): `eth`
- Sepolia Testnet (11155111): `sep`

**Add BSC Testnet:**
```bash
safe config chains add
# Enter: Chain ID: 97, Name: BSC Testnet, Short name: tbnb, RPC: https://data-seed-prebsc-1-s1.binance.org:8545
```

**Open Safe on BSC Testnet:**
```bash
safe account open tbnb:0xYOUR_SAFE --name "BSC Testnet Safe"
```

For more details, see the [Complete Safe CLI Guide](SAFE-SCRIPTS-GUIDE.md#-official-safe-cli-installation-recommended).

---

## 📝 Using Python Scripts (Alternative)

### 1. Check Signatures

```bash
python3 script/safe-check-signatures.py <SAFE_TX_HASH>
```

**Example:**
```bash
python3 script/safe-check-signatures.py 0x73b17378c1d8d5a48dd32dc483faa17aa6e23538ff5e68473f634b91cfe49367
```

**What it shows:**
- Required threshold
- How many approvals have been made
- Which owners approved
- If it's ready for execution

## 2. Execute Transaction

**⚠️ IMPORTANT: You need the original CALLDATA!**

```bash
python3 script/safe-execute-complete.py <PRIVATE_KEY> <CALLDATA> [SAFE_TX_HASH]
```

**Example:**
```bash
# If you have the CALLDATA
CALLDATA=0x3f4ba83a...
python3 script/safe-execute-complete.py \
  0x819b680e3578eac4f79b8fde643046e88f.... \
  $CALLDATA \
  0x73b17378c1d8d5a48dd32dc483faa17aa6e23538ff5e68473f634b91cfe49367
```

## Why do I need the CALLDATA?

The Safe TX Hash is just a **identifier** for the proposal. It does not contain:
- Destination address (to)
- Value
- Function data (data/calldata)

To execute, the Safe needs to reconstruct the transaction with the same data from the original proposal.

## If you don't have the CALLDATA

1. **Check the proposal history** - where you originally created the proposal
2. **Use the same CALLDATA** that you used in `safe-propose-direct.py`
3. **Or recreate the proposal** with the same data

## Script Summary

| Script | Usage |
|--------|-----|
| `safe-check-signatures.py` | Check how many signatures are needed |
| `safe-execute-complete.py` | Execute transaction (requires CALLDATA) |
| `safe-propose-direct.py` | Create new proposal |
| `safe-confirm.py` | Confirm existing proposal |
