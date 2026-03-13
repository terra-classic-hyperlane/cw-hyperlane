#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
#  🚀 CREATE WARP ROUTE SOLANA (SEALEVEL) ↔ TERRA CLASSIC — HYPERLANE
# ═══════════════════════════════════════════════════════════════════════════════
#
#  USAGE:
#    export TERRA_PRIVATE_KEY="YOUR_TERRA_PRIVATE_KEY_HEX"
#    chmod +x create-warp-sealevel.sh
#    ./create-warp-sealevel.sh
#
#  SKIP STEPS (program already deployed):
#    export WARP_PROGRAM_ID="Base58ProgramID"  → skips Warp Solana deploy
#    export SKIP_ISM="1"                       → skips ISM configuration
#    export SKIP_IGP="1"                       → skips IGP configuration
#    export SKIP_GAS="1"                       → skips destination gas configuration
#    export SKIP_ENROLL="1"                    → skips enroll remote router (Solana→TC)
#    export SKIP_TC_ROUTE="1"                  → skips set_route (TC→Solana)
#
#  ON SOLANA (Sealevel):
#    - Program ID  = the Warp Route (router address)
#    - Mint        = the SPL token created by warp (for type=synthetic)
#    - ISM         = MultisigISM program (validates msgs from Terra Classic)
#    - IGP         = Gas Paymaster (pays gas on Terra Classic)
#    - no AggregationHook like EVM — Sealevel has a different architecture
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
EVM_CONFIG="$SCRIPT_DIR/warp-evm-config.json"        # Terra Classic tokens
SOL_CONFIG="$SCRIPT_DIR/warp-sealevel-config.json"   # Solana networks
LOG_DIR="$SCRIPT_DIR/log"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/create-warp-sealevel.log"
STATE_FILE="$SCRIPT_DIR/.warp-sealevel-state.json"

# Auto-detect PROJECT_ROOT (for node_modules / cosmjs)
PROJECT_ROOT="$SCRIPT_DIR"
while [ ! -f "$PROJECT_ROOT/package.json" ] && [ "$PROJECT_ROOT" != "/" ]; do
    PROJECT_ROOT="$(dirname "$PROJECT_ROOT")"
done
if [ ! -f "$PROJECT_ROOT/package.json" ]; then
    echo "❌ Could not find the project root (package.json)!"
    exit 1
fi

# ─────────────────────────────────────────────────────────────────────────────
# UTILITIES
# ─────────────────────────────────────────────────────────────────────────────
log()      { echo -e "$@" | tee -a "$LOG_FILE"; }
log_ok()   { log "${OK} $*"; }
log_err()  { log "${ERR} $*"; }
log_warn() { log "${WARN} $*"; }
log_info() { log "${INFO} $*"; }
log_sep()  { log ""; log "${C}${W}$1${NC}"; log "────────────────────────────────────────────────────────────────"; }

evm_cfg()  { jq -r "$1" "$EVM_CONFIG" 2>/dev/null || echo ""; }
sol_cfg()  { jq -r "$1" "$SOL_CONFIG" 2>/dev/null || echo ""; }

wait_sec() {
    local s="$1" msg="${2:-Awaiting confirmation}"
    echo -ne "${INFO} ${msg}: "
    for ((i=s; i>0; i--)); do echo -ne "${i}s "; sleep 1; done
    echo "✓"
}

# Converts Program ID base58 → hex bytes32 (without 0x) using pure Python
b58_to_hex32() {
    python3 - "$1" <<'PYEOF' 2>/dev/null
import sys
def b58decode(s):
    alphabet = '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz'
    n = 0
    for c in s:
        if c not in alphabet:
            raise ValueError(f"Invalid char: {c}")
        n = n * 58 + alphabet.index(c)
    result = []
    while n > 0:
        result.append(n & 0xFF)
        n >>= 8
    result.reverse()
    # padding leading zeros
    for c in s:
        if c == '1': result.insert(0, 0)
        else: break
    return bytes(result)
try:
    decoded = b58decode(sys.argv[1])
    # Solana pubkeys are 32 bytes
    print(decoded.hex().zfill(64))
except Exception as e:
    sys.exit(1)
PYEOF
}

# Extract base58 pubkey from keypair JSON (array of 64 bytes: [secret(32)|public(32)])
keypair_to_pubkey() {
    python3 - "$1" <<'PYEOF' 2>/dev/null
import json, sys
try:
    with open(sys.argv[1], 'r') as f:
        data = json.load(f)
    if isinstance(data, list) and len(data) >= 64:
        pub = bytes(data[32:64])
    else:
        sys.exit(1)
    alphabet = '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz'
    n = int.from_bytes(pub, 'big')
    result = ''
    while n > 0:
        result = alphabet[n % 58] + result
        n //= 58
    for b in pub:
        if b == 0: result = '1' + result
        else: break
    print(result)
except Exception:
    sys.exit(1)
PYEOF
}

save_state() {
    cat > "$STATE_FILE" <<EOF
{
  "network":    "${NET_KEY:-}",
  "token":      "${TOKEN_KEY:-}",
  "program_id": "${WARP_PROGRAM_ID:-}",
  "program_hex":"${WARP_HEX:-}",
  "mint":       "${MINT_ADDRESS:-}",
  "timestamp":  "$(date -Iseconds)"
}
EOF
}

load_state() {
    [ -f "$STATE_FILE" ] || return 0
    _STATE_NET=$(jq -r '.network    // ""' "$STATE_FILE" 2>/dev/null || echo "")
    _STATE_TOK=$(jq -r '.token      // ""' "$STATE_FILE" 2>/dev/null || echo "")
    _STATE_PID=$(jq -r '.program_id // ""' "$STATE_FILE" 2>/dev/null || echo "")
    _STATE_HEX=$(jq -r '.program_hex// ""' "$STATE_FILE" 2>/dev/null || echo "")
    _STATE_MINT=$(jq -r '.mint      // ""' "$STATE_FILE" 2>/dev/null || echo "")
    if [ -n "$_STATE_TOK" ]; then
        log_warn "Previous state: token=${_STATE_TOK}, net=${_STATE_NET:-—}, program=${_STATE_PID:-—}"
        log "   To restart: ${Y}rm -f $STATE_FILE${NC}"
    fi
}

