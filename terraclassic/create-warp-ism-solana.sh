#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
#  🔐  CREATE WARP ISM (SEALEVEL) — community multisig ISM for Terra Classic
# ═══════════════════════════════════════════════════════════════════════════════
#
#  WHY:
#    The default Hyperlane multisig ISM on Solana (LwNfVY...) has NO entry for the
#    Terra Classic domain and is owned by Abacus Works. A community-run route needs
#    its OWN ISM, configured with the Terra Classic validators, under community
#    ownership.
#
#  WHAT (this script ONLY handles the ISM — IGP is a separate script):
#    1. Compile the multisig-ism-message-id program locally (verifiable) + hash
#    2. Deploy it → community ISM Program ID (your own upgrade authority)
#    3. Init the ISM (access-control PDA, owner = your keypair)
#    4. Set validators + threshold for the Terra Classic domain
#    5. Write ism.program_id into warp-sealevel-config.json
#    6. (optional) Point an existing warp token at this ISM
#
#  This REPLACES dumping bytecode from a third-party ISM: you build your own binary,
#  publish its SHA-256, and everyone can verify it.  See doc/archive/WARP-SOLANA-BINARY-REFERENCE.md
#
#  Usage:
#    ./create-warp-ism-solana.sh
#
#  Optional environment variables:
#    NET_KEY=<solanamainnet|solanatestnet|...>  → network (default: solanamainnet)
#    BINARY_SOURCE=build|local                  → compile (default) or reuse target/deploy/*.so
#    ISM_VALIDATORS=0x..,0x..                   → override validators (comma-separated)
#    ISM_THRESHOLD=<n>                          → override threshold
#    ISM_PROGRAM_ID=<addr>                      → reuse an existing ISM (skip build+deploy)
#    LINK_WARP=1                                → also set this ISM on the warp token
#    WARP_TOKEN=<key>                           → warp token key to link (default: igorfake)
#    SKIP_DEPLOY=1 / SKIP_INIT=1 / SKIP_VALIDATORS=1 / SKIP_CONFIG_WRITE=1
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

# Ensure the Solana toolchain (solana, solana-keygen, cargo-build-sbf) is on PATH.
# A terminal opened before the install — or a non-login shell — may miss it.
_SOLANA_BIN="$HOME/.local/share/solana/install/active_release/bin"
[ -d "$_SOLANA_BIN" ] && case ":$PATH:" in *":$_SOLANA_BIN:"*) ;; *) export PATH="$_SOLANA_BIN:$PATH" ;; esac

# ── COLORS ───────────────────────────────────────────────────────────────────
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'
B='\033[0;34m'; C='\033[0;36m'; W='\033[1m'; NC='\033[0m'
OK="${G}✅${NC}"; ERR="${R}❌${NC}"; WARN="${Y}⚠️ ${NC}"; INFO="${B}ℹ️ ${NC}"

# ── PATHS ────────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOL_CONFIG="$SCRIPT_DIR/warp-sealevel-config.json"
EVM_CONFIG="$SCRIPT_DIR/warp-evm-config.json"
LOG_DIR="$SCRIPT_DIR/log"; mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/create-warp-ism-solana.log"

NET_KEY="${NET_KEY:-solanamainnet}"
BINARY_SOURCE="${BINARY_SOURCE:-build}"
WARP_TOKEN="${WARP_TOKEN:-igorfake}"

# ── LOGGING ──────────────────────────────────────────────────────────────────
log()      { echo -e "$@" | tee -a "$LOG_FILE"; }
log_ok()   { log "${OK} $*"; }
log_err()  { log "${ERR} $*"; }
log_warn() { log "${WARN} $*"; }
log_info() { log "${INFO} $*"; }
log_sep()  { log ""; log "${C}${W}$1${NC}"; log "────────────────────────────────────────────────────────────────"; }

sol_cfg()  { jq -r "$1" "$SOL_CONFIG" 2>/dev/null || echo ""; }
evm_cfg()  { jq -r "$1" "$EVM_CONFIG" 2>/dev/null || echo ""; }

