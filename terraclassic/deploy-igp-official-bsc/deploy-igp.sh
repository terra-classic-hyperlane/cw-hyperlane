#!/usr/bin/env bash
# DEPRECATED CONTRACTS — DO NOT USE: OLD_IGP / OLD_HOOK below are the retired custom IGP and
# hook. This is a one-shot migration, already executed (2026-09-28/29). Current contracts:
# BSC IGP 0xc3593dD54274A4CDa8fEBDa343A63A7331154138, hook 0x4AE5fd735Fe1a987756366F7FFeE754C061839d4;
# ETH IGP 0x69b3A7C507014fd6E87E7b58a6b037e0EEe0e096, hook 0xDC9FF1B50d04792bf7730032F1763501D5669420.
# ============================================================================
# Deploys the OFFICIAL, unmodified Hyperlane InterchainGasPaymaster.sol on
# BSC, to replace the custom TerraClassicIGPStandalone contract currently at
# 0xEdEd7a4f6FEe4B474B9d7730Bf3465E35E2a4923 — which has NO ownership-transfer
# function at all (verified by full bytecode disassembly), so its owner (a
# single EOA) can never be moved off to the Safe.
#
# Source: InterchainGasPaymaster.sol shipped in npm package
# @hyperlane-xyz/core@11.3.1 (byte-for-byte identical to the current HEAD of
# hyperlane-monorepo/solidity/contracts/hooks/igp/InterchainGasPaymaster.sol,
# diffed to confirm). NOT modified in any way — see InterchainGasPaymaster.sol
# next to this script. InterchainGasPaymaster.bytecode.hex is the exact
# creation bytecode extracted from that package's compiled typechain factory
# (solc 0.8.33, matches this project's foundry.toml solc_version).
#
# Full deploy+initialize+configure+transferOwnership flow already dry-run
# tested end-to-end on a local anvil fork of BSC mainnet on 2026-09-28,
# including a real quoteGasPayment() call against the live production gas
# oracle — see chat history for the transcript. Bytecode has no unlinked
# library placeholders (checked for `__$...$__` patterns — none found).
#
# What this script does, in order (matches what the deployer explicitly
# asked for — instantiate with your own account first, THEN move owner):
#   1. Deploy the bare contract (no constructor args — OwnableUpgradeable
#      uses the `initializer` pattern, not a constructor. Confirmed: Hyperlane
#      Labs' own official IGP on BSC, 0x78E25e7f84416e69b9339B0A6336EB6EFfF6b451,
#      is deployed the exact same way — no proxy, bare contract + initialize()).
#   2. initialize(YOUR_ADDRESS, BENEFICIARY) — you become owner immediately;
#      beneficiary is set to the SAME relayer-reward-vault the current
#      production IGP already uses (0x34E06a7793877EC5251b1dC230aD7cD577d231f4).
#   3. setDestinationGasConfigs([{domain: 132556, gasOracle: <shared oracle>,
#      gasOverhead: <current live value>}]) — points at the SAME governed Gas
#      Oracle the current IGP uses (0x7dE950f8F0a037783989a6BE84B3620916552306
#      — read-only reference, this script NEVER touches its ownership) with
#      the SAME gas overhead currently live on-chain (14159690 — read directly
#      from the old IGP, not the (stale) config-file default of 200000).
#   4. Prints owner/beneficiary/config for you to verify, plus a live
#      quoteGasPayment() sanity check.
#   5. ONLY on a separate explicit confirmation: transferOwnership(SAFE).
#      This is a ONE-STEP Ownable transfer (not Ownable2Step like the ISM) —
#      it takes effect IMMEDIATELY, no separate accept needed.
#
# This script does NOT deploy the replacement AggregationHook or call
# setHook() on the LUNC/USTC warps — that is a separate next step, once this
# IGP's address is final, since it needs a Safe multisig transaction.
#
# >>> Deploying twice creates TWO separate IGP contracts — this script is NOT
#     idempotent like the ownership-transfer scripts (each run deploys a new
#     contract). Only run it once for real. <<<
#
# Usage:
#   ./deploy-igp.sh 0xYOUR_PRIVATE_KEY
#   ./deploy-igp.sh --aws alias/hyperlane-relayer-signer-bsc
# ============================================================================

