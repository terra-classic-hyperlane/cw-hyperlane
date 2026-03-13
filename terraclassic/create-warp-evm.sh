#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
#  🚀 CREATE WARP ROUTE EVM ↔ TERRA CLASSIC — HYPERLANE CLI (INTERACTIVE)
# ═══════════════════════════════════════════════════════════════════════════════
#
#  USAGE:
#    export ETH_PRIVATE_KEY="0xYOUR_EVM_PRIVATE_KEY"
#    export TERRA_PRIVATE_KEY="YOUR_TERRA_PRIVATE_KEY_HEX"   (optional: automatic deploy on Terra Classic)
#    chmod +x create-warp-evm.sh
#    ./create-warp-evm.sh
#
#  SKIP STEPS (contracts already deployed):
#    export WARP_ADDRESS="0x..."   → skips EVM Warp deploy
#    export IGP_ADDRESS="0x..."    → skips IGP deploy
#    export SKIP_ENROLL="1"        → skips enrollRemoteRouter
#
#  WHAT THE SCRIPT CONFIGURES ON THE EVM SIDE:
#    ✅ Mailbox   — Hyperlane central hub of the chosen network
#    ✅ ISM       — messageIdMultisigIsm (validates msgs from Terra Classic)
#    ✅ Hook      — custom IGP (pays gas on Terra Classic with EVM token)
#    ✅ IGP       — deploy + exchange_rate + gas_price
#    ✅ Link      — enrollRemoteRouter to the Terra Classic Warp
#
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# COLORS
# ─────────────────────────────────────────────────────────────────────────────
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'
B='\033[0;34m'; C='\033[0;36m'; W='\033[1m'; NC='\033[0m'
OK="${G}✅${NC}"; ERR="${R}❌${NC}"; WARN="${Y}⚠️ ${NC}"; INFO="${B}ℹ️ ${NC}"

# ─────────────────────────────────────────────────────────────────────────────
# PATHS
# ─────────────────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/warp-evm-config.json"
IGP_SOL="$SCRIPT_DIR/TerraClassicIGPStandalone-Sepolia.sol"
LOG_DIR="$SCRIPT_DIR/log"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/create-warp-evm.log"
STATE_FILE="$SCRIPT_DIR/.warp-evm-state.json"

# Auto-detect PROJECT_ROOT (directory that contains package.json and yarn)
# Required to run: yarn cw-hpl warp create ...
PROJECT_ROOT="$SCRIPT_DIR"
while [ ! -f "$PROJECT_ROOT/package.json" ] && [ "$PROJECT_ROOT" != "/" ]; do
    PROJECT_ROOT="$(dirname "$PROJECT_ROOT")"
done
if [ ! -f "$PROJECT_ROOT/package.json" ]; then
    echo "❌ Could not find the project root (package.json)!"
    echo "   Make sure this script is inside a cw-hyperlane project."
    exit 1
fi

# ─────────────────────────────────────────────────────────────────────────────
# UTILITIES
# ─────────────────────────────────────────────────────────────────────────────
log()       { echo -e "$@" | tee -a "$LOG_FILE"; }
log_ok()    { log "${OK} $*"; }
log_err()   { log "${ERR} $*"; }
log_warn()  { log "${WARN} $*"; }
log_info()  { log "${INFO} $*"; }
log_sep()   { log ""; log "${C}${W}$1${NC}"; log "────────────────────────────────────────────────────────────────"; }
cfg()       { jq -r "$1" "$CONFIG_FILE" 2>/dev/null || echo ""; }
is_evm()    { [[ "$1" =~ ^0x[0-9a-fA-F]{40}$ ]]; }
to_bytes32() {
    # Converts address/hash to bytes32 (64 hex chars, without 0x).
    # EVM address (20 bytes / 40 chars): left-pad with zeros.
    # CosmWasm hash (32 bytes / 64 chars): already 64 chars, do not add extra zeros.
    local a="${1#0x}"
    a="${a,,}"
    printf '%064s' "$a" | tr ' ' '0' | cut -c1-64
}

save_state() {
    cat > "$STATE_FILE" <<EOF
{
  "network":      "${NET_KEY:-}",
  "token":        "${TOKEN_KEY:-}",
  "warp_address": "${WARP_ADDRESS:-}",
  "igp_address":  "${IGP_ADDRESS:-}",
  "timestamp":    "$(date -Iseconds)"
}
EOF
}

load_state() {
    # Only reads saved state into global _STATE_* variables
    # Addresses are ONLY applied after confirming token+network match (see apply_state)
    [ -f "$STATE_FILE" ] || return 0
    _STATE_NET=$(jq -r '.network      // ""' "$STATE_FILE" 2>/dev/null || echo "")
    _STATE_TOK=$(jq -r '.token        // ""' "$STATE_FILE" 2>/dev/null || echo "")
    _STATE_WARP=$(jq -r '.warp_address // ""' "$STATE_FILE" 2>/dev/null || echo "")
    _STATE_IGP=$(jq -r '.igp_address  // ""' "$STATE_FILE" 2>/dev/null || echo "")
    if [ -n "$_STATE_NET" ] && [ -n "$_STATE_TOK" ]; then
        log_warn "Previous state: network=${_STATE_NET}, token=${_STATE_TOK}, warp=${_STATE_WARP:-—}, igp=${_STATE_IGP:-—}"
        log "   To restart: ${Y}rm -f $STATE_FILE${NC}"
    fi
}

apply_state() {
    # Applies saved state addresses ONLY if token+network match the current selection
    [ -z "${_STATE_NET:-}" ] && return 0
    if [ "${_STATE_NET}" = "${NET_KEY}" ] && [ "${_STATE_TOK}" = "${TOKEN_KEY}" ]; then
        [ -z "${WARP_ADDRESS:-}" ] && [ -n "${_STATE_WARP:-}" ] && export WARP_ADDRESS="$_STATE_WARP"
        [ -z "${IGP_ADDRESS:-}"  ] && [ -n "${_STATE_IGP:-}"  ] && export IGP_ADDRESS="$_STATE_IGP"
        [ -n "${WARP_ADDRESS:-}" ] && log_info "State restored: warp=${WARP_ADDRESS}, igp=${IGP_ADDRESS:-—}"
    else
        log_info "Previous state was for ${_STATE_TOK}/${_STATE_NET} — ignored for ${TOKEN_KEY}/${NET_KEY}."
    fi
}

wait_sec() {
    local s="$1" msg="${2:-Awaiting confirmation}"
    echo -ne "${INFO} ${msg}: "
    for ((i=s; i>0; i--)); do echo -ne "${i}s "; sleep 1; done
    echo "✓"
}

cast_tx() {
    local n=0 out
    while [ $n -lt 3 ]; do
        out=$(cast send "$@" 2>&1) && {
            echo "$out" | grep -oE "0x[0-9a-fA-F]{64}" | head -1
            return 0
        }
        n=$((n+1))
        [ $n -lt 3 ] && { log_warn "TX failed ($n/3), waiting 5s..."; sleep 5; }
    done
    return 1
}

# ─────────────────────────────────────────────────────────────────────────────
# BANNER
# ─────────────────────────────────────────────────────────────────────────────
> "$LOG_FILE"
clear 2>/dev/null || true
log "╔══════════════════════════════════════════════════════════════════════════╗"
log "║                                                                          ║"
log "║     🚀  CREATE WARP ROUTE EVM ↔ TERRA CLASSIC — HYPERLANE CLI  🚀       ║"
log "║                                                                          ║"
log "║     Config: warp-evm-config.json     Data: $(date '+%Y-%m-%d %H:%M:%S')          ║"
log "║                                                                          ║"
log "╚══════════════════════════════════════════════════════════════════════════╝"
log ""

# ─────────────────────────────────────────────────────────────────────────────
# INITIAL CHECKS
# ─────────────────────────────────────────────────────────────────────────────
if [ ! -f "$CONFIG_FILE" ]; then
    log_err "Configuration file not found: $CONFIG_FILE"; exit 1
fi
if ! jq empty "$CONFIG_FILE" 2>/dev/null; then
    log_err "Invalid JSON: $CONFIG_FILE"; exit 1
fi
log_ok "Configuration: $CONFIG_FILE"

# Check tools
HAVE_HYPERLANE=false; HAVE_FORGE=false; HAVE_CAST=false
command -v hyperlane &>/dev/null && HAVE_HYPERLANE=true
command -v forge     &>/dev/null && HAVE_FORGE=true
command -v cast      &>/dev/null && HAVE_CAST=true
command -v jq        &>/dev/null || { log_err "jq is required!"; exit 1; }

# Check minimum Hyperlane CLI version (>= 26)
if [ "$HAVE_HYPERLANE" = "true" ]; then
    HYP_VER=$(hyperlane --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "0")
    HYP_MAJOR=$(echo "$HYP_VER" | cut -d. -f1)
    if [ "${HYP_MAJOR:-0}" -lt 26 ]; then
        log_warn "Hyperlane CLI v${HYP_VER} — minimum recommended version: 26.x"
        log "${Y}  Updating CLI...${NC}"
        npm install -g @hyperlane-xyz/cli@latest >> "$LOG_FILE" 2>&1 \
            && log_ok "CLI atualizado para v$(hyperlane --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)" \
            || log_warn "Failed to update CLI — proceed with caution"
    fi
fi

load_state

# ═════════════════════════════════════════════════════════════════════════════
# MENU 1 — SELECT TOKEN
# ═════════════════════════════════════════════════════════════════════════════
log_sep "STEP 1/2 — SELECT TOKEN (Terra Classic)"

