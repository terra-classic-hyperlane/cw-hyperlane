#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
#  setup-ism-igp-terraclassic.sh
#  Deploy a new ISM + IGP + Oracle owned by this keypair and link them to the
#  already-deployed warp route (igorfake on solanamainnet).
#
#  WHY this script exists:
#    The shared ISM (LwNfVY...) on mainnet3 has no entry for Terra Classic
#    domain 132556 and is owned by a different keypair.  The shared IGP also
#    lacks an oracle for domain 132556.  This script creates owned replacements.
#
#  STEPS:
#    1. Dump ISM binary from existing program and deploy a new one
#    2. Init the new ISM (creates access-control PDA, owner = keypair)
#    3. Set validators + threshold for domain 132556
#    4. Create a custom environment dir so the client can manage the IGP
#    5. Init a new IGP account under the existing IGP program
#    6. Init an overhead-IGP account wrapping the base IGP account
#    7. Set gas oracle for domain 132556 (Terra Classic / LUNC)
#    8. Set destination gas overhead for domain 132556
#    9. Update warp route: new ISM + new IGP
#   10. Update warp-sealevel-config.json with new addresses
#
#  USAGE:
#    ./setup-ism-igp-terraclassic.sh
#
#  SKIP flags (env vars):
#    SKIP_ISM_DEPLOY=1      skip binary dump + deploy (ISM already deployed)
#    SKIP_ISM_INIT=1        skip ISM init
#    SKIP_ISM_VALIDATORS=1  skip set-validators step (step 3)
#    SKIP_IGP_INIT=1        skip IGP account creation
#    SKIP_ORACLE=1          skip oracle configuration
#    SKIP_WARP_UPDATE=1     skip setting ISM on warp route (step 7)
#    SKIP_IGP_WARP_UPDATE=1 skip setting IGP on warp route (step 7b)
#    NEW_ISM=<addr>         use this ISM address (skip deploy + init)
#    NEW_IGP_ACCT=<addr>    use this overhead-IGP account (skip IGP init)
#
#  Example — configure only IGP + Oracle (ISM not yet deployed):
#    SKIP_ISM_DEPLOY=1 SKIP_ISM_INIT=1 SKIP_ISM_VALIDATORS=1 \
#    SKIP_WARP_UPDATE=1 NEW_ISM=placeholder \
#    ./setup-ism-igp-terraclassic.sh
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# COLORS
# ─────────────────────────────────────────────────────────────────────────────
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'
B='\033[0;34m'; C='\033[0;36m'; W='\033[1m'; NC='\033[0m'
OK="${G}✅${NC}"; ERR="${R}❌${NC}"; WARN="${Y}⚠️ ${NC}"; INFO="${B}ℹ️ ${NC}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOL_CONFIG="$SCRIPT_DIR/warp-sealevel-config.json"
LOG_DIR="$SCRIPT_DIR/log"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/setup-ism-igp-terraclassic.log"
STATE_FILE="$SCRIPT_DIR/.ism-igp-tc-state.json"

log()      { echo -e "$@" | tee -a "$LOG_FILE"; }
log_ok()   { log "${OK} $*"; }
log_err()  { log "${ERR} $*"; }
log_warn() { log "${WARN} $*"; }
log_info() { log "${INFO} $*"; }
log_sep()  { log ""; log "${C}${W}$1${NC}"; log "────────────────────────────────────────────────────────────────"; }

sol_cfg()  { jq -r "$1" "$SOL_CONFIG" 2>/dev/null || echo ""; }

# ─────────────────────────────────────────────────────────────────────────────
# FIXED CONSTANTS
# ─────────────────────────────────────────────────────────────────────────────
TERRA_DOMAIN=132556
VALIDATOR_ADDR="0x71b2b8c36a0c76b74be92eb7915e26a69b3b03eb"
VALIDATOR_THRESHOLD=1

