# Warp Route Solana — Reference Binary & Build Verification

This document is the **canonical reference** for the Solana warp-route program
(`hyperlane-sealevel-token`, synthetic type) deployed by
[`deploy-warp-solana-buffer.sh`](../deploy-warp-solana-buffer.sh).

Its purpose is community trust: instead of trusting a third-party program's
bytecode copied from chain, **the binary is compiled locally from source and its
SHA-256 is published here.** Anyone can rebuild with the pinned toolchain below
and confirm they obtain the same program.

> **The deploy script has no fallback.** It only ever deploys the binary you
> compile locally (`BINARY_SOURCE=build`, the default) or one you already
> compiled yourself (`BINARY_SOURCE=local`). It never dumps or reuses an
> external on-chain program.

---

## 1. Source

| Item | Value |
|------|-------|
| Repository | `hyperlane-monorepo` |
| Commit | `9cdf9eb6dbbbcb552b5607bc87b09db1a9f82d74` |
| Program crate | `programs/hyperlane-sealevel-token` |
| Crate version | `hyperlane-sealevel-token 0.1.0` |
| Manifest | `rust/sealevel/programs/hyperlane-sealevel-token/Cargo.toml` |

---

## 2. Pinned toolchain

The binary was built with the following toolchain. **Reproducing the exact
SHA-256 requires the same versions** — `cargo build-sbf` is not guaranteed to be
bit-for-bit reproducible across differing toolchains or platform-tools releases.

| Tool | Version |
|------|---------|
| Solana CLI (Agave) | `4.0.0` (`src:2a165e7a`, `feat:dda54cf7`) |
| `cargo-build-sbf` | `4.0.0` |
| platform-tools | `v1.53` |
| SBF `rustc` (inside platform-tools) | `1.89.0` |
| Host `cargo` | `1.84.0` |
| Host `rustc` | `1.84.0` |

Check your local versions:

```bash
solana --version
cargo-build-sbf --version
rustc --version
```

---

## 3. Reference binary

| Item | Value |
|------|-------|
| Artifact | `hyperlane_sealevel_token.so` |
| Size | `318944` bytes |
| **SHA-256** | `d6f2fc9fed82c5079ce2cb1728d5f833d61c70e6d5f2f2a40d5df6d1bdb33419` |
| Built | 2026-06-05 |

The deploy script writes this same checksum next to the binary it produces
(`hyperlane_sealevel_token.so.sha256`) and prints it in the run log and in the
final `WARP-<NET>-<TOKEN>-BUFFER.txt` report (`Binary SHA-256:` field).

---

## 4. How to reproduce and verify

```bash
# 1. From the sealevel workspace, compile the token program
cd /home/lunc/hyperlane-monorepo/rust/sealevel
cargo build-sbf --manifest-path programs/hyperlane-sealevel-token/Cargo.toml

# 2. Hash the result
sha256sum target/deploy/hyperlane_sealevel_token.so

# 3. Compare against the reference SHA-256 in section 3
```

If the hash matches, the binary you (or the deployer) are about to publish on
Solana is exactly the audited source at the commit above — no hidden changes.

> **Note on reproducibility.** A matching hash across machines is only expected
> when the full toolchain (Solana CLI, `cargo-build-sbf`, platform-tools, and the
> embedded SBF `rustc`) matches section 2. Different platform-tools releases can
> embed different paths/metadata and change the hash even from identical source.
> For byte-identical cross-machine builds, use a Docker-pinned verifiable build
> (e.g. `solana-verify`) — not yet set up here.

---

## 5. Deploy — recommended two-step flow

Deployment is split into two scripts so that **creating the program** (build +
deploy + publish hash) is separate from **configuring the warp route** (token
init, ISM, IGP, routes). Step 1 produces the program the community verifies;
step 2 wires a warp route to it.

### Step 1 — create the program: `create-warp-program-solana.sh`

Builds the binary locally, publishes its SHA-256, deploys it to Solana, and
reports a fresh **Program ID**. This is the deploy that **replaces the old habit
of dumping bytecode from a third-party program** (e.g.
`Fa4zQJCH7id5KL1eFJt2mHyFpUNfCCSkHgtMrLvrRJBN`) — here you build your own binary
and everyone can verify its hash.

```bash
./create-warp-program-solana.sh                # BINARY_SOURCE=build (default)
```