TERRA_DOMAIN=$(cfg ".terra_classic.domain")
TERRA_RPC=$(cfg ".terra_classic.rpc")
TERRA_CHAIN_ID=$(cfg ".terra_classic.chain_id")

log "  Tokens configured in ${C}warp-evm-config.json${NC}:"
log ""

mapfile -t TOKEN_KEYS < <(jq -r '.terra_classic.tokens | keys[]' "$CONFIG_FILE" 2>/dev/null)
declare -a TOKEN_MENU=()
i=1

for TK in "${TOKEN_KEYS[@]}"; do
    T=".terra_classic.tokens.${TK}"
    TK_NAME=$(cfg "${T}.name")
    TK_SYM=$(cfg "${T}.symbol")
    TK_TYPE=$(cfg "${T}.terra_warp.type")
    TK_MODE=$(cfg "${T}.terra_warp.mode")
    TK_DEPLOYED=$(cfg "${T}.terra_warp.deployed")
    TK_OWNER=$(cfg "${T}.terra_warp.owner")
    TK_COLLAT=$(cfg "${T}.terra_warp.collateral_address")
    TK_WARP=$(cfg "${T}.terra_warp.warp_address")

    TOKEN_MENU+=("$TK")

    TAG_TYPE="${C}[${TK_TYPE}/${TK_MODE}]${NC}"
    if [ "$TK_DEPLOYED" = "true" ]; then
        TAG_DEP="${G}[warp terra deployed]${NC}"
    else
        TAG_DEP="${Y}[warp terra pending]${NC}"
    fi

    log "   ${W}[$i]${NC}  ${C}${TK}${NC} — ${TK_NAME} (${TK_SYM}) ${TAG_TYPE} ${TAG_DEP}"
    log "        Owner:      ${TK_OWNER}"
    if [ "$TK_TYPE" = "cw20" ]; then
        log "        CW20:       ${TK_COLLAT}"
    else
        log "        Denom:      $(cfg "${T}.terra_warp.denom")"
    fi
    if [ "$TK_DEPLOYED" = "true" ] && [ -n "$TK_WARP" ]; then
        log "        Warp Terra: ${G}${TK_WARP}${NC}"
    fi
    log ""
    i=$((i+1))
done

echo -ne "  ${W}Choose the token [1-${#TOKEN_MENU[@]}]: ${NC}"
read -r SEL_TOK 2>/dev/null || SEL_TOK="1"
SEL_TOK="${SEL_TOK:-1}"

if ! [[ "$SEL_TOK" =~ ^[0-9]+$ ]] || [ "$SEL_TOK" -lt 1 ] || [ "$SEL_TOK" -gt "${#TOKEN_MENU[@]}" ]; then
    log_err "Invalid selection: $SEL_TOK"; exit 1
fi

TOKEN_KEY="${TOKEN_MENU[$((SEL_TOK-1))]}"
TK=".terra_classic.tokens.${TOKEN_KEY}"

TOKEN_NAME=$(cfg "${TK}.name")
TOKEN_SYMBOL=$(cfg "${TK}.symbol")
TOKEN_DEC=$(cfg "${TK}.decimals")
TOKEN_DESC=$(cfg "${TK}.description")
TOKEN_IMG=$(cfg "${TK}.image")

TERRA_WARP_TYPE=$(cfg "${TK}.terra_warp.type")
TERRA_WARP_MODE=$(cfg "${TK}.terra_warp.mode")
TERRA_WARP_OWNER=$(cfg "${TK}.terra_warp.owner")
TERRA_WARP_DENOM=$(cfg "${TK}.terra_warp.denom")
TERRA_WARP_COLLAT=$(cfg "${TK}.terra_warp.collateral_address")
TERRA_WARP_ADDR=$(cfg "${TK}.terra_warp.warp_address")
TERRA_WARP_HEX=$(cfg "${TK}.terra_warp.warp_hexed")
TERRA_WARP_DEPLOYED=$(cfg "${TK}.terra_warp.deployed")

log_ok "Token selected: ${C}${TOKEN_KEY}${NC} — ${TOKEN_NAME} (${TOKEN_SYMBOL})"

# ─────────────────────────────────────────────────────────────────────────────
# HELPER: convert Terra Classic bech32 address → hex bytes32 (via Python3)
# ─────────────────────────────────────────────────────────────────────────────
bech32_to_hex() {
    local addr="$1"
    python3 - "$addr" <<'PYEOF' 2>/dev/null
import sys
addr = sys.argv[1]
CHARSET = 'qpzry9x8gf2tvdw0s3jn54khce6mua7l'
# find separator '1'
sep = addr.rfind('1')
data_str = addr[sep+1:-6]          # descarta checksum (6 chars)
vals = [CHARSET.index(c) for c in data_str]
# convert 5-bit groups → 8-bit
result, acc, bits = [], 0, 0
for v in vals:
    acc = (acc << 5) | v
    bits += 5
    while bits >= 8:
        bits -= 8
        result.append((acc >> bits) & 0xFF)
print('0x' + ''.join(f'{b:02x}' for b in result))
PYEOF
}

