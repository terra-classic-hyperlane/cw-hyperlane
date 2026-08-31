#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
#  update-warp-solana.sh — Update ISM, IGP, Oracle, and Router settings
#  on an already-deployed Hyperlane Warp Route on Solana
# ═══════════════════════════════════════════════════════════════════════════════
#
#  USAGE:
#    ./update-warp-solana.sh
#
#  WHAT THIS SCRIPT CAN DO:
#    1. Update ISM  — change the MultisigISM that validates incoming messages
#    2. Update IGP  — change the gas paymaster program/account
#    3. Update destination gas amount (gas units sent to Terra Classic per message)
#    4. Update gas oracle (token exchange rate + gas price for a remote domain)
#    5. Update gas overhead (overhead gas units added per message for a domain)
#    6. Enroll / update a remote router (Solana → Terra Classic link)
#    7. Query current state (ISM, IGP, oracle, routers, gas)
#    8. Transfer program ownership
#
#  REQUIREMENTS:
#    - warp-sealevel-config.json with the deployed warp route program_id
#    - Solana keypair with authority over the warp program
#    - Pre-compiled hyperlane-sealevel-client binary
#
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
EVM_CONFIG="$SCRIPT_DIR/warp-evm-config.json"
LOG_DIR="$SCRIPT_DIR/log"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/update-warp-solana.log"

log()      { echo -e "$@" | tee -a "$LOG_FILE"; }
log_ok()   { log "${OK} $*"; }
log_err()  { log "${ERR} $*"; }
log_warn() { log "${WARN} $*"; }
log_info() { log "${INFO} $*"; }
log_sep()  { log ""; log "${C}${W}$1${NC}"; log "────────────────────────────────────────────────────────────────"; }

sol_cfg()  { jq -r "$1" "$SOL_CONFIG" 2>/dev/null || echo ""; }
evm_cfg()  { jq -r "$1" "$EVM_CONFIG" 2>/dev/null || echo ""; }

> "$LOG_FILE"
clear 2>/dev/null || true

log "╔══════════════════════════════════════════════════════════════════════════╗"
log "║  🔧  UPDATE WARP ROUTE SOLANA — ISM / IGP / Oracle / Router            ║"
log "║  Date: $(date '+%Y-%m-%d %H:%M:%S')                                         ║"
log "╚══════════════════════════════════════════════════════════════════════════╝"
log ""

# ─────────────────────────────────────────────────────────────────────────────
# CHECKS
# ─────────────────────────────────────────────────────────────────────────────
[ -f "$SOL_CONFIG" ] || { log_err "warp-sealevel-config.json not found!"; exit 1; }
command -v jq &>/dev/null || { log_err "jq is required"; exit 1; }

# ─────────────────────────────────────────────────────────────────────────────
# MENU 1 — SELECT TOKEN
# ─────────────────────────────────────────────────────────────────────────────
log_sep "SELECT TOKEN"
mapfile -t TOKEN_KEYS < <(jq -r '.terra_classic.tokens | keys[]' "$EVM_CONFIG" 2>/dev/null)
declare -a TOKEN_MENU=()
i=1
for TK in "${TOKEN_KEYS[@]}"; do
    TK_NAME=$(evm_cfg ".terra_classic.tokens.${TK}.name")
    TK_SYM=$(evm_cfg  ".terra_classic.tokens.${TK}.symbol")
    TOKEN_MENU+=("$TK")
    log "  [${W}$i${NC}]  ${C}${TK}${NC} — ${TK_NAME:-N/A} (${TK_SYM:-?})"
    i=$((i+1))
done
echo -ne "  ${W}Token [1-${#TOKEN_MENU[@]}]: ${NC}"; read -r SEL_TOK 2>/dev/null || SEL_TOK="1"
SEL_TOK="${SEL_TOK:-1}"
[[ "$SEL_TOK" =~ ^[0-9]+$ ]] && [ "$SEL_TOK" -ge 1 ] && [ "$SEL_TOK" -le "${#TOKEN_MENU[@]}" ] \
    || { log_err "Invalid selection"; exit 1; }
TOKEN_KEY="${TOKEN_MENU[$((SEL_TOK-1))]}"
log_ok "Token: ${C}${TOKEN_KEY}${NC}"

