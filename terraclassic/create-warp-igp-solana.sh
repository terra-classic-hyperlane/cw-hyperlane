#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
#  ⛽  CREATE WARP IGP (SEALEVEL) — community IGP + gas oracle for Terra Classic
# ═══════════════════════════════════════════════════════════════════════════════
#
#  WHY:
#    The default Hyperlane IGP on Solana (BhNcatUDC...) has NO gas oracle for the
#    Terra Classic domain and is owned by Abacus Works. A community-run route needs
#    its OWN IGP account + oracle (and, by default here, its own IGP program) so it
#    can quote gas for Solana → Terra Classic transfers under community ownership.
#
#  WHAT (this script ONLY handles the IGP — ISM is a separate script):
#    1. Compile the IGP program locally (verifiable) + hash
#    2. Deploy a NEW community IGP program (or reuse one via REUSE_IGP_PROGRAM_ID)
#    3. Init an IGP account + an overhead-IGP account (owner = your keypair)
#    4. Set the gas oracle + destination gas overhead for the Terra Classic domain
#    5. Write igp.program_id + igp.account into warp-sealevel-config.json
#    6. (optional) Point an existing warp token at this IGP
#
#  This REPLACES trusting the shared Hyperlane IGP: you build your own binary,
#  publish its SHA-256, and everyone can verify it.  See doc/WARP-SOLANA-BINARY-REFERENCE.md
#
#  Usage:
#    ./create-warp-igp-solana.sh
#
#  Optional environment variables:
#    NET_KEY=<solanamainnet|...>        → network (default: solanamainnet)
#    BINARY_SOURCE=build|local          → compile (default) or reuse target/deploy/*.so
#    REUSE_IGP_PROGRAM_ID=<addr>        → reuse an existing IGP program (skip build+deploy),
#                                          only create community accounts + oracle
#    IGP_SALT=<name>                    → salt/context for the IGP account (default: tc-community)
#    ORACLE_EXCHANGE_RATE / ORACLE_GAS_PRICE / ORACLE_TOKEN_DECIMALS / GAS_OVERHEAD → oracle params
#    LINK_WARP=1                        → also set this IGP on the warp token
#    WARP_TOKEN=<key>                   → warp token key to link (default: igorfake)
#    SKIP_DEPLOY / SKIP_ACCOUNTS / SKIP_ORACLE / SKIP_CONFIG_WRITE=1
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
LOG_FILE="$LOG_DIR/create-warp-igp-solana.log"

NET_KEY="${NET_KEY:-solanamainnet}"
BINARY_SOURCE="${BINARY_SOURCE:-build}"
WARP_TOKEN="${WARP_TOKEN:-igorfake}"
IGP_SALT="${IGP_SALT:-tc-community}"

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
log "║  ⛽  CREATE WARP IGP (SEALEVEL) — community IGP + gas oracle            ║"
log "║  Date: $(date '+%Y-%m-%d %H:%M:%S')                                         ║"
log "╚══════════════════════════════════════════════════════════════════════════╝"

# ── CHECKS ───────────────────────────────────────────────────────────────────
[ -f "$SOL_CONFIG" ] || { log_err "Not found: $SOL_CONFIG"; exit 1; }
jq empty "$SOL_CONFIG" 2>/dev/null || { log_err "Invalid JSON: $SOL_CONFIG"; exit 1; }
for cmd in jq python3 solana solana-keygen cargo; do
    command -v $cmd &>/dev/null || { log_err "$cmd is required"; exit 1; }
done
[ "$BINARY_SOURCE" = "build" ] && [ -z "${REUSE_IGP_PROGRAM_ID:-}" ] && {
    command -v cargo-build-sbf &>/dev/null || { log_err "cargo-build-sbf required for BINARY_SOURCE=build"; exit 1; }; }

