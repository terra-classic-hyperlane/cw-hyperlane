#!/usr/bin/env bash
# =============================================================================
#  transfer-remote-terra.sh
#  Sends tokens via Hyperlane Warp Route: Terra Classic → EVM / Sealevel
#
#  Usage:
#    export TERRA_PRIVATE_KEY="<hex_privkey>"
#    ./transfer-remote-terra.sh
#
#  Optional variables for non-interactive execution:
#    TOKEN_KEY       = xpto | xptv | xpv | juris | wlunc | ustc
#    DEST_NETWORK    = sepolia | bsctestnet | solanatestnet
#    RECIPIENT       = 0x... (EVM) | Base58 (Solana)
#    AMOUNT          = valor em unidades mínimas (uXPTO, uLUNC etc.)
#    IGP_FEE_ULUNA   = manual fee (e.g.: 1780832150). If empty, queries IGP.
# =============================================================================
set -euo pipefail

# ─── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'; DIM='\033[2m'

# ─── Paths ────────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$SCRIPT_DIR/log"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/transfer-remote-terra.log"
EVM_CFG="$SCRIPT_DIR/warp-evm-config.json"
SOL_CFG="$SCRIPT_DIR/warp-sealevel-config.json"

# Fixed Terra Classic addresses
TC_RPC="https://rpc.terra-classic.hexxagon.dev"
TC_LCD="https://lcd.terra-classic.hexxagon.dev"
TC_CHAIN_ID="rebel-2"
TC_IGP="terra1n70g3vg7xge6q8m44rudm4y6fm6elpspwsgfmfphs3teezpak6cs6wxlk9"

# Override with config values if it exists
if command -v jq &>/dev/null && [ -f "$EVM_CFG" ]; then
    TC_RPC=$(jq -r '.terra_classic.rpc  // "https://rpc.terra-classic.hexxagon.dev"' "$EVM_CFG")
    TC_LCD=$(jq -r '.terra_classic.lcd  // "https://lcd.terra-classic.hexxagon.dev"' "$EVM_CFG")
    TC_CHAIN_ID=$(jq -r '.terra_classic.chain_id // "rebel-2"' "$EVM_CFG")
fi

# ─── Banner ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${CYAN}╔═══════════════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${CYAN}║   🌉  TRANSFER REMOTE — Terra Classic → Other Network     ║${RESET}"
echo -e "${BOLD}${CYAN}╚═══════════════════════════════════════════════════════════╝${RESET}"
echo ""

# ─── Dependencies ────────────────────────────────────────────────────────────
for dep in node jq curl python3; do
    if ! command -v "$dep" &>/dev/null; then
        echo -e "${RED}❌ Dependency not found: ${dep}${RESET}"
        exit 1
    fi
done

# Locate node_modules
PROJECT_ROOT="$SCRIPT_DIR"
while [ "$PROJECT_ROOT" != "/" ] && [ ! -f "$PROJECT_ROOT/package.json" ]; do
    PROJECT_ROOT="$(dirname "$PROJECT_ROOT")"
done
if [ ! -d "$PROJECT_ROOT/node_modules/@cosmjs/cosmwasm-stargate" ]; then
    echo -e "${RED}❌ node_modules/@cosmjs/cosmwasm-stargate not found in $PROJECT_ROOT${RESET}"
    echo -e "   Execute: cd $PROJECT_ROOT && yarn install"
    exit 1
fi

# ─── Private key ──────────────────────────────────────────────────────────────
if [ -z "${TERRA_PRIVATE_KEY:-}" ]; then
    echo -e "${YELLOW}⚠️  TERRA_PRIVATE_KEY not set.${RESET}"
    echo -n "   Enter your hex private key (will not be displayed): "
    read -rs TERRA_PRIVATE_KEY; echo ""
    [ -z "$TERRA_PRIVATE_KEY" ] && echo -e "${RED}❌ Key not provided.${RESET}" && exit 1
fi

