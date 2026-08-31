# Create a Warp Route — Solana (Sealevel) ↔ Terra Classic

> One script: `terraclassic/create-warp-sealevel.sh`. It deploys **only the token's
> own program**; ISM and IGP are the production ones, SET on the new warp — nothing
> else is created. Full reference: [`../archive/create-warp-sealevel-guide.md`](../archive/create-warp-sealevel-guide.md).

## 1. What gets deployed vs reused (mainnet, verified on-chain 2026-08-28)

| Piece | New token on Solana |
|---|---|
| Warp token program + SPL mint | 🆕 deployed (`hyperlane-sealevel-token` + metadata) |
| Collateral warp on Terra Classic | 🆕 deployed |
| ISM | ♻️ reused: `4MzF7HCfxuwj4EFHqZSEpvkcZZvv1mF37DP4pDHwR5VQ` (mutable MultisigISM, same 3-of-4 validator set as BSC/ETH) |
| IGP | ♻️ reused: program `FLZuKRsfdovLqd8n1AYhPCwLqBjfFyZY3A2edgnjdJoR` + **OverheadIgp** `FXacR73HiuNyvW7x34KYCDyv8XxM86pz31Ap8t2v3RCJ` — fees → pod pool PDA (relayer-reward-vault), prices governed |
| Destination gas (TC) | `3000000` (matches the live LUNC/USTC warps) |

⚠️ The IGP account type is **`overhead-igp`** (from `warp-sealevel-config.json`) —
setting it as plain `igp` would quote gas without overhead and underpay the relayer.
The script reads it from the config since 2026-08-28.

There is **no AggregationHook on Solana** — the sealevel architecture handles the
merkle insertion in the mailbox itself.

## 2. Prerequisites

### 2.1 Tools — with install commands

| Tool | Min version | Install |
|---|---|---|
| Solana CLI (Agave) | **3.0+** | `sh -c "$(curl -sSfL https://release.solana.com/stable/install)"` then `agave-install init 3.0.14` |
| Rust / cargo | **1.86+** | `curl https://sh.rustup.rs -sSf \| sh` |
| Node.js + the `@cosmjs` packages | 18+ | `cd ~/tc-cw-hyperlane && npm install @cosmjs/cosmwasm-stargate @cosmjs/proto-signing` (used for the TC `set_route`) |
| `jq`, `python3` | — | `sudo apt install jq python3` |

### 2.2 Build the sealevel client + token program (once, ~15 min)

```bash
# 1. The Rust client the script drives:
cd ~/hyperlane-monorepo/rust/sealevel
cargo build --release
# → target/release/hyperlane-sealevel-client

# 2. The warp token program (.so) that gets deployed:
cd programs && bash build-programs.sh token
# → ../target/deploy/hyperlane_sealevel_token.so
```

**Skip the .so build** by copying the community-verified prebuilt binary instead
(sha256 `d6f2fc9fed82c5079ce2cb1728d5f833d61c70e6d5f2f2a40d5df6d1bdb33419` —
byte-identical to the live LUNC/USTC programs):

```bash
cp ~/tc-cw-hyperlane/terraclassic/warp/reference-program/solanamainnet/hyperlane_sealevel_token.so \
   ~/hyperlane-monorepo/rust/sealevel/target/deploy/
sha256sum ~/hyperlane-monorepo/rust/sealevel/target/deploy/hyperlane_sealevel_token.so  # must match
```

### 2.3 Keys and funding

- A Solana keypair json with **≥ 3 SOL**. Real mainnet cost: **~2.28 SOL** —
  2.221 rent of the program (recoverable only by closing, which kills the
  program id **permanently**) + 0.05 for the ATA payer + negligible fees.
  The CLI demands rent **plus the worst-case fee estimate up front**, so with a
  hot network it can require ~2.8+ SOL to even start — see §2.4.
- `export TERRA_PRIVATE_KEY="hex_no_0x"` (TC warp owner) — without it the script
  skips the TC `set_route` (STEP 6) and prints the manual command.

### 2.4 RPC — a private endpoint is mandatory on mainnet

The public `api.mainnet-beta.solana.com` rate-limits (`429`) and stalls program
deploys. Use **Helius** (the free tier is enough for occasional deploys),
QuickNode or Triton, set as `networks.solanamainnet.rpc` in
`warp-sealevel-config.json` (fallbacks rotate automatically between retries).
If the network's priority fee is spiking, pin a low one and let the retries do
the work: `DEPLOY_CU_PRICE=200000 ./create-warp-sealevel.sh`.

## 3. Add your token to the config

**The token is defined ONCE, in `warp-evm-config.json` → `terra_classic.tokens`**
(the same §3.1 of [WARP-EVM.md](WARP-EVM.md)) — the sealevel script reads its menu
from there too. If you already added the token for BSC/ETH, there is nothing new
to define.