# ── LOAD NETWORK CONFIG ──────────────────────────────────────────────────────
N=".networks.${NET_KEY}"
NET_DISPLAY=$(sol_cfg "${N}.display_name")
NET_ENV=$(sol_cfg     "${N}.environment")
NET_RPC="${NET_RPC:-$(sol_cfg "${N}.rpc")}"   # env override wins over config (better RPC for congested public nodes)
NET_KEYPAIR=$(sol_cfg "${N}.keypair" | sed "s|^~|$HOME|")
NET_MONOREPO=$(sol_cfg "${N}.monorepo_dir" | sed "s|^~|$HOME|")
MAILBOX=$(sol_cfg     "${N}.mailbox")
VALIDATOR_ANNOUNCE=$(sol_cfg "${N}.validator_announce")   # required by CoreProgramIds schema (client)
CFG_ISM=$(sol_cfg     "${N}.ism.program_id")
WARP_PROGRAM_ID=$(sol_cfg "${N}.warp_tokens.${WARP_TOKEN}.program_id")

echo "$NET_RPC" | grep -q "YOUR_HELIUS_API_KEY" && {
    log_warn "Helius key placeholder — falling back to public RPC"
    NET_RPC="https://api.mainnet-beta.solana.com"; }

[ -f "$NET_KEYPAIR" ]  || { log_err "Keypair not found: ${NET_KEYPAIR:-unset}"; exit 1; }
[ -d "$NET_MONOREPO" ] || { log_err "Monorepo not found: ${NET_MONOREPO:-unset}"; exit 1; }

# Terra Classic domain + oracle params (community inputs — override via env vars)
# Terra domain: explicit env override (testnet launcher passes 1325) wins over config (mainnet 132556)
[ -z "${TERRA_DOMAIN:-}" ] && { TERRA_DOMAIN=$(evm_cfg '.terra_classic.domain'); TERRA_DOMAIN="${TERRA_DOMAIN:-132556}"; }
# ─────────────────────────────────────────────────────────────────────────────
# FÓRMULA REAL do quote sealevel (validada on-chain, 2026-07-09; scale rust = 1e19):
#   lamports = (gas_amount + GAS_OVERHEAD) × ORACLE_GAS_PRICE × ORACLE_EXCHANGE_RATE / 1e19 × 10^(9 − DECIMALS)
# Para CALIBRAR pelo preço-alvo em lamports (ex.: US$0.02 → alvo = 0.02/SOL_USD × 1e9):
#   ORACLE_EXCHANGE_RATE = alvo_lamports × 1e19 / ((100000 + GAS_OVERHEAD) × ORACLE_GAS_PRICE × 10^(9 − DECIMALS))
# Default 29400000000 ⇒ ~0.000258 SOL ≈ US$0.02 (SOL $77 / LUNC $0.00006, 2026-07-09).
# ⚠️ O antigo default 1e12 (e o 2e13 usado no 1º deploy) davam US$0.68–13.60 por volta — recalibre ao mudar preços!
# ─────────────────────────────────────────────────────────────────────────────
ORACLE_EXCHANGE_RATE="${ORACLE_EXCHANGE_RATE:-29400000000}"
ORACLE_GAS_PRICE="${ORACLE_GAS_PRICE:-28325}"                  # uluna per gas unit
ORACLE_TOKEN_DECIMALS="${ORACLE_TOKEN_DECIMALS:-6}"           # uluna
GAS_OVERHEAD="${GAS_OVERHEAD:-3000000}"                        # overhead gas units
# Estimativa de preço da volta com estes parâmetros (aviso se ficar caro):
EST_LAMPORTS=$(python3 -c "print(int((100000+${GAS_OVERHEAD})*${ORACLE_GAS_PRICE}*${ORACLE_EXCHANGE_RATE}/1e19*10**(9-${ORACLE_TOKEN_DECIMALS})))")
EST_SOL=$(python3 -c "print(f'{${EST_LAMPORTS}/1e9:.6f}')")
echo "ℹ️  Estimated RETURN fee with these params: ~${EST_SOL} SOL (${EST_LAMPORTS} lamports)"
python3 -c "exit(0 if ${EST_LAMPORTS} < 10_000_000 else 1)" || \
  echo "⚠️  WARNING: return fee > 0.01 SOL — provavelmente CARO DEMAIS. Recalibre ORACLE_EXCHANGE_RATE (fórmula acima)."

