#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
#  🚀 DEPLOY WARP SOLANA — BUFFER REUSE (sem cargo build do .so)
# ═══════════════════════════════════════════════════════════════════════════════
#
#  Estratégia: "binary dump + deploy separado"
#
#  Como funciona:
#    1. Obtém o binário .so via `solana program dump` de programa já deployado
#       (ou usa binário local já compilado)
#    2. Faz upload do binário para o chain via `solana program deploy` (direto)
#    3. Chama `warp-route deploy` → detecta programa existente → pula upload
#       → executa SOMENTE o init do token (idempotente)
#    4. Configura ISM, IGP, destination gas, enroll-remote-router, set_route
#
#  Economia:
#    ✅ Sem cargo build do .so (poupa 15-20 min de compilação BPF)
#    ✅ Binário vem de programa já deployado na mainnet (confiável + sem recompile)
#    ✅ Buffer reaproveitado em retentativas (deploy com falha parcial = paga só 1x)
#    ⚠️  Custo SOL do upload do binário (~2-5 SOL) é inevitável por programa
#
#  Source program padrão (synthetic, solanamainnet):
#    Fa4zQJCH7id5KL1eFJt2mHyFpUNfCCSkHgtMrLvrRJBN  (TONY / Big Tony)
#
#  Uso:
#    export TERRA_PRIVATE_KEY="hex_key"
#    ./deploy-warp-solana-buffer.sh
#
#  Variáveis opcionais:
#    SOURCE_PROGRAM_ID=<base58>  → programa cujo binário será reutilizado
#    WARP_PROGRAM_ID=<base58>    → pula deploy (programa já existe)
#    SKIP_INIT=1                 → pula warp-route deploy (init)
#    SKIP_ISM=1 / SKIP_IGP=1 / SKIP_GAS=1 / SKIP_ENROLL=1 / SKIP_TC_ROUTE=1
#
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# CORES
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

# Source program padrão (synthetic, Solana mainnet, mesmo binário que usaremos)
# TONY/BigTony — programa sintético confirmado no mainnet3
DEFAULT_SOURCE_PROGRAM="Fa4zQJCH7id5KL1eFJt2mHyFpUNfCCSkHgtMrLvrRJBN"

# Auto-detect PROJECT_ROOT
PROJECT_ROOT="$SCRIPT_DIR"
while [ ! -f "$PROJECT_ROOT/package.json" ] && [ "$PROJECT_ROOT" != "/" ]; do
    PROJECT_ROOT="$(dirname "$PROJECT_ROOT")"
done
if [ ! -f "$PROJECT_ROOT/package.json" ]; then
    echo "❌ Project root (package.json) não encontrado!"; exit 1
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

wait_sec() {
    local s="$1" msg="${2:-Aguardando}"
    echo -ne "${INFO} ${msg}: "
    for ((i=s; i>0; i--)); do echo -ne "${i}s "; sleep 1; done
    echo "✓"
}

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

load_state() {
    [ -f "$STATE_FILE" ] || return 0
    _ST_NET=$(jq -r '.network    // ""' "$STATE_FILE" 2>/dev/null || echo "")
    _ST_TOK=$(jq -r '.token      // ""' "$STATE_FILE" 2>/dev/null || echo "")
    _ST_PID=$(jq -r '.program_id // ""' "$STATE_FILE" 2>/dev/null || echo "")
    _ST_HEX=$(jq -r '.program_hex// ""' "$STATE_FILE" 2>/dev/null || echo "")
    _ST_MINT=$(jq -r '.mint      // ""' "$STATE_FILE" 2>/dev/null || echo "")
    [ -n "$_ST_TOK" ] && log_warn "Estado anterior: token=${_ST_TOK} net=${_ST_NET:-—} program=${_ST_PID:-—}"
    log "   Para reiniciar: ${Y}rm -f $STATE_FILE${NC}"
}

