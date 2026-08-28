# Deployed Contracts & Hashes — Terra Classic Hyperlane + Synthetics

> Auditable inventory of everything deployed, with the hash of each contract and
> the command to verify it. All values collected on-chain **2026-08-28**.
> Domains: Terra Classic **132556** · BSC **56** · Ethereum **1** · Solana **1399811149**.

## 1. Terra Classic core (columbus-5) — CosmWasm

`data_hash` = sha256 of the stored wasm, as reported by the chain itself.
Source: `tc-cw-hyperlane` (reproducible build, `cosmwasm/optimizer`).

| code_id | Contract | data_hash |
|---|---|---|
| 11371 | **hpl_mailbox** → `terra1fwg35n5esjgny7d8pxnz8usjpwsvpguk0txsy6cnqxy58x9fdlksjpx3p9` | `b6d789c1a31ee79548fd736bad241dbcd3b8b319d66a776f31479743fe49eb01` |
| 11372 | hpl_validator_announce | `c3c42fda7aabb73ab59a6dba75e20a905a310f8876e801451fcebf1599e8167d` |
| 11374 | hpl_ism_multisig | `32b07207c733ba7469f49d321c30cf00bacb8c9560dc92accd35df61e5e3a531` |
| 11376 | hpl_ism_routing | `0881d65f470425290990e53b87044477eaf704e0f2da8481eb4150c6e8c8143c` |
| 11377 | **hpl_igp** → `terra1taunhg629rssf3g939nqr0h594q5mssrzdj5lkx2hygmxmh72ghqeqqnvz` | `34313c90c9e08d2c342061412fafe4d064ad783f9be606255d0720590e6fad0b` |
| 11378 | hpl_hook_aggregate | `9dfbe1ba3e0dde5ea82cb0daee819214e46afb2ac78075c4f26523e6879a5004` |
| 11379 | hpl_hook_merkle | `c981467b9af207d09aac90716598ed51c547526b8b82189148a24e1704e7956e` |
| 11380 | hpl_hook_pausable | `f4258979caf115b1957a13f6b7ec59161b837e07b90828c2e6fc9e4e61e9f156` |
| 11381 | hpl_hook_fee | `0f53c4193be46b15eca53ff8cb2004dcc571bf74b345b2b7af2775b6fa99b6c2` |
| 11388 | **hpl_igp_oracle** → `terra1j8xzgzk7vds5uzrplmnln4vcz6f205t9atdyflypzrr43cd5eh7scwqj0d` | `3b0143755d322a7a8bcd2e6081c8a22f817644c557c85cfd4d570d69e08de1fc` |
| 11389 | **hpl_warp_cw20** → IGORFAKE collateral `terra1wr7krp8lpfddpzxfkxvmhfnxd06vkz34e7f0tk2vyau36j3d4pvs6pjpel` | `25b100c1c1bec141c90f4fc0e556b52025921403d7ae2d25bad8cfec35c74be7` |
| 11392 | cw20 (IGORFAKE token) → `terra1lpkaaqjaq8zfwktge3vy0zg46nxxsynsge2wxa7addpweu2w6gmsy3lhkr` | `28506f2a3070291f1f2568f271aa5617f0a9d02ef28d98b6804a8b7ba1506d34` |