CLIENT_BIN="$NET_MONOREPO/target/release/hyperlane-sealevel-client"
CLIENT_DIR="$NET_MONOREPO/client"
run_client() {
    if [ -x "$CLIENT_BIN" ]; then "$CLIENT_BIN" "$@"
    else ( cd "$CLIENT_DIR" && cargo run --release --quiet -- "$@" ); fi
}

BUILT_SO_DIR="$NET_MONOREPO/target/deploy"
LOCAL_SO="$BUILT_SO_DIR/hyperlane_sealevel_igp.so"
IGP_MANIFEST="$NET_MONOREPO/programs/hyperlane-sealevel-igp/Cargo.toml"

WORK_DIR="$SCRIPT_DIR/warp/${NET_KEY}/igp"
mkdir -p "$WORK_DIR"
BINARY_FILE="$WORK_DIR/hyperlane_sealevel_igp.so"

# Custom environment dir so the client can read/write our IGP program-ids + accounts
CUSTOM_ENV="mainnet-tc-community"
ENVIRONMENTS_BASE="$NET_MONOREPO/environments"
CUSTOM_CORE_DIR="$ENVIRONMENTS_BASE/${CUSTOM_ENV}/${NET_KEY}/core"
mkdir -p "$CUSTOM_CORE_DIR"

PAYER_PUBKEY=$(keypair_to_pubkey "$NET_KEYPAIR" 2>/dev/null || solana-keygen pubkey "$NET_KEYPAIR" 2>/dev/null || echo "?")
BALANCE=$(solana balance "$NET_KEYPAIR" --url "$NET_RPC" 2>/dev/null | awk '{print $1}' || echo "?")

log_ok "Network:    ${C}${NET_KEY}${NC} — ${NET_DISPLAY}"
log_info "Payer:      ${PAYER_PUBKEY} (balance: ${BALANCE} SOL)"
log_info "Terra dom:  ${TERRA_DOMAIN}"
log_info "Oracle:     rate=${ORACLE_EXCHANGE_RATE} gas_price=${ORACLE_GAS_PRICE} decimals=${ORACLE_TOKEN_DECIMALS} overhead=${GAS_OVERHEAD}"
log_info "RPC:        ${NET_RPC}"
[ -n "${REUSE_IGP_PROGRAM_ID:-}" ] && log_info "Reusing IGP program: ${REUSE_IGP_PROGRAM_ID} (build+deploy skipped)"
log ""
echo -ne "  ${W}Confirm and continue? [Y/n]: ${NC}"; read -r CONFIRM 2>/dev/null || CONFIRM="y"
[[ "${CONFIRM:-y}" =~ ^[nN]$ ]] && { log "  Cancelled."; exit 0; }

# ═════════════════════════════════════════════════════════════════════════════
# STEP 1 — BUILD IGP BINARY (.so) — local build (community-verifiable)
# ═════════════════════════════════════════════════════════════════════════════
log_sep "STEP 1 — BUILD IGP BINARY (.so)"

if [ -n "${REUSE_IGP_PROGRAM_ID:-}" ]; then
    log_warn "REUSE_IGP_PROGRAM_ID set — skipping build."
else
    case "$BINARY_SOURCE" in
        build)
            log_info "Binary source: ${G}build${NC} (compile from source — verifiable)"
            [ -f "$IGP_MANIFEST" ] || { log_err "Manifest not found: $IGP_MANIFEST"; exit 1; }
            log_info "Compiling: ${C}cargo build-sbf --manifest-path ${IGP_MANIFEST}${NC}"
            log_warn "First build may take ~15-20 min (BPF); cached afterwards."
            log ""
            set +e
            ( cd "$NET_MONOREPO" && cargo build-sbf --manifest-path "$IGP_MANIFEST" ) 2>&1 | tee -a "$LOG_FILE"
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
# STEP 2 — DEPLOY IGP PROGRAM (client deploy-program: deploys OUR .so + inits data)
# ═════════════════════════════════════════════════════════════════════════════
log_sep "STEP 2 — DEPLOY IGP PROGRAM"

