# Start here — Warp Routes on Terra Classic Hyperlane

> Entry-point documentation for creating and auditing **Hyperlane Warp Routes**
> connected to Terra Classic (columbus-5, domain **132556**). Everything below is
> current production state, verified on-chain **2026-08-28**.

## The 4 documents

| Document | What it covers |
|---|---|
| **[WARP-EVM.md](WARP-EVM.md)** | Create a warp on **BSC** or **Ethereum** with one script (`create-warp-evm.sh`) — examples for both chains |
| **[WARP-SOLANA.md](WARP-SOLANA.md)** | Create a warp on **Solana** (sealevel) with one script (`create-warp-sealevel.sh`) — full example |
| **[WARP-UI-PR.md](WARP-UI-PR.md)** | Make a deployed route **appear in the Warp UI** — fork & PR to the registry branch the UI reads (`terra-classic-warp`) |
| **[DEPLOY-HASHES.md](DEPLOY-HASHES.md)** | Complete deployed-contract inventory with **hashes**: Terra Classic core (code_ids + data_hash), and the synthetics' warp/ISM/IGP/hooks on BSC · ETH · Solana — with the commands to verify each one |

## The one principle to understand first

**Creating a new token creates ONLY the token's own contracts** (the synthetic on
the EVM/Solana side + the collateral warp on Terra Classic). Everything else —
security and economics — is **shared production infrastructure that the scripts
wire automatically**:

- **ISM (security):** the shared mutable **3-of-4 multisig** (same 4 validators on
  every chain). Validator rotation is one owner tx for ALL warps at once.
- **IGP (gas/fees):** the production gas paymaster — user fees fund the
  **relayer-reward-vault pool**, and gas prices are governed live by the
  oracle-agent/governor (no manual prices, ever).
- **Hooks (EVM):** the production AggregationHook [merkleTree + governed IGP].

Nothing to configure, nothing to price, nothing to secure by hand — and no orphan
ISM/IGP contracts left behind.

## Related

- Install scripts: `../../create-warp-evm.sh` · `../../create-warp-sealevel.sh`
  (configs: `../../warp-evm-config.json` · `../../warp-sealevel-config.json`)
- Deep-dive guides (every field, every step): `../create-warp-evm-guide.md` ·
  `../create-warp-sealevel-guide.md` · `../WARP-GAS-CONFIG.md`
- Relayer payment system (vaults, oracle-agent, operator setup):
  [`tc-proof-of-delivery/docs/install/`](https://github.com/terra-classic-hyperlane/proof-of-delivery/tree/main/docs/install)
  — its `AUDIT.md` covers the vault/governor contracts and their hashes
- Official Hyperlane registry: `columbus-5` is canonical since PR #1559 (2026-08-20)
