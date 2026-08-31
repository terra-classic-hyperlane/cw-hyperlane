# WARP-USTC — Terra Classic USD warp route (audit & developer reference)

> Complete on-chain record of the **USTC** warp route: Terra Classic (collateral,
> native `uusd`) ↔ synthetics on **BSC**, **Ethereum** and **Solana**.
> Deployed and verified 2026-08-29; live transfers tested in both directions on
> every leg. Registry route id: `USTC/terraclassic-bsc-ethereum-solanamainnet`
> (fork `terra-classic-hyperlane/hyperlane-registry`, branch `terra-classic-warp`).

| | Terra Classic | BSC | Ethereum | Solana |
|---|---|---|---|---|
| Domain | **132556** | 56 | 1 | 1399811149 |
| Standard | CwHypNative (collateral) | EvmHypSynthetic | EvmHypSynthetic | SealevelHypSynthetic |
| Contract / program | `terra1qu3x6vh…d3ccf` | `0xfC067fd9…74339` | `0xf49408be…F1e51` | `7CUdBt1Q…GEoyf` |
| Decimals | 6 | 6 | 6 | 6 |

All security (ISM) and gas (IGP/hooks) pieces are the **shared production
infrastructure** — identical to the LUNC route ([WARP-LUNC.md](WARP-LUNC.md)).
Full row-by-row record: [DEPLOY-HASHES.md](DEPLOY-HASHES.md) §6.

---

## 1. Terra Classic (columbus-5) — collateral side

| Field | Value |
|---|---|
| Warp contract | `terra1qu3x6vhk4y6w6erhmedzfp2ug53qm5nwpyarxveqa7tvwg0telxqvd3ccf` |
| bytes32 (hex) | `0x07226d32f6a934ed6477de5a24855c45220dd26e093a333320ef96c721ebcfcc` |
| Token type | `native { fungible { denom: "uusd" } }` — mode `collateral` |
| Code | code_id **11390** (`hpl_warp_native`) — data_hash `34b5deb86937f51d4b04ddc572597b95ffd1b3ce094df8a73dc1cf20babc7e55` (same code as the LUNC warp) |
| Owner | `terra1run9wz09uhh6pu7ggcwwetrgye4wu7wn26mawp` (deployer — multisig migration planned) |
| Contract admin | *(empty — non-migratable)* |
| Routes | `1 → 0x…f49408beb319aeCe3E8B3550a5C750C19b3F1e51` · `56 → 0x…fC067fd98FD123fC2cAd72d040AF60a523274339` · `1399811149 → 0x5c16beb39b4cce694d11540723116126a83611921f0746efdc2133a3d0ab1966` |
| set_route txs | ETH `20BA313D1E3D74C49781123E0422EEE1DB0B0DD18DB7DF998EE9316DE516D1F3` · BSC `4F6B9F079D643A44CE6D3E63CA37BBD18C9D7188BD785F97569B18EFE37B0368` · Solana `CE119868BF578706B0A1AA64C87F2552F8B1C3AECA8F738A5B184A30B414F750` |

### How to verify

```bash
WARP=terra1qu3x6vhk4y6w6erhmedzfp2ug53qm5nwpyarxveqa7tvwg0telxqvd3ccf
NODE=https://rpc.terra-classic.hexxagon.io

# All routes (must list domains 1, 56 and 1399811149) — re-checked on-chain 2026-08-31
terrad query wasm contract-state smart $WARP '{"router":{"list_routes":{}}}' --node $NODE

# One route
terrad query wasm contract-state smart $WARP \
  '{"router":{"get_route":{"domain":1399811149}}}' --node $NODE

# Contract info (code_id 11390, admin empty) + code hash
terrad query wasm contract $WARP --node $NODE
curl -s https://lcd.terra-classic.hexxagon.io/cosmwasm/wasm/v1/code/11390 | jq -r .code_info.data_hash

# Locked collateral = uusd balance held by the warp contract
terrad query bank balances $WARP --denom uusd --node $NODE
```

Same queries over LCD (no terrad): `curl https://lcd.terra-classic.hexxagon.io/cosmwasm/wasm/v1/contract/$WARP/smart/<base64-of-query>`.

---

## 2. BSC (chain 56) — synthetic HypERC20 proxy