# ─────────────────────────────────────────────────────────────────────────────
# MENU 2 — SELECT NETWORK
# ─────────────────────────────────────────────────────────────────────────────
log_sep "SELECT SOLANA NETWORK"
mapfile -t NET_KEYS < <(jq -r '.networks | to_entries[] | select(.value.enabled==true) | .key' "$SOL_CONFIG" 2>/dev/null)
declare -a NET_MENU=()
i=1
for NK in "${NET_KEYS[@]}"; do
    ND=$(sol_cfg ".networks.${NK}.display_name")
    SOL_PID=$(sol_cfg ".networks.${NK}.warp_tokens.${TOKEN_KEY}.program_id" 2>/dev/null || echo "")
    NET_MENU+=("$NK")
    [ -n "$SOL_PID" ] && [ "$SOL_PID" != "null" ] && TAG="${G}[deployed: ${SOL_PID:0:12}...]${NC}" || TAG="${Y}[not deployed]${NC}"
    log "  [${W}$i${NC}]  ${C}${NK}${NC} — ${ND} ${TAG}"
    i=$((i+1))
done
echo -ne "  ${W}Network [1-${#NET_MENU[@]}]: ${NC}"; read -r SEL_NET 2>/dev/null || SEL_NET="1"
SEL_NET="${SEL_NET:-1}"
[[ "$SEL_NET" =~ ^[0-9]+$ ]] && [ "$SEL_NET" -ge 1 ] && [ "$SEL_NET" -le "${#NET_MENU[@]}" ] \
    || { log_err "Invalid selection"; exit 1; }
NET_KEY="${NET_MENU[$((SEL_NET-1))]}"
N=".networks.${NET_KEY}"

NET_DISPLAY=$(sol_cfg  "${N}.display_name")
NET_RPC=$(sol_cfg      "${N}.rpc")
NET_DOMAIN=$(sol_cfg   "${N}.domain")
NET_KEYPAIR=$(sol_cfg  "${N}.keypair" | sed "s|^~|$HOME|")
NET_ENV=$(sol_cfg      "${N}.environment")
NET_MONOREPO=$(sol_cfg "${N}.monorepo_dir" | sed "s|^~|$HOME|")
WARP_PROGRAM_ID=$(sol_cfg "${N}.warp_tokens.${TOKEN_KEY}.program_id")
ISM_PROGRAM_ID=$(sol_cfg  "${N}.ism.program_id")
IGP_PROGRAM_ID=$(sol_cfg  "${N}.igp.program_id")
IGP_ACCOUNT=$(sol_cfg     "${N}.igp.account")
DEST_GAS=$(sol_cfg        "${N}.igp.destination_gas_terra")
TERRA_DOMAIN=$(evm_cfg    '.terra_classic.domain')
TERRA_WARP_HEX=$(evm_cfg  ".terra_classic.tokens.${TOKEN_KEY}.terra_warp.warp_hexed")

CLIENT_BIN="$NET_MONOREPO/target/release/hyperlane-sealevel-client"
CLIENT_DIR="$NET_MONOREPO/client"
ENVIRONMENTS_DIR="$NET_MONOREPO/environments"

run_client() {
    if [ -x "$CLIENT_BIN" ]; then
        "$CLIENT_BIN" "$@"
    else
        cd "$CLIENT_DIR"
        cargo run --release --quiet -- "$@"
        cd "$SCRIPT_DIR"
    fi
}

[ ! -f "$NET_KEYPAIR" ] && { log_err "Keypair not found: ${NET_KEYPAIR}"; exit 1; }
[ -z "$WARP_PROGRAM_ID" ] || [ "$WARP_PROGRAM_ID" = "null" ] && {
    log_err "No program_id found for ${TOKEN_KEY} on ${NET_KEY}!"
    log "  Deploy first with: ./deploy-warp-solana-buffer.sh"
    exit 1
}

log_ok "Network:    ${NET_DISPLAY} (domain: ${NET_DOMAIN})"
log_ok "Program ID: ${G}${WARP_PROGRAM_ID}${NC}"
log_ok "Keypair:    ${NET_KEYPAIR}"
log_ok "ISM:        ${ISM_PROGRAM_ID}"
log_ok "IGP:        ${IGP_PROGRAM_ID} / ${IGP_ACCOUNT}"
log ""