apply_state() {
    # Applies state ONLY if token+network match the current selection
    [ -z "${_STATE_TOK:-}" ] && return 0
    if [ "${_STATE_TOK}" = "${TOKEN_KEY}" ] && [ "${_STATE_NET}" = "${NET_KEY}" ]; then
        [ -z "${WARP_PROGRAM_ID:-}" ] && [ -n "${_STATE_PID:-}"  ] && export WARP_PROGRAM_ID="$_STATE_PID"
        [ -z "${WARP_HEX:-}"        ] && [ -n "${_STATE_HEX:-}"  ] && export WARP_HEX="$_STATE_HEX"
        [ -z "${MINT_ADDRESS:-}"    ] && [ -n "${_STATE_MINT:-}" ] && export MINT_ADDRESS="$_STATE_MINT"
        [ -n "${WARP_PROGRAM_ID:-}" ] && log_info "State restored: program=${WARP_PROGRAM_ID}, mint=${MINT_ADDRESS:-—}"
    else
        log_info "Previous state was for ${_STATE_TOK}/${_STATE_NET} — ignored for ${TOKEN_KEY}/${NET_KEY}."
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# BANNER
# ─────────────────────────────────────────────────────────────────────────────
> "$LOG_FILE"
clear 2>/dev/null || true
log "╔══════════════════════════════════════════════════════════════════════════╗"
log "║                                                                          ║"
log "║    🚀  CREATE WARP ROUTE SOLANA ↔ TERRA CLASSIC — HYPERLANE SEALEVEL 🚀 ║"
log "║                                                                          ║"
log "║    Configs: warp-sealevel-config.json + warp-evm-config.json            ║"
log "║    Data: $(date '+%Y-%m-%d %H:%M:%S')                                        ║"
log "╚══════════════════════════════════════════════════════════════════════════╝"
log ""

# ─────────────────────────────────────────────────────────────────────────────
# INITIAL CHECKS
# ─────────────────────────────────────────────────────────────────────────────
for cfg_file in "$EVM_CONFIG" "$SOL_CONFIG"; do
    if [ ! -f "$cfg_file" ]; then
        log_err "File not found: $cfg_file"; exit 1
    fi
    if ! jq empty "$cfg_file" 2>/dev/null; then
        log_err "Invalid JSON: $cfg_file"; exit 1
    fi
done
log_ok "Valid configurations: warp-evm-config.json + warp-sealevel-config.json"

# Check required tools
command -v jq      &>/dev/null || { log_err "jq is required!";         exit 1; }
command -v python3 &>/dev/null || { log_err "python3 is required!";    exit 1; }
command -v node    &>/dev/null || { log_err "node is required!";        exit 1; }
command -v cargo   &>/dev/null || { log_err "cargo (Rust) is required!"; exit 1; }
command -v solana  &>/dev/null || { log_err "solana-cli is required!";  exit 1; }

# Terra Classic (from warp-evm-config.json)
TERRA_DOMAIN=$(evm_cfg '.terra_classic.domain')
TERRA_RPC=$(evm_cfg    '.terra_classic.rpc')
TERRA_CHAIN_ID=$(evm_cfg '.terra_classic.chain_id')
log_ok "Terra Classic: domain=${TERRA_DOMAIN}, rpc=${TERRA_RPC}"

load_state

# ═════════════════════════════════════════════════════════════════════════════
# MENU 1 — SELECT TOKEN (Terra Classic)
# ═════════════════════════════════════════════════════════════════════════════
log_sep "STEP 1/2 — SELECT TOKEN (Terra Classic)"
log "  Tokens configured in ${C}warp-evm-config.json${NC}:"
log ""

mapfile -t TOKEN_KEYS < <(jq -r '.terra_classic.tokens | keys[]' "$EVM_CONFIG" 2>/dev/null)
declare -a TOKEN_MENU=()
i=1

for TK in "${TOKEN_KEYS[@]}"; do
    TK_NAME=$(evm_cfg ".terra_classic.tokens.${TK}.name")
    TK_SYM=$(evm_cfg  ".terra_classic.tokens.${TK}.symbol")
    TK_TYPE=$(evm_cfg ".terra_classic.tokens.${TK}.terra_warp.type")
    TK_DEPLOYED_TC=$(evm_cfg ".terra_classic.tokens.${TK}.terra_warp.deployed")
    TK_WARP_TC=$(evm_cfg     ".terra_classic.tokens.${TK}.terra_warp.warp_address")

    # Check if token has Solana config
    SOL_EXISTS=$(sol_cfg ".networks.solanatestnet.warp_tokens.${TK}.type" 2>/dev/null || echo "")
    SOL_DEPLOYED=$(sol_cfg ".networks.solanatestnet.warp_tokens.${TK}.deployed" 2>/dev/null || echo "false")
    SOL_PID=$(sol_cfg      ".networks.solanatestnet.warp_tokens.${TK}.program_id" 2>/dev/null || echo "")

    TOKEN_MENU+=("$TK")

    TAG_TC="${C}[terra: ${TK_TYPE}]${NC}"
    [ "$TK_DEPLOYED_TC"  = "true" ] && TAG_TC_DEP="${G}[warp TC ok]${NC}"  || TAG_TC_DEP="${Y}[warp TC pending]${NC}"
    [ "$SOL_DEPLOYED" = "true" ] && [ -n "$SOL_PID" ] \
        && TAG_SOL="${G}[solana: deployed]${NC}" || TAG_SOL="${B}[solana: new deploy]${NC}"

    log "   ${W}[$i]${NC}  ${C}${TK}${NC} — ${TK_NAME:-N/A} (${TK_SYM:-?}) ${TAG_TC} ${TAG_TC_DEP} ${TAG_SOL}"
    if [ -n "$TK_WARP_TC" ] && [ "$TK_WARP_TC" != "null" ]; then
        log "        Warp TC:    ${G}${TK_WARP_TC}${NC}"
    fi
    if [ -n "$SOL_PID" ] && [ "$SOL_PID" != "null" ]; then
        log "        Program ID: ${G}${SOL_PID}${NC}"
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
TK_TC=".terra_classic.tokens.${TOKEN_KEY}"

TOKEN_NAME=$(evm_cfg "${TK_TC}.name")
TOKEN_SYMBOL=$(evm_cfg "${TK_TC}.symbol")
TOKEN_DEC=$(evm_cfg "${TK_TC}.decimals")
TERRA_WARP_TYPE=$(evm_cfg   "${TK_TC}.terra_warp.type")
TERRA_WARP_MODE=$(evm_cfg   "${TK_TC}.terra_warp.mode")
TERRA_WARP_OWNER=$(evm_cfg  "${TK_TC}.terra_warp.owner")
TERRA_WARP_COLLAT=$(evm_cfg "${TK_TC}.terra_warp.collateral_address")
TERRA_WARP_DENOM=$(evm_cfg  "${TK_TC}.terra_warp.denom")
TERRA_WARP_ADDR=$(evm_cfg   "${TK_TC}.terra_warp.warp_address")
TERRA_WARP_HEX=$(evm_cfg    "${TK_TC}.terra_warp.warp_hexed")
TERRA_WARP_DEPLOYED=$(evm_cfg "${TK_TC}.terra_warp.deployed")

log_ok "Token selected: ${C}${TOKEN_KEY}${NC} — ${TOKEN_NAME} (${TOKEN_SYMBOL})"

# ═════════════════════════════════════════════════════════════════════════════
# MENU 2 — SELECT SOLANA NETWORK
# ═════════════════════════════════════════════════════════════════════════════
log_sep "STEP 2/2 — SELECT SOLANA NETWORK"
log "  Networks available in ${C}warp-sealevel-config.json${NC}:"
log ""

mapfile -t NET_KEYS < <(jq -r '.networks | keys[]' "$SOL_CONFIG" 2>/dev/null)
declare -a NET_MENU=()
i=1

for NK in "${NET_KEYS[@]}"; do
    NE=$(sol_cfg ".networks.${NK}.enabled")
    ND=$(sol_cfg ".networks.${NK}.display_name")
    ND_DOM=$(sol_cfg ".networks.${NK}.domain")
    SOL_WD=$(sol_cfg ".networks.${NK}.warp_tokens.${TOKEN_KEY}.deployed")
    SOL_WA=$(sol_cfg ".networks.${NK}.warp_tokens.${TOKEN_KEY}.program_id")

    if [ "$NE" = "true" ]; then
        NET_MENU+=("$NK")
        [ "$SOL_WD" = "true" ] && [ -n "$SOL_WA" ] && [ "$SOL_WA" != "null" ] \
            && TAG_W="${G}[warp already deployed]${NC}" \
            || TAG_W="${B}[new deploy]${NC}"
        log "   ${W}[$i]${NC}  ${C}${NK}${NC} — ${ND} (domain: ${ND_DOM}) ${TAG_W}"
        [ -n "$SOL_WA" ] && [ "$SOL_WA" != "null" ] && log "        Program ID: ${G}${SOL_WA}${NC}"
        log "        ISM:        $(sol_cfg ".networks.${NK}.ism.program_id")"
        log "        IGP:        $(sol_cfg ".networks.${NK}.igp.account")"
        log ""
        i=$((i+1))
    else
        log "   ${R}[-]${NC}  ${NK} — ${ND} ${R}[disabled]${NC}"
    fi
done

if [ ${#NET_MENU[@]} -eq 0 ]; then
    log_err "No Solana network enabled! Edit warp-sealevel-config.json."; exit 1
fi

echo -ne "  ${W}Choose the network [1-${#NET_MENU[@]}]: ${NC}"
read -r SEL_NET 2>/dev/null || SEL_NET="1"
SEL_NET="${SEL_NET:-1}"

if ! [[ "$SEL_NET" =~ ^[0-9]+$ ]] || [ "$SEL_NET" -lt 1 ] || [ "$SEL_NET" -gt "${#NET_MENU[@]}" ]; then
    log_err "Invalid selection: $SEL_NET"; exit 1
fi

NET_KEY="${NET_MENU[$((SEL_NET-1))]}"
N=".networks.${NET_KEY}"

# Load selected network config
NET_DISPLAY=$(sol_cfg "${N}.display_name")
NET_ENV=$(sol_cfg     "${N}.environment")
NET_DOMAIN=$(sol_cfg  "${N}.domain")
NET_RPC=$(sol_cfg     "${N}.rpc")
NET_EXPLORER=$(sol_cfg "${N}.explorer")
NET_KEYPAIR=$(sol_cfg "${N}.keypair" | sed "s|^~|$HOME|")
NET_MONOREPO=$(sol_cfg "${N}.monorepo_dir" | sed "s|^~|$HOME|")
ISM_PROGRAM_ID=$(sol_cfg "${N}.ism.program_id")
IGP_PROGRAM_ID=$(sol_cfg "${N}.igp.program_id")
IGP_ACCOUNT=$(sol_cfg    "${N}.igp.account")
DEST_GAS=$(sol_cfg       "${N}.igp.destination_gas_terra")

# Warp do token nesta rede (do config)
SOL_DEPLOYED_CFG=$(sol_cfg "${N}.warp_tokens.${TOKEN_KEY}.deployed")
SOL_PID_CFG=$(sol_cfg      "${N}.warp_tokens.${TOKEN_KEY}.program_id")
SOL_HEX_CFG=$(sol_cfg      "${N}.warp_tokens.${TOKEN_KEY}.program_hex")
SOL_MINT_CFG=$(sol_cfg     "${N}.warp_tokens.${TOKEN_KEY}.mint_address")
SOL_META_URI=$(sol_cfg     "${N}.warp_tokens.${TOKEN_KEY}.metadata_uri")
SOL_TOK_DEC=$(sol_cfg      "${N}.warp_tokens.${TOKEN_KEY}.decimals")
SOL_OWNER=$(sol_cfg        "${N}.warp_tokens.${TOKEN_KEY}.owner")
SOL_TYPE=$(sol_cfg         "${N}.warp_tokens.${TOKEN_KEY}.type")

log_ok "Network selected: ${C}${NET_KEY}${NC} — ${NET_DISPLAY} (domain: ${NET_DOMAIN})"

# Apply saved state ONLY if token+network match
apply_state

# Initialize runtime variables (priority: env > config > state)
WARP_PROGRAM_ID="${WARP_PROGRAM_ID:-}"
WARP_HEX="${WARP_HEX:-}"
MINT_ADDRESS="${MINT_ADDRESS:-}"

[ -z "$WARP_PROGRAM_ID" ] && [ -n "$SOL_PID_CFG"  ] && [ "$SOL_PID_CFG"  != "null" ] && WARP_PROGRAM_ID="$SOL_PID_CFG"
[ -z "$WARP_HEX"        ] && [ -n "$SOL_HEX_CFG"  ] && [ "$SOL_HEX_CFG"  != "null" ] && WARP_HEX="${SOL_HEX_CFG#0x}"
[ -z "$MINT_ADDRESS"    ] && [ -n "$SOL_MINT_CFG"  ] && [ "$SOL_MINT_CFG" != "null" ] && MINT_ADDRESS="$SOL_MINT_CFG"

# Validate keypair
if [ -z "$NET_KEYPAIR" ] || [ ! -f "$NET_KEYPAIR" ]; then
    log_err "Solana keypair not found: ${NET_KEYPAIR:-NOT CONFIGURED}"
    log "  Configure: warp-sealevel-config.json → .networks.${NET_KEY}.keypair"
    exit 1
fi

# Sealevel monorepo directories
if [ -z "$NET_MONOREPO" ] || [ ! -d "$NET_MONOREPO" ]; then
    log_err "Sealevel monorepo not found: ${NET_MONOREPO:-NOT CONFIGURED}"
    log "  Configure: warp-sealevel-config.json → .networks.${NET_KEY}.monorepo_dir"
    exit 1
fi

CLIENT_DIR="$NET_MONOREPO/client"
ENVIRONMENTS_DIR="$NET_MONOREPO/environments"
BUILT_SO_DIR="$NET_MONOREPO/target/deploy"
REGISTRY_DIR="$HOME/.hyperlane/registry"

if [ ! -d "$CLIENT_DIR" ]; then
    log_err "Rust client not found: $CLIENT_DIR"; exit 1
fi

if [ ! -f "$BUILT_SO_DIR/hyperlane_sealevel_token.so" ]; then
    log_err "Solana program not compiled: $BUILT_SO_DIR/hyperlane_sealevel_token.so"
    log "  Compile with: cd $NET_MONOREPO && cargo build --release"
    exit 1
fi

WARP_ROUTE_DIR="$ENVIRONMENTS_DIR/${NET_ENV}/warp-routes/${TOKEN_KEY}"
mkdir -p "$WARP_ROUTE_DIR/keys"

# ─────────────────────────────────────────────────────────────────────────────
# CONFIGURATION SUMMARY
# ─────────────────────────────────────────────────────────────────────────────
log ""
log "╔══════════════════════════════════════════════════════════════════════════╗"
log "║   📋  SUMMARY: Token ${C}${TOKEN_KEY}${NC} → Network ${C}${NET_DISPLAY}${NC}"
log "╚══════════════════════════════════════════════════════════════════════════╝"
log ""
log "  ${W}🪙 TOKEN${NC}"
log "     ${TOKEN_NAME} (${TOKEN_SYMBOL}) | type=${TERRA_WARP_TYPE} | decimals=${TOKEN_DEC}"
log ""
log "  ${W}🌐 SOLANA NETWORK${NC}"
log "     ${NET_DISPLAY}  |  Domain: ${NET_DOMAIN}"
log "     RPC: ${NET_RPC}"
log "     Keypair: ${NET_KEYPAIR}"
log ""
log "  ${W}🔐 ISM${NC}  —  MultisigISM validates msgs from Terra Classic"
log "     Program ID: ${ISM_PROGRAM_ID}"
log ""
log "  ${W}⛽ IGP${NC}  —  pays gas on Terra Classic"
log "     Program ID: ${IGP_PROGRAM_ID}"
log "     Account:    ${IGP_ACCOUNT}"
log "     Dest Gas:   ${DEST_GAS} (Terra Classic domain ${TERRA_DOMAIN})"
log ""
log "  ${W}🌍 TERRA CLASSIC${NC}"
log "     Domain: ${TERRA_DOMAIN}  |  Chain: ${TERRA_CHAIN_ID}"
log "     RPC: ${TERRA_RPC}"
if [ -n "$TERRA_WARP_ADDR" ] && [ "$TERRA_WARP_ADDR" != "null" ]; then
    log "     Warp: ${G}${TERRA_WARP_ADDR}${NC}"
else
    log "     Warp: ${R}NOT DEPLOYED${NC}"
fi
log ""

if [ "$TERRA_WARP_DEPLOYED" != "true" ] || [ -z "$TERRA_WARP_ADDR" ] || [ "$TERRA_WARP_ADDR" = "null" ]; then
    log_warn "Terra Classic Warp NOT deployed for '${TOKEN_KEY}'!"
    log "  Configure in warp-evm-config.json or use create-warp-evm.sh."
    log "  Bidirectional link steps (5 and 6) will be skipped."
    export SKIP_ENROLL="${SKIP_ENROLL:-1}"
    export SKIP_TC_ROUTE="${SKIP_TC_ROUTE:-1}"
fi

if [ -n "${WARP_PROGRAM_ID:-}" ]; then
    log_info "Program ID loaded: ${WARP_PROGRAM_ID} — deploy will be skipped."
fi

echo ""
echo -ne "  ${W}Confirm configuration and continue? [Y/n]: ${NC}"
read -r CONFIRM 2>/dev/null || CONFIRM="s"
CONFIRM="${CONFIRM:-s}"
if [[ ! "$CONFIRM" =~ ^[sSyY]$ ]]; then
    log "  Cancelled by user."; exit 0
fi

# ═════════════════════════════════════════════════════════════════════════════
# STEP 1 — DEPLOY WARP SOLANA
# ═════════════════════════════════════════════════════════════════════════════
log_sep "STEP 1 — DEPLOY WARP SOLANA (warp-route deploy)"

if [ -n "${WARP_PROGRAM_ID:-}" ]; then
    log_warn "WARP_PROGRAM_ID already set (${WARP_PROGRAM_ID}) — skipping deploy."
else
    # ── Resolve metadata URI ────────────────────────────────────────────────
    # Local path to metadata file (inside the cw-hyperlane project)
    WARP_SOL_DIR="$PROJECT_ROOT/warp/solana"
    LOCAL_META_FILE="$WARP_SOL_DIR/metadata-${TOKEN_KEY}.json"
    # Expected URL on GitHub (project standard)
    GITHUB_META_URI="https://raw.githubusercontent.com/igorv43/cw-hyperlane/refs/heads/main/warp/solana/metadata-${TOKEN_KEY}.json"

    # If metadata_uri empty or null → try using the GitHub default
    if [ -z "$SOL_META_URI" ] || [ "$SOL_META_URI" = "null" ]; then
        SOL_META_URI="$GITHUB_META_URI"
        log_warn "metadata_uri not configured — using default: $SOL_META_URI"
        # Update in config automatically
        TMP_CFG=$(mktemp)
        jq ".networks.\"${NET_KEY}\".warp_tokens.\"${TOKEN_KEY}\".metadata_uri = \"${SOL_META_URI}\"" \
            "$SOL_CONFIG" > "$TMP_CFG" && mv "$TMP_CFG" "$SOL_CONFIG"
    fi

    # Try downloading metadata from the configured URI
    META_TMP=$(mktemp /tmp/sol-meta-XXXXXX.json)
    META_NAME=""; META_SYM=""
    CURL_CODE=$(curl -s -o "$META_TMP" -w "%{http_code}" --max-time 15 "$SOL_META_URI" 2>/dev/null || echo "000")

    if [ "$CURL_CODE" = "200" ] && [ -s "$META_TMP" ]; then
        META_NAME=$(jq -r '.name   // ""' "$META_TMP" 2>/dev/null | tr -d '\r\n')
        META_SYM=$(jq -r  '.symbol // ""' "$META_TMP" 2>/dev/null | tr -d '\r\n')
        rm -f "$META_TMP"
        log_ok "Metadata downloaded: name='${META_NAME}' symbol='${META_SYM}'"
    else
        rm -f "$META_TMP"
        # URI not accessible → generate automatically from warp-evm-config.json
        log_warn "Metadata URI not accessible (HTTP $CURL_CODE) — generating automatically."
        META_NAME=$(evm_cfg ".terra_classic.tokens.${TOKEN_KEY}.name")
        META_SYM=$(evm_cfg  ".terra_classic.tokens.${TOKEN_KEY}.symbol")
        META_DESC=$(evm_cfg ".terra_classic.tokens.${TOKEN_KEY}.description")
        META_IMG=$(evm_cfg  ".terra_classic.tokens.${TOKEN_KEY}.image")
        [ -z "$META_NAME" ] && META_NAME="$TOKEN_NAME"
        [ -z "$META_SYM"  ] && META_SYM="$TOKEN_SYMBOL"
        [ -z "$META_DESC" ] && META_DESC="${META_NAME} via Hyperlane Warp Route (Solana)"
        [ "$META_IMG"  = "null" ] && META_IMG=""

        # Create local metadata file
        mkdir -p "$WARP_SOL_DIR"
        cat > "$LOCAL_META_FILE" <<METAJSON
{
  "name": "${META_NAME}",
  "symbol": "${META_SYM}",
  "description": "${META_DESC}",
  "image": "${META_IMG}",
  "attributes": []
}
METAJSON
        log_ok "Metadata generated: ${C}${LOCAL_META_FILE}${NC}"
        log_warn "Local file created — for on-chain metadata, commit/push this file:"
        log "    git add warp/solana/metadata-${TOKEN_KEY}.json && git push"
        log "  The on-chain URI will be: ${C}${SOL_META_URI}${NC}"
        # Use local URI if GitHub does not have it yet — deploy will work without on-chain metadata
        # but name/symbol fields are filled directly in token-config.json
    fi

    if [ -z "$META_NAME" ] || [ -z "$META_SYM" ]; then
        log_err "Could not get name/symbol for metadata!"; exit 1
    fi
    log_info "Metadata: name='${META_NAME}' symbol='${META_SYM}'"

    # Create token-config.json via jq (ensures valid JSON and "uri" only when accessible)
    TOKEN_CONFIG="$WARP_ROUTE_DIR/token-config.json"
    _BASE_JSON=$(jq -n \
        --arg net   "${NET_KEY}" \
        --arg type  "${SOL_TYPE:-synthetic}" \
        --arg name  "${META_NAME}" \
        --arg sym   "${META_SYM}" \
        --argjson dec "${SOL_TOK_DEC:-6}" \
        --arg igp   "${IGP_ACCOUNT}" \
        '{($net): {"type":$type,"name":$name,"symbol":$sym,"decimals":$dec,"totalSupply":"0","interchainGasPaymaster":$igp}}')

    # Include "uri" ONLY when the URI was successfully accessible (HTTP 200)
    # The warp-route deploy validates and fetches the URI — if it returns 404 it aborts with panic
    if [ "${CURL_CODE:-000}" = "200" ]; then
        TOKEN_CONFIG_JSON=$(echo "$_BASE_JSON" | jq \
            --arg net "${NET_KEY}" \
            --arg uri "${SOL_META_URI}" \
            '.[$net].uri = $uri')
        log_info "URI included in token-config: ${SOL_META_URI}"
    else
        TOKEN_CONFIG_JSON="$_BASE_JSON"
        log_warn "URI omitted from token-config (not accessible) — token will be deployed without on-chain metadata."
        log "    To add metadata later, commit the files in warp/solana/ and update"
        log "    warp-sealevel-config.json with the public URI, then redeploy."
    fi

    echo "$TOKEN_CONFIG_JSON" > "$TOKEN_CONFIG"
    log_ok "token-config.json created: $TOKEN_CONFIG"

    # Warning about compilation time
    log ""
    log_warn "cargo run --release can take 5-10 min on first compilation."
    log_info "Compilation in progress — please wait..."
    log ""

    # Deploy
    cd "$CLIENT_DIR"
    DEPLOY_TMP=$(mktemp)
    set +e
    cargo run --release -- \
        -k "$NET_KEYPAIR" \
        -u "$NET_RPC" \
        warp-route deploy \
        --warp-route-name "$TOKEN_KEY" \
        --environment "$NET_ENV" \
        --environments-dir "$ENVIRONMENTS_DIR" \
        --token-config-file "$TOKEN_CONFIG" \
        --built-so-dir "$BUILT_SO_DIR" \
        --registry "$REGISTRY_DIR" \
        --ata-payer-funding-amount 5000000 2>&1 \
        | grep -v "^warning:" | grep -v "^note:" \
        | tee -a "$LOG_FILE" "$DEPLOY_TMP"
    DEPLOY_EXIT=$?
    cd "$SCRIPT_DIR"
    set -e

    DEPLOY_OUT=$(cat "$DEPLOY_TMP"); rm -f "$DEPLOY_TMP"

    if [ $DEPLOY_EXIT -ne 0 ]; then
        KNOWN=$(echo "$DEPLOY_OUT" | grep -iE "already|exists|initialized" || echo "")
        if [ -z "$KNOWN" ]; then
            log_err "warp-route deploy falhou (exit $DEPLOY_EXIT)!"
            log "${Y}Verifique o log: $LOG_FILE${NC}"
            exit 1
        fi
        log_warn "warp-route deploy terminou com aviso (já inicializado?) — continuando."
    else
        log_ok "warp-route deploy completed!"
    fi

    # Extract Program ID from program-ids.json (generated by deploy)
    PROG_IDS_FILE="$WARP_ROUTE_DIR/program-ids.json"
    if [ -f "$PROG_IDS_FILE" ]; then
        WARP_PROGRAM_ID=$(jq -r ".${NET_KEY}.base58 // empty" "$PROG_IDS_FILE" 2>/dev/null || echo "")
        WARP_HEX_FROM_FILE=$(jq -r ".${NET_KEY}.hex // empty" "$PROG_IDS_FILE" 2>/dev/null | sed 's/^0x//' || echo "")
        [ -n "$WARP_HEX_FROM_FILE" ] && WARP_HEX="$WARP_HEX_FROM_FILE"
    fi

    # Fallback: read from keypair
    if [ -z "$WARP_PROGRAM_ID" ]; then
        PROGRAM_KEYPAIR="$WARP_ROUTE_DIR/keys/hyperlane_sealevel_token-${NET_KEY}-keypair.json"
        if [ -f "$PROGRAM_KEYPAIR" ]; then
            WARP_PROGRAM_ID=$(keypair_to_pubkey "$PROGRAM_KEYPAIR" 2>/dev/null || echo "")
            [ -z "$WARP_PROGRAM_ID" ] && \
                WARP_PROGRAM_ID=$(solana-keygen pubkey "$PROGRAM_KEYPAIR" 2>/dev/null || echo "")
        fi
    fi

    if [ -z "$WARP_PROGRAM_ID" ]; then
        log_err "Could not get Program ID after deploy!"
        log "  Set manually: export WARP_PROGRAM_ID='base58_program_id'"
        log "  Then run again."
        exit 1
    fi

    log_ok "Warp Program ID: ${G}${WARP_PROGRAM_ID}${NC}"
    save_state
fi

log_ok "Program ID: ${G}${WARP_PROGRAM_ID}${NC}"

# Convert Program ID → hex bytes32 (if we do not have it yet)
if [ -z "$WARP_HEX" ]; then
    WARP_HEX=$(b58_to_hex32 "$WARP_PROGRAM_ID")
    if [ -z "$WARP_HEX" ]; then
        log_err "Failed to convert Program ID to hex bytes32!"
        log "  Make sure python3 is available."
        exit 1
    fi
    save_state
fi

log_info "Program ID (hex32): 0x${WARP_HEX}"

# Auto-update warp-sealevel-config.json with program_id and program_hex
TMP_CFG=$(mktemp)
jq ".networks.\"${NET_KEY}\".warp_tokens.\"${TOKEN_KEY}\".program_id = \"${WARP_PROGRAM_ID}\" |
    .networks.\"${NET_KEY}\".warp_tokens.\"${TOKEN_KEY}\".program_hex = \"0x${WARP_HEX}\"" \
    "$SOL_CONFIG" > "$TMP_CFG" && mv "$TMP_CFG" "$SOL_CONFIG"
log_ok "${C}warp-sealevel-config.json${NC} updated with Program ID"

# ═════════════════════════════════════════════════════════════════════════════
# STEP 2 — CONFIGURE ISM
# ═════════════════════════════════════════════════════════════════════════════
log_sep "STEP 2 — CONFIGURE ISM (MultisigISM)"

if [ -n "${SKIP_ISM:-}" ]; then
    log_warn "SKIP_ISM set — skipping ISM configuration."
else
    log_info "ISM Program ID: ${ISM_PROGRAM_ID}"
    log_info "Warp Program ID: ${WARP_PROGRAM_ID}"

    cd "$CLIENT_DIR"
    ISM_TMP=$(mktemp)
    set +e
    timeout 180 cargo run --release -- \
        -k "$NET_KEYPAIR" \
        -u "$NET_RPC" \
        token set-interchain-security-module \
        --program-id "$WARP_PROGRAM_ID" \
        --ism "$ISM_PROGRAM_ID" 2>&1 \
        | grep -v "^warning:" | grep -v "^note:" | grep -v "^Compiling" \
        | tee -a "$LOG_FILE" "$ISM_TMP"
    ISM_EXIT=$?
    cd "$SCRIPT_DIR"
    ISM_OUT=$(cat "$ISM_TMP"); rm -f "$ISM_TMP"
    set -e

    if [ $ISM_EXIT -eq 0 ]; then
        log_ok "ISM configured on Warp Solana!"
    else
        KNOWN=$(echo "$ISM_OUT" | grep -iE "already|exists|same" || echo "")
        if [ -n "$KNOWN" ]; then
            log_ok "ISM was already configured (identical)."
        else
            log_warn "Error configuring ISM (exit $ISM_EXIT) — continue if already configured."
            log "  Manual: cd $CLIENT_DIR && cargo run --release -- -k $NET_KEYPAIR -u $NET_RPC token set-interchain-security-module --program-id $WARP_PROGRAM_ID --ism $ISM_PROGRAM_ID"
        fi
    fi
fi

# ═════════════════════════════════════════════════════════════════════════════
# STEP 3 — CONFIGURE IGP
# ═════════════════════════════════════════════════════════════════════════════
log_sep "STEP 3 — CONFIGURE IGP (Interchain Gas Paymaster)"

if [ -n "${SKIP_IGP:-}" ]; then
    log_warn "SKIP_IGP set — skipping IGP configuration."
else
    log_info "IGP Program ID: ${IGP_PROGRAM_ID}"
    log_info "IGP Account:    ${IGP_ACCOUNT}"

    cd "$CLIENT_DIR"
    IGP_TMP=$(mktemp)
    set +e
    timeout 180 cargo run --release -- \
        -k "$NET_KEYPAIR" \
        -u "$NET_RPC" \
        token igp \
        --program-id "$WARP_PROGRAM_ID" \
        set \
        "$IGP_PROGRAM_ID" \
        igp \
        "$IGP_ACCOUNT" 2>&1 \
        | grep -v "^warning:" | grep -v "^note:" | grep -v "^Compiling" \
        | tee -a "$LOG_FILE" "$IGP_TMP"
    IGP_EXIT=$?
    cd "$SCRIPT_DIR"
    IGP_OUT=$(cat "$IGP_TMP"); rm -f "$IGP_TMP"
    set -e

    if [ $IGP_EXIT -eq 0 ]; then
        log_ok "IGP associated with Warp Solana!"
    else
        KNOWN=$(echo "$IGP_OUT" | grep -iE "already|exists|same" || echo "")
        if [ -n "$KNOWN" ]; then
            log_ok "IGP was already associated."
        else
            log_warn "Error configuring IGP (exit $IGP_EXIT)."
            log "  Manual: cd $CLIENT_DIR && cargo run --release -- -k $NET_KEYPAIR -u $NET_RPC token igp --program-id $WARP_PROGRAM_ID set $IGP_PROGRAM_ID igp $IGP_ACCOUNT"
        fi
    fi
fi

# ═════════════════════════════════════════════════════════════════════════════
# STEP 4 — CONFIGURE DESTINATION GAS (Terra Classic)
# ═════════════════════════════════════════════════════════════════════════════
log_sep "STEP 4 — CONFIGURE DESTINATION GAS (Terra Classic domain ${TERRA_DOMAIN})"

if [ -n "${SKIP_GAS:-}" ]; then
    log_warn "SKIP_GAS set — skipping destination gas."
else
    log_info "Destination gas: ${DEST_GAS} for domain ${TERRA_DOMAIN}"
    log_warn "Without destination gas → transfers will fail with 'InvalidArgument'"

    cd "$CLIENT_DIR"
    GAS_TMP=$(mktemp)
    set +e
    timeout 180 cargo run --release -- \
        -k "$NET_KEYPAIR" \
        -u "$NET_RPC" \
        token set-destination-gas \
        --program-id "$WARP_PROGRAM_ID" \
        "$TERRA_DOMAIN" \
        "$DEST_GAS" 2>&1 \
        | grep -v "^warning:" | grep -v "^note:" | grep -v "^Compiling" \
        | tee -a "$LOG_FILE" "$GAS_TMP"
    GAS_EXIT=$?
    cd "$SCRIPT_DIR"
    GAS_OUT=$(cat "$GAS_TMP"); rm -f "$GAS_TMP"
    set -e

    if [ $GAS_EXIT -eq 0 ]; then
        log_ok "Destination Gas configured: domain=${TERRA_DOMAIN} gas=${DEST_GAS}"
    else
        KNOWN=$(echo "$GAS_OUT" | grep -iE "already|exists|same" || echo "")
        if [ -n "$KNOWN" ]; then
            log_ok "Destination gas was already configured."
        else
            log_warn "Error configuring destination gas (exit $GAS_EXIT)."
            log "  Manual: cd $CLIENT_DIR && cargo run --release -- -k $NET_KEYPAIR -u $NET_RPC token set-destination-gas --program-id $WARP_PROGRAM_ID $TERRA_DOMAIN $DEST_GAS"
        fi
    fi
fi

# ═════════════════════════════════════════════════════════════════════════════
# STEP 5 — ENROLL REMOTE ROUTER (Solana → Terra Classic)
# ═════════════════════════════════════════════════════════════════════════════
log_sep "STEP 5 — ENROLL REMOTE ROUTER (Solana → Terra Classic)"

if [ -n "${SKIP_ENROLL:-}" ]; then
    log_warn "SKIP_ENROLL set — skipping enroll remote router."
elif [ -z "$TERRA_WARP_ADDR" ] || [ "$TERRA_WARP_ADDR" = "null" ]; then
    log_warn "Terra Classic Warp not deployed — skipping enroll remote router."
else
    TERRA_HEX_CLEAN="${TERRA_WARP_HEX#0x}"
    log_info "Enrolling Terra Classic Warp on Solana..."
    log "  Terra Classic domain: ${TERRA_DOMAIN}"
    log "  Terra Classic Warp (hex): 0x${TERRA_HEX_CLEAN}"

    cd "$CLIENT_DIR"
    ENROLL_TMP=$(mktemp)
    set +e
    timeout 180 cargo run --release -- \
        -k "$NET_KEYPAIR" \
        -u "$NET_RPC" \
        token enroll-remote-router \
        --program-id "$WARP_PROGRAM_ID" \
        "$TERRA_DOMAIN" \
        "0x${TERRA_HEX_CLEAN}" 2>&1 \
        | grep -v "^warning:" | grep -v "^note:" | grep -v "^Compiling" \
        | tee -a "$LOG_FILE" "$ENROLL_TMP"
    ENROLL_EXIT=$?
    cd "$SCRIPT_DIR"
    ENROLL_OUT=$(cat "$ENROLL_TMP"); rm -f "$ENROLL_TMP"
    set -e

    if [ $ENROLL_EXIT -eq 0 ]; then
        log_ok "Remote Router enrolled! Solana now knows Terra Classic (domain ${TERRA_DOMAIN})"
    else
        KNOWN=$(echo "$ENROLL_OUT" | grep -iE "already|exists" || echo "")
        if [ -n "$KNOWN" ]; then
            log_ok "Remote Router was already enrolled."
        else
            log_warn "Error enrolling Remote Router (exit $ENROLL_EXIT)."
            log "  Manual: cd $CLIENT_DIR && cargo run --release -- -k $NET_KEYPAIR -u $NET_RPC token enroll-remote-router --program-id $WARP_PROGRAM_ID $TERRA_DOMAIN 0x${TERRA_HEX_CLEAN}"
        fi
    fi
fi

# ═════════════════════════════════════════════════════════════════════════════
# STEP 6 — SET ROUTE ON TERRA CLASSIC (Terra Classic → Solana)
# ═════════════════════════════════════════════════════════════════════════════
log_sep "STEP 6 — SET ROUTE ON TERRA CLASSIC (Terra Classic → Solana)"

if [ -n "${SKIP_TC_ROUTE:-}" ]; then
    log_warn "SKIP_TC_ROUTE set — skipping Terra Classic set_route."
elif [ -z "$TERRA_WARP_ADDR" ] || [ "$TERRA_WARP_ADDR" = "null" ]; then
    log_warn "Terra Classic Warp not deployed — skipping set_route."
elif [ -z "${TERRA_PRIVATE_KEY:-}" ]; then
    log_warn "TERRA_PRIVATE_KEY not set — skipping Terra Classic set_route."
    log "  Run: export TERRA_PRIVATE_KEY='hex_key'"
    log "  Then re-run with: export WARP_PROGRAM_ID='${WARP_PROGRAM_ID}'"
    log "  And: export SKIP_ENROLL=1 (if already enrolled)"
else
    TERRA_PRIV_CLEAN="${TERRA_PRIVATE_KEY#0x}"
    log_info "Terra Classic Warp: ${TERRA_WARP_ADDR}"
    log_info "Solana Domain: ${NET_DOMAIN}"
    log_info "Solana Route (hex32): ${WARP_HEX}"

    # Write Node.js script to temp file
    _NODE_TMP=$(mktemp /tmp/set-route-sol-XXXXXX.js)
    cat > "$_NODE_TMP" <<'NODEJS_SCRIPT'
const path = require('path');
const nm   = path.join(process.env._NM_ROOT, 'node_modules');
const { SigningCosmWasmClient } = require(path.join(nm, '@cosmjs/cosmwasm-stargate'));
const { DirectSecp256k1Wallet } = require(path.join(nm, '@cosmjs/proto-signing'));
const { GasPrice }              = require(path.join(nm, '@cosmjs/stargate'));
const { fromHex }               = require(path.join(nm, '@cosmjs/encoding'));

async function main() {
    const privKey  = process.env._NM_PRIV;
    const rpc      = process.env._NM_RPC;
    const warpAddr = process.env._NM_WARP;
    const solHex   = process.env._NM_SOL_HEX;   // hex32 sem 0x
    const domain   = parseInt(process.env._NM_DOMAIN, 10);

    const wallet = await DirectSecp256k1Wallet.fromKey(fromHex(privKey), 'terra');
    const [account] = await wallet.getAccounts();
    const client = await SigningCosmWasmClient.connectWithSigner(
        rpc, wallet,
        { gasPrice: GasPrice.fromString('0.015uluna') }
    );

    // Verificar se a rota já existe E aponta para o Program ID correto
    try {
        const routes = await client.queryContractSmart(warpAddr, {
            router: { list_routes: {} }
        });
        const ex = (routes.routes || []).find(r => r.domain === domain);
        if (ex && ex.route) {
            // Normalize both values (remove 0x and lowercase) to compare
            const existingNorm = ex.route.replace(/^0x/i, '').toLowerCase();
            const expectedNorm = solHex.replace(/^0x/i, '').toLowerCase();
            if (existingNorm === expectedNorm) {
                console.log('STATUS=already_set');
                console.log('EXISTING=' + ex.route);
                return;
            }
            // Route exists but points to different Program ID — update
            console.error('WARN: existing route (' + ex.route + ') differs from expected (' + solHex + ') — updating...');
        }
    } catch(e) { /* rota ainda não existe, continuar */ }

    const result = await client.execute(
        account.address, warpAddr,
        { router: { set_route: { set: { domain: domain, route: solHex.replace(/^0x/i, '') } } } },
        'auto',
        'set_route Terra Classic → Solana via create-warp-sealevel.sh'
    );
    console.log('STATUS=ok');
    console.log('TX=' + result.transactionHash);
    console.log('HEIGHT=' + result.height);
}
main().catch(e => { console.log('STATUS=error'); console.log('ERR=' + e.message); process.exit(0); });
NODEJS_SCRIPT

    SR_RESULT=""
    set +e
    SR_RESULT=$(
        _NM_ROOT="$PROJECT_ROOT" \
        _NM_PRIV="$TERRA_PRIV_CLEAN" \
        _NM_RPC="$TERRA_RPC" \
        _NM_WARP="$TERRA_WARP_ADDR" \
        _NM_SOL_HEX="$WARP_HEX" \
        _NM_DOMAIN="$NET_DOMAIN" \
        node --no-warnings "$_NODE_TMP" 2>&1
    )
    _NODE_EXIT=$?
    set -e
    rm -f "$_NODE_TMP"

    if [ $_NODE_EXIT -ne 0 ] && ! echo "$SR_RESULT" | grep -q "^STATUS="; then
        SR_STATUS="error"
        SR_ERR="node exited with code $_NODE_EXIT: $(echo "$SR_RESULT" | tail -3)"
    else
        SR_STATUS=$(echo "$SR_RESULT" | grep "^STATUS=" | cut -d= -f2  || echo "")
        SR_TX=$(echo    "$SR_RESULT"  | grep "^TX="     | cut -d= -f2   || echo "")
        SR_ERR=$(echo   "$SR_RESULT"  | grep "^ERR="    | cut -d= -f2-  || echo "")
    fi

    case "$SR_STATUS" in
        ok)
            log_ok "set_route executed! Terra Classic now knows the Solana Warp."
            log "   TX: ${B}https://finder.hexxagon.io/${TERRA_CHAIN_ID}/tx/${SR_TX}${NC}"
            ;;
        already_set)
            EXISTING_ROUTE=$(echo "$SR_RESULT" | grep "^EXISTING=" | cut -d= -f2 || echo "")
            log_ok "Route already configured on Terra Classic (${EXISTING_ROUTE:-already set})."
            ;;
        error)
            log_warn "Terra Classic set_route failed: ${SR_ERR}"
            log "  Output: $(echo "$SR_RESULT" | grep -v "^STATUS=" | head -5)"
            log "  Run manually:"
            log "  terrad tx wasm execute \"${TERRA_WARP_ADDR}\" \\"
            log "    '{\"router\":{\"set_route\":{\"set\":{\"domain\":${NET_DOMAIN},\"route\":\"${WARP_HEX}\"}}}}' \\"
            log "    --from <KEY> --keyring-backend file --chain-id ${TERRA_CHAIN_ID} --node ${TERRA_RPC} --gas auto --gas-adjustment 1.5 --fees 12000000uluna --yes"
            ;;
        *)
            log_warn "Terra Classic set_route: unexpected result (exit=$_NODE_EXIT)."
            [ -n "$SR_RESULT" ] && log "  Output: $(echo "$SR_RESULT" | head -5)"
            ;;
    esac
