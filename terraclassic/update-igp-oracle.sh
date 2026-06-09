#!/bin/bash
# =============================================================================
#  update-igp-oracle.sh
#  Configure / update the Terra Classic IGP Oracle gas prices for destination
#  chains (ETH, BSC, Solana, etc.).
#
#  Two modes:
#    1. DIRECT (owner)  — executes transactions immediately as the owner wallet
#    2. GOVERNANCE       — generates a JSON proposal file to submit via terrad
#
#  Usage (direct):
#    export TERRA_PRIVATE_KEY="your_hex_key_no_0x"
#    ./update-igp-oracle.sh
#
#  Usage (governance proposal only, no key needed):
#    MODE=governance ./update-igp-oracle.sh
#
#  Skip interactive menu:
#    DOMAINS="1,56,1399811149"   ./update-igp-oracle.sh    # configure these domains
#    ETH_USD=3500  BNB_USD=617  LUNC_USD=0.00006824        # override prices
#    GAS_PRICE_ETH=10000000000  GAS_PRICE_BSC=3000000000   # override gas prices
# =============================================================================
set -euo pipefail

R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'
B='\033[0;34m'; C='\033[0;36m'; W='\033[1m'; NC='\033[0m'
OK="${G}✅${NC}"; ERR="${R}❌${NC}"; WARN="${Y}⚠️ ${NC}"; INFO="${B}ℹ️ ${NC}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$SCRIPT_DIR/log"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/update-igp-oracle.log"

PROJECT_ROOT="$SCRIPT_DIR"
while [ ! -f "$PROJECT_ROOT/package.json" ] && [ "$PROJECT_ROOT" != "/" ]; do
    PROJECT_ROOT="$(dirname "$PROJECT_ROOT")"
done

# ── Mainnet contract addresses ────────────────────────────────────────────────
RPC="https://rpc.terra-classic.hexxagon.io"
LCD="https://lcd.terra-classic.hexxagon.io"
CHAIN_ID="columbus-5"
ORACLE="terra1j8xzgzk7vds5uzrplmnln4vcz6f205t9atdyflypzrr43cd5eh7scwqj0d"
IGP="terra1taunhg629rssf3g939nqr0h594q5mssrzdj5lkx2hygmxmh72ghqeqqnvz"
GOV_MODULE="terra10d07y265gmmuvt4z0w9aw880jnsr700juxf95n"
EXPLORER_TC="https://finder.hexxagon.io/columbus-5"

# ─────────────────────────────────────────────────────────────────────────────
# EXCHANGE RATE FORMULA
# ─────────────────────────────────────────────────────────────────────────────
# exchange_rate = (LUNC_USD / NATIVE_USD) * 1e12
#
# The Terra Classic IGP oracle payment formula is:
#   payment_uluna = gas_amount * gas_price * exchange_rate / 1e12
#
# Where:
#   gas_amount  = gas units to execute on destination (e.g. 300000)
#   gas_price   = destination gas price in native wei (e.g. 3e9 = 3 gwei for BSC)
#   exchange_rate = ratio of token prices scaled to 1e12
#
# Example (BSC mainnet, BNB=$617, LUNC=$0.00006824):
#   exchange_rate = (0.00006824 / 617) * 1e12 = 110531
#   fee = 300000 * 3000000000 * 110531 / 1e12 = 9947790000 uluna = 9948 LUNC
#
# Solana uses a different model (gas_price=1 lamport, exchange_rate pre-calculated):
#   Solana does not use EVM gwei model — fees are in compute units * lamports.
# ─────────────────────────────────────────────────────────────────────────────

calc_rate() {
    local lunc_usd="$1" native_usd="$2"
    python3 -c "r=($lunc_usd/$native_usd)*1e12; print(int(r))"
}

calc_fee_lunc() {
    local gas="$1" gas_price="$2" rate="$3" lunc_usd="$4"
    python3 -c "
fee = $gas * $gas_price * $rate / 1e12
lunc = fee / 1e6
usd = lunc * $lunc_usd
print(f'{int(fee)} uluna = {lunc:.2f} LUNC = \${usd:.5f} USD')
"
}

# ─────────────────────────────────────────────────────────────────────────────
# BANNER
# ─────────────────────────────────────────────────────────────────────────────
> "$LOG_FILE"
echo -e "${C}${W}"
echo "╔══════════════════════════════════════════════════════════════════════════╗"
echo "║   🔮  UPDATE IGP ORACLE — Terra Classic Mainnet (columbus-5)           ║"
echo "╚══════════════════════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo -e "  Oracle:  ${G}${ORACLE}${NC}"
echo -e "  IGP:     ${G}${IGP}${NC}"
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# MODE: direct (owner) or governance (proposal only)
# ─────────────────────────────────────────────────────────────────────────────
MODE="${MODE:-direct}"
if [ "$MODE" = "governance" ]; then
    echo -e "${Y}Mode: GOVERNANCE — will generate a proposal JSON file only.${NC}"