if [ -n "${REUSE_IGP_PROGRAM_ID:-}" ]; then
    IGP_PROGRAM_ID="$REUSE_IGP_PROGRAM_ID"
    log_warn "Using provided IGP program: $IGP_PROGRAM_ID"
elif [ -n "${SKIP_DEPLOY:-}" ]; then
    log_warn "SKIP_DEPLOY set — reading igp_program_id from custom env."
    IGP_PROGRAM_ID=$(jq -r '.igp_program_id // ""' "$CUSTOM_CORE_DIR/program-ids.json" 2>/dev/null || echo "")
else
    echo -ne "  ${W}Deploy a NEW IGP program now (~2-3 SOL)? [Y/n]: ${NC}"; read -r C2 2>/dev/null || C2="y"
    [[ "${C2:-y}" =~ ^[nN]$ ]] && { log "  Cancelled."; exit 0; }
    # deploy-program deploys built_so_dir/hyperlane_sealevel_igp.so and inits program data.
    # Point --built-so-dir at OUR verified binary's directory.
    OUR_SO_DIR="$WORK_DIR"; cp "$BINARY_FILE" "$OUR_SO_DIR/hyperlane_sealevel_igp.so" 2>/dev/null || true
    log_info "Deploying IGP program (this streams live; a program deploy can take a few minutes)..."
    _T=$(mktemp)
    set +e
    run_client -k "$NET_KEYPAIR" -u "$NET_RPC" \
        igp deploy-program \
        --environment "$CUSTOM_ENV" \
        --environments-dir "$ENVIRONMENTS_BASE" \
        --chain "$NET_KEY" \
        --built-so-dir "$OUR_SO_DIR" 2>&1 | tee -a "$LOG_FILE" "$_T"
    EXIT=${PIPESTATUS[0]}; set -e
    OUT=$(cat "$_T"); rm -f "$_T"
    IGP_PROGRAM_ID=$(echo "$OUT" | grep -oiE "program ID [1-9A-HJ-NP-Za-km-z]{32,44}" | grep -oE "[1-9A-HJ-NP-Za-km-z]{32,44}" | tail -1 || echo "")
    [ -z "$IGP_PROGRAM_ID" ] && IGP_PROGRAM_ID=$(jq -r '.igp_program_id // ""' "$ENVIRONMENTS_BASE/${CUSTOM_ENV}/igp/${NET_KEY}/program-ids.json" 2>/dev/null || echo "")
    { [ $EXIT -ne 0 ] && [ -z "$IGP_PROGRAM_ID" ]; } && { log_err "IGP deploy failed (exit $EXIT)."; exit 1; }
    log_ok "IGP program deployed: ${G}${IGP_PROGRAM_ID}${NC}"
fi
[ -n "${IGP_PROGRAM_ID:-}" ] || { log_err "No IGP Program ID resolved."; exit 1; }

# Seed the custom core/program-ids.json (gas-oracle-config reads IGP program+accounts from here)
if [ ! -f "$CUSTOM_CORE_DIR/program-ids.json" ]; then
    cat > "$CUSTOM_CORE_DIR/program-ids.json" <<JSON
{
  "mailbox":                 "${MAILBOX}",
  "validator_announce":      "${VALIDATOR_ANNOUNCE}",
  "multisig_ism_message_id": "${CFG_ISM}",
  "igp_program_id":          "${IGP_PROGRAM_ID}",
  "igp_account":             "",
  "overhead_igp_account":    ""
}
JSON
else
    TMP=$(mktemp); jq ".igp_program_id = \"${IGP_PROGRAM_ID}\"" "$CUSTOM_CORE_DIR/program-ids.json" > "$TMP" && mv "$TMP" "$CUSTOM_CORE_DIR/program-ids.json"
fi

