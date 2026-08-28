# Create a Warp Route — Solana (Sealevel) ↔ Terra Classic

> One script: `terraclassic/create-warp-sealevel.sh`. It deploys **only the token's
> own program**; ISM and IGP are the production ones, SET on the new warp — nothing
> else is created. Full reference: [`../create-warp-sealevel-guide.md`](../create-warp-sealevel-guide.md).

## 1. What gets deployed vs reused (mainnet, verified on-chain 2026-08-28)

| Piece | New token on Solana |
|---|---|
| Warp token program + SPL mint | 🆕 deployed (`hyperlane-sealevel-token` + metadata) |
| Collateral warp on Terra Classic | 🆕 deployed |
| ISM | ♻️ reused: `4MzF7HCfxuwj4EFHqZSEpvkcZZvv1mF37DP4pDHwR5VQ` (mutable MultisigISM, same 3-of-4 validator set as BSC/ETH) |
| IGP | ♻️ reused: program `FLZuKRsfdovLqd8n1AYhPCwLqBjfFyZY3A2edgnjdJoR` + **OverheadIgp** `FXacR73HiuNyvW7x34KYCDyv8XxM86pz31Ap8t2v3RCJ` — fees → pod pool PDA (relayer-reward-vault), prices governed |
| Destination gas (TC) | `3000000` (matches the live IGORFAKE warp) |

⚠️ The IGP account type is **`overhead-igp`** (from `warp-sealevel-config.json`) —
setting it as plain `igp` would quote gas without overhead and underpay the relayer.
The script reads it from the config since 2026-08-28.

There is **no AggregationHook on Solana** — the sealevel architecture handles the
merkle insertion in the mailbox itself.

## 2. Prerequisites

- Solana CLI + a funded keypair (the warp program deploy costs ~1.4 SOL of rent,
  recoverable on close), Rust toolchain for `hyperlane-sealevel-client`
  (built once from `~/hyperlane-monorepo/rust/sealevel`; the script reuses the binary).
- `TERRA_PRIVATE_KEY` for the Terra Classic side.
- A reliable mainnet RPC (config supports fallbacks).

## 3. Add your token to the config

Edit `terraclassic/warp-sealevel-config.json` → `networks.solanamainnet.warp_tokens`:

```jsonc
"mytoken": {
  "deployed": false,
  "type": "synthetic",
  "program_id": "",              // filled by the script after deploy
  "mint_address": "",
  "metadata_uri": "https://raw.githubusercontent.com/terra-classic-hyperlane/cw-hyperlane/refs/heads/main/warp/solana/metadata-mytoken.json",
  "decimals": 6,
  "owner": "<your solana pubkey>"
}
```

Commit the token's `metadata-mytoken.json` (name/symbol/image) to the repo first —
the URI must resolve at deploy time. Do **not** touch `ism`/`igp` — production defaults.

## 4. Run — example (mainnet)

```bash
cd ~/tc-cw-hyperlane/terraclassic
export TERRA_PRIVATE_KEY="hex_no_0x"
./create-warp-sealevel.sh          # interactive: pick token + solanamainnet
```

Expected flow:
`STEP 1` `warp-route deploy` (the only thing created: program + mint; the deploy
config already carries `interchainGasPaymaster` = the production overhead IGP) →
`STEP 2` `token set-interchain-security-module --ism 4MzF7HCf…` →
`STEP 3` `token igp set FLZuKRs… overhead-igp FXacR73…` →
`STEP 4` `destination gas 132556 = 3000000` →
`STEP 5` enroll remote router (Solana → TC) + `set_route` (TC → Solana).

Verify the result exactly like the audit does:

```bash
~/hyperlane-monorepo/rust/sealevel/target/release/hyperlane-sealevel-client \
  -u https://api.mainnet-beta.solana.com token query --program-id <WARP_PROGRAM_ID> synthetic
# interchain_security_module = 4MzF7HCf… · interchain_gas_paymaster = (FLZuKRs…, OverheadIgp(FXacR73…))
# destination_gas = {132556: 3000000} · remote_routers = {132556: <TC warp hexed>}
```

## 5. Post-deploy checklist (production tokens)

Same as EVM: registry PR · warp UI route · `originSenders` in the oracle-agent
config (tc-proof-of-delivery) · append the new addresses + hashes to
[DEPLOY-HASHES.md](DEPLOY-HASHES.md).