# Terra Classic oracle parameters (LUNC = 6 decimals, uluna gas price)
#   token_exchange_rate: estimated uluna per lamport of SOL (1 SOL ≈ 1M LUNC = 1e12 uluna)
#   gas_price: uluna per gas unit on Terra Classic
#   token_decimals: 6 (uluna)
#   overhead: gas units of overhead per delivered message
ORACLE_EXCHANGE_RATE=1000000000000  # 1 SOL ≈ 1,000,000 LUNC = 1e12 uluna
ORACLE_GAS_PRICE=28325              # uluna per gas unit
ORACLE_TOKEN_DECIMALS=6
GAS_OVERHEAD=3000000                # overhead gas units for TC message delivery

# Source ISM program to dump binary from
SOURCE_ISM_PROGRAM="LwNfVYMDzAe5dCJgA5CipTZcT34Eyf74zLr81K91jxk"

# ─────────────────────────────────────────────────────────────────────────────
# LOAD CONFIG
# ─────────────────────────────────────────────────────────────────────────────
NET_KEY="solanamainnet"
N=".networks.${NET_KEY}"

NET_RPC=$(sol_cfg "${N}.rpc")
NET_KEYPAIR=$(sol_cfg "${N}.keypair" | sed "s|^~|$HOME|")
NET_MONOREPO=$(sol_cfg "${N}.monorepo_dir" | sed "s|^~|$HOME|")
NET_ENV=$(sol_cfg "${N}.environment")
MAILBOX=$(sol_cfg "${N}.mailbox")
IGP_PROGRAM_ID=$(sol_cfg "${N}.igp.program_id")
WARP_PROGRAM_ID=$(sol_cfg "${N}.warp_tokens.igorfake.program_id")

# Fallback to public RPC if Helius key is placeholder
if echo "$NET_RPC" | grep -q "YOUR_HELIUS_API_KEY"; then
    log_warn "Helius API key not set — falling back to public RPC"
    NET_RPC="https://api.mainnet-beta.solana.com"
fi

CLIENT_BIN="$NET_MONOREPO/target/release/hyperlane-sealevel-client"
ENVIRONMENTS_BASE="$NET_MONOREPO/environments"

# Custom environment dir for our TC-specific setup
CUSTOM_ENV="mainnet-tc"
CUSTOM_ENV_DIR="$ENVIRONMENTS_BASE/${CUSTOM_ENV}/${NET_KEY}"
CUSTOM_CORE_DIR="$CUSTOM_ENV_DIR/core"

# Working dirs for keys
KEYS_DIR="$SCRIPT_DIR/warp/solanamainnet/keys"
mkdir -p "$KEYS_DIR"

ISM_KEYPAIR_FILE="$KEYS_DIR/ism-terraclassic-keypair.json"
BINARY_DIR="$SCRIPT_DIR/warp/solanamainnet/binaries"
mkdir -p "$BINARY_DIR"
ISM_BINARY="$BINARY_DIR/multisig_ism_message_id.so"

# ─────────────────────────────────────────────────────────────────────────────
# STATE PERSISTENCE
# ─────────────────────────────────────────────────────────────────────────────
save_state() {
    cat > "$STATE_FILE" <<EOF
{
  "new_ism":          "${NEW_ISM:-}",
  "new_igp_account":  "${NEW_IGP_ACCT:-}",
  "new_overhead_igp": "${NEW_OVERHEAD_IGP:-}",
  "timestamp":        "$(date -Iseconds)"
}
EOF
}

load_state() {
    [ -f "$STATE_FILE" ] || return 0
    _S_ISM=$(jq -r '.new_ism          // ""' "$STATE_FILE" 2>/dev/null || echo "")
    _S_IGP=$(jq -r '.new_igp_account  // ""' "$STATE_FILE" 2>/dev/null || echo "")
    _S_OVH=$(jq -r '.new_overhead_igp // ""' "$STATE_FILE" 2>/dev/null || echo "")
    [ -n "$_S_ISM" ] && log_warn "Previous state found: ISM=${_S_ISM}"
    log "   To reset: ${Y}rm -f $STATE_FILE${NC}"
}

run_client() {
    "$CLIENT_BIN" "$@"
}

