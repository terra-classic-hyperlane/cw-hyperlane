#!/bin/bash

# =============================================================================
# Hyperlane Terra Classic — Transfer Ownership to Governance
# =============================================================================
#
# This script transfers ownership of all deployed Hyperlane contracts from
# the current admin wallet to the Terra Classic governance module.
#
# The transfer is a 2-step process:
#   STEP 1 (this script - admin wallet): InitOwnershipTransfer on all contracts
#   STEP 2 (governance proposal):        ClaimOwnership via governance vote
#
# Network : Terra Classic Testnet (rebel-2)
# LCD     : https://lcd.luncblaze.com
# RPC     : https://rpc.luncblaze.com
#
# Governance module address: terra10d07y265gmmuvt4z0w9aw880jnsr700juxf95n
#
# Usage:
#   export PRIVATE_KEY="0xYOUR_HEX_PRIVATE_KEY"
#   chmod +x transfer-ownership-to-governance.sh
#   ./transfer-ownership-to-governance.sh
#
# For detailed explanation see: doc/TRANSFER-OWNERSHIP-TO-GOVERNANCE.md
# =============================================================================

set -e

# ── Configuration ─────────────────────────────────────────────────────────────
RPC="https://rpc.luncblaze.com"
LCD="https://lcd.luncblaze.com"
CHAIN_ID="rebel-2"
GAS_PRICES="28.325uluna"
GAS_ADJUSTMENT="1.5"
FROM_KEY="${TERRA_KEY_NAME:-validator-key}"   # terrad keyring name

GOVERNANCE="terra10d07y265gmmuvt4z0w9aw880jnsr700juxf95n"
ADMIN_WALLET="${ADMIN_WALLET:-terra12awgqgwm2evj05ndtgs0xa35uunlpc76d85pze}"

# ── Contract addresses — v2 re-deploy 2026-06-09, domain 132556 ───────────────
MAILBOX="terra1fwg35n5esjgny7d8pxnz8usjpwsvpguk0txsy6cnqxy58x9fdlksjpx3p9"
ISM_ROUTING="terra1uhzzvt9x3u8hjnkp695hklexx2uywjvfqv454d93ds92sgtpwk7qrpxdg0"
ISM_MULTI_ETH="terra187rzjc3dznfxqtqqrwh796e5q4khmvp5av8mka6zhp98zjfk2z2qneldar"
ISM_MULTI_BSC="terra1nqj7qlnt2sty0dgnu3ss5z4u6wr7hjfea7cn6wpwjt2uymts8ucsmuj9xw"
ISM_MULTI_SOL="terra10s3p36tjek8amhlc4krxpzln6g8n0qy9jq82wyda434l3rv89wfsucl50t"
HOOK_AGG_DEFAULT="terra1026v947k2jn58t09ppw003xujj92vp3lxv0fg3xk8ccz42r8d2sqvnmvel"
IGP="terra1taunhg629rssf3g939nqr0h594q5mssrzdj5lkx2hygmxmh72ghqeqqnvz"
IGP_ORACLE="terra1j8xzgzk7vds5uzrplmnln4vcz6f205t9atdyflypzrr43cd5eh7scwqj0d"
HOOK_AGG_REQUIRED="terra1xmdd7yhu3qdlfhrcku8srfvtday6efymj54gqz0daxsmn8pvqygq0nxq04"
HOOK_PAUSABLE="terra1x8s9qtw9355pfckywkns4e8f9zyfjaf8w5e5s8vh28ph5gzwwlks9tjcnf"
HOOK_FEE="terra1sud5xyknr93wmxem6kxdfd0vxcju47wuh7zdm5uecavrm36w669sp7j8ag"

# ── Helpers ───────────────────────────────────────────────────────────────────
TERRAD="terrad"
LOG_DIR="$(dirname "$0")/log"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/transfer-ownership-$(date +%Y%m%d-%H%M%S).log"

log() { echo "$1" | tee -a "$LOG_FILE"; }
die() { log "❌ ERROR: $1"; exit 1; }

query_owner() {
  local addr="$1"
  local Q
  Q=$(echo -n '{"ownable":{"get_owner":{}}}' | base64 -w0)
  curl -s --max-time 8 "$LCD/cosmwasm/wasm/v1/contract/$addr/smart/$Q" | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('data',{}).get('owner','?'))" 2>/dev/null
}

exec_ownable() {
  local label="$1"
  local contract="$2"
  local msg_key="$3"   # "ownable" or "ownership" (IGP oracle)
  local msg="{\"${msg_key}\":{\"init_ownership_transfer\":{\"next_owner\":\"${GOVERNANCE}\"}}}"
  log "  → $label ($contract)"
  $TERRAD tx wasm execute "$contract" "$msg" \
    --from "$FROM_KEY" \
    --chain-id "$CHAIN_ID" \
    --node "$RPC" \
    --gas auto \
    --gas-adjustment "$GAS_ADJUSTMENT" \
    --gas-prices "$GAS_PRICES" \
    --keyring-backend file \
    -y \
    2>&1 | tee -a "$LOG_FILE" | grep -E "(txhash|code|raw_log)" || true
  sleep 3
}

