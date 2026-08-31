# WARP-LUNC — Luna Classic warp route (audit & developer reference)

> Complete on-chain record of the **LUNC** warp route: Terra Classic (collateral,
> native `uluna`) ↔ synthetics on **BSC**, **Ethereum** and **Solana**.
> Deployed and verified 2026-08-29; live transfers tested in both directions on
> every leg. Registry route id: `LUNC/terraclassic-bsc-ethereum-solanamainnet`
> (fork `terra-classic-hyperlane/hyperlane-registry`, branch `terra-classic-warp`).

| | Terra Classic | BSC | Ethereum | Solana |
|---|---|---|---|---|
| Domain | **132556** | 56 | 1 | 1399811149 |
| Standard | CwHypNative (collateral) | EvmHypSynthetic | EvmHypSynthetic | SealevelHypSynthetic |
| Contract / program | `terra1m7jcqxf…50cggy` | `0x481095ec…9e6e2` | `0xA4bc47a4…44Ac6` | `Dd3ajD8W…NGnbr` |
| Decimals | 6 | 6 | 6 | 6 |

All security (ISM) and gas (IGP/hooks) pieces are the **shared production
infrastructure** — nothing token-specific was created for them. See
[DEPLOY-HASHES.md](DEPLOY-HASHES.md) §5 for the full row-by-row record.

---

## 1. Terra Classic (columbus-5) — collateral side

| Field | Value |
|---|---|
| Warp contract | `terra1m7jcqxfn4hd7q4sywhw508nxshaf078c4vh83y0ts43y9tlp9dcs50cggy` |
| bytes32 (hex) | `0xdfa5801933addbe0560475dd479e6685fa97f8f8ab2e7891eb856242afe12b71` |
| Token type | `native { fungible { denom: "uluna" } }` — mode `collateral` |
| Code | code_id **11390** (`hpl_warp_native`) — data_hash `34b5deb86937f51d4b04ddc572597b95ffd1b3ce094df8a73dc1cf20babc7e55` |
| Owner | `terra1run9wz09uhh6pu7ggcwwetrgye4wu7wn26mawp` (deployer — multisig migration planned) |
| Contract admin | *(empty — non-migratable)* |
| Routes | `1 → 0x…A4bc47a4C5461eB0E59A585a21A1222EF7544Ac6` · `56 → 0x…481095ecEd7A907e7f390b6226F53a66D379e6e2` · `1399811149 → 0xbb8812381e07b070e8d37945ae659b8ad17ff2c5c36f019f351f332d45a3b261` |
| set_route txs | ETH `752F3EA9E3925D3659E50641ADBC6610818FB33E544AC65115CA8B5B93A9BF80` · BSC `3A012A09C960896EEB22CBC908881A2C9FF0749E24100787C3519ED82936408C` · Solana `14C2BF10D2288940F2D65F3BD3017967B9563CF4CC98E8C314799C72ED65D9DA` |

### How to verify

```bash
WARP=terra1m7jcqxfn4hd7q4sywhw508nxshaf078c4vh83y0ts43y9tlp9dcs50cggy
NODE=https://rpc.terra-classic.hexxagon.io

# All routes (must list domains 1, 56 and 1399811149)
terrad query wasm contract-state smart $WARP '{"router":{"list_routes":{}}}' --node $NODE

# One route
terrad query wasm contract-state smart $WARP \
  '{"router":{"get_route":{"domain":1399811149}}}' --node $NODE

# Contract info (code_id 11390, admin empty) + code hash
terrad query wasm contract $WARP --node $NODE
curl -s https://lcd.terra-classic.hexxagon.io/cosmwasm/wasm/v1/code/11390 | jq -r .code_info.data_hash

# Locked collateral = uluna balance held by the warp contract
terrad query bank balances $WARP --denom uluna --node $NODE
```

Same queries over LCD (no terrad): `curl https://lcd.terra-classic.hexxagon.io/cosmwasm/wasm/v1/contract/$WARP/smart/<base64-of-query>`.

---

## 2. BSC (chain 56) — synthetic HypERC20 proxy

