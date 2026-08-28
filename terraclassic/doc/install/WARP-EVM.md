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

## 5. Test the route

```bash
# TC → EVM: send via the TC collateral warp (quote the IGP fee first)
# EVM → TC: approve + transferRemote on the synthetic
cast send <WARP> "transferRemote(uint32,bytes32,uint256)" 132556 <recipient_bytes32> <amount> \
  --value <igp_quote> --rpc-url <rpc> --private-key $ETH_PRIVATE_KEY
```
The relayer delivers automatically; the fee you paid funds the relayer-reward-vault.

## 6. Post-deploy checklist (production tokens)

1. **Registry**: PR to `hyperlane-registry` (pattern of PR #1559 — on-chain mirror,
   `deploy.yaml` without comments).
2. **Warp UI**: add the route (hyperlane-warp-ui-template).
3. **Claims**: add the new warp's sender to `originSenders` in the oracle-agent
   `config.json` (tc-proof-of-delivery) so deliveries are swept.
4. **Record hashes**: append the new addresses to
   [DEPLOY-HASHES.md](DEPLOY-HASHES.md) with their verified hashes.