Outputs, under `warp/reference-program/<network>/`:

| File | Content |
|------|---------|
| `hyperlane_sealevel_token.so` (+ `.sha256`) | the deployed binary and its checksum |
| `REFERENCE-<NET>.txt` | Program ID, hex32, SHA-256, monorepo commit, toolchain, explorer link |
| `reference-<net>.json` | the same, machine-readable |

Useful variables:

```bash
BINARY_SOURCE=local ./create-warp-program-solana.sh   # reuse a compiled .so (skip ~15-20 min build)
SKIP_DEPLOY=1       ./create-warp-program-solana.sh   # build + publish hash only, do not touch chain
PROGRAM_KEYPAIR=<path> ./create-warp-program-solana.sh # deploy under a specific keypair / Program ID
```

### Step 2 — configure the warp route: `deploy-warp-solana-buffer.sh`

Pass the Program ID reported by step 1 so the buffer script **skips build/deploy**
and only runs token init + ISM + IGP + destination gas + enroll + set_route
against that program:

```bash
export TERRA_PRIVATE_KEY="your_hex_private_key"
export WARP_PROGRAM_ID=<Program ID from step 1>
./deploy-warp-solana-buffer.sh
```

> `deploy-warp-solana-buffer.sh` can also do everything in one shot (it builds
> locally by default, `BINARY_SOURCE=build`), generating its own fresh Program ID
> per token. The two-step flow above is preferred when you want a single audited
> reference program + published hash that the community pins to.

In every path the on-chain program gets a **self-generated Program ID** from a
new keypair — this document references *the code* (via SHA-256), not any single
on-chain address.

---

## 6. Community ISM & IGP (Terra Classic domain 132556)

The default Hyperlane ISM (`LwNfVY…`) and IGP (`BhNcatUDC…`) on Solana are owned
by Abacus Works and have **no configuration for the Terra Classic domain**
(no validators in the ISM, no gas oracle in the IGP). A community-run route
therefore deploys its **own** ISM and IGP, built locally and hash-published like
the warp program above. These are **two separate scripts**, run before the warp
init:

> Terra Classic domain is **132556** (from `warp-evm-config.json`
> `.terra_classic.domain`). Both scripts read it from config — do not hardcode.

### `create-warp-ism-solana.sh` — community multisig ISM

Builds `hyperlane-sealevel-multisig-ism-message-id` locally (+ SHA-256), deploys
it, inits it, and sets the Terra Classic **validators + threshold**. Writes
`ism.program_id` into `warp-sealevel-config.json`.

```bash
./create-warp-ism-solana.sh
# override community inputs if needed:
ISM_VALIDATORS=0x..,0x.. ISM_THRESHOLD=2 ./create-warp-ism-solana.sh
```

### `create-warp-igp-solana.sh` — community IGP + gas oracle

Builds `hyperlane-sealevel-igp` locally (+ SHA-256), deploys a **new** IGP program
(or reuse one via `REUSE_IGP_PROGRAM_ID=<addr>`), inits an IGP account +
overhead-IGP account, and sets the Terra Classic **gas oracle + overhead**. Writes
`igp.program_id` and `igp.account` into `warp-sealevel-config.json`.

```bash
./create-warp-igp-solana.sh
# reuse the shared IGP program, only create your own accounts + oracle:
REUSE_IGP_PROGRAM_ID=BhNcatUDC2D5JTyeaqrdSukiVFsEHK7e3hVmKMztwefv ./create-warp-igp-solana.sh
```

### Full order for a community route

**Infrastructure (ISM, IGP) first, warp last.** The warp init consumes
`ism.program_id` and `igp.program_id` from config to point the token at them, so
both must exist *before* the init — otherwise the init would link the old
Abacus-Works defaults that have no Terra Classic config.

```bash
./create-warp-ism-solana.sh        # 1. community ISM  → writes ism.program_id
./create-warp-igp-solana.sh        # 2. community IGP  → writes igp.program_id / igp.account
export TERRA_PRIVATE_KEY=<hex>
./deploy-warp-solana-buffer.sh     # 3. warp: builds+deploys the token PROGRAM, inits it,
                                   #    then links ism.*/igp.* from config, enroll + set_route
```

Optional — deploy the token program as a standalone, hash-published reference
*before* the warp init (otherwise the buffer script builds+deploys it itself):