# ─── Check configs ────────────────────────────────────────────────────────────
[ ! -f "$EVM_CFG" ] && echo -e "${RED}❌ Not found: $EVM_CFG${RESET}" && exit 1
[ ! -f "$SOL_CFG" ] && echo -e "${RED}❌ Not found: $SOL_CFG${RESET}" && exit 1

# ─── Build list of available options (token × network) ──────────────────────
# Format: "TOKEN_KEY|DEST_NETWORK|DOMAIN|TYPE|COLLATERAL|WARP_TC|WARP_DEST|DEST_TYPE"
declare -a OPTIONS=()
declare -a LABELS=()

# EVM networks
while IFS= read -r entry; do
    NET=$(echo "$entry"    | cut -d'|' -f1)
    DOMAIN=$(echo "$entry" | cut -d'|' -f2)
    TOKEN=$(echo "$entry"  | cut -d'|' -f3)
    WARP_DEST=$(echo "$entry" | cut -d'|' -f4)

    # Get token data on Terra Classic
    TC_TYPE=$(jq -r --arg t "$TOKEN" '.terra_classic.tokens[$t].terra_warp.type // ""' "$EVM_CFG")
    TC_WARP=$(jq -r --arg t "$TOKEN" '.terra_classic.tokens[$t].terra_warp.warp_address // ""' "$EVM_CFG")
    TC_COLL=$(jq -r --arg t "$TOKEN" '.terra_classic.tokens[$t].terra_warp.collateral_address // ""' "$EVM_CFG")
    TC_SYM=$(jq  -r --arg t "$TOKEN" '.terra_classic.tokens[$t].symbol // $t' "$EVM_CFG")
    DISP=$(jq    -r --arg n "$NET" '.networks[$n].display_name // $n' "$EVM_CFG")

    [ -z "$TC_WARP" ] || [ "$TC_WARP" = "null" ] && continue

    OPT="${TOKEN}|${NET}|${DOMAIN}|${TC_TYPE}|${TC_COLL}|${TC_WARP}|${WARP_DEST}|evm"
    OPTIONS+=("$OPT")
    LABELS+=("  ${TC_SYM} → ${DISP}  (domain ${DOMAIN})")