The only Solana-specific piece **you** provide is the metadata file: commit
`warp/solana/metadata-mytoken.json` (name/symbol/description/image) to the repo —
the URI must resolve (HTTP 200) at deploy time, or the deploy runs without
on-chain metadata.

Everything in `warp-sealevel-config.json` → `networks.<net>.warp_tokens.mytoken`
is **deployment state, created and filled BY THE SCRIPT** (like WARP-EVM §3.2 —
do not write it):

| Field | What it records | Filled by |
|---|---|---|
| `program_id` | the warp token program deployed on Solana | script, after `warp-route deploy` |
| `mint_address` | the SPL mint created by the warp | script, after deploy |
| `metadata_uri` | the resolved metadata URI actually used | script |
| `deployed` | whether this token exists on this Solana network | script |

Do **not** touch `ism`/`igp` in the config — production defaults (§1).

## 4. Run — example (mainnet)

```bash
cd ~/tc-cw-hyperlane/terraclassic
export TERRA_PRIVATE_KEY="hex_no_0x"
./create-warp-sealevel.sh          # interactive: pick token + solanamainnet
```

Expected flow (this is how the live LUNC and USTC routes were created):
`STEP 1` **pure `solana program deploy`** of `hyperlane_sealevel_token.so` under a
fresh program keypair (network-sampled priority fee, buffer reused between
retries, `--max-sign-attempts 200`, RPC rotation) →
`STEP 1B` **atomic MEV-safe init** via `jito-warp-init.js` — `warp_init` +
`InitializeMetadataPointer` + `InitializeMint2` in a **single transaction**, then
Token-2022 metadata and mint authority handed to the mint PDA itself →
`STEP 2` `token set-interchain-security-module --ism 4MzF7HCf…` →
`STEP 3` `token igp set FLZuKRs… overhead-igp FXacR73…` →
`STEP 4` `destination gas 132556 = 3000000` →
`STEP 5` enroll remote router (Solana → TC) →
`STEP 6` `set_route` on the TC warp (TC → Solana; needs `TERRA_PRIVATE_KEY`) →
`STEP 7–8` on-chain verification → `STEP 9` generates the registry route YAML
(`warp/registry-<token>-config.yaml`) ready for the Warp UI PR.

> ⚠️ **Never use the client's `warp-route deploy` on mainnet.** Its init path
> fails creating the mint PDA (`IncorrectProgramId`) and leaves the program
> half-initialized — the only remedy is `solana program close` + a redeploy under
> a **new** keypair (a closed program id can never be reused, and its rent PDAs
> are orphaned). The script's STEP 1 + 1B flow exists precisely to avoid this.

Verify the result exactly like the audit does:

```bash
~/hyperlane-monorepo/rust/sealevel/target/release/hyperlane-sealevel-client \
  -u https://api.mainnet-beta.solana.com token query --program-id <WARP_PROGRAM_ID> synthetic
# interchain_security_module = 4MzF7HCf… · interchain_gas_paymaster = (FLZuKRs…, OverheadIgp(FXacR73…))
# destination_gas = {132556: 3000000} · remote_routers = {132556: <TC warp hexed>}
```

## 5. Manual deployment — step by step (what the script automates)

Every command the script runs, for hand execution, resuming a failed step, or
auditing. `CLIENT` = `~/hyperlane-monorepo/rust/sealevel/target/release/hyperlane-sealevel-client`,
`KEY` = your funded keypair json, `RPC` = a mainnet RPC.

### 5.1 Deploy the program + atomic init (the only things created)

Do **not** use `warp-route deploy` here (see the warning in §4). The working
manual flow is the same two-phase one the script runs:

```bash
# a) generate a FRESH program keypair (a closed id can never be reused):
solana-keygen new --no-bip39-passphrase -o program-keypair.json
# b) deploy the verified .so under it (200 sign attempts rides out RPC throttling):
solana program deploy <sealevel>/target/deploy/hyperlane_sealevel_token.so \
  -k $KEY --url $RPC \
  --program-id program-keypair.json --upgrade-authority $KEY \
  --use-rpc --with-compute-unit-price 200000 --max-sign-attempts 200
# → costs ~2.221 SOL of rent; on failure the buffer is reusable — re-run with
#   --buffer to resume the upload instead of paying again

# c) atomic init (mint PDA + metadata pointer + mint in ONE transaction),
#    driven by the repo config for your token:
cd ~/tc-cw-hyperlane/terraclassic
WARP_PROGRAM_ID=<PROGRAM_ID> TOKEN_KEY=mytoken NET_KEY=solanamainnet \
  node jito-warp-init.js
# → prints the mint address; also initializes Token-2022 metadata and moves the
#   mint authority to the mint PDA itself
```

### 5.2 Set the production ISM (3-of-4)

