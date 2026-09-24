# Create a Warp Route — Solana token → Terra Classic synthetic (reverse direction)

> The **reverse** of [WARP-SOLANA.md](WARP-SOLANA.md): here the token's real home
> is **Solana** (its own native SOL, or an existing SPL token) and **Terra Classic
> gets the synthetic mint**. No script automates this direction yet.
>
> ⚠️ **Unlike [WARP-EVM-TO-TC.md](WARP-EVM-TO-TC.md), this exact flow has not been
> run end-to-end in this repo.** The ISM/IGP/enroll/Terra-Classic steps below are
> the same proven mechanics as the live LUNC/USTC routes, just pointed at a
> different program. The **origin deploy** (§3.1) uses `hyperlane-sealevel-token-native`
> / `-collateral` instead of the `-token` (synthetic) program WARP-SOLANA.md
> deploys — verified against real mainnet config examples elsewhere in the
> Hyperlane monorepo (§3.1), but **do a devnet dry run before mainnet**; a botched
> Solana program deploy is not cheaply reversible (see WARP-SOLANA.md's own
> troubleshooting table for how that goes wrong).

## 1. What gets deployed vs reused

| Piece | Native origin (SOL) | Existing-SPL origin |
|---|---|---|
| Origin program on Solana | 🆕 `hyperlane-sealevel-token-native` (locks native SOL) | 🆕 `hyperlane-sealevel-token-collateral` (locks the existing SPL mint) |
| Synthetic warp on Terra Classic | 🆕 deployed, **mode `bridged`** (code 11389 `hpl_warp_cw20`) — same as [WARP-EVM-TO-TC.md §1](WARP-EVM-TO-TC.md#1-what-gets-deployed-vs-reused) | same |
| cw20-base "mold" | ♻️ reused: mainnet code **11677** / rebel-2 testnet code **2455** — see [WARP-EVM-TO-TC.md §2.1](WARP-EVM-TO-TC.md#21-one-extra-prerequisite-a-cw20-base-code-id-on-terra-classic) | same |
| ISM | ♻️ reused: `4MzF7HCfxuwj4EFHqZSEpvkcZZvv1mF37DP4pDHwR5VQ` (same 3-of-4 as every other TC-linked warp) | same |
| IGP | ♻️ reused: `FLZuKRsfdovLqd8n1AYhPCwLqBjfFyZY3A2edgnjdJoR` + OverheadIgp `FXacR73HiuNyvW7x34KYCDyv8XxM86pz31Ap8t2v3RCJ` | same |

Both `-native` and `-collateral` are **separate compiled programs** from the
synthetic one (`hyperlane-sealevel-token`) — Sealevel doesn't have a single
program with a runtime type switch the way the EVM `HypERC20` family does.
`build-programs.sh token` (WARP-SOLANA.md §2.2) already builds **all of them**
in one pass, so nothing new to build if you've run that once.

## 2. Prerequisites

Same as [WARP-SOLANA.md §2](WARP-SOLANA.md#2-prerequisites): Solana CLI 3.0+,
Rust 1.86+, the sealevel client built, `TERRA_PRIVATE_KEY` for the TC side, and
a private RPC (public mainnet-beta rate-limits deploys).

```bash
# Same build command as WARP-SOLANA.md §2.2 — builds token, token-native and
# token-collateral together:
cd ~/hyperlane-monorepo/rust/sealevel/programs && bash build-programs.sh token
# → ../target/deploy/hyperlane_sealevel_token_native.so
# → ../target/deploy/hyperlane_sealevel_token_collateral.so
```

Funding: same ballpark as WARP-SOLANA.md §2.3 (~2.2+ SOL rent for the program
account) — native/collateral don't create an SPL mint, so there's no separate
ATA-payer PDA to fund the way the synthetic deploy needs one.

The cw20-base code id prerequisite is identical to the EVM reverse direction —
see [WARP-EVM-TO-TC.md §2.1](WARP-EVM-TO-TC.md#21-one-extra-prerequisite-a-cw20-base-code-id-on-terra-classic)
(mainnet: reuse code **11677** · rebel-2 testnet: reuse code **2455** — nothing to upload).

## 3. Manual deployment — step by step

### 3.1 Deploy the origin program on Solana

`token_config_file` schema (verified against real production Solana warp
configs elsewhere in the Hyperlane monorepo — e.g. a native-SOL route uses
exactly this shape):

```jsonc
// token-config.json — native SOL origin
{
  "solanamainnet": {
    "type": "native",
    "decimals": 9,
    "interchainGasPaymaster": "FLZuKRsfdovLqd8n1AYhPCwLqBjfFyZY3A2edgnjdJoR",
    "owner": "<your Solana owner pubkey>"
  }
}
```

```jsonc
// token-config.json — existing SPL token origin instead
{
  "solanamainnet": {
    "type": "collateral",
    "decimals": 6,
    "token": "<existing SPL mint address, base58>",
    "interchainGasPaymaster": "FLZuKRsfdovLqd8n1AYhPCwLqBjfFyZY3A2edgnjdJoR",
    "owner": "<your Solana owner pubkey>"
  }
}
```

```bash
$CLIENT warp-route deploy \
  --built-so-dir ~/hyperlane-monorepo/rust/sealevel/target/deploy \
  --warp-route-name myeth-origin \
  --token-config-file token-config.json \
  --registry <path-to-a-hyperlane-registry-checkout> \
  -k $KEY -u $RPC
# → prints the deployed program id
```

`CLIENT` / `KEY` / `RPC` as defined in
[WARP-SOLANA.md §5](WARP-SOLANA.md#5-manual-deployment--step-by-step-what-the-script-automates).
**Test this on Solana devnet first** — nobody has run this exact command
against native/collateral in this repo yet (§0 warning above).

### 3.2 Set the production ISM

```bash
$CLIENT -k $KEY -u $RPC token set-interchain-security-module \
  --program-id <WARP> --ism 4MzF7HCfxuwj4EFHqZSEpvkcZZvv1mF37DP4pDHwR5VQ
```

### 3.3 Set the production IGP — type MUST be overhead-igp

```bash
$CLIENT -k $KEY -u $RPC token igp --program-id <WARP> set \
  FLZuKRsfdovLqd8n1AYhPCwLqBjfFyZY3A2edgnjdJoR overhead-igp \
  FXacR73HiuNyvW7x34KYCDyv8XxM86pz31Ap8t2v3RCJ
```

### 3.4 Set destination gas for Terra Classic

```bash
$CLIENT -k $KEY -u $RPC token set-destination-gas --program-id <WARP> 132556 3000000
```

### 3.5 Create the bridged (synthetic) warp on Terra Classic

Identical to the EVM reverse direction — Terra Classic doesn't care which
chain the origin token lives on, only its domain and route bytes. Follow
[WARP-EVM-TO-TC.md §3.3](WARP-EVM-TO-TC.md#33-create-the-bridged-synthetic-warp-on-terra-classic)
as-is (swap `decimals` to match the SPL token's, e.g. 9 for native SOL).

### 3.6 Enroll the Terra Classic route on the Solana warp

```bash
$CLIENT -k $KEY -u $RPC token enroll-remote-router --program-id <WARP> 132556 0x<TC_WARP_HEX>
```

`0x<TC_WARP_HEX>` = the bridged warp's `hexed` from §3.5 (same value format as
[WARP-SOLANA.md §5.5](WARP-SOLANA.md#55-enroll-the-tc-route-on-the-solana-warp)).

### 3.7 Enroll the Solana route on the Terra Classic warp (set_route)

```bash
python3 -c "import base58,sys; print(base58.b58decode('<WARP_PROGRAM_ID>').hex())"
terrad tx wasm execute <TC_WARP_ADDRESS> \
  '{"router":{"set_route":{"set":{"domain":1399811149,"route":"<PROGRAM_ID_HEX_64>"}}}}' \
  --from <tc-key> --keyring-backend file --gas auto --gas-adjustment 1.5 \
  --gas-prices 28.325uluna --chain-id columbus-5 \
  --node https://rpc.terra-classic.hexxagon.io:443 -y
```

### 3.8 Verify both directions

```bash
$CLIENT -u $RPC token query --program-id <WARP> native      # or: collateral
# interchain_security_module = 4MzF7HCf… · destination_gas = {132556: 3000000}
# remote_routers = {132556: <TC warp hex>}
terrad query wasm contract-state smart <TC_WARP_ADDRESS> \
  '{"router":{"list_routes":{}}}' --node https://rpc.terra-classic.hexxagon.io
```

## 4. Test the route

```bash
# Solana → TC: transferRemote via the origin program (locks SOL/SPL, mints on TC)
$CLIENT -k $KEY -u $RPC token transfer-remote --program-id <WARP> native \
  <sender-keypair> <amount> 132556 <tc-recipient-bytes32>

# TC → Solana: burns the bridged cw20, releases on Solana on arrival
terrad tx wasm execute <TC_WARP_ADDRESS> \
  '{"transfer_remote":{"dest_domain":1399811149,"recipient":"<recipient_bytes32>","amount":"<amount>"}}' \
  --amount <igp_quote>uluna --from <tc-key> --keyring-backend file --gas auto \
  --gas-adjustment 1.5 --gas-prices 28.325uluna --chain-id columbus-5 \
  --node https://rpc.terra-classic.hexxagon.io:443 -y
```

## 5. Post-deploy checklist (production tokens)

Same as [WARP-SOLANA.md §6](WARP-SOLANA.md#6-post-deploy-checklist-production-tokens):
registry PR, Warp UI listing ([WARP-UI-PR.md](WARP-UI-PR.md)), oracle-agent
`originSenders`, record addresses/hashes in [DEPLOY-HASHES.md](DEPLOY-HASHES.md).

## 6. Troubleshooting

Everything in [WARP-SOLANA.md §7](WARP-SOLANA.md#7-troubleshooting-lessons-from-the-live-luncustc-deploys-2026-08-29)
applies here too (RPC throttling, fee estimation, closed-program recovery —
none of that is specific to which program type was deployed). One addition:

| Symptom | Cause | Fix |
|---|---|---|
| `IncorrectProgramId` during `warp-route deploy` init | This was the known bug for the **synthetic** program's mint-PDA creation (WARP-SOLANA.md §4) — native/collateral don't create a new mint, so it shouldn't apply, but this combination is untested here | If it happens anyway, treat it exactly like WARP-SOLANA.md's warning: don't retry the same program id — `solana program close` (rent is only recoverable this way, and the id becomes permanently unusable) and redeploy under a fresh keypair |

