#!/usr/bin/env bash
# ============================================================================
# Ethereum mainnet equivalent of the BSC IGP replacement — deploys the
# OFFICIAL, unmodified Hyperlane InterchainGasPaymaster.sol to replace the
# custom TerraClassicIGPStandalone contract at
# 0x9650F1f8DB492750323172145e67Df4e89E964Aa (bytecode hash confirmed
# byte-for-byte identical to the BSC one — same problem: NO
# ownership-transfer function at all).
#
# Source/bytecode: identical files copied from deploy-igp-official-bsc/ next
# to this script — @hyperlane-xyz/core@11.3.1, diffed identical to
# hyperlane-monorepo HEAD, not modified in any way.
#
# Unlike BSC, there is no Safe on Ethereum yet — the warp/ISM/IGP owner is
# still a single EOA (0xEF8181201Ce6C83120035Ffbcc11945E67Ba00ae), and the
# deployer keeps that SAME role after this script (confirmed explicitly).
# So this script does everything in one run, including setHook() directly —
# no separate multisig step needed.
#
# Steps:
#   1. Deploy the bare IGP contract (no constructor args).
#   2. initialize(YOUR_ADDRESS, BENEFICIARY) — same beneficiary as the
#      current production IGP (0x04096dCBbBB0FA58a312761c38E1d3B9F64631F1).
#   3. setDestinationGasConfigs for domain 132556 (Terra Classic), pointing
#      at the SAME governed gas oracle the current IGP uses
#      (0x3987cCE8f08037EBF93Ef3a934753540A94196cE — read-only reference,
#      this script NEVER touches its ownership) with the SAME gas overhead
#      currently live on-chain (1469432).
#   4. Deploy a new AggregationHook [MerkleTree + new IGP] via the existing
#      factory (0x6D2555A8ba483CcF4409C39013F5e9a3285D3C9E, reused, not
#      redeployed).
#   5. setHook() on both LUNC and USTC warps, directly (you're still sole
#      owner of both).
#
# No transferOwnership call anywhere — you initialize as owner and stay
# owner, since that's what you asked for.
#
# >>> Ethereum mainnet gas is expensive. Review the confirmation prompts. <<<
# >>> Not idempotent — running this twice deploys two separate IGPs/hooks. <<<
#
# Usage:
#   ./deploy-igp-and-rehook.sh 0xYOUR_PRIVATE_KEY
#   ./deploy-igp-and-rehook.sh --aws alias/hyperlane-relayer-signer-eth
# ============================================================================

set -euo pipefail

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

