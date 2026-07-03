#!/usr/bin/env bash
#
# transfer-warp-evm.sh — Transfere a posse dos WARP ROUTES SINTÉTICOS na EVM
# (Ethereum e BSC) para um multisig SAFE (Gnosis Safe).
#
# Os warps sintéticos de LUNC/USTC na EVM são contratos HypERC20 que herdam
# OpenZeppelin OwnableUpgradeable. A transferência é por:
#
#     transferOwnership(address newOwner)   ← UM PASSO, IMEDIATO (sem claim!)
#
# >>> ATENÇÃO: diferente do Terra Classic, na EVM NÃO há passo de "claim".     <<<
# >>> Assim que a tx confirmar, o SAFE vira owner e VOCÊ perde o controle.      <<<
# >>> Confira o endereço do SAFE três vezes. Não há volta sem o SAFE.           <<<
#
# >>> SEGURO POR PADRÃO: roda em --dry-run (NÃO executa). Use --execute p/ valer. <<<
#
# Requer: foundry (cast).  https://book.getfoundry.sh
#
# Uso:
#   ./transfer-warp-evm.sh --network ethereum
#   ./transfer-warp-evm.sh --network bsc
#   ./transfer-warp-evm.sh --network ethereum --include-proxyadmin
#   ./transfer-warp-evm.sh --network bsc --execute
#
set -euo pipefail

# ============================================================================
# >>>>>>>>>>>>>>>>>>>>>>  CONFIGURE AQUI  <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
# ============================================================================

# Seu endereço atual de owner (deployer). Filtro de segurança: só transfere
# contratos cujo owner() == este endereço. OBRIGATÓRIO.
DEPLOYER_ADDRESS=""

# Como o cast assina as transações (só usado em --execute). Exemplos:
#   CAST_AUTH=(--account meu-deployer)        # keystore do foundry (recomendado)
#   CAST_AUTH=(--ledger)                       # hardware wallet
#   CAST_AUTH=(--private-key "$PRIVATE_KEY")   # variável de ambiente (evite hardcode)
CAST_AUTH=(--account meu-deployer)

# ---------- Ethereum (mainnet) ----------
ETH_RPC_URL="https://eth.llamarpc.com"
ETH_SAFE_ADDRESS=""                 # endereço do SAFE multisig dos validadores na ETH
ETH_TOKENS=(                        # endereços dos warps sintéticos (HypERC20) na ETH
  # "0xLUNC_synthetic..."
  # "0xUSTC_synthetic..."
)

# ---------- BSC (mainnet) ----------
BSC_RPC_URL="https://bsc-dataseed.binance.org"
BSC_SAFE_ADDRESS=""                 # endereço do SAFE multisig dos validadores na BSC
BSC_TOKENS=(                        # endereços dos warps sintéticos (HypERC20) na BSC
  # "0xLUNC_synthetic..."
  # "0xUSTC_synthetic..."
)

# ============================================================================
# >>>>>>>>>>>>>>>>>>>>>>  NÃO PRECISA EDITAR ABAIXO  <<<<<<<<<<<<<<<<<<<<<<<<<<<
# ============================================================================

DRY_RUN=1; NETWORK=""; INCLUDE_PROXYADMIN=0
# EIP-1967 admin slot (proxy -> ProxyAdmin)
ADMIN_SLOT="0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103"

while [ $# -gt 0 ]; do
  case "$1" in
    --network) NETWORK="${2:-}"; shift 2 ;;
    --execute) DRY_RUN=0; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --include-proxyadmin) INCLUDE_PROXYADMIN=1; shift ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Argumento desconhecido: $1"; exit 1 ;;
  esac
done

c_red=$'\e[31m'; c_grn=$'\e[32m'; c_ylw=$'\e[33m'; c_cyn=$'\e[36m'; c_off=$'\e[0m'
die(){ echo "${c_red}ERRO:${c_off} $*" >&2; exit 1; }
note(){ echo "${c_cyn}»${c_off} $*"; }
lc(){ printf '%s' "$1" | tr 'A-Z' 'a-z'; }

command -v cast >/dev/null 2>&1 || die "foundry 'cast' não encontrado. Instale: https://book.getfoundry.sh"
[[ "$DEPLOYER_ADDRESS" == 0x* ]] || die "configure DEPLOYER_ADDRESS (0x...)."

case "$NETWORK" in
  ethereum) RPC="$ETH_RPC_URL"; SAFE="$ETH_SAFE_ADDRESS"; TOKENS=("${ETH_TOKENS[@]}") ;;
  bsc)      RPC="$BSC_RPC_URL"; SAFE="$BSC_SAFE_ADDRESS"; TOKENS=("${BSC_TOKENS[@]}") ;;
  *) die "use --network ethereum  ou  --network bsc" ;;