set -euo pipefail

# ---- Signer ----
if [ $# -eq 0 ]; then
  read -s -p "Private key (0x...): " PROMPTED_KEY
  echo ""
  [ -z "$PROMPTED_KEY" ] && { echo "No private key or AWS alias provided"; exit 1; }
  SIGNER_ARG="--private-key $PROMPTED_KEY"
elif [ "$1" = "--aws" ] && [ $# -ge 2 ]; then
  SIGNER_ARG="$1 $2"
else
  SIGNER_ARG="--private-key $1"
fi

command -v cast >/dev/null 2>&1 || { echo "cast not found (Foundry). Install: curl -L https://foundry.paradigm.xyz | bash && foundryup"; exit 1; }

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info(){ echo -e "${BLUE}ℹ️${NC}  $1"; }
ok(){ echo -e "${GREEN}✅${NC}  $1"; }
err(){ echo -e "${RED}❌${NC}  $1"; }
warn(){ echo -e "${YELLOW}⚠️${NC}  $1"; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BYTECODE_FILE="$SCRIPT_DIR/InterchainGasPaymaster.bytecode.hex"
[ -f "$BYTECODE_FILE" ] || { err "Bytecode file not found: $BYTECODE_FILE"; exit 1; }
BYTECODE="$(cat "$BYTECODE_FILE")"

RPC="https://bsc-dataseed.bnbchain.org"
EXPLORER="https://bscscan.com"
OLD_IGP="0xEdEd7a4f6FEe4B474B9d7730Bf3465E35E2a4923"
BENEFICIARY="0x34E06a7793877EC5251b1dC230aD7cD577d231f4"
GAS_ORACLE="0x7dE950f8F0a037783989a6BE84B3620916552306"
GAS_OVERHEAD="14159690"
TERRA_CLASSIC_DOMAIN="132556"
SAFE="0x4d78A2182a7Cd3a370D73E6651EF4B32C2dd8BDb"

DEPLOYER=$(cast wallet address $SIGNER_ARG)
info "Deploying with: $DEPLOYER"
info "Old (custom, non-transferable) IGP: $OLD_IGP"
info "Beneficiary (same as current production IGP): $BENEFICIARY"
info "Gas oracle (same shared/governed oracle, read-only): $GAS_ORACLE"
info "Gas overhead (same as current live value): $GAS_OVERHEAD"
echo ""

# ---- Step 1: deploy ----
warn "About to deploy a NEW contract on BSC mainnet (real gas cost)."
read -p "Proceed with deploying the official InterchainGasPaymaster? (yes/no): " CONFIRM1
[[ "$CONFIRM1" =~ ^[Yy][Ee][Ss]$ ]] || { info "Aborted."; exit 0; }

TX=$(cast send --rpc-url "$RPC" $SIGNER_ARG --create "$BYTECODE" 2>&1) || true
if echo "$TX" | grep -qi "error\|revert"; then
  err "Deploy failed:"; echo "$TX"; exit 1
fi
NEW_IGP=$(echo "$TX" | grep -i "^contractAddress" | awk '{print $2}')
[ -z "$NEW_IGP" ] && { err "Could not extract deployed address. Raw output:"; echo "$TX"; exit 1; }
ok "Deployed at: $NEW_IGP ($EXPLORER/address/$NEW_IGP)"
echo ""

# ---- Step 2: initialize(deployer, beneficiary) ----
info "Step 2 — initialize(you, beneficiary)..."
TX=$(cast send "$NEW_IGP" "initialize(address,address)" "$DEPLOYER" "$BENEFICIARY" --rpc-url "$RPC" $SIGNER_ARG 2>&1) || true
if echo "$TX" | grep -qi "error\|revert"; then
  err "initialize() failed:"; echo "$TX"
  err "Contract is deployed at $NEW_IGP but uninitialized — investigate before retrying blindly (initialize can only be called once)."
  exit 1
fi
ok "Initialized. Owner = you, beneficiary set."
echo ""

# ---- Step 3: setDestinationGasConfigs ----
info "Step 3 — setDestinationGasConfigs([{domain: $TERRA_CLASSIC_DOMAIN, oracle, overhead}])..."
TX=$(cast send "$NEW_IGP" "setDestinationGasConfigs((uint32,(address,uint96))[])" \
  "[($TERRA_CLASSIC_DOMAIN,($GAS_ORACLE,$GAS_OVERHEAD))]" --rpc-url "$RPC" $SIGNER_ARG 2>&1) || true
if echo "$TX" | grep -qi "error\|revert"; then
  err "setDestinationGasConfigs() failed:"; echo "$TX"; exit 1
fi
ok "Gas config set."
echo ""

# ---- Step 4: verify ----
info "Verifying deployed state:"
echo "  owner():                        $(cast call "$NEW_IGP" "owner()(address)" --rpc-url "$RPC")"
echo "  beneficiary():                  $(cast call "$NEW_IGP" "beneficiary()(address)" --rpc-url "$RPC")"
echo "  destinationGasConfigs($TERRA_CLASSIC_DOMAIN): $(cast call "$NEW_IGP" "destinationGasConfigs(uint32)(address,uint96)" "$TERRA_CLASSIC_DOMAIN" --rpc-url "$RPC")"
echo "  quoteGasPayment($TERRA_CLASSIC_DOMAIN, 300000): $(cast call "$NEW_IGP" "quoteGasPayment(uint32,uint256)(uint256)" "$TERRA_CLASSIC_DOMAIN" 300000 --rpc-url "$RPC") wei"
echo "  hookType():                     $(cast call "$NEW_IGP" "hookType()(uint8)" --rpc-url "$RPC")  (must be 4)"
echo ""

# ---- Step 5: transfer ownership to the Safe (separate, explicit confirmation) ----
warn "Next: transferOwnership($SAFE) — ONE-STEP, takes effect IMMEDIATELY."
warn "Review the values printed above FIRST. This cannot be undone by you alone afterwards"
warn "(only the Safe, 4-of-6, could transfer it again from here)."
read -p "Confirm transferring ownership to the Safe now? (yes/no): " CONFIRM2
if [[ "$CONFIRM2" =~ ^[Yy][Ee][Ss]$ ]]; then
  TX=$(cast send "$NEW_IGP" "transferOwnership(address)" "$SAFE" --rpc-url "$RPC" $SIGNER_ARG 2>&1) || true
  if echo "$TX" | grep -qi "error\|revert"; then
    err "transferOwnership() failed:"; echo "$TX"; exit 1
  fi
  ok "Ownership transferred. New owner: $(cast call "$NEW_IGP" "owner()(address)" --rpc-url "$RPC")"
else
  info "Skipped. Owner is still you ($DEPLOYER). Run this to transfer later:"
  echo "  cast send $NEW_IGP \"transferOwnership(address)\" $SAFE --rpc-url $RPC --private-key <key>"
fi

echo ""
echo "============================================================"
ok "New IGP: $NEW_IGP"
echo "============================================================"
warn "This IGP is NOT wired to the warps yet. Nothing changes for LUNC/USTC"
warn "until a new AggregationHook [MerkleTree + this IGP] is deployed via the"
warn "existing factory ($EXPLORER/address/0xe70E86a7D1e001D419D71F960Cb6CaD59b6A3dB6)"
warn "and the Safe calls setHook() on both warps — that's the next script."
