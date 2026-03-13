#!/usr/bin/env bash
# =============================================================================
#  enroll-terra-router.sh
#  Registers the EVM route on the Terra Classic Warp contract
#  Fixes the error: "route not found" when calling transfer_remote
#
#  What it does:
#    Calls router.set_route on the Terra Classic Warp contract to register
#    the EVM Warp address (e.g.: Sepolia) as the router for the target domain.
#
#  USAGE:
#    export TERRA_PRIVATE_KEY="your_hex_key"
#    ./enroll-terra-router.sh
# =============================================================================
set -euo pipefail

# ─── Cores ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_JSON="$SCRIPT_DIR/warp-evm-config.json"

# ─── Banner ───────────────────────────────────────────────────────────────────
echo -e ""
echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${CYAN}║   enrollRemoteRouter — TERRA CLASSIC (set_route)    ║${RESET}"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════╝${RESET}"
echo -e ""

# ─── Check dependencies ──────────────────────────────────────────────────────
for dep in node jq; do
    if ! command -v "$dep" &>/dev/null; then
        echo -e "${RED}❌ Dependency not found: ${dep}${RESET}"
        exit 1
    fi
done

if [ ! -f "$CONFIG_JSON" ]; then
    echo -e "${RED}❌ File not found: $CONFIG_JSON${RESET}"
    exit 1
fi

# ─── Locate node_modules ────────────────────────────────────────────────────
PROJECT_ROOT="$SCRIPT_DIR"
while [ "$PROJECT_ROOT" != "/" ] && [ ! -f "$PROJECT_ROOT/package.json" ]; do
    PROJECT_ROOT="$(dirname "$PROJECT_ROOT")"
done
if [ ! -d "$PROJECT_ROOT/node_modules/@cosmjs/cosmwasm-stargate" ]; then
    echo -e "${RED}❌ node_modules not found in $PROJECT_ROOT${RESET}"
    echo -e "   Execute: cd $PROJECT_ROOT && yarn install"
    exit 1
fi

# ─── Read configuration from config JSON ────────────────────────────────────
TERRA_RPC=$(jq -r '.terra_classic.rpc'      "$CONFIG_JSON")
TERRA_CHAIN=$(jq -r '.terra_classic.chain_id' "$CONFIG_JSON")

echo -e "${BOLD}📌 Select the TOKEN to link:${RESET}"
echo -e ""

# List available tokens with warp_address on Terra
TOKENS=$(jq -r '.terra_classic.tokens | to_entries[] | select(.value.terra_warp.warp_address != "" and .value.terra_warp.warp_address != null) | .key' "$CONFIG_JSON")
TOKEN_LIST=()
while IFS= read -r t; do
    TOKEN_LIST+=("$t")
done <<< "$TOKENS"

