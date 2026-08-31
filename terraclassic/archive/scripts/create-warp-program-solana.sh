#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
#  🏗️  CREATE WARP PROGRAM (SEALEVEL) — build locally + deploy + publish hash
# ═══════════════════════════════════════════════════════════════════════════════
#
#  Purpose (standalone, does ONE thing):
#    1. Compile hyperlane-sealevel-token from source via `cargo build-sbf`
#    2. Publish the binary SHA-256 (community-verifiable reference)
#    3. Deploy the program to Solana → report a fresh Program ID (b58 + hex32)
#
#  This is the community reference deploy. It REPLACES the old habit of dumping
#  bytecode from a third-party program (e.g. Fa4zQJCH7id5KL1eFJt2mHyFpUNfCCSkHgtMrLvrRJBN):
#  here you build your OWN binary, everyone can verify its hash, and you deploy it
#  under your OWN Program ID.
#
#  It does NOT run token init / ISM / IGP / routes — that is the job of
#  deploy-warp-solana-buffer.sh. To wire that script to THIS program, pass the
#  reported Program ID back to it:
#      export WARP_PROGRAM_ID=<reported id>
#      ./deploy-warp-solana-buffer.sh
#
#  Usage:
#    ./create-warp-program-solana.sh
#
#  Optional environment variables:
#    BINARY_SOURCE=build|local  → build from source (default) or reuse target/deploy/*.so
#    PROGRAM_KEYPAIR=<path>      → deploy under an existing keypair (reuse a Program ID)
#    SKIP_DEPLOY=1              → build + hash only, do not touch chain
#
#  Pinned toolchain + reference SHA-256:  doc/archive/WARP-SOLANA-BINARY-REFERENCE.md
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
SOL_CONFIG="$SCRIPT_DIR/warp-sealevel-config.json"
LOG_DIR="$SCRIPT_DIR/log"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/create-warp-program-solana.log"

BINARY_SOURCE="${BINARY_SOURCE:-build}"

# ─────────────────────────────────────────────────────────────────────────────
# UTILITIES
# ─────────────────────────────────────────────────────────────────────────────
log()      { echo -e "$@" | tee -a "$LOG_FILE"; }
log_ok()   { log "${OK} $*"; }
log_err()  { log "${ERR} $*"; }
log_warn() { log "${WARN} $*"; }
log_info() { log "${INFO} $*"; }
log_sep()  { log ""; log "${C}${W}$1${NC}"; log "────────────────────────────────────────────────────────────────"; }

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

# ─────────────────────────────────────────────────────────────────────────────
# BANNER
# ─────────────────────────────────────────────────────────────────────────────
> "$LOG_FILE"
clear 2>/dev/null || true
log "╔══════════════════════════════════════════════════════════════════════════╗"
log "║  🏗️  CREATE WARP PROGRAM (SEALEVEL) — build + deploy + publish hash    ║"
log "║  Date: $(date '+%Y-%m-%d %H:%M:%S')                                         ║"
log "╚══════════════════════════════════════════════════════════════════════════╝"

# ─────────────────────────────────────────────────────────────────────────────
# INITIAL CHECKS
# ─────────────────────────────────────────────────────────────────────────────
[ -f "$SOL_CONFIG" ] || { log_err "File not found: $SOL_CONFIG"; exit 1; }
jq empty "$SOL_CONFIG" 2>/dev/null || { log_err "Invalid JSON: $SOL_CONFIG"; exit 1; }
command -v jq      &>/dev/null || { log_err "jq is required"; exit 1; }
command -v python3 &>/dev/null || { log_err "python3 is required"; exit 1; }
command -v solana  &>/dev/null || { log_err "solana-cli is required"; exit 1; }
if [ "$BINARY_SOURCE" = "build" ]; then
    command -v cargo-build-sbf &>/dev/null || { log_err "cargo-build-sbf is required for BINARY_SOURCE=build"; exit 1; }
fi