| Field | Value |
|---|---|
| Token contract | `0x481095ecEd7A907e7f390b6226F53a66D379e6e2` — "Luna Classic" / LUNC / 6 decimals |
| Owner | `0x8f085bAD1a15ee9ceeE58C83EFFFa72518975291` (deployer — multisig migration planned; also controls the ProxyAdmin) |
| ISM | production 3-of-4 `0xF6b0cDD33A7d2895a3F18b85569Ed9A8278cD151` |
| Hook | production AggregationHook `0xD2c82583C261fce94cD3F97f1dFF9B20a9338164` [merkleTree + governed IGP] |
| IGP | production `0xEdEd7a4f6FEe4B474B9d7730Bf3465E35E2a4923` (fees → relayer-reward-vault) |
| Router → TC | `132556 → 0xdfa5801933…afe12b71` |
| Proxy bytecode sha256 | `083b2cd9232be4b42ff640ef331a9c00a994527cce44917374c8021cc6c3e02b` (2882 B — byte-identical across all our HypERC20 proxies) |

### How to verify

```bash
W=0x481095ecEd7A907e7f390b6226F53a66D379e6e2
RPC=https://bsc-dataseed.bnbchain.org

cast call $W "name()(string)"        --rpc-url $RPC   # Luna Classic
cast call $W "symbol()(string)"      --rpc-url $RPC   # LUNC
cast call $W "decimals()(uint8)"     --rpc-url $RPC   # 6
cast call $W "totalSupply()(uint256)" --rpc-url $RPC  # synthetic supply on BSC
cast call $W "owner()(address)"      --rpc-url $RPC
cast call $W "interchainSecurityModule()(address)" --rpc-url $RPC
cast call $W "hook()(address)"       --rpc-url $RPC
cast call $W "routers(uint32)(bytes32)" 132556 --rpc-url $RPC  # must be 0xdfa58019…2b71

# Proxy bytecode hash
cast code $W --rpc-url $RPC | sed 's/^0x//' | xxd -r -p | sha256sum
# → 083b2cd9232be4b42ff640ef331a9c00a994527cce44917374c8021cc6c3e02b
```

Explorer: https://bscscan.com/token/0x481095ecEd7A907e7f390b6226F53a66D379e6e2

---

## 3. Ethereum (chain 1) — synthetic HypERC20 proxy

| Field | Value |
|---|---|
| Token contract | `0xA4bc47a4C5461eB0E59A585a21A1222EF7544Ac6` — "Luna Classic" / LUNC / 6 decimals |
| Owner | `0xEF8181201Ce6C83120035Ffbcc11945E67Ba00ae` (deployer — multisig migration planned; also controls the ProxyAdmin) |
| ISM | production 3-of-4 `0x3ba17675f0D319C89D70722f6eb07790DF0B254B` |
| Hook | production AggregationHook `0x912c4d91D9eD04B16B83dA79dbe7a209c8Fd0aA8` [merkleTree + governed IGP] |
| IGP | production `0x9650F1f8DB492750323172145e67Df4e89E964Aa` (fees → relayer-reward-vault) |
| Router → TC | `132556 → 0xdfa5801933…afe12b71` |
| Proxy bytecode sha256 | `083b2cd9232be4b42ff640ef331a9c00a994527cce44917374c8021cc6c3e02b` (2882 B) |

### How to verify

Same commands as BSC with `W=0xA4bc47a4C5461eB0E59A585a21A1222EF7544Ac6` and
`RPC=https://ethereum-rpc.publicnode.com`.

Explorer: https://etherscan.io/token/0xA4bc47a4C5461eB0E59A585a21A1222EF7544Ac6

---

## 4. Solana mainnet (domain 1399811149) — synthetic Sealevel warp