elif [ -z "${TERRA_PRIVATE_KEY:-}" ]; then
    echo -e "${WARN}TERRA_PRIVATE_KEY not set."
    echo -n "  Enter hex key (no 0x, will not be shown): "
    read -rs TERRA_PRIVATE_KEY; echo ""
    [ -z "$TERRA_PRIVATE_KEY" ] && {
        echo -e "${WARN}No key provided — switching to GOVERNANCE mode (proposal only)."
        MODE="governance"
    }
fi

# ─────────────────────────────────────────────────────────────────────────────
# CHECK CURRENT ORACLE STATE
# ─────────────────────────────────────────────────────────────────────────────
echo -e "${C}${W}Current IGP Oracle state:${NC}"
echo "────────────────────────────────────────────────────────────────"

node --no-warnings -e "
const path = require('path');
const nm   = path.join('${PROJECT_ROOT}', 'node_modules');
const { CosmWasmClient } = require(path.join(nm, '@cosmjs/cosmwasm-stargate'));
async function main() {
    const client = await CosmWasmClient.connect('${RPC}');
    const domains = [
        {id:1,         name:'Ethereum mainnet', short:'ETH'},
        {id:56,        name:'BSC mainnet',      short:'BNB'},
        {id:1399811149,name:'Solana mainnet',   short:'SOL'},
    ];
    for (const d of domains) {
        try {
            const r = await client.queryContractSmart('${ORACLE}',
                {oracle:{get_exchange_rate_and_gas_price:{dest_domain:d.id}}});
            console.log('✅  domain '+d.id+' ('+d.name+'): exchange_rate='+r.exchange_rate+' gas_price='+r.gas_price);
        } catch(e) {
            console.log('❌  domain '+d.id+' ('+d.name+'): NOT CONFIGURED');
        }
    }
}
main().catch(e => console.error('Query error:', e.message));
" 2>/dev/null
echo "────────────────────────────────────────────────────────────────"
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# PRICE INPUTS (from env or interactive)
# ─────────────────────────────────────────────────────────────────────────────
echo -e "${W}Token prices (USD) for exchange rate calculation:${NC}"
echo -e "${DIM:-}  Formula: exchange_rate = (LUNC_USD / NATIVE_USD) * 1e12${NC}"
echo ""

if [ -z "${LUNC_USD:-}" ]; then
    echo -n "  LUNC price in USD (e.g. 0.00006824): "
    read -r LUNC_USD
fi
if [ -z "${ETH_USD:-}" ]; then
    echo -n "  ETH price in USD  (e.g. 3500.00):   "
    read -r ETH_USD
fi
if [ -z "${BNB_USD:-}" ]; then
    echo -n "  BNB price in USD  (e.g. 617.38):    "
    read -r BNB_USD
fi
if [ -z "${SOL_USD:-}" ]; then
    echo -n "  SOL price in USD  (e.g. 150.00):    "
    read -r SOL_USD
fi

# Gas prices (wei/gwei on each chain)
GAS_PRICE_ETH="${GAS_PRICE_ETH:-10000000000}"   # 10 gwei — conservative ETH mainnet
GAS_PRICE_BSC="${GAS_PRICE_BSC:-3000000000}"    # 3 gwei  — BSC mainnet
GAS_PRICE_SOL="${GAS_PRICE_SOL:-1}"             # Solana: lamport model (gas_price=1)

# ─────────────────────────────────────────────────────────────────────────────
# COMPUTE EXCHANGE RATES
# ─────────────────────────────────────────────────────────────────────────────
RATE_ETH=$(calc_rate "$LUNC_USD" "$ETH_USD")
RATE_BSC=$(calc_rate "$LUNC_USD" "$BNB_USD")
# Solana: different formula — (LUNC_USD / SOL_USD) * 1e12 BUT gas_price=1 lamport
# so: payment = gas_cu * 1 * rate / 1e12 = gas_cu * (LUNC/SOL) * SCALE
# We use 1e15 scale to get meaningful fees for 300k compute units:
RATE_SOL=$(python3 -c "r=($LUNC_USD/$SOL_USD)*1e15; print(int(r))")
# Override with well-tested value if not already reasonable
# (Solana testnet used 40000000000000 which was calibrated manually)