# ─────────────────────────────────────────────────────────────────────────────
# DEPLOY TERRA CLASSIC (if warp not yet deployed)
# ─────────────────────────────────────────────────────────────────────────────
if [ "$TERRA_WARP_DEPLOYED" != "true" ] || [ -z "$TERRA_WARP_ADDR" ]; then
    log ""
    log "${Y}╔══════════════════════════════════════════════════════════════════════╗${NC}"
    log "${Y}║  ⚠️  WARP TERRA CLASSIC NOT YET DEPLOYED FOR '${TOKEN_KEY}'          ║${NC}"
    log "${Y}╚══════════════════════════════════════════════════════════════════════╝${NC}"
    log ""

    # ── Generate configuration file for Terra Classic ──────────────────
    TERRA_WARP_CONFIG="$SCRIPT_DIR/warp/terraclassic-${TERRA_WARP_TYPE}-${TOKEN_KEY}.json"
    mkdir -p "$(dirname "$TERRA_WARP_CONFIG")"

    if [ "$TERRA_WARP_TYPE" = "cw20" ]; then
        cat > "$TERRA_WARP_CONFIG" <<TCFG
{
  "type": "cw20",
  "mode": "${TERRA_WARP_MODE}",
  "id": "${TOKEN_KEY}",
  "owner": "${TERRA_WARP_OWNER}",
  "config": {
    "collateral": {
      "address": "${TERRA_WARP_COLLAT}"
    }
  }
}
TCFG
    else
        cat > "$TERRA_WARP_CONFIG" <<TCFG
{
  "type": "native",
  "mode": "${TERRA_WARP_MODE}",
  "id": "${TOKEN_KEY}",
  "owner": "${TERRA_WARP_OWNER}",
  "config": {
    "collateral": {
      "denom": "${TERRA_WARP_DENOM}"
    }
  }
}
TCFG
    fi
    log_ok "Config generated: ${C}${TERRA_WARP_CONFIG}${NC}"

    # ── Automatic deploy if TERRA_PRIVATE_KEY is set ─────────────
    if [ -n "${TERRA_PRIVATE_KEY:-}" ]; then
        log ""
        log_sep "DEPLOY TERRA CLASSIC — yarn cw-hpl warp create"
        log "  Tipo:  ${C}${TERRA_WARP_TYPE} / ${TERRA_WARP_MODE}${NC}"
        log "  ID:    ${C}${TOKEN_KEY}${NC}"
        log "  Owner: ${G}${TERRA_WARP_OWNER}${NC}"
        [ "$TERRA_WARP_TYPE" = "cw20" ] \
            && log "  CW20:  ${C}${TERRA_WARP_COLLAT}${NC}" \
            || log "  Denom: ${C}${TERRA_WARP_DENOM}${NC}"
        log ""
        log "${Y}⏳ Waiting for Terra Classic deploy (~1 min)...${NC}"

        TERRA_DEPLOY_TMP=$(mktemp)
        set +e
        # Ensure config.yaml in PROJECT_ROOT (cw-hpl reads from project root)
        if [ -f "$SCRIPT_DIR/config.yaml" ] && [ "$SCRIPT_DIR" != "$PROJECT_ROOT" ]; then
            cp "$SCRIPT_DIR/config.yaml" "$PROJECT_ROOT/config.yaml"
            log_info "config.yaml copied to $PROJECT_ROOT"
        fi
        cd "$PROJECT_ROOT"
        PRIVATE_KEY="$TERRA_PRIVATE_KEY" yarn cw-hpl warp create "$TERRA_WARP_CONFIG" -n terraclassic \
            2>&1 | tee -a "$LOG_FILE" "$TERRA_DEPLOY_TMP"
        TERRA_DEPLOY_EXIT=${PIPESTATUS[0]}
        cd "$SCRIPT_DIR"
        set -e

        TERRA_DEPLOY_OUT=$(cat "$TERRA_DEPLOY_TMP"); rm -f "$TERRA_DEPLOY_TMP"

        if [ "$TERRA_DEPLOY_EXIT" -ne 0 ]; then
            log_err "Terra Classic deploy failed (exit $TERRA_DEPLOY_EXIT)!"
            log ""
            log "${Y}Check the logs and try again, or do the manual deploy:${NC}"
            log "  cd $SCRIPT_DIR"
            log "  export PRIVATE_KEY='\$TERRA_PRIVATE_KEY'"
            log "  yarn cw-hpl warp create ${TERRA_WARP_CONFIG} -n terraclassic"
            log ""
            log "After the manual deploy, update warp-evm-config.json and re-run:"
            log "  .terra_classic.tokens.${TOKEN_KEY}.terra_warp.warp_address"
            log "  .terra_classic.tokens.${TOKEN_KEY}.terra_warp.warp_hexed"
            log "  .terra_classic.tokens.${TOKEN_KEY}.terra_warp.deployed = true"
            export SKIP_ENROLL="1"
        else
            # ── Extract bech32 address from output ───────────────────────────
            NEW_TERRA_ADDR=$(echo "$TERRA_DEPLOY_OUT" \
                | grep -oE 'terra1[a-z0-9]{38,58}' | tail -1 || echo "")

            # Fallback: read from context/terraclassic.json (CLI updates this file in project root)
            CONTEXT_FILE="$PROJECT_ROOT/context/terraclassic.json"
            if [ -z "$NEW_TERRA_ADDR" ] && [ -f "$CONTEXT_FILE" ]; then
                if [ "$TERRA_WARP_TYPE" = "cw20" ]; then
                    NEW_TERRA_ADDR=$(jq -r \
                        ".deployments.warp.cw20[] | select(.id==\"${TOKEN_KEY}\") | .address" \
                        "$CONTEXT_FILE" 2>/dev/null | tail -1 || echo "")
                else
                    NEW_TERRA_ADDR=$(jq -r \
                        ".deployments.warp.native[] | select(.id==\"${TOKEN_KEY}\") | .address" \
                        "$CONTEXT_FILE" 2>/dev/null | tail -1 || echo "")
                fi
            fi

            if [ -z "$NEW_TERRA_ADDR" ]; then
                log_err "Could not extract the Terra Classic contract address from output!"
                log "${Y}Find the address in the output above and fill in manually:${NC}"
                log "  warp-evm-config.json → .terra_classic.tokens.${TOKEN_KEY}.terra_warp.warp_address"
                export SKIP_ENROLL="1"
            else
                log_ok "Terra Classic Warp: ${G}${NEW_TERRA_ADDR}${NC}"

                # ── Convert bech32 → hex bytes32 ──────────────────────────
                NEW_TERRA_HEX=$(bech32_to_hex "$NEW_TERRA_ADDR")
                if [ -z "$NEW_TERRA_HEX" ]; then
                    # Fallback: try via context/terraclassic.json at project root
                    NEW_TERRA_HEX=$(jq -r \
                        ".deployments.warp.${TERRA_WARP_TYPE}[] | select(.id==\"${TOKEN_KEY}\") | .hexAddress // .hex_address // empty" \
                        "$PROJECT_ROOT/context/terraclassic.json" 2>/dev/null | head -1 || echo "")
                fi
                [ -n "$NEW_TERRA_HEX" ] && log_ok "Hex: ${G}${NEW_TERRA_HEX}${NC}" \
                                        || log_warn "Could not convert to hex — enrollRemoteRouter will be skipped"

                # ── Update warp-evm-config.json ──────────────────────────
                TMP_CFG=$(mktemp)
                jq ".terra_classic.tokens.\"${TOKEN_KEY}\".terra_warp.warp_address = \"${NEW_TERRA_ADDR}\" |
                    .terra_classic.tokens.\"${TOKEN_KEY}\".terra_warp.warp_hexed  = \"${NEW_TERRA_HEX}\" |
                    .terra_classic.tokens.\"${TOKEN_KEY}\".terra_warp.deployed    = true" \
                    "$CONFIG_FILE" > "$TMP_CFG" && mv "$TMP_CFG" "$CONFIG_FILE"
                log_ok "${C}warp-evm-config.json${NC} updated automatically!"

                # Update in-memory variables for enrollRemoteRouter
                TERRA_WARP_ADDR="$NEW_TERRA_ADDR"
                TERRA_WARP_HEX="$NEW_TERRA_HEX"
                TERRA_WARP_DEPLOYED="true"
                # Ensures enrollRemoteRouter will be executed
                unset SKIP_ENROLL
            fi
        fi

    else
        # ── Manual deploy instructions ────────────────────────────────────
        log ""
        log "  ${W}Automatic deploy:${NC} set ${C}TERRA_PRIVATE_KEY${NC} and re-run."
        log ""
        log "  ${W}Manual deploy:${NC}"
        log "  ┌──────────────────────────────────────────────────────────────────┐"
        log "  │  cd $SCRIPT_DIR                                                  │"
        log "  │  export PRIVATE_KEY='your_terra_hex_key'                          │"
        log "  │  yarn cw-hpl warp create \\                                      │"
        log "  │    ${TERRA_WARP_CONFIG} \\  │"
        log "  │    -n terraclassic                                               │"
        log "  └──────────────────────────────────────────────────────────────────┘"
        log ""
        log "  After deploy, fill in ${C}warp-evm-config.json${NC}:"
        log "    .terra_classic.tokens.${TOKEN_KEY}.terra_warp.warp_address = \"terra1...\""
        log "    .terra_classic.tokens.${TOKEN_KEY}.terra_warp.warp_hexed  = \"0x...\""
        log "    .terra_classic.tokens.${TOKEN_KEY}.terra_warp.deployed    = true"
        log ""
        echo -ne "  ${W}Continue anyway (enrollRemoteRouter will be skipped)? [y/N]: ${NC}"
        read -r CONT 2>/dev/null || CONT="s"
        CONT="${CONT:-s}"
        if [[ ! "$CONT" =~ ^[sSyY]$ ]]; then
            log "  Cancelled."; exit 0
        fi
        export SKIP_ENROLL="1"
    fi
fi

# ═════════════════════════════════════════════════════════════════════════════
# MENU 2 — SELECT EVM NETWORK
# ═════════════════════════════════════════════════════════════════════════════
log_sep "STEP 2/2 — SELECT EVM NETWORK"

log "  Networks available in ${C}warp-evm-config.json${NC}:"
log ""

mapfile -t NET_KEYS < <(jq -r '.networks | keys[]' "$CONFIG_FILE" 2>/dev/null)
declare -a NET_MENU=()
i=1

for NK in "${NET_KEYS[@]}"; do
    NE=$(cfg ".networks.${NK}.enabled")
    ND=$(cfg ".networks.${NK}.display_name")
    NC_ID=$(cfg ".networks.${NK}.chain_id")
    NT=$(cfg ".networks.${NK}.is_testnet")
    WD=$(cfg ".networks.${NK}.warp_tokens.${TOKEN_KEY}.deployed")
    WA=$(cfg ".networks.${NK}.warp_tokens.${TOKEN_KEY}.address")

    if [ "$NE" = "true" ]; then
        NET_MENU+=("$NK")
        TAG_T=""; [ "$NT" = "true" ] && TAG_T="${Y}[testnet]${NC}" || TAG_T="${R}[mainnet]${NC}"
        TAG_W=""; [ "$WD" = "true" ] && TAG_W="${G}[warp already deployed]${NC}" || TAG_W="${B}[new deploy]${NC}"
        log "   ${W}[$i]${NC}  ${C}${NK}${NC} — ${ND} (chain: ${NC_ID}) ${TAG_T} ${TAG_W}"
        if [ "$WD" = "true" ] && [ -n "$WA" ]; then
            log "        Warp: ${G}${WA}${NC}"
        fi
        log "        Mailbox: $(cfg ".networks.${NK}.mailbox.address")"
        log ""
        i=$((i+1))
    else
        log "   ${R}[-]${NC}  ${NK} — ${ND} ${R}[disabled]${NC}"
    fi
done

