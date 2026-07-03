#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
#  🔑  transfer-solana-ownership.sh
#  Transfere TODOS os papéis de owner/admin do deployment comunitário na Solana
#  da autoridade atual (deployer) para um NOVO_OWNER.
#
#  Papéis cobertos (para a rede NET_KEY):
#    1. IGP account          → owner           (igp transfer-igp-ownership)
#    2. IGP account          → beneficiary     (igp set-igp-beneficiary)      [opcional]
#    3. Overhead IGP account → owner           (igp transfer-overhead-igp-ownership)
#    4. ISM program          → owner           (multisig-ism-message-id transfer-ownership)
#    5. IGP program          → upgrade auth    (solana program set-upgrade-authority)
#    6. ISM program          → upgrade auth    (solana program set-upgrade-authority)
#    7. Cada warp token deployado:
#         - warp route owner (token transfer-ownership)
#         - upgrade authority (solana program set-upgrade-authority)
#
#  FASE 1 (ensaio):    NEW_OWNER = EMAYGf...  (chave de owner que você controla)
#  FASE 2 (produção):  NEW_OWNER = <vault do multisig Squads da comunidade>
#
#  ⚠️  IRREVERSÍVEL: na Solana não há "claim". Assim que a tx confirma, o
#      NEW_OWNER passa a mandar e a autoridade antiga perde o controle.
#      No ensaio (você controla as duas chaves) dá para reverter rodando de novo
#      com NEW_OWNER=<deployer> e OWNER_KEYPAIR=<keypair do EMAYGf>.
#      Com um multisig, é porta de mão única.
#
#  SEGURO POR PADRÃO: roda em DRY-RUN. Use --execute para executar de verdade.
#
#  Uso:
#    ./transfer-solana-ownership.sh                         # dry-run (testnet, → EMAYGf)
#    ./transfer-solana-ownership.sh --execute               # executa
#    NET_KEY=solanamainnet ./transfer-solana-ownership.sh   # mainnet (dry-run)
#    NEW_OWNER=<SQUADS_VAULT> ./transfer-solana-ownership.sh --execute   # → multisig
#
#  Variáveis:
#    NET_KEY            rede (default: solanatestnet)
#    NEW_OWNER         destino (default: EMAYGf... — owner de teste)
#    OWNER_KEYPAIR     keypair da autoridade ATUAL que assina (default: deployer)
#    SKIP_BENEFICIARY  =1 para não mexer no beneficiary do IGP
#    CLIENT            caminho do hyperlane-sealevel-client
# ═══════════════════════════════════════════════════════════════════════════════
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOL_CONFIG="$SCRIPT_DIR/warp-sealevel-config.json"
CLIENT="${CLIENT:-$HOME/hyperlane-monorepo/rust/sealevel/target/release/hyperlane-sealevel-client}"
ENVIRONMENTS_BASE="${ENVIRONMENTS_BASE:-$HOME/hyperlane-monorepo/rust/sealevel/environments}"
CUSTOM_ENV="mainnet-tc-community"

NET_KEY="${NET_KEY:-solanatestnet}"
NEW_OWNER="${NEW_OWNER:-EMAYGfEyhywUyEX6kfG5FZZMfznmKXM8PbWpkJhJ9Jjd}"
OWNER_KEYPAIR="${OWNER_KEYPAIR:-$HOME/keys/solana-keypair-BirXd4QDxfq2vx9LGqgXXSgZrjT81rhoFGUbQRWDEf1j.json}"

EXECUTE=0
TOKEN_KEY="${TOKEN_KEY:-}"
for arg in "$@"; do
  case "$arg" in
    --execute) EXECUTE=1 ;;
    --*)       echo "flag desconhecida: $arg" >&2; exit 1 ;;
    *)         TOKEN_KEY="$arg" ;;   # primeiro argumento posicional = token
  esac
done

