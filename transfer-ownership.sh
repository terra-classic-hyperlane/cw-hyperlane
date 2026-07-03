#!/usr/bin/env bash
#
# transfer-ownership.sh — Transfere owner (e, opcionalmente, admin de migração)
# de todos os contratos Hyperlane no Terra Classic para a conta da GOVERNANÇA.
#
# >>> SEGURO POR PADRÃO: roda em --dry-run (NÃO executa nada). <<<
# Para executar de verdade, passe --execute explicitamente.
#
# Mecanismo (confirmado no código hpl_ownable):
#   - Transferência de OWNER é em DOIS PASSOS:
#       1) VOCÊ (owner atual) chama  init_ownership_transfer { next_owner: GOV }
#       2) A GOVERNANÇA chama        claim_ownership {}        (precisa aceitar!)
#     Enquanto a governança não der o claim, VOCÊ continua sendo o owner.
#   - Transferência de ADMIN (migração) é em UM PASSO: set-contract-admin (imediato).
#
# Uso:
#   ./transfer-ownership.sh                      # dry-run: passo 1 (init transfer) p/ você rodar
#   ./transfer-ownership.sh --include-admin      # dry-run: + set-contract-admin
#   ./transfer-ownership.sh --claim              # dry-run: comandos de CLAIM p/ a governança rodar
#   ./transfer-ownership.sh --execute            # EXECUTA o passo 1 de verdade (cuidado!)
#   ./transfer-ownership.sh --claim --execute    # governança EXECUTA o claim
#
set -euo pipefail

# ============================================================================
# >>>>>>>>>>>>>>>>>>>>>>  CONFIGURE AQUI  <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
# ============================================================================

# Conta da governança que receberá owner/admin (terra1...). OBRIGATÓRIO.
GOVERNANCE_ADDRESS=""

# Seu endereço atual de owner (terra1...). Usado como FILTRO DE SEGURANÇA:
# o script só mexe em contratos cujo owner == este endereço. OBRIGATÓRIO.
CURRENT_OWNER=""

# Nome da key no keyring que assina as transações (terrad keys list).
#   - No modo normal: a SUA key (deployer/owner atual).
#   - No modo --claim: a key da GOVERNANÇA (se for conta normal/multisig).
SIGNER_KEY=""

# Rede
BINARY="terrad"
CHAIN_ID="columbus-5"
NODE="https://terra-classic-rpc.publicnode.com:443"
GAS_PRICES="28.325uluna"
GAS_ADJUST="1.5"

# Arquivo de contexto do deploy (endereços dos contratos núcleo; warp é ignorado)
CONTEXT_FILE="$(cd "$(dirname "$0")" && pwd)/context/terraclassic.json"

# NOTA: WARP ROUTES NÃO ENTRAM. Cada warp route é responsabilidade de quem o
# criou; o script ignora automaticamente tudo que está sob "deployments.warp".
#
# Contratos de INFRAESTRUTURA extra (mailbox/ISM/IGP/hook) que por acaso não
# estejam no context json — cole aqui. O script valida cada um via get_owner.
# (NÃO coloque warp routes aqui.)
EXTRA_CONTRACTS=(
  # "terra1..."
  # "terra1..."
)

# ============================================================================
# >>>>>>>>>>>>>>>>>>>>>>  NÃO PRECISA EDITAR ABAIXO  <<<<<<<<<<<<<<<<<<<<<<<<<<<
# ============================================================================

DRY_RUN=1
INCLUDE_ADMIN=0
CLAIM_MODE=0

for arg in "$@"; do
  case "$arg" in
    --execute)       DRY_RUN=0 ;;
    --dry-run)       DRY_RUN=1 ;;
    --include-admin) INCLUDE_ADMIN=1 ;;
    --claim)         CLAIM_MODE=1 ;;
    -h|--help)
      grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Argumento desconhecido: $arg"; exit 1 ;;
  esac
done

c_red=$'\e[31m'; c_grn=$'\e[32m'; c_ylw=$'\e[33m'; c_cyn=$'\e[36m'; c_off=$'\e[0m'
die(){ echo "${c_red}ERRO:${c_off} $*" >&2; exit 1; }
note(){ echo "${c_cyn}»${c_off} $*"; }

