#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
#  🚀 DEPLOY WARP ROUTE SOLANA (SEALEVEL) ↔ TERRA CLASSIC — HYPERLANE
#     Buffer-reuse strategy (no BPF recompilation required)
# ═══════════════════════════════════════════════════════════════════════════════
#
#  Strategy: "local build + separate deploy" (community-verifiable)
#
#  How it works:
#    1. Compiles the .so binary locally from source via `cargo build-sbf`
#       (reproducible → the community can verify the SHA-256, no blind trust in
#        a third-party program). The hash is printed and saved as <file>.sha256.
#       Only this locally-built binary is ever deployed — there is NO fallback
#       to any pre-existing on-chain program's bytecode.
#    2. Uploads the binary to chain via `solana program deploy` (direct)
#    3. Calls jito-warp-init.js → MEV-safe init (single atomic transaction)
#       → creates token storage + mint PDA atomically (no MEV window)
#    4. Configures ISM, IGP, destination gas, enroll-remote-router, set_route
#
#  Benefits:
#    ✅ Binary compiled from source → publishable SHA-256 the community can audit
#    ✅ No trust required in an external mainnet program (no dump, no fallback)
#    ✅ Buffer is reused on retries (partial deploy failure = pay only once)
#    ✅ MEV-safe mint initialization via single atomic transaction
#    ⚠️  SOL cost for binary upload (~2-5 SOL) is unavoidable per program
#    ⚠️  First local build takes ~15-20 min (BPF compilation); cached afterwards
#
#  Binary source is chosen by BINARY_SOURCE (default: build):
#    build  → compile locally from source            (recommended, verifiable)
#    local  → reuse an already-compiled target/deploy/*.so (built by you)
#
#  Pinned toolchain + reference SHA-256 for community verification:
#    doc/WARP-SOLANA-BINARY-REFERENCE.md
#
#  Usage:
#    export TERRA_PRIVATE_KEY="your_hex_private_key"
#    ./deploy-warp-solana-buffer.sh
#
#  Optional environment variables:
#    BINARY_SOURCE=build|local  → how to obtain the .so (default: build)
#    WARP_PROGRAM_ID=<base58>    → skip deploy (program already exists)
#    SKIP_INIT=1                 → skip token init (jito-warp-init.js)
#    SKIP_ISM=1                  → skip ISM configuration
#    SKIP_IGP=1                  → skip IGP configuration
#    SKIP_GAS=1                  → skip destination gas configuration
#    SKIP_ENROLL=1               → skip enroll-remote-router (Solana → TC)
#    SKIP_TC_ROUTE=1             → skip set_route (TC → Solana)
#    JITO_TIP_LAMPORTS=<n>       → override priority tip (default: 5000000)
#
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

# Ensure the Solana toolchain (solana, solana-keygen, cargo-build-sbf) is on PATH.
# A terminal opened before the install — or a non-login shell — may miss it.
_SOLANA_BIN="$HOME/.local/share/solana/install/active_release/bin"
[ -d "$_SOLANA_BIN" ] && case ":$PATH:" in *":$_SOLANA_BIN:"*) ;; *) export PATH="$_SOLANA_BIN:$PATH" ;; esac

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
EVM_CONFIG="$SCRIPT_DIR/warp-evm-config.json"
SOL_CONFIG="$SCRIPT_DIR/warp-sealevel-config.json"
LOG_DIR="$SCRIPT_DIR/log"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/deploy-warp-solana-buffer.log"
STATE_FILE="$SCRIPT_DIR/.warp-solana-buffer-state.json"

# Auto-detect PROJECT_ROOT (looks for package.json going up the directory tree)
PROJECT_ROOT="$SCRIPT_DIR"
while [ ! -f "$PROJECT_ROOT/package.json" ] && [ "$PROJECT_ROOT" != "/" ]; do
    PROJECT_ROOT="$(dirname "$PROJECT_ROOT")"
done
if [ ! -f "$PROJECT_ROOT/package.json" ]; then
    echo "❌ Project root (package.json) not found!"; exit 1
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

# Converts a base58 Solana pubkey to a 32-byte hex string (no 0x prefix)
b58_to_hex32() {
    python3 - "$1" <<'PY' 2>/dev/null
import sys
def b58decode(s):
    alpha='123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz'
    n=0
    for c in s:
        if c not in alpha: raise ValueError(c)
        n=n*58+alpha.index(c)
    r=[]
    while n>0: r.append(n&0xFF); n>>=8
    r.reverse()
    for c in s:
        if c=='1': r.insert(0,0)
        else: break
    return bytes(r)
try: print(b58decode(sys.argv[1]).hex().zfill(64))
except: sys.exit(1)
PY
}

# Extracts the public key (base58) from a Solana keypair JSON file
keypair_to_pubkey() {
    python3 - "$1" <<'PY' 2>/dev/null
import json,sys
try:
    data=json.load(open(sys.argv[1]))
    pub=bytes(data[32:64]) if isinstance(data,list) and len(data)>=64 else sys.exit(1)
    alpha='123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz'
    n=int.from_bytes(pub,'big'); r=''
    while n>0: r=alpha[n%58]+r; n//=58
    for b in pub:
        if b==0: r='1'+r
        else: break
    print(r)
except: sys.exit(1)
PY
}

# Saves current deploy state to the state file for resume support
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

# Loads previously saved state from the state file
load_state() {
    [ -f "$STATE_FILE" ] || return 0
    _ST_NET=$(jq -r '.network    // ""' "$STATE_FILE" 2>/dev/null || echo "")
    _ST_TOK=$(jq -r '.token      // ""' "$STATE_FILE" 2>/dev/null || echo "")
    _ST_PID=$(jq -r '.program_id // ""' "$STATE_FILE" 2>/dev/null || echo "")
    _ST_HEX=$(jq -r '.program_hex// ""' "$STATE_FILE" 2>/dev/null || echo "")
    _ST_MINT=$(jq -r '.mint      // ""' "$STATE_FILE" 2>/dev/null || echo "")
    [ -n "$_ST_TOK" ] && log_warn "Previous state found: token=${_ST_TOK} net=${_ST_NET:-—} program=${_ST_PID:-—}"
    log "   To reset: ${Y}rm -f $STATE_FILE${NC}"
}

