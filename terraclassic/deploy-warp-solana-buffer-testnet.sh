#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
#  🧪  TESTNET launcher → deploy-warp-solana-buffer.sh
#  Warp init on Solana testnet against Terra Classic TESTNET (rebel-2, domain 1325).
#
#  Reads Terra Classic data from the .terra_classic_testnet block (rebel-2).
#  Per-token warp routes on rebel-2 are NOT yet deployed (deployed=false in the
#  block), so the buffer script auto-skips enroll-remote-router / set_route for
#  those tokens and runs only the Solana side (build, deploy, init, ISM, IGP,
#  dest-gas). Once you deploy a token's warp on rebel-2 and fill its
#  warp_address/warp_hexed + deployed=true in warp-evm-config.json
#  (.terra_classic_testnet.tokens.<key>), enroll/set_route run automatically.
#
#  To run a specific token non-interactively: TOKEN_KEY=<key> ./deploy-warp-solana-buffer-testnet.sh
# ═══════════════════════════════════════════════════════════════════════════════
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export NET_KEY="${NET_KEY:-solanatestnet}"
export TERRA_CFG="${TERRA_CFG:-.terra_classic_testnet}"         # rebel-2 block in warp-evm-config.json
# Domain/rpc/chain-id come from the block above; override here only if needed.
export TERRA_DOMAIN="${TERRA_DOMAIN:-1325}"                     # Terra Classic testnet (rebel-2)
export TERRA_RPC="${TERRA_RPC:-https://rpc.luncblaze.com}"
export TERRA_CHAIN_ID="${TERRA_CHAIN_ID:-rebel-2}"

echo "🧪 TESTNET → deploy-warp-solana-buffer.sh"
echo "   Solana: ${NET_KEY} | Terra: ${TERRA_CFG} domain ${TERRA_DOMAIN} (${TERRA_CHAIN_ID}) rpc ${TERRA_RPC}"
echo "   ℹ️  enroll/set_route run per-token based on deployed=true in .terra_classic_testnet.tokens."
exec "$DIR/deploy-warp-solana-buffer.sh" "$@"