# ── Preflight checks ──────────────────────────────────────────────────────────
log ""
log "============================================================"
log "  Hyperlane — Transfer Ownership to Governance"
log "  $(date)"
log "============================================================"
log ""
log "  New owner (governance): $GOVERNANCE"
log "  Network               : $CHAIN_ID"
log "  Log file              : $LOG_FILE"
log ""

# Verify terrad is installed
command -v $TERRAD >/dev/null 2>&1 || die "terrad not found. Install it first."

# Verify key exists
$TERRAD keys show "$FROM_KEY" --keyring-backend file >/dev/null 2>&1 || \
  die "Key '$FROM_KEY' not found. Set TERRA_KEY_NAME to your terrad key name."

CURRENT_ADDR=$($TERRAD keys show "$FROM_KEY" --keyring-backend file --address 2>/dev/null)
log "  Signing wallet: $CURRENT_ADDR"

# Verify current ownership
log ""
log "► Verifying current ownership..."
for label_addr in \
  "mailbox:$MAILBOX" \
  "ism_routing:$ISM_ROUTING" \
  "ism_multisig_sol:$ISM_MULTI_SOL" \
  "ism_multisig_bsc:$ISM_MULTI_BSC" \
  "hook_aggregate_default:$HOOK_AGG_DEFAULT" \
  "igp:$IGP" \
  "igp_oracle:$IGP_ORACLE" \
  "hook_aggregate_required:$HOOK_AGG_REQUIRED" \
  "hook_pausable:$HOOK_PAUSABLE" \
  "hook_fee:$HOOK_FEE"; do
  label="${label_addr%%:*}"
  addr="${label_addr##*:}"
  owner=$(query_owner "$addr")
  if [ "$owner" != "$CURRENT_ADDR" ]; then
    log "  ⚠️  $label: owner is $owner (expected $CURRENT_ADDR)"
  else
    log "  ✅ $label: owner = $CURRENT_ADDR"
  fi
done

log ""
read -rp "Proceed with InitOwnershipTransfer on all contracts? [y/N]: " confirm
[[ "$confirm" =~ ^[Yy]$ ]] || { log "Aborted."; exit 0; }

# ─────────────────────────────────────────────────────────────────────────────
# STEP 1: InitOwnershipTransfer (from admin wallet)
# ─────────────────────────────────────────────────────────────────────────────
log ""
log "============================================================"
log "  STEP 1: InitOwnershipTransfer → $GOVERNANCE"
log "============================================================"
log ""
log "  Note: Most contracts use execute key 'ownable'."
log "  Exception: IGP Oracle uses execute key 'ownership'."
log ""

exec_ownable "Mailbox"                  "$MAILBOX"          "ownable"
exec_ownable "ISM Routing"              "$ISM_ROUTING"      "ownable"
exec_ownable "ISM Multisig (Solana)"    "$ISM_MULTI_SOL"    "ownable"
exec_ownable "ISM Multisig (BSC)"       "$ISM_MULTI_BSC"    "ownable"
exec_ownable "Hook Aggregate (default)" "$HOOK_AGG_DEFAULT" "ownable"
exec_ownable "IGP"                      "$IGP"              "ownable"
exec_ownable "IGP Oracle"               "$IGP_ORACLE"       "ownership"
exec_ownable "Hook Aggregate (required)""$HOOK_AGG_REQUIRED" "ownable"
exec_ownable "Hook Pausable"            "$HOOK_PAUSABLE"    "ownable"
exec_ownable "Hook Fee"                 "$HOOK_FEE"         "ownable"

log ""
log "✅ STEP 1 complete — InitOwnershipTransfer sent to all contracts."
log ""

# ─────────────────────────────────────────────────────────────────────────────
# STEP 2: Generate Governance Proposal for ClaimOwnership
# ─────────────────────────────────────────────────────────────────────────────
log "============================================================"
log "  STEP 2: Generating Governance Proposal"
log "============================================================"
log ""

PROPOSAL_FILE="$(dirname "$0")/log/governance-claim-ownership-$(date +%Y%m%d-%H%M%S).json"

python3 << PYEOF > "$PROPOSAL_FILE"
import json

GOVERNANCE = "terra10d07y265gmmuvt4z0w9aw880jnsr700juxf95n"