apply_state() {
    [ -z "${_ST_TOK:-}" ] && return 0
    if [ "${_ST_TOK}" = "${TOKEN_KEY}" ] && [ "${_ST_NET}" = "${NET_KEY}" ]; then
        [ -z "${WARP_PROGRAM_ID:-}" ] && [ -n "${_ST_PID:-}" ] && export WARP_PROGRAM_ID="$_ST_PID"
        [ -z "${WARP_HEX:-}"        ] && [ -n "${_ST_HEX:-}" ] && export WARP_HEX="$_ST_HEX"
        [ -z "${MINT_ADDRESS:-}"    ] && [ -n "${_ST_MINT:-}"] && export MINT_ADDRESS="$_ST_MINT"
        [ -n "${WARP_PROGRAM_ID:-}" ] && log_info "Estado restaurado: program=${WARP_PROGRAM_ID}"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# BANNER
# ─────────────────────────────────────────────────────────────────────────────
> "$LOG_FILE"
clear 2>/dev/null || true
log "╔══════════════════════════════════════════════════════════════════════════╗"
log "║  🔄  DEPLOY WARP SOLANA — BUFFER REUSE (sem compilação BPF)            ║"
log "║  Data: $(date '+%Y-%m-%d %H:%M:%S')                                         ║"
log "╚══════════════════════════════════════════════════════════════════════════╝"

# ─────────────────────────────────────────────────────────────────────────────
# CHECKS INICIAIS
# ─────────────────────────────────────────────────────────────────────────────
for f in "$EVM_CONFIG" "$SOL_CONFIG"; do
    [ -f "$f" ] || { log_err "Arquivo não encontrado: $f"; exit 1; }
    jq empty "$f" 2>/dev/null || { log_err "JSON inválido: $f"; exit 1; }
done
command -v jq      &>/dev/null || { log_err "jq obrigatório"; exit 1; }
command -v python3 &>/dev/null || { log_err "python3 obrigatório"; exit 1; }
command -v node    &>/dev/null || { log_err "node obrigatório"; exit 1; }
command -v solana  &>/dev/null || { log_err "solana-cli obrigatório"; exit 1; }
command -v cargo   &>/dev/null || { log_err "cargo (Rust) obrigatório"; exit 1; }

TERRA_DOMAIN=$(evm_cfg '.terra_classic.domain')
TERRA_RPC=$(evm_cfg    '.terra_classic.rpc')
TERRA_CHAIN_ID=$(evm_cfg '.terra_classic.chain_id')
log_ok "Terra Classic: domain=${TERRA_DOMAIN}, rpc=${TERRA_RPC}"

load_state

# ═════════════════════════════════════════════════════════════════════════════
# MENU 1 — TOKEN
# ═════════════════════════════════════════════════════════════════════════════
log_sep "SELEÇÃO DE TOKEN"
mapfile -t TOKEN_KEYS < <(jq -r '.terra_classic.tokens | keys[]' "$EVM_CONFIG" 2>/dev/null)
declare -a TOKEN_MENU=()
i=1
for TK in "${TOKEN_KEYS[@]}"; do
    TK_NAME=$(evm_cfg ".terra_classic.tokens.${TK}.name")
    TK_SYM=$(evm_cfg  ".terra_classic.tokens.${TK}.symbol")
    TK_DEP=$(evm_cfg  ".terra_classic.tokens.${TK}.terra_warp.deployed")
    TOKEN_MENU+=("$TK")
    [ "$TK_DEP" = "true" ] && TAG="${G}[TC ok]${NC}" || TAG="${Y}[TC pendente]${NC}"
    log "  [${W}$i${NC}]  ${C}${TK}${NC} — ${TK_NAME:-N/A} (${TK_SYM:-?}) ${TAG}"
    i=$((i+1))
done
echo -ne "  ${W}Token [1-${#TOKEN_MENU[@]}]: ${NC}"; read -r SEL_TOK 2>/dev/null || SEL_TOK="1"
SEL_TOK="${SEL_TOK:-1}"
[[ "$SEL_TOK" =~ ^[0-9]+$ ]] && [ "$SEL_TOK" -ge 1 ] && [ "$SEL_TOK" -le "${#TOKEN_MENU[@]}" ] \
    || { log_err "Seleção inválida"; exit 1; }
TOKEN_KEY="${TOKEN_MENU[$((SEL_TOK-1))]}"
TK_TC=".terra_classic.tokens.${TOKEN_KEY}"
TOKEN_NAME=$(evm_cfg    "${TK_TC}.name")
TOKEN_SYMBOL=$(evm_cfg  "${TK_TC}.symbol")
TOKEN_DEC=$(evm_cfg     "${TK_TC}.decimals")
TERRA_WARP_ADDR=$(evm_cfg "${TK_TC}.terra_warp.warp_address")
TERRA_WARP_HEX=$(evm_cfg  "${TK_TC}.terra_warp.warp_hexed")
TERRA_WARP_DEPLOYED=$(evm_cfg "${TK_TC}.terra_warp.deployed")
log_ok "Token: ${C}${TOKEN_KEY}${NC} — ${TOKEN_NAME} (${TOKEN_SYMBOL})"

# ═════════════════════════════════════════════════════════════════════════════
# MENU 2 — REDE SOLANA
# ═════════════════════════════════════════════════════════════════════════════
log_sep "SELEÇÃO DE REDE SOLANA"
mapfile -t NET_KEYS < <(jq -r '.networks | to_entries[] | select(.value.enabled==true) | .key' "$SOL_CONFIG" 2>/dev/null)
declare -a NET_MENU=()
i=1
for NK in "${NET_KEYS[@]}"; do
    ND=$(sol_cfg ".networks.${NK}.display_name")
    DOM=$(sol_cfg ".networks.${NK}.domain")
    SOL_WD=$(sol_cfg ".networks.${NK}.warp_tokens.${TOKEN_KEY}.deployed" 2>/dev/null || echo "false")
    SOL_WA=$(sol_cfg ".networks.${NK}.warp_tokens.${TOKEN_KEY}.program_id" 2>/dev/null || echo "")
    NET_MENU+=("$NK")
    [ "$SOL_WD" = "true" ] && [ -n "$SOL_WA" ] && TAG="${G}[já deployado]${NC}" || TAG="${B}[novo]${NC}"
    log "  [${W}$i${NC}]  ${C}${NK}${NC} — ${ND} (domain: ${DOM}) ${TAG}"
    [ -n "$SOL_WA" ] && [ "$SOL_WA" != "null" ] && log "         Program ID: ${G}${SOL_WA}${NC}"
    i=$((i+1))
done
[ ${#NET_MENU[@]} -eq 0 ] && { log_err "Nenhuma rede Solana habilitada!"; exit 1; }
echo -ne "  ${W}Rede [1-${#NET_MENU[@]}]: ${NC}"; read -r SEL_NET 2>/dev/null || SEL_NET="1"
SEL_NET="${SEL_NET:-1}"
[[ "$SEL_NET" =~ ^[0-9]+$ ]] && [ "$SEL_NET" -ge 1 ] && [ "$SEL_NET" -le "${#NET_MENU[@]}" ] \
    || { log_err "Seleção inválida"; exit 1; }
NET_KEY="${NET_MENU[$((SEL_NET-1))]}"
N=".networks.${NET_KEY}"

NET_DISPLAY=$(sol_cfg "${N}.display_name")
NET_ENV=$(sol_cfg     "${N}.environment")
NET_DOMAIN=$(sol_cfg  "${N}.domain")
NET_RPC=$(sol_cfg     "${N}.rpc")
NET_EXPLORER=$(sol_cfg "${N}.explorer")
NET_KEYPAIR=$(sol_cfg "${N}.keypair" | sed "s|^~|$HOME|")
NET_MONOREPO=$(sol_cfg "${N}.monorepo_dir" | sed "s|^~|$HOME|")
MAILBOX=$(sol_cfg     "${N}.mailbox" 2>/dev/null || echo "")
ISM_PROGRAM_ID=$(sol_cfg "${N}.ism.program_id")
IGP_PROGRAM_ID=$(sol_cfg "${N}.igp.program_id")
IGP_ACCOUNT=$(sol_cfg    "${N}.igp.account")
DEST_GAS=$(sol_cfg       "${N}.igp.destination_gas_terra")
SOL_PID_CFG=$(sol_cfg    "${N}.warp_tokens.${TOKEN_KEY}.program_id")
SOL_HEX_CFG=$(sol_cfg    "${N}.warp_tokens.${TOKEN_KEY}.program_hex")
SOL_MINT_CFG=$(sol_cfg   "${N}.warp_tokens.${TOKEN_KEY}.mint_address")
SOL_META_URI=$(sol_cfg   "${N}.warp_tokens.${TOKEN_KEY}.metadata_uri")
SOL_TOK_DEC=$(sol_cfg    "${N}.warp_tokens.${TOKEN_KEY}.decimals")
SOL_OWNER=$(sol_cfg      "${N}.warp_tokens.${TOKEN_KEY}.owner")
SOL_TYPE=$(sol_cfg       "${N}.warp_tokens.${TOKEN_KEY}.type")

# Resolve MAILBOX da rede
if [ -z "$MAILBOX" ] || [ "$MAILBOX" = "null" ]; then
    MAILBOX_JSON="$NET_MONOREPO/environments/${NET_ENV}/$(echo "$NET_KEY" | sed 's/mainnet/solanamainnet/;s/testnet/solanatestnet/')/core/program-ids.json"
    [ -f "$MAILBOX_JSON" ] && MAILBOX=$(jq -r '.mailbox // ""' "$MAILBOX_JSON" 2>/dev/null || echo "")
    # fallback: solanamainnet
    [ -z "$MAILBOX" ] && MAILBOX=$(jq -r '.mailbox // ""' "$NET_MONOREPO/environments/${NET_ENV}/solanamainnet/core/program-ids.json" 2>/dev/null || echo "")
    [ -z "$MAILBOX" ] && MAILBOX=$(jq -r '.mailbox // ""' "$NET_MONOREPO/environments/${NET_ENV}/solanatestnet/core/program-ids.json" 2>/dev/null || echo "")
fi

log_ok "Rede: ${C}${NET_KEY}${NC} — ${NET_DISPLAY} (domain: ${NET_DOMAIN})"
log_info "Mailbox: ${MAILBOX:-NÃO ENCONTRADO}"

apply_state

# Inicializa variáveis runtime
WARP_PROGRAM_ID="${WARP_PROGRAM_ID:-}"
WARP_HEX="${WARP_HEX:-}"
MINT_ADDRESS="${MINT_ADDRESS:-}"
[ -z "$WARP_PROGRAM_ID" ] && [ -n "$SOL_PID_CFG" ] && [ "$SOL_PID_CFG" != "null" ] && WARP_PROGRAM_ID="$SOL_PID_CFG"
[ -z "$WARP_HEX"        ] && [ -n "$SOL_HEX_CFG" ] && [ "$SOL_HEX_CFG" != "null" ] && WARP_HEX="${SOL_HEX_CFG#0x}"
[ -z "$MINT_ADDRESS"    ] && [ -n "$SOL_MINT_CFG"] && [ "$SOL_MINT_CFG" != "null" ] && MINT_ADDRESS="$SOL_MINT_CFG"

# Validações
[ -z "$NET_KEYPAIR" ] || [ ! -f "$NET_KEYPAIR" ] && {
    log_err "Keypair Solana não encontrado: ${NET_KEYPAIR:-NÃO CONFIGURADO}"
    log "  Configure: warp-sealevel-config.json → .networks.${NET_KEY}.keypair"; exit 1; }
[ -z "$NET_MONOREPO" ] || [ ! -d "$NET_MONOREPO" ] && {
    log_err "Monorepo não encontrado: ${NET_MONOREPO:-NÃO CONFIGURADO}"; exit 1; }

CLIENT_DIR="$NET_MONOREPO/client"
ENVIRONMENTS_DIR="$NET_MONOREPO/environments"
BUILT_SO_DIR="$NET_MONOREPO/target/deploy"
WARP_ROUTE_DIR="$ENVIRONMENTS_DIR/${NET_ENV}/warp-routes/${TOKEN_KEY}"
KEYS_DIR="$WARP_ROUTE_DIR/keys"
mkdir -p "$KEYS_DIR"

# Pre-built client binary (se existir evita cargo run overhead)
CLIENT_BIN="$NET_MONOREPO/target/release/hyperlane-sealevel-client"

# Keypair paths que o warp-route deploy espera encontrar
PROG_KEYPAIR_FILE="$KEYS_DIR/hyperlane_sealevel_token-${NET_KEY}-keypair.json"
BUFFER_KEYPAIR_FILE="$KEYS_DIR/hyperlane_sealevel_token-${NET_KEY}-buffer.json"

# ─────────────────────────────────────────────────────────────────────────────
# RESUMO
# ─────────────────────────────────────────────────────────────────────────────
log ""
log "╔══════════════════════════════════════════════════════════════════════════╗"
log "║  📋  CONFIGURAÇÃO: ${C}${TOKEN_KEY}${NC} → ${C}${NET_DISPLAY}${NC}"
log "╚══════════════════════════════════════════════════════════════════════════╝"
log "  Token:      ${TOKEN_NAME} (${TOKEN_SYMBOL}) | dec=${TOKEN_DEC}"
log "  Rede:       ${NET_DISPLAY} | domain=${NET_DOMAIN} | env=${NET_ENV}"
log "  ISM:        ${ISM_PROGRAM_ID}"
log "  IGP prog:   ${IGP_PROGRAM_ID}"
log "  IGP acct:   ${IGP_ACCOUNT}"
log "  Mailbox:    ${MAILBOX:-NÃO DEFINIDO}"
log "  Keypair:    ${NET_KEYPAIR}"
log "  Prog key:   ${PROG_KEYPAIR_FILE}"
log "  Buffer key: ${BUFFER_KEYPAIR_FILE}"
[ -n "$WARP_PROGRAM_ID" ] && log "  Program ID: ${G}${WARP_PROGRAM_ID}${NC} (será pulado o deploy)"
log ""

if [ "$TERRA_WARP_DEPLOYED" != "true" ] || [ -z "$TERRA_WARP_ADDR" ] || [ "$TERRA_WARP_ADDR" = "null" ]; then
    log_warn "Warp TC não deployado para '${TOKEN_KEY}' — enroll/set_route serão pulados"
    export SKIP_ENROLL="${SKIP_ENROLL:-1}"
    export SKIP_TC_ROUTE="${SKIP_TC_ROUTE:-1}"
fi

echo -ne "  ${W}Confirmar e continuar? [S/n]: ${NC}"
read -r CONFIRM 2>/dev/null || CONFIRM="s"
[[ "${CONFIRM:-s}" =~ ^[sSyY]$ ]] || { log "  Cancelado."; exit 0; }

# ═════════════════════════════════════════════════════════════════════════════
# STEP 1 — OBTER BINÁRIO
# ═════════════════════════════════════════════════════════════════════════════
log_sep "STEP 1 — OBTER BINÁRIO (.so)"

BINARY_FILE="$WARP_ROUTE_DIR/hyperlane_sealevel_token.so"

if [ -n "${WARP_PROGRAM_ID:-}" ]; then
    log_warn "WARP_PROGRAM_ID já definido — pulando obtenção de binário e deploy."
    BINARY_FILE=""
elif [ -f "$BINARY_FILE" ]; then
    log_ok "Binário já existe: ${C}${BINARY_FILE}${NC}"
    BINARY_SZ=$(du -sh "$BINARY_FILE" | cut -f1)
    log_info "Tamanho: ${BINARY_SZ}"
else
    # Fonte do binário
    SOURCE_PROGRAM="${SOURCE_PROGRAM_ID:-${DEFAULT_SOURCE_PROGRAM}}"

    # Opção A: binário local compilado
    LOCAL_SO="$BUILT_SO_DIR/hyperlane_sealevel_token.so"
    if [ -f "$LOCAL_SO" ]; then
        log_info "Binário local encontrado: ${LOCAL_SO}"
        cp "$LOCAL_SO" "$BINARY_FILE"
        log_ok "Usando binário local compilado."
    else
        # Opção B: dump de programa existente na mainnet
        log_info "Binário local não encontrado. Fazendo dump do programa ${SOURCE_PROGRAM}..."
        log_info "Programa fonte (synthetic solanamainnet): ${C}${SOURCE_PROGRAM}${NC}"
        log ""
        set +e
        solana program dump "$SOURCE_PROGRAM" "$BINARY_FILE" \
            --url "$NET_RPC" 2>&1 | tee -a "$LOG_FILE"
        DUMP_EXIT=$?
        set -e
        if [ $DUMP_EXIT -ne 0 ] || [ ! -f "$BINARY_FILE" ]; then
            log_err "Falha ao fazer dump do programa ${SOURCE_PROGRAM}"
            log "  Verifique o RPC ou defina SOURCE_PROGRAM_ID com outro programa synthetic."
            log "  Alternativa: compile o binário localmente:"
            log "    cd $NET_MONOREPO && cargo build-sbf --manifest-path programs/token/Cargo.toml"
            log "    cp target/deploy/hyperlane_sealevel_token.so ${BINARY_FILE}"
            exit 1
        fi
        BINARY_SZ=$(du -sh "$BINARY_FILE" | cut -f1)
        log_ok "Dump concluído: ${C}${BINARY_FILE}${NC} (${BINARY_SZ})"
        log_info "Programa fonte usado: ${SOURCE_PROGRAM}"
    fi
fi

# ═════════════════════════════════════════════════════════════════════════════
# STEP 2 — DEPLOY DO PROGRAMA (solana CLI direto)
# ═════════════════════════════════════════════════════════════════════════════
log_sep "STEP 2 — DEPLOY DO PROGRAMA (solana program deploy)"

if [ -n "${WARP_PROGRAM_ID:-}" ]; then
    log_warn "WARP_PROGRAM_ID=${WARP_PROGRAM_ID} — pulando deploy do binário."
else
    # Gerar ou carregar keypair do programa
    if [ ! -f "$PROG_KEYPAIR_FILE" ]; then
        log_info "Gerando keypair do programa..."
        solana-keygen new --no-passphrase --silent \
            --outfile "$PROG_KEYPAIR_FILE" 2>&1 | tee -a "$LOG_FILE"
        log_ok "Keypair criado: ${PROG_KEYPAIR_FILE}"
    else
        log_info "Keypair do programa já existe: ${PROG_KEYPAIR_FILE}"
    fi

    PROG_ID_FROM_KEY=$(keypair_to_pubkey "$PROG_KEYPAIR_FILE" 2>/dev/null || \
                       solana-keygen pubkey "$PROG_KEYPAIR_FILE" 2>/dev/null || echo "")
    if [ -z "$PROG_ID_FROM_KEY" ]; then
        log_err "Não foi possível obter Program ID do keypair!"; exit 1
    fi
    log_info "Program ID (do keypair): ${G}${PROG_ID_FROM_KEY}${NC}"

    # Verificar se programa já existe no chain
    PROG_EXISTS=$(solana program show "$PROG_ID_FROM_KEY" --url "$NET_RPC" 2>/dev/null | grep -c "Program Id" || echo "0")
    if [ "$PROG_EXISTS" -gt 0 ]; then
        log_ok "Programa já existe no chain: ${PROG_ID_FROM_KEY}"
        WARP_PROGRAM_ID="$PROG_ID_FROM_KEY"
    else
        # Verificar saldo
        BALANCE=$(solana balance "$NET_KEYPAIR" --url "$NET_RPC" 2>/dev/null | awk '{print $1}' || echo "0")
        log_info "Saldo carteira: ${BALANCE} SOL"
        BINARY_SZ_BYTES=$(wc -c < "$BINARY_FILE" 2>/dev/null || echo "0")
        RENT_EST=$(python3 -c "print(f'~{($BINARY_SZ_BYTES * 0.00000348):.2f} SOL')" 2>/dev/null || echo "~2-5 SOL")
        log_info "Custo estimado do upload do binário: ${RENT_EST}"
        log_warn "Este é o custo inevitável de armazenar o programa na Solana."

        echo -ne "  ${W}Prosseguir com o deploy do binário? [S/n]: ${NC}"
        read -r CONF_DEPLOY 2>/dev/null || CONF_DEPLOY="s"
        [[ "${CONF_DEPLOY:-s}" =~ ^[sSyY]$ ]] || { log "  Cancelado."; exit 0; }

        log_info "Iniciando upload do binário para Solana..."
        log_warn "Isso pode demorar alguns minutos (upload ~${BINARY_SZ_BYTES} bytes)..."
        log ""

        # Gerar buffer keypair se não existir
        if [ ! -f "$BUFFER_KEYPAIR_FILE" ]; then
            solana-keygen new --no-passphrase --silent \
                --outfile "$BUFFER_KEYPAIR_FILE" 2>&1 | tee -a "$LOG_FILE"
        else
            log_info "Buffer keypair reutilizado: ${BUFFER_KEYPAIR_FILE}"
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
            --use-rpc \
            2>&1 | tee -a "$LOG_FILE"
        DEPLOY_EXIT=$?
        set -e

        if [ $DEPLOY_EXIT -ne 0 ]; then
            log_err "Deploy do programa falhou (exit $DEPLOY_EXIT)!"
            log_warn "O buffer pode estar parcialmente financiado — execute novamente para retomar."
            log "  Buffer key: ${BUFFER_KEYPAIR_FILE}"
            log "  Buffer pubkey: ${BUFFER_PUBKEY:-N/A}"
            log "  Para cancelar e recuperar o SOL do buffer:"
            log "    solana program close ${BUFFER_PUBKEY:-BUFFER_PUBKEY} --url ${NET_RPC} --keypair ${NET_KEYPAIR} --buffer"
            exit 1
        fi

        WARP_PROGRAM_ID="$PROG_ID_FROM_KEY"
        log_ok "Programa deployado: ${G}${WARP_PROGRAM_ID}${NC}"
    fi

    save_state
fi

log_ok "Program ID: ${G}${WARP_PROGRAM_ID}${NC}"

# Converter para hex32
if [ -z "${WARP_HEX:-}" ]; then
    WARP_HEX=$(b58_to_hex32 "$WARP_PROGRAM_ID")
    [ -z "$WARP_HEX" ] && { log_err "Falha ao converter Program ID para hex32!"; exit 1; }
    save_state
fi
log_info "Program ID (hex32): 0x${WARP_HEX}"

# Atualizar config com program_id
TMP=$(mktemp)
jq ".networks.\"${NET_KEY}\".warp_tokens.\"${TOKEN_KEY}\".program_id = \"${WARP_PROGRAM_ID}\" |
    .networks.\"${NET_KEY}\".warp_tokens.\"${TOKEN_KEY}\".program_hex = \"0x${WARP_HEX}\"" \
    "$SOL_CONFIG" > "$TMP" && mv "$TMP" "$SOL_CONFIG"
log_ok "warp-sealevel-config.json atualizado com program_id"

# ═════════════════════════════════════════════════════════════════════════════
# STEP 3 — INIT DO TOKEN (warp-route deploy — só init, binário já existe)
# ═════════════════════════════════════════════════════════════════════════════
log_sep "STEP 3 — INIT DO TOKEN (warp-route deploy → init only)"

if [ -n "${SKIP_INIT:-}" ]; then
    log_warn "SKIP_INIT definido — pulando init."
else
    if [ -z "$MAILBOX" ] || [ "$MAILBOX" = "null" ]; then
        log_err "Mailbox Solana não encontrado! Configure em warp-sealevel-config.json → .networks.${NET_KEY}.mailbox"
        exit 1
    fi

    # Cria token-config.json que o warp-route deploy precisa
    TOKEN_CONFIG="$WARP_ROUTE_DIR/token-config.json"
    META_NAME="$TOKEN_SYMBOL"
    META_SYM="$TOKEN_SYMBOL"

    # Tenta baixar metadata
    if [ -n "$SOL_META_URI" ] && [ "$SOL_META_URI" != "null" ]; then
        META_TMP=$(mktemp /tmp/sol-meta-XXXXXX.json)
        HTTP_CODE=$(curl -s -o "$META_TMP" -w "%{http_code}" --max-time 10 "$SOL_META_URI" 2>/dev/null || echo "000")
        if [ "$HTTP_CODE" = "200" ] && [ -s "$META_TMP" ]; then
            META_NAME=$(jq -r '.name   // ""' "$META_TMP" 2>/dev/null | tr -d '\r\n')
            META_SYM=$(jq -r  '.symbol // ""' "$META_TMP" 2>/dev/null | tr -d '\r\n')
            log_ok "Metadata: name='${META_NAME}' symbol='${META_SYM}'"
        fi
        rm -f "$META_TMP"
    fi
    [ -z "$META_NAME" ] && META_NAME="$TOKEN_NAME"
    [ -z "$META_SYM"  ] && META_SYM="$TOKEN_SYMBOL"

    # Gera token-config.json
    _BASE=$(jq -n \
        --arg net  "${NET_KEY}" \
        --arg type "${SOL_TYPE:-synthetic}" \
        --arg name "${META_NAME}" \
        --arg sym  "${META_SYM}" \
        --argjson dec "${SOL_TOK_DEC:-6}" \
        --arg igp  "${IGP_ACCOUNT}" \
        '{($net): {"type":$type,"name":$name,"symbol":$sym,"decimals":$dec,"totalSupply":"0","interchainGasPaymaster":$igp}}')

    # Inclui URI somente se acessível
    if [ "${HTTP_CODE:-000}" = "200" ]; then
        TOKEN_CONFIG_JSON=$(echo "$_BASE" | jq --arg net "${NET_KEY}" --arg uri "${SOL_META_URI}" '.[$net].uri = $uri')
    else
        TOKEN_CONFIG_JSON="$_BASE"
        log_warn "URI omitida do token-config (não acessível) — metadata será adicionada depois."
    fi
    echo "$TOKEN_CONFIG_JSON" > "$TOKEN_CONFIG"
    log_ok "token-config.json criado: ${TOKEN_CONFIG}"

    log_info "Chamando warp-route deploy (detecta programa existente → executa APENAS init)..."
    log_info "Mailbox: ${MAILBOX}"
    log ""

    cd "$CLIENT_DIR"
    INIT_TMP=$(mktemp)
    set +e
    cargo run --release -- \
        -k "$NET_KEYPAIR" \
        -u "$NET_RPC" \
        warp-route deploy \
        --warp-route-name "$TOKEN_KEY" \
        --environment "$NET_ENV" \
        --environments-dir "$ENVIRONMENTS_DIR" \
        --token-config-file "$TOKEN_CONFIG" \
        --built-so-dir "$BUILT_SO_DIR" \
        --registry "$HOME/.hyperlane/registry" \
        --ata-payer-funding-amount 5000000 2>&1 \
        | grep -v "^warning:" | grep -v "^note:" \
        | tee -a "$LOG_FILE" "$INIT_TMP"
    INIT_EXIT=$?
    cd "$SCRIPT_DIR"
    INIT_OUT=$(cat "$INIT_TMP"); rm -f "$INIT_TMP"
    set -e

    if echo "$INIT_OUT" | grep -qiE "already deployed|skipping init|already exists"; then
        log_ok "Programa já inicializado (idempotente) ✅"
    elif [ $INIT_EXIT -eq 0 ]; then
        log_ok "Token inicializado com sucesso!"
    else
        log_warn "warp-route deploy retornou exit $INIT_EXIT — verifique o log."
        log "  Pode ser que o init já tenha sido feito. Prosseguindo com configuração..."
    fi
fi

# ═════════════════════════════════════════════════════════════════════════════
# STEP 4 — CONFIGURAR ISM
# ═════════════════════════════════════════════════════════════════════════════
log_sep "STEP 4 — CONFIGURAR ISM"

if [ -n "${SKIP_ISM:-}" ]; then
    log_warn "SKIP_ISM — pulando."
else
    run_client() {
        if [ -x "$CLIENT_BIN" ]; then
            "$CLIENT_BIN" "$@"
        else
            cd "$CLIENT_DIR"
            cargo run --release --quiet -- "$@"
            cd "$SCRIPT_DIR"
        fi
    }

    set +e
    TMP=$(mktemp)
    timeout 180 run_client \
        -k "$NET_KEYPAIR" -u "$NET_RPC" \
        token set-interchain-security-module \
        --program-id "$WARP_PROGRAM_ID" \
        --ism "$ISM_PROGRAM_ID" 2>&1 \
        | grep -v "^warning:" | grep -v "^note:" | grep -v "^Compiling" \
        | tee -a "$LOG_FILE" "$TMP"
    ISM_EXIT=$?
    ISM_OUT=$(cat "$TMP"); rm -f "$TMP"
    set -e

    if [ $ISM_EXIT -eq 0 ]; then
        log_ok "ISM configurado: ${ISM_PROGRAM_ID}"
    elif echo "$ISM_OUT" | grep -qiE "already|same"; then
        log_ok "ISM já configurado."
    else
        log_warn "Erro ao configurar ISM (exit $ISM_EXIT). Manual:"
        log "  cd $CLIENT_DIR && cargo run --release -- -k $NET_KEYPAIR -u $NET_RPC token set-interchain-security-module --program-id $WARP_PROGRAM_ID --ism $ISM_PROGRAM_ID"
    fi
fi

# ═════════════════════════════════════════════════════════════════════════════
# STEP 5 — CONFIGURAR IGP
# ═════════════════════════════════════════════════════════════════════════════
log_sep "STEP 5 — CONFIGURAR IGP"

if [ -n "${SKIP_IGP:-}" ]; then
    log_warn "SKIP_IGP — pulando."
else
    set +e
    TMP=$(mktemp)
    timeout 180 run_client \
        -k "$NET_KEYPAIR" -u "$NET_RPC" \
        token igp \
        --program-id "$WARP_PROGRAM_ID" \
        set \
        "$IGP_PROGRAM_ID" \
        igp \
        "$IGP_ACCOUNT" 2>&1 \
        | grep -v "^warning:" | grep -v "^note:" | grep -v "^Compiling" \
        | tee -a "$LOG_FILE" "$TMP"
    IGP_EXIT=$?
    IGP_OUT=$(cat "$TMP"); rm -f "$TMP"
    set -e

    if [ $IGP_EXIT -eq 0 ]; then
        log_ok "IGP configurado: ${IGP_PROGRAM_ID} / ${IGP_ACCOUNT}"
    elif echo "$IGP_OUT" | grep -qiE "already|same"; then
        log_ok "IGP já configurado."
    else
        log_warn "Erro ao configurar IGP (exit $IGP_EXIT). Manual:"
        log "  cd $CLIENT_DIR && cargo run --release -- -k $NET_KEYPAIR -u $NET_RPC token igp --program-id $WARP_PROGRAM_ID set $IGP_PROGRAM_ID igp $IGP_ACCOUNT"
    fi
fi

# ═════════════════════════════════════════════════════════════════════════════
# STEP 6 — DESTINATION GAS (Terra Classic)
# ═════════════════════════════════════════════════════════════════════════════
log_sep "STEP 6 — DESTINATION GAS (Terra Classic domain ${TERRA_DOMAIN})"

if [ -n "${SKIP_GAS:-}" ]; then
    log_warn "SKIP_GAS — pulando."
else
    set +e
    TMP=$(mktemp)
    timeout 180 run_client \
        -k "$NET_KEYPAIR" -u "$NET_RPC" \
        token set-destination-gas \
        --program-id "$WARP_PROGRAM_ID" \
        "$TERRA_DOMAIN" "$DEST_GAS" 2>&1 \
        | grep -v "^warning:" | grep -v "^note:" | grep -v "^Compiling" \
        | tee -a "$LOG_FILE" "$TMP"
    GAS_EXIT=$?
    GAS_OUT=$(cat "$TMP"); rm -f "$TMP"
    set -e

    if [ $GAS_EXIT -eq 0 ]; then
        log_ok "Destination gas: domain=${TERRA_DOMAIN} gas=${DEST_GAS}"
    elif echo "$GAS_OUT" | grep -qiE "already|same"; then
        log_ok "Destination gas já configurado."
    else
        log_warn "Erro ao configurar destination gas (exit $GAS_EXIT). Manual:"
        log "  cd $CLIENT_DIR && cargo run --release -- -k $NET_KEYPAIR -u $NET_RPC token set-destination-gas --program-id $WARP_PROGRAM_ID $TERRA_DOMAIN $DEST_GAS"
    fi
fi

# ═════════════════════════════════════════════════════════════════════════════
# STEP 7 — ENROLL REMOTE ROUTER (Solana → Terra Classic)
# ═════════════════════════════════════════════════════════════════════════════
log_sep "STEP 7 — ENROLL REMOTE ROUTER (Solana → Terra Classic)"

if [ -n "${SKIP_ENROLL:-}" ]; then
    log_warn "SKIP_ENROLL — pulando."
elif [ -z "$TERRA_WARP_ADDR" ] || [ "$TERRA_WARP_ADDR" = "null" ]; then
    log_warn "Warp TC não deployado — pulando enroll."
else
    TC_HEX="${TERRA_WARP_HEX#0x}"
    set +e
    TMP=$(mktemp)
    timeout 180 run_client \
        -k "$NET_KEYPAIR" -u "$NET_RPC" \
        token enroll-remote-router \
        --program-id "$WARP_PROGRAM_ID" \
        "$TERRA_DOMAIN" "0x${TC_HEX}" 2>&1 \
        | grep -v "^warning:" | grep -v "^note:" | grep -v "^Compiling" \
        | tee -a "$LOG_FILE" "$TMP"
    ENR_EXIT=$?
    ENR_OUT=$(cat "$TMP"); rm -f "$TMP"
    set -e

    if [ $ENR_EXIT -eq 0 ]; then
        log_ok "Remote Router enrolled: Terra Classic (domain ${TERRA_DOMAIN})"
    elif echo "$ENR_OUT" | grep -qiE "already|exists"; then
        log_ok "Remote Router já enrolled."
    else
        log_warn "Erro ao enroll (exit $ENR_EXIT). Manual:"
        log "  cd $CLIENT_DIR && cargo run --release -- -k $NET_KEYPAIR -u $NET_RPC token enroll-remote-router --program-id $WARP_PROGRAM_ID $TERRA_DOMAIN 0x${TC_HEX}"
    fi
fi

# ═════════════════════════════════════════════════════════════════════════════
# STEP 8 — SET ROUTE TERRA CLASSIC (Terra Classic → Solana)
# ═════════════════════════════════════════════════════════════════════════════
log_sep "STEP 8 — SET ROUTE TERRA CLASSIC (Terra Classic → Solana)"

if [ -n "${SKIP_TC_ROUTE:-}" ]; then
    log_warn "SKIP_TC_ROUTE — pulando."
elif [ -z "$TERRA_WARP_ADDR" ] || [ "$TERRA_WARP_ADDR" = "null" ]; then
    log_warn "Warp TC não deployado — pulando set_route."
elif [ -z "${TERRA_PRIVATE_KEY:-}" ]; then
    log_warn "TERRA_PRIVATE_KEY não definida — pulando set_route TC."
    log "  Execute: export TERRA_PRIVATE_KEY='hex_key'"
    log "  Depois:  export WARP_PROGRAM_ID='${WARP_PROGRAM_ID}' SKIP_ENROLL=1 && ./deploy-warp-solana-buffer.sh"
else
    TERRA_PRIV_CLEAN="${TERRA_PRIVATE_KEY#0x}"
    log_info "Warp TC: ${TERRA_WARP_ADDR}"
    log_info "Domain Solana: ${NET_DOMAIN}"
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
    } catch(e) { /* rota não existe ainda */ }

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
        ok)           log_ok "set_route executado! TC → Solana ligados."
                      log "   TX: ${B}https://finder.hexxagon.io/${TERRA_CHAIN_ID}/tx/${SR_TX}${NC}" ;;
        already_set)  EXISTING=$(echo "$SR_RESULT" | grep "^EXISTING=" | cut -d= -f2 || echo "")
                      log_ok "Rota já configurada na TC (${EXISTING:-already set})." ;;
        error)        log_warn "set_route falhou: ${SR_ERR}"
                      log "  Manual: terrad tx wasm execute \"${TERRA_WARP_ADDR}\" '{\"router\":{\"set_route\":{\"set\":{\"domain\":${NET_DOMAIN},\"route\":\"${WARP_HEX}\"}}}}' --from <KEY> --chain-id ${TERRA_CHAIN_ID} --node ${TERRA_RPC} --gas auto --gas-adjustment 1.5 --fees 12000000uluna --yes" ;;
        *)            log_warn "Resultado inesperado (exit=$NODE_EXIT)."
                      [ -n "$SR_RESULT" ] && echo "$SR_RESULT" | head -5 | tee -a "$LOG_FILE" ;;
    esac