# Applies saved state only if token + network match the current selection
apply_state() {
    [ -z "${_ST_TOK:-}" ] && return 0
    if [ "${_ST_TOK}" = "${TOKEN_KEY}" ] && [ "${_ST_NET}" = "${NET_KEY}" ]; then
        [ -z "${WARP_PROGRAM_ID:-}" ] && [ -n "${_ST_PID:-}" ] && export WARP_PROGRAM_ID="$_ST_PID"
        [ -z "${WARP_HEX:-}"        ] && [ -n "${_ST_HEX:-}" ] && export WARP_HEX="$_ST_HEX"
        [ -z "${MINT_ADDRESS:-}"    ] && [ -n "${_ST_MINT:-}" ] && export MINT_ADDRESS="$_ST_MINT"
        [ -n "${WARP_PROGRAM_ID:-}" ] && log_info "State restored: program=${WARP_PROGRAM_ID}"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# BANNER
# ─────────────────────────────────────────────────────────────────────────────
> "$LOG_FILE"
clear 2>/dev/null || true
log "╔══════════════════════════════════════════════════════════════════════════╗"
log "║  🚀  DEPLOY WARP ROUTE SOLANA ↔ TERRA CLASSIC — HYPERLANE              ║"
log "║  Date: $(date '+%Y-%m-%d %H:%M:%S')                                         ║"
log "╚══════════════════════════════════════════════════════════════════════════╝"

# ─────────────────────────────────────────────────────────────────────────────
# INITIAL CHECKS
# ─────────────────────────────────────────────────────────────────────────────
for f in "$EVM_CONFIG" "$SOL_CONFIG"; do
    [ -f "$f" ] || { log_err "File not found: $f"; exit 1; }
    jq empty "$f" 2>/dev/null || { log_err "Invalid JSON: $f"; exit 1; }
done
command -v jq      &>/dev/null || { log_err "jq is required"; exit 1; }
command -v python3 &>/dev/null || { log_err "python3 is required"; exit 1; }
command -v node    &>/dev/null || { log_err "node is required"; exit 1; }
command -v solana  &>/dev/null || { log_err "solana-cli is required"; exit 1; }
command -v cargo   &>/dev/null || { log_err "cargo (Rust) is required"; exit 1; }

# Which warp-evm-config.json block to read Terra Classic data from:
#   .terra_classic          → mainnet (columbus-5)   [default]
#   .terra_classic_testnet  → testnet (rebel-2)       [set by the testnet launcher]
TERRA_CFG="${TERRA_CFG:-.terra_classic}"

# Terra Classic vars: explicit env overrides (testnet launcher passes rebel-2 /
# domain 1325 / luncblaze rpc) win over the config block above.
TERRA_DOMAIN="${TERRA_DOMAIN:-$(evm_cfg "${TERRA_CFG}.domain")}"
TERRA_RPC="${TERRA_RPC:-$(evm_cfg "${TERRA_CFG}.rpc")}"
TERRA_CHAIN_ID="${TERRA_CHAIN_ID:-$(evm_cfg "${TERRA_CFG}.chain_id")}"
log_ok "Terra Classic [${TERRA_CFG}]: domain=${TERRA_DOMAIN}, rpc=${TERRA_RPC}"

load_state

# ═════════════════════════════════════════════════════════════════════════════
# MENU 1 — SELECT TOKEN
# ═════════════════════════════════════════════════════════════════════════════
log_sep "TOKEN SELECTION"
mapfile -t TOKEN_KEYS < <(jq -r "${TERRA_CFG}.tokens | keys[]" "$EVM_CONFIG" 2>/dev/null)
declare -a TOKEN_MENU=()
i=1
for TK in "${TOKEN_KEYS[@]}"; do
    TK_NAME=$(evm_cfg "${TERRA_CFG}.tokens.${TK}.name")
    TK_SYM=$(evm_cfg  "${TERRA_CFG}.tokens.${TK}.symbol")
    TK_DEP=$(evm_cfg  "${TERRA_CFG}.tokens.${TK}.terra_warp.deployed")
    TOKEN_MENU+=("$TK")
    [ "$TK_DEP" = "true" ] && TAG="${G}[TC ok]${NC}" || TAG="${Y}[TC pending]${NC}"
    log "  [${W}$i${NC}]  ${C}${TK}${NC} — ${TK_NAME:-N/A} (${TK_SYM:-?}) ${TAG}"
    i=$((i+1))
done
# Non-interactive token selection: if TOKEN_KEY is preset (e.g. by a launcher)
# and matches a token, skip the menu.
SEL_TOK=""
if [ -n "${TOKEN_KEY:-}" ]; then
    for idx in "${!TOKEN_MENU[@]}"; do
        [ "${TOKEN_MENU[$idx]}" = "$TOKEN_KEY" ] && SEL_TOK=$((idx+1))
    done
    [ -n "$SEL_TOK" ] && log_info "Token preset via TOKEN_KEY=${TOKEN_KEY} (menu skipped)"
fi
if [ -z "$SEL_TOK" ]; then
    echo -ne "  ${W}Token [1-${#TOKEN_MENU[@]}]: ${NC}"; read -r SEL_TOK 2>/dev/null || SEL_TOK="1"
    SEL_TOK="${SEL_TOK:-1}"
fi
[[ "$SEL_TOK" =~ ^[0-9]+$ ]] && [ "$SEL_TOK" -ge 1 ] && [ "$SEL_TOK" -le "${#TOKEN_MENU[@]}" ] \
    || { log_err "Invalid selection"; exit 1; }
TOKEN_KEY="${TOKEN_MENU[$((SEL_TOK-1))]}"
TK_TC="${TERRA_CFG}.tokens.${TOKEN_KEY}"
TOKEN_NAME=$(evm_cfg    "${TK_TC}.name")
TOKEN_SYMBOL=$(evm_cfg  "${TK_TC}.symbol")
TOKEN_DEC=$(evm_cfg     "${TK_TC}.decimals")
TERRA_WARP_ADDR=$(evm_cfg "${TK_TC}.terra_warp.warp_address")
TERRA_WARP_HEX=$(evm_cfg  "${TK_TC}.terra_warp.warp_hexed")
TERRA_WARP_DEPLOYED=$(evm_cfg "${TK_TC}.terra_warp.deployed")
log_ok "Token: ${C}${TOKEN_KEY}${NC} — ${TOKEN_NAME} (${TOKEN_SYMBOL})"

# ═════════════════════════════════════════════════════════════════════════════
# MENU 2 — SELECT SOLANA NETWORK
# ═════════════════════════════════════════════════════════════════════════════
log_sep "SOLANA NETWORK SELECTION"
mapfile -t NET_KEYS < <(jq -r '.networks | to_entries[] | select(.value.enabled==true) | .key' "$SOL_CONFIG" 2>/dev/null)
declare -a NET_MENU=()
i=1
for NK in "${NET_KEYS[@]}"; do
    ND=$(sol_cfg ".networks.${NK}.display_name")
    DOM=$(sol_cfg ".networks.${NK}.domain")
    SOL_WD=$(sol_cfg ".networks.${NK}.warp_tokens.${TOKEN_KEY}.deployed" 2>/dev/null || echo "false")
    SOL_WA=$(sol_cfg ".networks.${NK}.warp_tokens.${TOKEN_KEY}.program_id" 2>/dev/null || echo "")
    NET_MENU+=("$NK")
    [ "$SOL_WD" = "true" ] && [ -n "$SOL_WA" ] && TAG="${G}[already deployed]${NC}" || TAG="${B}[new]${NC}"
    log "  [${W}$i${NC}]  ${C}${NK}${NC} — ${ND} (domain: ${DOM}) ${TAG}"
    [ -n "$SOL_WA" ] && [ "$SOL_WA" != "null" ] && log "         Program ID: ${G}${SOL_WA}${NC}"
    i=$((i+1))
done
[ ${#NET_MENU[@]} -eq 0 ] && { log_err "No Solana network enabled!"; exit 1; }
# Non-interactive network selection: if NET_KEY is preset (e.g. by the testnet
# launcher) and matches an enabled network, skip the menu.
SEL_NET=""
if [ -n "${NET_KEY:-}" ]; then
    for idx in "${!NET_MENU[@]}"; do
        [ "${NET_MENU[$idx]}" = "$NET_KEY" ] && SEL_NET=$((idx+1))
    done
    [ -n "$SEL_NET" ] && log_info "Network preset via NET_KEY=${NET_KEY} (menu skipped)"
fi
if [ -z "$SEL_NET" ]; then
    echo -ne "  ${W}Network [1-${#NET_MENU[@]}]: ${NC}"; read -r SEL_NET 2>/dev/null || SEL_NET="1"
    SEL_NET="${SEL_NET:-1}"
fi
[[ "$SEL_NET" =~ ^[0-9]+$ ]] && [ "$SEL_NET" -ge 1 ] && [ "$SEL_NET" -le "${#NET_MENU[@]}" ] \
    || { log_err "Invalid selection"; exit 1; }
NET_KEY="${NET_MENU[$((SEL_NET-1))]}"
N=".networks.${NET_KEY}"

NET_DISPLAY=$(sol_cfg "${N}.display_name")
NET_ENV=$(sol_cfg     "${N}.environment")
NET_DOMAIN=$(sol_cfg  "${N}.domain")
NET_RPC="${NET_RPC:-$(sol_cfg "${N}.rpc")}"   # env override wins over config (better RPC for congested nodes)
NET_EXPLORER=$(sol_cfg "${N}.explorer")
NET_KEYPAIR=$(sol_cfg "${N}.keypair" | sed "s|^~|$HOME|")
NET_MONOREPO=$(sol_cfg "${N}.monorepo_dir" | sed "s|^~|$HOME|")
MAILBOX=$(sol_cfg     "${N}.mailbox" 2>/dev/null || echo "")
ISM_PROGRAM_ID=$(sol_cfg "${N}.ism.program_id")
IGP_PROGRAM_ID=$(sol_cfg "${N}.igp.program_id")
IGP_ACCOUNT=$(sol_cfg    "${N}.igp.account")
# ⚠️ TIPO da conta IGP ('overhead-igp' | 'igp') — DEVE casar com a conta gravada no config.
#    BUG HISTÓRICO (2026-07-09): tipo hardcoded 'igp' com a conta OVERHEAD → PayForGas quebrava
#    (BorshIoError) e a VOLTA sealevel→TC nunca funcionou. Nosso deploy grava a OVERHEAD → default overhead-igp.
IGP_ACCOUNT_TYPE=$(sol_cfg "${N}.igp.account_type" 2>/dev/null || echo "")
{ [ -z "$IGP_ACCOUNT_TYPE" ] || [ "$IGP_ACCOUNT_TYPE" = "null" ]; } && IGP_ACCOUNT_TYPE="overhead-igp"
DEST_GAS=$(sol_cfg       "${N}.igp.destination_gas_terra")
SOL_PID_CFG=$(sol_cfg    "${N}.warp_tokens.${TOKEN_KEY}.program_id")
SOL_HEX_CFG=$(sol_cfg    "${N}.warp_tokens.${TOKEN_KEY}.program_hex")
SOL_MINT_CFG=$(sol_cfg   "${N}.warp_tokens.${TOKEN_KEY}.mint_address")
SOL_META_URI=$(sol_cfg   "${N}.warp_tokens.${TOKEN_KEY}.metadata_uri")
SOL_TOK_DEC=$(sol_cfg    "${N}.warp_tokens.${TOKEN_KEY}.decimals")
SOL_OWNER=$(sol_cfg      "${N}.warp_tokens.${TOKEN_KEY}.owner")
SOL_TYPE=$(sol_cfg       "${N}.warp_tokens.${TOKEN_KEY}.type")

# Resolve mailbox address from environment config files if not in warp config
if [ -z "$MAILBOX" ] || [ "$MAILBOX" = "null" ]; then
    MAILBOX_JSON="$NET_MONOREPO/environments/${NET_ENV}/solanamainnet/core/program-ids.json"
    [ -f "$MAILBOX_JSON" ] && MAILBOX=$(jq -r '.mailbox // ""' "$MAILBOX_JSON" 2>/dev/null || echo "")
    [ -z "$MAILBOX" ] && MAILBOX=$(jq -r '.mailbox // ""' "$NET_MONOREPO/environments/${NET_ENV}/solanatestnet/core/program-ids.json" 2>/dev/null || echo "")
fi

log_ok "Network: ${C}${NET_KEY}${NC} — ${NET_DISPLAY} (domain: ${NET_DOMAIN})"
log_info "Mailbox: ${MAILBOX:-NOT FOUND}"

apply_state

# Initialize runtime variables (priority: env > config > saved state)
WARP_PROGRAM_ID="${WARP_PROGRAM_ID:-}"
WARP_HEX="${WARP_HEX:-}"
MINT_ADDRESS="${MINT_ADDRESS:-}"
[ -z "$WARP_PROGRAM_ID" ] && [ -n "$SOL_PID_CFG" ] && [ "$SOL_PID_CFG" != "null" ] && WARP_PROGRAM_ID="$SOL_PID_CFG"
[ -z "$WARP_HEX"        ] && [ -n "$SOL_HEX_CFG" ] && [ "$SOL_HEX_CFG" != "null" ] && WARP_HEX="${SOL_HEX_CFG#0x}"
[ -z "$MINT_ADDRESS"    ] && [ -n "$SOL_MINT_CFG" ] && [ "$SOL_MINT_CFG" != "null" ] && MINT_ADDRESS="$SOL_MINT_CFG"

# Validate required paths
[ -z "$NET_KEYPAIR" ] || [ ! -f "$NET_KEYPAIR" ] && {
    log_err "Solana keypair not found: ${NET_KEYPAIR:-NOT CONFIGURED}"
    log "  Configure: warp-sealevel-config.json → .networks.${NET_KEY}.keypair"; exit 1; }
[ -z "$NET_MONOREPO" ] || [ ! -d "$NET_MONOREPO" ] && {
    log_err "Monorepo not found: ${NET_MONOREPO:-NOT CONFIGURED}"; exit 1; }

CLIENT_DIR="$NET_MONOREPO/client"
ENVIRONMENTS_DIR="$NET_MONOREPO/environments"
BUILT_SO_DIR="$NET_MONOREPO/target/deploy"
WARP_ROUTE_DIR="$ENVIRONMENTS_DIR/${NET_ENV}/warp-routes/${TOKEN_KEY}"
KEYS_DIR="$WARP_ROUTE_DIR/keys"
mkdir -p "$KEYS_DIR"

# Pre-compiled client binary path (avoids cargo run overhead if binary exists)
CLIENT_BIN="$NET_MONOREPO/target/release/hyperlane-sealevel-client"

# Keypair file paths expected by the warp-route deploy command
PROG_KEYPAIR_FILE="$KEYS_DIR/hyperlane_sealevel_token-${NET_KEY}-keypair.json"
BUFFER_KEYPAIR_FILE="$KEYS_DIR/hyperlane_sealevel_token-${NET_KEY}-buffer.json"

# ─────────────────────────────────────────────────────────────────────────────
# CONFIGURATION SUMMARY
# ─────────────────────────────────────────────────────────────────────────────
log ""
log "╔══════════════════════════════════════════════════════════════════════════╗"
log "║  📋  CONFIGURATION: ${C}${TOKEN_KEY}${NC} → ${C}${NET_DISPLAY}${NC}"
log "╚══════════════════════════════════════════════════════════════════════════╝"
log "  Token:      ${TOKEN_NAME} (${TOKEN_SYMBOL}) | decimals=${TOKEN_DEC}"
log "  Network:    ${NET_DISPLAY} | domain=${NET_DOMAIN} | env=${NET_ENV}"
log "  ISM:        ${ISM_PROGRAM_ID}"
log "  IGP prog:   ${IGP_PROGRAM_ID}"
log "  IGP acct:   ${IGP_ACCOUNT}"
log "  Mailbox:    ${MAILBOX:-NOT SET}"
log "  Keypair:    ${NET_KEYPAIR}"
log "  Prog key:   ${PROG_KEYPAIR_FILE}"
log "  Buffer key: ${BUFFER_KEYPAIR_FILE}"
[ -n "$WARP_PROGRAM_ID" ] && log "  Program ID: ${G}${WARP_PROGRAM_ID}${NC} (deploy will be skipped)"
log ""

if [ "$TERRA_WARP_DEPLOYED" != "true" ] || [ -z "$TERRA_WARP_ADDR" ] || [ "$TERRA_WARP_ADDR" = "null" ]; then
    log_warn "Terra Classic Warp not deployed for '${TOKEN_KEY}' — enroll/set_route will be skipped"
    export SKIP_ENROLL="${SKIP_ENROLL:-1}"
    export SKIP_TC_ROUTE="${SKIP_TC_ROUTE:-1}"
fi

echo -ne "  ${W}Confirm and continue? [Y/n]: ${NC}"
read -r CONFIRM 2>/dev/null || CONFIRM="y"
[[ "${CONFIRM:-y}" =~ ^[sSyYnN]$ ]] || CONFIRM="y"
[[ "${CONFIRM:-y}" =~ ^[sS]$ ]] && CONFIRM="y"
[[ "$CONFIRM" =~ ^[nN]$ ]] && { log "  Cancelled."; exit 0; }

# ═════════════════════════════════════════════════════════════════════════════
# STEP 1 — GET BINARY (.so) — local build preferred (community-verifiable)
# ═════════════════════════════════════════════════════════════════════════════
log_sep "STEP 1 — GET BINARY (.so)"

BINARY_FILE="$WARP_ROUTE_DIR/hyperlane_sealevel_token.so"
LOCAL_SO="$BUILT_SO_DIR/hyperlane_sealevel_token.so"
TOKEN_MANIFEST="$NET_MONOREPO/programs/hyperlane-sealevel-token/Cargo.toml"
BINARY_SOURCE="${BINARY_SOURCE:-build}"

# Records the .so SHA-256 next to it and prints it — the community references
# THIS hash to verify the deployed bytecode instead of trusting a live program.
publish_hash() {
    local so="$1"
    [ -f "$so" ] || return 0
    local sum
    sum=$(sha256sum "$so" | awk '{print $1}')
    echo "$sum  $(basename "$so")" > "${so}.sha256"
    BINARY_SHA256="$sum"
    log_ok "SHA-256: ${G}${sum}${NC}"
    log_info "Hash saved: ${so}.sha256"
    log_info "Anyone can verify with: ${Y}sha256sum ${so}${NC}"
}

if [ -n "${WARP_PROGRAM_ID:-}" ]; then
    log_warn "WARP_PROGRAM_ID already set — skipping binary acquisition and deploy."
    BINARY_FILE=""
elif [ -f "$BINARY_FILE" ]; then
    log_ok "Binary already present: ${C}${BINARY_FILE}${NC} ($(du -sh "$BINARY_FILE" | cut -f1))"
    publish_hash "$BINARY_FILE"
else
    case "$BINARY_SOURCE" in
        build)
            # Only path that deploys: compile from source so the SHA-256 is auditable.
            log_info "Binary source: ${G}build${NC} (compile locally from source — verifiable)"
            command -v cargo-build-sbf &>/dev/null || {
                log_err "cargo-build-sbf not found in PATH — cannot build locally."
                log "  Install the Solana toolchain, or (if you already built it) set BINARY_SOURCE=local."
                exit 1; }
            [ -f "$TOKEN_MANIFEST" ] || { log_err "Token manifest not found: $TOKEN_MANIFEST"; exit 1; }
            log_info "Compiling: ${C}cargo build-sbf --manifest-path ${TOKEN_MANIFEST}${NC}"
            log_warn "First build may take ~15-20 min (BPF compilation); cached afterwards."
            log ""
            set +e
            ( cd "$NET_MONOREPO" && cargo build-sbf --manifest-path "$TOKEN_MANIFEST" ) 2>&1 | tee -a "$LOG_FILE"
            BUILD_EXIT=${PIPESTATUS[0]}
            set -e
            if [ $BUILD_EXIT -ne 0 ] || [ ! -f "$LOCAL_SO" ]; then
                log_err "Local build failed (exit $BUILD_EXIT). Fix the toolchain/source and retry."
                exit 1
            fi
            cp "$LOCAL_SO" "$BINARY_FILE"
            log_ok "Compiled locally from source."
            ;;
        local)
            # Reuse a binary you already compiled yourself (no rebuild).
            log_info "Binary source: ${G}local${NC} (reuse pre-compiled ${LOCAL_SO})"
            [ -f "$LOCAL_SO" ] || { log_err "No compiled binary at ${LOCAL_SO}. Use BINARY_SOURCE=build."; exit 1; }
            cp "$LOCAL_SO" "$BINARY_FILE"
            log_ok "Using pre-compiled local binary."
            ;;
        *)
            log_err "Unknown BINARY_SOURCE='${BINARY_SOURCE}' (valid: build | local)"
            exit 1
            ;;
    esac
    BINARY_SZ=$(du -sh "$BINARY_FILE" | cut -f1)
    log_ok "Binary ready: ${C}${BINARY_FILE}${NC} (${BINARY_SZ})"
    publish_hash "$BINARY_FILE"