# ─────────────────────────────────────────────────────────────────────────────
# MENU 3 — SELECT ACTION
# ─────────────────────────────────────────────────────────────────────────────
log_sep "SELECT ACTION"
log "  [${W}1${NC}]  Query current state (ISM, IGP, oracle, routers, gas)"
log "  [${W}2${NC}]  Update ISM — change the Interchain Security Module"
log "  [${W}3${NC}]  Update IGP — change the Gas Paymaster program/account"
log "  [${W}4${NC}]  Update destination gas amount (gas units per message to Terra Classic)"
log "  [${W}5${NC}]  Update gas oracle (token exchange rate + gas price)"
log "  [${W}6${NC}]  Update gas overhead (overhead gas added per message)"
log "  [${W}7${NC}]  Enroll / update remote router (Solana → Terra Classic)"
log "  [${W}8${NC}]  Transfer program ownership"
log ""
echo -ne "  ${W}Action [1-8]: ${NC}"; read -r ACTION 2>/dev/null || ACTION="1"
ACTION="${ACTION:-1}"

case "$ACTION" in

# ═══════════════════════════════════════════════════════
# 1 — QUERY CURRENT STATE
# ═══════════════════════════════════════════════════════
1)
    log_sep "QUERY — Current Warp Route State"
    log_info "Querying program: ${WARP_PROGRAM_ID}"
    log ""
    set +e
    run_client \
        -k "$NET_KEYPAIR" -u "$NET_RPC" \
        token query --program-id "$WARP_PROGRAM_ID" synthetic 2>&1 \
        | grep -v "^warning:" | grep -v "^note:" \
        | tee -a "$LOG_FILE"
    set -e

    log ""
    log_sep "QUERY — IGP State"
    log_info "IGP Program: ${IGP_PROGRAM_ID}"
    log_info "IGP Account:  ${IGP_ACCOUNT}"
    set +e
    run_client \
        -k "$NET_KEYPAIR" -u "$NET_RPC" \
        igp query \
        --program-id "$IGP_PROGRAM_ID" \
        --igp-account "$IGP_ACCOUNT" 2>&1 \
        | grep -v "^warning:" | grep -v "^note:" \
        | tee -a "$LOG_FILE"
    set -e

    log ""
    log_sep "QUERY — ISM State (domain ${TERRA_DOMAIN})"
    set +e
    run_client \
        -k "$NET_KEYPAIR" -u "$NET_RPC" \
        multisig-ism-message-id query \
        --program-id "$ISM_PROGRAM_ID" \
        --domains "$TERRA_DOMAIN" 2>&1 \
        | grep -v "^warning:" | grep -v "^note:" \
        | tee -a "$LOG_FILE"
    set -e
    ;;

# ═══════════════════════════════════════════════════════
# 2 — UPDATE ISM
# ═══════════════════════════════════════════════════════
2)
    log_sep "UPDATE ISM"
    log_info "Current ISM: ${ISM_PROGRAM_ID}"
    log ""
    echo -ne "  ${W}New ISM program ID (Enter = keep current): ${NC}"
    read -r NEW_ISM 2>/dev/null || NEW_ISM=""
    NEW_ISM="${NEW_ISM:-$ISM_PROGRAM_ID}"

    log_info "Setting ISM to: ${NEW_ISM}"
    set +e
    TMP=$(mktemp)
    run_client \
        -k "$NET_KEYPAIR" -u "$NET_RPC" \
        token set-interchain-security-module \
        --program-id "$WARP_PROGRAM_ID" \
        --ism "$NEW_ISM" 2>&1 \
        | grep -v "^warning:" | grep -v "^note:" \
        | tee -a "$LOG_FILE" "$TMP"
    EXIT_CODE=${PIPESTATUS[0]}
    OUT=$(cat "$TMP"); rm -f "$TMP"
    set -e

    if [ $EXIT_CODE -eq 0 ]; then
        log_ok "ISM updated to: ${G}${NEW_ISM}${NC}"
        # Update config
        TMP2=$(mktemp)
        jq ".networks.\"${NET_KEY}\".ism.program_id = \"${NEW_ISM}\"" \
            "$SOL_CONFIG" > "$TMP2" && mv "$TMP2" "$SOL_CONFIG"
        log_ok "warp-sealevel-config.json updated with new ISM"
    elif echo "$OUT" | grep -qiE "already|same"; then
        log_ok "ISM already set to: ${NEW_ISM}"
    else
        log_err "ISM update failed (exit $EXIT_CODE)"
        log "$OUT" | tail -5
    fi
    ;;