# ═════════════════════════════════════════════════════════════════════════════
# MENU — SELECT SOLANA NETWORK
# ═════════════════════════════════════════════════════════════════════════════
log_sep "SOLANA NETWORK SELECTION"
mapfile -t NET_KEYS < <(jq -r '.networks | to_entries[] | select(.value.enabled==true) | .key' "$SOL_CONFIG" 2>/dev/null)
[ ${#NET_KEYS[@]} -eq 0 ] && { log_err "No Solana network enabled!"; exit 1; }
declare -a NET_MENU=()
i=1
for NK in "${NET_KEYS[@]}"; do
    ND=$(sol_cfg ".networks.${NK}.display_name")
    DOM=$(sol_cfg ".networks.${NK}.domain")
    NET_MENU+=("$NK")
    log "  [${W}$i${NC}]  ${C}${NK}${NC} — ${ND} (domain: ${DOM})"
    i=$((i+1))
done
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

log_ok "Network: ${C}${NET_KEY}${NC} — ${NET_DISPLAY} (domain: ${NET_DOMAIN})"

# Validate required paths
[ -z "$NET_KEYPAIR" ] || [ ! -f "$NET_KEYPAIR" ] && {
    log_err "Solana keypair not found: ${NET_KEYPAIR:-NOT CONFIGURED}"
    log "  Configure: warp-sealevel-config.json → .networks.${NET_KEY}.keypair"; exit 1; }
[ -z "$NET_MONOREPO" ] || [ ! -d "$NET_MONOREPO" ] && {
    log_err "Monorepo not found: ${NET_MONOREPO:-NOT CONFIGURED}"; exit 1; }

BUILT_SO_DIR="$NET_MONOREPO/target/deploy"
LOCAL_SO="$BUILT_SO_DIR/hyperlane_sealevel_token.so"
TOKEN_MANIFEST="$NET_MONOREPO/programs/hyperlane-sealevel-token/Cargo.toml"

# Work dir for this reference program (binary + keypairs + reference files)
WORK_DIR="$SCRIPT_DIR/warp/reference-program/${NET_KEY}"
KEYS_DIR="$WORK_DIR/keys"
mkdir -p "$KEYS_DIR"

BINARY_FILE="$WORK_DIR/hyperlane_sealevel_token.so"
PROG_KEYPAIR_FILE="${PROGRAM_KEYPAIR:-$KEYS_DIR/reference-program-${NET_KEY}-keypair.json}"
BUFFER_KEYPAIR_FILE="$KEYS_DIR/reference-program-${NET_KEY}-buffer.json"

# ═════════════════════════════════════════════════════════════════════════════
# STEP 1 — BUILD BINARY (.so) — local build only (community-verifiable)
# ═════════════════════════════════════════════════════════════════════════════
log_sep "STEP 1 — BUILD BINARY (.so)"

case "$BINARY_SOURCE" in
    build)
        log_info "Binary source: ${G}build${NC} (compile locally from source — verifiable)"
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
        log_info "Binary source: ${G}local${NC} (reuse pre-compiled ${LOCAL_SO})"
        [ -f "$LOCAL_SO" ] || { log_err "No compiled binary at ${LOCAL_SO}. Use BINARY_SOURCE=build."; exit 1; }
        cp "$LOCAL_SO" "$BINARY_FILE"
        log_ok "Using pre-compiled local binary."
        ;;
    *)
        log_err "Unknown BINARY_SOURCE='${BINARY_SOURCE}' (valid: build | local)"; exit 1 ;;
esac

BINARY_SZ=$(du -sh "$BINARY_FILE" | cut -f1)
BINARY_BYTES=$(wc -c < "$BINARY_FILE" 2>/dev/null || echo "0")
log_ok "Binary ready: ${C}${BINARY_FILE}${NC} (${BINARY_SZ})"
publish_hash "$BINARY_FILE"

# Capture toolchain versions for the reference record
TC_SOLANA=$(solana --version 2>/dev/null || echo "?")
TC_SBF=$(cargo-build-sbf --version 2>/dev/null | tr '\n' ' ' || echo "?")
MONOREPO_COMMIT=$(git -C "$NET_MONOREPO" rev-parse HEAD 2>/dev/null || echo "unknown")

# ═════════════════════════════════════════════════════════════════════════════
# STEP 2 — DEPLOY PROGRAM (solana program deploy — buffer strategy)
# ═════════════════════════════════════════════════════════════════════════════
log_sep "STEP 2 — DEPLOY PROGRAM"

if [ -n "${SKIP_DEPLOY:-}" ]; then
    log_warn "SKIP_DEPLOY set — build + hash only, not deploying."
    WARP_PROGRAM_ID=""