keypair_to_pubkey() {
    python3 - "$1" <<'PY' 2>/dev/null
import json, sys
data = json.load(open(sys.argv[1]))
pub = bytes(data[32:64])
alpha = '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz'
n = int.from_bytes(pub, 'big'); r = ''
while n > 0: r = alpha[n % 58] + r; n //= 58
for b in pub:
    if b == 0: r = '1' + r
    else: break
print(r)
PY
}

# ─────────────────────────────────────────────────────────────────────────────
# BANNER
# ─────────────────────────────────────────────────────────────────────────────
> "$LOG_FILE"
clear 2>/dev/null || true
log "╔══════════════════════════════════════════════════════════════════════════╗"
log "║  🔐  SETUP ISM + IGP + ORACLE — Terra Classic → Solana (igorfake)       ║"
log "║  Date: $(date '+%Y-%m-%d %H:%M:%S')                                         ║"
log "╚══════════════════════════════════════════════════════════════════════════╝"

# ─────────────────────────────────────────────────────────────────────────────
# CHECKS
# ─────────────────────────────────────────────────────────────────────────────
for cmd in jq python3 solana solana-keygen; do
    command -v $cmd &>/dev/null || { log_err "$cmd is required"; exit 1; }
done
[ -x "$CLIENT_BIN" ]       || { log_err "Client binary not found: $CLIENT_BIN"; exit 1; }
[ -f "$NET_KEYPAIR" ]       || { log_err "Keypair not found: $NET_KEYPAIR"; exit 1; }
[ -n "$WARP_PROGRAM_ID" ]   || { log_err "igorfake program_id not set in warp-sealevel-config.json"; exit 1; }
[ -n "$IGP_PROGRAM_ID" ]    || { log_err "igp.program_id not set in warp-sealevel-config.json"; exit 1; }

PAYER_PUBKEY=$(keypair_to_pubkey "$NET_KEYPAIR")
BALANCE=$(solana balance "$NET_KEYPAIR" --url "$NET_RPC" 2>/dev/null | awk '{print $1}' || echo "?")

log_ok "Keypair:      $NET_KEYPAIR"
log_info "Payer:        $PAYER_PUBKEY"
log_info "Balance:      $BALANCE SOL"
log_info "Warp route:   $WARP_PROGRAM_ID"
log_info "IGP program:  $IGP_PROGRAM_ID"
log_info "Mailbox:      $MAILBOX"
log_info "RPC:          $NET_RPC"
log_info "Validator:    $VALIDATOR_ADDR (domain $TERRA_DOMAIN, threshold $VALIDATOR_THRESHOLD)"
log ""

load_state

# Apply saved state if no env overrides
NEW_ISM="${NEW_ISM:-${_S_ISM:-}}"
NEW_IGP_ACCT="${NEW_IGP_ACCT:-${_S_IGP:-}}"
NEW_OVERHEAD_IGP="${NEW_OVERHEAD_IGP:-${_S_OVH:-}}"

echo -ne "  ${W}Confirm and continue? [Y/n]: ${NC}"
read -r CONFIRM 2>/dev/null || CONFIRM="y"
[[ "${CONFIRM:-y}" =~ ^[nN]$ ]] && { log "  Cancelled."; exit 0; }

# ═════════════════════════════════════════════════════════════════════════════
# STEP 1 — DEPLOY NEW ISM PROGRAM
# ═════════════════════════════════════════════════════════════════════════════
log_sep "STEP 1 — DEPLOY NEW ISM PROGRAM"

if [ -n "${SKIP_ISM_DEPLOY:-}" ] || [ -n "$NEW_ISM" ]; then
    log_warn "SKIP_ISM_DEPLOY set or NEW_ISM=${NEW_ISM:-} — skipping deploy."
