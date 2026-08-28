# Create a Warp Route — BSC / Ethereum ↔ Terra Classic

> One script does everything: `terraclassic/create-warp-evm.sh`. It deploys **only
> the token's own contracts** and wires them to the production ISM/IGP/hook
> (see [README.md](README.md)). Full field-by-field reference:
> [`../create-warp-evm-guide.md`](../create-warp-evm-guide.md).

## 1. What gets deployed vs reused

| Piece | New token on BSC | New token on Ethereum |
|---|---|---|
| Synthetic token (HypERC20 proxy) | 🆕 deployed | 🆕 deployed |
| Collateral warp on Terra Classic | 🆕 deployed (code 11389 `hpl_warp_cw20` / native) | same |
| ISM | ♻️ reused: `0xF6b0cDD33A7d2895a3F18b85569Ed9A8278cD151` (mutable 3-of-4) | ♻️ `0x3ba17675f0D319C89D70722f6eb07790DF0B254B` |
| IGP | ♻️ reused: `0xEdEd7a4f6FEe4B474B9d7730Bf3465E35E2a4923` (fees → vault pool) | ♻️ `0x9650F1f8DB492750323172145e67Df4e89E964Aa` |
| Hook | ♻️ reused: AggregationHook `0xD2c82583C261fce94cD3F97f1dFF9B20a9338164` | ♻️ `0x912c4d91D9eD04B16B83dA79dbe7a209c8Fd0aA8` |
| Gas prices | ♻️ governed (oracle-agent → governor → oracle) — never set manually | same |

All reuse defaults come from `warp-evm-config.json` (`ism.deployed_address`,
`igp.deployed_address`, `hook.deployed_aggregation`) — already filled with the
production addresses above.

## 2. Prerequisites

- Node.js 20+, `jq`, Foundry (`cast`); the script installs `@hyperlane-xyz/cli` if missing.
- **Keys** (env only, never in files): the EVM owner key of the target chain and,
  for the automatic Terra Classic side, the TC owner key.
- Gas: ~0.01 BNB (BSC) / ~0.02 ETH (mainnet, varies) + ~200 LUNC for the TC side.

## 3. Add your token to the config

Edit `terraclassic/warp-evm-config.json` (guide §4.3 has the full annotated
template). **You write only the token definition (§3.1).** Everything the script
configures is deployment **state** that the script itself creates and maintains
in the same file (§3.2) — you never write it.

### 3.1 Define the token — `terra_classic.tokens` (the ONLY thing you write)

What the token IS and its Terra Classic side:

```jsonc
"mytoken": {
  "id": "mytoken",
  "name": "My Token",
  "symbol": "MTK",
  "decimals": 6,
  "terra_warp": {
    "type": "cw20",                     // or "native"
    "mode": "collateral",
    "owner": "terra1...",
    "denom": "",                        // fill if native (e.g. "uluna")
    "collateral_address": "terra1..."   // fill if cw20
  }
}
```

That's it. The token now appears in the script's menu (the menu lists
`terra_classic.tokens` keys).

### 3.2 Deployment state — created and filled BY THE SCRIPT (do not write)

