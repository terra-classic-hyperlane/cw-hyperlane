#!/bin/bash

# =============================================================================
# Hyperlane Terra Classic — Check On-Chain Contract Configuration
# =============================================================================
# Queries the deployed contracts and compares with config.yaml values.
#
# Contracts queried:
#   - hpl_igp_oracle  → exchange_rate and gas_price per domain
#   - hpl_igp         → default_gas_usage
#   - hpl_hook_fee    → fee denom and amount
#
# Network: Terra Classic Testnet (rebel-2)
# LCD:     https://lcd.luncblaze.com
#
# Usage:
#   chmod +x check-contract-config.sh
#   ./check-contract-config.sh
# =============================================================================

LCD="https://lcd.luncblaze.com"

# Contract addresses (from context/terraclassic.json deployments)
IGP_ORACLE="terra1yew4y2ekzhkwuuz07yt7qufqxxejxhmnr7apehkqk7e8jdw8ffqqs8zhds"
IGP="terra1mcaqgr7kqs9xr3q6w0e9f2ekrj6sehwcep9shtss6u8pdz2rsw5qzrew7r"
HOOK_FEE="terra1g8yzt275smsneyp8qrejc2v99dutt6yhfa8x4yylprh4x9vep7gsxuq2q8"

# Expected values from config.yaml (for comparison)
CFG_97_EXCHANGE="14794529576536"
CFG_97_GASPRICE="100000000"
CFG_SOL_EXCHANGE="57675000000000000"
CFG_SOL_GASPRICE="1"
CFG_DEFAULT_GAS="100000"
CFG_FEE_DENOM="uluna"
CFG_FEE_AMOUNT="283215"

# Helper: query a contract and return JSON data field
query() {
  local contract="$1"
  local msg="$2"
  local encoded
  encoded=$(echo -n "$msg" | base64 -w0)
  curl -s --max-time 10 "$LCD/cosmwasm/wasm/v1/contract/$contract/smart/$encoded"
}

# Helper: compare and print status
compare() {
  local label="$1"
  local on_chain="$2"
  local config="$3"
  if [ "$on_chain" = "$config" ]; then
    echo "    ✅ $label: $on_chain (matches config.yaml)"
  else
    echo "    ⚠️  $label"
    echo "       On-chain : $on_chain"
    echo "       config.yaml: $config"
    echo "       → DIVERGENCE DETECTED"
  fi
}

echo ""
echo "============================================================"
echo "  Hyperlane — On-Chain Contract Configuration Check"
echo "  Network : Terra Classic Testnet (rebel-2)"
echo "  LCD     : $LCD"
echo "============================================================"
echo ""

# ─────────────────────────────────────────────────────────────────────────────
echo "► IGP Oracle: $IGP_ORACLE"
echo ""

# Domain 97 — BSC Testnet
echo "  [Domain 97 — BSC Testnet]"
RESULT=$(query "$IGP_ORACLE" '{"oracle":{"get_exchange_rate_and_gas_price":{"dest_domain":97}}}')
CODE=$(echo "$RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('code','0'))" 2>/dev/null)
if [ "$CODE" != "0" ] && [ -n "$CODE" ]; then
  echo "    ❌ Not configured on-chain (domain 97 not found)"
else
  GAS_PRICE=$(echo "$RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['data']['gas_price'])" 2>/dev/null)
  EXCHANGE=$(echo "$RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['data']['exchange_rate'])" 2>/dev/null)
  compare "gas_price    " "$GAS_PRICE" "$CFG_97_GASPRICE"
  compare "exchange_rate" "$EXCHANGE"  "$CFG_97_EXCHANGE"
fi
echo ""

# Domain 1399811150 — Solana Testnet
echo "  [Domain 1399811150 — Solana Testnet]"
RESULT=$(query "$IGP_ORACLE" '{"oracle":{"get_exchange_rate_and_gas_price":{"dest_domain":1399811150}}}')
CODE=$(echo "$RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('code','0'))" 2>/dev/null)
if [ "$CODE" != "0" ] && [ -n "$CODE" ]; then
  echo "    ❌ Not configured on-chain (domain 1399811150 not found)"
else
  GAS_PRICE=$(echo "$RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['data']['gas_price'])" 2>/dev/null)
  EXCHANGE=$(echo "$RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['data']['exchange_rate'])" 2>/dev/null)
  compare "gas_price    " "$GAS_PRICE" "$CFG_SOL_GASPRICE"
  compare "exchange_rate" "$EXCHANGE"  "$CFG_SOL_EXCHANGE"
fi
echo ""

# Domain 11155111 — Sepolia (ETH Testnet)
echo "  [Domain 11155111 — Sepolia / ETH Testnet]"
RESULT=$(query "$IGP_ORACLE" '{"oracle":{"get_exchange_rate_and_gas_price":{"dest_domain":11155111}}}')
CODE=$(echo "$RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('code','0'))" 2>/dev/null)
if [ "$CODE" != "0" ] && [ -n "$CODE" ]; then
  echo "    ❌ Not configured on-chain (domain 11155111 not found)"
