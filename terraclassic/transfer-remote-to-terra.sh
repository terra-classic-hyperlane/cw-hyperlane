#!/usr/bin/env bash
# =============================================================================
#  transfer-remote-to-terra.sh
#  Sends tokens via Hyperlane Warp Route: EVM / Sealevel → Terra Classic
#
#  Interactive mode:
#    ./transfer-remote-to-terra.sh
#
#  Non-interactive mode (EVM):
#    export ETH_PRIVATE_KEY="0x..."
#    TOKEN_KEY=xpto SOURCE_NETWORK=sepolia \
#      RECIPIENT="terra18lr7ujd9nsgyr49930ppaajhadzrezam70j39k" \
#      AMOUNT=10000000 AUTO_CONFIRM=s \
#      ./transfer-remote-to-terra.sh
#
#  Non-interactive mode (Sealevel):
#    TOKEN_KEY=xpto SOURCE_NETWORK=solanatestnet \
#      RECIPIENT="terra18lr7ujd9nsgyr49930ppaajhadzrezam70j39k" \
#      AMOUNT=1000000 AUTO_CONFIRM=s \
#      ./transfer-remote-to-terra.sh
#
#  Optional variables:
#    ETH_PRIVATE_KEY  = EVM private key (0x...)
#    SOL_KEYPAIR      = path to Solana keypair (default: from config)
#    AUTO_CONFIRM     = y → skip confirmation
# =============================================================================
set -euo pipefail

# ─── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'; DIM='\033[2m'

# ─── Paths ────────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$SCRIPT_DIR/log"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/transfer-remote-to-terra.log"
EVM_CFG="$SCRIPT_DIR/warp-evm-config.json"
SOL_CFG="$SCRIPT_DIR/warp-sealevel-config.json"

# Terra Classic constants
TC_DOMAIN=1325
SEALEVEL_CLIENT="/home/lunc/hyperlane-monorepo/rust/sealevel/target/debug/hyperlane-sealevel-client"

# ─── Banner ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${CYAN}╔═══════════════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${CYAN}║   🌉  TRANSFER REMOTE — Other Network → Terra Classic     ║${RESET}"
echo -e "${BOLD}${CYAN}╚═══════════════════════════════════════════════════════════╝${RESET}"
echo ""

# ─── Dependencies ────────────────────────────────────────────────────────────
for dep in jq curl python3; do
    command -v "$dep" &>/dev/null || { echo -e "${RED}❌ Dependency not found: ${dep}${RESET}"; exit 1; }
done

[ ! -f "$EVM_CFG" ] && echo -e "${RED}❌ Not found: $EVM_CFG${RESET}" && exit 1
[ ! -f "$SOL_CFG" ] && echo -e "${RED}❌ Not found: $SOL_CFG${RESET}" && exit 1

# ─── Function: Convert Terra Classic bech32 → bytes32 (hex 64 chars without 0x) ─
bech32_to_b32() {
    local addr="$1"
    python3 -c "
import sys
addr = '${addr}'
# Basic validation
if not addr.startswith('terra1'):
    sys.stderr.write('ERR: address must start with terra1\n'); sys.exit(1)
try:
    import bech32 as b32mod
    hrp, data = b32mod.bech32_decode(addr)
    raw = bytes(b32mod.convertbits(data, 5, 8, False))
except ImportError:
    # Fallback: manual implementation
    CHARSET = 'qpzry9x8gf2tvdw0s3jn54khce6mua7l'
    pos = addr.rfind('1')
    data_chars = [CHARSET.find(c) for c in addr[pos+1:]]
    acc=0; bits=0; result=[]
    for val in data_chars[:-6]:
        acc = ((acc<<5)|val)
        bits += 5
        while bits >= 8:
            bits -= 8
            result.append((acc>>bits)&0xff)
    raw = bytes(result)
if len(raw) != 20:
    sys.stderr.write('ERR: unexpected size: ' + str(len(raw)) + '\n'); sys.exit(1)
print(raw.hex().zfill(64))
" 2>&1
}

# ─── Build list of available options ────────────────────────────────────────
declare -a OPTIONS=()
declare -a LABELS=()