echo ""
echo -e "${W}Calculated exchange rates:${NC}"
echo "────────────────────────────────────────────────────────────────"
printf "  %-28s exchange_rate=%-12s  gas_price=%s\n" \
    "ETH mainnet  (domain 1)"         "$RATE_ETH"  "${GAS_PRICE_ETH} wei ($(python3 -c "print(${GAS_PRICE_ETH}/1e9,end='')") gwei)"
printf "  %-28s exchange_rate=%-12s  gas_price=%s\n" \
    "BSC mainnet  (domain 56)"        "$RATE_BSC"  "${GAS_PRICE_BSC} wei ($(python3 -c "print(${GAS_PRICE_BSC}/1e9,end='')") gwei)"
printf "  %-28s exchange_rate=%-12s  gas_price=%s\n" \
    "Solana mainnet (domain 1399811149)" "$RATE_SOL" "${GAS_PRICE_SOL} (lamport model)"
echo "────────────────────────────────────────────────────────────────"
echo ""
echo -e "${W}Estimated fees (300k gas):${NC}"
echo -e "  ETH:    $(calc_fee_lunc 300000 "$GAS_PRICE_ETH" "$RATE_ETH" "$LUNC_USD")"
echo -e "  BSC:    $(calc_fee_lunc 300000 "$GAS_PRICE_BSC" "$RATE_BSC" "$LUNC_USD")"
echo -e "  Solana: $(calc_fee_lunc 300000 "$GAS_PRICE_SOL" "$RATE_SOL" "$LUNC_USD") (300k compute units)"
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# SELECT DOMAINS TO UPDATE
# ─────────────────────────────────────────────────────────────────────────────
if [ -z "${DOMAINS:-}" ]; then
    echo -e "${W}Which domains to configure?${NC}"
    echo "  [1] ETH mainnet  (domain 1)"
    echo "  [2] BSC mainnet  (domain 56)"
    echo "  [3] Solana mainnet (domain 1399811149)"
    echo "  [4] All (1 + 56 + 1399811149)"
    echo ""
    echo -n "  Selection [1/2/3/4]: "
    read -r SEL_DOMAIN
    case "$SEL_DOMAIN" in
        1) DOMAINS="1" ;;
        2) DOMAINS="56" ;;
        3) DOMAINS="1399811149" ;;
        4) DOMAINS="1,56,1399811149" ;;
        *) echo -e "${ERR} Invalid selection."; exit 1 ;;
    esac
fi

# ─────────────────────────────────────────────────────────────────────────────
# BUILD CONFIG ARRAY
# ─────────────────────────────────────────────────────────────────────────────
declare -a CFG_DOMAINS=()
declare -a CFG_RATES=()
declare -a CFG_GAS_PRICES=()

IFS=',' read -ra DOMAIN_LIST <<< "$DOMAINS"
for D in "${DOMAIN_LIST[@]}"; do
    D="${D// /}"
    case "$D" in
        1)
            CFG_DOMAINS+=("$D"); CFG_RATES+=("$RATE_ETH"); CFG_GAS_PRICES+=("$GAS_PRICE_ETH")
            ;;
        56)
            CFG_DOMAINS+=("$D"); CFG_RATES+=("$RATE_BSC"); CFG_GAS_PRICES+=("$GAS_PRICE_BSC")
            ;;
        1399811149)
            CFG_DOMAINS+=("$D"); CFG_RATES+=("$RATE_SOL"); CFG_GAS_PRICES+=("$GAS_PRICE_SOL")
            ;;
        *)
            echo -e "${WARN}Unknown domain $D — provide custom rates via env vars."
            CFG_DOMAINS+=("$D")
            echo -n "  exchange_rate for domain $D: "; read -r CR
            echo -n "  gas_price for domain $D: "; read -r CGP
            CFG_RATES+=("$CR"); CFG_GAS_PRICES+=("$CGP")
            ;;
    esac
done

echo ""
echo -e "${W}Will configure:${NC}"
for i in "${!CFG_DOMAINS[@]}"; do
    echo -e "  domain ${C}${CFG_DOMAINS[$i]}${NC}  rate=${G}${CFG_RATES[$i]}${NC}  gas_price=${G}${CFG_GAS_PRICES[$i]}${NC}"
done
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# CONFIRMATION
# ─────────────────────────────────────────────────────────────────────────────
echo -n "  Proceed? [y/N]: "
read -r CONF
[[ ! "$CONF" =~ ^[sSyY]$ ]] && echo "Cancelled." && exit 0