# ═══════════════════════════════════════════════════════
# 3 — UPDATE IGP
# ═══════════════════════════════════════════════════════
3)
    log_sep "UPDATE IGP"
    log_info "Current IGP program: ${IGP_PROGRAM_ID}"
    log_info "Current IGP account: ${IGP_ACCOUNT}"
    log ""
    echo -ne "  ${W}New IGP program ID (Enter = keep current): ${NC}"
    read -r NEW_IGP_PROG 2>/dev/null || NEW_IGP_PROG=""
    NEW_IGP_PROG="${NEW_IGP_PROG:-$IGP_PROGRAM_ID}"

    echo -ne "  ${W}New IGP account (Enter = keep current): ${NC}"
    read -r NEW_IGP_ACCT 2>/dev/null || NEW_IGP_ACCT=""
    NEW_IGP_ACCT="${NEW_IGP_ACCT:-$IGP_ACCOUNT}"

    log ""
    log "  IGP type options:"
    log "    [${W}1${NC}]  igp          (standard IGP)"
    log "    [${W}2${NC}]  overhead-igp (overhead IGP — recommended for mainnet)"
    echo -ne "  ${W}IGP type [1-2, Enter = overhead-igp]: ${NC}"
    read -r IGP_TYPE_SEL 2>/dev/null || IGP_TYPE_SEL="2"
    IGP_TYPE_SEL="${IGP_TYPE_SEL:-2}"
    [ "$IGP_TYPE_SEL" = "1" ] && IGP_TYPE="igp" || IGP_TYPE="overhead-igp"

    log_info "Setting IGP: program=${NEW_IGP_PROG} type=${IGP_TYPE} account=${NEW_IGP_ACCT}"
    set +e
    TMP=$(mktemp)
    run_client \
        -k "$NET_KEYPAIR" -u "$NET_RPC" \
        token igp \
        --program-id "$WARP_PROGRAM_ID" \
        set "$NEW_IGP_PROG" "$IGP_TYPE" "$NEW_IGP_ACCT" 2>&1 \
        | grep -v "^warning:" | grep -v "^note:" \
        | tee -a "$LOG_FILE" "$TMP"
    EXIT_CODE=${PIPESTATUS[0]}
    OUT=$(cat "$TMP"); rm -f "$TMP"
    set -e

    if [ $EXIT_CODE -eq 0 ]; then
        log_ok "IGP updated: program=${G}${NEW_IGP_PROG}${NC} type=${IGP_TYPE} account=${G}${NEW_IGP_ACCT}${NC}"
        TMP2=$(mktemp)
        jq ".networks.\"${NET_KEY}\".igp.program_id = \"${NEW_IGP_PROG}\" |
            .networks.\"${NET_KEY}\".igp.account    = \"${NEW_IGP_ACCT}\"" \
            "$SOL_CONFIG" > "$TMP2" && mv "$TMP2" "$SOL_CONFIG"
        log_ok "warp-sealevel-config.json updated with new IGP"
    elif echo "$OUT" | grep -qiE "already|same"; then
        log_ok "IGP already configured."
    else
        log_err "IGP update failed (exit $EXIT_CODE)"
        log "$OUT" | tail -5
    fi
    ;;