| Field | Value |
|---|---|
| Token contract | `0xfC067fd98FD123fC2cAd72d040AF60a523274339` — "Terra Classic USD" / USTC / 6 decimals |
| Owner | `0x8f085bAD1a15ee9ceeE58C83EFFFa72518975291` (deployer — multisig migration planned; also controls the ProxyAdmin) |
| ISM | production 3-of-4 `0xF6b0cDD33A7d2895a3F18b85569Ed9A8278cD151` |
| Hook | production AggregationHook `0xD2c82583C261fce94cD3F97f1dFF9B20a9338164` [merkleTree + governed IGP] |
| IGP | production `0xEdEd7a4f6FEe4B474B9d7730Bf3465E35E2a4923` (fees → relayer-reward-vault) |
| Router → TC | `132556 → 0x07226d32f6…21ebcfcc` |
| Proxy bytecode sha256 | `083b2cd9232be4b42ff640ef331a9c00a994527cce44917374c8021cc6c3e02b` (2882 B — byte-identical across all our HypERC20 proxies) |

### How to verify

```bash
W=0xfC067fd98FD123fC2cAd72d040AF60a523274339
RPC=https://bsc-dataseed.bnbchain.org

cast call $W "name()(string)"        --rpc-url $RPC   # Terra Classic USD
cast call $W "symbol()(string)"      --rpc-url $RPC   # USTC
cast call $W "decimals()(uint8)"     --rpc-url $RPC   # 6
cast call $W "totalSupply()(uint256)" --rpc-url $RPC  # synthetic supply on BSC
cast call $W "owner()(address)"      --rpc-url $RPC
cast call $W "interchainSecurityModule()(address)" --rpc-url $RPC
cast call $W "hook()(address)"       --rpc-url $RPC
cast call $W "routers(uint32)(bytes32)" 132556 --rpc-url $RPC  # must be 0x07226d32…cfcc

# Proxy bytecode hash
cast code $W --rpc-url $RPC | sed 's/^0x//' | xxd -r -p | sha256sum
# → 083b2cd9232be4b42ff640ef331a9c00a994527cce44917374c8021cc6c3e02b
```

Explorer: https://bscscan.com/token/0xfC067fd98FD123fC2cAd72d040AF60a523274339

---

## 3. Ethereum (chain 1) — synthetic HypERC20 proxy

| Field | Value |
|---|---|
| Token contract | `0xf49408beb319aeCe3E8B3550a5C750C19b3F1e51` — "Terra Classic USD" / USTC / 6 decimals |
| Owner | `0xEF8181201Ce6C83120035Ffbcc11945E67Ba00ae` (deployer — multisig migration planned; also controls the ProxyAdmin) |
| ISM | production 3-of-4 `0x3ba17675f0D319C89D70722f6eb07790DF0B254B` |
| Hook | production AggregationHook `0x912c4d91D9eD04B16B83dA79dbe7a209c8Fd0aA8` [merkleTree + governed IGP] |
| IGP | production `0x9650F1f8DB492750323172145e67Df4e89E964Aa` (fees → relayer-reward-vault) |
| Router → TC | `132556 → 0x07226d32f6…21ebcfcc` |
| Proxy bytecode sha256 | `083b2cd9232be4b42ff640ef331a9c00a994527cce44917374c8021cc6c3e02b` (2882 B) |

### How to verify

Same commands as BSC with `W=0xf49408beb319aeCe3E8B3550a5C750C19b3F1e51` and
`RPC=https://ethereum-rpc.publicnode.com`.

Explorer: https://etherscan.io/token/0xf49408beb319aeCe3E8B3550a5C750C19b3F1e51

---

## 4. Solana mainnet (domain 1399811149) — synthetic Sealevel warp