keypair_to_pubkey() {
    python3 - "$1" <<'PY' 2>/dev/null
import json,sys
try:
    data=json.load(open(sys.argv[1])); pub=bytes(data[32:64])
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

# Records the .so SHA-256 next to it and prints it (community verification)
publish_hash() {
    local so="$1"; [ -f "$so" ] || return 0
    local sum; sum=$(sha256sum "$so" | awk '{print $1}')
    echo "$sum  $(basename "$so")" > "${so}.sha256"; BINARY_SHA256="$sum"
    log_ok "SHA-256: ${G}${sum}${NC}"
    log_info "Hash saved: ${so}.sha256 — verify with: ${Y}sha256sum ${so}${NC}"
}

# ── BANNER ───────────────────────────────────────────────────────────────────
> "$LOG_FILE"; clear 2>/dev/null || true
log "╔══════════════════════════════════════════════════════════════════════════╗"
log "║  🔐  CREATE WARP ISM (SEALEVEL) — community multisig ISM                ║"
log "║  Date: $(date '+%Y-%m-%d %H:%M:%S')                                         ║"
log "╚══════════════════════════════════════════════════════════════════════════╝"

# ── CHECKS ───────────────────────────────────────────────────────────────────
[ -f "$SOL_CONFIG" ] || { log_err "Not found: $SOL_CONFIG"; exit 1; }
jq empty "$SOL_CONFIG" 2>/dev/null || { log_err "Invalid JSON: $SOL_CONFIG"; exit 1; }
for cmd in jq python3 solana solana-keygen cargo; do
    command -v $cmd &>/dev/null || { log_err "$cmd is required"; exit 1; }
done
[ "$BINARY_SOURCE" = "build" ] && { command -v cargo-build-sbf &>/dev/null || { log_err "cargo-build-sbf required for BINARY_SOURCE=build"; exit 1; }; }

# ── LOAD NETWORK CONFIG ──────────────────────────────────────────────────────
N=".networks.${NET_KEY}"
NET_DISPLAY=$(sol_cfg "${N}.display_name")
NET_RPC=$(sol_cfg     "${N}.rpc")
NET_KEYPAIR=$(sol_cfg "${N}.keypair" | sed "s|^~|$HOME|")
NET_MONOREPO=$(sol_cfg "${N}.monorepo_dir" | sed "s|^~|$HOME|")
WARP_PROGRAM_ID=$(sol_cfg "${N}.warp_tokens.${WARP_TOKEN}.program_id")

echo "$NET_RPC" | grep -q "YOUR_HELIUS_API_KEY" && {
    log_warn "Helius key placeholder — falling back to public RPC"
    NET_RPC="https://api.mainnet-beta.solana.com"; }

[ -f "$NET_KEYPAIR" ]  || { log_err "Keypair not found: ${NET_KEYPAIR:-unset}"; exit 1; }
[ -d "$NET_MONOREPO" ] || { log_err "Monorepo not found: ${NET_MONOREPO:-unset}"; exit 1; }

# Terra Classic domain + validators (community inputs — override via env vars)
# Terra domain: explicit env override (testnet launcher passes 1325) wins over config (mainnet 132556)
[ -z "${TERRA_DOMAIN:-}" ] && { TERRA_DOMAIN=$(evm_cfg '.terra_classic.domain'); TERRA_DOMAIN="${TERRA_DOMAIN:-132556}"; }
ISM_VALIDATORS="${ISM_VALIDATORS:-0x71b2b8c36a0c76b74be92eb7915e26a69b3b03eb}"
ISM_THRESHOLD="${ISM_THRESHOLD:-1}"

# Client binary (fall back to cargo run if not pre-built)
CLIENT_BIN="$NET_MONOREPO/target/release/hyperlane-sealevel-client"
CLIENT_DIR="$NET_MONOREPO/client"
run_client() {
    if [ -x "$CLIENT_BIN" ]; then "$CLIENT_BIN" "$@"
    else ( cd "$CLIENT_DIR" && cargo run --release --quiet -- "$@" ); fi
}

# Build paths
BUILT_SO_DIR="$NET_MONOREPO/target/deploy"
LOCAL_SO="$BUILT_SO_DIR/hyperlane_sealevel_multisig_ism_message_id.so"
ISM_MANIFEST="$NET_MONOREPO/programs/ism/multisig-ism-message-id/Cargo.toml"

WORK_DIR="$SCRIPT_DIR/warp/${NET_KEY}/ism"
KEYS_DIR="$WORK_DIR/keys"; mkdir -p "$KEYS_DIR"
BINARY_FILE="$WORK_DIR/hyperlane_sealevel_multisig_ism_message_id.so"
ISM_KEYPAIR_FILE="$KEYS_DIR/ism-terraclassic-${NET_KEY}-keypair.json"

PAYER_PUBKEY=$(keypair_to_pubkey "$NET_KEYPAIR" 2>/dev/null || solana-keygen pubkey "$NET_KEYPAIR" 2>/dev/null || echo "?")
BALANCE=$(solana balance "$NET_KEYPAIR" --url "$NET_RPC" 2>/dev/null | awk '{print $1}' || echo "?")

log_ok "Network:    ${C}${NET_KEY}${NC} — ${NET_DISPLAY}"
log_info "Payer:      ${PAYER_PUBKEY} (balance: ${BALANCE} SOL)"
log_info "Terra dom:  ${TERRA_DOMAIN}"
log_info "Validators: ${ISM_VALIDATORS} (threshold ${ISM_THRESHOLD})"
log_info "RPC:        ${NET_RPC}"
[ -n "${ISM_PROGRAM_ID:-}" ] && log_info "Reusing ISM: ${ISM_PROGRAM_ID} (build+deploy skipped)"
log ""
echo -ne "  ${W}Confirm and continue? [Y/n]: ${NC}"; read -r CONFIRM 2>/dev/null || CONFIRM="y"
[[ "${CONFIRM:-y}" =~ ^[nN]$ ]] && { log "  Cancelled."; exit 0; }

# ═════════════════════════════════════════════════════════════════════════════
# STEP 1 — BUILD BINARY (.so) — local build (community-verifiable)
# ═════════════════════════════════════════════════════════════════════════════
log_sep "STEP 1 — BUILD ISM BINARY (.so)"

if [ -n "${ISM_PROGRAM_ID:-}" ]; then
    log_warn "ISM_PROGRAM_ID set — skipping build."
else
    case "$BINARY_SOURCE" in
        build)
            log_info "Binary source: ${G}build${NC} (compile from source — verifiable)"
            [ -f "$ISM_MANIFEST" ] || { log_err "Manifest not found: $ISM_MANIFEST"; exit 1; }
            log_info "Compiling: ${C}cargo build-sbf --manifest-path ${ISM_MANIFEST}${NC}"
            log_warn "First build may take ~15-20 min (BPF); cached afterwards."
            log ""
            set +e
            ( cd "$NET_MONOREPO" && cargo build-sbf --manifest-path "$ISM_MANIFEST" ) 2>&1 | tee -a "$LOG_FILE"
            BUILD_EXIT=${PIPESTATUS[0]}
            set -e
            { [ $BUILD_EXIT -ne 0 ] || [ ! -f "$LOCAL_SO" ]; } && { log_err "Build failed (exit $BUILD_EXIT)."; exit 1; }
            cp "$LOCAL_SO" "$BINARY_FILE"; log_ok "Compiled locally from source."
            ;;
        local)
            log_info "Binary source: ${G}local${NC} (reuse ${LOCAL_SO})"
            [ -f "$LOCAL_SO" ] || { log_err "No compiled binary at ${LOCAL_SO}. Use BINARY_SOURCE=build."; exit 1; }
            cp "$LOCAL_SO" "$BINARY_FILE"; log_ok "Using pre-compiled local binary."
            ;;
        *) log_err "Unknown BINARY_SOURCE='${BINARY_SOURCE}' (valid: build | local)"; exit 1 ;;
    esac
    log_ok "Binary ready: ${C}${BINARY_FILE}${NC} ($(du -sh "$BINARY_FILE" | cut -f1))"
    publish_hash "$BINARY_FILE"