# ─────────────────────────────────────────────────────────────────────────────
# GOVERNANCE MODE — generate proposal JSON
# ─────────────────────────────────────────────────────────────────────────────
if [ "$MODE" = "governance" ]; then
    PROPOSAL_FILE="$LOG_DIR/oracle-update-proposal-$(date +%Y%m%d-%H%M%S).json"

    # Build configs JSON array
    CONFIGS_JSON="["
    ROUTES_JSON="["
    for i in "${!CFG_DOMAINS[@]}"; do
        [ $i -gt 0 ] && CONFIGS_JSON+=","
        [ $i -gt 0 ] && ROUTES_JSON+=","
        CONFIGS_JSON+="{\"remote_domain\":${CFG_DOMAINS[$i]},\"token_exchange_rate\":\"${CFG_RATES[$i]}\",\"gas_price\":\"${CFG_GAS_PRICES[$i]}\"}"
        ROUTES_JSON+="{\"domain\":${CFG_DOMAINS[$i]},\"route\":\"${ORACLE}\"}"
    done
    CONFIGS_JSON+="]"
    ROUTES_JSON+="]"

    cat > "$PROPOSAL_FILE" <<PROPJSON
{
  "title": "Update IGP Oracle — Terra Classic Mainnet",
  "description": "Updates gas price oracle data for destination chains: $(echo "${CFG_DOMAINS[@]}" | tr ' ' ','). Prices: LUNC=\$${LUNC_USD}, ETH=\$${ETH_USD:-N/A}, BNB=\$${BNB_USD:-N/A}, SOL=\$${SOL_USD:-N/A}. Generated $(date '+%Y-%m-%d %H:%M:%S').",
  "messages": [
    {
      "type": "wasm/MsgExecuteContract",
      "value": {
        "sender": "${GOV_MODULE}",
        "contract": "${ORACLE}",
        "msg": {
          "set_remote_gas_data_configs": {
            "configs": ${CONFIGS_JSON}
          }
        },
        "funds": []
      }
    },
    {
      "type": "wasm/MsgExecuteContract",
      "value": {
        "sender": "${GOV_MODULE}",
        "contract": "${IGP}",
        "msg": {
          "router": {
            "set_routes": {
              "set": ${ROUTES_JSON}
            }
          }
        },
        "funds": []
      }
    }
  ],
  "deposit": "512000000uluna"
}
PROPJSON

    echo ""
    echo -e "${OK} Proposal JSON generated: ${Y}${PROPOSAL_FILE}${NC}"
    echo ""
    echo -e "${W}Submit via terrad:${NC}"
    echo -e "  terrad tx gov submit-proposal ${PROPOSAL_FILE} \\"
    echo -e "    --from YOUR_KEY --chain-id columbus-5 \\"
    echo -e "    --node ${RPC}:443 \\"
    echo -e "    --gas auto --gas-adjustment 1.5 --gas-prices 28.5uluna -y"
    echo ""
    echo -e "${W}Vote YES (after getting proposal ID):${NC}"
    echo -e "  terrad tx gov vote PROPOSAL_ID yes \\"
    echo -e "    --from YOUR_KEY --chain-id columbus-5 \\"
    echo -e "    --node ${RPC}:443 \\"
    echo -e "    --gas auto --gas-adjustment 1.5 --gas-prices 28.5uluna -y"
    exit 0
fi

# ─────────────────────────────────────────────────────────────────────────────
# DIRECT MODE — execute transactions as owner
# ─────────────────────────────────────────────────────────────────────────────
PRIV_CLEAN="${TERRA_PRIVATE_KEY#0x}"

# Build JS arrays
JS_CONFIGS="["
JS_ROUTES="["
for i in "${!CFG_DOMAINS[@]}"; do
    [ $i -gt 0 ] && JS_CONFIGS+="," && JS_ROUTES+=","
    JS_CONFIGS+="{remote_domain:${CFG_DOMAINS[$i]},token_exchange_rate:'${CFG_RATES[$i]}',gas_price:'${CFG_GAS_PRICES[$i]}'}"
    JS_ROUTES+="{domain:${CFG_DOMAINS[$i]},route:'${ORACLE}'}"
done
JS_CONFIGS+="]"
JS_ROUTES+="]"

echo ""
echo -e "${C}${W}Executing transactions...${NC}"
echo ""