else
    # Generate or load the program keypair
    if [ ! -f "$PROG_KEYPAIR_FILE" ]; then
        log_info "Generating program keypair..."
        solana-keygen new --no-passphrase --silent --outfile "$PROG_KEYPAIR_FILE" 2>&1 | tee -a "$LOG_FILE"
        log_ok "Keypair created: ${PROG_KEYPAIR_FILE}"
    else
        log_info "Program keypair already exists: ${PROG_KEYPAIR_FILE}"
    fi

    PROG_ID_FROM_KEY=$(keypair_to_pubkey "$PROG_KEYPAIR_FILE" 2>/dev/null || \
                       solana-keygen pubkey "$PROG_KEYPAIR_FILE" 2>/dev/null || echo "")
    [ -z "$PROG_ID_FROM_KEY" ] && { log_err "Could not derive Program ID from keypair!"; exit 1; }
    log_info "Program ID (from keypair): ${G}${PROG_ID_FROM_KEY}${NC}"

    # Check if the program already exists on-chain
    PROG_EXISTS=$(solana program show "$PROG_ID_FROM_KEY" --url "$NET_RPC" 2>/dev/null | grep -c "Program Id" 2>/dev/null || true)
    PROG_EXISTS="${PROG_EXISTS//[^0-9]/}"; PROG_EXISTS="${PROG_EXISTS:-0}"
    if [ "$PROG_EXISTS" -gt 0 ] 2>/dev/null; then
        log_ok "Program already exists on-chain: ${PROG_ID_FROM_KEY}"
        WARP_PROGRAM_ID="$PROG_ID_FROM_KEY"
    else
        BALANCE=$(solana balance "$NET_KEYPAIR" --url "$NET_RPC" 2>/dev/null | awk '{print $1}' || echo "0")
        RENT_EST=$(python3 -c "print(f'~{(${BINARY_BYTES} * 0.00000696):.2f} SOL')" 2>/dev/null || echo "~2-5 SOL")  # ~6.96e-6 SOL/byte (programdata rent, medido)
        log_info "Wallet balance: ${BALANCE} SOL"
        log_info "Estimated binary upload cost: ${RENT_EST}"
        log_warn "This SOL cost is unavoidable — it pays for on-chain program storage."

        echo -ne "  ${W}Proceed with binary deploy? [Y/n]: ${NC}"
        read -r CONF_DEPLOY 2>/dev/null || CONF_DEPLOY="y"
        [[ "${CONF_DEPLOY:-y}" =~ ^[nN]$ ]] && { log "  Cancelled."; exit 0; }

        # Generate buffer keypair if it doesn't exist (reused on retry)
        if [ ! -f "$BUFFER_KEYPAIR_FILE" ]; then
            solana-keygen new --no-passphrase --silent --outfile "$BUFFER_KEYPAIR_FILE" 2>&1 | tee -a "$LOG_FILE"
        else
            log_info "Reusing existing buffer keypair: ${BUFFER_KEYPAIR_FILE}"
        fi
        BUFFER_PUBKEY=$(solana-keygen pubkey "$BUFFER_KEYPAIR_FILE" 2>/dev/null || \
                        keypair_to_pubkey "$BUFFER_KEYPAIR_FILE" 2>/dev/null || echo "")
        log_info "Buffer pubkey: ${BUFFER_PUBKEY:-N/A}"
        log_info "Uploading binary to Solana (~${BINARY_BYTES} bytes)..."
        log ""

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
            log "  Buffer pubkey:  ${BUFFER_PUBKEY:-N/A}"
            log "  Recover SOL:    solana program close ${BUFFER_PUBKEY:-BUFFER} --url ${NET_RPC} --keypair ${NET_KEYPAIR} --buffers"
            exit 1
        fi

        WARP_PROGRAM_ID="$PROG_ID_FROM_KEY"
        log_ok "Program deployed: ${G}${WARP_PROGRAM_ID}${NC}"
    fi
fi

# Convert Program ID to hex32 (required for Terra Classic set_route)
WARP_HEX=""
if [ -n "${WARP_PROGRAM_ID:-}" ]; then
    WARP_HEX=$(b58_to_hex32 "$WARP_PROGRAM_ID")
    [ -z "$WARP_HEX" ] && { log_err "Failed to convert Program ID to hex32!"; exit 1; }
    log_info "Program ID (hex32): 0x${WARP_HEX}"
fi