# ── cores ────────────────────────────────────────────────────────────────────
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'; C='\033[0;36m'; W='\033[1m'; NC='\033[0m'
info(){ echo -e "${B}ℹ️ ${NC} $*"; }
ok(){   echo -e "${G}✅${NC} $*"; }
warn(){ echo -e "${Y}⚠️ ${NC} $*"; }
err(){  echo -e "${R}❌${NC} $*"; }
sep(){  echo -e "\n${C}${W}$*${NC}\n────────────────────────────────────────────────────────────────"; }

# ── checagens ────────────────────────────────────────────────────────────────
[ -f "$SOL_CONFIG" ] || { err "config não encontrado: $SOL_CONFIG"; exit 1; }
[ -x "$CLIENT" ]     || { err "client não encontrado/executável: $CLIENT"; exit 1; }
command -v jq >/dev/null || { err "jq é necessário"; exit 1; }
command -v solana >/dev/null || { err "solana CLI é necessário"; exit 1; }
[ "$EXECUTE" -eq 1 ] && { [ -f "$OWNER_KEYPAIR" ] || { err "OWNER_KEYPAIR não existe: $OWNER_KEYPAIR"; exit 1; }; }

# ── resolve endereços a partir do config + artifacts ─────────────────────────
scfg(){ jq -r "$1 // empty" "$SOL_CONFIG"; }
RPC=$(scfg ".networks.\"$NET_KEY\".rpc")
IGP_PROGRAM=$(scfg ".networks.\"$NET_KEY\".igp.program_id")
OVERHEAD_IGP=$(scfg ".networks.\"$NET_KEY\".igp.account")
ISM_PROGRAM=$(scfg ".networks.\"$NET_KEY\".ism.program_id")

# inner IGP account vem do artifacts do env (não fica no warp-sealevel-config)
IGP_ARTIFACTS="$ENVIRONMENTS_BASE/$CUSTOM_ENV/igp/$NET_KEY/tc-community/igp-accounts.json"
INNER_IGP=""
[ -f "$IGP_ARTIFACTS" ] && INNER_IGP=$(jq -r '.igp_account // empty' "$IGP_ARTIFACTS")

[ -n "$RPC" ] || { err "RPC não resolvido para $NET_KEY"; exit 1; }

# ── token obrigatório: qual warp você quer transferir (junto com a infra) ────
if [ -z "$TOKEN_KEY" ]; then
  err "Informe o warp token. Uso: ./transfer-solana-ownership.sh <token> [--execute]"
  echo "   Tokens deployados em $NET_KEY:" >&2
  jq -r ".networks.\"$NET_KEY\".warp_tokens | to_entries[]
    | select(.value.deployed==true and (.value.program_id//\"\")!=\"\")
    | \"     - \(.key)  (\(.value.program_id))\"" "$SOL_CONFIG" >&2
  exit 1
fi
TOKEN_PID=$(scfg ".networks.\"$NET_KEY\".warp_tokens.\"$TOKEN_KEY\".program_id")
[ -n "$TOKEN_PID" ] || { err "token '$TOKEN_KEY' sem program_id (não deployado?) em $NET_KEY"; exit 1; }

# ── helpers de leitura on-chain (para dry-run informativo) ───────────────────
# upgrade authority via `solana program show` (confiável)
prog_authority(){ solana program show "$1" --url "$RPC" 2>/dev/null | awk -F': ' '/^Authority:/{print $2}'; }
# owner do access-control de um programa token (warp route) via token query
token_owner(){
  "$CLIENT" -u "$RPC" token query --program-id "$1" synthetic 2>/dev/null \
    | grep -A2 "^        owner: Some(" | sed -n '2p' | tr -d ' ,' || true
}

# ── executor: roda ou só imprime, conforme --execute ─────────────────────────
run(){
  echo -e "   ${W}\$${NC} $*"
  if [ "$EXECUTE" -eq 1 ]; then
    set +e; "$@" 2>&1 | sed 's/^/     /'; local rc=${PIPESTATUS[0]}; set -e
    if [ $rc -eq 0 ]; then ok "ok"; else warn "falhou/pulado (rc=$rc) — pode já estar transferido ou você não é a autoridade atual"; fi
  fi
}
# variante para o solana CLI (upgrade authority)
run_sol(){
  echo -e "   ${W}\$${NC} $*"
  if [ "$EXECUTE" -eq 1 ]; then
    set +e; "$@" 2>&1 | sed 's/^/     /'; local rc=${PIPESTATUS[0]}; set -e
    if [ $rc -eq 0 ]; then ok "ok"; else warn "falhou/pulado (rc=$rc)"; fi
  fi
}

# transfere upgrade authority de um programa (skip se já == NEW_OWNER)
transfer_upgrade_authority(){
  local label="$1" pid="$2"
  [ -n "$pid" ] || { warn "$label: program_id vazio — pulado"; return; }
  local cur; cur=$(prog_authority "$pid")
  if [ "$cur" = "$NEW_OWNER" ]; then ok "$label upgrade-authority já é NEW_OWNER — pulado"; return; fi
  if [ -z "$cur" ]; then warn "$label ($pid): sem upgrade authority (imutável?) — pulado"; return; fi
  info "$label upgrade-authority: ${cur} → ${NEW_OWNER}"
  run_sol solana program set-upgrade-authority "$pid" \
    -k "$OWNER_KEYPAIR" --upgrade-authority "$OWNER_KEYPAIR" \
    --new-upgrade-authority "$NEW_OWNER" \
    --skip-new-upgrade-authority-signer-check \
    --url "$RPC"
}

# ── banner ───────────────────────────────────────────────────────────────────
echo -e "${C}${W}╔══════════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${C}${W}║  🔑  TRANSFER SOLANA OWNERSHIP — community deployment                     ║${NC}"
echo -e "${C}${W}╚══════════════════════════════════════════════════════════════════════════╝${NC}"
info "Rede:        ${C}${NET_KEY}${NC}  (rpc: ${RPC})"
info "Token:       ${C}${TOKEN_KEY}${NC}  (${TOKEN_PID})"
info "NEW_OWNER:   ${G}${NEW_OWNER}${NC}"
info "Autoridade:  ${OWNER_KEYPAIR}"
info "Escopo:      infra compartilhada (IGP/ISM) + warp '${TOKEN_KEY}'"
info "IGP program: ${IGP_PROGRAM}"
info "IGP inner:   ${INNER_IGP:-<não resolvido>}"
info "Overhead IGP:${OVERHEAD_IGP}"
info "ISM program: ${ISM_PROGRAM}"
if [ "$EXECUTE" -eq 1 ]; then
  echo -e "\n${R}${W}*** MODO --execute: as transferências são IRREVERSÍVEIS ***${NC}"
  echo -ne "${W}Digite 'TRANSFERIR' para confirmar: ${NC}"; read -r CONF
  [ "$CONF" = "TRANSFERIR" ] || { err "cancelado."; exit 1; }
else
  warn "DRY-RUN — nada será executado. Use ${W}--execute${NC} para valer."
fi

# ═════════════════════════════════════════════════════════════════════════════
# 1-3. IGP (beneficiary ANTES de transferir o owner!)
# ═════════════════════════════════════════════════════════════════════════════
sep "IGP — beneficiary + owner (inner) + overhead owner"
if [ -z "$INNER_IGP" ]; then
  warn "inner IGP account não resolvido ($IGP_ARTIFACTS) — pulando papéis do IGP inner."
else
  if [ -z "${SKIP_BENEFICIARY:-}" ]; then
    info "IGP beneficiary → ${NEW_OWNER}   (precisa ser feito ANTES de transferir o owner)"
    run "$CLIENT" -k "$OWNER_KEYPAIR" -u "$RPC" igp set-igp-beneficiary \
        --program-id "$IGP_PROGRAM" --igp-account "$INNER_IGP" "$NEW_OWNER"
  else
    warn "SKIP_BENEFICIARY=1 — beneficiary não alterado."
  fi
  info "IGP owner (inner) → ${NEW_OWNER}"
  run "$CLIENT" -k "$OWNER_KEYPAIR" -u "$RPC" igp transfer-igp-ownership \
      --program-id "$IGP_PROGRAM" --igp-account "$INNER_IGP" "$NEW_OWNER"
fi
if [ -n "$OVERHEAD_IGP" ]; then
  info "Overhead IGP owner → ${NEW_OWNER}"
  run "$CLIENT" -k "$OWNER_KEYPAIR" -u "$RPC" igp transfer-overhead-igp-ownership \
      --program-id "$IGP_PROGRAM" --igp-account "$OVERHEAD_IGP" "$NEW_OWNER"
fi

# ═════════════════════════════════════════════════════════════════════════════
# 4. ISM owner
# ═════════════════════════════════════════════════════════════════════════════
sep "ISM — owner (access control)"
if [ -n "$ISM_PROGRAM" ]; then
  info "ISM owner → ${NEW_OWNER}"
  run "$CLIENT" -k "$OWNER_KEYPAIR" -u "$RPC" multisig-ism-message-id transfer-ownership \
      --program-id "$ISM_PROGRAM" "$NEW_OWNER"
else
  warn "ISM program_id vazio — pulado."
fi

# ═════════════════════════════════════════════════════════════════════════════
# 5-6. Upgrade authorities dos programas de infra (IGP, ISM)
# ═════════════════════════════════════════════════════════════════════════════
sep "Upgrade authorities — IGP + ISM programs"
transfer_upgrade_authority "IGP program" "$IGP_PROGRAM"
transfer_upgrade_authority "ISM program" "$ISM_PROGRAM"

# ═════════════════════════════════════════════════════════════════════════════
# 7. Warp tokens deployados: route owner + upgrade authority
# ═════════════════════════════════════════════════════════════════════════════
sep "Warp '${TOKEN_KEY}' — route owner + upgrade authority"
echo -e "${W}• token ${C}${TOKEN_KEY}${NC} (${TOKEN_PID})"
# route owner
CUR_OWN=$(token_owner "$TOKEN_PID")
if [ "$CUR_OWN" = "$NEW_OWNER" ]; then
  ok "  route owner já é NEW_OWNER — pulado"
else
  info "  route owner ${CUR_OWN:-?} → ${NEW_OWNER}"
  run "$CLIENT" -k "$OWNER_KEYPAIR" -u "$RPC" token transfer-ownership \
      --program-id "$TOKEN_PID" "$NEW_OWNER"
fi
# upgrade authority
transfer_upgrade_authority "  token $TOKEN_KEY" "$TOKEN_PID"

# ═════════════════════════════════════════════════════════════════════════════
sep "RESUMO"
if [ "$EXECUTE" -eq 1 ]; then
  ok "Execução concluída. Verifique com os comandos abaixo:"
else
  info "DRY-RUN concluído. Reveja o plano acima e rode com ${W}--execute${NC} quando estiver pronto."
fi
cat <<EOF

  Verificação (owner/authority após transferir):
    solana program show ${IGP_PROGRAM} --url ${RPC} | grep Authority
    solana program show ${ISM_PROGRAM} --url ${RPC} | grep Authority
    ${CLIENT} -u ${RPC} token query --program-id <TOKEN_PID> synthetic | grep -A2 'owner: Some'

  Reverter o ensaio (você controla as duas chaves):
    NEW_OWNER=<deployer> OWNER_KEYPAIR=<keypair do NEW_OWNER atual> ./transfer-solana-ownership.sh --execute
EOF
