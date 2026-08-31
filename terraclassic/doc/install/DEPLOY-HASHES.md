# Deployed Contracts & Hashes — Terra Classic Hyperlane + Synthetics

> Auditable inventory of everything deployed, with the hash of each contract and
> the command to verify it. All values collected on-chain **2026-08-28**.
> Domains: Terra Classic **132556** · BSC **56** · Ethereum **1** · Solana **1399811149**.

## 1. Terra Classic core (columbus-5) — CosmWasm

`data_hash` = sha256 of the stored wasm, as reported by the chain itself.
Source: `tc-cw-hyperlane` (reproducible build, `cosmwasm/optimizer`).

Complete upload set (store txs and instantiation record:
[`../HYPERLANE_DEPLOYMENT-MAINNET_EN.md`](../HYPERLANE_DEPLOYMENT-MAINNET_EN.md)):

| code_id | Contract | data_hash |
|---|---|---|
| 11371 | **hpl_mailbox** → `terra1fwg35n5esjgny7d8pxnz8usjpwsvpguk0txsy6cnqxy58x9fdlksjpx3p9` | `b6d789c1a31ee79548fd736bad241dbcd3b8b319d66a776f31479743fe49eb01` |
| 11372 | hpl_validator_announce → `terra1gtnmdevekgxpvzej3wfy20e2n335gm3muwj6geduxxa86j3x70cq00asmy` | `c3c42fda7aabb73ab59a6dba75e20a905a310f8876e801451fcebf1599e8167d` |
| 11373 | hpl_ism_aggregate | `e33ccca03a9366c4020900e562febcd8311fc3449687ec876cc7ea8b84767f4f` |
| 11374 | hpl_ism_multisig → inbound ISMs: ETH `terra187rzjc3…neldar` (**6-of-9**) · BSC `terra1nqj7qln…muj9xw` (**4-of-6**) · SOL `terra10s3p36t…ucl50t` (**3-of-5**) — official Hyperlane validator sets | `32b07207c733ba7469f49d321c30cf00bacb8c9560dc92accd35df61e5e3a531` |
| 11375 | hpl_ism_pausable | `31fff431baa0d752f3f9f6c63400bef9c69363cff16d9064a1882fd697b0cacb` |
| 11376 | hpl_ism_routing → `terra1uhzzvt9x3u8hjnkp695hklexx2uywjvfqv454d93ds92sgtpwk7qrpxdg0` (= mailbox **default_ism**) | `0881d65f470425290990e53b87044477eaf704e0f2da8481eb4150c6e8c8143c` |
| 11377 | **hpl_igp** → `terra1taunhg629rssf3g939nqr0h594q5mssrzdj5lkx2hygmxmh72ghqeqqnvz` | `34313c90c9e08d2c342061412fafe4d064ad783f9be606255d0720590e6fad0b` |
| 11378 | hpl_hook_aggregate → default `terra1026v947…vnmvel` (= mailbox **default_hook**) · required `terra1xmdd7yh…0nxq04` (= **required_hook**) | `9dfbe1ba3e0dde5ea82cb0daee819214e46afb2ac78075c4f26523e6879a5004` |
| 11379 | hpl_hook_fee → `terra1sud5xyk…p7j8ag` | `c981467b9af207d09aac90716598ed51c547526b8b82189148a24e1704e7956e` |
| 11380 | hpl_hook_merkle → `terra183lq6yq…yp0n2p` | `f4258979caf115b1957a13f6b7ec59161b837e07b90828c2e6fc9e4e61e9f156` |
| 11381 | hpl_hook_pausable → `terra1x8s9qtw…9tjcnf` | `0f53c4193be46b15eca53ff8cb2004dcc571bf74b345b2b7af2775b6fa99b6c2` |
| 11382 | hpl_hook_routing | `ff11e7535f07cb20123735b61f31bf1b60a428f67cb332faf64a2b7641d11ed3` |
| 11383 | hpl_hook_routing_custom | `34c947fbf2cc37df33237ab062265520fc28d5427745c669631590f22fd9d534` |
| 11384 | hpl_hook_routing_fallback | `b4930c213cae2728b83ffee876d0d880030ed079cc0167fd7e69c98880315f89` |
| 11385 | hpl_test_mock_hook | `8dcdf5f9ef0f7632404b5310b9ed37e091c9854d6fe5e4c38ae3424948a9d3a1` |
| 11386 | hpl_test_mock_ism | `e283df5977a897e0c33f47540f2d50f43f735dfe6f31ef2614aefff225af8c8f` |
| 11387 | hpl_test_mock_msg_receiver | `aa7fca1213b164cb1e8a1beefe32dce6d31f7ebe8add4b568db49283bbdb43af` |
| 11388 | **hpl_igp_oracle** → `terra1j8xzgzk7vds5uzrplmnln4vcz6f205t9atdyflypzrr43cd5eh7scwqj0d` | `3b0143755d322a7a8bcd2e6081c8a22f817644c557c85cfd4d570d69e08de1fc` |
| 11389 | **hpl_warp_cw20** → IGORFAKE collateral `terra1wr7krp8lpfddpzxfkxvmhfnxd06vkz34e7f0tk2vyau36j3d4pvs6pjpel` | `25b100c1c1bec141c90f4fc0e556b52025921403d7ae2d25bad8cfec35c74be7` |
| 11389 | hpl_warp_cw20 → FAKEFAKE collateral `terra1zkkk9km8f6gf5vgn4zf66ep0djztqqkvns8jws8c9f85v4tfxrvq9n2wlk` (2026-08-28; routes: 56 ↔ BSC warp) | same code — `25b100c1c1bec141c90f4fc0e556b52025921403d7ae2d25bad8cfec35c74be7` |
| 11390 | hpl_warp_native | `34b5deb86937f51d4b04ddc572597b95ffd1b3ce094df8a73dc1cf20babc7e55` |
| 11392 | cw20 (IGORFAKE token) → `terra1lpkaaqjaq8zfwktge3vy0zg46nxxsynsge2wxa7addpweu2w6gmsy3lhkr` | `28506f2a3070291f1f2568f271aa5617f0a9d02ef28d98b6804a8b7ba1506d34` |
| 11392 | cw20 (FAKEFAKE token, mirror of IGORFAKE) → `terra1f45rp85m53688ykan8mgjmfyz43d5h7psgawz5n775wde6vrzj5s4tvpwq` (tx `DA1D1E0227FDC64E5164661C310867318C8204A850E252DEA69A5CF339A06BD6`, 2026-08-28) | same code — `28506f2a3070291f1f2568f271aa5617f0a9d02ef28d98b6804a8b7ba1506d34` |