fi

# ═════════════════════════════════════════════════════════════════════════════
# STEP 2 — DEPLOY ISM PROGRAM
# ═════════════════════════════════════════════════════════════════════════════
log_sep "STEP 2 — DEPLOY ISM PROGRAM"

if [ -n "${ISM_PROGRAM_ID:-}" ]; then
    log_warn "Using provided ISM_PROGRAM_ID=${ISM_PROGRAM_ID}"
elif [ -n "${SKIP_DEPLOY:-}" ]; then
    log_warn "SKIP_DEPLOY set — skipping deploy."
else
    if [ ! -f "$ISM_KEYPAIR_FILE" ]; then
        solana-keygen new --no-passphrase --silent --outfile "$ISM_KEYPAIR_FILE" 2>&1 | tee -a "$LOG_FILE"
        log_ok "ISM keypair created: $ISM_KEYPAIR_FILE"
    else
        log_info "Reusing ISM keypair: $ISM_KEYPAIR_FILE"
    fi
    ISM_PROGRAM_ID=$(keypair_to_pubkey "$ISM_KEYPAIR_FILE" 2>/dev/null || solana-keygen pubkey "$ISM_KEYPAIR_FILE")
    log_info "ISM Program ID: ${G}${ISM_PROGRAM_ID}${NC}"

    PROG_EXISTS=$(solana program show "$ISM_PROGRAM_ID" --url "$NET_RPC" 2>/dev/null | grep -c "Program Id" || true)
    PROG_EXISTS="${PROG_EXISTS//[^0-9]/}"; PROG_EXISTS="${PROG_EXISTS:-0}"
    if [ "$PROG_EXISTS" -gt 0 ] 2>/dev/null; then
        log_ok "ISM program already on-chain: $ISM_PROGRAM_ID"
    else
        echo -ne "  ${W}Deploy ISM binary now (~2-3 SOL)? [Y/n]: ${NC}"; read -r C2 2>/dev/null || C2="y"
        [[ "${C2:-y}" =~ ^[nN]$ ]] && { log "  Cancelled."; exit 0; }
        set +e
        solana program deploy "$BINARY_FILE" \
            --url "$NET_RPC" --keypair "$NET_KEYPAIR" \
            --program-id "$ISM_KEYPAIR_FILE" --upgrade-authority "$NET_KEYPAIR" \
            2>&1 | tee -a "$LOG_FILE"
        DEPLOY_EXIT=$?
        set -e
        [ $DEPLOY_EXIT -ne 0 ] && { log_err "ISM deploy failed! Re-run to resume, or reuse with ISM_PROGRAM_ID=<addr>."; exit 1; }
        log_ok "ISM program deployed: ${G}${ISM_PROGRAM_ID}${NC}"
    fi