fi

# ═════════════════════════════════════════════════════════════════════════════
# STEP 2 — DEPLOY PROGRAM (solana CLI)
# ═════════════════════════════════════════════════════════════════════════════
log_sep "STEP 2 — DEPLOY PROGRAM (solana program deploy)"

if [ -n "${WARP_PROGRAM_ID:-}" ]; then
    log_warn "WARP_PROGRAM_ID=${WARP_PROGRAM_ID} — skipping binary deploy."
else
    # Generate or load the program keypair
    if [ ! -f "$PROG_KEYPAIR_FILE" ]; then
        log_info "Generating program keypair..."
        solana-keygen new --no-passphrase --silent \
            --outfile "$PROG_KEYPAIR_FILE" 2>&1 | tee -a "$LOG_FILE"
        log_ok "Keypair created: ${PROG_KEYPAIR_FILE}"
    else
        log_info "Program keypair already exists: ${PROG_KEYPAIR_FILE}"
    fi

    PROG_ID_FROM_KEY=$(keypair_to_pubkey "$PROG_KEYPAIR_FILE" 2>/dev/null || \
                       solana-keygen pubkey "$PROG_KEYPAIR_FILE" 2>/dev/null || echo "")
    if [ -z "$PROG_ID_FROM_KEY" ]; then
        log_err "Could not derive Program ID from keypair!"; exit 1
    fi
    log_info "Program ID (from keypair): ${G}${PROG_ID_FROM_KEY}${NC}"

    # Check if the program already exists on-chain
    PROG_EXISTS=$(solana program show "$PROG_ID_FROM_KEY" --url "$NET_RPC" 2>/dev/null | grep -c "Program Id" 2>/dev/null || true)
    PROG_EXISTS="${PROG_EXISTS//[^0-9]/}"
    PROG_EXISTS="${PROG_EXISTS:-0}"
    if [ "$PROG_EXISTS" -gt 0 ] 2>/dev/null; then
        log_ok "Program already exists on-chain: ${PROG_ID_FROM_KEY}"
        WARP_PROGRAM_ID="$PROG_ID_FROM_KEY"
    else
        BALANCE=$(solana balance "$NET_KEYPAIR" --url "$NET_RPC" 2>/dev/null | awk '{print $1}' || echo "0")
        log_info "Wallet balance: ${BALANCE} SOL"
        BINARY_SZ_BYTES=$(wc -c < "$BINARY_FILE" 2>/dev/null || echo "0")
        RENT_EST=$(python3 -c "print(f'~{($BINARY_SZ_BYTES * 0.00000696):.2f} SOL')" 2>/dev/null || echo "~2-5 SOL")  # ~6.96e-6 SOL/byte (programdata rent, medido)
        log_info "Estimated binary upload cost: ${RENT_EST}"
        log_warn "This SOL cost is unavoidable — it pays for on-chain program storage."

        echo -ne "  ${W}Proceed with binary deploy? [Y/n]: ${NC}"
        read -r CONF_DEPLOY 2>/dev/null || CONF_DEPLOY="y"
        [[ "${CONF_DEPLOY:-y}" =~ ^[nN]$ ]] && { log "  Cancelled."; exit 0; }

        log_info "Uploading binary to Solana..."
        log_warn "This may take several minutes (~${BINARY_SZ_BYTES} bytes)..."
        log ""

        # Generate buffer keypair if it doesn't exist
        if [ ! -f "$BUFFER_KEYPAIR_FILE" ]; then
            solana-keygen new --no-passphrase --silent \
                --outfile "$BUFFER_KEYPAIR_FILE" 2>&1 | tee -a "$LOG_FILE"
        else
            log_info "Reusing existing buffer keypair: ${BUFFER_KEYPAIR_FILE}"
        fi

        BUFFER_PUBKEY=$(solana-keygen pubkey "$BUFFER_KEYPAIR_FILE" 2>/dev/null || \
                        keypair_to_pubkey "$BUFFER_KEYPAIR_FILE" 2>/dev/null || echo "")
        log_info "Buffer pubkey: ${BUFFER_PUBKEY:-N/A}"

        set +e
        solana program deploy "$BINARY_FILE" \
            --url "$NET_RPC" \
            --keypair "$NET_KEYPAIR" \
            --program-id "$PROG_KEYPAIR_FILE" \
            --buffer "$BUFFER_KEYPAIR_FILE" \
            --upgrade-authority "$NET_KEYPAIR" \
            2>&1 | tee -a "$LOG_FILE"
        DEPLOY_EXIT=$?
        set -e

        if [ $DEPLOY_EXIT -ne 0 ]; then
            log_err "Program deploy failed (exit $DEPLOY_EXIT)!"
            log_warn "The buffer may be partially funded — run again to resume."
            log "  Buffer keypair: ${BUFFER_KEYPAIR_FILE}"
            log "  Buffer pubkey:  ${BUFFER_PUBKEY:-N/A}"
            log "  To cancel and recover SOL from the buffer:"
            log "    solana program close ${BUFFER_PUBKEY:-BUFFER_PUBKEY} --url ${NET_RPC} --keypair ${NET_KEYPAIR} --buffer"
            exit 1
        fi

        WARP_PROGRAM_ID="$PROG_ID_FROM_KEY"
        log_ok "Program deployed: ${G}${WARP_PROGRAM_ID}${NC}"
    fi

    save_state