**Wiring (all re-verified on-chain 2026-08-28):** mailbox `default_ism` = ISM
Routing, `default_hook`/`required_hook` = the two Aggregates, inbound ISM validator
sets/thresholds as listed above (unchanged since instantiation) · IGP beneficiary =
relayer-reward-vault `terra1gqkrh2…duzc2q` · IGP-oracle owner = oracle-governor
`terra1z7jmlky…9sv4hj`. Those two contracts (the
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
| Warp FAKEFAKE (HypERC20 proxy, 2026-08-28) | `0x07289a10E1c4E8218AE2ACC599FfC29C68f32C47` | `083b2cd9232be4b42ff640ef331a9c00a994527cce44917374c8021cc6c3e02b` (2882 B — byte-identical to IGORFAKE) |
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
| Warp FAKEFAKE (HypERC20 proxy, 2026-08-28) | `0x959DBb6784182ba5995cCEf6Abe4e378620ADA17` | `083b2cd9232be4b42ff640ef331a9c00a994527cce44917374c8021cc6c3e02b` (2882 B — byte-identical to IGORFAKE) |
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

> ⚠️ **IGORFAKE Solana warp CLOSED on 2026-08-29** — program
> `EPJNrrpCeZGqDPoFtdV9u9uDWBNW3Xqh84LfM7345zcL` was closed
> (`solana program close`, 2.221 SOL rent reclaimed) to fund the LUNC/USTC
> Solana deploys. The program id is now permanently unusable and the TC↔Solana
> IGORFAKE route is discontinued; ~345 synthetic IGORFAKE that were in
> circulation are stranded. The shared ISM/IGP/mailbox rows below are
> production infra and stay live. **Registry cleanup DONE 2026-08-29** (fork
> commit `c8f770db`): the IGORFAKE route file (and the XPTO/XPTV/XPV testnet
> routes) were removed from branch `terra-classic-warp`, so none of them appear
> in the Warp UI anymore. Still pending: removing IGORFAKE/XPTV/XPV from the
> **upstream** hyperlane-registry (merged there via PR #1559) — needs a separate
> upstream PR.

| Piece | Program / account | sha256 (size) |
|---|---|---|
| Warp IGORFAKE (token program) — **CLOSED 2026-08-29** | ~~`EPJNrrpCeZGqDPoFtdV9u9uDWBNW3Xqh84LfM7345zcL`~~ | `d6f2fc9fed82c5079ce2cb1728d5f833d61c70e6d5f2f2a40d5df6d1bdb33419` (318,944 B) |
| SPL mint (IGORFAKE, orphaned) | `CeLHx5Wm9AzuWRnP4URMfNqNa9kDDrnsNGoATCS96QwD` | — (account) |
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
# (EPJNrr… is closed — use a live warp, e.g. LUNC:)
~/hyperlane-monorepo/rust/sealevel/target/release/hyperlane-sealevel-client \
  -u https://api.mainnet-beta.solana.com token query --program-id Dd3ajD8WbEyx7z3HqPnDyvUgFqEBzvF1VePjYd1NGnbr synthetic
```

## 5. LUNC — native coin warp route (complete record, 2026-08-29)

The warp route for the chain's **native coin (uluna)**. Deserves its own full
record: unlike the test cw20s, this collateralizes real LUNC.

### Terra Classic side (collateral, code_id 11390 `hpl_warp_native`)

| Field | Value |
|---|---|
| Warp contract | `terra1m7jcqxfn4hd7q4sywhw508nxshaf078c4vh83y0ts43y9tlp9dcs50cggy` |
| bytes32 (hex) | `0xdfa5801933addbe0560475dd479e6685fa97f8f8ab2e7891eb856242afe12b71` |
| Token type | `native { fungible { denom: "uluna" } }` — mode `collateral` |
| **Owner** | `terra1run9wz09uhh6pu7ggcwwetrgye4wu7wn26mawp` (deployer) — **⚠️ PLANNED: migrate to a multisig account**; owner controls `set_route`/`set_ism`/`set_hook` |
| Contract admin | *(empty — contract is non-migratable)* |
| Routes | `56 → 0x…481095ecEd7A907e7f390b6226F53a66D379e6e2` (BSC) — set_route tx `3A012A09C960896EEB22CBC908881A2C9FF0749E24100787C3519ED82936408C` · `1 → 0x…A4bc47a4C5461eB0E59A585a21A1222EF7544Ac6` (Ethereum) — set_route tx `752F3EA9E3925D3659E50641ADBC6610818FB33E544AC65115CA8B5B93A9BF80` · `1399811149 → 0xbb8812381e07b070e8d37945ae659b8ad17ff2c5c36f019f351f332d45a3b261` (Solana) — set_route tx `14C2BF10D2288940F2D65F3BD3017967B9563CF4CC98E8C314799C72ED65D9DA` |
| data_hash (code 11390) | `34b5deb86937f51d4b04ddc572597b95ffd1b3ce094df8a73dc1cf20babc7e55` (see §1) |

### BSC side (synthetic HypERC20 proxy)

| Field | Value |
|---|---|
| Warp contract | `0x481095ecEd7A907e7f390b6226F53a66D379e6e2` — "Luna Classic" / LUNC / 6 decimals |
| **Owner** | `0x8f085bAD1a15ee9ceeE58C83EFFFa72518975291` (deployer) — **⚠️ PLANNED: migrate to a multisig**; owner controls `setHook`/`setInterchainSecurityModule`/`enrollRemoteRouter` and proxy upgrades via its ProxyAdmin |
| ISM | production 3-of-4 `0xF6b0cDD33A7d2895a3F18b85569Ed9A8278cD151` |
| Hook | production AggregationHook `0xD2c82583C261fce94cD3F97f1dFF9B20a9338164` [merkle + governed IGP] — setHook tx `0x84da30aa…ece36b2` |
| IGP | production `0xEdEd7a4f6FEe4B474B9d7730Bf3465E35E2a4923` (fees → relayer-reward-vault) |
| Router → TC | `132556 → 0xdfa5801933…afe12b71` — enroll tx `0xdcfc2dac…c468f7f` |
| Bytecode sha256 | `083b2cd9232be4b42ff640ef331a9c00a994527cce44917374c8021cc6c3e02b` (2882 B — byte-identical to IGORFAKE/FAKEFAKE proxies) |

### Ethereum side (synthetic HypERC20 proxy)

| Field | Value |
|---|---|
| Warp contract | `0xA4bc47a4C5461eB0E59A585a21A1222EF7544Ac6` — "Luna Classic" / LUNC / 6 decimals |
| **Owner** | `0xEF8181201Ce6C83120035Ffbcc11945E67Ba00ae` (deployer) — **⚠️ PLANNED: migrate to a multisig**; owner controls `setHook`/`setInterchainSecurityModule`/`enrollRemoteRouter` and proxy upgrades via its ProxyAdmin |
| ISM | production 3-of-4 `0x3ba17675f0D319C89D70722f6eb07790DF0B254B` |
| Hook | production AggregationHook `0x912c4d91D9eD04B16B83dA79dbe7a209c8Fd0aA8` [merkle + governed IGP] — setHook tx `0x8e8ca9bf…801b1307` |
| IGP | production `0x9650F1f8DB492750323172145e67Df4e89E964Aa` (fees → relayer-reward-vault) |
| Router → TC | `132556 → 0xdfa5801933…afe12b71` — enroll tx `0xe8e1bd4d…02c6001f` |
| Bytecode sha256 | `083b2cd9232be4b42ff640ef331a9c00a994527cce44917374c8021cc6c3e02b` (2882 B — byte-identical to the BSC LUNC / IGORFAKE / FAKEFAKE proxies) |

### Solana mainnet side (synthetic Sealevel warp, deployed 2026-08-29)

| Field | Value |
|---|---|
| Warp program | `Dd3ajD8WbEyx7z3HqPnDyvUgFqEBzvF1VePjYd1NGnbr` |
| Program hex32 (route set on TC) | `0xbb8812381e07b070e8d37945ae659b8ad17ff2c5c36f019f351f332d45a3b261` |
| Mint (Token-2022) | `8dxTo5reLtvRDx3Q8WEP33Uj2C5u6372EygJdNbsLFKG` — "Luna Classic" / LUNC / 6 decimals, mint authority = the mint PDA itself |
| **Owner** | `BirXd4QDxfq2vx9LGqgXXSgZrjT81rhoFGUbQRWDEf1j` (deployer) — **⚠️ PLANNED: migrate to a multisig** (same handoff plan as the EVM sides) |
| ISM | production 3-of-4 `4MzF7HCfxuwj4EFHqZSEpvkcZZvv1mF37DP4pDHwR5VQ` |
| IGP | production `FLZuKRsfdovLqd8n1AYhPCwLqBjfFyZY3A2edgnjdJoR` / OverheadIgp `FXacR73HiuNyvW7x34KYCDyv8XxM86pz31Ap8t2v3RCJ` — destination gas `3000000` for domain 132556 |
| Router → TC | `132556 → 0xdfa5801933…afe12b71` (enroll-remote-router) |
| Program sha256 | `d6f2fc9fed82c5079ce2cb1728d5f833d61c70e6d5f2f2a40d5df6d1bdb33419` (318,944 B — byte-identical to the reference `hyperlane_sealevel_token.so`; dumped and re-hashed on-chain 2026-08-29) |

> Provenance note: a first LUNC program `4SA1eK3vp9Ez2HvTftyh5k1vL6zkXJyMe6UCaRipECmR`
> was deployed and configured earlier the same day but accidentally closed at 12:11
> (`close-warp-program.sh`); a closed program id can never be redeployed, so the route
> was redone under `Dd3ajD8W…`. The old mint `3NmtMEbR…` (supply 0) is orphaned.

Everything re-verified on-chain 2026-08-29 (routes in BOTH directions on all
three networks, hook, ISM, owner queries — TC `list_routes` = `{1 → 0xA4bc47a4…,
56 → 0x481095ec…, 1399811149 → 0xbb8812…}`; Solana warp `token query` shows
ISM/IGP/destination gas/remote router all set and the LCD route query returns
`bb8812…`). **Live transfers TC ↔ Solana tested both ways 2026-08-29.** Registry
fork updated the same day: `LUNC/terraclassic-bsc-ethereum-solanamainnet` +
`USTC/terraclassic-bsc-ethereum-solanamainnet` published on branch
`terra-classic-warp` (commit `c8f770db`), so the Warp UI serves both routes. Note: an older native-uluna warp (**wlunc**,
`terra1zlm0h2xu…`, owner `terra12awgq…`) exists from a previous generation —
this LUNC route supersedes it for production use.

## 6. USTC — native coin warp route (complete record, 2026-08-29)

Second native coin of the chain (**uusd**). Same structure and shared
production infrastructure as the LUNC route (§5).

### Terra Classic side (collateral, code_id 11390 `hpl_warp_native`)

| Field | Value |
|---|---|
| Warp contract | `terra1qu3x6vhk4y6w6erhmedzfp2ug53qm5nwpyarxveqa7tvwg0telxqvd3ccf` |
| bytes32 (hex) | `0x07226d32f6a934ed6477de5a24855c45220dd26e093a333320ef96c721ebcfcc` |
| Token type | `native { fungible { denom: "uusd" } }` — mode `collateral` |
| **Owner** | `terra1run9wz09uhh6pu7ggcwwetrgye4wu7wn26mawp` (deployer) — **⚠️ PLANNED: migrate to a multisig account**; owner controls `set_route`/`set_ism`/`set_hook` |
| Contract admin | *(empty — contract is non-migratable)* |
| Routes | `56 → 0x…fC067fd98FD123fC2cAd72d040AF60a523274339` (BSC) — set_route tx `4F6B9F079D643A44CE6D3E63CA37BBD18C9D7188BD785F97569B18EFE37B0368` · `1 → 0x…f49408beb319aeCe3E8B3550a5C750C19b3F1e51` (Ethereum) — set_route tx `20BA313D1E3D74C49781123E0422EEE1DB0B0DD18DB7DF998EE9316DE516D1F3` · `1399811149 → 0x5c16beb39b4cce694d11540723116126a83611921f0746efdc2133a3d0ab1966` (Solana) — set_route tx `CE119868BF578706B0A1AA64C87F2552F8B1C3AECA8F738A5B184A30B414F750` |
| data_hash (code 11390) | `34b5deb86937f51d4b04ddc572597b95ffd1b3ce094df8a73dc1cf20babc7e55` (see §1) |

### BSC side (synthetic HypERC20 proxy)

| Field | Value |
|---|---|
| Warp contract | `0xfC067fd98FD123fC2cAd72d040AF60a523274339` — "Terra Classic USD" / USTC / 6 decimals |
| **Owner** | `0x8f085bAD1a15ee9ceeE58C83EFFFa72518975291` (deployer) — **⚠️ PLANNED: migrate to a multisig**; owner controls `setHook`/`setInterchainSecurityModule`/`enrollRemoteRouter` and proxy upgrades via its ProxyAdmin |
| ISM | production 3-of-4 `0xF6b0cDD33A7d2895a3F18b85569Ed9A8278cD151` |
| Hook | production AggregationHook `0xD2c82583C261fce94cD3F97f1dFF9B20a9338164` [merkle + governed IGP] |
| IGP | production `0xEdEd7a4f6FEe4B474B9d7730Bf3465E35E2a4923` (fees → relayer-reward-vault) |
| Router → TC | `132556 → 0x07226d32f6…21ebcfcc` — enroll tx `0xbfdfc072…730417b9` |
| Bytecode sha256 | `083b2cd9232be4b42ff640ef331a9c00a994527cce44917374c8021cc6c3e02b` (2882 B — byte-identical to the LUNC / IGORFAKE / FAKEFAKE proxies) |

### Ethereum side (synthetic HypERC20 proxy)

| Field | Value |
|---|---|
| Warp contract | `0xf49408beb319aeCe3E8B3550a5C750C19b3F1e51` — "Terra Classic USD" / USTC / 6 decimals |
| **Owner** | `0xEF8181201Ce6C83120035Ffbcc11945E67Ba00ae` (deployer) — **⚠️ PLANNED: migrate to a multisig**; owner controls `setHook`/`setInterchainSecurityModule`/`enrollRemoteRouter` and proxy upgrades via its ProxyAdmin |
| ISM | production 3-of-4 `0x3ba17675f0D319C89D70722f6eb07790DF0B254B` |
| Hook | production AggregationHook `0x912c4d91D9eD04B16B83dA79dbe7a209c8Fd0aA8` [merkle + governed IGP] — setHook tx `0x0c3641cf…1e0930e7` |
| IGP | production `0x9650F1f8DB492750323172145e67Df4e89E964Aa` (fees → relayer-reward-vault) |
| Router → TC | `132556 → 0x07226d32f6…21ebcfcc` — enroll tx `0x15c5eb8c…f3e36fb9` |
| Bytecode sha256 | `083b2cd9232be4b42ff640ef331a9c00a994527cce44917374c8021cc6c3e02b` (2882 B — byte-identical to the other HypERC20 proxies) |

### Solana mainnet side (synthetic Sealevel warp, deployed 2026-08-29)

| Field | Value |
|---|---|
| Warp program | `7CUdBt1Qn2R2StE7MDPhQW2EhmnGg8zKK8oJXwAGEoyf` |
| Program hex32 (route set on TC) | `0x5c16beb39b4cce694d11540723116126a83611921f0746efdc2133a3d0ab1966` |
| Mint (Token-2022) | `GNUbsF5mrurtDzNc65HipN5Fyzzzqbj5UonLNhj9frjF` — "Terra Classic USD" / USTC / 6 decimals, mint authority = the mint PDA itself |
| **Owner** | `BirXd4QDxfq2vx9LGqgXXSgZrjT81rhoFGUbQRWDEf1j` (deployer) — **⚠️ PLANNED: migrate to a multisig** (same handoff plan as the EVM sides) |
| ISM | production 3-of-4 `4MzF7HCfxuwj4EFHqZSEpvkcZZvv1mF37DP4pDHwR5VQ` |
| IGP | production `FLZuKRsfdovLqd8n1AYhPCwLqBjfFyZY3A2edgnjdJoR` / OverheadIgp `FXacR73HiuNyvW7x34KYCDyv8XxM86pz31Ap8t2v3RCJ` — destination gas `3000000` for domain 132556 |
| Router → TC | `132556 → 0x07226d32f6…21ebcfcc` (enroll-remote-router) |
| TC → Solana route | `1399811149 → 0x5c16beb3…d0ab1966` — set_route tx `CE119868BF578706B0A1AA64C87F2552F8B1C3AECA8F738A5B184A30B414F750` |
| Program sha256 | `d6f2fc9fed82c5079ce2cb1728d5f833d61c70e6d5f2f2a40d5df6d1bdb33419` (318,944 B — byte-identical to the reference `hyperlane_sealevel_token.so` and to the LUNC program; dumped and re-hashed on-chain 2026-08-29) |

Re-verified on-chain 2026-08-29: routes in BOTH directions on all three
networks — TC `list_routes` = `{1 → 0xf49408be…, 56 → 0xfC067fd9…,
1399811149 → 0x5c16beb3…}`, `routers(132556)` on each synthetic = TC warp hex
— plus hook, ISM and owner queries. **Live transfers TC ↔ Solana tested both
ways 2026-08-29** (same day as LUNC). Note: the older **ustc** warp from the
previous generation (`terra1rnpvpwv…`, owner `terra12awgq…`) is superseded by
this route.

## 7. Maintaining this document

When a new warp is deployed (see [WARP-EVM.md](WARP-EVM.md) /
[WARP-SOLANA.md](WARP-SOLANA.md)): append the new token's addresses + hashes to the
matching section, computed with the verify commands above. The shared
ISM/IGP/hook rows never change with new tokens; validator rotations change the ISM
**contents** (validators list) but not the addresses.