fi
[ -n "${ISM_PROGRAM_ID:-}" ] || { log_err "No ISM Program ID resolved."; exit 1; }

# ═════════════════════════════════════════════════════════════════════════════
# STEP 3 — INIT ISM (access-control PDA, owner = keypair)
# ═════════════════════════════════════════════════════════════════════════════
log_sep "STEP 3 — INIT ISM"

if [ -n "${SKIP_INIT:-}" ]; then
    log_warn "SKIP_INIT set — skipping."
else
    set +e
    OUT=$(run_client -k "$NET_KEYPAIR" -u "$NET_RPC" \
        multisig-ism-message-id init --program-id "$ISM_PROGRAM_ID" 2>&1)
    EXIT=$?; set -e
    echo "$OUT" | tee -a "$LOG_FILE"
    if [ $EXIT -eq 0 ]; then log_ok "ISM initialized."
    elif echo "$OUT" | grep -qiE "already|exists"; then log_ok "ISM already initialized."
    else log_warn "ISM init exit $EXIT — may already be initialized, continuing."; fi
fi

# ═════════════════════════════════════════════════════════════════════════════
# STEP 4 — SET VALIDATORS + THRESHOLD FOR TERRA CLASSIC DOMAIN
# ═════════════════════════════════════════════════════════════════════════════
log_sep "STEP 4 — SET VALIDATORS FOR DOMAIN ${TERRA_DOMAIN}"

if [ -n "${SKIP_VALIDATORS:-}" ]; then
    log_warn "SKIP_VALIDATORS set — skipping."
else
    set +e
    OUT=$(run_client -k "$NET_KEYPAIR" -u "$NET_RPC" \
        multisig-ism-message-id set-validators-and-threshold \
        --program-id "$ISM_PROGRAM_ID" \
        --domain "$TERRA_DOMAIN" \
        --validators "$ISM_VALIDATORS" \
        --threshold "$ISM_THRESHOLD" 2>&1)
    EXIT=$?; set -e
    echo "$OUT" | tee -a "$LOG_FILE"
    if [ $EXIT -eq 0 ]; then log_ok "Validators set: ${ISM_VALIDATORS} (threshold ${ISM_THRESHOLD})"
    elif echo "$OUT" | grep -qiE "already|same"; then log_ok "Validators already configured."
    else
        log_err "Failed to set validators (exit $EXIT)"
        log "  Manual: $CLIENT_BIN -k $NET_KEYPAIR -u $NET_RPC multisig-ism-message-id set-validators-and-threshold --program-id $ISM_PROGRAM_ID --domain $TERRA_DOMAIN --validators $ISM_VALIDATORS --threshold $ISM_THRESHOLD"
        exit 1
    fi
    log_info "Verifying domain ${TERRA_DOMAIN}..."
    run_client -k "$NET_KEYPAIR" -u "$NET_RPC" \
        multisig-ism-message-id query --program-id "$ISM_PROGRAM_ID" --domains "$TERRA_DOMAIN" 2>&1 \
        | grep -iE "domain|validator|threshold|No domain" | tee -a "$LOG_FILE" || true