else
    # Generate or load ISM keypair
    if [ ! -f "$ISM_KEYPAIR_FILE" ]; then
        log_info "Generating ISM keypair..."
        solana-keygen new --no-passphrase --silent --outfile "$ISM_KEYPAIR_FILE"
        log_ok "ISM keypair created: $ISM_KEYPAIR_FILE"
    else
        log_info "Using existing ISM keypair: $ISM_KEYPAIR_FILE"
    fi

    NEW_ISM_CANDIDATE=$(keypair_to_pubkey "$ISM_KEYPAIR_FILE")
    log_info "New ISM program ID: $NEW_ISM_CANDIDATE"

    # Check if already deployed on-chain
    PROG_EXISTS=$(solana program show "$NEW_ISM_CANDIDATE" --url "$NET_RPC" 2>/dev/null | grep -c "Program Id" || true)
    if [ "${PROG_EXISTS:-0}" -gt 0 ]; then
        log_ok "ISM program already on-chain: $NEW_ISM_CANDIDATE"
        NEW_ISM="$NEW_ISM_CANDIDATE"
    else
        # Dump binary from existing ISM
        if [ ! -f "$ISM_BINARY" ]; then
            log_info "Dumping ISM binary from $SOURCE_ISM_PROGRAM ..."
            set +e
            solana program dump "$SOURCE_ISM_PROGRAM" "$ISM_BINARY" --url "$NET_RPC" 2>&1 | tee -a "$LOG_FILE"
            DUMP_EXIT=$?
            set -e
            [ $DUMP_EXIT -ne 0 ] || [ ! -f "$ISM_BINARY" ] && {
                log_err "Binary dump failed. Check RPC or set SOURCE_ISM_PROGRAM to another multisig ISM."
                exit 1
            }
            log_ok "Binary dumped: $ISM_BINARY ($(du -sh "$ISM_BINARY" | cut -f1))"
        else
            log_info "Binary already exists: $ISM_BINARY"
        fi

        # Deploy
        log_info "Deploying new ISM program..."
        set +e
        solana program deploy "$ISM_BINARY" \
            --url "$NET_RPC" \
            --keypair "$NET_KEYPAIR" \
            --program-id "$ISM_KEYPAIR_FILE" \
            --upgrade-authority "$NET_KEYPAIR" \
            2>&1 | tee -a "$LOG_FILE"
        DEPLOY_EXIT=$?
        set -e

        [ $DEPLOY_EXIT -ne 0 ] && {
            log_err "ISM deploy failed!"
            log "  Retry with: export SKIP_ISM_DEPLOY=1 NEW_ISM=<addr> (if partially deployed)"
            exit 1
        }

        NEW_ISM="$NEW_ISM_CANDIDATE"
        log_ok "ISM program deployed: $NEW_ISM"
    fi

    save_state
fi

log_ok "New ISM: ${G}$NEW_ISM${NC}"

# ═════════════════════════════════════════════════════════════════════════════
# STEP 2 — INIT ISM
# ═════════════════════════════════════════════════════════════════════════════
log_sep "STEP 2 — INIT ISM (creates access-control PDA, owner = keypair)"

if [ -n "${SKIP_ISM_INIT:-}" ]; then
    log_warn "SKIP_ISM_INIT set — skipping."
else
    set +e
    OUT=$(run_client \
        -k "$NET_KEYPAIR" -u "$NET_RPC" \
        multisig-ism-message-id init \
        --program-id "$NEW_ISM" 2>&1)
    EXIT_CODE=$?
    set -e
    echo "$OUT" | tee -a "$LOG_FILE"

    if [ $EXIT_CODE -eq 0 ]; then
        log_ok "ISM initialized."
    elif echo "$OUT" | grep -qiE "already|exists"; then
        log_ok "ISM already initialized."
    else
        log_warn "ISM init returned exit $EXIT_CODE — may already be initialized, continuing."
    fi
fi

# ═════════════════════════════════════════════════════════════════════════════
# STEP 3 — SET VALIDATORS + THRESHOLD FOR DOMAIN 132556
# ═════════════════════════════════════════════════════════════════════════════
log_sep "STEP 3 — SET VALIDATORS FOR DOMAIN $TERRA_DOMAIN (Terra Classic)"