# ═══════════════════════════════════════════════════════
# 4 — UPDATE DESTINATION GAS AMOUNT
# ═══════════════════════════════════════════════════════
4)
    log_sep "UPDATE DESTINATION GAS AMOUNT"
    log_info "Current: domain=${TERRA_DOMAIN} gas=${DEST_GAS}"
    log_info "This controls how many gas units are sent to Terra Classic with each message."
    log_info "Typical value: 3000000 (3M units)"
    log ""
    echo -ne "  ${W}Domain (Enter = ${TERRA_DOMAIN}): ${NC}"
    read -r NEW_DOMAIN 2>/dev/null || NEW_DOMAIN=""
    NEW_DOMAIN="${NEW_DOMAIN:-$TERRA_DOMAIN}"

    echo -ne "  ${W}New gas amount (Enter = keep ${DEST_GAS}): ${NC}"
    read -r NEW_GAS 2>/dev/null || NEW_GAS=""
    NEW_GAS="${NEW_GAS:-$DEST_GAS}"

    log_info "Setting destination gas: domain=${NEW_DOMAIN} gas=${NEW_GAS}"
    set +e
    TMP=$(mktemp)
    run_client \
        -k "$NET_KEYPAIR" -u "$NET_RPC" \
        token set-destination-gas \
        --program-id "$WARP_PROGRAM_ID" \
        "$NEW_DOMAIN" "$NEW_GAS" 2>&1 \
        | grep -v "^warning:" | grep -v "^note:" \
        | tee -a "$LOG_FILE" "$TMP"
    EXIT_CODE=${PIPESTATUS[0]}
    OUT=$(cat "$TMP"); rm -f "$TMP"
    set -e

    if [ $EXIT_CODE -eq 0 ]; then
        log_ok "Destination gas updated: domain=${NEW_DOMAIN} gas=${G}${NEW_GAS}${NC}"
        TMP2=$(mktemp)
        jq ".networks.\"${NET_KEY}\".igp.destination_gas_terra = ${NEW_GAS}" \
            "$SOL_CONFIG" > "$TMP2" && mv "$TMP2" "$SOL_CONFIG"
        log_ok "warp-sealevel-config.json updated"
    elif echo "$OUT" | grep -qiE "already|same"; then
        log_ok "Destination gas already configured."
    else
        log_err "Failed (exit $EXIT_CODE)"
        log "$OUT" | tail -5
    fi
    ;;

# ═══════════════════════════════════════════════════════
# 5 — UPDATE GAS ORACLE
# ═══════════════════════════════════════════════════════
5)
    log_sep "UPDATE GAS ORACLE"
    log_info "The gas oracle sets the token exchange rate and gas price for a remote domain."
    log_info "This is configured on the IGP program, not on the warp route program."
    log ""
    log_info "IGP Program:  ${IGP_PROGRAM_ID}"
    log_info "IGP Account:  ${IGP_ACCOUNT}"
    log_info "Environment:  ${NET_ENV}"
    log ""
    log_warn "This command reads from the environments directory in the monorepo."

    echo -ne "  ${W}Remote domain (Enter = ${TERRA_DOMAIN}): ${NC}"
    read -r ORC_DOMAIN 2>/dev/null || ORC_DOMAIN=""
    ORC_DOMAIN="${ORC_DOMAIN:-$TERRA_DOMAIN}"

    echo -ne "  ${W}Token exchange rate (e.g. 1000000000000000000 = 1.0): ${NC}"
    read -r ORC_EXCH 2>/dev/null || ORC_EXCH=""
    [ -z "$ORC_EXCH" ] && { log_warn "Exchange rate required. Skipping."; exit 0; }

    echo -ne "  ${W}Gas price (in the remote chain's native token, e.g. 28325000000): ${NC}"
    read -r ORC_PRICE 2>/dev/null || ORC_PRICE=""
    [ -z "$ORC_PRICE" ] && { log_warn "Gas price required. Skipping."; exit 0; }

    echo -ne "  ${W}Token decimals (e.g. 18 for LUNC, 9 for SOL): ${NC}"
    read -r ORC_DECS 2>/dev/null || ORC_DECS="18"
    ORC_DECS="${ORC_DECS:-18}"

    log ""
    log_info "Setting oracle: domain=${ORC_DOMAIN} exchange_rate=${ORC_EXCH} gas_price=${ORC_PRICE} decimals=${ORC_DECS}"
    set +e
    TMP=$(mktemp)
    run_client \
        -k "$NET_KEYPAIR" -u "$NET_RPC" \
        igp gas-oracle-config \
        --environment "$NET_ENV" \
        --environments-dir "$ENVIRONMENTS_DIR" \
        --chain-name "$NET_KEY" \
        --remote-domain "$ORC_DOMAIN" \
        set \
        --token-exchange-rate "$ORC_EXCH" \
        --gas-price "$ORC_PRICE" \
        --token-decimals "$ORC_DECS" 2>&1 \
        | grep -v "^warning:" | grep -v "^note:" \
        | tee -a "$LOG_FILE" "$TMP"
    EXIT_CODE=${PIPESTATUS[0]}
    OUT=$(cat "$TMP"); rm -f "$TMP"
    set -e

    if [ $EXIT_CODE -eq 0 ]; then
        log_ok "Gas oracle updated for domain ${ORC_DOMAIN}"
    else
        log_err "Oracle update failed (exit $EXIT_CODE)"
        log "$OUT" | tail -5
        log ""
        log_info "Manual command:"
        log "  $CLIENT_BIN -k $NET_KEYPAIR -u $NET_RPC igp gas-oracle-config \\"
        log "    --environment $NET_ENV --environments-dir $ENVIRONMENTS_DIR \\"
        log "    --chain-name $NET_KEY --remote-domain $ORC_DOMAIN \\"
        log "    set --token-exchange-rate $ORC_EXCH --gas-price $ORC_PRICE --token-decimals $ORC_DECS"
    fi
    ;;

