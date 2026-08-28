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

**The token is defined ONCE, in `warp-evm-config.json` → `terra_classic.tokens`**
(the same §3.1 of [WARP-EVM.md](WARP-EVM.md)) — the sealevel script reads its menu
from there too. If you already added the token for BSC/ETH, there is nothing new
to define.

The only Solana-specific piece **you** provide is the metadata file: commit
`warp/solana/metadata-mytoken.json` (name/symbol/description/image) to the repo —
the URI must resolve (HTTP 200) at deploy time, or the deploy runs without
on-chain metadata.

Everything in `warp-sealevel-config.json` → `networks.<net>.warp_tokens.mytoken`
is **deployment state, created and filled BY THE SCRIPT** (like WARP-EVM §3.2 —
do not write it):

| Field | What it records | Filled by |
|---|---|---|
| `program_id` | the warp token program deployed on Solana | script, after `warp-route deploy` |
| `mint_address` | the SPL mint created by the warp | script, after deploy |
| `metadata_uri` | the resolved metadata URI actually used | script |
| `deployed` | whether this token exists on this Solana network | script |

Do **not** touch `ism`/`igp` in the config — production defaults (§1).

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

## 5. Manual deployment — step by step (what the script automates)

Every command the script runs, for hand execution, resuming a failed step, or
auditing. `CLIENT` = `~/hyperlane-monorepo/rust/sealevel/target/release/hyperlane-sealevel-client`,
`KEY` = your funded keypair json, `RPC` = a mainnet RPC.

### 5.1 Deploy the warp token program (the only thing created)

```bash
# token-config.json — what the script generates for the deploy:
{ "solanamainnet": { "type": "synthetic", "name": "My Token", "symbol": "MTK",
    "decimals": 6, "totalSupply": "0",
    "interchainGasPaymaster": "FXacR73HiuNyvW7x34KYCDyv8XxM86pz31Ap8t2v3RCJ",
    "uri": "https://raw.githubusercontent.com/terra-classic-hyperlane/cw-hyperlane/refs/heads/main/warp/solana/metadata-mytoken.json" } }

$CLIENT -k $KEY -u $RPC warp-route deploy \
  --warp-route-name mytoken \
  --environment mainnet3 \
  --environments-dir <sealevel>/environments \
  --token-config-file token-config.json \
  --built-so-dir <sealevel>/target/deploy \
  --registry <registry-dir> \
  --ata-payer-funding-amount 5000000
# → note the WARP program id (costs ~1.4 SOL of recoverable rent)
```

### 5.2 Set the production ISM (3-of-4)

```bash
$CLIENT -k $KEY -u $RPC token set-interchain-security-module \
  --program-id <WARP> --ism 4MzF7HCfxuwj4EFHqZSEpvkcZZvv1mF37DP4pDHwR5VQ
```

### 5.3 Set the production IGP — type MUST be overhead-igp

```bash
$CLIENT -k $KEY -u $RPC token igp --program-id <WARP> set \
  FLZuKRsfdovLqd8n1AYhPCwLqBjfFyZY3A2edgnjdJoR overhead-igp \
  FXacR73HiuNyvW7x34KYCDyv8XxM86pz31Ap8t2v3RCJ
```

### 5.4 Set destination gas for Terra Classic

```bash
$CLIENT -k $KEY -u $RPC token set-destination-gas --program-id <WARP> 132556 3000000
```

### 5.5 Enroll the TC route on the Solana warp

`0x<TC_WARP_HEX>` = the TC collateral warp's 32-byte hex (from
`context/terraclassic.json`, see WARP-EVM §5.1):

```bash
$CLIENT -k $KEY -u $RPC token enroll-remote-router --program-id <WARP> 132556 0x<TC_WARP_HEX>
```

### 5.6 Enroll the Solana route on the TC warp (set_route)

`route` = the warp **program id decoded from base58 to 32-byte hex** (the script
stores it as `program_hex`; e.g. IGORFAKE = `c6de5b1f…437f95`):

```bash
python3 -c "import base58,sys; print(base58.b58decode('<WARP_PROGRAM_ID>').hex())"
terrad tx wasm execute <TC_WARP_ADDRESS> \
  '{"router":{"set_route":{"set":{"domain":1399811149,"route":"<PROGRAM_ID_HEX_64>"}}}}' \
  --from <tc-key> --keyring-backend file --gas auto --gas-adjustment 1.5 \
  --gas-prices 28.325uluna --chain-id columbus-5 \
  --node https://rpc.terra-classic.hexxagon.io:443 -y
```

### 5.7 Verify everything

```bash
$CLIENT -u $RPC token query --program-id <WARP> synthetic
# interchain_security_module = 4MzF7HCf… · interchain_gas_paymaster = (FLZuKRs…, OverheadIgp(FXacR73…))
# destination_gas = {132556: 3000000} · remote_routers = {132556: <TC warp hex>}
```

## 6. Post-deploy checklist (production tokens)

Same as EVM: registry PR · warp UI route · `originSenders` in the oracle-agent
config (tc-proof-of-delivery) · append the new addresses + hashes to
[DEPLOY-HASHES.md](DEPLOY-HASHES.md).