fi

# ═════════════════════════════════════════════════════════════════════════════
# STEP 7 — EXTRACT MINT ADDRESS + TRANSFER OWNERSHIP
# ═════════════════════════════════════════════════════════════════════════════
log_sep "STEP 7 — QUERY WARP (Mint Address + Verification)"

cd "$CLIENT_DIR"
QUERY_TMP=$(mktemp)
set +e
timeout 120 cargo run --release --quiet -- \
    -k "$NET_KEYPAIR" \
    -u "$NET_RPC" \
    token query \
    --program-id "$WARP_PROGRAM_ID" \
    synthetic 2>&1 \
    | grep -v "^warning:" | grep -v "^note:" \
    | tee -a "$LOG_FILE" "$QUERY_TMP"
QUERY_EXIT=$?
cd "$SCRIPT_DIR"
QUERY_OUT=$(cat "$QUERY_TMP"); rm -f "$QUERY_TMP"
set -e

if [ $QUERY_EXIT -eq 0 ] && [ -n "$QUERY_OUT" ]; then
    NEW_MINT=$(echo "$QUERY_OUT" | grep -iE "mint" | grep -oE "[1-9A-HJ-NP-Za-km-z]{32,44}" | head -1 || echo "")
    if [ -n "$NEW_MINT" ]; then
        MINT_ADDRESS="$NEW_MINT"
        log_ok "Mint Address: ${G}${MINT_ADDRESS}${NC}"
        # Auto-atualizar config
        TMP_CFG=$(mktemp)
        jq ".networks.\"${NET_KEY}\".warp_tokens.\"${TOKEN_KEY}\".mint_address = \"${MINT_ADDRESS}\" |
            .networks.\"${NET_KEY}\".warp_tokens.\"${TOKEN_KEY}\".deployed = true" \
            "$SOL_CONFIG" > "$TMP_CFG" && mv "$TMP_CFG" "$SOL_CONFIG"
        log_ok "${C}warp-sealevel-config.json${NC} updated with mint_address and deployed=true"
        save_state
    else
        log_warn "Mint Address not found in query — the token may not be initialized yet."
    fi