fi

log_ok "Program ID: ${G}${WARP_PROGRAM_ID}${NC}"

# Convert Program ID to hex32 (required for Terra Classic set_route).
# ALWAYS derive from WARP_PROGRAM_ID (source of truth) — a stale program_hex in the
# config (e.g. from a previous/closed program) must NOT win, or set_route on Terra
# Classic would point at the wrong Solana program.
if [ -n "${WARP_PROGRAM_ID:-}" ]; then
    _DERIVED_HEX=$(b58_to_hex32 "$WARP_PROGRAM_ID")
    [ -z "$_DERIVED_HEX" ] && { log_err "Failed to convert Program ID to hex32!"; exit 1; }
    [ "${WARP_HEX:-}" != "$_DERIVED_HEX" ] && WARP_HEX="$_DERIVED_HEX" && save_state
fi
log_info "Program ID (hex32): 0x${WARP_HEX}"

# Update warp-sealevel-config.json with program_id and hex
TMP=$(mktemp)
jq ".networks.\"${NET_KEY}\".warp_tokens.\"${TOKEN_KEY}\".program_id = \"${WARP_PROGRAM_ID}\" |
    .networks.\"${NET_KEY}\".warp_tokens.\"${TOKEN_KEY}\".program_hex = \"0x${WARP_HEX}\"" \
    "$SOL_CONFIG" > "$TMP" && mv "$TMP" "$SOL_CONFIG"