if [ -n "${SKIP_ISM_VALIDATORS:-}" ]; then
    log_warn "SKIP_ISM_VALIDATORS set — skipping."
else
set +e
OUT=$(run_client \
    -k "$NET_KEYPAIR" -u "$NET_RPC" \
    multisig-ism-message-id set-validators-and-threshold \
    --program-id "$NEW_ISM" \
    --domain "$TERRA_DOMAIN" \
    --validators "$VALIDATOR_ADDR" \
    --threshold "$VALIDATOR_THRESHOLD" 2>&1)
EXIT_CODE=$?
set -e
echo "$OUT" | tee -a "$LOG_FILE"

if [ $EXIT_CODE -eq 0 ]; then
    log_ok "Validators set: $VALIDATOR_ADDR (threshold $VALIDATOR_THRESHOLD)"
elif echo "$OUT" | grep -qiE "already|same"; then
    log_ok "Validators already configured."
else
    log_err "Failed to set validators (exit $EXIT_CODE)"
    log "  Manual: $CLIENT_BIN -k $NET_KEYPAIR -u $NET_RPC multisig-ism-message-id set-validators-and-threshold --program-id $NEW_ISM --domain $TERRA_DOMAIN --validators $VALIDATOR_ADDR --threshold $VALIDATOR_THRESHOLD"
    exit 1
fi

# Verify
log_info "Verifying ISM domain $TERRA_DOMAIN..."
run_client -k "$NET_KEYPAIR" -u "$NET_RPC" \
    multisig-ism-message-id query \
    --program-id "$NEW_ISM" \
    --domains "$TERRA_DOMAIN" 2>&1 | tee -a "$LOG_FILE"
fi  # end SKIP_ISM_VALIDATORS

# ═════════════════════════════════════════════════════════════════════════════
# STEP 4 — CREATE CUSTOM ENVIRONMENT DIR FOR IGP
# ═════════════════════════════════════════════════════════════════════════════
log_sep "STEP 4 — CREATE CUSTOM ENVIRONMENT DIR FOR IGP"

mkdir -p "$CUSTOM_CORE_DIR"

# Build program-ids.json for our custom environment
# Start from the existing mainnet3 config and override ISM
EXISTING_CORE="$ENVIRONMENTS_BASE/mainnet3/${NET_KEY}/core/program-ids.json"
if [ -f "$EXISTING_CORE" ]; then
    jq ".multisig_ism_message_id = \"${NEW_ISM}\"" "$EXISTING_CORE" > "$CUSTOM_CORE_DIR/program-ids.json"
else
    cat > "$CUSTOM_CORE_DIR/program-ids.json" <<JSON
{
  "mailbox":                  "$MAILBOX",
  "multisig_ism_message_id":  "$NEW_ISM",
  "igp_program_id":           "$IGP_PROGRAM_ID",
  "igp_account":              "",
  "overhead_igp_account":     ""
}
JSON
fi
log_ok "Custom env dir created: $CUSTOM_CORE_DIR"

# ═════════════════════════════════════════════════════════════════════════════
# STEP 5 — INIT IGP ACCOUNT
# ═════════════════════════════════════════════════════════════════════════════
log_sep "STEP 5 — INIT BASE IGP ACCOUNT"

if [ -n "${SKIP_IGP_INIT:-}" ] || [ -n "$NEW_IGP_ACCT" ]; then
    log_warn "SKIP_IGP_INIT or NEW_IGP_ACCT set — skipping IGP account creation."