# ═════════════════════════════════════════════════════════════════════════════
# STEP 3 — INIT IGP ACCOUNT + OVERHEAD IGP ACCOUNT (owner = keypair)
# ═════════════════════════════════════════════════════════════════════════════
log_sep "STEP 3 — INIT IGP ACCOUNTS"

IGP_ACCOUNT=""; OVERHEAD_IGP_ACCOUNT=""
if [ -n "${SKIP_ACCOUNTS:-}" ]; then
    log_warn "SKIP_ACCOUNTS set — reading accounts from custom env."
    IGP_ACCOUNT=$(jq -r '.igp_account // ""' "$CUSTOM_CORE_DIR/program-ids.json" 2>/dev/null || echo "")
    OVERHEAD_IGP_ACCOUNT=$(jq -r '.overhead_igp_account // ""' "$CUSTOM_CORE_DIR/program-ids.json" 2>/dev/null || echo "")
else
    log_info "Creating IGP account (streams live)..."
    _T=$(mktemp)
    set +e
    run_client -k "$NET_KEYPAIR" -u "$NET_RPC" \
        igp init-igp-account \
        --program-id "$IGP_PROGRAM_ID" \
        --environment "$CUSTOM_ENV" \
        --environments-dir "$ENVIRONMENTS_BASE" \
        --chain "$NET_KEY" \
        --context "$IGP_SALT" 2>&1 | tee -a "$LOG_FILE" "$_T"
    EXIT=${PIPESTATUS[0]}; set -e
    OUT=$(cat "$_T"); rm -f "$_T"
    IGP_ACCOUNT=$(echo "$OUT" | grep -oE "[1-9A-HJ-NP-Za-km-z]{32,44}" | tail -1 || echo "")
    [ -z "$IGP_ACCOUNT" ] && IGP_ACCOUNT=$(jq -r '.igp_account // ""' "$ENVIRONMENTS_BASE/${CUSTOM_ENV}/igp/${NET_KEY}/${IGP_SALT}/igp-accounts.json" 2>/dev/null || echo "")
    { [ $EXIT -ne 0 ] && [ -z "$IGP_ACCOUNT" ]; } && { log_err "init-igp-account failed (exit $EXIT)."; exit 1; }
    log_ok "IGP account: ${G}${IGP_ACCOUNT}${NC}"

    log_info "Creating overhead-IGP account (streams live)..."
    _T=$(mktemp)
    set +e
    run_client -k "$NET_KEYPAIR" -u "$NET_RPC" \
        igp init-overhead-igp-account \
        --program-id "$IGP_PROGRAM_ID" \
        --environment "$CUSTOM_ENV" \
        --environments-dir "$ENVIRONMENTS_BASE" \
        --chain "$NET_KEY" \
        --inner-igp-account "$IGP_ACCOUNT" \
        --context "${IGP_SALT}-overhead" 2>&1 | tee -a "$LOG_FILE" "$_T"
    EXIT2=${PIPESTATUS[0]}; set -e
    OUT2=$(cat "$_T"); rm -f "$_T"
    OVERHEAD_IGP_ACCOUNT=$(echo "$OUT2" | grep -oE "[1-9A-HJ-NP-Za-km-z]{32,44}" | tail -1 || echo "")
    if [ -n "$OVERHEAD_IGP_ACCOUNT" ]; then log_ok "Overhead IGP account: ${G}${OVERHEAD_IGP_ACCOUNT}${NC}"
    else log_warn "Overhead IGP account not determined — will use base IGP account."; fi
fi

# Update custom core/program-ids.json with the resolved accounts
TMP=$(mktemp)
jq ".igp_account = \"${IGP_ACCOUNT}\" | .overhead_igp_account = \"${OVERHEAD_IGP_ACCOUNT}\"" \
    "$CUSTOM_CORE_DIR/program-ids.json" > "$TMP" && mv "$TMP" "$CUSTOM_CORE_DIR/program-ids.json"

# Which account the warp token points at (prefer overhead-igp)
if [ -n "$OVERHEAD_IGP_ACCOUNT" ]; then WARP_IGP_ACCOUNT="$OVERHEAD_IGP_ACCOUNT"; WARP_IGP_TYPE="overhead-igp"
else WARP_IGP_ACCOUNT="$IGP_ACCOUNT"; WARP_IGP_TYPE="igp"; fi