# ═════════════════════════════════════════════════════════════════════════════
# REFERENCE RECORD — for the community
# ═════════════════════════════════════════════════════════════════════════════
NET_UPPER=$(echo "$NET_KEY" | tr '[:lower:]' '[:upper:]')
REF_TXT="$WORK_DIR/REFERENCE-${NET_UPPER}.txt"
REF_JSON="$WORK_DIR/reference-${NET_KEY}.json"

cat > "$REF_TXT" <<TXT
═══════════════════════════════════════════════════════════
  WARP PROGRAM REFERENCE — ${NET_DISPLAY}
  Generated: $(date '+%Y-%m-%d %H:%M:%S')
═══════════════════════════════════════════════════════════

[BINARY — verify before trusting]
File:            hyperlane_sealevel_token.so
Size (bytes):    ${BINARY_BYTES}
SHA-256:         ${BINARY_SHA256:-N/A}
Verify:          sha256sum ${BINARY_FILE}

[SOURCE / TOOLCHAIN]
Monorepo commit: ${MONOREPO_COMMIT}
Manifest:        ${TOKEN_MANIFEST}
Solana:          ${TC_SOLANA}
Build tool:      ${TC_SBF}

[PROGRAM ON-CHAIN]
Network:         ${NET_DISPLAY} (domain: ${NET_DOMAIN})
Program ID:      ${WARP_PROGRAM_ID:-NOT DEPLOYED}
Program ID hex:  ${WARP_HEX:+0x${WARP_HEX}}
Upgrade auth:    $(keypair_to_pubkey "$NET_KEYPAIR" 2>/dev/null || solana-keygen pubkey "$NET_KEYPAIR" 2>/dev/null || echo "N/A")
RPC:             ${NET_RPC}
Explorer:        ${NET_EXPLORER}/address/${WARP_PROGRAM_ID:-}

[NEXT STEP — configure the warp route with THIS program]
export WARP_PROGRAM_ID=${WARP_PROGRAM_ID:-<program id>}
./deploy-warp-solana-buffer.sh
TXT

cat > "$REF_JSON" <<JSON
{
  "network": "${NET_KEY}",
  "display_name": "${NET_DISPLAY}",
  "domain": ${NET_DOMAIN:-0},
  "program_id": "${WARP_PROGRAM_ID:-}",
  "program_hex": "${WARP_HEX:+0x${WARP_HEX}}",
  "binary_sha256": "${BINARY_SHA256:-}",
  "binary_bytes": ${BINARY_BYTES:-0},
  "monorepo_commit": "${MONOREPO_COMMIT}",
  "solana_version": "${TC_SOLANA}",
  "generated": "$(date -Iseconds)"
}
JSON

log_ok "Reference saved: ${C}${REF_TXT}${NC}"
log_ok "Reference JSON:  ${C}${REF_JSON}${NC}"

# ═════════════════════════════════════════════════════════════════════════════
# FINAL SUMMARY
# ═════════════════════════════════════════════════════════════════════════════
log ""
log "╔══════════════════════════════════════════════════════════════════════════╗"
log "║          ✅  WARP PROGRAM CREATED — SHARE THE REFERENCE BELOW           ║"
log "╚══════════════════════════════════════════════════════════════════════════╝"
log ""
log "  ${G}Network:${NC}      ${NET_DISPLAY} (domain ${NET_DOMAIN})"
[ -n "${WARP_PROGRAM_ID:-}" ] && log "  ${G}Program ID:${NC}   ${WARP_PROGRAM_ID}"
[ -n "${WARP_HEX:-}" ]        && log "  ${G}Hex32:${NC}        0x${WARP_HEX}"
log "  ${G}SHA-256:${NC}      ${BINARY_SHA256:-N/A}"
log "  ${G}Commit:${NC}       ${MONOREPO_COMMIT}"
log ""
log "  ${W}Community verification:${NC}"
log "    sha256sum ${BINARY_FILE}"
log "    → must equal ${BINARY_SHA256:-N/A}"
log ""
log "  ${W}Wire the warp route to this program:${NC}"
log "    export WARP_PROGRAM_ID=${WARP_PROGRAM_ID:-<program id>}"
log "    ./deploy-warp-solana-buffer.sh"
log ""
log "${B}📄 Reference: ${REF_TXT}${NC}"
log "${B}📋 Log:       ${LOG_FILE}${NC}"