# ---- validações ------------------------------------------------------------
command -v "$BINARY" >/dev/null 2>&1 || die "binário '$BINARY' não encontrado no PATH."
command -v python3   >/dev/null 2>&1 || die "python3 é necessário para ler o JSON."
[ -f "$CONTEXT_FILE" ] || die "context não encontrado: $CONTEXT_FILE"
[[ "$GOVERNANCE_ADDRESS" == terra1* ]] || die "configure GOVERNANCE_ADDRESS (terra1...)."
[[ "$CURRENT_OWNER"      == terra1* ]] || die "configure CURRENT_OWNER (terra1...)."

if [ "$DRY_RUN" -eq 0 ]; then
  [[ -n "$SIGNER_KEY" ]] || die "modo --execute exige SIGNER_KEY configurado."
fi

# ---- coleta de endereços candidatos ----------------------------------------
# Pega todos os terra1... que parecem CONTRATO (>= 58 chars de payload) do
# context json + os EXTRA_CONTRACTS. Wallets (38 chars) são ignoradas.
mapfile -t CTX_ADDRS < <(python3 - "$CONTEXT_FILE" <<'PY'
import json,sys,re
d=json.load(open(sys.argv[1]))
seen=[]
def walk(o,key=None):
    # Pula toda a subárvore de warp routes: são responsabilidade de quem criou.
    if key == "warp":
        return
    if isinstance(o,dict):
        for k,v in o.items(): walk(v,k)
    elif isinstance(o,list):
        for v in o: walk(v,key)
    elif isinstance(o,str):
        # contratos no Terra têm 32 bytes -> bech32 longo (~63 chars)
        if re.fullmatch(r"terra1[0-9a-z]{58}", o) and o not in seen:
            seen.append(o)
walk(d)
print("\n".join(seen))
PY
)

CANDIDATES=("${CTX_ADDRS[@]}")
for a in "${EXTRA_CONTRACTS[@]}"; do
  [[ "$a" == terra1* ]] && CANDIDATES+=("$a")
done

# dedup
mapfile -t CANDIDATES < <(printf '%s\n' "${CANDIDATES[@]}" | awk 'NF && !seen[$0]++')

[ "${#CANDIDATES[@]}" -gt 0 ] || die "nenhum endereço candidato encontrado."

echo
echo "============================================================"
echo " Transferência de propriedade — Hyperlane Terra Classic"
echo "============================================================"
echo " Modo            : $( [ "$CLAIM_MODE" -eq 1 ] && echo 'CLAIM (rodar pela GOVERNANÇA)' || echo 'INIT TRANSFER (rodar por você)' )"
echo " Execução        : $( [ "$DRY_RUN" -eq 1 ] && echo "${c_ylw}DRY-RUN (não executa)${c_off}" || echo "${c_red}EXECUTAR DE VERDADE${c_off}" )"
echo " Governança (GOV): $GOVERNANCE_ADDRESS"
echo " Owner atual     : $CURRENT_OWNER"
echo " Incluir admin   : $( [ "$INCLUDE_ADMIN" -eq 1 ] && echo 'SIM' || echo 'não' )"
echo " Candidatos      : ${#CANDIDATES[@]} endereço(s)"
echo "============================================================"
echo

TXFLAGS=(--chain-id "$CHAIN_ID" --node "$NODE" --gas auto \
         --gas-adjustment "$GAS_ADJUST" --gas-prices "$GAS_PRICES" \
         --from "$SIGNER_KEY" -y -b sync -o json)

q_owner(){ # echo owner addr ou vazio se não for ownable
  "$BINARY" query wasm contract-state smart "$1" '{"ownable":{"get_owner":{}}}' \
     --node "$NODE" -o json 2>/dev/null \
   | python3 -c 'import sys,json;
try:
 print(json.load(sys.stdin)["data"]["owner"])
except Exception: pass' 2>/dev/null
}
q_admin(){ # echo admin addr atual do contrato
  "$BINARY" query wasm contract "$1" --node "$NODE" -o json 2>/dev/null \
   | python3 -c 'import sys,json;
try:
 print(json.load(sys.stdin)["contract_info"]["admin"])
except Exception: pass' 2>/dev/null
}