if [ ${#NET_MENU[@]} -eq 0 ]; then
    log_err "No enabled network! Edit warp-evm-config.json."; exit 1
fi

echo -ne "  ${W}Choose the network [1-${#NET_MENU[@]}]: ${NC}"
read -r SEL_NET 2>/dev/null || SEL_NET="1"
SEL_NET="${SEL_NET:-1}"

if ! [[ "$SEL_NET" =~ ^[0-9]+$ ]] || [ "$SEL_NET" -lt 1 ] || [ "$SEL_NET" -gt "${#NET_MENU[@]}" ]; then
    log_err "Invalid selection: $SEL_NET"; exit 1
fi

NET_KEY="${NET_MENU[$((SEL_NET-1))]}"
N=".networks.${NET_KEY}"

log_ok "Network selected: ${C}${NET_KEY}${NC}"

# ─────────────────────────────────────────────────────────────────────────────
# LOAD SELECTED NETWORK CONFIGURATION
# ─────────────────────────────────────────────────────────────────────────────
NET_DISPLAY=$(cfg "${N}.display_name")
NET_CHAIN_ID=$(cfg "${N}.chain_id")
NET_DOMAIN=$(cfg "${N}.domain")
NET_IS_TEST=$(cfg "${N}.is_testnet")
NET_NATIVE=$(cfg "${N}.native_token.symbol")
NET_RPC=$(jq -r "${N}.rpc_urls[0]" "$CONFIG_FILE")
NET_RPC_ALT=$(jq -r "${N}.rpc_urls[1] // empty" "$CONFIG_FILE" 2>/dev/null || echo "")
NET_EXPLORER=$(cfg "${N}.explorer")

MAILBOX=$(cfg "${N}.mailbox.address")
ISM_TYPE=$(cfg "${N}.ism.type")
ISM_FACTORY=$(cfg "${N}.ism.factory")
ISM_DEPLOYED_CFG=$(cfg "${N}.ism.deployed_address")
ISM_VALIDATORS=$(jq -r "${N}.ism.validators[]" "$CONFIG_FILE" 2>/dev/null | tr '\n' ',' | sed 's/,$//')
ISM_THRESHOLD=$(cfg "${N}.ism.threshold")
HOOK_MERKLE=$(cfg "${N}.hook.merkle_tree")
AGG_HOOK_FACTORY=$(cfg "${N}.hook.agg_hook_factory")
GAS_ORACLE=$(cfg "${N}.igp.gas_oracle")
GAS_OVERHEAD=$(cfg "${N}.igp.overhead_default")
IGP_EXCHANGE_RATE=$(cfg "${N}.igp.terra_classic_config.exchange_rate")
IGP_GAS_PRICE=$(cfg "${N}.igp.terra_classic_config.gas_price_wei")

# Token Warp on this network
WARP_DEPLOYED_CFG=$(cfg "${N}.warp_tokens.${TOKEN_KEY}.deployed")
WARP_ADDR_CFG=$(cfg "${N}.warp_tokens.${TOKEN_KEY}.address")
IGP_ADDR_CFG=$(cfg "${N}.warp_tokens.${TOKEN_KEY}.igp_custom")
HOOK_AGG_CFG=$(cfg "${N}.warp_tokens.${TOKEN_KEY}.hook_aggregation")
WARP_OWNER_CFG=$(cfg "${N}.warp_tokens.${TOKEN_KEY}.owner")

# Apply saved state only if token+network match (avoids using another token address)
apply_state

# Use addresses from JSON (only if not yet defined via state or env)
[ -z "${WARP_ADDRESS:-}" ] && [ -n "$WARP_ADDR_CFG" ] && [ "$WARP_ADDR_CFG" != "null" ] && export WARP_ADDRESS="$WARP_ADDR_CFG"
[ -z "${IGP_ADDRESS:-}"  ] && [ -n "$IGP_ADDR_CFG"  ] && [ "$IGP_ADDR_CFG"  != "null" ] && export IGP_ADDRESS="$IGP_ADDR_CFG"
[ -z "${HOOK_AGG_ADDRESS:-}" ] && [ -n "$HOOK_AGG_CFG" ] && [ "$HOOK_AGG_CFG" != "null" ] && export HOOK_AGG_ADDRESS="$HOOK_AGG_CFG"

# Owner: derive from wallet or use configured value
if command -v cast &>/dev/null && [ -n "${ETH_PRIVATE_KEY:-}" ]; then
    WALLET=$(cast wallet address "$ETH_PRIVATE_KEY" 2>/dev/null || echo "")
fi
WARP_OWNER="${WARP_OWNER:-${WALLET:-${WARP_OWNER_CFG}}}"

# ─────────────────────────────────────────────────────────────────────────────
# CONFIGURATION SUMMARY
# ─────────────────────────────────────────────────────────────────────────────
log ""
log "╔══════════════════════════════════════════════════════════════════════════╗"
log "║   📋  SUMMARY: Token ${C}${TOKEN_KEY}${NC} → Network ${C}${NET_DISPLAY}${NC}"
log "╚══════════════════════════════════════════════════════════════════════════╝"
log ""
log "  ${W}🌐 EVM NETWORK${NC}"
log "     ${NET_DISPLAY}  |  Chain: ${NET_CHAIN_ID}  |  Domain: ${NET_DOMAIN}"
log "     RPC: ${NET_RPC}"
log ""
log "  ${W}📮 MAILBOX${NC}  —  central message hub"
log "     ${G}${MAILBOX}${NC}"
log ""
log "  ${W}🔐 ISM${NC}  —  validates messages received from Terra Classic"
log "     Tipo:       ${ISM_TYPE}"
log "     Validators: ${ISM_VALIDATORS}"
log "     Threshold:  ${ISM_THRESHOLD}"
[ -n "$ISM_DEPLOYED_CFG" ] && [ "$ISM_DEPLOYED_CFG" != "null" ] && \
    log "     Deployed:   ${G}${ISM_DEPLOYED_CFG}${NC}"
log ""
log "  ${W}🪝 HOOK${NC}  —  custom IGP (hookType=4) as Warp hook"
log "     Merkle Tree: ${HOOK_MERKLE}"
log ""
log "  ${W}⛽ IGP${NC}  —  pays gas on Terra Classic using ${NET_NATIVE}"
log "     Gas Oracle:    ${GAS_ORACLE}"
log "     Gas Overhead:  ${GAS_OVERHEAD}"
log "     Exchange Rate: ${IGP_EXCHANGE_RATE}  (→ Terra domain ${TERRA_DOMAIN})"
log "     Gas Price:     ${IGP_GAS_PRICE} wei"
[ -n "${IGP_ADDRESS:-}" ] && log "     Custom IGP:    ${G}${IGP_ADDRESS}${NC}  ${G}(already deployed)${NC}"
log ""
log "  ${W}🪙 TOKEN${NC}  —  ${TOKEN_NAME} (${TOKEN_SYMBOL})"
log "     Tipo EVM:   synthetic  |  Decimals: ${TOKEN_DEC}"
[ -n "${WARP_ADDRESS:-}" ] && log "     Warp Route: ${G}${WARP_ADDRESS}${NC}  ${G}(already deployed)${NC}" \
                            || log "     Status:     ${Y}New deploy${NC}"
log ""
log "  ${W}🌉 TERRA CLASSIC LINK${NC}  —  for enrollRemoteRouter"
log "     Tipo:    ${TERRA_WARP_TYPE} / ${TERRA_WARP_MODE}"
if [ "$TERRA_WARP_TYPE" = "cw20" ]; then
    log "     CW20:    ${TERRA_WARP_COLLAT}"
else
    log "     Denom:   ${TERRA_WARP_DENOM}"
fi
log "     Owner:   ${TERRA_WARP_OWNER}"
if [ -n "$TERRA_WARP_ADDR" ]; then
    log "     Warp:    ${G}${TERRA_WARP_ADDR}${NC}"
    log "     Hex:     ${TERRA_WARP_HEX}"
else
    log "     Warp:    ${Y}(not deployed — enrollRemoteRouter will be skipped)${NC}"
fi
log ""

# ─────────────────────────────────────────────────────────────────────────────
# VERIFY PRIVATE KEY
# ─────────────────────────────────────────────────────────────────────────────
if [ -z "${ETH_PRIVATE_KEY:-}" ]; then
    log_err "ETH_PRIVATE_KEY not set!"
    log "   ${Y}export ETH_PRIVATE_KEY='0xYOUR_KEY'${NC}"
    log "   ${Y}./create-warp-evm.sh${NC}"
    exit 1
fi

if [ "$HAVE_CAST" = "true" ] && [ -n "${WALLET:-}" ]; then
    log_ok "Wallet: ${G}${WALLET}${NC}"
    BAL_WEI=$(cast balance "$WALLET" --rpc-url "$NET_RPC" 2>/dev/null || echo "0")
    BAL=$(cast to-unit "$BAL_WEI" ether 2>/dev/null || echo "?")
    log_info "Balance: ${G}${BAL} ${NET_NATIVE}${NC}"
fi

# ─────────────────────────────────────────────────────────────────────────────
# CONFIRMATION
# ─────────────────────────────────────────────────────────────────────────────
log ""
echo -ne "  ${W}▶ Proceed with deploy of ${C}${TOKEN_SYMBOL}${NC} on network ${C}${NET_DISPLAY}${NC}? [y/N]: ${NC}"
read -r CONFIRM 2>/dev/null || CONFIRM="s"
CONFIRM="${CONFIRM:-s}"
[[ ! "$CONFIRM" =~ ^[sSyY]$ ]] && { log "  Cancelled."; exit 0; }

# ─────────────────────────────────────────────────────────────────────────────
# CHECK TOOLS
# ─────────────────────────────────────────────────────────────────────────────
log_sep "TOOLS"
[ "$HAVE_HYPERLANE" = "true" ] && log_ok "hyperlane CLI" || {
    log_info "Installing Hyperlane CLI..."
    npm install -g @hyperlane-xyz/cli >> "$LOG_FILE" 2>&1 \
        && HAVE_HYPERLANE=true && log_ok "hyperlane CLI installed" \
        || log_warn "Failed to install hyperlane CLI"
}
[ "$HAVE_FORGE" = "true" ] && log_ok "forge (Foundry)" || log_warn "forge not found"
[ "$HAVE_CAST"  = "true" ] && log_ok "cast (Foundry)"  || log_warn "cast not found"

# Check RPC
log_info "Testing RPC: $NET_RPC"
if ! curl -sf --max-time 8 -X POST "$NET_RPC" \
    -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' >> "$LOG_FILE" 2>&1; then
    [ -n "$NET_RPC_ALT" ] && NET_RPC="$NET_RPC_ALT" && log_warn "Usando RPC alternativo: $NET_RPC" \
                          || { log_err "RPC unavailable!"; exit 1; }
fi
log_ok "RPC OK: $NET_RPC"

# ═════════════════════════════════════════════════════════════════════════════
# STEP 1 — GENERATE warp-<network>-<token>.yaml
# ═════════════════════════════════════════════════════════════════════════════
log_sep "STEP 1 — GENERATE WARP YAML"

WARP_YAML="$SCRIPT_DIR/warp/warp-${NET_KEY}-${TOKEN_KEY}.yaml"

VALIDATORS_YAML=""
while IFS= read -r VAL; do
    [ -n "$VAL" ] && VALIDATORS_YAML+="    - \"${VAL}\"
"
done < <(jq -r "${N}.ism.validators[]" "$CONFIG_FILE" 2>/dev/null)

cat > "$WARP_YAML" <<YAML
# ─────────────────────────────────────────────────────────────────────────────
# Warp Route: ${NET_DISPLAY} ↔ Terra Classic
# Token:      ${TOKEN_NAME} (${TOKEN_SYMBOL})
# Generated:  $(date '+%Y-%m-%d %H:%M:%S')
# ─────────────────────────────────────────────────────────────────────────────
${NET_KEY}:
  isNft: false
  type: synthetic
  name: "${TOKEN_NAME}"
  symbol: "${TOKEN_SYMBOL}"
  decimals: ${TOKEN_DEC}
  owner: "${WARP_OWNER}"
  mailbox: "${MAILBOX}"
  interchainSecurityModule:
    type: ${ISM_TYPE}
    validators:
${VALIDATORS_YAML}    threshold: ${ISM_THRESHOLD}
YAML

log_ok "File: ${C}${WARP_YAML}${NC}"
cat "$WARP_YAML"

# ═════════════════════════════════════════════════════════════════════════════
# STEP 2 — DEPLOY WARP ROUTE (hyperlane warp deploy)
# ═════════════════════════════════════════════════════════════════════════════
log_sep "STEP 2 — WARP ROUTE DEPLOY"

if [ -n "${WARP_ADDRESS:-}" ]; then
    log_warn "Warp Route already set: ${G}${WARP_ADDRESS}${NC}  → Skipping."
elif [ "$HAVE_HYPERLANE" = "false" ]; then
    log_err "Hyperlane CLI not available!"; exit 1
else
    log_info "Running: hyperlane warp deploy ..."
    log "${Y}⏳ Please wait (~2 minutes)...${NC}"

    DEPLOY_TMP=$(mktemp)
    set +e
    hyperlane warp deploy \
        --config "$WARP_YAML" \
        --key "$ETH_PRIVATE_KEY" \
        --yes 2>&1 | tee -a "$LOG_FILE" "$DEPLOY_TMP"
    DEPLOY_EXIT=${PIPESTATUS[0]}
    set -e

    DEPLOY_OUT=$(cat "$DEPLOY_TMP"); rm -f "$DEPLOY_TMP"

    if [ "$DEPLOY_EXIT" -ne 0 ]; then
        log_err "hyperlane warp deploy failed (exit $DEPLOY_EXIT)!"
        log ""
        log "${Y}════ DIAGNOSTICS ════${NC}"
        # Hint for common error: outdated CLI with invalid protocol
        if echo "$DEPLOY_OUT" | grep -q "invalid_enum_value"; then
            log_warn "Hyperlane CLI is outdated and does not recognize a protocol."
            log "  Update with: ${C}npm install -g @hyperlane-xyz/cli@latest${NC}"
        fi
        # Hint for missing private key
        if echo "$DEPLOY_OUT" | grep -q "too_small\|private.key\|signer"; then
            log_warn "Check if ETH_PRIVATE_KEY is exported correctly."
            log "  ${C}export ETH_PRIVATE_KEY='0xYOUR_KEY'${NC}"
        fi
        log ""
        log "${Y}To skip the deploy (if the contract already exists):${NC}"
        log "  ${C}export WARP_ADDRESS='0x...'${NC}"
        log "  ${C}./create-warp-evm.sh${NC}"
        exit 1
    fi

    # Extract address from output
    WARP_ADDRESS=$(echo "$DEPLOY_OUT" | grep -oiE '"addressOrDenom":\s*"(0x[0-9a-fA-F]{40})"' \
        | grep -oiE '0x[0-9a-fA-F]{40}' | tail -1 || echo "")
    [ -z "$WARP_ADDRESS" ] && \
        WARP_ADDRESS=$(echo "$DEPLOY_OUT" | grep -oiE "0x[0-9a-fA-F]{40}" | tail -1 || echo "")

    # Fallback: search in local registry
    if [ -z "$WARP_ADDRESS" ]; then
        WARP_FILE=$(find "$HOME/.hyperlane" \( -name "*.json" -o -name "*.yaml" \) \
            -newer "$WARP_YAML" 2>/dev/null | head -1 || echo "")
        [ -n "$WARP_FILE" ] && WARP_ADDRESS=$(jq -r \
            ".tokens[]?.addressOrDenom // .${NET_KEY}.token // .${NET_KEY}.router // empty" \
            "$WARP_FILE" 2>/dev/null | grep -oiE "0x[0-9a-fA-F]{40}" | head -1 || echo "")
    fi

    if [ -z "$WARP_ADDRESS" ]; then
        log_err "Could not extract Warp Route address!"
        log "Output (últimas linhas): $(echo "$DEPLOY_OUT" | tail -15)"
        log "${Y}Copy the address from the output and re-run:${NC}"
        log "  ${C}export WARP_ADDRESS='0x...'${NC}"
        log "  ${C}./create-warp-evm.sh${NC}"
        exit 1
    fi
    log_ok "Warp Route: ${G}${WARP_ADDRESS}${NC}"
fi
save_state

# ═════════════════════════════════════════════════════════════════════════════
# STEP 3 — DEPLOY CUSTOM IGP (hookType = 4)
# ═════════════════════════════════════════════════════════════════════════════
log_sep "STEP 3 — CUSTOM IGP DEPLOY"

if [ -n "${IGP_ADDRESS:-}" ]; then
    log_warn "IGP already set: ${G}${IGP_ADDRESS}${NC}  → Skipping."
elif [ "$HAVE_FORGE" = "false" ]; then
    log ""
    log "${Y}════════ MANUAL DEPLOY VIA REMIX IDE ════════${NC}"
    log "  1. https://remix.ethereum.org"
    log "  2. Create: TerraClassicIGP.sol"
    log "  3. Cole: ${C}${IGP_SOL}${NC}"
    log "  4. Compile: Solidity 0.8.13+ | Optimization ON"
    log "  5. Deploy on ${NET_DISPLAY} with:"
    log "       _GASORACLE:   ${G}${GAS_ORACLE}${NC}"
    log "       _GASOVERHEAD: ${G}${GAS_OVERHEAD}${NC}"
    log "       _BENEFICIARY: ${G}${WARP_OWNER}${NC}"
    log "  6. Copy the address and continue:"
    log "     ${C}export IGP_ADDRESS='0x...'${NC}"
    log "     ${C}./create-warp-evm.sh${NC}"
    save_state; exit 0
else
    TMP_DIR="/tmp/igp-deploy-$$"
    mkdir -p "$TMP_DIR/src"
    [ ! -f "$IGP_SOL" ] && { log_err "IGP SOL not found: $IGP_SOL"; exit 1; }
    cp "$IGP_SOL" "$TMP_DIR/src/TerraClassicIGP.sol"

    cd "$TMP_DIR"
    forge init --no-git --force . >> "$LOG_FILE" 2>&1
    log_info "Compiling..."
    forge build >> "$LOG_FILE" 2>&1 || { log_err "Compilation failed!"; exit 1; }

    # ── Foundry 1.x: forge create enters dry-run by default.
    # ── Solution: use cast send --create with compiled bytecode.
    ARTIFACT="$TMP_DIR/out/TerraClassicIGP.sol/TerraClassicIGPStandalone.json"
    [ ! -f "$ARTIFACT" ] && { log_err "Artifact not found: $ARTIFACT"; cd "$SCRIPT_DIR"; rm -rf "$TMP_DIR"; exit 1; }

    BYTECODE=$(jq -r '.bytecode.object' "$ARTIFACT" 2>/dev/null || echo "")
    [ -z "$BYTECODE" ] || [ "$BYTECODE" = "null" ] && { log_err "Empty bytecode!"; cd "$SCRIPT_DIR"; rm -rf "$TMP_DIR"; exit 1; }

    # ABI-encode constructor args: (address _gasOracle, uint96 _gasOverhead, address _beneficiary)
    CTOR_ARGS=$(cast abi-encode "constructor(address,uint96,address)" \
        "$GAS_ORACLE" "$GAS_OVERHEAD" "$WARP_OWNER" 2>/dev/null || echo "")
    [ -z "$CTOR_ARGS" ] && { log_err "Failed to encode constructor args!"; cd "$SCRIPT_DIR"; rm -rf "$TMP_DIR"; exit 1; }

    # Concatenate bytecode + args (remove 0x from CTOR_ARGS)
    DEPLOY_DATA="${BYTECODE}${CTOR_ARGS:2}"

    log_info "Deploying IGP on ${NET_DISPLAY} via cast send --create..."
    # Note: flags must come BEFORE --create (cast syntax)
    CAST_OUT=$(cast send \
        --rpc-url "$NET_RPC" \
        --private-key "$ETH_PRIVATE_KEY" \
        --legacy \
        --create "$DEPLOY_DATA" 2>&1 | tee -a "$LOG_FILE")

    # Extract contractAddress from output
    IGP_ADDRESS=$(echo "$CAST_OUT" | grep -i "^contractAddress" | awk '{print $2}' | tr -d '[:space:]' || echo "")

    # Fallback: any 0x address after "contractAddress"
    if [ -z "$IGP_ADDRESS" ] || [ "$IGP_ADDRESS" = "null" ]; then
        IGP_ADDRESS=$(echo "$CAST_OUT" | grep -i "contractAddress" \
            | grep -oiE '0x[0-9a-fA-F]{40}' | head -1 || echo "")
    fi

    if [ -z "$IGP_ADDRESS" ] || [ "$IGP_ADDRESS" = "null" ]; then
        log_err "IGP deploy failed!"
        log "Output: $(echo "$CAST_OUT" | tail -10)"
        log "${Y}If the contract was deployed, copy the address and continue:${NC}"
        log "  ${C}export IGP_ADDRESS='0x...'${NC}"
        log "  ${C}export WARP_ADDRESS='${WARP_ADDRESS}'${NC}"
        log "  ${C}./create-warp-evm.sh${NC}"
        cd "$SCRIPT_DIR"; rm -rf "$TMP_DIR"; exit 1
    fi

    log_ok "IGP deployed: ${G}${IGP_ADDRESS}${NC}"
    cd "$SCRIPT_DIR"; rm -rf "$TMP_DIR"
fi
save_state

# ═════════════════════════════════════════════════════════════════════════════
# STEP 4 — CONFIGURE GAS ORACLE: exchange rate and gas price for Terra Classic
# ═════════════════════════════════════════════════════════════════════════════
log_sep "STEP 4 — CONFIGURE GAS ORACLE (setRemoteGasData)"

log "  Gas Oracle:    ${G}${GAS_ORACLE}${NC}"
log "  Domain Terra:  ${G}${TERRA_DOMAIN}${NC}"
log "  Exchange Rate: ${G}${IGP_EXCHANGE_RATE}${NC}"
log "  Gas Price:     ${G}${IGP_GAS_PRICE} wei${NC}"
log ""
log "  ${INFO} Nota: setRemoteGasData é chamado no GAS ORACLE (não no IGP)."
log "           O IGP customizado (TerraClassicIGPStandalone) consulta o oracle"
log "           para calcular o custo de gas."
log ""

if [ "$HAVE_CAST" = "false" ]; then
    log_warn "cast not available — run manually:"
    log "  cast send ${GAS_ORACLE} \"setRemoteGasData(uint32,uint128,uint128)\" \\"
    log "    ${TERRA_DOMAIN} ${IGP_EXCHANGE_RATE} ${IGP_GAS_PRICE} \\"
    log "    --rpc-url ${NET_RPC} --private-key \$ETH_PRIVATE_KEY --legacy"
else
    # Check if there is already data for this domain
    CURRENT_RATE=$(cast call "$GAS_ORACLE" \
        "getExchangeRateAndGasPrice(uint32)(uint128,uint128)" \
        "$TERRA_DOMAIN" --rpc-url "$NET_RPC" 2>/dev/null | head -1 || echo "0")

    if [ "${CURRENT_RATE}" != "0" ] && [ "${CURRENT_RATE}" != "null" ]; then
        log_ok "Gas Oracle already configured for Terra Classic (domain ${TERRA_DOMAIN})!"
        log "  Current Exchange Rate: ${G}${CURRENT_RATE}${NC}"
        log_info "Updating with new values..."
    fi

    TX=$(cast_tx "$GAS_ORACLE" \
        "setRemoteGasData(uint32,uint128,uint128)" \
        "$TERRA_DOMAIN" "$IGP_EXCHANGE_RATE" "$IGP_GAS_PRICE" \
        --rpc-url "$NET_RPC" \
        --private-key "$ETH_PRIVATE_KEY" \
        --legacy) || { log_warn "setRemoteGasData falhou (pode não ser owner do oracle) — continuando..."; TX=""; }

    if [ -n "$TX" ]; then
        log_ok "Gas Oracle configured for Terra Classic!"
        log "   TX: ${B}${NET_EXPLORER}/tx/${TX}${NC}"
    else
        log_info "Gas Oracle possibly already configured or lacking owner permission."
    fi
fi

# ═════════════════════════════════════════════════════════════════════════════
# STEP 5 — CONFIGURE WARP ROUTE HOOK (AggregationHook = MerkleTree + IGP)
# ═════════════════════════════════════════════════════════════════════════════
log_sep "STEP 5 — CONFIGURE HOOK (AggregationHook = MerkleTree + IGP)"

log "  Warp Route:       ${G}${WARP_ADDRESS}${NC}"
log "  MerkleTree Hook:  ${G}${HOOK_MERKLE}${NC}"
log "  Custom IGP:       ${G}${IGP_ADDRESS}${NC}"
log "  AggFactory:       ${G}${AGG_HOOK_FACTORY:-N/A}${NC}"
log ""
log "  ${INFO} O AggregationHook garante que as msgs entram na merkle tree"
log "  ${INFO} (necessário para o validator assinar) E pagam o IGP customizado."
log ""

if [ "$HAVE_CAST" = "false" ]; then
    log_warn "cast not available — run manually:"
    log "  # 1. Deploy AggregationHook"
    log "  cast send ${AGG_HOOK_FACTORY:-<agg_hook_factory>} \"deploy(address[])\" \"[${HOOK_MERKLE},${IGP_ADDRESS}]\" \\"
    log "    --rpc-url ${NET_RPC} --private-key \$ETH_PRIVATE_KEY --legacy"
    log "  # 2. Get address via eth_call and set on Warp"
    log "  cast send ${WARP_ADDRESS} \"setHook(address)\" <AGG_HOOK_ADDRESS> \\"
    log "    --rpc-url ${NET_RPC} --private-key \$ETH_PRIVATE_KEY --legacy"
else
    # Check if we already have a deployed AggregationHook in config
    if [ -n "${HOOK_AGG_ADDRESS:-}" ] && [ "${HOOK_AGG_ADDRESS}" != "null" ]; then
        log_info "AggregationHook already set: ${G}${HOOK_AGG_ADDRESS}${NC}"
    elif [ -z "${AGG_HOOK_FACTORY:-}" ] || [ "${AGG_HOOK_FACTORY}" = "null" ]; then
        log_warn "agg_hook_factory not configured — using only IGP as hook (legacy)."
        log_warn "${R}⚠ WARNING: without MerkleTree in hook, the validator will NOT see messages!${NC}"
        HOOK_AGG_ADDRESS="$IGP_ADDRESS"
    else
        log_info "Deploying AggregationHook [MerkleTree + IGP] via factory..."
        # Simulate deploy to get deterministic address
        HOOK_AGG_ADDRESS=$(cast call "$AGG_HOOK_FACTORY" \
            "deploy(address[])(address)" \
            "[$HOOK_MERKLE,$IGP_ADDRESS]" \
            --rpc-url "$NET_RPC" 2>/dev/null || echo "")

        if [ -z "$HOOK_AGG_ADDRESS" ] || [ "$HOOK_AGG_ADDRESS" = "0x0000000000000000000000000000000000000000" ]; then
            log_warn "Could not get address via simulation — doing real deploy..."
            TX_AGG=$(cast_tx "$AGG_HOOK_FACTORY" \
                "deploy(address[])" \
                "[$HOOK_MERKLE,$IGP_ADDRESS]" \
                --rpc-url "$NET_RPC" \
                --private-key "$ETH_PRIVATE_KEY" \
                --legacy) || { log_err "Deploy AggregationHook falhou!"; exit 1; }
            log_ok "AggregationHook deployed! TX: ${B}${NET_EXPLORER}/tx/${TX_AGG}${NC}"
            # Re-obtain address after deploy
            HOOK_AGG_ADDRESS=$(cast call "$AGG_HOOK_FACTORY" \
                "deploy(address[])(address)" \
                "[$HOOK_MERKLE,$IGP_ADDRESS]" \
                --rpc-url "$NET_RPC" 2>/dev/null || echo "")
        else
            # Real deploy (address already exists deterministically, but must be deployed)
            TX_AGG=$(cast_tx "$AGG_HOOK_FACTORY" \
                "deploy(address[])" \
                "[$HOOK_MERKLE,$IGP_ADDRESS]" \
                --rpc-url "$NET_RPC" \
                --private-key "$ETH_PRIVATE_KEY" \
                --legacy 2>/dev/null) || true
            [ -n "$TX_AGG" ] && log "   TX AggHook: ${B}${NET_EXPLORER}/tx/${TX_AGG}${NC}"
        fi

        if [ -n "$HOOK_AGG_ADDRESS" ] && [ "$HOOK_AGG_ADDRESS" != "0x0000000000000000000000000000000000000000" ]; then
            log_ok "AggregationHook: ${G}${HOOK_AGG_ADDRESS}${NC}"
            export HOOK_AGG_ADDRESS
        else
            log_warn "AggregationHook address not obtained — using only IGP (legacy)."
            HOOK_AGG_ADDRESS="$IGP_ADDRESS"
        fi
    fi

    # Set the AggregationHook (or IGP fallback) on the Warp Route
    CURRENT_HOOK=$(cast call "$WARP_ADDRESS" "hook()(address)" \
        --rpc-url "$NET_RPC" 2>/dev/null || echo "")

    if [ "${CURRENT_HOOK,,}" = "${HOOK_AGG_ADDRESS,,}" ]; then
        log_ok "Hook already configured correctly: ${G}${CURRENT_HOOK}${NC}"
    else
        log_info "Current hook: ${CURRENT_HOOK:-none}"
        log_info "Setting hook to AggregationHook [MerkleTree + IGP]..."
        TX_HOOK=$(cast_tx "$WARP_ADDRESS" \
            "setHook(address)" "$HOOK_AGG_ADDRESS" \
            --rpc-url "$NET_RPC" \
            --private-key "$ETH_PRIVATE_KEY" \
            --legacy) || { log_err "setHook failed!"; exit 1; }
        log_ok "Hook updated: ${G}${HOOK_AGG_ADDRESS}${NC}"
        [ -n "$TX_HOOK" ] && log "   TX: ${B}${NET_EXPLORER}/tx/${TX_HOOK}${NC}"
    fi
fi
save_state

# ═════════════════════════════════════════════════════════════════════════════
# STEP 6 — CONFIGURE WARP ROUTE ISM
# ═════════════════════════════════════════════════════════════════════════════
log_sep "STEP 6 — CONFIGURE WARP ROUTE ISM"

if [ -n "$ISM_DEPLOYED_CFG" ] && [ "$ISM_DEPLOYED_CFG" != "null" ] && is_evm "$ISM_DEPLOYED_CFG"; then
    log "  ISM: ${G}${ISM_DEPLOYED_CFG}${NC}"
    if [ "$HAVE_CAST" = "false" ]; then
        log_warn "cast não disponível — execute:"
        log "  cast send ${WARP_ADDRESS} \"setInterchainSecurityModule(address)\" \\"
        log "    ${ISM_DEPLOYED_CFG} --rpc-url ${NET_RPC} --private-key \$ETH_PRIVATE_KEY --legacy"
    else
        CURR_ISM=$(cast call "$WARP_ADDRESS" "interchainSecurityModule()(address)" \
            --rpc-url "$NET_RPC" 2>/dev/null || echo "")
        if [ "${CURR_ISM,,}" = "${ISM_DEPLOYED_CFG,,}" ]; then
            log_ok "ISM already configured."
        else
            TX_ISM=$(cast_tx "$WARP_ADDRESS" \
                "setInterchainSecurityModule(address)" "$ISM_DEPLOYED_CFG" \
                --rpc-url "$NET_RPC" \
                --private-key "$ETH_PRIVATE_KEY" \
                --legacy) || log_warn "setInterchainSecurityModule falhou (pode usar ISM do Mailbox)"
            [ -n "${TX_ISM:-}" ] && {
                log_ok "ISM updated!"
                log "   TX: ${B}${NET_EXPLORER}/tx/${TX_ISM}${NC}"
            }
        fi
    fi
else
    log_info "ISM not explicitly defined → Warp will use the Mailbox default ISM."
    log "  Mailbox default ISM:"
    log "  ${C}cast call ${MAILBOX} \"defaultIsm()(address)\" --rpc-url ${NET_RPC}${NC}"
fi

# ═════════════════════════════════════════════════════════════════════════════
# STEP 7 — ENROLL REMOTE ROUTER (link Terra Classic ↔ this network)
# ═════════════════════════════════════════════════════════════════════════════
log_sep "STEP 7 — LINK TERRA CLASSIC ROUTE (enrollRemoteRouter)"

if [ -n "${SKIP_ENROLL:-}" ]; then
    log_warn "enrollRemoteRouter skipped (SKIP_ENROLL or Terra warp not deployed)."
    log ""
    log "  When the Terra Classic Warp is deployed, run:"
    log "  ${C}cast send ${WARP_ADDRESS} \"enrollRemoteRouter(uint32,bytes32)\" \\"
    log "    ${TERRA_DOMAIN} 0x<WARP_TERRA_HEX_BYTES32> \\"
    log "    --rpc-url ${NET_RPC} --private-key \$ETH_PRIVATE_KEY --legacy${NC}"
elif [ -z "$TERRA_WARP_HEX" ]; then
    log_warn "warp_hexed empty in config — enrollRemoteRouter skipped."
else
    TERRA_B32=$(to_bytes32 "$TERRA_WARP_HEX")
    log "  ${NET_KEY} (domain ${NET_DOMAIN}) → Terra Classic (domain ${TERRA_DOMAIN})"
    log "  Terra Warp bytes32: ${G}${TERRA_B32}${NC}"

    if [ "$HAVE_CAST" = "false" ]; then
        log_warn "cast not available — run manually:"
        log "  cast send ${WARP_ADDRESS} \"enrollRemoteRouter(uint32,bytes32)\" \\"
        log "    ${TERRA_DOMAIN} 0x${TERRA_B32} \\"
        log "    --rpc-url ${NET_RPC} --private-key \$ETH_PRIVATE_KEY --legacy"
    else
        TX_ENROLL=$(cast_tx "$WARP_ADDRESS" \
            "enrollRemoteRouter(uint32,bytes32)" \
            "$TERRA_DOMAIN" "0x${TERRA_B32}" \
            --rpc-url "$NET_RPC" \
            --private-key "$ETH_PRIVATE_KEY" \
            --legacy) || log_warn "enrollRemoteRouter falhou (pode já estar configurado)"
        [ -n "${TX_ENROLL:-}" ] && {
            log_ok "Terra Classic route linked!"
            log "   TX: ${B}${NET_EXPLORER}/tx/${TX_ENROLL}${NC}"
        }
    fi
fi

# ═════════════════════════════════════════════════════════════════════════════
# STEP 7B — ENROLL REMOTE ROUTER ON TERRA CLASSIC (set_route)
#   Registers the EVM Warp in the Terra Classic Warp contract.
#   Without this step, transfer_remote from Terra Classic fails with "route not found"
# ═════════════════════════════════════════════════════════════════════════════
log_sep "STEP 7B — LINK EVM ROUTE ON TERRA CLASSIC (set_route)"

if [ -n "${SKIP_ENROLL:-}" ]; then
    log_warn "set_route Terra Classic skipped (SKIP_ENROLL set)."
    log "  Execute manualmente com: ./enroll-terra-router.sh"
elif [ -z "${TERRA_WARP_ADDR:-}" ]; then
    log_warn "Terra Classic Warp not deployed — set_route will be skipped."
    log "  Após fazer o deploy do Warp Terra Classic, execute: ./enroll-terra-router.sh"
elif [ -z "${TERRA_PRIVATE_KEY:-}" ]; then
    log_warn "TERRA_PRIVATE_KEY not set — Terra Classic set_route skipped."
    log "  Run: export TERRA_PRIVATE_KEY='hex_key' && ./enroll-terra-router.sh"
else
    # Convert EVM Warp address to bytes32 (without 0x)
    EVM_B32_HEX="${WARP_ADDRESS#0x}"
    EVM_B32=$(printf '%064s' "$EVM_B32_HEX" | tr ' ' '0')
    log "  Terra Classic Warp: ${G}${TERRA_WARP_ADDR}${NC}"
    log "  EVM (${NET_KEY}) domain ${NET_DOMAIN} → bytes32: ${G}${EVM_B32}${NC}"
    log ""

    TERRA_PRIV_CLEAN="${TERRA_PRIVATE_KEY#0x}"

    # Write Node.js script to temp file (avoids bash bug: heredoc inside $() with set -euo pipefail)
    _NODE_TMP=$(mktemp /tmp/set-route-XXXXXX.js)
    cat > "$_NODE_TMP" <<'NODEJS_SCRIPT'
const path = require('path');
const nm   = path.join(process.env._NM_ROOT, 'node_modules');
const { SigningCosmWasmClient } = require(path.join(nm, '@cosmjs/cosmwasm-stargate'));
const { DirectSecp256k1Wallet } = require(path.join(nm, '@cosmjs/proto-signing'));
const { GasPrice }              = require(path.join(nm, '@cosmjs/stargate'));
const { fromHex }               = require(path.join(nm, '@cosmjs/encoding'));

async function main() {
    const privKey    = process.env._NM_PRIV;
    const rpc        = process.env._NM_RPC;
    const warpAddr   = process.env._NM_WARP;
    const evmB32     = process.env._NM_EVM_B32;
    const netDomain  = parseInt(process.env._NM_DOMAIN, 10);

    const wallet = await DirectSecp256k1Wallet.fromKey(fromHex(privKey), 'terra');
    const [account] = await wallet.getAccounts();
    const client = await SigningCosmWasmClient.connectWithSigner(
        rpc, wallet,
        { gasPrice: GasPrice.fromString('28.325uluna') }
    );

    // Verificar usando list_routes
    try {
        const routes = await client.queryContractSmart(warpAddr, {
            router: { list_routes: {} }
        });
        const ex = (routes.routes || []).find(r => r.domain === netDomain);
        if (ex && ex.route) {
            console.log('STATUS=already_set');
            console.log('EXISTING=' + ex.route);
            return;
        }
    } catch(e) { /* rota ainda nao existe, continuar */ }

    const result = await client.execute(
        account.address, warpAddr,
        { router: { set_route: { set: { domain: netDomain, route: evmB32 } } } },
        'auto',
        'enrollRemoteRouter Terra Classic via create-warp-evm.sh'
    );
    console.log('STATUS=ok');
    console.log('TX=' + result.transactionHash);
    console.log('HEIGHT=' + result.height);
}
main().catch(e => { console.log('STATUS=error'); console.log('ERR=' + e.message); process.exit(0); });
NODEJS_SCRIPT

    # Run node passing variables via env (no bash expansion in JS, no heredoc in $())
    SET_ROUTE_RESULT=""
    set +e
    SET_ROUTE_RESULT=$(
        _NM_ROOT="$PROJECT_ROOT" \
        _NM_PRIV="$TERRA_PRIV_CLEAN" \
        _NM_RPC="$TERRA_RPC" \
        _NM_WARP="$TERRA_WARP_ADDR" \
        _NM_EVM_B32="$EVM_B32" \
        _NM_DOMAIN="$NET_DOMAIN" \
        node --no-warnings "$_NODE_TMP" 2>&1
    )
    _NODE_EXIT=$?
    set -e
    rm -f "$_NODE_TMP"

    # If node crashed unexpectedly (no STATUS= in output), capture as error
    if [ $_NODE_EXIT -ne 0 ] && ! echo "$SET_ROUTE_RESULT" | grep -q "^STATUS="; then
        SR_STATUS="error"
        SR_ERR="node exited with code $_NODE_EXIT: $(echo "$SET_ROUTE_RESULT" | tail -3)"
    else
        # IMPORTANT: use "|| echo """ to prevent grep with no match (exit 1) from
        # causing script exit with set -euo pipefail (bug: grep exits 1 when no match found)
        SR_STATUS=$(echo "$SET_ROUTE_RESULT" | grep "^STATUS=" | cut -d= -f2  || echo "")
        SR_TX=$(echo "$SET_ROUTE_RESULT"     | grep "^TX="     | cut -d= -f2   || echo "")
        SR_ERR=$(echo "$SET_ROUTE_RESULT"    | grep "^ERR="    | cut -d= -f2-  || echo "")
    fi

    case "$SR_STATUS" in
        ok)
            log_ok "set_route executed! Terra Classic knows the ${NET_KEY} Warp."
            log "   TX: ${B}https://finder.hexxagon.io/${TERRA_CHAIN_ID}/tx/${SR_TX}${NC}"
            ;;
        already_set)
            EXISTING_ROUTE=$(echo "$SET_ROUTE_RESULT" | grep "^EXISTING=" | cut -d= -f2 || echo "")
            log_ok "Route already configured on Terra Classic (${EXISTING_ROUTE:-already set})."
            ;;
        error)
            log_warn "Terra Classic set_route failed: ${SR_ERR}"
            log "  Detalhes: $(echo "$SET_ROUTE_RESULT" | grep -v "^STATUS=" | head -5)"
            log "  Run manually: ${C}./enroll-terra-router.sh${NC}"
            ;;
        *)
            log_warn "Terra Classic set_route: unexpected result (exit=${_NODE_EXIT})."
            [ -n "$SET_ROUTE_RESULT" ] && log "  Output: $(echo "$SET_ROUTE_RESULT" | head -5)"
            log "  Run manually: ${C}./enroll-terra-router.sh${NC}"
            ;;
    esac