fi

# Transfer ownership (if owner configured and different from keypair)
if [ -n "$SOL_OWNER" ] && [ "$SOL_OWNER" != "null" ]; then
    log_info "Transferring ownership to: $SOL_OWNER"
    cd "$CLIENT_DIR"
    set +e
    timeout 120 cargo run --release -- \
        -k "$NET_KEYPAIR" \
        -u "$NET_RPC" \
        token transfer-ownership \
        --program-id "$WARP_PROGRAM_ID" \
        "$SOL_OWNER" 2>&1 \
        | grep -v "^warning:" | grep -v "^note:" | grep -v "^Compiling" \
        | tee -a "$LOG_FILE"
    OWN_EXIT=$?
    cd "$SCRIPT_DIR"
    set -e
    if [ $OWN_EXIT -eq 0 ]; then
        log_ok "Ownership transferred to: $SOL_OWNER"
    else
        log_warn "Error transferring ownership (exit $OWN_EXIT) — may already be correct."
        log "  Manual: cd $CLIENT_DIR && cargo run --release -- -k $NET_KEYPAIR -u $NET_RPC token transfer-ownership --program-id $WARP_PROGRAM_ID $SOL_OWNER"
    fi
fi

# ═════════════════════════════════════════════════════════════════════════════
# STEP 8 — FINAL VERIFICATION
# ═════════════════════════════════════════════════════════════════════════════
log_sep "STEP 8 — FINAL VERIFICATION"