# EVM → Terra Classic
while IFS= read -r entry; do
    NET=$(echo "$entry"    | cut -d'|' -f1)
    TOKEN=$(echo "$entry"  | cut -d'|' -f2)
    WARP=$(echo "$entry"   | cut -d'|' -f3)
    DOMAIN=$(echo "$entry" | cut -d'|' -f4)
    SYM=$(jq -r --arg t "$TOKEN" '.terra_classic.tokens[$t].symbol // $t' "$EVM_CFG")
    DISP=$(jq -r --arg n "$NET" '.networks[$n].display_name // $n' "$EVM_CFG")
    RPC_LIST=$(jq -r --arg n "$NET" '.networks[$n].rpc_urls[0] // ""' "$EVM_CFG")
    OPTIONS+=("${TOKEN}|${NET}|${WARP}|${DOMAIN}|evm|${RPC_LIST}")
    LABELS+=("  ${SYM} ← ${DISP}  (domain ${DOMAIN})")
done < <(jq -r '
  .networks | to_entries[]
  | select(.value.enabled == true)
  | .key as $net
  | .value.domain as $dom
  | .value.warp_tokens | to_entries[]
  | select((.value | type) == "object")
  | select(.value.deployed == true and (.value.address // "") != "")
  | [$net, .key, .value.address, ($dom|tostring)] | join("|")
' "$EVM_CFG" 2>/dev/null)

# Sealevel → Terra Classic
while IFS= read -r entry; do
    NET=$(echo "$entry"       | cut -d'|' -f1)
    TOKEN=$(echo "$entry"     | cut -d'|' -f2)
    PROG_ID=$(echo "$entry"   | cut -d'|' -f3)
    DOMAIN=$(echo "$entry"    | cut -d'|' -f4)
    SOL_RPC_V=$(echo "$entry" | cut -d'|' -f5)
    KEYPAIR_V=$(echo "$entry" | cut -d'|' -f6)
    SYM=$(jq -r --arg t "$TOKEN" '.terra_classic.tokens[$t].symbol // $t' "$EVM_CFG")
    DISP=$(jq -r --arg n "$NET" '.networks[$n].display_name // $n' "$SOL_CFG")
    MINT_V=$(echo "$entry" | cut -d'|' -f7)
    OPTIONS+=("${TOKEN}|${NET}|${PROG_ID}|${DOMAIN}|sealevel|${SOL_RPC_V}|${KEYPAIR_V}|${MINT_V}")
    LABELS+=("  ${SYM} ← ${DISP}  (domain ${DOMAIN})")
done < <(jq -r '
  .networks | to_entries[]
  | select(.value.enabled == true)
  | .key as $net
  | .value.domain as $dom
  | .value.rpc as $rpc
  | .value.keypair as $kp
  | .value.warp_tokens | to_entries[]
  | select(.value.deployed == true and (.value.program_id // "") != "")
  | [$net, .key, .value.program_id, ($dom|tostring), $rpc, $kp, (.value.mint_address // "")] | join("|")
' "$SOL_CFG" 2>/dev/null)

if [ ${#OPTIONS[@]} -eq 0 ]; then
    echo -e "${RED}❌ No options available in configs.${RESET}"; exit 1
fi

# ─── Seleção ──────────────────────────────────────────────────────────────────
SELECTED_IDX=""
if [ -n "${TOKEN_KEY:-}" ] && [ -n "${SOURCE_NETWORK:-}" ]; then
    for i in "${!OPTIONS[@]}"; do
        T=$(echo "${OPTIONS[$i]}" | cut -d'|' -f1)
        N=$(echo "${OPTIONS[$i]}" | cut -d'|' -f2)
        [ "$T" = "$TOKEN_KEY" ] && [ "$N" = "$SOURCE_NETWORK" ] && SELECTED_IDX="$i" && break
    done
    [ -z "$SELECTED_IDX" ] && \
        echo -e "${RED}❌ Combination TOKEN_KEY='${TOKEN_KEY}' + SOURCE_NETWORK='${SOURCE_NETWORK}' not found.${RESET}" && exit 1
else
    echo -e "${BOLD}Select the token and source network:${RESET}"
    echo ""
    for i in "${!LABELS[@]}"; do
        echo -e "  ${CYAN}[$((i+1))]${RESET} ${LABELS[$i]}"
    done
    echo ""
    echo -n "  Option [1-${#OPTIONS[@]}]: "
    read -r SEL
    [[ ! "$SEL" =~ ^[0-9]+$ ]] || [ "$SEL" -lt 1 ] || [ "$SEL" -gt "${#OPTIONS[@]}" ] && \
        echo -e "${RED}❌ Invalid option.${RESET}" && exit 1
    SELECTED_IDX=$((SEL-1))
fi

# ─── Extrair dados ────────────────────────────────────────────────────────────
SEL_OPT="${OPTIONS[$SELECTED_IDX]}"
TOKEN_KEY=$(echo "$SEL_OPT"   | cut -d'|' -f1)
SOURCE_NET=$(echo "$SEL_OPT"  | cut -d'|' -f2)
WARP_SRC=$(echo "$SEL_OPT"    | cut -d'|' -f3)   # EVM: 0x... | Sealevel: program_id
SRC_DOMAIN=$(echo "$SEL_OPT"  | cut -d'|' -f4)
SRC_TYPE=$(echo "$SEL_OPT"    | cut -d'|' -f5)   # evm | sealevel
SRC_RPC=$(echo "$SEL_OPT"     | cut -d'|' -f6)
SOL_KEYPAIR_CFG=$(echo "$SEL_OPT" | cut -d'|' -f7 2>/dev/null || echo "")
SOL_MINT=$(echo "$SEL_OPT"       | cut -d'|' -f8 2>/dev/null || echo "")

TOKEN_UPPER="${TOKEN_KEY^^}"
NET_UPPER="${SOURCE_NET^^}"
TOKEN_SYM=$(jq -r --arg t "$TOKEN_KEY" '.terra_classic.tokens[$t].symbol // $t' "$EVM_CFG")

echo ""
echo -e "${BOLD}${GREEN}✅ Selected:${RESET}  ${TOKEN_UPPER}  ←  ${NET_UPPER}  (source domain ${SRC_DOMAIN} → TC domain ${TC_DOMAIN})"
echo -e "   Type        : ${SRC_TYPE}"
echo -e "   Source Warp : ${WARP_SRC}"
echo -e "   Source RPC  : ${SRC_RPC}"
echo ""

# ─── Recipient (Terra Classic) ────────────────────────────────────────────────
if [ -z "${RECIPIENT:-}" ]; then
    echo -e "${DIM}  Format: terra1... (bech32 address of Terra Classic wallet)${RESET}"
    echo -n "  Recipient address (terra1...): "
    read -r RECIPIENT
fi
[ -z "$RECIPIENT" ] && echo -e "${RED}❌ Recipient not provided.${RESET}" && exit 1

# Convert to bytes32
RECIPIENT_B32=$(bech32_to_b32 "$RECIPIENT")
if [[ "$RECIPIENT_B32" == ERR* ]] || [ -z "$RECIPIENT_B32" ]; then
    echo -e "${RED}❌ Error converting Terra Classic address: ${RECIPIENT_B32}${RESET}"
    echo -e "   Make sure to use a valid bech32 address (terra1...)"
    exit 1
fi
echo -e "   Recipient bytes32 : ${RECIPIENT_B32}"

# ─── Amount ───────────────────────────────────────────────────────────────────
if [ -z "${AMOUNT:-}" ]; then
    DECIMALS=$(jq -r --arg t "$TOKEN_KEY" '.terra_classic.tokens[$t].decimals // 6' "$EVM_CFG")
    echo ""
    echo -e "${DIM}  Decimals: ${DECIMALS} — e.g.: 1 ${TOKEN_SYM} = 1$(python3 -c "print('0'*${DECIMALS})")${RESET}"
    echo -n "  Amount (minimum units, e.g.: 10000000): "
    read -r AMOUNT
fi
[[ ! "$AMOUNT" =~ ^[0-9]+$ ]] || [ "$AMOUNT" -eq 0 ] 2>/dev/null && \
    echo -e "${RED}❌ Invalid amount: ${AMOUNT}${RESET}" && exit 1
echo -e "   Amount            : ${AMOUNT}"
echo ""

# ─── EVM: quote gas payment ───────────────────────────────────────────────────
EVM_GAS_FEE=""
if [ "$SRC_TYPE" = "evm" ]; then
    # Verificar cast
    if ! command -v cast &>/dev/null; then
        echo -e "${RED}❌ 'cast' (Foundry) not found. Install: curl -L https://foundry.paradigm.xyz | bash${RESET}"
        exit 1
    fi

    echo -e "${DIM}  Querying quoteGasPayment for TC (domain ${TC_DOMAIN})...${RESET}"
    # cast call retorna "109030327234501 [1.09e14]" — extrair só o número com awk
    EVM_GAS_FEE=$(cast call "$WARP_SRC" \
        "quoteGasPayment(uint32)(uint256)" \
        "$TC_DOMAIN" \
        --rpc-url "$SRC_RPC" 2>/dev/null | awk '{print $1}' || echo "")

    if [ -z "$EVM_GAS_FEE" ] || ! [[ "$EVM_GAS_FEE" =~ ^[0-9]+$ ]]; then
        # Fallback: try alternative RPCs from rpc_urls list
        for RPC_ALT in $(jq -r --arg n "$SOURCE_NET" '.networks[$n].rpc_urls[]' "$EVM_CFG" 2>/dev/null); do
            [ "$RPC_ALT" = "$SRC_RPC" ] && continue
            echo -e "${DIM}  Trying alternative RPC: ${RPC_ALT}${RESET}"
            EVM_GAS_FEE=$(cast call "$WARP_SRC" \
                "quoteGasPayment(uint32)(uint256)" \
                "$TC_DOMAIN" \
                --rpc-url "$RPC_ALT" 2>/dev/null | awk '{print $1}' || echo "")
            if [ -n "$EVM_GAS_FEE" ] && [[ "$EVM_GAS_FEE" =~ ^[0-9]+$ ]]; then
                SRC_RPC="$RPC_ALT"
                echo -e "${DIM}  RPC ativo: ${SRC_RPC}${RESET}"
                break
            fi
        done
    fi

    if [ -z "$EVM_GAS_FEE" ] || ! [[ "$EVM_GAS_FEE" =~ ^[0-9]+$ ]]; then
        echo -e "${YELLOW}⚠️  quoteGasPayment failed. Enter the fee manually (in wei).${RESET}"
        echo -e "${DIM}  (e.g.: 109030327234501 for Sepolia)${RESET}"
        while true; do
            echo -n "  EVM_GAS_FEE (wei): "
            read -r EVM_GAS_FEE
            [[ "$EVM_GAS_FEE" =~ ^[0-9]+$ ]] && break
            echo -e "${RED}  Invalid value. Enter numbers only.${RESET}"
        done
    fi

    # Converter para ETH para exibição — usar precisão dinâmica para evitar "0.00000000"
    CHAIN_NATIVE=$(jq -r --arg n "$SOURCE_NET" '.networks[$n].native_token.symbol // "ETH"' "$EVM_CFG")
    EVM_FEE_ETH=$(python3 -c "
v = ${EVM_GAS_FEE} / 1e18
# Escolher precisão suficiente para mostrar pelo menos 4 dígitos significativos
if v >= 0.0001:
    print(f'{v:.6f}')
elif v >= 0.000001:
    print(f'{v:.8f}')
else:
    print(f'{v:.12f}')
" 2>/dev/null || echo "?")
    echo -e "${GREEN}✅ Gas fee: ${EVM_GAS_FEE} wei  (~${EVM_FEE_ETH} ${CHAIN_NATIVE})${RESET}"

    # Chave privada EVM
    if [ -z "${ETH_PRIVATE_KEY:-}" ]; then
        echo ""
        echo -n "  ETH_PRIVATE_KEY (0x...): "
        read -rs ETH_PRIVATE_KEY; echo ""
    fi
    [ -z "$ETH_PRIVATE_KEY" ] && echo -e "${RED}❌ ETH_PRIVATE_KEY not provided.${RESET}" && exit 1

    # ── Preflight balance check ───────────────────────────────────────────────
    SENDER_ADDR=$(cast wallet address "$ETH_PRIVATE_KEY" 2>/dev/null || echo "")
    if [ -n "$SENDER_ADDR" ]; then
        echo ""
        echo -e "${DIM}  Checking wallet balances for ${SENDER_ADDR}...${RESET}"

        # Native ETH balance (in wei)
        ETH_BAL_WEI=$(cast balance "$SENDER_ADDR" --rpc-url "$SRC_RPC" 2>/dev/null | awk '{print $1}' || echo "0")
        ETH_BAL_WEI=${ETH_BAL_WEI:-0}
        ETH_BAL_DISP=$(python3 -c "
v = ${ETH_BAL_WEI} / 1e18
print(f'{v:.6f}') if v >= 0.0001 else print(f'{v:.8f}') if v >= 0.000001 else print(f'{v:.12f}')
" 2>/dev/null || echo "?")

        # EVM synthetic token balance
        TOKEN_BAL=$(cast call "$WARP_SRC" \
            "balanceOf(address)(uint256)" "$SENDER_ADDR" \
            --rpc-url "$SRC_RPC" 2>/dev/null | awk '{print $1}' || echo "0")
        TOKEN_BAL=${TOKEN_BAL:-0}

        echo -e "  Wallet           : ${BOLD}${SENDER_ADDR}${RESET}"
        echo -e "  Balance ${CHAIN_NATIVE}      : ${ETH_BAL_DISP} ${CHAIN_NATIVE}"
        echo -e "  Balance ${TOKEN_UPPER}     : ${TOKEN_BAL}"
        echo ""

        PREFLIGHT_OK=true

        # Check sufficient ETH (fee + 0.001 ETH buffer for tx gas)
ETH_NEEDED=$((EVM_GAS_FEE + 1000000000000000))  # fee + ~0.001 ETH buffer
        if [ "$ETH_BAL_WEI" -lt "$ETH_NEEDED" ] 2>/dev/null; then
            FEE_DISP=$(python3 -c "
v=${EVM_GAS_FEE}/1e18; print(f'{v:.6f}') if v>=0.0001 else print(f'{v:.8f}')
" 2>/dev/null || echo "?")
            echo -e "${RED}  ❌ Insufficient ${CHAIN_NATIVE} balance!${RESET}"
            echo -e "     Required   : ~${FEE_DISP} ${CHAIN_NATIVE}  (IGP fee + tx gas)"
            echo -e "     Available  : ${ETH_BAL_DISP} ${CHAIN_NATIVE}"
            echo -e ""
            echo -e "  ${YELLOW}  💡 Get testnet ${CHAIN_NATIVE}:${RESET}"
            if [[ "$SOURCE_NET" == "sepolia" ]]; then
                echo -e "       https://sepoliafaucet.com"
                echo -e "       https://www.alchemy.com/faucets/ethereum-sepolia"
            elif [[ "$SOURCE_NET" == "bsctestnet" ]]; then
                echo -e "       https://testnet.bnbchain.org/faucet-smart"
            fi
            PREFLIGHT_OK=false
        fi

        # Check token balance
        if [ "$TOKEN_BAL" = "0" ] || [ -z "$TOKEN_BAL" ] 2>/dev/null; then
            echo -e "${RED}  ❌ No ${TOKEN_UPPER} balance in this wallet!${RESET}"
            echo -e "     The synthetic ${TOKEN_UPPER} token (HypERC20) must be in the source wallet."
            echo -e "     To get tokens: first send from Terra Classic → ${NET_UPPER} with recipient ${SENDER_ADDR}"
            PREFLIGHT_OK=false
        elif python3 -c "exit(0 if int('${TOKEN_BAL}') >= int('${AMOUNT}') else 1)" 2>/dev/null; then
            echo -e "${GREEN}  ✅ Balance ${TOKEN_UPPER}: ${TOKEN_BAL}  (required: ${AMOUNT})${RESET}"
        else
            echo -e "${RED}  ❌ Insufficient ${TOKEN_UPPER} balance!${RESET}"
            echo -e "     Required   : ${AMOUNT}"
            echo -e "     Available  : ${TOKEN_BAL}"
            PREFLIGHT_OK=false
        fi

        if [ "$PREFLIGHT_OK" = "false" ]; then
            echo ""
            echo -e "${RED}  Transfer cancelled due to insufficient balance.${RESET}"
            exit 1
        fi
        echo ""
    fi
fi

# ─── Sealevel: keypair ────────────────────────────────────────────────────────
if [ "$SRC_TYPE" = "sealevel" ]; then
    if [ ! -f "$SEALEVEL_CLIENT" ]; then
        echo -e "${RED}❌ hyperlane-sealevel-client not found at: ${SEALEVEL_CLIENT}${RESET}"
        echo -e "   Compile com: cd /home/lunc/hyperlane-monorepo/rust/sealevel && cargo build"
        exit 1
    fi

    # Keypair: environment variable > config
    SOL_KEYPAIR="${SOL_KEYPAIR:-${SOL_KEYPAIR_CFG}}"
    if [ -z "$SOL_KEYPAIR" ] || [ ! -f "$SOL_KEYPAIR" ]; then
        echo ""
        echo -e "${YELLOW}  Solana keypair not configured.${RESET}"
        echo -n "  Keypair path (.json): "
        read -r SOL_KEYPAIR
    fi
    [ ! -f "$SOL_KEYPAIR" ] && echo -e "${RED}❌ Keypair not found: ${SOL_KEYPAIR}${RESET}" && exit 1

    # Extract public key
    SENDER_PUBKEY=$(python3 -c "
import json
with open('${SOL_KEYPAIR}') as f:
    data = json.load(f)
# Solana keypair is [privkey...pubkey] array or object
if isinstance(data, list):
    import base64
    privkey_bytes = bytes(data)
    # Ed25519: first 32 bytes = seed, last 32 bytes = pubkey
    pubkey_bytes = privkey_bytes[32:]
    try:
        import base58
        print(base58.b58encode(pubkey_bytes).decode())
    except ImportError:
        # Fallback: use bs58 via node
        print('USE_NODE')
else:
    print(data.get('publicKey', '?'))
" 2>/dev/null || echo "USE_NODE")

    if [ "$SENDER_PUBKEY" = "USE_NODE" ] || [ -z "$SENDER_PUBKEY" ] || [ "$SENDER_PUBKEY" = "?" ]; then
        # Tentar via solana CLI
        if command -v solana &>/dev/null; then
            SENDER_PUBKEY=$(solana-keygen pubkey "$SOL_KEYPAIR" 2>/dev/null || echo "")
        fi
    fi

    [ -z "$SENDER_PUBKEY" ] && \
        echo -e "${RED}❌ Could not extract public key from keypair.${RESET}" && exit 1

    echo -e "   Sender Solana : ${SENDER_PUBKEY}"
fi

# ─── Resumo e confirmação ──────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${BOLD}  Transfer summary${RESET}"
echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "  Token          : ${TOKEN_UPPER} / ${TOKEN_SYM}"
echo -e "  Source         : ${NET_UPPER}  (${SRC_TYPE}, domain ${SRC_DOMAIN})"
echo -e "  Destination    : Terra Classic  (domain ${TC_DOMAIN})"
echo -e "  Recipient TC   : ${RECIPIENT}"
echo -e "  Recipient b32  : ${RECIPIENT_B32}"
echo -e "  Amount         : ${AMOUNT}"
echo -e "  Source Warp    : ${WARP_SRC}"
[ -n "$EVM_GAS_FEE" ] && echo -e "  Gas fee (EVM)  : ${EVM_GAS_FEE} wei  (~${EVM_FEE_ETH} ${CHAIN_NATIVE:-ETH})"
echo ""

if [[ "${AUTO_CONFIRM:-}" =~ ^[sStTyY1]$ ]]; then
    echo -e "${DIM}  (AUTO_CONFIRM enabled — proceeding automatically)${RESET}"
else
    echo -n "  Confirm and send? [y/N]: "
    read -r CONF
    [[ ! "$CONF" =~ ^[sStTyY]$ ]] && echo -e "${YELLOW}⚠️  Cancelled by user.${RESET}" && exit 0
fi

echo ""
echo -e "${BOLD}${GREEN}▶ Executing transfer...${RESET}"
echo ""

TX_HASH=""

# ══════════════════════════════════════════════════════════════════════════════
# EVM → Terra Classic
# ══════════════════════════════════════════════════════════════════════════════
if [ "$SRC_TYPE" = "evm" ]; then
    # cast send: transferRemote(uint32 destDomain, bytes32 recipient, uint256 amount)
    # --value = gas fee em wei (native token: ETH/BNB)
    CAST_OUT=$(cast send "$WARP_SRC" \
        "transferRemote(uint32,bytes32,uint256)" \
        "$TC_DOMAIN" \
        "0x${RECIPIENT_B32}" \
        "$AMOUNT" \
        --value "${EVM_GAS_FEE}" \
        --private-key "$ETH_PRIVATE_KEY" \
        --rpc-url "$SRC_RPC" \
        --json 2>&1 || true)

    TX_HASH=$(echo "$CAST_OUT" | jq -r '.transactionHash // ""' 2>/dev/null || true)

    if [ -z "$TX_HASH" ] || [ "$TX_HASH" = "null" ]; then
        echo -e "${RED}╔═══════════════════════════════════════════════════════════╗${RESET}"
        echo -e "${RED}║  ❌  TRANSFER ERROR (EVM)                                 ║${RESET}"
        echo -e "${RED}╚═══════════════════════════════════════════════════════════╝${RESET}"
        echo ""
        echo -e "${RED}  cast output:${RESET}"
        echo "$CAST_OUT" | head -20
        echo ""
        echo -e "${YELLOW}  Tips:${RESET}"
        echo -e "  • Check ${CHAIN_NATIVE:-ETH} balance to cover gas fee + tx fee"
        echo -e "  • Check token balance in the source wallet"
        echo -e "  • Confirm ETH_PRIVATE_KEY has funds: cast balance <addr> --rpc-url ${SRC_RPC}"
        exit 1
    fi

    # Determinar explorer
    EXPLORER=$(jq -r --arg n "$SOURCE_NET" '.networks[$n].explorer // ""' "$EVM_CFG")
    echo -e "${BOLD}${GREEN}╔═══════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${BOLD}${GREEN}║  ✅  EVM TRANSFER SENT SUCCESSFULLY!                      ║${RESET}"
    echo -e "${BOLD}${GREEN}╚═══════════════════════════════════════════════════════════╝${RESET}"
    echo ""
    echo -e "  ${BOLD}TX Hash :${RESET} ${TX_HASH}"
    [ -n "$EXPLORER" ] && echo -e "  ${BOLD}Explorer:${RESET} ${EXPLORER}/tx/${TX_HASH}"
fi

# ══════════════════════════════════════════════════════════════════════════════
# Sealevel → Terra Classic
# ══════════════════════════════════════════════════════════════════════════════
if [ "$SRC_TYPE" = "sealevel" ]; then
    # hyperlane-sealevel-client token transfer-remote
    #   <SENDER> <AMOUNT> <DEST_DOMAIN> <RECIPIENT> <TOKEN_TYPE>
    #   --program-id <PROGRAM_ID>
    #   -u <RPC> -k <KEYPAIR>
    #
    # TOKEN_TYPE = synthetic (SealevelHypSynthetic)
    TOKEN_TYPE_SOL="synthetic"

    # ── Preflight: verificar saldo SPL antes de tentar ────────────────────────
    if [ -n "$SOL_MINT" ]; then
        SPL_BAL_RAW=$(spl-token balance "$SOL_MINT" \
            --owner "$SENDER_PUBKEY" \
            --url "$SRC_RPC" 2>&1 || true)
        # Se retornar erro de "account not found" ou saldo 0, avisar
        if echo "$SPL_BAL_RAW" | grep -qi "not found\|Error\|failed"; then
            echo -e "${RED}╔═══════════════════════════════════════════════════════════╗${RESET}"
            echo -e "${RED}║  ❌  NO SPL BALANCE — TRANSFER CANCELLED                  ║${RESET}"
            echo -e "${RED}╚═══════════════════════════════════════════════════════════╝${RESET}"
            echo ""
            echo -e "${YELLOW}  Wallet    : ${SENDER_PUBKEY}${RESET}"
            echo -e "${YELLOW}  Mint      : ${SOL_MINT}${RESET}"
            echo -e "${YELLOW}  Response  : ${SPL_BAL_RAW}${RESET}"
            echo ""
            echo -e "  💡 To get XPTO tokens on Solana, first send from Terra Classic:"
            echo -e "     ./transfer-remote-terra.sh"
            echo ""
            exit 1
        fi
        SPL_BAL=$(echo "$SPL_BAL_RAW" | tr -d '[:space:]')
        echo -e "   SPL Balance (${TOKEN_KEY^^}) : ${SPL_BAL}"
        # Verificar se saldo é zero
        if [ "$SPL_BAL" = "0" ]; then
            echo -e "${RED}❌ SPL balance is zero. Send tokens from Terra Classic first.${RESET}"
            echo -e "   Mint: ${SOL_MINT}"
            echo -e "   Owner: ${SENDER_PUBKEY}"
            exit 1
        fi
    fi

    # SENDER deve ser o caminho do arquivo keypair (.json), não a public key
    # RECIPIENT deve ter prefixo 0x para ser interpretado como hex (não como base58 Solana)
    SOL_OUT=$("$SEALEVEL_CLIENT" \
        --url "$SRC_RPC" \
        --keypair "$SOL_KEYPAIR" \
        token transfer-remote \
        "$SOL_KEYPAIR" \
        "$AMOUNT" \
        "$TC_DOMAIN" \
        "0x${RECIPIENT_B32}" \
        "$TOKEN_TYPE_SOL" \
        --program-id "$WARP_SRC" \
        2>&1 || true)

    echo "$SOL_OUT"
    echo ""

    # Tentar extrair signature/txhash do output
    TX_HASH=$(echo "$SOL_OUT" | grep -oE '[A-Za-z0-9]{87,88}' | head -1 || true)

    if echo "$SOL_OUT" | grep -qi "error\|failed\|panicked"; then
        echo -e "${RED}╔═══════════════════════════════════════════════════════════╗${RESET}"
        echo -e "${RED}║  ❌  TRANSFER ERROR (SEALEVEL)                            ║${RESET}"
        echo -e "${RED}╚═══════════════════════════════════════════════════════════╝${RESET}"
        echo ""
        echo -e "${YELLOW}  Tips:${RESET}"
        echo -e "  • Check SOL balance in wallet for IGP fee"
        if [ -n "$SOL_MINT" ]; then
            echo -e "  • Saldo SPL: spl-token balance ${SOL_MINT} --owner ${SENDER_PUBKEY} --url ${SRC_RPC}"
        fi
        echo -e "  • Confirm RPC: ${SRC_RPC}"
        exit 1
    fi

    SOL_EXPLORER_BASE=$(jq -r --arg n "$SOURCE_NET" '.networks[$n].explorer // ""' "$SOL_CFG")
    echo -e "${BOLD}${GREEN}╔═══════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${BOLD}${GREEN}║  ✅  SEALEVEL TRANSFER SENT!                               ║${RESET}"
    echo -e "${BOLD}${GREEN}╚═══════════════════════════════════════════════════════════╝${RESET}"
    echo ""
    [ -n "$TX_HASH" ] && echo -e "  ${BOLD}TX Signature :${RESET} ${TX_HASH}"
    if [ -n "$TX_HASH" ] && [ -n "$SOL_EXPLORER_BASE" ]; then
        # Extrair cluster da URL (ex: ?cluster=testnet) e montar link /tx/{sig}?cluster=...
        SOL_CLUSTER=$(echo "$SOL_EXPLORER_BASE" | grep -oE 'cluster=[^&]+' || echo "")
        SOL_EXPLORER_HOST=$(echo "$SOL_EXPLORER_BASE" | sed 's/?.*$//' | sed 's|/$||')
        if [ -n "$SOL_CLUSTER" ]; then
            echo -e "  ${BOLD}Explorer     :${RESET} ${SOL_EXPLORER_HOST}/tx/${TX_HASH}?${SOL_CLUSTER}"
        else
            echo -e "  ${BOLD}Explorer     :${RESET} ${SOL_EXPLORER_HOST}/tx/${TX_HASH}"
        fi
    fi
fi

# ─── Tracking information ────────────────────────────────────────────────────
echo ""
echo -e "${DIM}  A mensagem será relayada pelo Hyperlane Relayer."
echo -e "  Track at: https://explorer.hyperlane.xyz"
echo -e "  Estimated delivery time: 1–5 minutes.${RESET}"

# ─── Report ──────────────────────────────────────────────────────────────────
REPORT_FILE="$LOG_DIR/TRANSFER-TO-TERRA-${NET_UPPER}-${TOKEN_UPPER}-$(date +%Y%m%d-%H%M%S).txt"
{
    echo "TRANSFER REMOTE — ${NET_UPPER} → Terra Classic"
    echo "Date           : $(date)"
    echo "Token          : ${TOKEN_UPPER} / ${TOKEN_SYM}"
    echo "Source         : ${NET_UPPER}  (${SRC_TYPE}, domain ${SRC_DOMAIN})"
    echo "Destination    : Terra Classic  (domain ${TC_DOMAIN})"
    echo "Recipient TC   : ${RECIPIENT}"
    echo "Recipient b32  : ${RECIPIENT_B32}"
    echo "Amount         : ${AMOUNT}"
    echo "Source Warp    : ${WARP_SRC}"
    [ -n "${EVM_GAS_FEE:-}" ] && echo "Gas fee (wei)  : ${EVM_GAS_FEE}"
    [ -n "$TX_HASH" ] && echo "TX Hash        : ${TX_HASH}"
} > "$REPORT_FILE"

echo ""
echo -e "  ${BOLD}Report    :${RESET} ${REPORT_FILE}"
echo ""
echo "$(date) | ${NET_UPPER}→TC | ${TOKEN_UPPER} | amount=${AMOUNT} | tx=${TX_HASH:-?}" >> "$LOG_FILE"