fi

# ═════════════════════════════════════════════════════════════════════════════
# STEP 8 — FINAL VERIFICATION
# ═════════════════════════════════════════════════════════════════════════════
log_sep "STEP 8 — FINAL VERIFICATION"

wait_sec 12 "Waiting for propagation"

ERROS=0

if [ "$HAVE_CAST" = "true" ]; then

    # 1. Mailbox
    log_info "1. Mailbox (${MAILBOX})..."
    MB_CODE=$(cast code "$MAILBOX" --rpc-url "$NET_RPC" 2>/dev/null || echo "0x")
    [ "$MB_CODE" != "0x" ] && log_ok "Mailbox ok" || { log_warn "Mailbox not found"; ERROS=$((ERROS+1)); }

    # 2. Warp Route exists
    log_info "2. Warp Route (${WARP_ADDRESS})..."
    WP_CODE=$(cast code "$WARP_ADDRESS" --rpc-url "$NET_RPC" 2>/dev/null || echo "0x")
    [ "$WP_CODE" != "0x" ] && log_ok "Warp Route exists" || { log_err "Warp Route not found!"; ERROS=$((ERROS+1)); }

    # 3. Hook = AggregationHook (or IGP fallback)
    log_info "3. Warp Route Hook..."
    HOOK=$(cast call "$WARP_ADDRESS" "hook()(address)" --rpc-url "$NET_RPC" 2>/dev/null || echo "")
    EXPECTED_HOOK="${HOOK_AGG_ADDRESS:-${IGP_ADDRESS}}"
    if [ "${HOOK,,}" = "${EXPECTED_HOOK,,}" ]; then
        log_ok "Hook = AggregationHook ✅  (${HOOK})"
    elif [ "${HOOK,,}" = "${IGP_ADDRESS,,}" ]; then
        log_warn "Hook = IGP (legacy) — no MerkleTree! Msgs will not be signed by validator."
        log_warn "Run again to fix with AggregationHook."
        ERROS=$((ERROS+1))
    else
        log_warn "Hook: ${HOOK} ≠ ${EXPECTED_HOOK}"
        ERROS=$((ERROS+1))
    fi

    # 4. hookType of custom IGP
    log_info "4. Custom IGP hookType..."
    HTYPE=$(cast call "$IGP_ADDRESS" "hookType()(uint8)" --rpc-url "$NET_RPC" 2>/dev/null || echo "")
    [ "$HTYPE" = "4" ] && log_ok "hookType IGP = 4 (INTERCHAIN_GAS_PAYMASTER) ✅" \
                       || { log_err "hookType IGP=$HTYPE (must be 4)"; ERROS=$((ERROS+1)); }

    # 5. ISM
    log_info "5. Warp Route ISM..."
    ISM_WP=$(cast call "$WARP_ADDRESS" "interchainSecurityModule()(address)" \
        --rpc-url "$NET_RPC" 2>/dev/null || echo "")
    if [ -n "$ISM_WP" ] && [ "$ISM_WP" != "0x0000000000000000000000000000000000000000" ]; then
        log_ok "ISM: ${ISM_WP}"
    else
        log_info "ISM: inherited from Mailbox (normal if not set)"
    fi

    # 6. Terra Classic Router
    if [ -z "${SKIP_ENROLL:-}" ] && [ -n "$TERRA_WARP_HEX" ]; then
        log_info "6. Terra Classic Route..."
        ROUTER=$(cast call "$WARP_ADDRESS" "routers(uint32)(bytes32)" "$TERRA_DOMAIN" \
            --rpc-url "$NET_RPC" 2>/dev/null || echo "0x00")
        TERRA_B32_EXP=$(to_bytes32 "$TERRA_WARP_HEX")
        if echo "${ROUTER,,}" | grep -q "${TERRA_B32_EXP,,}"; then
            log_ok "Terra Classic route linked ✅"
        else
            log_warn "Router: ${ROUTER} (esperado: 0x${TERRA_B32_EXP})"
            ERROS=$((ERROS+1))
        fi
    fi
