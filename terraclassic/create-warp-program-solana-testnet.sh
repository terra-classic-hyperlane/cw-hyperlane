#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
#  🧪  TESTNET launcher → create-warp-program-solana.sh
#  Deploys the warp token PROGRAM on Solana testnet (build local + publish hash).
#  Same logic as mainnet; only the network is preset to solanatestnet.
# ═══════════════════════════════════════════════════════════════════════════════
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export NET_KEY="${NET_KEY:-solanatestnet}"

echo "🧪 TESTNET → create-warp-program-solana.sh (NET_KEY=${NET_KEY})"
exec "$DIR/create-warp-program-solana.sh" "$@"
