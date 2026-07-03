#!/usr/bin/env bash
#
# transfer-warp-solana.sh — Transfere a posse dos WARP ROUTES SINTÉTICOS na
# Solana para um multisig Squads.
#
# Os warps sintéticos na Solana são programas hyperlane-sealevel-token. A
# transferência usa o client oficial:
#
#     hyperlane-sealevel-client token transfer-ownership \
#         --program-id <PROGRAM_ID> <NEW_OWNER>     ← UM PASSO, IMEDIATO (sem claim!)
#
# O <NEW_OWNER> deve ser o endereço da VAULT do Squads (a PDA que atua como
# autoridade do multisig) — NÃO o endereço da conta de configuração do multisig.
#
# >>> ATENÇÃO: como na EVM, na Solana NÃO há passo de "claim". Assim que a tx   <<<
# >>> confirma, o Squads vira owner e VOCÊ perde o controle. Confira a vault.    <<<
#
# >>> SEGURO POR PADRÃO: roda em --dry-run (NÃO executa). Use --execute p/ valer. <<<
#
# Requer: binário hyperlane-sealevel-client (compilado de rust/sealevel/client).
#
# Uso:
#   ./transfer-warp-solana.sh                 # dry-run
#   ./transfer-warp-solana.sh --execute       # executa de verdade
#
set -euo pipefail

# ============================================================================
# >>>>>>>>>>>>>>>>>>>>>>  CONFIGURE AQUI  <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
# ============================================================================

# Endereço da VAULT do Squads que receberá a posse (base58). OBRIGATÓRIO.
SQUADS_VAULT=""

# Caminho do binário do client (ajuste se necessário)
CLIENT="$HOME/hyperlane-monorepo/rust/sealevel/target/release/hyperlane-sealevel-client"

# Keypair do OWNER ATUAL (deployer) que assina as transações. OBRIGATÓRIO.
OWNER_KEYPAIR="$HOME/.config/solana/id.json"

# RPC da Solana mainnet
RPC_URL="https://api.mainnet-beta.solana.com"

# Tipo do token sintético (synthetic / collateral / native)
TOKEN_TYPE="synthetic"

# Program IDs dos warps sintéticos (LUNC, USTC, ...) na Solana
TOKEN_PROGRAM_IDS=(
  # "ProgramIdDoLUNC..."
  # "ProgramIdDoUSTC..."
)

# ============================================================================
# >>>>>>>>>>>>>>>>>>>>>>  NÃO PRECISA EDITAR ABAIXO  <<<<<<<<<<<<<<<<<<<<<<<<<<<
# ============================================================================

DRY_RUN=1
for arg in "$@"; do
  case "$arg" in
    --execute) DRY_RUN=0 ;;
    --dry-run) DRY_RUN=1 ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Argumento desconhecido: $arg"; exit 1 ;;
  esac
done

c_red=$'\e[31m'; c_grn=$'\e[32m'; c_ylw=$'\e[33m'; c_cyn=$'\e[36m'; c_off=$'\e[0m'
die(){ echo "${c_red}ERRO:${c_off} $*" >&2; exit 1; }
note(){ echo "${c_cyn}»${c_off} $*"; }

[ -x "$CLIENT" ] || die "client não encontrado/executável: $CLIENT
  Compile com: (cd ~/hyperlane-monorepo/rust/sealevel/client && cargo build --release)"
[ -f "$OWNER_KEYPAIR" ] || die "keypair do owner não encontrado: $OWNER_KEYPAIR"
[[ -n "$SQUADS_VAULT" ]] || die "configure SQUADS_VAULT (endereço base58 da vault)."
[ "${#TOKEN_PROGRAM_IDS[@]}" -gt 0 ] || die "configure TOKEN_PROGRAM_IDS."

echo
echo "============================================================"
echo " Transferência de WARP SINTÉTICO (Solana) -> Squads"
echo "============================================================"
echo " Execução       : $( [ "$DRY_RUN" -eq 1 ] && echo "${c_ylw}DRY-RUN (não executa)${c_off}" || echo "${c_red}EXECUTAR DE VERDADE${c_off}" )"
echo " Squads vault   : $SQUADS_VAULT"
echo " Owner keypair  : $OWNER_KEYPAIR"
echo " RPC            : $RPC_URL"
echo " Tokens         : ${#TOKEN_PROGRAM_IDS[@]}"
echo "============================================================"
echo "${c_ylw} LEMBRE: transfer-ownership na Solana é IMEDIATO e sem claim.${c_off}"
echo

run_or_show(){ local desc="$1"; shift
  if [ "$DRY_RUN" -eq 1 ]; then echo "  # $desc"; echo "  $*"; echo
  else echo "  ▶ $desc"; "$@"; echo; sleep 2; fi
}

for pid in "${TOKEN_PROGRAM_IDS[@]}"; do
  [[ -n "$pid" ]] || continue
  echo "------------------------------------------------------------"
  note "Token program: $pid"

  # Mostra o estado atual (inclui o owner) — só leitura
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "  # consultar estado atual (owner):"
    echo "  $CLIENT --url $RPC_URL token query --program-id $pid $TOKEN_TYPE"
    echo
  else
    "$CLIENT" --url "$RPC_URL" token query --program-id "$pid" "$TOKEN_TYPE" || true
  fi

  run_or_show "transfer-ownership -> $SQUADS_VAULT @ $pid" \
    "$CLIENT" --url "$RPC_URL" --keypair "$OWNER_KEYPAIR" \
    token transfer-ownership --program-id "$pid" "$SQUADS_VAULT"
done

echo "------------------------------------------------------------"
note "Conferir owner depois (deve ser a vault do Squads):"
echo "  $CLIENT --url $RPC_URL token query --program-id <PROGRAM_ID> $TOKEN_TYPE"
echo
[ "$DRY_RUN" -eq 1 ] && note "${c_grn}DRY-RUN: nada foi executado.${c_off} Revise e rode com --execute quando estiver pronto."