if [ ${#TOKEN_LIST[@]} -eq 0 ]; then
    echo -e "${RED}❌ No token with warp_address configured on Terra Classic.${RESET}"
    exit 1
fi

for i in "${!TOKEN_LIST[@]}"; do
    TK="${TOKEN_LIST[$i]}"
    SYMBOL=$(jq -r ".terra_classic.tokens.${TK}.symbol" "$CONFIG_JSON")
    WADDR=$(jq -r ".terra_classic.tokens.${TK}.terra_warp.warp_address" "$CONFIG_JSON")
    echo -e "  ${CYAN}[$((i+1))]${RESET} ${BOLD}${SYMBOL}${RESET} — ${WADDR}"
done
echo -e ""
echo -ne "${YELLOW}▶ Enter the number: ${RESET}"
read -r TOKEN_IDX
TOKEN_IDX=$((TOKEN_IDX - 1))
if [ "$TOKEN_IDX" -lt 0 ] || [ "$TOKEN_IDX" -ge "${#TOKEN_LIST[@]}" ]; then
    echo -e "${RED}❌ Invalid option.${RESET}"; exit 1
fi

TOKEN_KEY="${TOKEN_LIST[$TOKEN_IDX]}"
TERRA_WARP_ADDR=$(jq -r ".terra_classic.tokens.${TOKEN_KEY}.terra_warp.warp_address" "$CONFIG_JSON")
TOKEN_SYMBOL=$(jq -r ".terra_classic.tokens.${TOKEN_KEY}.symbol" "$CONFIG_JSON")

echo -e ""
echo -e "${BOLD}📌 Select the destination EVM network:${RESET}"
echo -e ""

# List networks that have this token deployed
NETWORKS=$(jq -r --arg tk "$TOKEN_KEY" \
    '.networks | to_entries[] | select(.value.enabled == true and .value.warp_tokens[$tk].deployed == true) | .key' \
    "$CONFIG_JSON")
NET_LIST=()
while IFS= read -r n; do
    NET_LIST+=("$n")
done <<< "$NETWORKS"

if [ ${#NET_LIST[@]} -eq 0 ]; then
    echo -e "${RED}❌ No EVM network with ${TOKEN_KEY} deployed.${RESET}"
    echo -e "${YELLOW}   Check warp_tokens.${TOKEN_KEY}.deployed=true in config.${RESET}"
    exit 1
fi

for i in "${!NET_LIST[@]}"; do
    NK="${NET_LIST[$i]}"
    ND=$(jq -r ".networks.${NK}.display_name" "$CONFIG_JSON")
    WADDR=$(jq -r ".networks.${NK}.warp_tokens.${TOKEN_KEY}.address" "$CONFIG_JSON")
    DOM=$(jq -r ".networks.${NK}.domain" "$CONFIG_JSON")
    echo -e "  ${CYAN}[$((i+1))]${RESET} ${BOLD}${ND}${RESET} (domain ${DOM}) — ${WADDR}"
done
echo -e ""
echo -ne "${YELLOW}▶ Enter the number: ${RESET}"
read -r NET_IDX
NET_IDX=$((NET_IDX - 1))
if [ "$NET_IDX" -lt 0 ] || [ "$NET_IDX" -ge "${#NET_LIST[@]}" ]; then
    echo -e "${RED}❌ Invalid option.${RESET}"; exit 1
fi

NET_KEY="${NET_LIST[$NET_IDX]}"
EVM_DOMAIN=$(jq -r ".networks.${NET_KEY}.domain"                        "$CONFIG_JSON")
EVM_DISPLAY=$(jq -r ".networks.${NET_KEY}.display_name"                  "$CONFIG_JSON")
EVM_WARP_ADDR=$(jq -r ".networks.${NET_KEY}.warp_tokens.${TOKEN_KEY}.address" "$CONFIG_JSON")

# Convert EVM address to bytes32 without 0x
EVM_WARP_HEX="${EVM_WARP_ADDR#0x}"
EVM_WARP_B32=$(printf '%064s' "$EVM_WARP_HEX" | tr ' ' '0')

# ─── Private key ──────────────────────────────────────────────────────────────
if [ -z "${TERRA_PRIVATE_KEY:-}" ]; then
    echo -e ""
    echo -e "${YELLOW}⚠️  TERRA_PRIVATE_KEY not set.${RESET}"
    echo -e "   export TERRA_PRIVATE_KEY=\"your_hex_key\""
    echo -n "   > "
    read -rs TERRA_PRIVATE_KEY
    echo ""
    if [ -z "$TERRA_PRIVATE_KEY" ]; then
        echo -e "${RED}❌ Private key not provided. Aborting.${RESET}"; exit 1
    fi
fi
TERRA_PRIVATE_KEY="${TERRA_PRIVATE_KEY#0x}"

# ─── Summary ─────────────────────────────────────────────────────────────────
echo -e ""
echo -e "${BOLD}📋 Operation parameters:${RESET}"
echo -e "   ${CYAN}Token         :${RESET} $TOKEN_SYMBOL ($TOKEN_KEY)"
echo -e "   ${CYAN}Terra Warp    :${RESET} $TERRA_WARP_ADDR"
echo -e "   ${CYAN}EVM Network   :${RESET} $EVM_DISPLAY (domain $EVM_DOMAIN)"
echo -e "   ${CYAN}EVM Warp      :${RESET} $EVM_WARP_ADDR"
echo -e "   ${CYAN}EVM bytes32   :${RESET} $EVM_WARP_B32"
echo -e "   ${CYAN}RPC Terra     :${RESET} $TERRA_RPC"
echo -e ""
echo -e "${BOLD}CosmWasm message to be executed:${RESET}"
echo -e "${CYAN}{
  \"router\": {
    \"set_route\": {
      \"set\": {
        \"domain\": $EVM_DOMAIN,
        \"route\": \"$EVM_WARP_B32\"
      }
    }
  }
}${RESET}"
echo -e ""