# 1. Check remote routers on Solana
log_info "Checking remote routers on Warp Solana..."
cd "$CLIENT_DIR"
set +e
VER_SOL=$(timeout 60 cargo run --release --quiet -- \
    -k "$NET_KEYPAIR" \
    -u "$NET_RPC" \
    token query \
    --program-id "$WARP_PROGRAM_ID" \
    synthetic 2>&1 \
    | grep -v "^warning:" | grep -v "^note:" \
    | grep -iE "remote_router|ism|igp|destination_gas" | head -10 || echo "")
set -e
cd "$SCRIPT_DIR"

if [ -n "$VER_SOL" ]; then
    log_ok "Warp Solana state:"
    echo "$VER_SOL" | while IFS= read -r line; do log "    $line"; done
else
    log_warn "No verification info returned."
fi

# 2. Check route on Terra Classic
if [ -n "$TERRA_WARP_ADDR" ] && [ "$TERRA_WARP_ADDR" != "null" ]; then
    log_info "Checking route on Terra Classic (domain ${NET_DOMAIN})..."
    set +e
    TC_ROUTE=$(terrad query wasm contract-state smart "$TERRA_WARP_ADDR" \
        "{\"router\":{\"get_route\":{\"domain\":${NET_DOMAIN}}}}" \
        --node "$TERRA_RPC" 2>&1 | grep -A3 "route" | head -5 || echo "N/A")
    set -e
    log "    Terra Classic route: ${TC_ROUTE}"