fi

# ═════════════════════════════════════════════════════════════════════════════
# STEP 5 — WRITE ism.program_id INTO warp-sealevel-config.json
# ═════════════════════════════════════════════════════════════════════════════
log_sep "STEP 5 — UPDATE warp-sealevel-config.json"

if [ -n "${SKIP_CONFIG_WRITE:-}" ]; then
    log_warn "SKIP_CONFIG_WRITE set — not touching config."
else
    TMP=$(mktemp)
    jq ".networks.\"${NET_KEY}\".ism.program_id = \"${ISM_PROGRAM_ID}\"" "$SOL_CONFIG" > "$TMP" && mv "$TMP" "$SOL_CONFIG"
    log_ok "ism.program_id = ${ISM_PROGRAM_ID}"
fi

# ═════════════════════════════════════════════════════════════════════════════
# STEP 6 — (optional) POINT WARP TOKEN AT THIS ISM
# ═════════════════════════════════════════════════════════════════════════════
if [ -n "${LINK_WARP:-}" ] && [ -n "$WARP_PROGRAM_ID" ] && [ "$WARP_PROGRAM_ID" != "null" ]; then
    log_sep "STEP 6 — SET ISM ON WARP TOKEN (${WARP_TOKEN})"
    set +e
    OUT=$(run_client -k "$NET_KEYPAIR" -u "$NET_RPC" \
        token set-interchain-security-module --program-id "$WARP_PROGRAM_ID" --ism "$ISM_PROGRAM_ID" 2>&1)
    EXIT=$?; set -e
    echo "$OUT" | tee -a "$LOG_FILE"
    if [ $EXIT -eq 0 ]; then log_ok "Warp token ISM set: $ISM_PROGRAM_ID"
    elif echo "$OUT" | grep -qiE "already|same"; then log_ok "Warp token ISM already set."
    else log_warn "Failed to set ISM on warp token (exit $EXIT). Set it during warp init instead."; fi
else
    log_info "Not linking to a warp token (set LINK_WARP=1 + a deployed WARP_TOKEN to do so)."
    log_info "The warp init (deploy-warp-solana-buffer.sh) will read ism.program_id from config."
fi

# ── REFERENCE + SUMMARY ──────────────────────────────────────────────────────
REF="$WORK_DIR/REFERENCE-ISM-$(echo "$NET_KEY" | tr a-z A-Z).txt"
cat > "$REF" <<TXT
═══════════════════════════════════════════════════════════
  COMMUNITY ISM — ${NET_DISPLAY}
  Generated: $(date '+%Y-%m-%d %H:%M:%S')
═══════════════════════════════════════════════════════════
Program (multisig-ism-message-id)
  Program ID:     ${ISM_PROGRAM_ID}
  Binary SHA-256: ${BINARY_SHA256:-N/A (reused existing program)}
  Owner/upgrade:  ${PAYER_PUBKEY}
Terra Classic (domain ${TERRA_DOMAIN})
  Validators:     ${ISM_VALIDATORS}
  Threshold:      ${ISM_THRESHOLD}
Verify binary:    sha256sum ${BINARY_FILE}
Query on-chain:   ${CLIENT_BIN} -k ${NET_KEYPAIR} -u ${NET_RPC} multisig-ism-message-id query --program-id ${ISM_PROGRAM_ID} --domains ${TERRA_DOMAIN}
TXT

log ""
log "╔══════════════════════════════════════════════════════════════════════════╗"
log "║          ✅  COMMUNITY ISM READY                                        ║"
log "╚══════════════════════════════════════════════════════════════════════════╝"
log "  ${G}ISM Program:${NC}  ${ISM_PROGRAM_ID}"
log "  ${G}SHA-256:${NC}      ${BINARY_SHA256:-N/A}"
log "  ${G}Domain:${NC}       ${TERRA_DOMAIN} — validators ${ISM_VALIDATORS} (threshold ${ISM_THRESHOLD})"
log ""
log "  Next: deploy the IGP → ${Y}./create-warp-igp-solana.sh${NC}"
log "        then warp init  → ${Y}./deploy-warp-solana-buffer.sh${NC} (reads ism.program_id from config)"
log ""
log "${B}📄 Reference: ${REF}${NC}"
log "${B}📋 Log:       ${LOG_FILE}${NC}"