RESULT=$(node --no-warnings -e "
const path = require('path');
const nm   = path.join('${PROJECT_ROOT}', 'node_modules');
const { SigningCosmWasmClient } = require(path.join(nm, '@cosmjs/cosmwasm-stargate'));
const { DirectSecp256k1Wallet } = require(path.join(nm, '@cosmjs/proto-signing'));
const { GasPrice }              = require(path.join(nm, '@cosmjs/stargate'));
const { fromHex }               = require(path.join(nm, '@cosmjs/encoding'));

const ORACLE = '${ORACLE}';
const IGP    = '${IGP}';
const CONFIGS = ${JS_CONFIGS};
const ROUTES  = ${JS_ROUTES};

async function main() {
    const wallet = await DirectSecp256k1Wallet.fromKey(fromHex('${PRIV_CLEAN}'), 'terra');
    const [account] = await wallet.getAccounts();
    console.log('Sender: ' + account.address);

    const client = await SigningCosmWasmClient.connectWithSigner(
        '${RPC}', wallet, { gasPrice: GasPrice.fromString('28.325uluna') }
    );

    // TX 1: set_remote_gas_data_configs on oracle
    console.log('TX1: set_remote_gas_data_configs...');
    const r1 = await client.execute(
        account.address, ORACLE,
        { set_remote_gas_data_configs: { configs: CONFIGS } },
        'auto', 'update IGP oracle — update-igp-oracle.sh'
    );
    console.log('TX1_HASH=' + r1.transactionHash);

    // TX 2: router.set_routes on IGP
    console.log('TX2: router.set_routes...');
    const r2 = await client.execute(
        account.address, IGP,
        { router: { set_routes: { set: ROUTES } } },
        'auto', 'set IGP routes — update-igp-oracle.sh'
    );
    console.log('TX2_HASH=' + r2.transactionHash);
    console.log('SUCCESS');
}
main().catch(e => { console.log('ERROR: ' + e.message); process.exit(1); });
" 2>/dev/null)

echo "$RESULT" | while IFS= read -r line; do
    case "$line" in
        TX1_HASH=*) echo -e "  ${OK} Oracle TX: ${B}${EXPLORER_TC}/tx/${line#TX1_HASH=}${NC}" ;;
        TX2_HASH=*) echo -e "  ${OK} Routes TX: ${B}${EXPLORER_TC}/tx/${line#TX2_HASH=}${NC}" ;;
        ERROR:*)    echo -e "  ${ERR} ${line#ERROR: }" ;;
        SUCCESS)    ;;
        *)          echo -e "  ${line}" ;;
    esac
done

if ! echo "$RESULT" | grep -q "^SUCCESS"; then
    echo -e "${ERR} Transaction failed. Check log: ${LOG_FILE}"
    echo "$RESULT" >> "$LOG_FILE"
    exit 1
fi

# ─────────────────────────────────────────────────────────────────────────────
# VERIFY ON-CHAIN
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo -e "${C}${W}Verifying on-chain...${NC}"
sleep 4

node --no-warnings -e "
const path = require('path');
const nm   = path.join('${PROJECT_ROOT}', 'node_modules');
const { CosmWasmClient } = require(path.join(nm, '@cosmjs/cosmwasm-stargate'));
const LUNC = ${LUNC_USD};
async function main() {
    const client = await CosmWasmClient.connect('${RPC}');
    const domains = [${CFG_DOMAINS[*]}];
    for (const d of domains) {
        try {
            const r = await client.queryContractSmart('${ORACLE}',
                {oracle:{get_exchange_rate_and_gas_price:{dest_domain:d}}});
            const fee = 300000 * Number(r.gas_price) * Number(r.exchange_rate) / 1e12;
            const lunc = fee / 1e6;
            const usd = lunc * LUNC;
            console.log('✅ domain '+d+': rate='+r.exchange_rate+' gas='+r.gas_price+
                ' | fee(300k gas)='+lunc.toFixed(2)+' LUNC (\$'+usd.toFixed(5)+')');
        } catch(e) {
            console.log('❌ domain '+d+': ' + e.message.substring(0,60));
        }
    }
}
main().catch(e => console.error(e.message));
" 2>/dev/null

echo ""
echo -e "${OK} ${W}Oracle updated successfully!${NC}"
echo -e "  Log: ${Y}${LOG_FILE}${NC}"
echo ""

# Save log
{
    echo "=== update-igp-oracle.sh — $(date) ==="
    echo "Domains: ${CFG_DOMAINS[*]}"
    echo "LUNC_USD: ${LUNC_USD}"
    echo "ETH_USD: ${ETH_USD:-N/A}  BNB_USD: ${BNB_USD:-N/A}  SOL_USD: ${SOL_USD:-N/A}"
    for i in "${!CFG_DOMAINS[@]}"; do
        echo "  domain=${CFG_DOMAINS[$i]} rate=${CFG_RATES[$i]} gas_price=${CFG_GAS_PRICES[$i]}"
    done
    echo "$RESULT"
} >> "$LOG_FILE"