# ═══════════════════════════════════════════════════════
# 6 — UPDATE GAS OVERHEAD
# ═══════════════════════════════════════════════════════
6)
    log_sep "UPDATE GAS OVERHEAD"
    log_info "Gas overhead is extra gas units added on top of the oracle gas estimate."
    log_info "Set on the Overhead IGP account for a specific remote domain."
    log ""
    log_info "IGP Program:  ${IGP_PROGRAM_ID}"
    log_info "IGP Account:  ${IGP_ACCOUNT}"
    log ""
    echo -ne "  ${W}Remote domain (Enter = ${TERRA_DOMAIN}): ${NC}"
    read -r OVH_DOMAIN 2>/dev/null || OVH_DOMAIN=""
    OVH_DOMAIN="${OVH_DOMAIN:-$TERRA_DOMAIN}"

    echo -ne "  ${W}Gas overhead amount (e.g. 200000): ${NC}"
    read -r OVH_GAS 2>/dev/null || OVH_GAS=""
    [ -z "$OVH_GAS" ] && { log_warn "Gas overhead required. Skipping."; exit 0; }

    log_info "Setting gas overhead: domain=${OVH_DOMAIN} overhead=${OVH_GAS}"
    set +e
    TMP=$(mktemp)
    run_client \
        -k "$NET_KEYPAIR" -u "$NET_RPC" \
        igp destination-gas-overhead \
        --environment "$NET_ENV" \
        --environments-dir "$ENVIRONMENTS_DIR" \
        --chain-name "$NET_KEY" \
        --remote-domain "$OVH_DOMAIN" \
        set \
        --gas-overhead "$OVH_GAS" 2>&1 \
        | grep -v "^warning:" | grep -v "^note:" \
        | tee -a "$LOG_FILE" "$TMP"
    EXIT_CODE=${PIPESTATUS[0]}
    OUT=$(cat "$TMP"); rm -f "$TMP"
    set -e

    if [ $EXIT_CODE -eq 0 ]; then
        log_ok "Gas overhead updated: domain=${OVH_DOMAIN} overhead=${G}${OVH_GAS}${NC}"
    else
        log_err "Gas overhead update failed (exit $EXIT_CODE)"
        log "$OUT" | tail -5
        log ""
        log_info "Manual command:"
        log "  $CLIENT_BIN -k $NET_KEYPAIR -u $NET_RPC igp destination-gas-overhead \\"
        log "    --environment $NET_ENV --environments-dir $ENVIRONMENTS_DIR \\"
        log "    --chain-name $NET_KEY --remote-domain $OVH_DOMAIN \\"
        log "    set --gas-overhead $OVH_GAS"
    fi
    ;;

