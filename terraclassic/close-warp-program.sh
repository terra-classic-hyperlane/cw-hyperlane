#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
#  🗑️  CLOSE WARP PROGRAM — Fecha programa, recupera SOL, reseta config
# ═══════════════════════════════════════════════════════════════════════════════
#
#  USAGE:
#    chmod +x close-warp-program.sh
#    ./close-warp-program.sh
#
#  O script lista todos os tokens deployados, fecha o programa no Solana,
#  recupera o SOL e reseta deployed=false no warp-sealevel-config.json.
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOL_CONFIG="$SCRIPT_DIR/warp-sealevel-config.json"

R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'
B='\033[0;34m'; C='\033[0;36m'; W='\033[1m'; NC='\033[0m'
OK="${G}✅${NC}"; ERR="${R}❌${NC}"; WARN="${Y}⚠️ ${NC}"; INFO="${B}ℹ️ ${NC}"

sol_cfg() { jq -r "$1" "$SOL_CONFIG" 2>/dev/null || echo ""; }

clear 2>/dev/null || true
echo -e "╔══════════════════════════════════════════════════════════════════════════╗"
echo -e "║                                                                          ║"
echo -e "║   🗑️  CLOSE WARP PROGRAM — Recuperar SOL + Reset Config                 ║"
echo -e "║                                                                          ║"
echo -e "╚══════════════════════════════════════════════════════════════════════════╝"
echo ""

# ─── Listar TODOS os tokens de todas as redes habilitadas ───
declare -a ENTRY_NET=()
declare -a ENTRY_TOK=()
declare -a ENTRY_PID=()
declare -a ENTRY_CAN_CLOSE=()

i=1
while IFS= read -r NET_KEY; do
    NET_DISP=$(sol_cfg ".networks.\"$NET_KEY\".display_name")
    RPC=$(sol_cfg ".networks.\"$NET_KEY\".rpc")

    while IFS= read -r TOK_KEY; do
        PID=$(sol_cfg ".networks.\"$NET_KEY\".warp_tokens.\"$TOK_KEY\".program_id")
        MINT=$(sol_cfg ".networks.\"$NET_KEY\".warp_tokens.\"$TOK_KEY\".mint_address")
        DEP=$(sol_cfg ".networks.\"$NET_KEY\".warp_tokens.\"$TOK_KEY\".deployed")
        [ "$PID"  = "null" ] && PID=""
        [ "$MINT" = "null" ] && MINT=""

        ENTRY_NET+=("$NET_KEY")
        ENTRY_TOK+=("$TOK_KEY")
        ENTRY_PID+=("$PID")

        if [ -n "$PID" ]; then
            ENTRY_CAN_CLOSE+=("yes")
            MINT_DISP="${MINT:-—}"
            DEP_TAG="${Y}[pendente]${NC}"; [ "$DEP" = "true" ] && DEP_TAG="${G}[deployed]${NC}"
            echo -e "   ${W}[$i]${NC}  ${C}${TOK_KEY}${NC} @ ${NET_DISP} ${DEP_TAG}"
            echo -e "        Program: ${G}${PID}${NC}"
            echo -e "        Mint:    ${MINT_DISP}"
        else
            ENTRY_CAN_CLOSE+=("no")
            echo -e "   ${W}[$i]${NC}  ${C}${TOK_KEY}${NC} @ ${NET_DISP} ${R}[sem deploy]${NC}"
        fi
        i=$((i+1))
    done < <(jq -r ".networks.\"$NET_KEY\".warp_tokens | keys[]" "$SOL_CONFIG" 2>/dev/null)
    echo ""
done < <(jq -r '.networks | to_entries[] | select(.value.enabled==true) | .key' "$SOL_CONFIG" 2>/dev/null)