echo -ne "${YELLOW}▶ Confirm? [y/N]: ${RESET}"
read -r CONFIRM
if [[ ! "$CONFIRM" =~ ^[sStTyY]$ ]]; then
    echo -e "${RED}❌ Cancelled.${RESET}"; exit 0
fi

echo -e ""
echo -e "${BOLD}⏳ Sending transaction...${RESET}"
echo -e ""

# ─── Export variables to Node.js via env (heredoc with quotes = no bash expansion) ───
export _NM="$PROJECT_ROOT"
export _RPC="$TERRA_RPC"
export _WARP="$TERRA_WARP_ADDR"
export _DOMAIN="$EVM_DOMAIN"
export _ROUTE="$EVM_WARP_B32"
export _KEY="$TERRA_PRIVATE_KEY"

# ─── Inline Node.js to execute set_route ────────────────────────────────────
# IMPORTANT: disable set -e to capture errors manually
set +e
RESULT=$(node --no-warnings - 2>&1 <<'NODEJS_EOF'
const path = require('path');
const nm = path.join(process.env._NM, 'node_modules');
const { SigningCosmWasmClient } = require(path.join(nm, '@cosmjs/cosmwasm-stargate'));
const { DirectSecp256k1Wallet }  = require(path.join(nm, '@cosmjs/proto-signing'));
const { GasPrice }               = require(path.join(nm, '@cosmjs/stargate'));
const { fromHex }                = require(path.join(nm, '@cosmjs/encoding'));

async function main() {
    const rpc         = process.env._RPC;
    const terraWarp   = process.env._WARP;
    const evmDomain   = parseInt(process.env._DOMAIN, 10);
    const evmRouteHex = process.env._ROUTE;
    const privKeyHex  = process.env._KEY;
    const gasPrice    = GasPrice.fromString("28.325uluna");

    let privKeyBytes;
    try {
        privKeyBytes = fromHex(privKeyHex);
    } catch(e) {
        console.log("STATUS=error");
        console.log("ERR=Invalid private key: " + e.message);
        return;
    }

    const wallet = await DirectSecp256k1Wallet.fromKey(privKeyBytes, 'terra');
    const [account] = await wallet.getAccounts();
    console.log("SENDER=" + account.address);

    const client = await SigningCosmWasmClient.connectWithSigner(rpc, wallet, { gasPrice });

    // Check if route already exists using list_routes (more reliable)
    // get_route returns {route: null} when NOT set — do not use for checking!
    try {
        const routes = await client.queryContractSmart(terraWarp, {
            router: { list_routes: {} }
        });
        const existing = (routes.routes || []).find(r => r.domain === evmDomain);
        if (existing && existing.route) {
            console.log("STATUS=already_set");
            console.log("EXISTING_ROUTE=" + existing.route);
            return;
        }
    } catch(e) {
        // fallback: proceed anyway
    }

    const msg = {
        router: {
            set_route: {
                set: {
                    domain: evmDomain,
                    route: evmRouteHex,
                }
            }
        }
    };

    const result = await client.execute(
        account.address, terraWarp, msg,
        "auto",
        "enrollRemoteRouter via enroll-terra-router.sh"
    );

    console.log("TX_HASH=" + result.transactionHash);
    console.log("HEIGHT=" + result.height);
    console.log("GAS_USED=" + result.gasUsed);
    console.log("STATUS=ok");
}

main().catch(e => {
    console.log("STATUS=error");
    console.log("ERR=" + e.message);
});
NODEJS_EOF
)
EXIT_CODE=$?
set -e