fi

# ─────────────────────────────────────────────────────────────────────────────
# GENERATE INFO FILE
# ─────────────────────────────────────────────────────────────────────────────
TOKEN_UPPER=$(echo "$TOKEN_KEY" | tr '[:lower:]' '[:upper:]')
NET_UPPER=$(echo "$NET_KEY" | tr '[:lower:]' '[:upper:]')
INFO_FILE="$LOG_DIR/WARP-${NET_UPPER}-${TOKEN_UPPER}.txt"

cat > "$INFO_FILE" <<EOF
═══════════════════════════════════════════════════════════
  WARP SOLANA: ${TOKEN_KEY^^} on ${NET_DISPLAY}
  Generated: $(date '+%Y-%m-%d %H:%M:%S')
═══════════════════════════════════════════════════════════

[WARP SOLANA]
Network:            ${NET_DISPLAY} (domain: ${NET_DOMAIN})
Token Key:          ${TOKEN_KEY}
Token Name:         ${TOKEN_NAME} (${TOKEN_SYMBOL})
Token Type:         ${SOL_TYPE:-synthetic}
Program ID (Base58):${WARP_PROGRAM_ID}
Program ID (Hex32): 0x${WARP_HEX}
Mint Address:       ${MINT_ADDRESS:-N/A}
ISM Program:        ${ISM_PROGRAM_ID}
IGP Program:        ${IGP_PROGRAM_ID}
IGP Account:        ${IGP_ACCOUNT}
Dest Gas (Terra):   ${DEST_GAS}
Owner:              ${SOL_OWNER:-keypair}
RPC:                ${NET_RPC}
Explorer:           ${NET_EXPLORER}