| Field | Value |
|---|---|
| Warp program | `Dd3ajD8WbEyx7z3HqPnDyvUgFqEBzvF1VePjYd1NGnbr` |
| Program hex32 (the route stored on TC) | `0xbb8812381e07b070e8d37945ae659b8ad17ff2c5c36f019f351f332d45a3b261` |
| Mint (Token-2022) | `8dxTo5reLtvRDx3Q8WEP33Uj2C5u6372EygJdNbsLFKG` — mint authority = the mint PDA itself |
| Token storage PDA | `A4kSqqDvYFtC4Cvn1ZTU7YRZHAgnBCNjco7oib9DP2w3` |
| ATA payer PDA | `G7VKP5kEACiWHJvAt3zC4GY1DfJ1X2qHy5uzFDmUZDyL` (funds recipients' token accounts) |
| Owner | `BirXd4QDxfq2vx9LGqgXXSgZrjT81rhoFGUbQRWDEf1j` (deployer — multisig migration planned) |
| Mailbox | `E588QtVUvresuXq2KoNEwAmoifCzYGpRBdHByN9KQMbi` (official Hyperlane) |
| ISM | production 3-of-4 `4MzF7HCfxuwj4EFHqZSEpvkcZZvv1mF37DP4pDHwR5VQ` |
| IGP | `FLZuKRsfdovLqd8n1AYhPCwLqBjfFyZY3A2edgnjdJoR` / OverheadIgp `FXacR73HiuNyvW7x34KYCDyv8XxM86pz31Ap8t2v3RCJ` — destination gas `3000000` for domain 132556 |
| Router → TC | `132556 → 0xdfa5801933…afe12b71` |
| Program sha256 | `d6f2fc9fed82c5079ce2cb1728d5f833d61c70e6d5f2f2a40d5df6d1bdb33419` (318,944 B — byte-identical to the reference `hyperlane_sealevel_token.so`) |
| Metadata URI | `https://raw.githubusercontent.com/terra-classic-hyperlane/cw-hyperlane/refs/heads/main/warp/solana/metadata-lunc.json` |

### How to verify

```bash
RPC=https://api.mainnet-beta.solana.com   # or a private RPC
PROG=Dd3ajD8WbEyx7z3HqPnDyvUgFqEBzvF1VePjYd1NGnbr
MINT=8dxTo5reLtvRDx3Q8WEP33Uj2C5u6372EygJdNbsLFKG

# Program bytecode hash (must match d6f2fc9f…b33419)
solana program dump $PROG lunc.so --url $RPC && sha256sum lunc.so

# Mint: supply, decimals, mint authority (= the mint PDA), Token-2022 metadata
spl-token display $MINT --url $RPC -p TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb

# Full warp state: ISM, IGP, destination_gas, remote_routers, mint, owner
~/hyperlane-monorepo/rust/sealevel/target/release/hyperlane-sealevel-client \
  -u $RPC token query --program-id $PROG synthetic
```

Explorer: https://explorer.solana.com/address/Dd3ajD8WbEyx7z3HqPnDyvUgFqEBzvF1VePjYd1NGnbr
· mint https://explorer.solana.com/address/8dxTo5reLtvRDx3Q8WEP33Uj2C5u6372EygJdNbsLFKG

---

## 5. Auditing a transfer

The collateral invariant: **uluna locked on the TC warp = sum of synthetic
supplies on BSC + Ethereum + Solana** (each transfer out locks on TC and mints
on the destination; the return burns and releases).

```bash
# TC locked collateral
terrad query bank balances terra1m7jcqxfn4hd7q4sywhw508nxshaf078c4vh83y0ts43y9tlp9dcs50cggy \
  --denom uluna --node https://rpc.terra-classic.hexxagon.io
# vs. the three synthetic supplies
cast call 0x481095ecEd7A907e7f390b6226F53a66D379e6e2 "totalSupply()(uint256)" --rpc-url https://bsc-dataseed.bnbchain.org
cast call 0xA4bc47a4C5461eB0E59A585a21A1222EF7544Ac6 "totalSupply()(uint256)" --rpc-url https://ethereum-rpc.publicnode.com
spl-token supply 8dxTo5reLtvRDx3Q8WEP33Uj2C5u6372EygJdNbsLFKG --url https://api.mainnet-beta.solana.com
```

Per-message tracing: TC txs on https://finder.hexxagon.io/columbus-5 (the
`transfer_remote` / `process` events carry the Hyperlane message id), EVM txs on
BSCScan/Etherscan, Solana on the Solana Explorer. Deploy/wiring txs are recorded
in [DEPLOY-HASHES.md](DEPLOY-HASHES.md) §5.