esac

[[ "$SAFE" == 0x* ]] || die "configure o SAFE da rede '$NETWORK' (endereço 0x...)."
[ "${#TOKENS[@]}" -gt 0 ] || die "nenhum token sintético configurado para '$NETWORK'."

echo
echo "============================================================"
echo " Transferência de WARP SINTÉTICO (EVM) -> SAFE"
echo "============================================================"
echo " Rede           : $NETWORK"
echo " Execução       : $( [ "$DRY_RUN" -eq 1 ] && echo "${c_ylw}DRY-RUN (não executa)${c_off}" || echo "${c_red}EXECUTAR DE VERDADE${c_off}" )"
echo " SAFE (destino) : $SAFE"
echo " Owner atual    : $DEPLOYER_ADDRESS"
echo " Incluir ProxyAdmin (upgrade) : $( [ "$INCLUDE_PROXYADMIN" -eq 1 ] && echo SIM || echo não )"
echo " Tokens         : ${#TOKENS[@]}"
echo "============================================================"
echo "${c_ylw} LEMBRE: transferOwnership na EVM é IMEDIATO e sem claim.${c_off}"
echo

run_or_show(){ local desc="$1"; shift
  if [ "$DRY_RUN" -eq 1 ]; then echo "  # $desc"; echo "  $*"; echo
  else echo "  ▶ $desc"; "$@"; echo; sleep 2; fi
}

declare -A PROXYADMINS=()

for tok in "${TOKENS[@]}"; do
  [[ "$tok" == 0x* ]] || continue
  owner="$(cast call "$tok" "owner()(address)" --rpc-url "$RPC" 2>/dev/null || true)"
  if [ -z "$owner" ]; then
    echo "  ${c_ylw}skip${c_off} $tok  (não respondeu owner() — endereço errado?)"; continue
  fi
  if [ "$(lc "$owner")" != "$(lc "$DEPLOYER_ADDRESS")" ]; then
    echo "  ${c_ylw}skip${c_off} $tok  (owner já é $owner)"; continue
  fi
  echo "  ${c_grn}ok  ${c_off} $tok"
  run_or_show "transferOwnership($SAFE) @ $tok" \
    cast send "$tok" "transferOwnership(address)" "$SAFE" --rpc-url "$RPC" "${CAST_AUTH[@]}"

  if [ "$INCLUDE_PROXYADMIN" -eq 1 ]; then
    raw="$(cast storage "$tok" "$ADMIN_SLOT" --rpc-url "$RPC" 2>/dev/null || true)"
    if [ -n "$raw" ] && [ "$raw" != "0x0000000000000000000000000000000000000000000000000000000000000000" ]; then
      pa="0x${raw: -40}"
      PROXYADMINS["$(lc "$pa")"]="$pa"
    fi
  fi
done

if [ "$INCLUDE_PROXYADMIN" -eq 1 ]; then
  echo "------------------------------------------------------------"
  note "ProxyAdmin (autoridade de UPGRADE dos proxies):"
  echo "${c_ylw}  AVISO: transferir o ProxyAdmin afeta TODOS os proxies sob ele.${c_off}"
  echo "${c_ylw}  Faça SÓ depois de confirmar que o SAFE já é o owner dos tokens.${c_off}"
  echo
  if [ "${#PROXYADMINS[@]}" -eq 0 ]; then
    note "Nenhum ProxyAdmin detectado (tokens podem não ser proxies)."
  fi
  for pa in "${PROXYADMINS[@]}"; do
    paowner="$(cast call "$pa" "owner()(address)" --rpc-url "$RPC" 2>/dev/null || true)"
    if [ "$(lc "$paowner")" != "$(lc "$DEPLOYER_ADDRESS")" ]; then
      echo "  ${c_ylw}skip ProxyAdmin${c_off} $pa  (owner = ${paowner:-?})"; continue
    fi
    run_or_show "transferOwnership($SAFE) @ ProxyAdmin $pa" \
      cast send "$pa" "transferOwnership(address)" "$SAFE" --rpc-url "$RPC" "${CAST_AUTH[@]}"
  done
fi

echo "------------------------------------------------------------"
note "Conferir owner de um token:"
echo "  cast call <token> \"owner()(address)\" --rpc-url $RPC"
echo
[ "$DRY_RUN" -eq 1 ] && note "${c_grn}DRY-RUN: nada foi executado.${c_off} Revise e rode com --execute quando estiver pronto."