[WARP TERRA CLASSIC]
Address (Bech32):   ${TERRA_WARP_ADDR:-N/A}
Address (Hex):      ${TERRA_WARP_HEX:-N/A}
Domain:             ${TERRA_DOMAIN}
Chain ID:           ${TERRA_CHAIN_ID}

[CONFIGURED LINKS]
Solana → Terra Classic:  enroll-remote-router (domain ${TERRA_DOMAIN})
Terra Classic → Solana:  set_route (domain ${NET_DOMAIN})

[MANUAL VERIFICATION COMMANDS]
# Check Warp Solana:
cd ${CLIENT_DIR}
cargo run --release -- -k ${NET_KEYPAIR} -u ${NET_RPC} token query --program-id ${WARP_PROGRAM_ID} synthetic

# Check Terra Classic route:
terrad query wasm contract-state smart ${TERRA_WARP_ADDR:-TC_WARP_ADDR} '{"router":{"get_route":{"domain":${NET_DOMAIN}}}}' --node ${TERRA_RPC}

# Check ISM:
cargo run --release -- -k ${NET_KEYPAIR} -u ${NET_RPC} multisig-ism-message-id query --program-id ${ISM_PROGRAM_ID} --domains ${TERRA_DOMAIN}
EOF

log_ok "Info saved at: ${C}${INFO_FILE}${NC}"