ELIGIBLE=(); SKIP=()
note "Consultando owner on-chain de cada candidato..."
echo
for addr in "${CANDIDATES[@]}"; do
  owner="$(q_owner "$addr")"
  if [ -z "$owner" ]; then
    SKIP+=("$addr  (não-ownable, ex.: validator_announce/merkle hook) — pulado")
    printf "  %s  %s\n" "${c_ylw}skip${c_off}" "$addr  (sem get_owner)"
    continue
  fi
  if [ "$owner" != "$CURRENT_OWNER" ]; then
    SKIP+=("$addr  (owner = $owner ≠ você) — pulado")
    printf "  %s  %s\n" "${c_ylw}skip${c_off}" "$addr  (owner já é $owner)"
    continue
  fi
  ELIGIBLE+=("$addr")
  printf "  %s  %s\n" "${c_grn}ok  ${c_off}" "$addr"
done

echo
echo "------------------------------------------------------------"
echo " Elegíveis (owner == você): ${#ELIGIBLE[@]}    |    Pulados: ${#SKIP[@]}"
echo "------------------------------------------------------------"
echo

[ "${#ELIGIBLE[@]}" -gt 0 ] || { note "Nada a fazer."; exit 0; }

run_or_show(){ # $1 = descrição, resto = comando
  local desc="$1"; shift
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "  # $desc"
    echo "  $*"
    echo
  else
    echo "  ▶ $desc"
    "$@"
    echo
    sleep 2   # respiro entre txs p/ sequência de nonce
  fi
}

if [ "$CLAIM_MODE" -eq 1 ]; then
  # ---- modo CLAIM: governança aceita a posse ------------------------------
  note "Comandos de CLAIM (executar com a key da GOVERNANÇA = $GOVERNANCE_ADDRESS):"
  echo
  for addr in "${ELIGIBLE[@]}"; do
    run_or_show "claim_ownership @ $addr" \
      "$BINARY" tx wasm execute "$addr" '{"ownable":{"claim_ownership":{}}}' "${TXFLAGS[@]}"
  done
else
  # ---- modo INIT TRANSFER: você propõe a transferência --------------------
  note "Passo 1 — init_ownership_transfer (executar com a SUA key = $CURRENT_OWNER):"
  echo
  for addr in "${ELIGIBLE[@]}"; do
    run_or_show "init_ownership_transfer -> $GOVERNANCE_ADDRESS @ $addr" \
      "$BINARY" tx wasm execute "$addr" \
      "{\"ownable\":{\"init_ownership_transfer\":{\"next_owner\":\"$GOVERNANCE_ADDRESS\"}}}" \
      "${TXFLAGS[@]}"
  done

  if [ "$INCLUDE_ADMIN" -eq 1 ]; then
    echo "------------------------------------------------------------"
    note "Admin de migração — set-contract-admin (UM passo, imediato):"
    echo "${c_ylw}  AVISO: ao mudar o admin você perde o poder de 'migrate' (upgrade) destes contratos.${c_off}"
    echo "${c_ylw}  Recomendado fazer SÓ depois que a governança já tiver dado o claim do owner.${c_off}"
    echo
    for addr in "${ELIGIBLE[@]}"; do
      cur_admin="$(q_admin "$addr")"
      if [ "$cur_admin" != "$CURRENT_OWNER" ]; then
        echo "  ${c_ylw}skip admin${c_off} $addr  (admin atual = ${cur_admin:-<nenhum/imutável>})"
        continue
      fi
      run_or_show "set-contract-admin -> $GOVERNANCE_ADDRESS @ $addr" \
        "$BINARY" tx wasm set-contract-admin "$addr" "$GOVERNANCE_ADDRESS" "${TXFLAGS[@]}"
    done
  fi

  echo "------------------------------------------------------------"
  note "LEMBRE: o owner só muda de fato quando a GOVERNANÇA rodar o claim:"
  echo "        ./transfer-ownership.sh --claim            (dry-run)"
  echo "        ./transfer-ownership.sh --claim --execute  (governança executa)"
  echo "  Para CANCELAR antes do claim:"
  echo "        $BINARY tx wasm execute <CONTRATO> '{\"ownable\":{\"revoke_ownership_transfer\":{}}}' --from <sua_key> ..."
fi

echo
note "Conferir resultado de qualquer contrato:"
echo "  $BINARY query wasm contract-state smart <CONTRATO> '{\"ownable\":{\"get_owner\":{}}}' --node $NODE"
echo "  $BINARY query wasm contract-state smart <CONTRATO> '{\"ownable\":{\"get_pending_owner\":{}}}' --node $NODE"
echo
[ "$DRY_RUN" -eq 1 ] && note "${c_grn}DRY-RUN: nada foi executado.${c_off} Revise acima e rode com --execute quando estiver pronto."