command -v cast >/dev/null 2>&1 || { echo "cast not found (Foundry)."; exit 1; }

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info(){ echo -e "${BLUE}ℹ️${NC}  $1"; }
ok(){ echo -e "${GREEN}✅${NC}  $1"; }
err(){ echo -e "${RED}❌${NC}  $1"; }
warn(){ echo -e "${YELLOW}⚠️${NC}  $1"; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BYTECODE_FILE="$SCRIPT_DIR/InterchainGasPaymaster.bytecode.hex"
[ -f "$BYTECODE_FILE" ] || { err "Bytecode file not found: $BYTECODE_FILE"; exit 1; }
BYTECODE="$(cat "$BYTECODE_FILE")"

RPC="https://ethereum.publicnode.com"
EXPLORER="https://etherscan.io"
OLD_IGP="0x9650F1f8DB492750323172145e67Df4e89E964Aa"
BENEFICIARY="0x04096dCBbBB0FA58a312761c38E1d3B9F64631F1"
GAS_ORACLE="0x3987cCE8f08037EBF93Ef3a934753540A94196cE"
GAS_OVERHEAD="1469432"
TERRA_CLASSIC_DOMAIN="132556"
LUNC_WARP="0xA4bc47a4C5461eB0E59A585a21A1222EF7544Ac6"
USTC_WARP="0xf49408beb319aeCe3E8B3550a5C750C19b3F1e51"
AGG_FACTORY="0x6D2555A8ba483CcF4409C39013F5e9a3285D3C9E"
MERKLE="0x48e6c30B97748d1e2e03bf3e9FbE3890ca5f8CCA"
OLD_HOOK="0x912c4d91D9eD04B16B83dA79dbe7a209c8Fd0aA8"
EXPECTED_OWNER="0xEF8181201Ce6C83120035Ffbcc11945E67Ba00ae"

# Compute an explicit, tight gas price instead of letting `cast` pick its own
# (observed to pad well beyond 2x the current base fee by default, inflating
# the balance cast requires up front even though only real usage is charged).
# maxFeePerGas = 2x current base fee (standard EIP-1559 headroom for a couple
# of blocks); priority fee kept minimal since eth_maxPriorityFeePerGas is
# currently suggesting 0 on mainnet.
BASE_FEE=$(cast base-fee --rpc-url "$RPC" 2>/dev/null || echo "")
if [ -n "$BASE_FEE" ]; then
  MAX_FEE=$((BASE_FEE * 2))
  PRIORITY_FEE=100000000  # 0.1 gwei
  GASPRICE_ARGS=(--gas-price "$MAX_FEE" --priority-gas-price "$PRIORITY_FEE")
else
  GASPRICE_ARGS=()
fi

DEPLOYER=$(cast wallet address $SIGNER_ARG)
if [ "$(echo "$DEPLOYER" | tr '[:upper:]' '[:lower:]')" != "$(echo "$EXPECTED_OWNER" | tr '[:upper:]' '[:lower:]')" ]; then
  err "Signer ($DEPLOYER) is not $EXPECTED_OWNER, the expected/current owner of the warps and ISM."
  err "setHook() at the end would revert. Aborting."
  exit 1
fi
info "Deploying with: $DEPLOYER (matches expected owner)"
info "Old (custom, non-transferable) IGP: $OLD_IGP"
info "Beneficiary: $BENEFICIARY   Gas oracle: $GAS_ORACLE   Overhead: $GAS_OVERHEAD"
echo ""

# ---- Step 1: deploy IGP ----
warn "About to deploy a NEW contract on ETHEREUM MAINNET (real, expensive gas cost)."
read -p "Proceed with deploying the official InterchainGasPaymaster? (yes/no): " CONFIRM1
[[ "$CONFIRM1" =~ ^[Yy][Ee][Ss]$ ]] || { info "Aborted."; exit 0; }

TX=$(cast send --rpc-url "$RPC" $SIGNER_ARG --gas-limit 3900000 "${GASPRICE_ARGS[@]}" --create "$BYTECODE" 2>&1) || true
if echo "$TX" | grep -qi "error\|revert"; then
  err "Deploy failed:"; echo "$TX"; exit 1
fi
NEW_IGP=$(echo "$TX" | grep -i "^contractAddress" | awk '{print $2}')
[ -z "$NEW_IGP" ] && { err "Could not extract deployed address. Raw output:"; echo "$TX"; exit 1; }
ok "Deployed at: $NEW_IGP ($EXPLORER/address/$NEW_IGP)"
echo ""

# ---- Step 2: initialize ----
info "Step 2 — initialize(you, beneficiary)..."
TX=$(cast send "$NEW_IGP" "initialize(address,address)" "$DEPLOYER" "$BENEFICIARY" --rpc-url "$RPC" $SIGNER_ARG "${GASPRICE_ARGS[@]}" 2>&1) || true
if echo "$TX" | grep -qi "error\|revert"; then
  err "initialize() failed:"; echo "$TX"
  err "Contract deployed at $NEW_IGP but uninitialized (initialize can only run once) — investigate before retrying."
  exit 1
fi
ok "Initialized. Owner = you, beneficiary set."
echo ""

# ---- Step 3: setDestinationGasConfigs ----
info "Step 3 — setDestinationGasConfigs([{domain: $TERRA_CLASSIC_DOMAIN, oracle, overhead}])..."
TX=$(cast send "$NEW_IGP" "setDestinationGasConfigs((uint32,(address,uint96))[])" \
  "[($TERRA_CLASSIC_DOMAIN,($GAS_ORACLE,$GAS_OVERHEAD))]" --rpc-url "$RPC" $SIGNER_ARG "${GASPRICE_ARGS[@]}" 2>&1) || true
if echo "$TX" | grep -qi "error\|revert"; then
  err "setDestinationGasConfigs() failed:"; echo "$TX"; exit 1
fi
ok "Gas config set."
echo ""

info "Verifying new IGP:"
echo "  owner():                        $(cast call "$NEW_IGP" "owner()(address)" --rpc-url "$RPC")"
echo "  beneficiary():                  $(cast call "$NEW_IGP" "beneficiary()(address)" --rpc-url "$RPC")"
echo "  destinationGasConfigs($TERRA_CLASSIC_DOMAIN): $(cast call "$NEW_IGP" "destinationGasConfigs(uint32)(address,uint96)" "$TERRA_CLASSIC_DOMAIN" --rpc-url "$RPC")"
echo "  hookType():                     $(cast call "$NEW_IGP" "hookType()(uint8)" --rpc-url "$RPC")  (must be 4)"
echo ""

# ---- Step 4: deploy new AggregationHook via existing factory ----
PREDICTED=$(cast call "$AGG_FACTORY" "deploy(address[])(address)" "[$MERKLE,$NEW_IGP]" --rpc-url "$RPC")
info "Step 4 — AggregationHook [MerkleTree, new IGP] — predicted address: $PREDICTED"
EXISTING_CODE=$(cast code "$PREDICTED" --rpc-url "$RPC")
if [ "$EXISTING_CODE" != "0x" ]; then
  ok "Already deployed — reusing $PREDICTED."
  NEW_HOOK="$PREDICTED"
else
  warn "About to deploy a new AggregationHook on Ethereum mainnet (real gas cost)."
  read -p "Proceed? (yes/no): " CONFIRM2
  [[ "$CONFIRM2" =~ ^[Yy][Ee][Ss]$ ]] || { info "Stopping here. New IGP is deployed and owned by you at $NEW_IGP — re-run later to finish wiring it."; exit 0; }

  TX=$(cast send "$AGG_FACTORY" "deploy(address[])" "[$MERKLE,$NEW_IGP]" --rpc-url "$RPC" $SIGNER_ARG "${GASPRICE_ARGS[@]}" 2>&1) || true
  if echo "$TX" | grep -qi "error\|revert"; then
    err "Hook deploy failed:"; echo "$TX"; exit 1
  fi
  NEW_HOOK=$(cast call "$AGG_FACTORY" "deploy(address[])(address)" "[$MERKLE,$NEW_IGP]" --rpc-url "$RPC")
  ok "New AggregationHook: $NEW_HOOK ($EXPLORER/address/$NEW_HOOK)"
fi
echo ""
info "Constituent hooks: $(cast call "$NEW_HOOK" "hooks(bytes)(address[])" 0x --rpc-url "$RPC")"
echo ""

# ---- Step 5: setHook on both warps, directly (no multisig on ETH) ----
warn "Old hook (still live until this step, still points at the old custom IGP): $OLD_HOOK"
warn "About to call setHook($NEW_HOOK) directly on LUNC and USTC warps."
read -p "Proceed? (yes/no): " CONFIRM3
if [[ "$CONFIRM3" =~ ^[Yy][Ee][Ss]$ ]]; then
  TX=$(cast send "$LUNC_WARP" "setHook(address)" "$NEW_HOOK" --rpc-url "$RPC" $SIGNER_ARG "${GASPRICE_ARGS[@]}" 2>&1) || true
  if echo "$TX" | grep -qi "error\|revert"; then err "LUNC setHook failed:"; echo "$TX"; exit 1; fi
  ok "LUNC warp hook updated."

  TX=$(cast send "$USTC_WARP" "setHook(address)" "$NEW_HOOK" --rpc-url "$RPC" $SIGNER_ARG "${GASPRICE_ARGS[@]}" 2>&1) || true
  if echo "$TX" | grep -qi "error\|revert"; then err "USTC setHook failed:"; echo "$TX"; exit 1; fi
  ok "USTC warp hook updated."
else
  info "Skipped. Warps still point at the old hook ($OLD_HOOK). Run manually later:"
  echo "  cast send $LUNC_WARP \"setHook(address)\" $NEW_HOOK --rpc-url $RPC --private-key <key>"
  echo "  cast send $USTC_WARP \"setHook(address)\" $NEW_HOOK --rpc-url $RPC --private-key <key>"
fi

echo ""
echo "============================================================"
ok "New IGP: $NEW_IGP"
ok "New Hook: $NEW_HOOK"
echo "============================================================"
info "Verify:"
echo "  cast call $LUNC_WARP \"hook()(address)\" --rpc-url $RPC   # should be $NEW_HOOK"
echo "  cast call $USTC_WARP \"hook()(address)\" --rpc-url $RPC   # should be $NEW_HOOK"
