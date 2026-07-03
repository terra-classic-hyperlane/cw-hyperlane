#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
#  🧪  TESTNET launcher → create-warp-ism-solana.sh
#  Deploys the community multisig ISM on Solana testnet, configured for the
#  Terra Classic TESTNET domain (rebel-2 = 1325). Build local + publish hash.
#
#  ISM_VALIDATORS defaults to the Terra Classic rebel-2 validator. Override only
#  if the validator set changes:
#    ISM_VALIDATORS=0x<v1>,0x<v2> ISM_THRESHOLD=2 ./create-warp-ism-solana-testnet.sh
# ═══════════════════════════════════════════════════════════════════════════════
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export NET_KEY="${NET_KEY:-solanatestnet}"
export TERRA_DOMAIN="${TERRA_DOMAIN:-1325}"                                    # Terra Classic testnet (rebel-2)
export ISM_VALIDATORS="${ISM_VALIDATORS:-0x133fd7f7094dbd17b576907d052a5acbd48db526}"  # rebel-2 validator
export ISM_THRESHOLD="${ISM_THRESHOLD:-1}"

echo "🧪 TESTNET → create-warp-ism-solana.sh"
echo "   Terra domain: ${TERRA_DOMAIN} (rebel-2) | validators: ${ISM_VALIDATORS} (threshold ${ISM_THRESHOLD})"
exec "$DIR/create-warp-ism-solana.sh" "$@"