else
  GAS_PRICE=$(echo "$RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['data']['gas_price'])" 2>/dev/null)
  EXCHANGE=$(echo "$RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['data']['exchange_rate'])" 2>/dev/null)
  echo "    ℹ️  gas_price    : $GAS_PRICE  (not in config.yaml — extra domain)"
  echo "    ℹ️  exchange_rate: $EXCHANGE  (not in config.yaml — extra domain)"
fi
echo ""

# Domain 1 — Ethereum Mainnet (check if configured)
echo "  [Domain 1 — Ethereum Mainnet]"
RESULT=$(query "$IGP_ORACLE" '{"oracle":{"get_exchange_rate_and_gas_price":{"dest_domain":1}}}')
CODE=$(echo "$RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('code','0'))" 2>/dev/null)
if [ "$CODE" != "0" ] && [ -n "$CODE" ]; then
  echo "    ℹ️  Not configured on-chain (domain 1 not found — expected for testnet)"
else
  GAS_PRICE=$(echo "$RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['data']['gas_price'])" 2>/dev/null)
  EXCHANGE=$(echo "$RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['data']['exchange_rate'])" 2>/dev/null)
  echo "    ⚠️  gas_price    : $GAS_PRICE  (unexpected — check if mainnet domain was added)"
  echo "    ⚠️  exchange_rate: $EXCHANGE"
fi
echo ""

# Domain 56 — BSC Mainnet (check if configured)
echo "  [Domain 56 — BSC Mainnet]"
RESULT=$(query "$IGP_ORACLE" '{"oracle":{"get_exchange_rate_and_gas_price":{"dest_domain":56}}}')
CODE=$(echo "$RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('code','0'))" 2>/dev/null)
if [ "$CODE" != "0" ] && [ -n "$CODE" ]; then
  echo "    ℹ️  Not configured on-chain (domain 56 not found — expected for testnet)"
else
  GAS_PRICE=$(echo "$RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['data']['gas_price'])" 2>/dev/null)
  EXCHANGE=$(echo "$RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['data']['exchange_rate'])" 2>/dev/null)
  echo "    ⚠️  gas_price    : $GAS_PRICE  (unexpected — check if mainnet domain was added)"
  echo "    ⚠️  exchange_rate: $EXCHANGE"
fi
echo ""

# ─────────────────────────────────────────────────────────────────────────────
echo "► IGP (default_gas_usage): $IGP"
echo ""
RESULT=$(query "$IGP" '{"igp":{"default_gas":{}}}')
CODE=$(echo "$RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('code','0'))" 2>/dev/null)
if [ "$CODE" != "0" ] && [ -n "$CODE" ]; then
  echo "    ❌ Query failed: $(echo "$RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('message',''))" 2>/dev/null)"
else
  DEFAULT_GAS=$(echo "$RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['data']['gas'])" 2>/dev/null)
  compare "default_gas_usage" "$DEFAULT_GAS" "$CFG_DEFAULT_GAS"
fi
echo ""

# ─────────────────────────────────────────────────────────────────────────────
echo "► Hook Fee: $HOOK_FEE"
echo ""
RESULT=$(query "$HOOK_FEE" '{"fee_hook":{"fee":{}}}')
CODE=$(echo "$RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('code','0'))" 2>/dev/null)
if [ "$CODE" != "0" ] && [ -n "$CODE" ]; then
  echo "    ❌ Query failed: $(echo "$RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('message',''))" 2>/dev/null)"
else
  FEE_DENOM=$(echo "$RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['data']['fee']['denom'])" 2>/dev/null)
  FEE_AMOUNT=$(echo "$RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['data']['fee']['amount'])" 2>/dev/null)
  compare "fee.denom " "$FEE_DENOM"  "$CFG_FEE_DENOM"
  compare "fee.amount" "$FEE_AMOUNT" "$CFG_FEE_AMOUNT"
fi
echo ""

# ─────────────────────────────────────────────────────────────────────────────
echo "============================================================"
echo "  Summary of current on-chain values:"
echo ""
echo "  IGP Oracle:"
echo "    Domain 97  (BSC Testnet)    → queried above"
echo "    Domain 1399811150 (Solana)  → queried above"
echo "    Domain 11155111 (Sepolia)   → queried above"
echo ""
echo "  IGP:"
echo "    default_gas_usage           → queried above"
echo ""
echo "  Hook Fee:"
echo "    denom / amount              → queried above"
echo ""
echo "  Legend:"
echo "    ✅  On-chain value matches config.yaml"
echo "    ⚠️   On-chain value DIFFERS from config.yaml"
echo "    ❌  Contract not responding or domain not found"
echo "    ℹ️   Informational (not in config.yaml)"
echo "============================================================"
echo ""
