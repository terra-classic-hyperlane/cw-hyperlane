#!/usr/bin/env bash
# ============================================================================
# Transfers ownership on Ethereum mainnet to the Safe multisig
# (0x4d78A2182a7Cd3a370D73E6651EF4B32C2dd8BDb — verified on Ethereum too:
# v1.5.0, 4-of-6, same 6 signers as the BSC Safe), mirroring the BSC
# migration already done, plus the two ProxyAdmins (a gap that still exists
# on BSC, being closed here on ETH instead).
#
# All 5 targets are plain OZ Ownable (one-step, immediate) — confirmed
# 2026-09-29 by checking pendingOwner() reverts on all of them (no
# Ownable2Step here, unlike the ISM).
#
# Targets (all currently owned by the deployer EOA
# 0xEF8181201Ce6C83120035Ffbcc11945E67Ba00ae):
#   1. New IGP            0x69b3A7C507014fd6E87E7b58a6b037e0EEe0e096
#   2. Warp LUNC          0xA4bc47a4C5461eB0E59A585a21A1222EF7544Ac6
#   3. Warp USTC          0xf49408beb319aeCe3E8B3550a5C750C19b3F1e51
#   4. LUNC ProxyAdmin    0x8c7a816d2c5d4dd480d7267caa46769a3c9fa2b5
#   5. USTC ProxyAdmin    0xfbb065fcb26a7a74e5c1f187ae9a45a7d80a51c1
#   6. ISM (propose only) 0x3ba17675f0D319C89D70722f6eb07790DF0B254B
#
# Also included: the ETH ISM (0x3ba17675f0D319C89D70722f6eb07790DF0B254B) —
# a 45-byte EIP-1167 minimal proxy, byte-identical to the BSC ISM. No admin
# exists for it (mathematically impossible for this bytecode — same proof as
# BSC's ISM: no CALLER opcode, no storage-based admin field at all). Its
# owner() IS Ownable2StepUpgradeable though (pendingOwner() confirmed present
# and currently zero, unlike the other 5 which revert on pendingOwner()) — so
# this script only PROPOSES the Safe as pending owner. The transfer only
# finalizes once the Safe itself executes acceptOwnership() on the ISM via a
# separate Safe transaction (4-of-6, same as was done on BSC).
#
# Usage:
#   ./transfer-to-safe.sh 0xYOUR_PRIVATE_KEY
#   ./transfer-to-safe.sh --aws alias/hyperlane-relayer-signer-eth
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

RPC="https://ethereum.publicnode.com"
EXPLORER="https://etherscan.io"
SAFE="0x4d78A2182a7Cd3a370D73E6651EF4B32C2dd8BDb"
EXPECTED_OWNER="0xEF8181201Ce6C83120035Ffbcc11945E67Ba00ae"

# Same tight-gas-price approach as deploy-igp-and-rehook.sh — cast's own
# default padding was seen requiring ~2x more balance than necessary.
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
  err "Signer ($DEPLOYER) is not $EXPECTED_OWNER, the expected current owner."
  exit 1
fi
info "Signer confirmed: $DEPLOYER"
info "New owner (Safe, 4-of-6, verified on Ethereum too): $SAFE"
echo ""

transfer(){
  local name="$1" addr="$2"
  local current
  current=$(cast call "$addr" "owner()(address)" --rpc-url "$RPC")
  if [ "$(echo "$current" | tr '[:upper:]' '[:lower:]')" = "$(echo "$SAFE" | tr '[:upper:]' '[:lower:]')" ]; then
    ok "$name already owned by the Safe — skipping."
    echo ""
    return
  fi
  if [ "$(echo "$current" | tr '[:upper:]' '[:lower:]')" != "$(echo "$EXPECTED_OWNER" | tr '[:upper:]' '[:lower:]')" ]; then
    warn "$name owner ($current) is neither the Safe nor the expected EOA — skipping, not touching it."
    echo ""
    return
  fi
  warn "About to PERMANENTLY and IMMEDIATELY transfer $name ownership to the Safe."
  read -p "Confirm transferring $name ownership? (yes/no): " CONFIRM
  if [[ ! "$CONFIRM" =~ ^[Yy][Ee][Ss]$ ]]; then
    info "Skipped $name."
    echo ""
    return
  fi
  TX=$(cast send "$addr" "transferOwnership(address)" "$SAFE" --rpc-url "$RPC" $SIGNER_ARG "${GASPRICE_ARGS[@]}" 2>&1) || true
  if echo "$TX" | grep -qi "error\|revert"; then
    err "Failed:"; echo "$TX"; exit 1
  fi
  TX_HASH=$(echo "$TX" | grep -oE "0x[0-9a-fA-F]{64}" | head -1)
  ok "$name transferred. Tx: $TX_HASH ($EXPLORER/tx/$TX_HASH)"
  info "New owner: $(cast call "$addr" "owner()(address)" --rpc-url "$RPC")"
  echo ""
}