done < <(jq -r '
  .networks | to_entries[]
  | select(.value.enabled == true)
  | .key as $net
  | .value.domain as $dom
  | .value.warp_tokens | to_entries[]
  | select((.value | type) == "object")
  | select(.value.deployed == true and (.value.address // "") != "")
  | [$net, ($dom|tostring), .key, .value.address] | join("|")
' "$EVM_CFG" 2>/dev/null)

# Sealevel networks
while IFS= read -r entry; do
    NET=$(echo "$entry"    | cut -d'|' -f1)
    DOMAIN=$(echo "$entry" | cut -d'|' -f2)
    TOKEN=$(echo "$entry"  | cut -d'|' -f3)
    PROG_HEX=$(echo "$entry" | cut -d'|' -f4)

    # Get token data on Terra Classic (busca no EVM config que tem os tokens TC)
    TC_TYPE=$(jq -r --arg t "$TOKEN" '.terra_classic.tokens[$t].terra_warp.type // ""' "$EVM_CFG")
    TC_WARP=$(jq -r --arg t "$TOKEN" '.terra_classic.tokens[$t].terra_warp.warp_address // ""' "$EVM_CFG")
    TC_COLL=$(jq -r --arg t "$TOKEN" '.terra_classic.tokens[$t].terra_warp.collateral_address // ""' "$EVM_CFG")
    TC_SYM=$(jq  -r --arg t "$TOKEN" '.terra_classic.tokens[$t].symbol // $t' "$EVM_CFG")
    DISP=$(jq    -r --arg n "$NET" '.networks[$n].display_name // $n' "$SOL_CFG")

    [ -z "$TC_WARP" ] || [ "$TC_WARP" = "null" ] && continue

    OPT="${TOKEN}|${NET}|${DOMAIN}|${TC_TYPE}|${TC_COLL}|${TC_WARP}|${PROG_HEX}|sealevel"
    OPTIONS+=("$OPT")
    LABELS+=("  ${TC_SYM} → ${DISP}  (domain ${DOMAIN})")
done < <(jq -r '
  .networks | to_entries[]
  | select(.value.enabled == true)
  | .key as $net
  | .value.domain as $dom
  | .value.warp_tokens | to_entries[]
  | select(.value.deployed == true and (.value.program_hex // "") != "")
  | [$net, ($dom|tostring), .key, .value.program_hex] | join("|")
' "$SOL_CFG" 2>/dev/null)

if [ ${#OPTIONS[@]} -eq 0 ]; then
    echo -e "${RED}❌ No deployed token/network combination found in configs.${RESET}"
    echo -e "   Verifique ${EVM_CFG} e ${SOL_CFG}."
    exit 1
fi

# ─── Interactive selection or via variables ─────────────────────────────────
SELECTED_IDX=""
if [ -n "${TOKEN_KEY:-}" ] && [ -n "${DEST_NETWORK:-}" ]; then
    # Non-interactive mode: search for combination
    for i in "${!OPTIONS[@]}"; do
        OPT="${OPTIONS[$i]}"
        T=$(echo "$OPT" | cut -d'|' -f1)
        N=$(echo "$OPT" | cut -d'|' -f2)
        [ "$T" = "$TOKEN_KEY" ] && [ "$N" = "$DEST_NETWORK" ] && SELECTED_IDX="$i" && break
    done
    if [ -z "$SELECTED_IDX" ]; then
        echo -e "${RED}❌ Combination TOKEN_KEY='${TOKEN_KEY}' + DEST_NETWORK='${DEST_NETWORK}' not found.${RESET}"
        exit 1
    fi
else
    # Interactive mode
    echo -e "${BOLD}Select the token and destination network:${RESET}"
    echo ""
    for i in "${!LABELS[@]}"; do
        echo -e "  ${CYAN}[$((i+1))]${RESET} ${LABELS[$i]}"
    done
    echo ""
    echo -n "  Opção [1-${#OPTIONS[@]}]: "
    read -r SEL
    if ! [[ "$SEL" =~ ^[0-9]+$ ]] || [ "$SEL" -lt 1 ] || [ "$SEL" -gt "${#OPTIONS[@]}" ]; then
        echo -e "${RED}❌ Invalid option.${RESET}" && exit 1
    fi
    SELECTED_IDX=$((SEL-1))
fi

# ─── Extract data from selected option ──────────────────────────────────────
SEL_OPT="${OPTIONS[$SELECTED_IDX]}"
TOKEN_KEY=$(echo "$SEL_OPT"   | cut -d'|' -f1)
DEST_NET=$(echo "$SEL_OPT"    | cut -d'|' -f2)
DEST_DOMAIN=$(echo "$SEL_OPT" | cut -d'|' -f3)
TC_TYPE=$(echo "$SEL_OPT"     | cut -d'|' -f4)
TC_COLL=$(echo "$SEL_OPT"     | cut -d'|' -f5)
TC_WARP=$(echo "$SEL_OPT"     | cut -d'|' -f6)
WARP_DEST=$(echo "$SEL_OPT"   | cut -d'|' -f7)
DEST_TYPE=$(echo "$SEL_OPT"   | cut -d'|' -f8)

TOKEN_UPPER="${TOKEN_KEY^^}"
NET_UPPER="${DEST_NET^^}"

echo ""
echo -e "${BOLD}${GREEN}✅ Selected:${RESET}  ${TOKEN_UPPER}  →  ${NET_UPPER}  (domain ${DEST_DOMAIN})"
echo -e "   TC token type : ${TC_TYPE}"
echo -e "   Warp TC       : ${TC_WARP}"
[ -n "$TC_COLL" ] && [ "$TC_COLL" != "null" ] && \
    echo -e "   Collateral    : ${TC_COLL}"
echo -e "   Dest Warp     : ${WARP_DEST}"
echo ""

# ─── Recipient ────────────────────────────────────────────────────────────────
if [ -z "${RECIPIENT:-}" ]; then
    if [ "$DEST_TYPE" = "evm" ]; then
        echo -e "${DIM}  EVM format: 0x... (e.g.: 0x867f9ce9f0d7218b016351cb6122406e6d247a5e)${RESET}"
    else
        echo -e "${DIM}  Solana format: Base58 (e.g.: EMAYGfEyhywUyEX6kfG5FZZMfznmKXM8PbWpkJhJ9Jjd)${RESET}"
        echo -e "${DIM}  Or 64-char hex without 0x${RESET}"
    fi
    echo -n "  Recipient address: "
    read -r RECIPIENT
fi
[ -z "$RECIPIENT" ] && echo -e "${RED}❌ Recipient not provided.${RESET}" && exit 1

# ─── Convert recipient to bytes32 (hex 64 chars without 0x) ────────────────
if [ "$DEST_TYPE" = "evm" ]; then
    # EVM: remove 0x, left-pad with zeros to 64 chars
    ADDR_CLEAN="${RECIPIENT#0x}"
    ADDR_CLEAN="${ADDR_CLEAN#0X}"
    ADDR_CLEAN=$(echo "$ADDR_CLEAN" | tr '[:upper:]' '[:lower:]')
    if [ ${#ADDR_CLEAN} -gt 64 ] || ! [[ "$ADDR_CLEAN" =~ ^[0-9a-f]+$ ]]; then
        echo -e "${RED}❌ Invalid EVM address: ${RECIPIENT}${RESET}"
        exit 1
    fi
    RECIPIENT_B32=$(printf '%064s' "$ADDR_CLEAN" | tr ' ' '0')
else
    # Sealevel: can be Base58 or direct hex
    if [[ "$RECIPIENT" =~ ^[0-9a-fA-F]{64}$ ]]; then
        RECIPIENT_B32=$(echo "$RECIPIENT" | tr '[:upper:]' '[:lower:]')
    elif [[ "$RECIPIENT" =~ ^0x[0-9a-fA-F]{64}$ ]]; then
        RECIPIENT_B32="${RECIPIENT#0x}"
    else
        # Try decoding as Base58 via Node.js
        RECIPIENT_B32=$(node -e "
const bs58 = require('${PROJECT_ROOT}/node_modules/bs58');
try {
    const buf = bs58.decode('${RECIPIENT}');
    if (buf.length !== 32) { process.stderr.write('ERR: invalid size: ' + buf.length + '\n'); process.exit(1); }
    process.stdout.write(Buffer.from(buf).toString('hex'));
} catch(e) { process.stderr.write('ERR: ' + e.message + '\n'); process.exit(1); }
" 2>&1) || {
            echo -e "${RED}❌ Invalid Solana address: ${RECIPIENT}${RESET}"
            echo -e "   Use Base58 (e.g.: EMAYGf...) or 64-char hex."
            exit 1
        }
    fi
fi

echo -e "   Recipient bytes32 : ${RECIPIENT_B32}"

# ─── Amount ───────────────────────────────────────────────────────────────────
if [ -z "${AMOUNT:-}" ]; then
    TOKEN_SYM=$(jq -r --arg t "$TOKEN_KEY" '.terra_classic.tokens[$t].symbol // $t' "$EVM_CFG")
    DECIMALS=$(jq -r --arg t "$TOKEN_KEY" '.terra_classic.tokens[$t].decimals // 6' "$EVM_CFG")
    echo ""
    echo -e "${DIM}  Decimals: ${DECIMALS} — e.g.: 1 ${TOKEN_SYM} = 1$(printf '%0.s0' $(seq 1 $DECIMALS))${RESET}"
    echo -n "  Amount (in minimum units, e.g.: 10000000): "
    read -r AMOUNT
fi
if ! [[ "$AMOUNT" =~ ^[0-9]+$ ]] || [ "$AMOUNT" -eq 0 ] 2>/dev/null; then
    echo -e "${RED}❌ Invalid amount: ${AMOUNT}${RESET}" && exit 1
fi

echo -e "   Amount            : ${AMOUNT}"
echo ""

# ─── Query IGP fee via LCD ────────────────────────────────────────────────────
if [ -n "${IGP_FEE_ULUNA:-}" ]; then
    echo -e "${YELLOW}⚠️  Manual fee: ${IGP_FEE_ULUNA} uluna${RESET}"
    IGP_FEE="$IGP_FEE_ULUNA"
else
    echo -e "${DIM}  Querying IGP fee for domain ${DEST_DOMAIN}...${RESET}"
    GAS_AMOUNT="300000"
    QUERY_B64=$(python3 -c "
import json,base64
q={'quote_gas_payment':{'dest_domain':${DEST_DOMAIN},'gas_amount':'${GAS_AMOUNT}'}}
print(base64.b64encode(json.dumps(q).encode()).decode())
")

    IGP_FEE=""
    # Try multiple LCD endpoints
    for LCD_TRY in "$TC_LCD" "https://terra-classic-lcd.publicnode.com" "https://lcd.terrarebels.net"; do
        IGP_RESP=$(curl -s --max-time 10 \
            -H "Accept: application/json" \
            -H "User-Agent: hyperlane-warp/1.0" \
            "${LCD_TRY}/cosmwasm/wasm/v1/contract/${TC_IGP}/smart/${QUERY_B64}" 2>/dev/null || echo "")
        IGP_FEE=$(echo "$IGP_RESP" | jq -r '.data.gas_needed // ""' 2>/dev/null || echo "")
        if [ -n "$IGP_FEE" ] && [ "$IGP_FEE" != "null" ] && [[ "$IGP_FEE" =~ ^[0-9]+$ ]]; then
            echo -e "${GREEN}✅ IGP fee calculado: ${IGP_FEE} uluna  (via ${LCD_TRY})${RESET}"
            break
        fi
        IGP_FEE=""
    done

    if [ -z "$IGP_FEE" ]; then
        # Fallback: values based on real project usage
        case "$DEST_DOMAIN" in
            11155111)   IGP_FEE="1780832150" ;;  # Sepolia (real historical value)
            97)         IGP_FEE="500000000"  ;;  # BSC Testnet
            1399811150) IGP_FEE="300000"     ;;  # Solana Testnet
            *)          IGP_FEE="1000000000" ;;
        esac
        echo -e "${YELLOW}⚠️  IGP query failed on all LCDs, using default fee: ${IGP_FEE} uluna${RESET}"
        echo -e "${DIM}     (use IGP_FEE_ULUNA=<value> to override)${RESET}"
    fi
fi

# ─── Confirmation ─────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${BOLD}  Transfer summary${RESET}"
echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "  Token          : ${TOKEN_UPPER}  (${TC_TYPE})"
echo -e "  Destination    : ${NET_UPPER}  (domain ${DEST_DOMAIN})"
echo -e "  Recipient      : ${RECIPIENT}"
echo -e "  Recipient b32  : ${RECIPIENT_B32}"
echo -e "  Amount         : ${AMOUNT}"
echo -e "  Fee IGP        : ${IGP_FEE} uluna"
echo -e "  Warp TC        : ${TC_WARP}"
[ -n "$TC_COLL" ] && [ "$TC_COLL" != "null" ] && \
    echo -e "  Collateral CW20: ${TC_COLL}"
echo ""

if [[ "${AUTO_CONFIRM:-}" =~ ^[sStTyY1]$ ]]; then
    echo -e "${DIM}  (AUTO_CONFIRM enabled — proceeding automatically)${RESET}"
else
    echo -n "  Confirm and send? [y/N]: "
    read -r CONF
    [[ ! "$CONF" =~ ^[sSyY]$ ]] && echo -e "${YELLOW}⚠️  Cancelled by user.${RESET}" && exit 0
fi

echo ""
echo -e "${BOLD}${GREEN}▶ Executing transfer...${RESET}"
echo ""

# ─── Execute via Node.js + CosmJS ─────────────────────────────────────────────
RESULT=$(node --input-type=module << NODEJS 2>&1 || true
import { SigningCosmWasmClient } from '${PROJECT_ROOT}/node_modules/@cosmjs/cosmwasm-stargate/build/index.js';
import { DirectSecp256k1Wallet } from '${PROJECT_ROOT}/node_modules/@cosmjs/proto-signing/build/index.js';
import { GasPrice } from '${PROJECT_ROOT}/node_modules/@cosmjs/stargate/build/index.js';

const RPC         = '${TC_RPC}';
const PRIVATE_KEY = '${TERRA_PRIVATE_KEY}';
const TC_TYPE     = '${TC_TYPE}';
const TC_COLL     = '${TC_COLL}';
const TC_WARP     = '${TC_WARP}';
const DEST_DOMAIN = ${DEST_DOMAIN};
const RECIPIENT   = '${RECIPIENT_B32}';   // bytes32 without 0x
const AMOUNT      = '${AMOUNT}';
const IGP_FEE     = '${IGP_FEE}';

async function main() {
    // Wallet
    const privHex = PRIVATE_KEY.replace(/^0x/, '');
    const privBuf = Buffer.from(privHex, 'hex');
    const wallet  = await DirectSecp256k1Wallet.fromKey(privBuf, 'terra');
    const [account] = await wallet.getAccounts();
    console.log('Sender: ' + account.address);

    const client = await SigningCosmWasmClient.connectWithSigner(
        RPC, wallet,
        { gasPrice: GasPrice.fromString('0.015uluna') }
    );

    let txHash;

    if (TC_TYPE === 'cw20') {
        // ── CW20: increase_allowance + transfer_remote ──────────────────────
        console.log('CW20 mode: increase_allowance + transfer_remote');

        const msgs = [
            {
                typeUrl: '/cosmwasm.wasm.v1.MsgExecuteContract',
                value: {
                    sender:   account.address,
                    contract: TC_COLL,
                    msg: Buffer.from(JSON.stringify({
                        increase_allowance: {
                            spender: TC_WARP,
                            amount:  AMOUNT,
                            expires: { never: {} }
                        }
                    })),
                    funds: []
                }
            },
            {
                typeUrl: '/cosmwasm.wasm.v1.MsgExecuteContract',
                value: {
                    sender:   account.address,
                    contract: TC_WARP,
                    msg: Buffer.from(JSON.stringify({
                        transfer_remote: {
                            dest_domain: DEST_DOMAIN,
                            recipient:   RECIPIENT,
                            amount:      AMOUNT
                        }
                    })),
                    funds: [{ denom: 'uluna', amount: IGP_FEE }]
                }
            }
        ];

        const result = await client.signAndBroadcast(
            account.address, msgs, 'auto',
            'transfer_remote CW20 via Hyperlane Warp — transfer-remote-terra.sh'
        );
        if (result.code !== 0) throw new Error('Tx failed: ' + result.rawLog);
        txHash = result.transactionHash;

    } else {
        // ── Native: transfer_remote com funds ───────────────────────────────
        console.log('Native mode: transfer_remote with funds');

        const result = await client.execute(
            account.address, TC_WARP,
            {
                transfer_remote: {
                    dest_domain: DEST_DOMAIN,
                    recipient:   RECIPIENT,
                    amount:      AMOUNT
                }
            },
            'auto',
            'transfer_remote native via Hyperlane Warp — transfer-remote-terra.sh',
            [{ denom: 'uluna', amount: IGP_FEE }]
        );
        txHash = result.transactionHash;
    }

    console.log('TX_HASH=' + txHash);
    console.log('SUCCESS');
}

main().catch(e => { console.error('ERROR: ' + e.message); process.exit(1); });
NODEJS
)

# ─── Result ───────────────────────────────────────────────────────────────────
while IFS= read -r line; do
    echo -e "  ${DIM}${line}${RESET}"
done < <(echo "$RESULT" | grep -v "^TX_HASH=\|^SUCCESS\|^ERROR:" || true)

TX_HASH=$(echo "$RESULT" | grep "^TX_HASH=" | cut -d'=' -f2 || true)
IS_OK=$(echo "$RESULT"   | grep -c "^SUCCESS" || true)
IS_ERR=$(echo "$RESULT"  | grep "^ERROR:" | sed 's/^ERROR: //' || true)

echo ""
if [ "$IS_OK" -gt 0 ] && [ -n "$TX_HASH" ]; then
    echo -e "${BOLD}${GREEN}╔═══════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${BOLD}${GREEN}║  ✅  TRANSFER SENT SUCCESSFULLY!                          ║${RESET}"
    echo -e "${BOLD}${GREEN}╚═══════════════════════════════════════════════════════════╝${RESET}"
    echo ""
    echo -e "  ${BOLD}TX Hash :${RESET} ${TX_HASH}"
    echo -e "  ${BOLD}Explorer:${RESET} https://finder.hexxagon.io/rebel-2/tx/${TX_HASH}"
    echo ""
    echo -e "${DIM}  A mensagem será relayada pelo Hyperlane Relayer."
    echo -e "  Tempo estimado de entrega: 1-5 minutos.${RESET}"

    # ─── Save report ──────────────────────────────────────────────────────────
    REPORT_FILE="$LOG_DIR/TRANSFER-REMOTE-${NET_UPPER}-${TOKEN_UPPER}-$(date +%Y%m%d-%H%M%S).txt"
    {
        echo "TRANSFER REMOTE — Terra Classic → ${NET_UPPER}"
        echo "Date          : $(date)"
        echo "Token         : ${TOKEN_UPPER}  (${TC_TYPE})"
        echo "Destination   : ${NET_UPPER}  (domain ${DEST_DOMAIN})"
        echo "Recipient     : ${RECIPIENT}"
        echo "Recipient b32 : ${RECIPIENT_B32}"
        echo "Amount        : ${AMOUNT}"
        echo "Fee IGP       : ${IGP_FEE} uluna"
        echo "Warp TC       : ${TC_WARP}"
        [ -n "$TC_COLL" ] && [ "$TC_COLL" != "null" ] && echo "Collateral    : ${TC_COLL}"
        echo "TX Hash       : ${TX_HASH}"
        echo "Explorer      : https://finder.hexxagon.io/rebel-2/tx/${TX_HASH}"
    } > "$REPORT_FILE"
    echo -e "  ${BOLD}Report    :${RESET} ${REPORT_FILE}"
    echo ""
    # Log
    echo "$(date) | ${TOKEN_UPPER}→${NET_UPPER} | amount=${AMOUNT} | fee=${IGP_FEE} | tx=${TX_HASH}" >> "$LOG_FILE"
else
    echo -e "${RED}╔═══════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${RED}║  ❌  TRANSFER ERROR                                       ║${RESET}"
    echo -e "${RED}╚═══════════════════════════════════════════════════════════╝${RESET}"
    echo ""
    [ -n "$IS_ERR" ] && echo -e "${RED}  Error: ${IS_ERR}${RESET}"
    echo ""
    echo -e "${YELLOW}  Tips:${RESET}"
    echo -e "  • Check that the token/network are correctly configured"
    echo -e "  • Increase IGP_FEE_ULUNA if the error is about insufficient gas"
    echo -e "  • Check LUNC balance to cover the IGP fee"
    echo -e "  • Confirm that the warp route is active: enrollRemoteRouter configured"
    exit 1
fi