log_ok "warp-sealevel-config.json updated with program_id"

# ═════════════════════════════════════════════════════════════════════════════
# STEP 3 — TOKEN INIT via jito-warp-init.js (MEV-safe)
# ═════════════════════════════════════════════════════════════════════════════
#
#  MEV PROTECTION:
#  jito-warp-init.js sends warp_init + InitializeMint2 in a SINGLE atomic
#  transaction, eliminating any window where an MEV bot could steal the
#  uninitialized mint PDA between two separate transactions.
#
#  Set SKIP_INIT=1 to skip if the token storage already exists.
#
log_sep "STEP 3 — TOKEN INIT (jito-warp-init.js — MEV-safe)"

if [ -n "${SKIP_INIT:-}" ]; then
    log_warn "SKIP_INIT set — skipping token init."
else
    if [ -z "$MAILBOX" ] || [ "$MAILBOX" = "null" ]; then
        log_err "Mailbox not found! Set it in warp-sealevel-config.json → .networks.${NET_KEY}.mailbox"
        exit 1
    fi

    JITO_SCRIPT="$SCRIPT_DIR/jito-warp-init.js"
    if [ ! -f "$JITO_SCRIPT" ]; then
        log_err "jito-warp-init.js not found at: $JITO_SCRIPT"
        exit 1
    fi

    # Priority fee tip (default: 0.005 SOL = 5000000 lamports)
    JITO_TIP="${JITO_TIP_LAMPORTS:-5000000}"
    log_info "Priority fee: $(python3 -c "print(f'{${JITO_TIP}/1e9:.4f} SOL')" 2>/dev/null || echo "${JITO_TIP} lamports")"

    # Retry loop with increasing tip if init fails
    JITO_MAX_RETRIES=3
    JITO_RETRY=0
    JITO_SUCCESS=0

    while [ $JITO_RETRY -lt $JITO_MAX_RETRIES ]; do
        log_info "Attempt $((JITO_RETRY+1)) of ${JITO_MAX_RETRIES} — tip = ${JITO_TIP} lamports"
        log ""

        JITO_TMP=$(mktemp)
        set +e
        NET_KEY="$NET_KEY" \
        TOKEN_KEY="$TOKEN_KEY" \
        NET_RPC="$NET_RPC" \
        KEYPAIR_PATH="$NET_KEYPAIR" \
        WARP_PROGRAM_ID="$WARP_PROGRAM_ID" \
        MAILBOX="$MAILBOX" \
        IGP_PROGRAM_ID="$IGP_PROGRAM_ID" \
        IGP_ACCOUNT="$IGP_ACCOUNT" \
        DECIMALS="${SOL_TOK_DEC:-6}" \
        TOKEN_NAME="${TOKEN_NAME}" \
        TOKEN_SYMBOL="${TOKEN_SYMBOL}" \
        TOKEN_URI="${SOL_META_URI:-}" \
        JITO_TIP_LAMPORTS="$JITO_TIP" \
        ATA_PAYER_FUNDING="50000000" \
            node "$JITO_SCRIPT" "$NET_KEY" "$TOKEN_KEY" 2>&1 \
            | tee -a "$LOG_FILE" "$JITO_TMP"
        JITO_EXIT=$?
        JITO_OUT=$(cat "$JITO_TMP"); rm -f "$JITO_TMP"
        set -e

        # Exit code 2 = MEV bot won, retry with doubled tip
        if [ $JITO_EXIT -eq 2 ]; then
            JITO_TIP=$(python3 -c "print(int(${JITO_TIP} * 2))" 2>/dev/null || echo "$((JITO_TIP * 2))")
            log_warn "MEV bot won! Doubling tip to ${JITO_TIP} lamports and retrying..."
            JITO_RETRY=$((JITO_RETRY+1))
            sleep 5
            continue
        fi

        if [ $JITO_EXIT -eq 0 ] && echo "$JITO_OUT" | grep -q "JITO_INIT_OK=1"; then
            JITO_SUCCESS=1
            _MINT_FROM_JITO=$(echo "$JITO_OUT" | grep "^MINT_ADDRESS=" | cut -d= -f2 | tr -d '[:space:]' || echo "")
            [ -n "$_MINT_FROM_JITO" ] && MINT_ADDRESS="$_MINT_FROM_JITO"
            log_ok "Init confirmed! Mint: ${G}${MINT_ADDRESS:-N/A}${NC}"
            break
        fi

        log_err "jito-warp-init.js failed (exit $JITO_EXIT)"
        echo "$JITO_OUT" | tail -10 | tee -a "$LOG_FILE"
        JITO_RETRY=$((JITO_RETRY+1))
        if [ $JITO_RETRY -lt $JITO_MAX_RETRIES ]; then
            log_warn "Retrying in 10s..."
            sleep 10
        fi
    done

    if [ $JITO_SUCCESS -eq 0 ]; then
        log_err "Token init failed after ${JITO_MAX_RETRIES} attempts!"
        log ""
        log "  Recovery options:"
        log "  1. Close program and reclaim SOL: ${Y}./close-warp-program.sh${NC}"
        log "  2. Retry with higher tip: ${Y}export JITO_TIP_LAMPORTS=20000000${NC}"
        log "  3. Try again during off-peak hours (fewer MEV bots)"
        exit 1
    fi

    # Update config with mint_address (jito-warp-init.js also does this, but ensure it here)
    if [ -n "${MINT_ADDRESS:-}" ]; then
        TMP=$(mktemp)
        jq ".networks.\"${NET_KEY}\".warp_tokens.\"${TOKEN_KEY}\".mint_address = \"${MINT_ADDRESS}\" |
            .networks.\"${NET_KEY}\".warp_tokens.\"${TOKEN_KEY}\".deployed = true" \
            "$SOL_CONFIG" > "$TMP" && mv "$TMP" "$SOL_CONFIG"
        log_ok "warp-sealevel-config.json updated: mint_address=${MINT_ADDRESS}"
        save_state
    fi