# ─────────────────────────────────────────────────────────────────────────────
# FINAL SUMMARY
# ─────────────────────────────────────────────────────────────────────────────
log ""
log "╔══════════════════════════════════════════════════════════════════════════╗"
log "║               ✅  WARP SOLANA CONFIGURED SUCCESSFULLY!                  ║"
log "╚══════════════════════════════════════════════════════════════════════════╝"
log ""
log "${G}📝 Warp Solana:${NC}"
log "   Token:       ${TOKEN_NAME} (${TOKEN_SYMBOL})"
log "   Program ID:  ${G}${WARP_PROGRAM_ID}${NC}"
log "   Hex32:       ${G}0x${WARP_HEX}${NC}"
[ -n "${MINT_ADDRESS:-}" ] && log "   Mint:        ${G}${MINT_ADDRESS}${NC}"
log "   ISM:         ${ISM_PROGRAM_ID}"
log "   IGP Account: ${IGP_ACCOUNT}"
log "   Dest Gas:    ${DEST_GAS} (Terra Classic domain ${TERRA_DOMAIN})"
log ""
log "${G}📝 Warp Terra Classic:${NC}"
log "   Address: ${TERRA_WARP_ADDR:-N/A}"
log "   Domain:  ${TERRA_DOMAIN}"
log ""
log "${G}📝 Links:${NC}"
if [ -z "${SKIP_ENROLL:-}" ]; then
    log "   ✅ Solana → Terra Classic (domain ${TERRA_DOMAIN})"
else
    log "   ⚠️  Solana → Terra Classic: pending"
fi
if [ -z "${SKIP_TC_ROUTE:-}" ] && [ -n "${TERRA_PRIVATE_KEY:-}" ]; then
    log "   ✅ Terra Classic → Solana (domain ${NET_DOMAIN})"
else
    log "   ⚠️  Terra Classic → Solana: pending"
fi
log ""
log "${C}  Automatic updates in warp-sealevel-config.json:${NC}"
log "    .networks.${NET_KEY}.warp_tokens.${TOKEN_KEY}.program_id  = \"${WARP_PROGRAM_ID}\""
log "    .networks.${NET_KEY}.warp_tokens.${TOKEN_KEY}.program_hex = \"0x${WARP_HEX}\""
[ -n "${MINT_ADDRESS:-}" ] && log "    .networks.${NET_KEY}.warp_tokens.${TOKEN_KEY}.mint_address = \"${MINT_ADDRESS}\""
log "    .networks.${NET_KEY}.warp_tokens.${TOKEN_KEY}.deployed    = true"
log ""
log "${B}📄 Detalhes: ${INFO_FILE}${NC}"
log "${B}📋 Log:      ${LOG_FILE}${NC}"
log ""