fi

# ═════════════════════════════════════════════════════════════════════════════
# STEP 9 — TRANSFER OWNERSHIP + QUERY MINT
# ═════════════════════════════════════════════════════════════════════════════
log_sep "STEP 9 — QUERY WARP + MINT ADDRESS"

set +e
QUERY_OUT=$(timeout 60 run_client \
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
        log_ok "warp-sealevel-config.json atualizado (deployed=true, mint_address)"
        save_state
    fi
fi

if [ -n "$SOL_OWNER" ] && [ "$SOL_OWNER" != "null" ]; then
    log_info "Transferindo ownership para: $SOL_OWNER"
    set +e
    timeout 120 run_client \
        -k "$NET_KEYPAIR" -u "$NET_RPC" \
        token transfer-ownership \
        --program-id "$WARP_PROGRAM_ID" \
        "$SOL_OWNER" 2>&1 \
        | grep -v "^warning:" | grep -v "^note:" | grep -v "^Compiling" \
        | tee -a "$LOG_FILE"
    OWN_EXIT=$?
    set -e
    [ $OWN_EXIT -eq 0 ] && log_ok "Ownership transferida para: $SOL_OWNER" \
                         || log_warn "Erro ao transferir ownership (pode já estar correto)."
fi

# ═════════════════════════════════════════════════════════════════════════════
# RELATÓRIO FINAL
# ═════════════════════════════════════════════════════════════════════════════
NET_UPPER=$(echo "$NET_KEY" | tr '[:lower:]' '[:upper:]')
TOK_UPPER=$(echo "$TOKEN_KEY" | tr '[:lower:]' '[:upper:]')
REPORT="$LOG_DIR/WARP-${NET_UPPER}-${TOK_UPPER}-BUFFER.txt"

cat > "$REPORT" <<TXT
═══════════════════════════════════════════════════════════
  WARP SOLANA (BUFFER DEPLOY): ${TOKEN_SYMBOL} on ${NET_DISPLAY}
  Generated: $(date '+%Y-%m-%d %H:%M:%S')
═══════════════════════════════════════════════════════════

[PROGRAMA SOLANA]
Network:          ${NET_DISPLAY} (domain: ${NET_DOMAIN})
Token:            ${TOKEN_NAME} (${TOKEN_SYMBOL})
Program ID (b58): ${WARP_PROGRAM_ID}
Program ID (hex): 0x${WARP_HEX}
Mint Address:     ${MINT_ADDRESS:-N/A}
ISM Program:      ${ISM_PROGRAM_ID}
IGP Program:      ${IGP_PROGRAM_ID}
IGP Account:      ${IGP_ACCOUNT}
Dest Gas (TC):    ${DEST_GAS}
Mailbox:          ${MAILBOX:-N/A}
Owner:            ${SOL_OWNER:-keypair}
RPC:              ${NET_RPC}
Explorer:         ${NET_EXPLORER}

[WARP TERRA CLASSIC]
Address:   ${TERRA_WARP_ADDR:-N/A}
Hex:       ${TERRA_WARP_HEX:-N/A}
Domain:    ${TERRA_DOMAIN}
Chain ID:  ${TERRA_CHAIN_ID}

[VERIFICAÇÃO MANUAL]
# Query Solana:
cargo run --release -- -k ${NET_KEYPAIR} -u ${NET_RPC} token query --program-id ${WARP_PROGRAM_ID} synthetic

# Route TC:
terrad query wasm contract-state smart ${TERRA_WARP_ADDR:-TC_WARP} '{"router":{"get_route":{"domain":${NET_DOMAIN}}}}' --node ${TERRA_RPC}

# Buffer no chain (se deploy pendente):
solana program show --url ${NET_RPC} --programs --keypair ${NET_KEYPAIR} | grep Program
TXT

log_ok "Relatório salvo: ${C}${REPORT}${NC}"

log ""
log "╔══════════════════════════════════════════════════════════════════════════╗"
log "║          ✅  WARP SOLANA (BUFFER) CONFIGURADO!                          ║"
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
    log "  ⚠️  Solana → Terra Classic: pendente"
fi
if [ -z "${SKIP_TC_ROUTE:-}" ] && [ -n "${TERRA_PRIVATE_KEY:-}" ]; then
    log "  ✅ Terra Classic → Solana (set_route, domain ${NET_DOMAIN})"
else
    log "  ⚠️  Terra Classic → Solana: pendente"
fi
log ""
log "${B}📄 Relatório: ${REPORT}${NC}"
log "${B}📋 Log:       ${LOG_FILE}${NC}"
