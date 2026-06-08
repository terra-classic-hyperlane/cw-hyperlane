# Funding Proposal — Hyperlane Warp Routes Deployment on Solana Mainnet

> **Author:** Igor Veras (`terra10d07y265gmmuvt4z0w9aw880jnsr700juxf95n`)  
> **Date:** 2026-06-07  
> **Category:** Infrastructure / Interoperability  
> **Status:** Awaiting community approval

---

## Transparency Note

I would like to apologize to the community for not disclosing these costs in the original proposal that requested authorization to carry out this Hyperlane integration work with Terra Classic.

During Solana testnet testing, I had already noticed that program deployment costs were significantly higher than on EVM networks. However, I believed the cost would be different on mainnet — which turned out to be a surprise: the rent-exempt cost on Solana Mainnet is equivalent to testnet in SOL terms, but with SOL priced at ~$65 USD at the time, the real financial impact was far higher than expected.

I acknowledge this information should have been raised and communicated beforehand. This proposal is the way to correct that gap transparently, with all data available for the community to evaluate.

---

## Executive Summary

This proposal requests funding to cover the deployment of 5 Solana programs required to activate **Hyperlane Warp Routes** between Terra Classic and Solana Mainnet — enabling trustless, non-custodial bridging of **LUNC** and **USTC**.

The main cost is the **rent-exempt reserve** required by Solana to keep programs on-chain. After the initial deployment, any future reconfiguration via governance costs only a minimal transaction fee (~0.00025 SOL), with no new deployments required.

---

## 1. What Has Already Been Done — Personal Investment

Before requesting any resources from the community, all integration and configuration work on **Ethereum, BSC, and Terra Classic** was completed and fully funded from personal resources. **No compensation will be requested for these already-incurred costs.**

### 1.1 Terra Classic — ~20 Contracts Deployed (Personal Cost)

Hyperlane **had no integration with Terra Classic**. The entire infrastructure had to be deployed from scratch:

| Group | Contracts | Description |
|-------|-----------|-------------|
| Core Hyperlane | Mailbox, ISM, IGP, Hook, Validator Announce | Cross-chain protocol foundation |
| Warp Routes | CwHypNative (LUNC), CwHypNative (USTC), CwHypCw20 (multiple tokens) | Bridge routes |
| Governance | On-chain configuration and ownership transfer | Decentralized control |

The 13 core Hyperlane contracts were deployed on Terra Classic Mainnet (columbus-5), covering all infrastructure needed for cross-chain communication with Ethereum, BSC, and Solana:

| # | Contract | Function | Address |
|---|----------|----------|---------|
| 1 | Mailbox | Central cross-chain messaging hub | `terra1qeutmjcnwmhmumv4xlzrqmva0m4usdw6lt7mayk7wfw7gftsv6wq2xnxh5` |
| 2 | Validator Announce | Public validator registry | `terra1jg7904q2305f8qm6ph8jz95uez7undc57wd4dgaf9mvfxcw5j9wq3zdn8c` |
| 3 | ISM Multisig — Ethereum | Validates messages received from ETH (domain 1) | `terra16axf5f8pqjz3kap0hmrwhatav2q8yrngn6f9vrzx0ralypzxw47s9tml5u` |
| 4 | ISM Multisig — BSC | Validates messages received from BSC (domain 56) | `terra16hqg4napp3vypdvyymzd3sdsc3uewhyctxjng79j67lku27a5r7q4z8lnt` |
| 5 | ISM Multisig — Solana | Validates messages received from Solana (domain 1399811149) | `terra180s622shslcldkrl93ksaddhnfvvclejvgt70xsz8flphwzc3fcqkn7m09` |
| 6 | ISM Routing | Routes messages to the correct ISM by origin | `terra1gd3re2pmv34ruwlmmhq80qtp6xqt8htgjqdvsj6clzh0wef6s7mqt6p5ka` |
| 7 | Hook Merkle | Generates cryptographic proof for each sent message | `terra1edwd2rhpzhl73uyqf24cc8zp0j5leuc72m7dxtmgfcgvpypj6afsryacf5` |
| 8 | IGP | Charges and manages gas for destination execution | `terra1f6n8asv4ecqjjhvf57cprgcjwzd4y2mncpp6gcc95gd22mljnrcs3gcgkk` |
| 9 | IGP Oracle | Provides LUNC/ETH/BNB/SOL rates for fee calculation | `terra14yp4fvjx9llussdy7ghpu3gszrdfr0q3v53qcy4lkxzs2wc5dngq9zlux2` |
| 10 | Hook Aggregate #1 | Aggregates Hook Merkle + IGP (standard flow) | `terra1vtxef5jzax9uaktygay7nnl48akxekt94yg6ak4xa7unawp3du2qevkgde` |
| 11 | Hook Pausable | Allows emergency pause of outbound messages | `terra162q4qzmdy5rutkpkxwqw5xlw0vdjg8c7gw0njnk6ma2s8j52arhsgv3u29` |
| 12 | Hook Fee | Charges a fixed fee per sent message | `terra1w8923j0nfvahxcsllqqslwqc0wj22673tf25exwx2vm8dag2a86sk2mdv0` |
| 13 | Hook Aggregate #2 | Aggregates Hook Pausable + Fee (required flow) | `terra1n5wfxj38y5ejkh9kkz4ud7t6gqqshzhhhcu97j2j0kfa4359za8sdsqexu` |