As the run progresses, the script **adds** its state to the same JSON via `jq`
(missing fields/entries are created automatically — you don't pre-create them):

- Inside your token's `terra_warp` (after the TC collateral deploy):
  `warp_address` (the collateral warp on TC), `warp_hexed` (same address as
  32-byte hex, used by `enrollRemoteRouter` on the EVM side), `deployed: true`.
- A `networks.<bsc|ethereum>.warp_tokens.mytoken` entry per chain:

| Field | What it records | Filled by |
|---|---|---|
| `deployed` | whether the synthetic already exists on this chain | script, after STEP 2 succeeds (`false` → `true`) |
| `address` | the synthetic token (HypERC20) address on this chain — e.g. IGORFAKE/BSC = `0x3605D894…` | script, after `hyperlane warp deploy` |
| `igp_custom` | the IGP associated with this token's route — with production defaults, the shared IGP (BSC `0xEdEd7a4f…`) | script, STEP 3 |
| `hook_aggregation` | the AggregationHook set on the warp via `setHook` — with defaults, the production one (BSC `0xD2c82583…`) | script, STEP 5 |
| `owner` | the warp's owner on this chain (derived from `ETH_PRIVATE_KEY`) | script, after deploy |

Why it matters:
- **Resume after failure** — re-running the script reads these fields and skips
  what is already done (`address` filled → no second warp deploy; and so on).
  Nothing is ever deployed twice.
- **One entry per network** — the same token has different addresses on each
  chain; `networks.bsc.warp_tokens.mytoken` and
  `networks.ethereum.warp_tokens.mytoken` are independent records.
- **Post-deploy source of truth** — after the run, this entry is where you copy
  the addresses from for [DEPLOY-HASHES.md](DEPLOY-HASHES.md) and the registry PR.

Do **not** touch `ism`, `igp`, `hook` or any price field — production defaults.

## 4. Run

```bash
cd ~/tc-cw-hyperlane/terraclassic
export ETH_PRIVATE_KEY="0x…"            # owner on the target EVM chain
export TERRA_PRIVATE_KEY="hex_no_0x"    # optional: automatic TC collateral deploy
./create-warp-evm.sh                    # interactive: pick the token + network
```

### Example — BSC

Pick `bsc` in the menu. Expected flow:
`STEP 1` yaml with `interchainSecurityModule: "0xF6b0cDD3…"` (no ISM created) →
`STEP 2` `hyperlane warp deploy` (the only EVM contract created) →
`STEP 3` "Reusing production IGP 0xEdEd7a4f… (fees → vault pool)" →
`STEP 4` "oracle already has data for domain 132556" (skipped) →
`STEP 5` "Reusing production AggregationHook 0xD2c82583…" → `setHook` →
`STEP 6` ISM verification (already set) →
`STEP 7` `enrollRemoteRouter` ↔ TC `set_route` (bidirectional link).

### Example — Ethereum

Identical flow picking `ethereum`; the reused addresses are the ETH column of §1.
Watch mainnet gas — the only expensive tx is the warp deploy itself.

## 5. Manual deployment — step by step (what the script automates)

Every step below is exactly what `create-warp-evm.sh` runs. Use this to execute
by hand, to resume one failed step, or to audit what the automation does.
Example values: BSC (domain 56); swap the addresses for ETH (§1).

### 5.1 Deploy the collateral warp on Terra Classic

```bash
cd ~/tc-cw-hyperlane        # project root (cw-hpl reads config.yaml + context/ here)
PRIVATE_KEY="$TERRA_PRIVATE_KEY" yarn cw-hpl warp create <warp-config> -n terraclassic
# → the new address is recorded in context/terraclassic.json
#   (.deployments.warp.cw20[] / .native[] — fields address and hexAddress)
```

Keep the bech32 address (`terra1…`) and its **32-byte hex** (`hexAddress`) — the
hex is what the EVM side enrolls.

### 5.2 Deploy the synthetic on the EVM chain

Write the deploy config (this is the yaml the script generates — note the ISM is
the production **address**, so no new ISM is created):

```yaml
# warp/warp-bsc-mytoken.yaml
bsc:
  isNft: false
  type: synthetic
  name: "My Token"
  symbol: "MTK"
  decimals: 6
  owner: "0x8f085bAD1a15ee9ceeE58C83EFFFa72518975291"
  mailbox: "0x2971b9Aec44bE4eb673DF1B88cDB57b96eefe8a4"
  interchainSecurityModule: "0xF6b0cDD33A7d2895a3F18b85569Ed9A8278cD151"
```

```bash
hyperlane warp deploy --config warp/warp-bsc-mytoken.yaml --key "$ETH_PRIVATE_KEY" --yes
# → note the deployed warp address (addressOrDenom in the output)
```

### 5.3 Verify the ISM (set at deploy; fix only if needed)

```bash
cast call <WARP> "interchainSecurityModule()(address)" --rpc-url <RPC>
# must print 0xF6b0cDD3… — if not:
cast send <WARP> "setInterchainSecurityModule(address)" 0xF6b0cDD33A7d2895a3F18b85569Ed9A8278cD151 \
  --rpc-url <RPC> --private-key "$ETH_PRIVATE_KEY" --legacy
```

### 5.4 Set the production hook (merkle + governed IGP)

```bash
cast send <WARP> "setHook(address)" 0xD2c82583C261fce94cD3F97f1dFF9B20a9338164 \
  --rpc-url <RPC> --private-key "$ETH_PRIVATE_KEY" --legacy
```

No IGP deploy and no gas prices to set — the hook's IGP is the production one,
already governed (fees → vault pool).

### 5.5 Enroll the TC route on the EVM warp

`bytes32` = the TC warp's `hexAddress` from §5.1, left-padded to 64 hex chars:

```bash
cast send <WARP> "enrollRemoteRouter(uint32,bytes32)" 132556 0x<TC_WARP_HEX_64> \
  --rpc-url <RPC> --private-key "$ETH_PRIVATE_KEY" --legacy
```

### 5.6 Enroll the EVM route on the TC warp (set_route)

`route` = the EVM warp address without `0x`, left-padded with zeros to 64 hex chars:

```bash
terrad tx wasm execute <TC_WARP_ADDRESS> \
  '{"router":{"set_route":{"set":{"domain":56,"route":"000000000000000000000000<EVM_WARP_40HEX>"}}}}' \
  --from <tc-key> --keyring-backend file --gas auto --gas-adjustment 1.5 \
  --gas-prices 28.325uluna --chain-id columbus-5 \
  --node https://rpc.terra-classic.hexxagon.io:443 -y
```

Without this step, `transfer_remote` from Terra Classic fails with "route not found".

### 5.7 Verify both directions

```bash
cast call <WARP> "routers(uint32)(bytes32)" 132556 --rpc-url <RPC>     # → TC warp hex
curl -s "https://lcd.terra-classic.hexxagon.io/cosmwasm/wasm/v1/contract/<TC_WARP>/smart/$(echo -n '{"router":{"list_routes":{}}}' | base64 -w0)"
```

## 6. Test the route

```bash
# TC → EVM: send via the TC collateral warp (quote the IGP fee first)
# EVM → TC: approve + transferRemote on the synthetic
cast send <WARP> "transferRemote(uint32,bytes32,uint256)" 132556 <recipient_bytes32> <amount> \
  --value <igp_quote> --rpc-url <rpc> --private-key $ETH_PRIVATE_KEY
```
The relayer delivers automatically; the fee you paid funds the relayer-reward-vault.

## 7. Post-deploy checklist (production tokens)

1. **Registry**: PR to `hyperlane-registry` (pattern of PR #1559 — on-chain mirror,
   `deploy.yaml` without comments).
2. **Warp UI**: add the route (hyperlane-warp-ui-template).
3. **Claims**: add the new warp's sender to `originSenders` in the oracle-agent
   `config.json` (tc-proof-of-delivery) so deliveries are swept.
4. **Record hashes**: append the new addresses to
   [DEPLOY-HASHES.md](DEPLOY-HASHES.md) with their verified hashes.