```bash
./create-warp-ism-solana.sh
./create-warp-igp-solana.sh
./create-warp-program-solana.sh                 # standalone program → WARP_PROGRAM_ID + SHA-256
export WARP_PROGRAM_ID=<from create-warp-program-solana.sh>
export TERRA_PRIVATE_KEY=<hex>
./deploy-warp-solana-buffer.sh                  # skips build/deploy, just init + link + route
```

Steps 1–2 write their addresses into `warp-sealevel-config.json`, so the warp init
(`deploy-warp-solana-buffer.sh` STEP 4/5/6) automatically points the warp token
at the community ISM and IGP — no dumping, no dependency on Abacus-Works-owned
per-domain config. Each script also drops a `REFERENCE-*.txt` with the program
IDs, SHA-256, and Terra Classic parameters for the community to verify.

> Legacy note: `setup-ism-igp-terraclassic.sh` does ISM+IGP in one combined script
> and **dumps** the ISM bytecode from a third-party program. The two scripts above
> supersede it — they build locally, publish hashes, and keep ISM and IGP separate.

### Testnet (Solana testnet ↔ Terra Classic rebel-2, domain 1325)

Each script has a `*-testnet.sh` launcher that presets the testnet context
(`NET_KEY=solanatestnet`, Terra domain **1325**, rpc `https://rpc.luncblaze.com`,
chain-id `rebel-2`) and delegates to the same underlying script — identical logic,
only the network/domain differ:

```bash
./create-warp-program-solana-testnet.sh
ISM_VALIDATORS=0x<rebel2-validator> ./create-warp-ism-solana-testnet.sh   # ⚠ testnet validator likely differs
./create-warp-igp-solana-testnet.sh
./deploy-warp-solana-buffer-testnet.sh                                    # Solana side only (see below)
```

Notes:
- **Domain is 1325 on testnet, 132556 on mainnet** — do not mix them. The
  underlying scripts read the domain from an env override the launcher provides.
- `create-warp-ism-solana-testnet.sh` defaults `ISM_VALIDATORS` to the Terra
  Classic **rebel-2** validator `0x133fd7f7094dbd17b576907d052a5acbd48db526`
  (threshold 1). Override only if the validator set changes.
- Testnet Solana mailbox `75HBBLae3ddeneJVrZeyrDfv6vb7SMC3aCpBucSXS5aR` is set in
  `warp-sealevel-config.json` under `networks.solanatestnet.mailbox`.

**Terra Classic rebel-2 block (`terra_classic_testnet` in `warp-evm-config.json`):**
The buffer testnet launcher sets `TERRA_CFG=.terra_classic_testnet`, so the buffer
script reads Terra data from this dedicated rebel-2 block instead of the mainnet
one. Core rebel-2 contracts are filled in (real, from the testnet deployment doc):

| Contract | rebel-2 address |
|----------|-----------------|
| mailbox | `terra1rqg3qfkfg5upad9xu6zj5jhl626qy053s7rn08829rgqzv2wu39s5la8yf` |
| igp | `terra1n70g3vg7xge6q8m44rudm4y6fm6elpspwsgfmfphs3teezpak6cs6wxlk9` |
| igp_oracle | `terra18tyqe79yktac6p3alv3f49k06xqna2q52twyaflrz55qka9emhrs30k3hg` |
| ism_routing | `terra1h4sd8fyxhde7dc9w9y9zhc2epphgs75q7zzfg3tfynm8qvpe3jlsd7sauh` |
| ism_multisig_sol | `terra1d7a52pxu309jcgv8grck7jpgwlfw7cy0zen9u42rqdr39tef9g7qc8gp4a` |

Per-token warp routes are **placeholders** (`deployed: false`, empty
`warp_address`/`warp_hexed`/`collateral_address`) because they are not yet deployed
on rebel-2. The buffer script auto-skips enroll/set_route for a token until you:

1. Deploy that token's warp contract on rebel-2, then
2. Fill `warp_address` + `warp_hexed` + `collateral_address` and set
   `deployed: true` under `.terra_classic_testnet.tokens.<key>`.

After that, `deploy-warp-solana-buffer-testnet.sh` runs enroll-remote-router and
set_route for that token automatically — no code change needed.

---

_When the source commit or toolchain changes, rebuild and update sections 1–3
with the new commit, versions, size, and SHA-256 so the reference stays accurate._