fi

# ── Helper: run the pre-compiled sealevel client binary ─────────────────────
run_client() {
    if [ -x "$CLIENT_BIN" ]; then
        "$CLIENT_BIN" "$@"
    else
        cd "$CLIENT_DIR"
        cargo run --release --quiet -- "$@"
        cd "$SCRIPT_DIR"
    fi
}

# ═════════════════════════════════════════════════════════════════════════════
# STEP 4 — CONFIGURE ISM (Interchain Security Module)
# ═════════════════════════════════════════════════════════════════════════════
log_sep "STEP 4 — CONFIGURE ISM (Interchain Security Module)"

if [ -n "${SKIP_ISM:-}" ]; then
    log_warn "SKIP_ISM set — skipping."
else
    set +e
    TMP=$(mktemp)
    run_client \
        -k "$NET_KEYPAIR" -u "$NET_RPC" \
        token set-interchain-security-module \
        --program-id "$WARP_PROGRAM_ID" \
        --ism "$ISM_PROGRAM_ID" 2>&1 \
        | grep -v "^warning:" | grep -v "^note:" | grep -v "^Compiling" \
        | tee -a "$LOG_FILE" "$TMP"
    ISM_EXIT=${PIPESTATUS[0]}
    ISM_OUT=$(cat "$TMP"); rm -f "$TMP"
    set -e

    if [ $ISM_EXIT -eq 0 ]; then
        log_ok "ISM configured: ${ISM_PROGRAM_ID}"
    elif echo "$ISM_OUT" | grep -qiE "already|same"; then
        log_ok "ISM already configured."
    else
        log_warn "ISM configuration failed (exit $ISM_EXIT). Run manually:"
        log "  $CLIENT_BIN -k $NET_KEYPAIR -u $NET_RPC token set-interchain-security-module --program-id $WARP_PROGRAM_ID --ism $ISM_PROGRAM_ID"
    fi
fi

# ═════════════════════════════════════════════════════════════════════════════
# STEP 5 — CONFIGURE IGP (Interchain Gas Paymaster)
# ═════════════════════════════════════════════════════════════════════════════
log_sep "STEP 5 — CONFIGURE IGP (Interchain Gas Paymaster)"

if [ -n "${SKIP_IGP:-}" ]; then
    log_warn "SKIP_IGP set — skipping."
else
    log_info "IGP type: ${IGP_ACCOUNT_TYPE} (must match the account kind — overhead account ⇒ overhead-igp)"
    set +e
    TMP=$(mktemp)
    run_client \
        -k "$NET_KEYPAIR" -u "$NET_RPC" \
        token igp \
        --program-id "$WARP_PROGRAM_ID" \
        set "$IGP_PROGRAM_ID" "$IGP_ACCOUNT_TYPE" "$IGP_ACCOUNT" 2>&1 \
        | grep -v "^warning:" | grep -v "^note:" | grep -v "^Compiling" \
        | tee -a "$LOG_FILE" "$TMP"
    IGP_EXIT=${PIPESTATUS[0]}
    IGP_OUT=$(cat "$TMP"); rm -f "$TMP"
    set -e

    if [ $IGP_EXIT -eq 0 ]; then
        log_ok "IGP configured: ${IGP_PROGRAM_ID} / ${IGP_ACCOUNT_TYPE}(${IGP_ACCOUNT})"
    elif echo "$IGP_OUT" | grep -qiE "already|same"; then
        log_ok "IGP already configured."
    else
        # FATAL: sem o IGP correto a VOLTA (sealevel→TC) NÃO funciona — não seguir como sucesso.
        log_err "IGP configuration FAILED (exit $IGP_EXIT). The RETURN route will NOT work. Run manually:"
        log "  $CLIENT_BIN -k $NET_KEYPAIR -u $NET_RPC token igp --program-id $WARP_PROGRAM_ID set $IGP_PROGRAM_ID $IGP_ACCOUNT_TYPE $IGP_ACCOUNT"
        exit 1
    fi

    # ── VERIFICAÇÃO on-chain: o tipo gravado no token DEVE ser o esperado ────────
    set +e
    IGP_GET=$(run_client -k "$NET_KEYPAIR" -u "$NET_RPC" \
        token igp --program-id "$WARP_PROGRAM_ID" get synthetic 2>&1 | tail -5)
    set -e
    if echo "$IGP_GET" | grep -q "OverheadIgp" && [ "$IGP_ACCOUNT_TYPE" = "overhead-igp" ]; then
        log_ok "Verified on-chain: token IGP type = OverheadIgp ✅"
    elif echo "$IGP_GET" | grep -qE "\bIgp\(" && [ "$IGP_ACCOUNT_TYPE" = "igp" ]; then
        log_ok "Verified on-chain: token IGP type = Igp ✅"
    else
        log_warn "Could not verify IGP type on-chain — CHECK MANUALLY (type mismatch breaks the return route):"
        log "  $CLIENT_BIN -u $NET_RPC token igp --program-id $WARP_PROGRAM_ID get synthetic"
    fi
fi

