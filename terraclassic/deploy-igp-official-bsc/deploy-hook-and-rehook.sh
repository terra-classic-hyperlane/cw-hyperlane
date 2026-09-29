#!/usr/bin/env bash
# ============================================================================
# Step 2 of the IGP replacement: deploys a new StaticAggregationHook
# [MerkleTree + the new official IGP] via the existing, already-deployed
# factory on BSC (permissionless — anyone can call deploy()), then prints the
# Safe Transaction Builder calldata needed to point the LUNC and USTC warps
# at it.
#
# Does NOT touch the warps itself — setHook() requires the Safe's 4-of-6
# approval, so this script only deploys the hook and hands you the exact
# calldata to paste into app.safe.global (Transaction Builder), same flow you
# already used for the ISM's acceptOwnership().
#
# Prerequisite: the new IGP must already be deployed, initialized, configured
# and owned by the Safe — see deploy-igp.sh (already done 2026-09-28,
# new IGP = 0xc3593dD54274A4CDa8fEBDa343A63A7331154138, owner = Safe).
#
# Usage:
#   ./deploy-hook-and-rehook.sh 0xYOUR_PRIVATE_KEY
#   ./deploy-hook-and-rehook.sh --aws alias/hyperlane-relayer-signer-bsc
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

RPC="https://bsc-dataseed.bnbchain.org"
EXPLORER="https://bscscan.com"
FACTORY="0xe70E86a7D1e001D419D71F960Cb6CaD59b6A3dB6"
MERKLE="0xFDb9Cd5f9daAA2E4474019405A328a88E7484f26"
NEW_IGP="0xc3593dD54274A4CDa8fEBDa343A63A7331154138"
LUNC_WARP="0x481095ecEd7A907e7f390b6226F53a66D379e6e2"
USTC_WARP="0xfC067fd98FD123fC2cAd72d040AF60a523274339"
SAFE="0x4d78A2182a7Cd3a370D73E6651EF4B32C2dd8BDb"
OLD_HOOK="0xD2c82583C261fce94cD3F97f1dFF9B20a9338164"

info "Factory: $FACTORY"
info "Hooks to combine: [MerkleTree $MERKLE, new IGP $NEW_IGP]"
echo ""

PREDICTED=$(cast call "$FACTORY" "deploy(address[])(address)" "[$MERKLE,$NEW_IGP]" --rpc-url "$RPC")
info "Predicted (deterministic) hook address: $PREDICTED"
EXISTING_CODE=$(cast code "$PREDICTED" --rpc-url "$RPC")
if [ "$EXISTING_CODE" != "0x" ]; then
  ok "Already deployed at $PREDICTED — skipping deploy, reusing it."
  NEW_HOOK="$PREDICTED"
else
  warn "About to deploy a new AggregationHook on BSC mainnet (real gas cost)."
  read -p "Proceed? (yes/no): " CONFIRM1
  [[ "$CONFIRM1" =~ ^[Yy][Ee][Ss]$ ]] || { info "Aborted."; exit 0; }

  TX=$(cast send "$FACTORY" "deploy(address[])" "[$MERKLE,$NEW_IGP]" --rpc-url "$RPC" $SIGNER_ARG 2>&1) || true
  if echo "$TX" | grep -qi "error\|revert"; then
    err "Deploy failed:"; echo "$TX"; exit 1
  fi
  ok "Deploy tx sent."
  NEW_HOOK=$(cast call "$FACTORY" "deploy(address[])(address)" "[$MERKLE,$NEW_IGP]" --rpc-url "$RPC")
  ok "New AggregationHook: $NEW_HOOK ($EXPLORER/address/$NEW_HOOK)"
fi
echo ""

info "Verifying new hook's constituent hooks:"
cast call "$NEW_HOOK" "hooks(bytes)(address[])" 0x --rpc-url "$RPC"
echo ""

CALLDATA_LUNC=$(cast calldata "setHook(address)" "$NEW_HOOK")
CALLDATA_USTC="$CALLDATA_LUNC"  # same function, same arg — identical calldata for both warps

echo "============================================================"
ok "Hook ready: $NEW_HOOK"
echo "============================================================"
echo ""
warn "Old hook (still live, untouched, still points at the old custom IGP): $OLD_HOOK"
warn "Nothing changes for LUNC/USTC until the SAFE executes setHook() below."
echo ""
info "Safe Transaction Builder steps (app.safe.global -> $SAFE -> New transaction -> Transaction Builder):"
echo ""
echo "  Transaction 1/2 — LUNC warp:"
echo "    To address: $LUNC_WARP"
echo "    Custom data: $CALLDATA_LUNC"
echo "    BNB value: 0"
echo ""
echo "  Transaction 2/2 — USTC warp:"
echo "    To address: $USTC_WARP"
echo "    Custom data: $CALLDATA_USTC"
echo "    BNB value: 0"
echo ""
info "Add both to the same batch, then Create Batch -> Send Batch -> get 4-of-6 approvals."
echo ""
info "After execution, verify with:"
echo "  cast call $LUNC_WARP \"hook()(address)\" --rpc-url $RPC   # should be $NEW_HOOK"
echo "  cast call $USTC_WARP \"hook()(address)\" --rpc-url $RPC   # should be $NEW_HOOK"