fi

# ═════════════════════════════════════════════════════════════════════════════
# FINAL RESULT
# ═════════════════════════════════════════════════════════════════════════════
log ""
if [ "$ERROS" -eq 0 ]; then
    log "╔══════════════════════════════════════════════════════════════════════════╗"
    log "║                                                                          ║"
    log "║        ✅✅✅  WARP ROUTE CONFIGURED SUCCESSFULLY!  ✅✅✅             ║"
    log "║                                                                          ║"
    log "╚══════════════════════════════════════════════════════════════════════════╝"
else
    log "╔══════════════════════════════════════════════════════════════════════════╗"
    log "║       ⚠️  DEPLOY COMPLETED WITH ${ERROS} WARNING(S)                       ║"
    log "╚══════════════════════════════════════════════════════════════════════════╝"
fi

log ""
log "${G}${W}📋 SUMMARY — ${TOKEN_SYMBOL} on ${NET_DISPLAY}${NC}"
log "────────────────────────────────────────────────────────────────────────"
log "  Token:       ${TOKEN_NAME} (${TOKEN_SYMBOL})"
log "  📮 Mailbox:  ${G}${MAILBOX}${NC}"
log "  🔗 Warp EVM: ${G}${WARP_ADDRESS}${NC}"
log "  ⛽ IGP:       ${G}${IGP_ADDRESS}${NC}"
log "  🔐 ISM:      ${ISM_TYPE} | validators: ${ISM_VALIDATORS} | threshold: ${ISM_THRESHOLD}"
log "  🪝 Hook:     custom IGP (hookType=4)"
log "  🌍 Domains:  EVM=${NET_DOMAIN} | Terra=${TERRA_DOMAIN}"
log ""
log "  Terra Classic (${TOKEN_KEY}):"
log "    Tipo:  ${TERRA_WARP_TYPE} / ${TERRA_WARP_MODE}"
[ -n "$TERRA_WARP_ADDR" ] && log "    Warp:  ${G}${TERRA_WARP_ADDR}${NC}" \
                           || log "    Warp:  ${Y}(not yet deployed)${NC}"
