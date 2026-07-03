#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
#  🧪  TESTNET launcher → create-warp-igp-solana.sh
#  Deploys the community IGP + gas oracle on Solana testnet, configured for the
#  Terra Classic TESTNET domain (rebel-2 = 1325). Build local + publish hash.
#
#  Oracle params default to the LUNC values (28.325 uluna gas, 6 decimals); tune
#  for testnet if needed via ORACLE_* / GAS_OVERHEAD env vars.
# ═══════════════════════════════════════════════════════════════════════════════
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export NET_KEY="${NET_KEY:-solanatestnet}"
export TERRA_DOMAIN="${TERRA_DOMAIN:-1325}"                    # Terra Classic testnet (rebel-2)
export ORACLE_EXCHANGE_RATE="${ORACLE_EXCHANGE_RATE:-1000000000000}"
export ORACLE_GAS_PRICE="${ORACLE_GAS_PRICE:-28325}"
export ORACLE_TOKEN_DECIMALS="${ORACLE_TOKEN_DECIMALS:-6}"
export GAS_OVERHEAD="${GAS_OVERHEAD:-3000000}"

echo "🧪 TESTNET → create-warp-igp-solana.sh"
echo "   Terra domain: ${TERRA_DOMAIN} (rebel-2) | oracle rate=${ORACLE_EXCHANGE_RATE} gas=${ORACLE_GAS_PRICE} dec=${ORACLE_TOKEN_DECIMALS} overhead=${GAS_OVERHEAD}"
exec "$DIR/create-warp-igp-solana.sh" "$@"