# ═════════════════════════════════════════════════════════════════════════════
# STEP 6 — CONFIGURE DESTINATION GAS (Terra Classic)
# ═════════════════════════════════════════════════════════════════════════════
log_sep "STEP 6 — CONFIGURE DESTINATION GAS (Terra Classic domain ${TERRA_DOMAIN})"

if [ -n "${SKIP_GAS:-}" ]; then
    log_warn "SKIP_GAS set — skipping."
else
    set +e
    TMP=$(mktemp)
    run_client \
        -k "$NET_KEYPAIR" -u "$NET_RPC" \
        token set-destination-gas \
        --program-id "$WARP_PROGRAM_ID" \
        "$TERRA_DOMAIN" "$DEST_GAS" 2>&1 \
        | grep -v "^warning:" | grep -v "^note:" | grep -v "^Compiling" \
        | tee -a "$LOG_FILE" "$TMP"
    GAS_EXIT=${PIPESTATUS[0]}
    GAS_OUT=$(cat "$TMP"); rm -f "$TMP"
    set -e

    if [ $GAS_EXIT -eq 0 ]; then
        log_ok "Destination gas configured: domain=${TERRA_DOMAIN} gas=${DEST_GAS}"
    elif echo "$GAS_OUT" | grep -qiE "already|same"; then
        log_ok "Destination gas already configured."
    else
        log_warn "Destination gas configuration failed (exit $GAS_EXIT). Run manually:"
        log "  $CLIENT_BIN -k $NET_KEYPAIR -u $NET_RPC token set-destination-gas --program-id $WARP_PROGRAM_ID $TERRA_DOMAIN $DEST_GAS"
    fi
fi

# ═════════════════════════════════════════════════════════════════════════════
# STEP 7 — ENROLL REMOTE ROUTER (Solana → Terra Classic)
# ═════════════════════════════════════════════════════════════════════════════
log_sep "STEP 7 — ENROLL REMOTE ROUTER (Solana → Terra Classic)"

if [ -n "${SKIP_ENROLL:-}" ]; then
    log_warn "SKIP_ENROLL set — skipping."
elif [ -z "$TERRA_WARP_ADDR" ] || [ "$TERRA_WARP_ADDR" = "null" ]; then
    log_warn "Terra Classic Warp not deployed — skipping enroll."
else
    TC_HEX="${TERRA_WARP_HEX#0x}"
    set +e
    TMP=$(mktemp)
    run_client \
        -k "$NET_KEYPAIR" -u "$NET_RPC" \
        token enroll-remote-router \
        --program-id "$WARP_PROGRAM_ID" \
        "$TERRA_DOMAIN" "0x${TC_HEX}" 2>&1 \
        | grep -v "^warning:" | grep -v "^note:" | grep -v "^Compiling" \
        | tee -a "$LOG_FILE" "$TMP"
    ENR_EXIT=${PIPESTATUS[0]}
    ENR_OUT=$(cat "$TMP"); rm -f "$TMP"
    set -e

    if [ $ENR_EXIT -eq 0 ]; then
        log_ok "Remote Router enrolled: Terra Classic (domain ${TERRA_DOMAIN})"
    elif echo "$ENR_OUT" | grep -qiE "already|exists"; then
        log_ok "Remote Router already enrolled."
    else
        log_warn "Enroll failed (exit $ENR_EXIT). Run manually:"
        log "  $CLIENT_BIN -k $NET_KEYPAIR -u $NET_RPC token enroll-remote-router --program-id $WARP_PROGRAM_ID $TERRA_DOMAIN 0x${TC_HEX}"
    fi
fi

# ═════════════════════════════════════════════════════════════════════════════
# STEP 8 — SET ROUTE ON TERRA CLASSIC (Terra Classic → Solana)
# ═════════════════════════════════════════════════════════════════════════════
log_sep "STEP 8 — SET ROUTE ON TERRA CLASSIC (Terra Classic → Solana)"

if [ -n "${SKIP_TC_ROUTE:-}" ]; then
    log_warn "SKIP_TC_ROUTE set — skipping."
elif [ -z "$TERRA_WARP_ADDR" ] || [ "$TERRA_WARP_ADDR" = "null" ]; then
    log_warn "Terra Classic Warp not deployed — skipping set_route."
elif [ -z "${TERRA_PRIVATE_KEY:-}" ]; then
    log_warn "TERRA_PRIVATE_KEY not set — skipping Terra Classic set_route."
    log "  Run: export TERRA_PRIVATE_KEY='your_hex_key'"
    log "  Then: export WARP_PROGRAM_ID='${WARP_PROGRAM_ID}' SKIP_ENROLL=1 && ./deploy-warp-solana-buffer.sh"
else
    TERRA_PRIV_CLEAN="${TERRA_PRIVATE_KEY#0x}"
    log_info "Terra Classic Warp: ${TERRA_WARP_ADDR}"
    log_info "Solana domain: ${NET_DOMAIN}"
    log_info "Solana hex32: ${WARP_HEX}"

    _NODE_TMP=$(mktemp /tmp/set-route-sol-XXXXXX.js)
    cat > "$_NODE_TMP" <<'NODEJS'
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
    const solHex   = process.env._NM_SOL_HEX;
    const domain   = parseInt(process.env._NM_DOMAIN, 10);

    const wallet = await DirectSecp256k1Wallet.fromKey(fromHex(privKey), 'terra');
    const [account] = await wallet.getAccounts();
    const client = await SigningCosmWasmClient.connectWithSigner(
        rpc, wallet, { gasPrice: GasPrice.fromString('28.325uluna') }
    );

    try {
        const routes = await client.queryContractSmart(warpAddr, { router: { list_routes: {} } });
        const ex = (routes.routes || []).find(r => r.domain === domain);
        if (ex && ex.route) {
            const en = ex.route.replace(/^0x/i,'').toLowerCase();
            const ep = solHex.replace(/^0x/i,'').toLowerCase();
            if (en === ep) { console.log('STATUS=already_set'); console.log('EXISTING='+ex.route); return; }
        }
    } catch(e) { /* route does not exist yet */ }

    const result = await client.execute(
        account.address, warpAddr,
        { router: { set_route: { set: { domain: domain, route: solHex.replace(/^0x/i,'') } } } },
        'auto', 'set_route TC → Solana via deploy-warp-solana-buffer.sh'
    );
    console.log('STATUS=ok');
    console.log('TX='+result.transactionHash);
}
main().catch(e => { console.log('STATUS=error'); console.log('ERR='+e.message); process.exit(0); });
NODEJS

    set +e
    SR_RESULT=$(
        _NM_ROOT="$PROJECT_ROOT" _NM_PRIV="$TERRA_PRIV_CLEAN" _NM_RPC="$TERRA_RPC" \
        _NM_WARP="$TERRA_WARP_ADDR" _NM_SOL_HEX="$WARP_HEX" _NM_DOMAIN="$NET_DOMAIN" \
        node --no-warnings "$_NODE_TMP" 2>&1
    )
    NODE_EXIT=$?
    set -e
    rm -f "$_NODE_TMP"

    SR_STATUS=$(echo "$SR_RESULT" | grep "^STATUS=" | cut -d= -f2 || echo "")
    SR_TX=$(echo     "$SR_RESULT" | grep "^TX="     | cut -d= -f2 || echo "")
    SR_ERR=$(echo    "$SR_RESULT" | grep "^ERR="    | cut -d= -f2- || echo "")

    case "$SR_STATUS" in
        ok)           log_ok "set_route executed! Terra Classic → Solana linked."
                      log "   TX: ${B}https://finder.hexxagon.io/${TERRA_CHAIN_ID}/tx/${SR_TX}${NC}" ;;
        already_set)  EXISTING=$(echo "$SR_RESULT" | grep "^EXISTING=" | cut -d= -f2 || echo "")
                      log_ok "Route already configured on Terra Classic (${EXISTING:-already set})." ;;
        error)        log_warn "set_route failed: ${SR_ERR}"
                      log "  Manual: terrad tx wasm execute \"${TERRA_WARP_ADDR}\" '{\"router\":{\"set_route\":{\"set\":{\"domain\":${NET_DOMAIN},\"route\":\"${WARP_HEX}\"}}}}' --from <KEY> --chain-id ${TERRA_CHAIN_ID} --node ${TERRA_RPC} --gas auto --gas-adjustment 1.5 --fees 12000000uluna --yes" ;;
        *)            log_warn "Unexpected result (exit=$NODE_EXIT)."
                      [ -n "$SR_RESULT" ] && echo "$SR_RESULT" | head -5 | tee -a "$LOG_FILE" ;;
    esac