### Uploaded Binaries (Code IDs)

Before instantiating the contracts, **20 WASM binaries** had to be uploaded to the Terra Classic network. Each upload is an independent on-chain transaction:

| # | Binary | Code ID | TX Hash |
|---|--------|---------|---------|
| 1 | hpl_mailbox | 11371 | `EE52306E16EB9A3D434219ECA0BDF838761B6ED7FDA4EBCA27E6072EAF7F3246` |
| 2 | hpl_validator_announce | 11372 | `EA29FACCCDFED7F54E5C7CC28E631C9DCD6EF3B6711BDED6611C6D6062E3C435` |
| 3 | hpl_ism_aggregate | 11373 | `7DD1BDB4EC4B57DBAC835087E1328EB6B201EF07BB5C4C5850A92A9FE3B615AA` |
| 4 | hpl_ism_multisig | 11374 | `B0F1C5CF22F5A55185E9CC79DFBF1DB97681BABAFC98ECC7F16F1EFF5AB3C1D1` |
| 5 | hpl_ism_pausable | 11375 | `6F5283B1D2FF2C2F8AB3E3F7209A3BDBA4E5916621B2C596A7A2946D07696A58` |
| 6 | hpl_ism_routing | 11376 | `523D8DD5AADDFD533F8C61AC651F6DAC76E88E8625FE9364D8035381912E1A9A` |
| 7 | hpl_igp | 11377 | `C81D18B9C7729209D379E929B85BFBC2FAF410748ADCF6F320541CFFBF19686E` |
| 8 | hpl_hook_aggregate | 11378 | `97814830E9459ABE12A99C82F8B6D65AF28282EDEB1B56B5C27BA83A0F51F681` |
| 9 | hpl_hook_fee | 11379 | `4E08DA612B3E89AC5CA71CF3B4099B3B1B5800190B814EF65F92A7327B839C51` |
| 10 | hpl_hook_merkle | 11380 | `F8004659796F3EED60623944C4A9C6938975FF72B0D626BE379BC994B7058D29` |
| 11 | hpl_hook_pausable | 11381 | `0694354D4312B965F45D4ED14372925D23AD6F0F1A217245E9EDFCFECE699F85` |
| 12 | hpl_hook_routing | 11382 | `6799A20AFD9C69F7D3BB41B078EE4FBDC5241CC0B41C192721F9325B2A66696A` |
| 13 | hpl_hook_routing_custom | 11383 | `56300AD82FB441094678272A34B1AF131AC69DF04277242FD17C1758F797E574` |
| 14 | hpl_hook_routing_fallback | 11384 | `8B18DB2D65A81F40A4AB896E9C58E3BB9C251B272928575EC787EA13B20838D0` |
| 15 | hpl_test_mock_hook | 11385 | `04F546649FC718DCBA701A9767395CEBD120C3DED9A266EE723F9751F60923D7` |
| 16 | hpl_test_mock_ism | 11386 | `EBEB7221C86FAD9C1449713357F78B14E10510AC87C0A46D0BC1EA717ABC4017` |
| 17 | hpl_test_mock_msg_receiver | 11387 | `E1F27D012F1575BC54A4E0A2714FC1A967789BAA5210FCCF6515868D3F56579B` |
| 18 | hpl_igp_oracle | 11388 | `C367D2C70F87D6B10F3CFCF7B3105BCA774C22890B67CE69BB4F36DA759B7E9D` |
| 19 | hpl_warp_cw20 | 11389 | `AD2C0B4E55BA7A3D4817DE9D95CA17A3E6D9B72A61F70B98485C39412D778926` |
| 20 | hpl_warp_native | 11390 | `F5BCFCDE48617B6B4A70E57B7F0B5376FC3B192B343D0A203F46F8627CF54D2D` |

**Total: 20 binaries uploaded + 13 contracts instantiated = 33 on-chain transactions on Terra Classic**, all funded from personal resources.

