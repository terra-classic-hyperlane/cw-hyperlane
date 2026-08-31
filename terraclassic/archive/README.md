# 🗄️ Archive (arquivo morto) — scripts & warp configs

Retired scripts and per-token config files, kept **for historical reference and
audit trail only**. Nothing here is part of the current workflow.

> **The live workflow** uses only what remains at `terraclassic/`:
> `create-warp-evm.sh` / `create-warp-sealevel.sh` (+ `jito-warp-init.js`,
> `close-warp-program.sh`, `enroll-terra-router.sh`, the two `.sol` sources and
> the two config JSONs), plus the core-deployment trio referenced by
> [`doc/HYPERLANE_DEPLOYMENT-MAINNET_EN.md`](../doc/HYPERLANE_DEPLOYMENT-MAINNET_EN.md)
> (`CustomInstantiateWasm-mainnet-v2.ts`, `submit-proposal-mainnet.ts`,
> `update-igp-oracle.sh`). Docs: [`doc/install/`](../doc/install/) ·
> archived docs: [`doc/archive/`](../doc/archive/).

## `scripts/`

| File(s) | What it was |
|---|---|
| `create-warp-ism-solana*.sh` / `create-warp-igp-solana*.sh` | One-time deploy of the community ISM/IGP on Solana (mainnet + testnet) — infra is live, never redeploy |
| `create-warp-program-solana*.sh` / `deploy-warp-solana-buffer*.sh` | Older Solana warp deploy flows — superseded by `create-warp-sealevel.sh` |
| `setup-ism-igp-terraclassic.sh` | One-time TC-side ISM/IGP wiring |
| `transfer-remote-terra.sh` / `transfer-remote-to-terra.sh` / `transfer-cw20-terra.sh` | Manual test-transfer helpers (the Warp UI / registry routes cover this now) |
| `transfer-ownership-to-governance.sh` / `transfer-solana-ownership.sh` | Ownership handoff procedures (run when the multisig migration happens) |
| `update-warp-solana.sh` | Older Solana warp update helper |
| `check-contract-config.sh` | Ad-hoc config checker (superseded by the verify commands in `doc/install/`) |
| `create-warp-igorfake-link.sh` | Linked the discontinued IGORFAKE test route (route retired 2026-08-29) |
| `CustomInstantiateWasm-mainnet.ts` | Original core deploy (2026-06-03, domain 1325) — superseded by `CustomInstantiateWasm-mainnet-v2.ts` (domain 132556) |
| `submit-proposal-testnet.ts` | Testnet governance proposal submitter |
| `create-warp-sealevel copy.sh` / `warp-evm-config.json.bak-*` | Stray working copies |

## `warp/`

Per-token config files for **discontinued test tokens** (IGORFAKE, XPTO, XPTV,
XPV, FAKEFAKE, ZTT — retired 2026-08-29), testnet-era files (sepolia/juris),
the old-generation `terraclassic-native.json` (wwwwlunc) and a stale
`warpRouteConfigs.yaml` copy.

The **live** files stay in [`../warp/`](../warp/): the LUNC/USTC registry YAMLs
+ per-chain configs, the Solana token metadata, and the shared infra
(`reference-program/`, `solanamainnet/`, `solanatestnet/`).