# Show raw output in case of total node failure
if [ $EXIT_CODE -ne 0 ] && ! echo "$RESULT" | grep -q "^STATUS="; then
    echo -e "${RED}❌ Unexpected Node.js failure (exit $EXIT_CODE):${RESET}"
    echo -e "${YELLOW}$RESULT${RESET}"
    exit 1
fi

# IMPORTANT: use "|| echo """ to prevent grep with no match (exit 1) from causing
# script exit with set -euo pipefail (bug: grep exits 1 when no match found)
TX_HASH=$(echo "$RESULT"  | grep "^TX_HASH="        | cut -d= -f2  || echo "")
HEIGHT=$(echo "$RESULT"   | grep "^HEIGHT="         | cut -d= -f2  || echo "")
GAS_USED=$(echo "$RESULT" | grep "^GAS_USED="       | cut -d= -f2  || echo "")
SENDER=$(echo "$RESULT"   | grep "^SENDER="         | cut -d= -f2  || echo "")
STATUS=$(echo "$RESULT"   | grep "^STATUS="         | cut -d= -f2  || echo "")
EXISTING=$(echo "$RESULT" | grep "^EXISTING_ROUTE=" | cut -d= -f2  || echo "")
ERR_MSG=$(echo "$RESULT"  | grep "^ERR="            | cut -d= -f2- || echo "")

if [ "$STATUS" = "error" ]; then
    echo -e "${RED}❌ Error executing set_route:${RESET}"
    echo -e "   ${YELLOW}${ERR_MSG}${RESET}"
    echo -e ""
    echo -e "${BOLD}Full output:${RESET}"
    echo -e "$RESULT"
    exit 1
elif [ "$STATUS" = "already_set" ]; then
    echo -e "${GREEN}✅ Route was already configured!${RESET}"
    echo -e "   ${CYAN}Existing route:${RESET} $EXISTING"
    echo -e ""
    echo -e "${YELLOW}⚠️  If the 'route not found' error persists, check:${RESET}"
    echo -e "   1. Whether the EVM address matches the deployed Warp"
    echo -e "   2. Whether the correct domain is being passed in transfer_remote"
else
    echo -e ""
    echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════╗${RESET}"
    echo -e "${BOLD}${GREEN}║    ✅ set_route EXECUTED SUCCESSFULLY!               ║${RESET}"
    echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════╝${RESET}"
    echo -e ""
    echo -e "${BOLD}📦 Transaction:${RESET}"
    echo -e "   ${CYAN}TX Hash   :${RESET} ${BOLD}${TX_HASH}${RESET}"
    echo -e "   ${CYAN}Block     :${RESET} $HEIGHT"
    echo -e "   ${CYAN}Gas used  :${RESET} $GAS_USED"
    echo -e "   ${CYAN}Sender    :${RESET} $SENDER"
    echo -e ""
    echo -e "   ${BOLD}🔗 Explorer:${RESET}"
    echo -e "   ${CYAN}https://finder.hexxagon.io/${TERRA_CHAIN}/tx/${TX_HASH}${RESET}"
fi

echo -e ""
echo -e "${BOLD}📋 Registered configuration:${RESET}"
echo -e "   ${CYAN}Terra Warp   :${RESET} $TERRA_WARP_ADDR"
echo -e "   ${CYAN}EVM Domain   :${RESET} $EVM_DOMAIN ($EVM_DISPLAY)"
echo -e "   ${CYAN}EVM Warp     :${RESET} $EVM_WARP_ADDR"
echo -e "   ${CYAN}EVM bytes32  :${RESET} $EVM_WARP_B32"
echo -e ""
echo -e "${GREEN}✅ The Terra Classic contract now knows the route to $EVM_DISPLAY!${RESET}"
echo -e "   transfer_remote { dest_domain: $EVM_DOMAIN } should work now."
echo -e ""