transfer "New IGP" "0x69b3A7C507014fd6E87E7b58a6b037e0EEe0e096"
transfer "Warp LUNC" "0xA4bc47a4C5461eB0E59A585a21A1222EF7544Ac6"
transfer "Warp USTC" "0xf49408beb319aeCe3E8B3550a5C750C19b3F1e51"
transfer "LUNC ProxyAdmin" "0x8c7a816d2c5d4dd480d7267caa46769a3c9fa2b5"
transfer "USTC ProxyAdmin" "0xfbb065fcb26a7a74e5c1f187ae9a45a7d80a51c1"

# ---- ISM: Ownable2Step — this script only does step 1 (propose) ----
CONFIRM_ISM=""
ISM="0x3ba17675f0D319C89D70722f6eb07790DF0B254B"
ISM_OWNER=$(cast call "$ISM" "owner()(address)" --rpc-url "$RPC")
ISM_PENDING=$(cast call "$ISM" "pendingOwner()(address)" --rpc-url "$RPC")
info "Current ISM owner: $ISM_OWNER"
info "Current ISM pendingOwner: $ISM_PENDING"
if [ "$(echo "$ISM_OWNER" | tr '[:upper:]' '[:lower:]')" = "$(echo "$SAFE" | tr '[:upper:]' '[:lower:]')" ]; then
  ok "ISM already fully owned by the Safe (acceptOwnership already done) — skipping."
elif [ "$(echo "$ISM_PENDING" | tr '[:upper:]' '[:lower:]')" = "$(echo "$SAFE" | tr '[:upper:]' '[:lower:]')" ]; then
  ok "Safe is already the ISM's pendingOwner — skipping the proposal step."
  warn "Still need the Safe's acceptOwnership() to finalize — see the reminder below."
  CONFIRM_ISM="no-op-already-proposed"
else
  warn "The ISM is Ownable2Step. This step only PROPOSES the Safe as pending owner."
  warn "The transfer does NOT take effect until the Safe itself executes an"
  warn "acceptOwnership() call on this contract from app.safe.global (needs a"
  warn "separate 4-of-6 Safe approval) — this script cannot do that second step."
  read -p "Confirm proposing the Safe as the ISM's pending owner? (yes/no): " CONFIRM_ISM
fi
if [[ "$CONFIRM_ISM" =~ ^[Yy][Ee][Ss]$ ]]; then
  TX=$(cast send "$ISM" "transferOwnership(address)" "$SAFE" --rpc-url "$RPC" $SIGNER_ARG "${GASPRICE_ARGS[@]}" 2>&1) || true
  if echo "$TX" | grep -qi "error\|revert"; then
    err "Failed:"; echo "$TX"; exit 1
  fi
  TX_HASH=$(echo "$TX" | grep -oE "0x[0-9a-fA-F]{64}" | head -1)
  ok "ISM ownership proposed. Tx: $TX_HASH ($EXPLORER/tx/$TX_HASH)"
  info "Verifying pendingOwner (should now be the Safe):"
  cast call "$ISM" "pendingOwner()(address)" --rpc-url "$RPC"
  warn "REMINDER: go to app.safe.global, create a transaction calling"
  warn "acceptOwnership() on $ISM, and get 4 of the 6 Safe signers to approve it."
elif [ "$CONFIRM_ISM" != "no-op-already-proposed" ]; then
  info "Skipped ISM."
fi

echo ""
ok "Done."