```bash
$CLIENT -k $KEY -u $RPC token set-interchain-security-module \
  --program-id <WARP> --ism 4MzF7HCfxuwj4EFHqZSEpvkcZZvv1mF37DP4pDHwR5VQ
```

### 5.3 Set the production IGP — type MUST be overhead-igp

```bash
$CLIENT -k $KEY -u $RPC token igp --program-id <WARP> set \
  FLZuKRsfdovLqd8n1AYhPCwLqBjfFyZY3A2edgnjdJoR overhead-igp \
  FXacR73HiuNyvW7x34KYCDyv8XxM86pz31Ap8t2v3RCJ
```

### 5.4 Set destination gas for Terra Classic

```bash
$CLIENT -k $KEY -u $RPC token set-destination-gas --program-id <WARP> 132556 3000000
```

### 5.5 Enroll the TC route on the Solana warp

`0x<TC_WARP_HEX>` = the TC collateral warp's 32-byte hex (from
`context/terraclassic.json`, see WARP-EVM §5.1):

```bash
$CLIENT -k $KEY -u $RPC token enroll-remote-router --program-id <WARP> 132556 0x<TC_WARP_HEX>
```

### 5.6 Enroll the Solana route on the TC warp (set_route)

`route` = the warp **program id decoded from base58 to 32-byte hex** (the script
stores it as `program_hex`; e.g. LUNC = `bb881238…b261`):

```bash
python3 -c "import base58,sys; print(base58.b58decode('<WARP_PROGRAM_ID>').hex())"
terrad tx wasm execute <TC_WARP_ADDRESS> \
  '{"router":{"set_route":{"set":{"domain":1399811149,"route":"<PROGRAM_ID_HEX_64>"}}}}' \
  --from <tc-key> --keyring-backend file --gas auto --gas-adjustment 1.5 \
  --gas-prices 28.325uluna --chain-id columbus-5 \
  --node https://rpc.terra-classic.hexxagon.io:443 -y
```

### 5.7 Verify everything

```bash
$CLIENT -u $RPC token query --program-id <WARP> synthetic
# interchain_security_module = 4MzF7HCf… · interchain_gas_paymaster = (FLZuKRs…, OverheadIgp(FXacR73…))
# destination_gas = {132556: 3000000} · remote_routers = {132556: <TC warp hex>}
```

## 6. Post-deploy checklist (production tokens)

Same as EVM: registry PR · warp UI route ([WARP-UI-PR.md](WARP-UI-PR.md) —
STEP 9 already generated the route YAML for you) · `originSenders` in the
oracle-agent config (tc-proof-of-delivery) · append the new addresses + hashes
to [DEPLOY-HASHES.md](DEPLOY-HASHES.md).

## 7. Troubleshooting (lessons from the live LUNC/USTC deploys, 2026-08-29)

| Symptom | Cause | Fix |
|---|---|---|
| `Max retries exceeded` during deploy | RPC throttling + the CLI gives up re-signing each write after 5 attempts by default — **raising the priority fee does NOT help** | the script already passes `--max-sign-attempts 200`; manually, add it yourself. Use a private RPC (§2.4) |
| `has insufficient funds for spend (…) + fee (…)` before anything happens | the CLI demands rent **+ worst-case fee estimate** up front; a fee spike inflates the estimate | wait for a calm network and/or pin `DEPLOY_CU_PRICE=200000`; the script aborts early on this instead of doubling the fee |
| Deploy timed out mid-upload | slow RPC | just re-run — the buffer is reused, the upload resumes where it stopped |
| `Program is not deployed` / `UnsupportedProgramId` on every config step, yet a success banner | stale `.warp-sealevel-state.json` pointing at a **closed** program id | `rm -f .warp-sealevel-state.json`, confirm the token's entry in `warp-sealevel-config.json` is reset, re-run (a new program keypair is generated) |
| Want to check whether a program is closed | the account keeps its `executable` flag after close — most probes give a false "alive" | only `solana program show <ID>` is reliable: it prints "has been closed" |
| Thinking of closing a program to recover SOL | `solana program close` is **permanent**: the id can never be redeployed, and the warp's mint/storage/ATA-payer PDAs (~0.06 SOL) are orphaned forever | only close routes you are genuinely retiring; redeploy = new id = new mint = new registry entry |
| Mint exists but no on-chain metadata | the metadata URI didn't resolve (HTTP ≠ 200) at init time | fix/commit the `warp/solana/metadata-<token>.json` and run the printed manual `spl-token initialize-metadata` command |

Deep-dive (every config field, every internal step):
[`../archive/create-warp-sealevel-guide.md`](../archive/create-warp-sealevel-guide.md).
Live examples to compare against: [WARP-LUNC.md](WARP-LUNC.md) · [WARP-USTC.md](WARP-USTC.md).
