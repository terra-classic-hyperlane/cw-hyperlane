# How to Execute Safe Transactions

## Available Scripts

### 1. `safe-execute-complete.py` - Execute with CALLDATA

**Usage:**
```bash
python3 script/safe-execute-complete.py <PRIVATE_KEY> <CALLDATA> [SAFE_TX_HASH]
```

**Example:**
```bash
# With CALLDATA only
python3 script/safe-execute-complete.py \
  0x819b680e3578eac4f79b8fde643046e88f.... \
  0x3f4ba83a...

# With CALLDATA and Safe TX Hash (for validation)
python3 script/safe-execute-complete.py \
  0x819b680e3578eac4f79b8fde643046e88f.... \
  0x3f4ba83a... \
  0x73b17378c1d8d5a48dd32dc483faa17aa6e23538ff5e68473f634b91cfe49367
```

**What it does:**
- Reconstructs the Safe transaction using the CALLDATA
- Verifies approvals and threshold
- Attempts to execute using SafeTx execute() method
- If it fails, tries alternative approach with formatted signatures

### 2. `safe-execute-by-hash.py` - Execute using Safe TX Hash

**Usage:**
```bash
python3 script/safe-execute-by-hash.py <PRIVATE_KEY> <SAFE_TX_HASH>
```

**Limitation:**
- The Safe TX Hash does not contain the transaction data
- You still need the original CALLDATA
- Use `safe-execute-complete.py` instead

## Complete Flow

1. **Create Proposal:**
```bash
CALLDATA=$(cast calldata "setInterchainSecurityModule(address)" 0xNEW_ISM)
python3 script/safe-propose-direct.py 0xPRIVATE_KEY 0xCONTRACT $CALLDATA
# Save the returned Safe TX Hash
```

2. **Confirm (other owners):**
```bash
python3 script/safe-confirm.py 0xOWNER_PRIVATE_KEY <SAFE_TX_HASH>
```

3. **Execute:**
```bash
python3 script/safe-execute-complete.py 0xPRIVATE_KEY $CALLDATA [SAFE_TX_HASH]
```

## Troubleshooting

### GS013 Error
- Verify if the Safe has sufficient BNB
- Verify if all required signatures are present
- The script tries two approaches automatically

### Safe-cli doesn't work (Python version)

**Problem:** The Python Safe CLI (`safe-cli` via pip) no longer works.

**Solution:** Use the official Node.js Safe CLI:

```bash
# Remove old Python installation
deactivate 2>/dev/null
rm -rf safe-cli-env

# Install official Node.js version
npm install -g @safe-global/safe-cli

# Verify
safe --version

# Query Safe information
safe account info bnb:0xYOUR_SAFE
```

For more details, see the [Complete Safe CLI Guide](SAFE-SCRIPTS-GUIDE.md#-official-safe-cli-installation-recommended).

**Alternative:** Use Python scripts directly (see section above).
