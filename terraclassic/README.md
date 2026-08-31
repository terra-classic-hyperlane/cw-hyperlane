# Terra Classic — Hyperlane Warp Routes

Scripts, configs and documentation for the Hyperlane deployment on
**Terra Classic mainnet** (`columbus-5`, domain **132556**) and its warp routes
to **BSC**, **Ethereum** and **Solana**.

**Live routes:** [LUNC](doc/install/WARP-LUNC.md) and
[USTC](doc/install/WARP-USTC.md) — Terra Classic collateral ↔ synthetics on the
three chains, transfers verified in both directions (2026-08-29).

## Create a warp route

| Target | Script | Guide |
|---|---|---|
| BSC / Ethereum | [`create-warp-evm.sh`](create-warp-evm.sh) | [doc/install/WARP-EVM.md](doc/install/WARP-EVM.md) |
| Solana (sealevel) | [`create-warp-sealevel.sh`](create-warp-sealevel.sh) | [doc/install/WARP-SOLANA.md](doc/install/WARP-SOLANA.md) |
| Show it in the Warp UI | — | [doc/install/WARP-UI-PR.md](doc/install/WARP-UI-PR.md) |

Both scripts are interactive and idempotent: they deploy only the token's own
contracts and **wire the shared production ISM/IGP/hooks automatically** —
nothing security- or gas-related is created per token.

## What's in this folder

| Path | Purpose |
|---|---|
| `create-warp-evm.sh` / `create-warp-sealevel.sh` | The two warp-route creators |
| `jito-warp-init.js` | Atomic (MEV-safe) Solana token init — called by `create-warp-sealevel.sh` |
| `close-warp-program.sh` | Close a Solana warp program and reclaim its SOL (⚠️ permanent — the program id can never be reused) |
| `enroll-terra-router.sh` | Re-run the TC-side `set_route` for an EVM warp if it was skipped |
| `warp-evm-config.json` / `warp-sealevel-config.json` | Token + network configuration the scripts read and update (tokens: `lunc`, `ustc`, `juris`) |
| `TerraClassicOracle.sol` / `TerraClassicIGPStandalone-Sepolia.sol` | Solidity sources compiled on demand by `create-warp-evm.sh` |
| `CustomInstantiateWasm-mainnet-v2.ts` · `submit-proposal-mainnet.ts` · `update-igp-oracle.sh` | Core-deployment / governance / oracle tooling — usage in the deployment record below |
| [`warp/`](warp/) | Live per-token configs (LUNC/USTC registry YAMLs + per-chain files), Solana token metadata, and the shared verified binaries/keys |
| [`doc/`](doc/README.md) | Documentation: [`doc/install/`](doc/install/README.md) (create warps, audit references, [DEPLOY-HASHES](doc/install/DEPLOY-HASHES.md) inventory) and the core [deployment record](doc/HYPERLANE_DEPLOYMENT-MAINNET_EN.md) |
| `log/` · `context/` | Script run logs / deploy context |

## Documentation

- **Start here:** [`doc/README.md`](doc/README.md)
- **Create a warp:** [`doc/install/`](doc/install/README.md)
- **Audit the live routes:** [WARP-LUNC.md](doc/install/WARP-LUNC.md) · [WARP-USTC.md](doc/install/WARP-USTC.md) · [DEPLOY-HASHES.md](doc/install/DEPLOY-HASHES.md)
- **Core deployment record** (code_ids, hashes, governance, mailbox wiring): [`doc/HYPERLANE_DEPLOYMENT-MAINNET_EN.md`](doc/HYPERLANE_DEPLOYMENT-MAINNET_EN.md)

## 🗄️ Arquivo morto (archive)

Retired material is kept for reference and audit trail only — **do not use it
for new deploys**:

- [`archive/`](archive/README.md) — retired scripts (`archive/scripts/`) and
  legacy per-token warp configs (`archive/warp/`)
- [`doc/archive/`](doc/archive/README.md) — superseded guides, testnet records,
  funding proposals and one-off reports

## Related

- Warp UI registry fork: [`terra-classic-hyperlane/hyperlane-registry`](https://github.com/terra-classic-hyperlane/hyperlane-registry/tree/terra-classic-warp) (branch `terra-classic-warp`)
- Relayer payment system: [`terra-classic-hyperlane/proof-of-delivery`](https://github.com/terra-classic-hyperlane/proof-of-delivery)
- Official Hyperlane registry: `columbus-5` canonical since PR #1559 (2026-08-20)