| Field | Value |
|---|---|
| Warp program | `7CUdBt1Qn2R2StE7MDPhQW2EhmnGg8zKK8oJXwAGEoyf` |
| Program hex32 (the route stored on TC) | `0x5c16beb39b4cce694d11540723116126a83611921f0746efdc2133a3d0ab1966` |
| Mint (Token-2022) | `GNUbsF5mrurtDzNc65HipN5Fyzzzqbj5UonLNhj9frjF` — mint authority = the mint PDA itself |
| Token storage PDA | `5Qw5PnPbEEfq1qudRu3fRnscQGvHDBVPVte8oZqDEqej` |
| ATA payer PDA | `2PJy1MUAaCQfxJYPm6wxZfthc46Z1iYr3MnSwRR56WHF` (funds recipients' token accounts) |
| Owner | `BirXd4QDxfq2vx9LGqgXXSgZrjT81rhoFGUbQRWDEf1j` (deployer — multisig migration planned) |
| Mailbox | `E588QtVUvresuXq2KoNEwAmoifCzYGpRBdHByN9KQMbi` (official Hyperlane) |
| ISM | production 3-of-4 `4MzF7HCfxuwj4EFHqZSEpvkcZZvv1mF37DP4pDHwR5VQ` |
| IGP | `FLZuKRsfdovLqd8n1AYhPCwLqBjfFyZY3A2edgnjdJoR` / OverheadIgp `FXacR73HiuNyvW7x34KYCDyv8XxM86pz31Ap8t2v3RCJ` — destination gas `3000000` for domain 132556 |
| Router → TC | `132556 → 0x07226d32f6…21ebcfcc` |
| Deploy / init txs | deploy `WYpXYQ24…fm1W8m9` · atomic init `jDxAwcka…GD1RGsV` · metadata `34TbFeC1…HocBUFM` |
| Program sha256 | `d6f2fc9fed82c5079ce2cb1728d5f833d61c70e6d5f2f2a40d5df6d1bdb33419` (318,944 B — byte-identical to the reference `hyperlane_sealevel_token.so` and to the LUNC program) |
| Metadata URI | `https://raw.githubusercontent.com/terra-classic-hyperlane/cw-hyperlane/refs/heads/main/warp/solana/metadata-ustc.json` |

### How to verify

```bash
RPC=https://api.mainnet-beta.solana.com   # or a private RPC
PROG=7CUdBt1Qn2R2StE7MDPhQW2EhmnGg8zKK8oJXwAGEoyf
MINT=GNUbsF5mrurtDzNc65HipN5Fyzzzqbj5UonLNhj9frjF

# Program bytecode hash (must match d6f2fc9f…b33419)
solana program dump $PROG ustc.so --url $RPC && sha256sum ustc.so

# Mint: supply, decimals, mint authority (= the mint PDA), Token-2022 metadata
spl-token display $MINT --url $RPC -p TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb

# Full warp state: ISM, IGP, destination_gas, remote_routers, mint, owner
~/hyperlane-monorepo/rust/sealevel/target/release/hyperlane-sealevel-client \
  -u $RPC token query --program-id $PROG synthetic
```

Explorer: https://explorer.solana.com/address/7CUdBt1Qn2R2StE7MDPhQW2EhmnGg8zKK8oJXwAGEoyf
· mint https://explorer.solana.com/address/GNUbsF5mrurtDzNc65HipN5Fyzzzqbj5UonLNhj9frjF

---

## 5. Auditing a transfer

The collateral invariant: **uusd locked on the TC warp = sum of synthetic
supplies on BSC + Ethereum + Solana** (each transfer out locks on TC and mints
on the destination; the return burns and releases).

```bash
# TC locked collateral
terrad query bank balances terra1qu3x6vhk4y6w6erhmedzfp2ug53qm5nwpyarxveqa7tvwg0telxqvd3ccf \
  --denom uusd --node https://rpc.terra-classic.hexxagon.io
# vs. the three synthetic supplies
cast call 0xfC067fd98FD123fC2cAd72d040AF60a523274339 "totalSupply()(uint256)" --rpc-url https://bsc-dataseed.bnbchain.org
cast call 0xf49408beb319aeCe3E8B3550a5C750C19b3F1e51 "totalSupply()(uint256)" --rpc-url https://ethereum-rpc.publicnode.com
spl-token supply GNUbsF5mrurtDzNc65HipN5Fyzzzqbj5UonLNhj9frjF --url https://api.mainnet-beta.solana.com
```

Per-message tracing: TC txs on https://finder.hexxagon.io/columbus-5 (the
`transfer_remote` / `process` events carry the Hyperlane message id), EVM txs on
BSCScan/Etherscan, Solana on the Solana Explorer. Deploy/wiring txs are recorded
in [DEPLOY-HASHES.md](DEPLOY-HASHES.md) §6.