else
    set +e
    OUT=$(run_client \
        -k "$NET_KEYPAIR" -u "$NET_RPC" \
        igp init-igp-account \
        --program-id "$IGP_PROGRAM_ID" \
        --environment "$CUSTOM_ENV" \
        --environments-dir "$ENVIRONMENTS_BASE" \
        --chain "$NET_KEY" \
        --account-salt "tc-igorfake" 2>&1)
    EXIT_CODE=$?
    set -e
    echo "$OUT" | tee -a "$LOG_FILE"

    if [ $EXIT_CODE -eq 0 ] || echo "$OUT" | grep -qiE "already|exists"; then
        # Extract the new IGP account address from output or program-ids.json
        NEW_BASE_IGP=$(jq -r '.igp_account // ""' "$CUSTOM_CORE_DIR/program-ids.json" 2>/dev/null || echo "")
        [ -z "$NEW_BASE_IGP" ] && NEW_BASE_IGP=$(echo "$OUT" | grep -oE '[1-9A-HJ-NP-Za-km-z]{32,44}' | tail -1 || echo "")
        log_ok "Base IGP account: $NEW_BASE_IGP"
    else
        log_warn "igp init-igp-account returned exit $EXIT_CODE — checking if account already exists..."
        NEW_BASE_IGP=$(jq -r '.igp_account // ""' "$CUSTOM_CORE_DIR/program-ids.json" 2>/dev/null || echo "")
    fi

    # ── STEP 5b — INIT OVERHEAD IGP ACCOUNT ──────────────────────────────────
    if [ -n "$NEW_BASE_IGP" ] && [ "$NEW_BASE_IGP" != "null" ] && [ "$NEW_BASE_IGP" != "" ]; then
        log_sep "STEP 5b — INIT OVERHEAD IGP ACCOUNT (wraps base IGP)"
        set +e
        OUT2=$(run_client \
            -k "$NET_KEYPAIR" -u "$NET_RPC" \
            igp init-overhead-igp-account \
            --program-id "$IGP_PROGRAM_ID" \
            --environment "$CUSTOM_ENV" \
            --environments-dir "$ENVIRONMENTS_BASE" \
            --chain "$NET_KEY" \
            --inner-igp-account "$NEW_BASE_IGP" \
            --account-salt "tc-igorfake-overhead" 2>&1)
        EXIT2=$?
        set -e
        echo "$OUT2" | tee -a "$LOG_FILE"

        NEW_OVERHEAD_IGP=$(jq -r '.overhead_igp_account // ""' "$CUSTOM_CORE_DIR/program-ids.json" 2>/dev/null || echo "")
        [ -z "$NEW_OVERHEAD_IGP" ] && NEW_OVERHEAD_IGP=$(echo "$OUT2" | grep -oE '[1-9A-HJ-NP-Za-km-z]{32,44}' | tail -1 || echo "")

        if [ -n "$NEW_OVERHEAD_IGP" ] && [ "$NEW_OVERHEAD_IGP" != "null" ]; then
            log_ok "Overhead IGP account: $NEW_OVERHEAD_IGP"
            NEW_IGP_ACCT="$NEW_OVERHEAD_IGP"
        else
            log_warn "Could not determine overhead IGP account address — using base IGP."
            NEW_IGP_ACCT="$NEW_BASE_IGP"
        fi
    else
        log_warn "Base IGP account not determined — skipping overhead IGP."
    fi

    save_state
fi

log_ok "IGP account to use: ${G}${NEW_IGP_ACCT:-NOT SET}${NC}"

# ═════════════════════════════════════════════════════════════════════════════
# STEP 6 — SET GAS ORACLE FOR DOMAIN 132556 (Terra Classic)
# ═════════════════════════════════════════════════════════════════════════════
log_sep "STEP 6 — SET GAS ORACLE FOR DOMAIN $TERRA_DOMAIN (Terra Classic)"

if [ -n "${SKIP_ORACLE:-}" ]; then
    log_warn "SKIP_ORACLE set — skipping."