if [ ${#ENTRY_NET[@]} -eq 0 ]; then
    echo -e "${WARN} Nenhum token encontrado no warp-sealevel-config.json."
    exit 0
fi

echo -ne "  ${W}Selecione o token para fechar [1-${#ENTRY_NET[@]}] (Enter=cancelar): ${NC}"
read -r SEL 2>/dev/null || SEL=""
[ -z "$SEL" ] && echo "  Cancelado." && exit 0

if ! [[ "$SEL" =~ ^[0-9]+$ ]] || [ "$SEL" -lt 1 ] || [ "$SEL" -gt "${#ENTRY_NET[@]}" ]; then
    echo -e "${ERR} Seleção inválida: $SEL"; exit 1
fi

IDX=$((SEL-1))
if [ "${ENTRY_CAN_CLOSE[$IDX]}" = "no" ]; then
    echo -e "${WARN} ${ENTRY_TOK[$IDX]} @ ${ENTRY_NET[$IDX]} não tem programa deployado — nada a fechar."
    exit 0
fi

NET_KEY="${ENTRY_NET[$IDX]}"
TOK_KEY="${ENTRY_TOK[$IDX]}"
PROGRAM_ID="${ENTRY_PID[$IDX]}"
NET_DISP=$(sol_cfg ".networks.\"$NET_KEY\".display_name")
RPC=$(sol_cfg ".networks.\"$NET_KEY\".rpc")
KEYPAIR=$(sol_cfg ".networks.\"$NET_KEY\".keypair" | sed "s|^~|$HOME|")
NET_ENV=$(sol_cfg ".networks.\"$NET_KEY\".environment")
MONOREPO=$(sol_cfg ".networks.\"$NET_KEY\".monorepo_dir" | sed "s|^~|$HOME|")
WARP_KEYS_DIR="$MONOREPO/environments/${NET_ENV}/warp-routes/${TOK_KEY}/keys"
STATE_FILE="$SCRIPT_DIR/.warp-sealevel-state.json"

echo ""
echo -e "${WARN} Você selecionou:"
echo -e "   Token:   ${C}${TOK_KEY}${NC}"
echo -e "   Rede:    ${NET_DISP} (${NET_KEY})"
echo -e "   Program: ${G}${PROGRAM_ID}${NC}"
echo -e "   RPC:     ${RPC}"
echo ""
echo -e "   Ações: fechar programa + fechar buffers + limpar keypairs + resetar config"
echo ""
echo -ne "  ${W}Confirmar? [s/N]: ${NC}"
read -r CONF 2>/dev/null || CONF="n"
[[ ! "$CONF" =~ ^[sS]$ ]] && echo "  Cancelado." && exit 0

echo ""

# ─── 1. Fechar programa ───
echo -e "${INFO} Fechando programa ${PROGRAM_ID}..."
CLOSE_OUT=$(solana program close "$PROGRAM_ID" \
  --bypass-warning \
  -k "$KEYPAIR" \
  --url "$RPC" 2>&1 || true)

if echo "$CLOSE_OUT" | grep -q "SOL reclaimed\|reclaimed\|Closed"; then
    SOL_BACK=$(echo "$CLOSE_OUT" | grep -oE "[0-9]+\.[0-9]+ SOL" | head -1 || echo "")
    echo -e "${OK} Programa fechado! ${G}${SOL_BACK:-SOL recuperado}${NC}"
elif echo "$CLOSE_OUT" | grep -qi "already closed\|has been closed\|does not exist"; then
    echo -e "${WARN} Programa já estava fechado (ou não existe on-chain)."
else
    echo -e "${WARN} Resposta do close:"
    echo "$CLOSE_OUT" | head -5
fi

# ─── 2. Fechar buffers órfãos ───
echo -e "${INFO} Verificando buffers órfãos..."
BUF_OUT=$(solana program close --buffers \
  -k "$KEYPAIR" \
  --url "$RPC" 2>&1 || true)

BUF_TOTAL=$(echo "$BUF_OUT" | grep -c "SOL" || true)
if [ "$BUF_TOTAL" -gt 0 ]; then
    BUF_SOL=$(echo "$BUF_OUT" | grep -oE "[0-9]+\.[0-9]+ SOL" | \
        python3 -c "import sys; total=sum(float(x.split()[0]) for x in sys.stdin); print(f'{total:.6f} SOL')" 2>/dev/null || echo "?")
    echo -e "${OK} Buffers fechados: ${BUF_TOTAL} buffer(s), ${G}${BUF_SOL}${NC} recuperados"
else
    echo -e "${INFO} Nenhum buffer órfão encontrado."
fi

# ─── 3. Limpar keypairs ───
if [ -d "$WARP_KEYS_DIR" ]; then
    KEY_COUNT=$(ls "$WARP_KEYS_DIR"/*.json 2>/dev/null | wc -l)
    if [ "$KEY_COUNT" -gt 0 ]; then
        rm -f "$WARP_KEYS_DIR"/*.json
        echo -e "${OK} ${KEY_COUNT} keypair(s) removidos de: ${C}${WARP_KEYS_DIR}${NC}"
    fi
else
    echo -e "${INFO} Diretório de keypairs não encontrado (já limpo)."
fi

# ─── 4. Limpar state file ───
if [ -f "$STATE_FILE" ]; then
    STATE_TOK=$(jq -r '.token // ""' "$STATE_FILE" 2>/dev/null || echo "")
    STATE_NET=$(jq -r '.network // ""' "$STATE_FILE" 2>/dev/null || echo "")
    if [ "$STATE_TOK" = "$TOK_KEY" ] && [ "$STATE_NET" = "$NET_KEY" ]; then
        rm -f "$STATE_FILE"
        echo -e "${OK} State file removido."
    fi
fi

# ─── 5. Resetar config ───
TMP_CFG=$(mktemp)
jq ".networks.\"${NET_KEY}\".warp_tokens.\"${TOK_KEY}\".deployed = false |
    .networks.\"${NET_KEY}\".warp_tokens.\"${TOK_KEY}\".program_id = \"\" |
    .networks.\"${NET_KEY}\".warp_tokens.\"${TOK_KEY}\".program_hex = \"\" |
    .networks.\"${NET_KEY}\".warp_tokens.\"${TOK_KEY}\".mint_address = \"\"" \
    "$SOL_CONFIG" > "$TMP_CFG" && mv "$TMP_CFG" "$SOL_CONFIG"
echo -e "${OK} ${C}warp-sealevel-config.json${NC} resetado: deployed=false, program_id='', mint_address=''"

# ─── 6. Saldo final ───
echo ""
BALANCE=$(solana balance "$KEYPAIR" --url "$RPC" 2>/dev/null || \
    curl -s --max-time 8 -X POST "$RPC" -H "Content-Type: application/json" \
    -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"getBalance\",\"params\":[\"$(solana-keygen pubkey "$KEYPAIR" 2>/dev/null)\"]}" | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print(str(round(d['result']['value']/1e9,6))+' SOL')" 2>/dev/null || echo "?")
echo -e "${OK} Saldo atual em ${NET_DISP}: ${G}${BALANCE}${NC}"
echo ""
echo -e "  Pronto para novo deploy: ${Y}./create-warp-sealevel.sh${NC}"
echo ""
