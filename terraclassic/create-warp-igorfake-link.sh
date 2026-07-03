#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
#  🚀 CREATE IGORFAKE COLLATERAL WARP ON TERRA CLASSIC + LINK EXISTING SYNTHETICS
# ═══════════════════════════════════════════════════════════════════════════════
#
#  Deploys a NEW collateral Warp Route for IGORFAKE on Terra Classic (columbus-5,
#  mailbox v2 / domain 132556) and links it bidirectionally to the EXISTING
#  synthetic Warp Routes already deployed on Ethereum and BSC.
#
#  It does NOT deploy anything on the EVM side — the synthetics already exist.
#  It only:
#    1. cw-hpl warp create  → new IGORFAKE collateral warp on Terra Classic
#    2. set_route (Terra)    → new warp learns the ETH + BSC synthetic routers
#    3. enrollRemoteRouter   → ETH + BSC synthetics point domain 132556 to the new warp
#
#  USAGE:
#    export TERRA_PRIVATE_KEY="hex_no_0x"   # owner: terra1run9wz09uhh6pu7ggcwwetrgye4wu7wn26mawp
#    export ETH_PRIVATE_KEY="0x..."         # owner: 0xEF8181201Ce6C83120035Ffbcc11945E67Ba00ae
#    export BSC_PRIVATE_KEY="0x..."         # owner: 0x8f085bAD1a15ee9ceeE58C83EFFFa72518975291
#    chmod +x create-warp-igorfake-link.sh
#    ./create-warp-igorfake-link.sh
#
#  OPTIONS:
#    YES=1                  → skip the confirmation prompt (non-interactive)
#    NEW_WARP_ADDRESS=...   → skip the Terra deploy and link this existing warp instead
#
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# COLORS / LOGGING
# ─────────────────────────────────────────────────────────────────────────────
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'; C='\033[0;36m'; W='\033[1m'; NC='\033[0m'
OK="${G}✅${NC}"; ERR="${R}❌${NC}"; WARN="${Y}⚠️ ${NC}"; INFO="${B}ℹ️ ${NC}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$SCRIPT_DIR/log"; mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/create-warp-igorfake-link-$(date +%Y%m%d-%H%M%S).log"

log()      { echo -e "$@" | tee -a "$LOG_FILE"; }
log_ok()   { log "${OK} $*"; }
log_err()  { log "${ERR} $*"; }
log_warn() { log "${WARN} $*"; }
log_info() { log "${INFO} $*"; }
log_sep()  { log ""; log "${C}${W}$1${NC}"; log "────────────────────────────────────────────────────────────────"; }

# Find cw-hyperlane project root (where package.json lives)
PROJECT_ROOT="$SCRIPT_DIR"
while [ ! -f "$PROJECT_ROOT/package.json" ] && [ "$PROJECT_ROOT" != "/" ]; do
    PROJECT_ROOT="$(dirname "$PROJECT_ROOT")"
done
[ -f "$PROJECT_ROOT/package.json" ] || { log_err "cw-hyperlane project root (package.json) not found"; exit 1; }

# ─────────────────────────────────────────────────────────────────────────────
# CONSTANTS — Terra Classic (mainnet, v2 mailbox / domain 132556)
# ─────────────────────────────────────────────────────────────────────────────
TOKEN_ID="igorfake"
TERRA_DOMAIN=132556
TERRA_CHAIN_ID="columbus-5"
TERRA_RPC="https://rpc.terra-classic.hexxagon.io"
# Underlying CW20 wrapped as collateral by the warp (from warp-evm-config.json)
TERRA_COLLATERAL="terra1lpkaaqjaq8zfwktge3vy0zg46nxxsynsge2wxa7addpweu2w6gmsy3lhkr"

# ─────────────────────────────────────────────────────────────────────────────
# CONSTANTS — existing EVM synthetics to link to (addresses from doc/README.md
# and warp-evm-config.json). Parallel arrays, index 0 = ETH, 1 = BSC.
# ─────────────────────────────────────────────────────────────────────────────
EVM_NAMES=(ethereum bsc)
EVM_DOMAINS=(1 56)
EVM_SYNTHETICS=(0xA687a4C4Ca49795999b36fDC8A18D1ddD63EdfB5 0x3605d8946fC6f5a75D89D92173100F59743b5318)
EVM_RPCS=(https://ethereum-rpc.publicnode.com https://bsc.publicnode.com)
EVM_EXPLORERS=(https://etherscan.io https://bscscan.com)
EVM_PK_VARS=(ETH_PRIVATE_KEY BSC_PRIVATE_KEY)

# ─────────────────────────────────────────────────────────────────────────────
# HELPERS
# ─────────────────────────────────────────────────────────────────────────────
# Pad an address/hash to bytes32 (64 hex chars, no 0x). EVM 20-byte addrs get
# left-padded; CosmWasm 32-byte hashes are already 64 chars.
to_bytes32() { local a="${1#0x}"; a="${a,,}"; printf '%064s' "$a" | tr ' ' '0' | cut -c1-64; }

# bech32 (terra1...) → 0x-prefixed hex of the underlying 32-byte address
bech32_to_hex() {
    python3 - "$1" <<'PYEOF' 2>/dev/null
import sys
addr = sys.argv[1]
CHARSET = 'qpzry9x8gf2tvdw0s3jn54khce6mua7l'
sep = addr.rfind('1')
data_str = addr[sep+1:-6]
vals = [CHARSET.index(c) for c in data_str]
result, acc, bits = [], 0, 0
for v in vals:
    acc = (acc << 5) | v; bits += 5
    while bits >= 8:
        bits -= 8; result.append((acc >> bits) & 0xFF)
print('0x' + ''.join(f'{b:02x}' for b in result))
PYEOF
}

# cast send with up to 3 retries; echoes the tx hash on success
cast_tx() {
    local n=0 out
    while [ $n -lt 3 ]; do
        out=$(cast send "$@" 2>&1) && { echo "$out" | grep -oE "0x[0-9a-fA-F]{64}" | head -1; return 0; }
        n=$((n+1)); [ $n -lt 3 ] && { log_warn "TX failed ($n/3), retrying in 5s..."; sleep 5; }
    done
    return 1
}

# ─────────────────────────────────────────────────────────────────────────────
# BANNER + PREFLIGHT
# ─────────────────────────────────────────────────────────────────────────────
> "$LOG_FILE"
log "╔══════════════════════════════════════════════════════════════════════════╗"
log "║   🚀  IGORFAKE — new Terra Classic collateral warp + link ETH/BSC          ║"
log "║       $(date '+%Y-%m-%d %H:%M:%S')                                                  ║"
log "╚══════════════════════════════════════════════════════════════════════════╝"

command -v jq      >/dev/null || { log_err "jq required";      exit 1; }
command -v node    >/dev/null || { log_err "node required";    exit 1; }
command -v python3 >/dev/null || { log_err "python3 required"; exit 1; }
command -v cast    >/dev/null || { log_err "cast (foundry) required for EVM enroll"; exit 1; }
command -v yarn    >/dev/null || { log_err "yarn required for cw-hpl"; exit 1; }

: "${TERRA_PRIVATE_KEY:?Set TERRA_PRIVATE_KEY (hex, no 0x)}"
: "${ETH_PRIVATE_KEY:?Set ETH_PRIVATE_KEY (0x...)}"
: "${BSC_PRIVATE_KEY:?Set BSC_PRIVATE_KEY (0x...)}"
TERRA_PRIV_CLEAN="${TERRA_PRIVATE_KEY#0x}"

# Derive Terra owner address from the key (used as warp owner + set_route signer)
TERRA_OWNER=$(
  _NM_ROOT="$PROJECT_ROOT" _NM_PRIV="$TERRA_PRIV_CLEAN" node --no-warnings -e '
    const path=require("path"); const nm=path.join(process.env._NM_ROOT,"node_modules");
    const {DirectSecp256k1Wallet}=require(path.join(nm,"@cosmjs/proto-signing"));
    const {fromHex}=require(path.join(nm,"@cosmjs/encoding"));
    (async()=>{const w=await DirectSecp256k1Wallet.fromKey(fromHex(process.env._NM_PRIV),"terra");
      const [a]=await w.getAccounts(); console.log(a.address);})();' 2>/dev/null
)
[ -n "$TERRA_OWNER" ] || { log_err "Could not derive Terra address from TERRA_PRIVATE_KEY"; exit 1; }

log_ok "Terra owner / deployer: ${G}${TERRA_OWNER}${NC}"
log_info "Terra mailbox (v2) read from ${C}context/terraclassic.json${NC} → domain ${TERRA_DOMAIN}"
log "  Collateral CW20: ${C}${TERRA_COLLATERAL}${NC}"
log "  Link targets:"
for i in "${!EVM_NAMES[@]}"; do
    log "    • ${EVM_NAMES[$i]} (domain ${EVM_DOMAINS[$i]}) synthetic ${C}${EVM_SYNTHETICS[$i]}${NC}"
done

if [ -z "${YES:-}" ]; then
    log ""
    echo -ne "  ${W}Proceed with deploy + linking on MAINNET? [y/N]: ${NC}"
    read -r CONFIRM 2>/dev/null || CONFIRM="n"
    [[ "$CONFIRM" =~ ^[yY]$ ]] || { log_warn "Aborted by user."; exit 0; }
fi

# ═════════════════════════════════════════════════════════════════════════════
# STEP 1 — DEPLOY NEW IGORFAKE COLLATERAL WARP ON TERRA CLASSIC
# ═════════════════════════════════════════════════════════════════════════════
log_sep "STEP 1 — DEPLOY TERRA CLASSIC WARP (yarn cw-hpl warp create)"

if [ -n "${NEW_WARP_ADDRESS:-}" ]; then
    TERRA_WARP_ADDR="$NEW_WARP_ADDRESS"
    log_warn "Skipping deploy — using provided NEW_WARP_ADDRESS=${TERRA_WARP_ADDR}"
else
    TERRA_WARP_CONFIG="$SCRIPT_DIR/warp/terraclassic-cw20-${TOKEN_ID}-$(date +%Y%m%d%H%M%S).json"
    mkdir -p "$(dirname "$TERRA_WARP_CONFIG")"
    cat > "$TERRA_WARP_CONFIG" <<TCFG
{
  "type": "cw20",
  "mode": "collateral",
  "id": "${TOKEN_ID}",
  "owner": "${TERRA_OWNER}",
  "config": {
    "collateral": {
      "address": "${TERRA_COLLATERAL}"
    }
  }
}
TCFG
    log_ok "Config: ${C}${TERRA_WARP_CONFIG}${NC}"
    log "${Y}⏳ Deploying on Terra Classic (~1 min)...${NC}"

    # cw-hpl reads config.yaml + context from PROJECT_ROOT
    [ -f "$SCRIPT_DIR/config.yaml" ] && [ "$SCRIPT_DIR" != "$PROJECT_ROOT" ] && cp "$SCRIPT_DIR/config.yaml" "$PROJECT_ROOT/config.yaml"

    DEPLOY_TMP=$(mktemp)
    set +e
    ( cd "$PROJECT_ROOT" && PRIVATE_KEY="$TERRA_PRIVATE_KEY" yarn cw-hpl warp create "$TERRA_WARP_CONFIG" -n terraclassic < /dev/null ) \
        2>&1 | tee -a "$LOG_FILE" "$DEPLOY_TMP"
    DEPLOY_EXIT=${PIPESTATUS[0]}
    set -e
    DEPLOY_OUT=$(cat "$DEPLOY_TMP"); rm -f "$DEPLOY_TMP"
    [ "$DEPLOY_EXIT" -eq 0 ] || { log_err "Terra deploy failed (exit $DEPLOY_EXIT)"; exit 1; }

    # Extract new contract address (last terra1 in output, fallback to context file)
    TERRA_WARP_ADDR=$(echo "$DEPLOY_OUT" | grep -oE 'terra1[a-z0-9]{38,58}' | tail -1 || echo "")
    if [ -z "$TERRA_WARP_ADDR" ]; then
        TERRA_WARP_ADDR=$(jq -r ".deployments.warp.cw20[] | select(.id==\"${TOKEN_ID}\") | .address" \
            "$PROJECT_ROOT/context/terraclassic.json" 2>/dev/null | tail -1 || echo "")
    fi
    [ -n "$TERRA_WARP_ADDR" ] || { log_err "Could not determine the new warp address from output"; exit 1; }
fi

TERRA_WARP_HEX=$(bech32_to_hex "$TERRA_WARP_ADDR")
[ -n "$TERRA_WARP_HEX" ] || { log_err "bech32→hex conversion failed for $TERRA_WARP_ADDR"; exit 1; }
TERRA_WARP_B32=$(to_bytes32 "$TERRA_WARP_HEX")

log_ok "New Terra warp:  ${G}${TERRA_WARP_ADDR}${NC}"
log_ok "bytes32:         ${G}0x${TERRA_WARP_B32}${NC}"

# ═════════════════════════════════════════════════════════════════════════════
# STEP 2 — set_route ON TERRA (new warp learns the ETH + BSC synthetic routers)
# ═════════════════════════════════════════════════════════════════════════════
log_sep "STEP 2 — LINK EVM ROUTES ON TERRA (router.set_route)"

_NODE_TMP=$(mktemp /tmp/igf-set-route-XXXXXX.js)
cat > "$_NODE_TMP" <<'NODEJS'
const path = require('path');
const nm   = path.join(process.env._NM_ROOT, 'node_modules');
const { SigningCosmWasmClient } = require(path.join(nm, '@cosmjs/cosmwasm-stargate'));
const { DirectSecp256k1Wallet } = require(path.join(nm, '@cosmjs/proto-signing'));
const { GasPrice }              = require(path.join(nm, '@cosmjs/stargate'));
const { fromHex }               = require(path.join(nm, '@cosmjs/encoding'));
async function main() {
    const wallet = await DirectSecp256k1Wallet.fromKey(fromHex(process.env._NM_PRIV), 'terra');
    const [account] = await wallet.getAccounts();
    const client = await SigningCosmWasmClient.connectWithSigner(
        process.env._NM_RPC, wallet, { gasPrice: GasPrice.fromString('28.325uluna') });
    const warpAddr  = process.env._NM_WARP;
    const domain    = parseInt(process.env._NM_DOMAIN, 10);
    const route     = process.env._NM_ROUTE; // 64-hex, no 0x
    try {
        const routes = await client.queryContractSmart(warpAddr, { router: { list_routes: {} } });
        const ex = (routes.routes || []).find(r => r.domain === domain);
        if (ex && ex.route && ex.route.replace(/^0x/,'').toLowerCase() === route.toLowerCase()) {
            console.log('STATUS=already_set'); return;
        }
    } catch (e) { /* no routes yet */ }
    const res = await client.execute(account.address, warpAddr,
        { router: { set_route: { set: { domain, route } } } }, 'auto',
        'enrollRemoteRouter igorfake link');
    console.log('STATUS=ok'); console.log('TX=' + res.transactionHash);
}
main().catch(e => { console.log('STATUS=error'); console.log('ERR=' + e.message); process.exit(0); });
NODEJS

for i in "${!EVM_NAMES[@]}"; do
    DOM="${EVM_DOMAINS[$i]}"
    ROUTE_B32=$(to_bytes32 "${EVM_SYNTHETICS[$i]}")
    log "  ${EVM_NAMES[$i]} (domain ${DOM}) → route 0x${ROUTE_B32}"
    set +e
    OUT=$(_NM_ROOT="$PROJECT_ROOT" _NM_PRIV="$TERRA_PRIV_CLEAN" _NM_RPC="$TERRA_RPC" \
          _NM_WARP="$TERRA_WARP_ADDR" _NM_DOMAIN="$DOM" _NM_ROUTE="$ROUTE_B32" \
          node --no-warnings "$_NODE_TMP" 2>&1)
    set -e
    STATUS=$(echo "$OUT" | grep "^STATUS=" | cut -d= -f2 || echo "")
    case "$STATUS" in
        ok)          log_ok "  set_route OK — TX $(echo "$OUT" | grep '^TX=' | cut -d= -f2)";;
        already_set) log_ok "  route already set on Terra";;
        *)           log_warn "  set_route issue: $(echo "$OUT" | grep -E '^ERR=' | cut -d= -f2- | head -1)"
                     log "    raw: $(echo "$OUT" | head -3)";;
    esac
done
rm -f "$_NODE_TMP"

# ═════════════════════════════════════════════════════════════════════════════
# STEP 3 — enrollRemoteRouter ON ETH + BSC (synthetics point 132556 → new warp)
# ═════════════════════════════════════════════════════════════════════════════
log_sep "STEP 3 — LINK TERRA ROUTE ON ETH/BSC (enrollRemoteRouter)"

for i in "${!EVM_NAMES[@]}"; do
    NAME="${EVM_NAMES[$i]}"; SYN="${EVM_SYNTHETICS[$i]}"; RPC="${EVM_RPCS[$i]}"
    EXPL="${EVM_EXPLORERS[$i]}"; PK="${!EVM_PK_VARS[$i]}"
    log "  ${NAME}: ${C}${SYN}${NC}  enrollRemoteRouter(${TERRA_DOMAIN}, 0x${TERRA_WARP_B32})"

    # Skip if already pointing to the new warp
    set +e
    CUR=$(cast call "$SYN" "routers(uint32)(bytes32)" "$TERRA_DOMAIN" --rpc-url "$RPC" 2>/dev/null | tr 'A-F' 'a-f')
    set -e
    if [ "${CUR#0x}" = "$TERRA_WARP_B32" ]; then
        log_ok "  already enrolled → ${TERRA_WARP_ADDR}"
        continue
    fi

    set +e
    TX=$(cast_tx "$SYN" "enrollRemoteRouter(uint32,bytes32)" "$TERRA_DOMAIN" "0x${TERRA_WARP_B32}" \
            --rpc-url "$RPC" --private-key "$PK" --legacy)
    RC=$?
    set -e
    if [ $RC -eq 0 ] && [ -n "$TX" ]; then
        log_ok "  enrolled — ${B}${EXPL}/tx/${TX}${NC}"
    else
        log_warn "  enrollRemoteRouter failed on ${NAME} (check owner / gas / RPC)"
    fi
done

# ═════════════════════════════════════════════════════════════════════════════
# SUMMARY
# ═════════════════════════════════════════════════════════════════════════════
log_sep "DONE"
log_ok "New IGORFAKE collateral warp on Terra Classic (domain ${TERRA_DOMAIN}):"
log "    bech32:  ${G}${TERRA_WARP_ADDR}${NC}"
log "    bytes32: ${G}0x${TERRA_WARP_B32}${NC}"
log ""
log "${W}Next steps (not done by this script):${NC}"
log "  1. Update warp-evm-config.json → .terra_classic.tokens.igorfake.terra_warp.warp_address/.warp_hexed"
log "  2. Update the registry warp route so the explorer + warp UI use the new warp:"
log "     ${C}deployments/warp_routes/IGORFAKE/terraclassic-bsc-ethereum-solanamainnet-config.yaml${NC}"
log "     set the terraclassic token addressOrDenom to ${G}${TERRA_WARP_ADDR}${NC}"
log "  3. Do a fresh transfer from the warp UI and confirm it appears in tc-hyperlane-explorer."
log ""
log "Log saved to: ${C}${LOG_FILE}${NC}"