fi

# ═════════════════════════════════════════════════════════════════════════════
# STEP 9 — QUERY WARP STATE + TRANSFER OWNERSHIP
# ═════════════════════════════════════════════════════════════════════════════
log_sep "STEP 9 — QUERY WARP STATE + MINT ADDRESS"

set +e
QUERY_OUT=$(run_client \
    -k "$NET_KEYPAIR" -u "$NET_RPC" \
    token query --program-id "$WARP_PROGRAM_ID" synthetic 2>&1 \
    | grep -v "^warning:" | grep -v "^note:" || echo "")
set -e

if [ -n "$QUERY_OUT" ]; then
    NEW_MINT=$(echo "$QUERY_OUT" | grep -iE "mint" | grep -oE "[1-9A-HJ-NP-Za-km-z]{32,44}" | head -1 || echo "")
    if [ -n "$NEW_MINT" ]; then
        MINT_ADDRESS="$NEW_MINT"
        log_ok "Mint Address: ${G}${MINT_ADDRESS}${NC}"
        TMP=$(mktemp)
        jq ".networks.\"${NET_KEY}\".warp_tokens.\"${TOKEN_KEY}\".mint_address = \"${MINT_ADDRESS}\" |
            .networks.\"${NET_KEY}\".warp_tokens.\"${TOKEN_KEY}\".deployed = true" \
            "$SOL_CONFIG" > "$TMP" && mv "$TMP" "$SOL_CONFIG"
        log_ok "warp-sealevel-config.json updated (deployed=true, mint_address)"
        save_state
    fi
fi

if [ -n "$SOL_OWNER" ] && [ "$SOL_OWNER" != "null" ]; then
    log_info "Transferring ownership to: $SOL_OWNER"
    set +e
    run_client \
        -k "$NET_KEYPAIR" -u "$NET_RPC" \
        token transfer-ownership \
        --program-id "$WARP_PROGRAM_ID" \
        "$SOL_OWNER" 2>&1 \
        | grep -v "^warning:" | grep -v "^note:" | grep -v "^Compiling" \
        | tee -a "$LOG_FILE"
    OWN_EXIT=${PIPESTATUS[0]}
    set -e
    [ $OWN_EXIT -eq 0 ] && log_ok "Ownership transferred to: $SOL_OWNER" \
                         || log_warn "Ownership transfer failed (may already be correct)."
fi

# ═════════════════════════════════════════════════════════════════════════════
# FINAL REPORT
# ═════════════════════════════════════════════════════════════════════════════
NET_UPPER=$(echo "$NET_KEY" | tr '[:lower:]' '[:upper:]')
TOK_UPPER=$(echo "$TOKEN_KEY" | tr '[:lower:]' '[:upper:]')
REPORT="$LOG_DIR/WARP-${NET_UPPER}-${TOK_UPPER}-BUFFER.txt"

cat > "$REPORT" <<TXT
═══════════════════════════════════════════════════════════
  WARP ROUTE SOLANA: ${TOKEN_SYMBOL} on ${NET_DISPLAY}
  Generated: $(date '+%Y-%m-%d %H:%M:%S')
═══════════════════════════════════════════════════════════

[SOLANA PROGRAM]
Network:          ${NET_DISPLAY} (domain: ${NET_DOMAIN})
Token:            ${TOKEN_NAME} (${TOKEN_SYMBOL})
Program ID (b58): ${WARP_PROGRAM_ID}
Program ID (hex): 0x${WARP_HEX}
Binary SHA-256:   ${BINARY_SHA256:-N/A}
Mint Address:     ${MINT_ADDRESS:-N/A}
ISM Program:      ${ISM_PROGRAM_ID}
IGP Program:      ${IGP_PROGRAM_ID}
IGP Account:      ${IGP_ACCOUNT}
Dest Gas (TC):    ${DEST_GAS}
Mailbox:          ${MAILBOX:-N/A}
Owner:            ${SOL_OWNER:-keypair}
RPC:              ${NET_RPC}
Explorer:         ${NET_EXPLORER}

[TERRA CLASSIC WARP]
Address:   ${TERRA_WARP_ADDR:-N/A}
Hex:       ${TERRA_WARP_HEX:-N/A}
Domain:    ${TERRA_DOMAIN}
Chain ID:  ${TERRA_CHAIN_ID}

[MANUAL VERIFICATION]
# Query Solana warp state:
${CLIENT_BIN} -k ${NET_KEYPAIR} -u ${NET_RPC} token query --program-id ${WARP_PROGRAM_ID} synthetic

# Query Terra Classic route:
terrad query wasm contract-state smart ${TERRA_WARP_ADDR:-TC_WARP} '{"router":{"get_route":{"domain":${NET_DOMAIN}}}}' --node ${TERRA_RPC}

# List on-chain programs (check for orphaned buffers):
solana program show --url ${NET_RPC} --programs --keypair ${NET_KEYPAIR}

# Close program and recover SOL:
solana program close ${WARP_PROGRAM_ID} --bypass-warning --keypair ${NET_KEYPAIR} --url ${NET_RPC}
TXT

log_ok "Report saved: ${C}${REPORT}${NC}"

log ""
log "╔══════════════════════════════════════════════════════════════════════════╗"
log "║          ✅  WARP ROUTE SOLANA DEPLOYED SUCCESSFULLY!                   ║"
log "╚══════════════════════════════════════════════════════════════════════════╝"
log ""
log "  ${G}Program ID:${NC}  ${WARP_PROGRAM_ID}"
log "  ${G}Hex32:${NC}       0x${WARP_HEX}"
[ -n "${MINT_ADDRESS:-}" ] && log "  ${G}Mint:${NC}        ${MINT_ADDRESS}"
log "  ${G}ISM:${NC}         ${ISM_PROGRAM_ID}"
log "  ${G}IGP:${NC}         ${IGP_ACCOUNT}"
log "  ${G}Terra Warp:${NC}  ${TERRA_WARP_ADDR:-N/A}"
log ""
if [ -z "${SKIP_ENROLL:-}" ]; then
    log "  ✅ Solana → Terra Classic (enroll, domain ${TERRA_DOMAIN})"
else
    log "  ⚠️  Solana → Terra Classic: pending"
fi
if [ -z "${SKIP_TC_ROUTE:-}" ] && [ -n "${TERRA_PRIVATE_KEY:-}" ]; then
    log "  ✅ Terra Classic → Solana (set_route, domain ${NET_DOMAIN})"
else
    log "  ⚠️  Terra Classic → Solana: pending (export TERRA_PRIVATE_KEY=... and rerun)"
fi
log ""
log "${B}📄 Report: ${REPORT}${NC}"
log "${B}📋 Log:    ${LOG_FILE}${NC}"