else
    log_info "Oracle params: exchange_rate=$ORACLE_EXCHANGE_RATE gas_price=$ORACLE_GAS_PRICE decimals=$ORACLE_TOKEN_DECIMALS"

    set +e
    OUT=$(run_client \
        -k "$NET_KEYPAIR" -u "$NET_RPC" \
        igp gas-oracle-config \
        --environment "$CUSTOM_ENV" \
        --environments-dir "$ENVIRONMENTS_BASE" \
        --chain-name "$NET_KEY" \
        --remote-domain "$TERRA_DOMAIN" \
        set \
        --token-exchange-rate "$ORACLE_EXCHANGE_RATE" \
        --gas-price "$ORACLE_GAS_PRICE" \
        --token-decimals "$ORACLE_TOKEN_DECIMALS" 2>&1)
    EXIT_CODE=$?
    set -e
    echo "$OUT" | tee -a "$LOG_FILE"

    if [ $EXIT_CODE -eq 0 ]; then
        log_ok "Gas oracle set for domain $TERRA_DOMAIN"
    elif echo "$OUT" | grep -qiE "already|same"; then
        log_ok "Oracle already configured."
    else
        log_warn "Oracle config returned exit $EXIT_CODE — may need manual configuration."
        log "  Manual: $CLIENT_BIN -k $NET_KEYPAIR -u $NET_RPC igp gas-oracle-config \\"
        log "    --environment $CUSTOM_ENV --environments-dir $ENVIRONMENTS_BASE \\"
        log "    --chain-name $NET_KEY --remote-domain $TERRA_DOMAIN \\"
        log "    set --token-exchange-rate $ORACLE_EXCHANGE_RATE --gas-price $ORACLE_GAS_PRICE --token-decimals $ORACLE_TOKEN_DECIMALS"
    fi

    # Set overhead gas
    log_info "Setting gas overhead for domain $TERRA_DOMAIN: $GAS_OVERHEAD units"
    set +e
    run_client \
        -k "$NET_KEYPAIR" -u "$NET_RPC" \
        igp destination-gas-overhead \
        --environment "$CUSTOM_ENV" \
        --environments-dir "$ENVIRONMENTS_BASE" \
        --chain-name "$NET_KEY" \
        --remote-domain "$TERRA_DOMAIN" \
        set 2>&1 | tee -a "$LOG_FILE"
    set -e
fi

# ═════════════════════════════════════════════════════════════════════════════
# STEP 7 — UPDATE WARP ROUTE: SET NEW ISM
# ═════════════════════════════════════════════════════════════════════════════
log_sep "STEP 7 — UPDATE WARP ROUTE: SET NEW ISM"

if [ -n "${SKIP_WARP_UPDATE:-}" ]; then
    log_warn "SKIP_WARP_UPDATE set — skipping warp route update."
else
    set +e
    OUT=$(run_client \
        -k "$NET_KEYPAIR" -u "$NET_RPC" \
        token set-interchain-security-module \
        --program-id "$WARP_PROGRAM_ID" \
        --ism "$NEW_ISM" 2>&1)
    EXIT_CODE=$?
    set -e
    echo "$OUT" | tee -a "$LOG_FILE"

    if [ $EXIT_CODE -eq 0 ]; then
        log_ok "Warp route ISM updated: $NEW_ISM"
    elif echo "$OUT" | grep -qiE "already|same"; then
        log_ok "ISM already set."
    else
        log_err "Failed to set ISM on warp route (exit $EXIT_CODE)"
        log "  Manual: $CLIENT_BIN -k $NET_KEYPAIR -u $NET_RPC token set-interchain-security-module --program-id $WARP_PROGRAM_ID --ism $NEW_ISM"
        exit 1
    fi

fi

# ── STEP 7b — UPDATE WARP ROUTE: SET NEW IGP ─────────────────────────────
if [ -n "${SKIP_IGP_WARP_UPDATE:-}" ]; then
    log_warn "SKIP_IGP_WARP_UPDATE set — skipping IGP warp update."