# Contracts using "ownable" key
ownable_contracts = {
    "Mailbox":                    "terra1s4jwfe0tcaztpfsct5wzj02esxyjy7e7lhkcwn5dp04yvly82rwsvzyqmm",
    "ISM Routing":                "terra1na6ljyf4m5x2u7llfvvxxe2nyq0t8628qyk0vnwu4ttpq86tt0cse47t68",
    "ISM Multisig Solana":        "terra18gh7nl0tk047ykrvy0a8z2lhv0rvl65wu95texyawrj879qenysq02p98f",
    "ISM Multisig BSC":           "terra1ksq6cekt0as2f9vv5txld90s854y4pkr2k0jn5p83vqpa5zzzfysuavxr0",
    "Hook Aggregate Default":     "terra18shx4zhfehscggs9upspl489qd7yg29vdasvrerytppt3am92mnsj5365s",
    "IGP":                        "terra1mcaqgr7kqs9xr3q6w0e9f2ekrj6sehwcep9shtss6u8pdz2rsw5qzrew7r",
    "Hook Aggregate Required":    "terra16veqgkz2yzvgmhyw8rn5k8fue4wysey077zmexevv7hm6ud4my0q8g3krq",
    "Hook Pausable":              "terra12qw82wwutq6hpswfgqfkcjdr0z4fqg4wus9np0uhxdngfwy6lf7s2xsq7d",
    "Hook Fee":                   "terra1g8yzt275smsneyp8qrejc2v99dutt6yhfa8x4yylprh4x9vep7gsxuq2q8",
}

# IGP Oracle uses "ownership" key (different execute variant)
oracle_contract = "terra1yew4y2ekzhkwuuz07yt7qufqxxejxhmnr7apehkqk7e8jdw8ffqqs8zhds"

messages = []
for name, addr in ownable_contracts.items():
    messages.append({
        "@type": "/cosmwasm.wasm.v1.MsgExecuteContract",
        "sender": GOVERNANCE,
        "contract": addr,
        "msg": {"ownable": {"claim_ownership": {}}},
        "funds": []
    })

# IGP Oracle: uses "ownership" key
messages.append({
    "@type": "/cosmwasm.wasm.v1.MsgExecuteContract",
    "sender": GOVERNANCE,
    "contract": oracle_contract,
    "msg": {"ownership": {"claim_ownership": {}}},
    "funds": []
})

proposal = {
    "messages": messages,
    "metadata": "ipfs://",
    "deposit": "1000000uluna",
    "title": "Hyperlane: Transfer Protocol Ownership to Governance",
    "summary": (
        "This proposal completes the 2-step ownership transfer of all Hyperlane "
        "protocol contracts (Mailbox, ISMs, IGP, Hooks) from the deployer wallet "
        "to the governance module. The deployer already called InitOwnershipTransfer. "
        "This proposal calls ClaimOwnership on all 10 contracts to finalize decentralized control."
    )
}

print(json.dumps(proposal, indent=2))
PYEOF

log "  Proposal file generated: $PROPOSAL_FILE"
log ""
log "  Submit the proposal with:"
log ""
log "  terrad tx gov submit-proposal $PROPOSAL_FILE \\"
log "    --from $FROM_KEY \\"
log "    --chain-id $CHAIN_ID \\"
log "    --node $RPC \\"
log "    --gas auto \\"
log "    --gas-adjustment $GAS_ADJUSTMENT \\"
log "    --gas-prices $GAS_PRICES \\"
log "    --keyring-backend file \\"
log "    -y"
log ""

read -rp "Submit the governance proposal now? [y/N]: " submit
if [[ "$submit" =~ ^[Yy]$ ]]; then
  log ""
  log "► Submitting governance proposal..."
  $TERRAD tx gov submit-proposal "$PROPOSAL_FILE" \
    --from "$FROM_KEY" \
    --chain-id "$CHAIN_ID" \
    --node "$RPC" \
    --gas auto \
    --gas-adjustment "$GAS_ADJUSTMENT" \
    --gas-prices "$GAS_PRICES" \
    --keyring-backend file \
    -y 2>&1 | tee -a "$LOG_FILE"

  log ""
  log "► Check proposal status:"
  log "  terrad query gov proposals --node $RPC --chain-id $CHAIN_ID"
  log ""
  log "► Vote YES on the proposal (replace <PROPOSAL_ID> with the actual ID):"
  log "  terrad tx gov vote <PROPOSAL_ID> yes \\"
  log "    --from $FROM_KEY --chain-id $CHAIN_ID --node $RPC \\"
  log "    --gas auto --gas-adjustment $GAS_ADJUSTMENT --gas-prices $GAS_PRICES \\"
  log "    --keyring-backend file -y"
fi

# ─────────────────────────────────────────────────────────────────────────────
log ""
log "============================================================"
log "  After governance proposal passes — verify new ownership:"
log "============================================================"
log ""
log "  Run: ./check-contract-config.sh"
log "  Or manually:"
log ""
log "  LCD=$LCD"
for addr in $MAILBOX $ISM_ROUTING $IGP $HOOK_FEE; do
  log "  curl -s \"\$LCD/cosmwasm/wasm/v1/contract/$addr/smart/\$(echo -n '{\"ownable\":{\"get_owner\":{}}}' | base64 -w0)\" | jq .data.owner"
done
log ""
log "  Expected: \"$GOVERNANCE\""
log ""
log "  Full log saved to: $LOG_FILE"
log "============================================================"