**Wiring (verified):** IGP beneficiary = relayer-reward-vault `terra1gqkrh2…duzc2q` ·
IGP-oracle owner = oracle-governor `terra1z7jmlky…9sv4hj`. Those two contracts (the
relayer payment system) are documented with their own hashes and migration txs in
[`tc-proof-of-delivery/docs/install/AUDIT.md`](https://github.com/terra-classic-hyperlane/proof-of-delivery/blob/main/docs/install/AUDIT.md)
(vault code **11635** `339b8257…33fa` · governor 11587 `3383e2bc…41744`).

Verify any row:
```bash
curl -s https://lcd.terra-classic.hexxagon.io/cosmwasm/wasm/v1/code/<code_id> | jq -r .code_info.data_hash
curl -s https://lcd.terra-classic.hexxagon.io/cosmwasm/wasm/v1/contract/<address> | jq .contract_info.code_id
```

## 2. BSC (domain 56) — synthetic side

Hash = sha256 of the **live deployed bytecode** (`eth_getCode`).

| Piece | Address | sha256 (size) |
|---|---|---|
| Warp IGORFAKE (HypERC20 proxy) | `0x3605D8946FC6F5A75d89d92173100F59743B5318` | `083b2cd9232be4b42ff640ef331a9c00a994527cce44917374c8021cc6c3e02b` (2882 B) |
| **ISM 3-of-4** (mutable, minimal proxy) | `0xF6b0cDD33A7d2895a3F18b85569Ed9A8278cD151` | `ebabd1533007ed187cdd35cbea521be162e818a8a859f251d6f0cc6a9d69efaf` (45 B) |
| **IGP** (beneficiary = vault `0x34E06a77…`) | `0xEdEd7a4f6FEe4B474B9d7730Bf3465E35E2a4923` | `ae76a7148c0989c4d7cd30b2b5faaf7935482e9e751013cb5303de666c18a80b` (6043 B) |
| Gas oracle (owner = governor) | `0x7dE950f8F0a037783989a6BE84B3620916552306` | `d93c86aa1b584fc0147de6aadc09b78de90f08b0378ef43a2d5118d9b62440d8` (2118 B) |
| AggregationHook [merkle + IGP] | `0xD2c82583C261fce94cD3F97f1dFF9B20a9338164` | `f63af7636991137e6b3766a54f893a3a546d8513302ae45fc8d41a393f5d4e38` (246 B) |
| MerkleTree hook | `0xFDb9Cd5f9daAA2E4474019405A328a88E7484f26` | `67faae609e0c2b54b5508c926c3cb49221c6c529da5cf5ba8708a149b9b71189` (6278 B) |
| Mailbox (proxy) | `0x2971b9Aec44bE4eb673DF1B88cDB57b96eefe8a4` | `295eafd39c3e3f7a6beed270a4b13f626ef7b2613c65a2df0f0ac43f4334f189` (2555 B) |

## 3. Ethereum (domain 1) — synthetic side

| Piece | Address | sha256 (size) |
|---|---|---|
| Warp IGORFAKE (HypERC20 proxy) | `0xA687a4C4CA49795999b36fDC8A18d1DDd63eDFB5` | `083b2cd9232be4b42ff640ef331a9c00a994527cce44917374c8021cc6c3e02b` (2882 B) |
| **ISM 3-of-4** (mutable, minimal proxy) | `0x3ba17675f0D319C89D70722f6eb07790DF0B254B` | `b7cdff85f92c8394e47555637814cd106c6d807bb5cba8c3e51e3015b3a03b41` (45 B) |
| **IGP** (beneficiary = vault `0x04096dCB…`) | `0x9650F1f8DB492750323172145e67Df4e89E964Aa` | `ae76a7148c0989c4d7cd30b2b5faaf7935482e9e751013cb5303de666c18a80b` (6043 B) |
| Gas oracle (owner = governor) | `0x3987cCE8f08037EBF93Ef3a934753540A94196cE` | `d93c86aa1b584fc0147de6aadc09b78de90f08b0378ef43a2d5118d9b62440d8` (2118 B) |
| AggregationHook [merkle + IGP] | `0x912c4d91D9eD04B16B83dA79dbe7a209c8Fd0aA8` | `487b329dd722a0b9e1657453d941dd6c211f5a905aa0ccd915c9dbb198e00e3c` (246 B) |
| MerkleTree hook | `0x48e6c30B97748d1e2e03bf3e9FbE3890ca5f8CCA` | `f26ae2c918dd1b41e62a8c9f23257901b701ae82513cbfa7a1eee267c64f5623` (6278 B) |
| Mailbox (proxy) | `0xc005dc82818d67AF737725bD4bf75435d065D239` | `295eafd39c3e3f7a6beed270a4b13f626ef7b2613c65a2df0f0ac43f4334f189` (2555 B) |

**Cross-chain identity checks the hashes reveal:** the warp proxies, the IGPs, the
gas oracles, the merkle hooks and the mailbox proxies are **byte-identical between
BSC and Ethereum** (same sha256) — same code on both chains. The 45-byte ISMs and
246-byte AggregationHooks are minimal proxies/metaproxies: they differ across
chains **only** because the implementation/inner addresses are embedded in the
bytecode. Both ISMs return the identical validator set
(igorveras `0x71B2B8C3…` · tcv `0x1Afd3D07…` · darksun `0xe6BB0401…` ·
burnitall `0x5c374754…`, **threshold 3**).

Verify any row:
```bash
verify() { curl -s -X POST "$1" -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"eth_getCode","params":["'$2'","latest"]}' \
  | jq -r .result | sed 's/^0x//' | xxd -r -p | sha256sum; }
verify https://bsc-rpc.publicnode.com      0x3605D8946FC6F5A75d89d92173100F59743B5318
verify https://ethereum-rpc.publicnode.com 0xA687a4C4CA49795999b36fDC8A18d1DDd63eDFB5
# validators of an ISM:
cast call <ISM> "validatorsAndThreshold(bytes)(address[],uint8)" 0x --rpc-url <rpc>
```

## 4. Solana (domain 1399811149) — synthetic side

Hash = sha256 of `solana program dump` output (the deployed program bytes; size shown).

| Piece | Program / account | sha256 (size) |
|---|---|---|
| Warp IGORFAKE (token program) | `EPJNrrpCeZGqDPoFtdV9u9uDWBNW3Xqh84LfM7345zcL` | `d6f2fc9fed82c5079ce2cb1728d5f833d61c70e6d5f2f2a40d5df6d1bdb33419` (318,944 B) |
| SPL mint | `CeLHx5Wm9AzuWRnP4URMfNqNa9kDDrnsNGoATCS96QwD` | — (account) |
| **ISM** (mutable MultisigISM, 3-of-4) | `4MzF7HCfxuwj4EFHqZSEpvkcZZvv1mF37DP4pDHwR5VQ` | `7c97cfedfbce7321229b811af0e36a9d6e888904964f239eb6058d769f33a53d` (161,280 B) |
| **IGP program** | `FLZuKRsfdovLqd8n1AYhPCwLqBjfFyZY3A2edgnjdJoR` | `4321c4263c37317baafdb99e133ddcded8fca470c86b16383e681e9cecc08c6d` (231,824 B) |
| OverheadIgp account (set on the warp) | `FXacR73HiuNyvW7x34KYCDyv8XxM86pz31Ap8t2v3RCJ` | — (account; wraps the inner IGP below) |
| Inner IGP account (receives payments) | `FPTvDsowMHXFKktoLgy2a2qfr5yL6846JHKwvk2mYKFk` | — (beneficiary = pod pool PDA `Eq1mJGTS…`, owner = gov PDA `4sZAfqDq…`) |
| Mailbox | `E588QtVUvresuXq2KoNEwAmoifCzYGpRBdHByN9KQMbi` | — (program) |

Live warp wiring (verified with `hyperlane-sealevel-client token query`):
`interchain_security_module = 4MzF7HCf…` · `interchain_gas_paymaster =
(FLZuKRs…, OverheadIgp(FXacR73…))` · `destination_gas = {132556: 3000000}`.

Verify:
```bash
solana program dump <PROGRAM_ID> /tmp/p.so -u mainnet-beta && sha256sum /tmp/p.so
~/hyperlane-monorepo/rust/sealevel/target/release/hyperlane-sealevel-client \
  -u https://api.mainnet-beta.solana.com token query --program-id EPJNrrpCeZGqDPoFtdV9u9uDWBNW3Xqh84LfM7345zcL synthetic
```

## 5. Maintaining this document

When a new warp is deployed (see [WARP-EVM.md](WARP-EVM.md) /
[WARP-SOLANA.md](WARP-SOLANA.md)): append the new token's addresses + hashes to the
matching section, computed with the verify commands above. The shared
ISM/IGP/hook rows never change with new tokens; validator rotations change the ISM
**contents** (validators list) but not the addresses.