log ""
log "  IGP config → Terra Classic:"
log "    Exchange Rate: ${IGP_EXCHANGE_RATE}"
log "    Gas Price:     ${IGP_GAS_PRICE} wei"
log ""
log "${C}🎯 LINKS:${NC}"
log "  Warp Route:  ${B}${NET_EXPLORER}/address/${WARP_ADDRESS}${NC}"
log "  Hyperlane:   ${B}https://explorer.hyperlane.xyz${NC}"
log "────────────────────────────────────────────────────────────────────────"
log "${INFO} Log: ${Y}${LOG_FILE}${NC}"
log ""

# Save report
REPORT_FILE="$LOG_DIR/WARP-${NET_KEY^^}-${TOKEN_KEY^^}.txt"
cat > "$REPORT_FILE" <<TXT
═══════════════════════════════════════════════════════════
  WARP: ${TOKEN_SYMBOL} on ${NET_DISPLAY^^}
  Generated: $(date '+%Y-%m-%d %H:%M:%S')
═══════════════════════════════════════════════════════════

TOKEN:
  Name:     ${TOKEN_NAME}
  Symbol:   ${TOKEN_SYMBOL}
  Decimals: ${TOKEN_DEC}
  Type:     ${TERRA_WARP_TYPE} / ${TERRA_WARP_MODE}

EVM NETWORK: ${NET_DISPLAY}
  Chain ID:  ${NET_CHAIN_ID}
  Domain:    ${NET_DOMAIN}

EVM CONTRACTS:
  Mailbox:   ${MAILBOX}
  Warp:      ${WARP_ADDRESS}
  IGP:       ${IGP_ADDRESS}
  GasOracle: ${GAS_ORACLE}
  ISM:       ${ISM_TYPE} | validators: ${ISM_VALIDATORS}

TERRA CLASSIC:
  Domain:    ${TERRA_DOMAIN}
  Type:      ${TERRA_WARP_TYPE} / ${TERRA_WARP_MODE}
  Owner:     ${TERRA_WARP_OWNER}
  CW20/Denom: ${TERRA_WARP_COLLAT:-${TERRA_WARP_DENOM}}
  Warp:      ${TERRA_WARP_ADDR:-PENDING}

IGP CONFIG (EVM → Terra):
  Exchange Rate: ${IGP_EXCHANGE_RATE}
  Gas Price:     ${IGP_GAS_PRICE} wei
═══════════════════════════════════════════════════════════
TXT

save_state
log_ok "Report: ${Y}${REPORT_FILE}${NC}"
log ""
