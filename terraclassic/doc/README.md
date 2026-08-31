# Documentation — Hyperlane Warp Routes on Terra Classic

> Only two things live here. Everything else was retired to the
> [archive](archive/) to keep the entry path unambiguous.

## 📌 The documents that matter

### 1. Create a warp route → [`install/`](install/)

Start at [`install/README.md`](install/README.md). Four documents cover the whole
lifecycle:

| Document | What it covers |
|---|---|
| [`install/WARP-EVM.md`](install/WARP-EVM.md) | Create a warp on **BSC** or **Ethereum** with one script (`create-warp-evm.sh`) |
| [`install/WARP-SOLANA.md`](install/WARP-SOLANA.md) | Create a warp on **Solana** (sealevel) with one script (`create-warp-sealevel.sh`) |
| [`install/WARP-UI-PR.md`](install/WARP-UI-PR.md) | Make a deployed route appear in the **Warp UI** (registry fork, branch `terra-classic-warp`) |
| [`install/DEPLOY-HASHES.md`](install/DEPLOY-HASHES.md) | **Live inventory** of every deployed contract with verifiable hashes — TC core, and the LUNC/USTC warp + ISM/IGP/hooks on BSC · ETH · Solana |
| [`install/WARP-LUNC.md`](install/WARP-LUNC.md) | The live **LUNC** route per chain (TC · BSC · ETH · Solana): contracts, hashes, owners, routes + query/audit commands |
| [`install/WARP-USTC.md`](install/WARP-USTC.md) | The live **USTC** route — same per-chain audit & developer reference |

### 2. Core deployment record → [`HYPERLANE_DEPLOYMENT-MAINNET_EN.md`](HYPERLANE_DEPLOYMENT-MAINNET_EN.md)

The complete record of the Hyperlane **core** deployment on columbus-5 (domain
132556): contract uploads with code_ids and `data_hash`, instantiation,
governance configuration, mailbox wiring, ISM validator sets, and the IGP
oracle — with the commands to re-verify each item on-chain.

## 🗄️ Archive (arquivo morto)

Historical guides, superseded deep-dives, testnet records, funding proposals and
one-off reports were moved to [`archive/`](archive/). They are kept for
reference and audit trail only — **do not follow them for new deploys**; the
current path is always `install/` + `DEPLOY-HASHES.md`.

## Related

- Scripts: [`../create-warp-evm.sh`](../create-warp-evm.sh) · [`../create-warp-sealevel.sh`](../create-warp-sealevel.sh)
  (configs: `../warp-evm-config.json` · `../warp-sealevel-config.json`)
- Relayer payment system (vaults, oracle-agent, operator setup):
  [`tc-proof-of-delivery/docs/install/`](https://github.com/terra-classic-hyperlane/proof-of-delivery/tree/main/docs/install)
- Official Hyperlane registry: `columbus-5` is canonical since PR #1559 (2026-08-20)