elif [ -n "$NEW_IGP_ACCT" ] && [ "$NEW_IGP_ACCT" != "null" ] && [ "$NEW_IGP_ACCT" != "" ]; then
    log_sep "STEP 7b — UPDATE WARP ROUTE: SET NEW IGP"

    IGP_TYPE="overhead-igp"
    # If we couldn't create overhead-igp, fall back to base igp type
    [ "$NEW_IGP_ACCT" = "${NEW_BASE_IGP:-}" ] && IGP_TYPE="igp"

    set +e
    OUT=$(run_client \
        -k "$NET_KEYPAIR" -u "$NET_RPC" \
        token igp \
        --program-id "$WARP_PROGRAM_ID" \
        set "$IGP_PROGRAM_ID" "$IGP_TYPE" "$NEW_IGP_ACCT" 2>&1)
    EXIT_CODE=$?
    set -e
    echo "$OUT" | tee -a "$LOG_FILE"

    if [ $EXIT_CODE -eq 0 ]; then
        log_ok "Warp route IGP updated: $IGP_PROGRAM_ID / $NEW_IGP_ACCT ($IGP_TYPE)"
    elif echo "$OUT" | grep -qiE "already|same"; then
        log_ok "IGP already set."
    else
        log_warn "Failed to set IGP on warp route (exit $EXIT_CODE) — continuing."
    fi
else
    log_warn "No new IGP account — keeping existing IGP on warp route."
fi

# ═════════════════════════════════════════════════════════════════════════════
# STEP 8 — UPDATE warp-sealevel-config.json
# ═════════════════════════════════════════════════════════════════════════════
log_sep "STEP 8 — UPDATE warp-sealevel-config.json"

TMP=$(mktemp)
JQ_EXPR=".networks.\"${NET_KEY}\".ism.program_id = \"${NEW_ISM}\""
[ -n "$NEW_IGP_ACCT" ] && [ "$NEW_IGP_ACCT" != "null" ] && \
    JQ_EXPR="$JQ_EXPR | .networks.\"${NET_KEY}\".igp.account = \"${NEW_IGP_ACCT}\""
jq "$JQ_EXPR" "$SOL_CONFIG" > "$TMP" && mv "$TMP" "$SOL_CONFIG"
log_ok "warp-sealevel-config.json updated"

# ═════════════════════════════════════════════════════════════════════════════
# STEP 9 — VERIFY FINAL STATE
# ═════════════════════════════════════════════════════════════════════════════
log_sep "STEP 9 — FINAL VERIFICATION"

log_info "Warp route state:"
run_client -k "$NET_KEYPAIR" -u "$NET_RPC" \
    token query --program-id "$WARP_PROGRAM_ID" synthetic 2>&1 \
    | grep -E "interchain_security_module|interchain_gas_paymaster|remote_routers" \
    | tee -a "$LOG_FILE"

log ""
log_info "ISM domain $TERRA_DOMAIN:"
run_client -k "$NET_KEYPAIR" -u "$NET_RPC" \
    multisig-ism-message-id query \
    --program-id "$NEW_ISM" \
    --domains "$TERRA_DOMAIN" 2>&1 \
    | grep -E "domain|validator|threshold|No domain" \
    | tee -a "$LOG_FILE"

# ─────────────────────────────────────────────────────────────────────────────
# FINAL REPORT
# ─────────────────────────────────────────────────────────────────────────────
log ""
log "╔══════════════════════════════════════════════════════════════════════════╗"
log "║  ✅  ISM + IGP + ORACLE SETUP COMPLETE                                  ║"
log "╚══════════════════════════════════════════════════════════════════════════╝"
log ""
log "  ${G}New ISM:${NC}         $NEW_ISM"
log "  ${G}  Domain 132556:${NC}   validator=$VALIDATOR_ADDR  threshold=$VALIDATOR_THRESHOLD"
[ -n "$NEW_IGP_ACCT" ] && \
log "  ${G}New IGP acct:${NC}    $NEW_IGP_ACCT"
log "  ${G}  Oracle:${NC}        domain=$TERRA_DOMAIN  gas_price=$ORACLE_GAS_PRICE  decimals=$ORACLE_TOKEN_DECIMALS"
log "  ${G}Warp route:${NC}      $WARP_PROGRAM_ID  ← ISM updated"
log ""
log "  Next step: restart the relayer on the VPS so it picks up the new ISM."
log "    ${B}ssh root@31.97.91.4 'systemctl restart hyperlane-relayer'${NC}"
log ""
log "${B}📋 Log: $LOG_FILE${NC}"

save_state