# ═════════════════════════════════════════════════════════════════════════════
# STEP 4 — SET GAS ORACLE + DESTINATION GAS OVERHEAD FOR TERRA CLASSIC
# ═════════════════════════════════════════════════════════════════════════════
log_sep "STEP 4 — GAS ORACLE + OVERHEAD FOR DOMAIN ${TERRA_DOMAIN}"

if [ -n "${SKIP_ORACLE:-}" ]; then
    log_warn "SKIP_ORACLE set — skipping."
else
    log_info "Setting gas oracle (streams live)..."
    _T=$(mktemp)
    set +e
    run_client -k "$NET_KEYPAIR" -u "$NET_RPC" \
        igp gas-oracle-config \
        --environment "$CUSTOM_ENV" \
        --environments-dir "$ENVIRONMENTS_BASE" \
        --chain-name "$NET_KEY" \
        --remote-domain "$TERRA_DOMAIN" \
        set \
        --token-exchange-rate "$ORACLE_EXCHANGE_RATE" \
        --gas-price "$ORACLE_GAS_PRICE" \
        --token-decimals "$ORACLE_TOKEN_DECIMALS" 2>&1 | tee -a "$LOG_FILE" "$_T"
    EXIT=${PIPESTATUS[0]}; set -e
    OUT=$(cat "$_T"); rm -f "$_T"
    if [ $EXIT -eq 0 ]; then log_ok "Gas oracle set for domain ${TERRA_DOMAIN}."
    elif echo "$OUT" | grep -qiE "already|same"; then log_ok "Gas oracle already configured."
    else log_warn "Gas oracle set exit $EXIT — see log; may need manual retry."; fi

    log_info "Setting destination gas overhead: ${GAS_OVERHEAD} units"
    set +e
    run_client -k "$NET_KEYPAIR" -u "$NET_RPC" \
        igp destination-gas-overhead \
        --environment "$CUSTOM_ENV" \
        --environments-dir "$ENVIRONMENTS_BASE" \
        --chain-name "$NET_KEY" \
        --remote-domain "$TERRA_DOMAIN" \
        set --gas-overhead "$GAS_OVERHEAD" 2>&1 | tee -a "$LOG_FILE"
    set -e
fi

# ═════════════════════════════════════════════════════════════════════════════
# STEP 5 — WRITE igp.program_id + igp.account INTO warp-sealevel-config.json
# ═════════════════════════════════════════════════════════════════════════════
log_sep "STEP 5 — UPDATE warp-sealevel-config.json"

if [ -n "${SKIP_CONFIG_WRITE:-}" ]; then
    log_warn "SKIP_CONFIG_WRITE set — not touching config."
else
    TMP=$(mktemp)
    # account_type: o deploy-warp-solana-buffer.sh usa este campo p/ `token igp set <prog> <TYPE> <acct>`.
    # Tipo errado (igp c/ conta overhead) = VOLTA quebrada (BorshIoError no PayForGas) — bug de 2026-07-09.
    jq ".networks.\"${NET_KEY}\".igp.program_id = \"${IGP_PROGRAM_ID}\" |
        .networks.\"${NET_KEY}\".igp.account = \"${WARP_IGP_ACCOUNT}\" |
        .networks.\"${NET_KEY}\".igp.account_type = \"${WARP_IGP_TYPE}\" |
        .networks.\"${NET_KEY}\".igp.destination_gas_terra = ${GAS_OVERHEAD}" \
        "$SOL_CONFIG" > "$TMP" && mv "$TMP" "$SOL_CONFIG"
    log_ok "igp.program_id=${IGP_PROGRAM_ID}  igp.account=${WARP_IGP_ACCOUNT}  igp.account_type=${WARP_IGP_TYPE}"
fi