For the full details of each contract, audit hashes, and deployment transactions, see the complete documentation:  
📄 [HYPERLANE_DEPLOYMENT-MAINNET_EN.md](https://github.com/terra-classic-hyperlane/cw-hyperlane/blob/main/terraclassic/doc/HYPERLANE_DEPLOYMENT-MAINNET_EN.md)

> All contracts were deployed directly from personal resources. Each transaction hash has been documented and made publicly available for audit purposes — any developer can verify that the original code was not modified. Once all configuration is complete, the **owner** account will be transferred to the Terra Classic governance account (`terra10d07y265gmmuvt4z0w9aw880jnsr700juxf95n`), ensuring decentralized control of the infrastructure.

### 1.2 Ethereum and BSC — Fully Configured (Personal Cost)

The Ethereum and BSC networks are already **fully configured and operational**, with all infrastructure contracts deployed and tested:

| Network | Deployed Contracts | Approximate Cost |
|---------|--------------------|-----------------|
| Ethereum Mainnet | ISM, IGP, Oracle, Hook Aggregation, Warp IGORFAKE | ~$12 USD |
| BSC Mainnet | ISM, IGP, Oracle, Hook Aggregation, Warp IGORFAKE, Warp ZTT | included in ~$12 USD |

> The total cost on ETH and BSC was approximately **$12 USD** — an accessible amount I was able to cover without burdening the community.

### 1.3 Why Solana Is Different

On EVM networks (Ethereum/BSC), configuration contracts (ISM, IGP, Oracle) cost only a few dollars in gas. On Solana, each **program** requires a rent-exempt deposit proportional to the size of the compiled binary — which raises the cost to tens or hundreds of dollars per program.

| Network | Avg. cost per config contract | Warp cost per token |
|---------|-------------------------------|---------------------|
| Ethereum / BSC | $1–3 USD | project owner's responsibility |
| Terra Classic | ~$0.10 USD (in LUNC) | ~$0.10 USD |
| **Solana** | **$45–200 USD** | **$70–200 USD** |

> **Important note:** On EVM networks and Terra Classic, the **warp route** (the token contract itself) is the responsibility of each project owner — the Terra Classic community only covers shared infrastructure contracts. In the case of Solana, since **LUNC and USTC are native Terra Classic tokens**, it falls to the community to also fund the warp programs for these two tokens.

---

## 2. Context and Proof of Concept

### 2.1 Test Conducted with IGORFAKE

To validate technical feasibility before requesting community resources, I conducted a **full test** using the IGORFAKE token (personal test token):

| Item | Address | Value |
|------|---------|-------|
| Warp Program (closed) | `Hs4FrEgigJaabS5HtdkzceFdCPNmPhntWbbdWBJcXyCn` | 2.22105432 SOL |
| ProgramData (closed) | `4emPmRNLtcdZmtJyfSqGteoDJSApVTGaUL37cFrb3auY` | — |
| IGORFAKE Mint | `5s6DL6pYGxLNXNf1U915BLzLxNkRjnWCzqyzEfXuYDQT` | 0.00405768 SOL |
| ISM Buffer (failed) | `8keKF8ouqxsmQKZ2Yo3RfzGJQxFjk1MDsECCATUd37CV` | 0 SOL |

> **Important:** If you look up the warp program address in the explorer, the balance appears as zero. This is because after the test I **closed the program** with `solana program close`, which returned the 2.22 SOL to my wallet. **The program can no longer be used under any circumstances** — even though the address exists in the explorer, the code has been destroyed and the program is inactive. Any future use requires re-uploading the binary with a new address.

### 2.2 Test Results

- ✅ Warp program deployed successfully
- ✅ Synthetic token mint created on Solana
- ✅ Terra Classic ↔ Solana route configured and functional
- ❌ ISM deployment failed due to **insufficient balance** (~1.35 SOL needed, 0.93 SOL available)
- ✅ **2.22105432 SOL recovered** after closing the test program
- ⚠️ **0.00114144 SOL permanently locked** in the program account (Solana limitation — non-recoverable)

---

## 3. Programs to Deploy

### 3.1 Program Architecture

Solana requires each binary program to occupy an account with a minimum rent-exempt balance proportional to the code size. The values below are calculated from real data measured during the test:

| # | Program | Function | Size | Estimated Cost |
|---|---------|----------|------|----------------|
| 1 | **ISM** (MultisigIsmMessageId) | Validates messages received from Terra Classic | 194,344 bytes | ~1.35 SOL |
| 2 | **Warp LUNC** (HypSynthetic) | Bridges LUNC between Terra Classic ↔ Solana | 318,944 bytes | ~2.22 SOL |
| 3 | **Warp USTC** (HypSynthetic) | Bridges USTC between Terra Classic ↔ Solana | 318,944 bytes | ~2.22 SOL |
| 4 | **IGP** (InterchainGasPaymaster) | Cross-chain gas payment management | 248,080 bytes | ~1.73 SOL |
| 5 | **Oracle** (Gas Oracle) | Price feed for fee calculation | — | ~0.01 SOL |

> **Note on ISM:** Once deployed, the same ISM is **shared by all tokens** (LUNC, USTC and future ones). There is no need to deploy a separate ISM per token.

### 3.2 Total Cost

```
Full own deployment (complete governance sovereignty):
  ISM:          ~1.35 SOL
  Warp LUNC:    ~2.22 SOL
  Warp USTC:    ~2.22 SOL
  IGP:          ~1.73 SOL
  Oracle:       ~0.01 SOL
  Fees/txs:     ~0.05 SOL
  ──────────────────────────
  Total:        ~7.58 SOL
```

We will not use Hyperlane Labs' native programs — the Terra Classic community will have **full control** over validators, gas fees, and oracle configurations, with no third-party dependency.

### 3.3 Future Maintenance Cost

After the initial deployment, any governance change (updating validators, adjusting gas fees, updating oracle) costs only:
- **~0.00025 SOL per transaction** (network fee)
- **No new program deployments required**

---

## 4. Technical References

### 4.1 Reference Programs on Solana Mainnet

| Program | Address | Status |
|---------|---------|--------|
| Hyperlane Mailbox | `E588QtVUvresuXq2KoNEwAmoifCzYGpRBdHByN9KQMbi` | active |
| Hyperlane IGP | `BhNcatUDC2D5JTyeaqrdSukiVFsEHK7e3hVmKMztwefv` | active |
| IGP Account | `AkeHBbE5JkwVppujCQQ6WuxsVsJtruBAjUo6fDCFp6fF` | active |
| Reference ISM | `LwNfVYMDzAe5dCJgA5CipTZcT34Eyf74zLr81K91jxk` | active (external owner) |

### 4.2 Warp Routes Already Deployed (Terra Classic Testnet)

Testnet routes are operational, validating the full stack:

| Token | Terra Classic Testnet | Solana Testnet |
|-------|-----------------------|----------------|
| LUNC | `terra1zlm0h2xu6rhnjchn29hxnpvr74uxxqetar9y75zcehyx2mqezg9slj09ml` | `HNxN3ZSBtD5J2nNF4AATMhuvTWVeHQf18nTtzKtsnkyw` |
| USTC | `terra1rnpvpwvqcf94keldtm2udt4tqhwthpw5cu94m443rz5ue7rvvkjq9nklml` | `7PtxvK2AB8TmhygeWDyVjkCKvBST16QFb8j6tdSLtoha` |

### 4.3 Validator Configuration

The protocol operates with **multiple independent validators** to ensure decentralization and security. The validator used during testing was the deployer itself, with a 1/1 threshold. As external validators complete their infrastructure, the ISM will be updated to include them — an operation that costs only a transaction fee, with no new deployment required.

| Validator | Status | Address |
|-----------|--------|---------|
| Deployer (test) | ✅ Active from the start | `0x71b2b8c36a0c76b74be92eb7915e26a69b3b03eb` |
| @Thomas_HighStakes | ✅ Infrastructure complete | pending inclusion in ISM |
| Validator 3 | 🔄 Setting up infrastructure | — |
| Validator 4 | 🔄 Setting up infrastructure | — |

> The ISM will be updated to the full validator set once all validators complete their infrastructure setup. The final threshold will be defined together with the validators. This update requires no new program deployment — only a configuration transaction.

| Field | Current value (test) |
|-------|----------------------|
| Terra Classic Mainnet Domain | `1325` (columbus-5) |
| Current threshold | 1/1 (deployer only) |
| Target threshold | to be defined with all 4 validators |

---

## 5. How It Works After Deployment

```
Terra Classic (LUNC/USTC)          Solana Mainnet
        │                                │
        │  1. lock/burn on TC warp       │
        │ ─────────────────────────────► │
        │                                │  2. ISM verifies validator
        │                                │     signature
        │                                │  3. mint/release on Solana warp
        │                                │
        │  4. burn on Solana warp        │
        │ ◄───────────────────────────── │
        │  5. release on TC warp         │
        │                                │
```

- **Warp LUNC/USTC:** programs that lock tokens at origin and mint synthetic tokens at destination
- **ISM:** cryptographically verifies that the message originated from Terra Classic (validator signature)
- **IGP:** charges and manages the gas fee for execution at the destination
- **Oracle:** provides the SOL/LUNC price feed for correct fee calculation

---

## 6. Funding Request

### 6.1 Amount Requested

| Item | Amount (SOL) | Notes |
|------|-------------|-------|
| ISM program | 1.35 | One-time deploy, shared by all tokens |
| Warp LUNC | 2.22 | Required per token |
| Warp USTC | 2.22 | Required per token |
| IGP program | 1.73 | Full governance control |
| Oracle + PDA accounts | 0.06 | Init + configurations |
| Safety buffer | 0.50 | Fees, retries and contingencies |
| Contingency reserve | 1.00 | Unexpected costs, SOL price fluctuation |
| **Total in SOL** | **9.08 SOL** | |

### 6.2 Conversion to LUNC

The community will send **LUNC** directly to my wallet. The amount was calculated using **$70/SOL** as a conservative reference, given SOL's high volatility and the time the proposal may take to be approved.

| Reference | Value |
|-----------|-------|
| SOL price used (conservative) | $70.00 USD |
| LUNC price on 2026-06-08 | $0.00007006 USD |
| Total in USD (9.08 SOL × $70) | $635.60 USD |
| **Total requested in LUNC** | **≈ 9,072,794 LUNC** |

> **On volatility:** SOL was trading at $66.87 USD on 2026-06-08. The $70/SOL rate was used to cover a potential price increase before approval. On the day of the SOL purchase I will publish the transaction hash. **If any LUNC remains**, it will be sent directly back to the community — **it will not be converted, it will be returned as LUNC**.

### 6.3 Destination of Funds

Funds should be sent in **LUNC** to the Terra Classic wallet:

```
terra1run9wz09uhh6pu7ggcwwetrgye4wu7wn26mawp
```

The LUNC received will be converted to SOL on the day of purchase and used exclusively for program deployment. The conversion will be documented with the transaction hash for full accountability. Any remaining LUNC will be returned directly to the community.

---

## 7. Transparency and Accountability

- All code is publicly available: [github.com/terra-classic-hyperlane/cw-hyperlane](https://github.com/terra-classic-hyperlane/cw-hyperlane)
- Deployed program addresses will be published immediately after each deployment
- Deployment scripts are auditable in the `terraclassic/` folder of the repository
- Deployed programs will be transferred to governance control (`terra10d07y265gmmuvt4z0w9aw880jnsr700juxf95n`)

### 7.1 SOL Purchase Accountability Report

A complete report will be published containing:

1. **LUNC → SOL purchase TX** — transaction hash of the conversion from the community's LUNC to SOL, evidencing the exchange rate used and the amount received
2. **TX for each deployment** — transaction hash of each deployment on Solana Mainnet, with the resulting program address and exact SOL cost
3. **Final wallet balance** — public statement of wallet `BirXd4QDxfq2vx9LGqgXXSgZrjT81rhoFGUbQRWDEf1j` after all deployments are complete

**If SOL remains:** any balance left in the wallet after full deployment will be sent directly to the Terra Classic governance account (`terra10d07y265gmmuvt4z0w9aw880jnsr700juxf95n`). No value will be retained.

---

## 8. Timeline

| Step | Estimated Timeframe |
|------|---------------------|
| Proposal approval | — |
| Receipt of funds | Immediately after approval |
| ISM deployment | Day 1 |
| Warp LUNC deployment | Day 1 |
| Warp USTC deployment | Day 2 |
| IGP + Oracle deployment | Day 2 |
| Final mainnet testing | Day 3 |
| Handover to governance | Day 3–5 |

---

## 9. FAQ

**Why not reuse the IGORFAKE test programs?**  
The program `Hs4FrEgigJaabS5HtdkzceFdCPNmPhntWbbdWBJcXyCn` was closed with `solana program close` to recover the invested SOL. After closing, the program is **permanently inactive** — the address may be visible in the explorer but contains no executable code. A new binary must be uploaded with a new address.

**Is the rent lost?**  
No. The rent remains locked while the program exists and is **fully recoverable** via `solana program close`. Exception: 0.00114144 SOL from the program account pointer (non-recoverable due to Solana limitations — an insignificant residual amount).

**Why does Solana charge so much?**  
The rent-exempt reserve is a guarantee of permanent data availability on the network. It is a one-time infrastructure cost, not a recurring fee.

**What if validators need to be updated?**  
A single transaction of ~0.00025 SOL on the already-deployed ISM is sufficient. No new program deployment is required.

---

*Proposal by Igor Veras — Hyperlane Terra Classic Developer*