# ═══════════════════════════════════════════════════════
# 7 — ENROLL / UPDATE REMOTE ROUTER
# ═══════════════════════════════════════════════════════
7)
    log_sep "ENROLL / UPDATE REMOTE ROUTER (Solana → Terra Classic)"
    log_info "Current Terra Classic warp address (hex): ${TERRA_WARP_HEX}"
    log ""
    echo -ne "  ${W}Remote domain (Enter = ${TERRA_DOMAIN}): ${NC}"
    read -r ENR_DOMAIN 2>/dev/null || ENR_DOMAIN=""
    ENR_DOMAIN="${ENR_DOMAIN:-$TERRA_DOMAIN}"

    echo -ne "  ${W}Remote router address hex (0x...) (Enter = ${TERRA_WARP_HEX}): ${NC}"
    read -r ENR_HEX 2>/dev/null || ENR_HEX=""
    ENR_HEX="${ENR_HEX:-$TERRA_WARP_HEX}"
    ENR_HEX_CLEAN="${ENR_HEX#0x}"

    log_info "Enrolling: domain=${ENR_DOMAIN} router=0x${ENR_HEX_CLEAN}"
    set +e
    TMP=$(mktemp)
    run_client \
        -k "$NET_KEYPAIR" -u "$NET_RPC" \
        token enroll-remote-router \
        --program-id "$WARP_PROGRAM_ID" \
        "$ENR_DOMAIN" "0x${ENR_HEX_CLEAN}" 2>&1 \
        | grep -v "^warning:" | grep -v "^note:" \
        | tee -a "$LOG_FILE" "$TMP"
    EXIT_CODE=${PIPESTATUS[0]}
    OUT=$(cat "$TMP"); rm -f "$TMP"
    set -e

    if [ $EXIT_CODE -eq 0 ]; then
        log_ok "Remote router enrolled: domain=${ENR_DOMAIN} → 0x${ENR_HEX_CLEAN}"
    elif echo "$OUT" | grep -qiE "already|same|exists"; then
        log_ok "Remote router already enrolled."
    else
        log_err "Enroll failed (exit $EXIT_CODE)"
        log "$OUT" | tail -5
    fi
    ;;

# ═══════════════════════════════════════════════════════
# 8 — TRANSFER OWNERSHIP
# ═══════════════════════════════════════════════════════
8)
    log_sep "TRANSFER PROGRAM OWNERSHIP"
    CURRENT_OWNER=$(sol_cfg ".networks.${NET_KEY}.warp_tokens.${TOKEN_KEY}.owner")
    log_info "Current owner: ${CURRENT_OWNER:-keypair (default)}"
    log_warn "Transferring ownership is irreversible unless the new owner signs back."
    log ""
    echo -ne "  ${W}New owner pubkey (Enter to cancel): ${NC}"
    read -r NEW_OWNER 2>/dev/null || NEW_OWNER=""
    [ -z "$NEW_OWNER" ] && { log "  Cancelled."; exit 0; }

    echo -ne "  ${W}Confirm transfer to ${NEW_OWNER}? [y/N]: ${NC}"
    read -r CONF 2>/dev/null || CONF="n"
    [[ "$CONF" =~ ^[yY]$ ]] || { log "  Cancelled."; exit 0; }

    set +e
    TMP=$(mktemp)
    run_client \
        -k "$NET_KEYPAIR" -u "$NET_RPC" \
        token transfer-ownership \
        --program-id "$WARP_PROGRAM_ID" \
        "$NEW_OWNER" 2>&1 \
        | grep -v "^warning:" | grep -v "^note:" \
        | tee -a "$LOG_FILE" "$TMP"
    EXIT_CODE=${PIPESTATUS[0]}
    OUT=$(cat "$TMP"); rm -f "$TMP"
    set -e

    if [ $EXIT_CODE -eq 0 ]; then
        log_ok "Ownership transferred to: ${G}${NEW_OWNER}${NC}"
        TMP2=$(mktemp)
        jq ".networks.\"${NET_KEY}\".warp_tokens.\"${TOKEN_KEY}\".owner = \"${NEW_OWNER}\"" \
            "$SOL_CONFIG" > "$TMP2" && mv "$TMP2" "$SOL_CONFIG"
        log_ok "warp-sealevel-config.json updated"
    else
        log_err "Ownership transfer failed (exit $EXIT_CODE)"
        log "$OUT" | tail -5
    fi
    ;;

*)
    log_err "Invalid action: $ACTION"
    exit 1
    ;;
esac

log ""
log_ok "Done. Log: ${LOG_FILE}"
