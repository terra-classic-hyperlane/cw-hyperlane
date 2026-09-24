# Create a Warp Route — BSC / Ethereum token → Terra Classic synthetic (reverse direction)

> The **reverse** of [WARP-EVM.md](WARP-EVM.md): here the token's real home is
> **BSC or Ethereum** (its own native gas coin, or an existing ERC20) and
> **Terra Classic gets the synthetic mint**. No script automates this direction
> yet — every step below uses the **same two tools** WARP-EVM.md already
> depends on (`hyperlane` CLI + `cw-hpl`), just with different config values.
> A working reference implementation (browser wallets instead of CLI keys,
> fully tested on both mainnet and rebel-2 testnet) lives in the
> `warp-foundry-v2` app.

## 1. What gets deployed vs reused

| Piece | Native origin (e.g. ETH, BNB) | Existing-ERC20 origin (e.g. an existing token) |
|---|---|---|
| Origin router on the EVM chain | 🆕 `HypNative` (locks the chain's own gas coin) | 🆕 `HypCollateral` (locks the existing ERC20) |
| Synthetic warp on Terra Classic | 🆕 deployed, **mode `bridged`** (code 11389 `hpl_warp_cw20` — mints a fresh cw20-base child on receipt) | same |
| cw20-base "mold" the synthetic is minted from | ♻️ reused: mainnet code **3** (the chain's original shared cw20-base) | same |
| ISM / IGP / Hook (EVM side) | ♻️ reused — identical addresses to [WARP-EVM.md §1](WARP-EVM.md#1-what-gets-deployed-vs-reused) for the same chain | same |
| ISM / IGP / Hook (Terra Classic side) | ♻️ reused — production shared infra, same as every other TC warp | same |

The **collateral invariant flips** compared to WARP-EVM.md: instead of "uluna
locked on TC = synthetic supply on EVM", it's now **origin token locked on the
EVM chain = synthetic cw20 supply on Terra Classic**. Nothing else about the
security model changes — same ISM validator sets, same governed gas oracle.

## 2. Prerequisites

Same tools, repo setup, and key handling as
[WARP-EVM.md §2](WARP-EVM.md#2-prerequisites) — `forge`/`cast`, the `hyperlane`
CLI (v26+), `yarn install` once in `~/tc-cw-hyperlane`, and:

```bash
export ETH_PRIVATE_KEY="0x…"              # owner on the EVM chain (BSC/Ethereum)
export TERRA_PRIVATE_KEY="hex_no_0x"      # owner on Terra Classic (signs the bridged create + set_route)
```

Funding: same EVM amounts as WARP-EVM.md §2.4 (the origin deploy is a bit
cheaper than a synthetic deploy — no `initialSupply`/`name`/`symbol` storage
writes); **~60 LUNC** on Terra Classic for the bridged create + `set_route`
(cheaper than the ~200 LUNC WARP-EVM.md budgets, since nothing is locked here).

### 2.1 One extra prerequisite: a cw20-base code id on Terra Classic

The bridged warp needs an already-uploaded **cw20-base** contract code to mint
children from (`config.code_id` in §4). This is a one-time upload per network,
not per token:

| Network | code_id | Notes |
|---|---|---|
| Mainnet (columbus-5) | **3** | The chain's original shared cw20-base — already used by MIR and hundreds of Terra-era tokens. Reuse it; do not upload a new one. |
| rebel-2 testnet | *(upload your own — no shared one exists yet)* | See below |

To upload a fresh one (testnet, or if mainnet's ever needs replacing):

```bash
terrad tx wasm store cw20_base.wasm \
  --from <tc-key> --keyring-backend file --gas auto --gas-adjustment 1.5 \
  --gas-prices 28.325uluna --chain-id <columbus-5|rebel-2> \
  --node <rpc> -y
# → find the new code_id in the tx's store_code event:
terrad query tx <TX_HASH> --node <rpc> -o json | jq -r '.events[] | select(.type=="store_code") | .attributes[] | select(.key=="code_id") | .value'
```

`cw20_base.wasm` is the stock [CosmWasm Plus](https://github.com/CosmWasm/cw-plus)
`cw20-base` contract — any build of it works, mainnet's code 3 and this one are
interchangeable in function.

## 3. Manual deployment — step by step

Example values below: **Ethereum**, native ETH origin (domain 1). Swap
addresses for BSC using [WARP-EVM.md §1](WARP-EVM.md#1-what-gets-deployed-vs-reused);
swap `type: native` for `type: collateral` + `token: <erc20-address>` for an
existing-ERC20 origin (§3.1b).

### 3.1a Deploy the origin router on the EVM chain — native coin

```yaml
# warp/warp-ethereum-myeth-origin.yaml
ethereum:
  isNft: false
  type: native
  owner: "0xEF8181201Ce6C83120035Ffbcc11945E67Ba00ae"
  mailbox: "0xc005dc82818d67AF737725bD4bf75435d065D239"
  interchainSecurityModule: "0x3ba17675f0D319C89D70722f6eb07790DF0B254B"
```

```bash
hyperlane warp deploy --config warp/warp-ethereum-myeth-origin.yaml --key "$ETH_PRIVATE_KEY" --yes
# → note the deployed router address (addressOrDenom in the output)
```

### 3.1b …or deploy it locking an existing ERC20 instead

Same config, `type: collateral` + the token to lock:

```yaml
ethereum:
  isNft: false
  type: collateral
  token: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"   # the existing ERC20 address
  owner: "0xEF8181201Ce6C83120035Ffbcc11945E67Ba00ae"
  mailbox: "0xc005dc82818d67AF737725bD4bf75435d065D239"
  interchainSecurityModule: "0x3ba17675f0D319C89D70722f6eb07790DF0B254B"
```

Everything from here on is identical for both — the router deployed in either
case exposes the same `enrollRemoteRouter`/`routers()` interface.

### 3.2 Set the production hook

```bash
cast send <ROUTER> "setHook(address)" 0x912c4d91D9eD04B16B83dA79dbe7a209c8Fd0aA8 \
  --rpc-url <RPC> --private-key "$ETH_PRIVATE_KEY" --legacy
```
(BSC: `0xD2c82583C261fce94cD3F97f1dFF9B20a9338164` — see WARP-EVM.md §1.)

### 3.3 Create the bridged (synthetic) warp on Terra Classic

```jsonc
// warp/warp-tc-myeth-bridged.json
{
  "type": "cw20",
  "mode": "bridged",
  "id": "myeth",
  "owner": "terra1run9wz09uhh6pu7ggcwwetrgye4wu7wn26mawp",
  "config": {
    "code_id": 3,
    "init_msg": {
      "name": "My ETH",
      "symbol": "ETH",
      "decimals": 18,
      "initial_balances": [],
      "mint": null,
      "marketing": null
    }
  }
}
```

```bash
cd ~/tc-cw-hyperlane
PRIVATE_KEY="$TERRA_PRIVATE_KEY" yarn cw-hpl warp create warp/warp-tc-myeth-bridged.json -n terraclassic
# → the new address is recorded in context/terraclassic.json
#   (.deployments.warp.cw20[] — fields address and hexed)
```

Two things worth knowing about `mode: "bridged"`:

- **`mint` in `init_msg` is ignored** — the contract forcibly sets the fresh
  cw20's minter to *itself* on instantiation (so it can mint on receipt / burn
  on send). Whatever you put there is overwritten; leaving it `null` is fine.
- **`initial_balances` should stay `[]`.** The synthetic's supply is meant to
  be entirely backed by what's locked on the EVM side — pre-minting here
  creates unbacked supply.
- `decimals` should match the **origin token's** decimals (18 for ETH/most
  ERC20s, not the 6 you'll see in [WARP-LUNC.md](WARP-LUNC.md) — that one's a
  Terra-native 6-decimal token, unrelated here).

### 3.4 Enroll the Terra Classic route on the EVM router

`bytes32` = the TC warp's `hexed` from §3.3, left-padded to 64 hex chars:

```bash
cast send <ROUTER> "enrollRemoteRouter(uint32,bytes32)" 132556 0x<TC_WARP_HEX_64> \
  --rpc-url <RPC> --private-key "$ETH_PRIVATE_KEY" --legacy
```

### 3.5 Enroll the EVM route on the Terra Classic warp

`route` = the EVM router address without `0x`, left-padded with zeros to 64
hex chars; `1` = Ethereum's domain (`56` for BSC):

```bash
terrad tx wasm execute <TC_WARP_ADDRESS> \
  '{"router":{"set_route":{"set":{"domain":1,"route":"000000000000000000000000<EVM_ROUTER_40HEX>"}}}}' \
  --from <tc-key> --keyring-backend file --gas auto --gas-adjustment 1.5 \
  --gas-prices 28.325uluna --chain-id columbus-5 \
  --node https://rpc.terra-classic.hexxagon.io:443 -y
```

Without this step, transfers arriving *from* Ethereum have nowhere to route
back to, and `transfer_remote` *to* Ethereum fails with "route not found".

### 3.6 Verify both directions

```bash
cast call <ROUTER> "routers(uint32)(bytes32)" 132556 --rpc-url <RPC>   # → TC warp hex
terrad query wasm contract-state smart <TC_WARP_ADDRESS> \
  '{"router":{"list_routes":{}}}' --node https://rpc.terra-classic.hexxagon.io
```

## 4. Test the route

```bash
# EVM → TC: send via the origin router (mints on Terra Classic on arrival)
cast send <ROUTER> "transferRemote(uint32,bytes32,uint256)" 132556 <recipient_bytes32> <amount> \
  --value <igp_quote> --rpc-url <RPC> --private-key $ETH_PRIVATE_KEY

# TC → EVM: send via the bridged warp (burns on Terra Classic, unlocks on arrival)
terrad tx wasm execute <TC_WARP_ADDRESS> \
  '{"transfer_remote":{"dest_domain":1,"recipient":"<recipient_bytes32>","amount":"<amount>"}}' \
  --amount <igp_quote>uluna --from <tc-key> --keyring-backend file --gas auto \
  --gas-adjustment 1.5 --gas-prices 28.325uluna --chain-id columbus-5 \
  --node https://rpc.terra-classic.hexxagon.io:443 -y
```

The relayer delivers both directions automatically.

## 5. Post-deploy checklist (production tokens)

Same as [WARP-EVM.md §7](WARP-EVM.md#7-post-deploy-checklist-production-tokens):
registry PR, Warp UI listing ([WARP-UI-PR.md](WARP-UI-PR.md)), oracle-agent
`originSenders`, and record the new addresses/hashes in
[DEPLOY-HASHES.md](DEPLOY-HASHES.md).

## 6. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `cw-hpl warp create` fails validating `config.code_id` | No cw20-base uploaded on this network yet | §2.1 — upload one, or reuse mainnet's code 3 |
| Synthetic's total supply looks wrong right after create | `initial_balances` was non-empty in `init_msg` | Re-deploy with `initial_balances: []` — supply must come only from cross-chain mints |
| `transfer_remote` from Terra Classic reverts with "route not found" | §3.5 wasn't run, or ran with the wrong `domain` | Re-run §3.5 with the correct EVM domain (1 = Ethereum, 56 = BSC) |
| Inbound EVM → TC transfer never arrives | §3.4 wasn't run (EVM router has no route to TC) | Re-run §3.4 |
| `quoteGasPayment` reverts / returns 0 on the origin router | Hook not set, or wrong hook | Re-check §3.2 against [WARP-EVM.md §1](WARP-EVM.md#1-what-gets-deployed-vs-reused) |
| `-n terraclassictestnet` fails / unknown network | This repo's `cw-hpl` context currently only has a mainnet (`terraclassic`) context file | Testnet needs its own `context/terraclassictestnet.json`, or use the `warp-foundry-v2` app, which handles rebel-2 independently |

Live example to compare structure against (forward direction, but same shared
infra): [WARP-LUNC.md](WARP-LUNC.md).