# ═════════════════════════════════════════════════════════════════════════════
# STEP 6 — (optional) POINT WARP TOKEN AT THIS IGP
# ═════════════════════════════════════════════════════════════════════════════
if [ -n "${LINK_WARP:-}" ] && [ -n "$WARP_PROGRAM_ID" ] && [ "$WARP_PROGRAM_ID" != "null" ]; then
    log_sep "STEP 6 — SET IGP ON WARP TOKEN (${WARP_TOKEN})"
    _T=$(mktemp)
    set +e
    run_client -k "$NET_KEYPAIR" -u "$NET_RPC" \
        token igp --program-id "$WARP_PROGRAM_ID" \
        set "$IGP_PROGRAM_ID" "$WARP_IGP_TYPE" "$WARP_IGP_ACCOUNT" 2>&1 | tee -a "$LOG_FILE" "$_T"
    EXIT=${PIPESTATUS[0]}; set -e
    OUT=$(cat "$_T"); rm -f "$_T"
    if [ $EXIT -eq 0 ]; then log_ok "Warp token IGP set: ${IGP_PROGRAM_ID} / ${WARP_IGP_ACCOUNT} (${WARP_IGP_TYPE})"
    elif echo "$OUT" | grep -qiE "already|same"; then log_ok "Warp token IGP already set."
    else log_warn "Failed to set IGP on warp token (exit $EXIT). Set it during warp init instead."; fi
else
    log_info "Not linking to a warp token (set LINK_WARP=1 + a deployed WARP_TOKEN to do so)."
    log_info "The warp init (deploy-warp-solana-buffer.sh) will read igp.* from config."
fi

# ── REFERENCE + SUMMARY ──────────────────────────────────────────────────────
REF="$WORK_DIR/REFERENCE-IGP-$(echo "$NET_KEY" | tr a-z A-Z).txt"
cat > "$REF" <<TXT
═══════════════════════════════════════════════════════════
  COMMUNITY IGP — ${NET_DISPLAY}
  Generated: $(date '+%Y-%m-%d %H:%M:%S')
═══════════════════════════════════════════════════════════
Program (hyperlane-sealevel-igp)
  Program ID:        ${IGP_PROGRAM_ID}
  Binary SHA-256:    ${BINARY_SHA256:-N/A (reused existing program)}
  Owner/upgrade:     ${PAYER_PUBKEY}
Accounts
  IGP account:       ${IGP_ACCOUNT:-N/A}
  Overhead IGP:      ${OVERHEAD_IGP_ACCOUNT:-N/A}
  Warp uses:         ${WARP_IGP_ACCOUNT} (${WARP_IGP_TYPE})
Terra Classic (domain ${TERRA_DOMAIN})
  Exchange rate:     ${ORACLE_EXCHANGE_RATE}
  Gas price:         ${ORACLE_GAS_PRICE}
  Token decimals:    ${ORACLE_TOKEN_DECIMALS}
  Gas overhead:      ${GAS_OVERHEAD}
Verify binary:       sha256sum ${BINARY_FILE}
Custom env config:   ${CUSTOM_CORE_DIR}/program-ids.json
TXT

log ""
log "╔══════════════════════════════════════════════════════════════════════════╗"
log "║          ✅  COMMUNITY IGP READY                                        ║"
log "╚══════════════════════════════════════════════════════════════════════════╝"
log "  ${G}IGP Program:${NC}  ${IGP_PROGRAM_ID}"
log "  ${G}IGP account:${NC}  ${WARP_IGP_ACCOUNT} (${WARP_IGP_TYPE})"
log "  ${G}SHA-256:${NC}      ${BINARY_SHA256:-N/A}"
log "  ${G}Oracle:${NC}       domain ${TERRA_DOMAIN} — rate ${ORACLE_EXCHANGE_RATE}, gas ${ORACLE_GAS_PRICE}, overhead ${GAS_OVERHEAD}"
log ""
log "  Next: warp init → ${Y}./deploy-warp-solana-buffer.sh${NC} (reads igp.* + ism.program_id from config)"
log ""
log "${B}📄 Reference: ${REF}${NC}"
log "${B}📋 Log:       ${LOG_FILE}${NC}"
