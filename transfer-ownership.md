# transfer-ownership.sh — Hyperlane ownership transfer to governance (Terra Classic)

Reference document for `transfer-ownership.sh`, which transfers the **owner**
(and, optionally, the **migration admin**) of **every** Hyperlane contract on
Terra Classic — mailbox, ISMs, hooks, IGP, and the LUNC/USTC/IGORFAKE/FAKEFAKE
warp routes — to the **governance** account.

> ⚠️ **This is preparation only.** The script defaults to `--dry-run` (prints
> the commands, executes nothing). Nothing on-chain changes until it is run
> with `--execute`, and that has not happened yet.

---

## 0. Scope — what changes and what doesn't

**Changes (14 contracts, all currently owned by the deployer
`terra1run9wz09uhh6pu7ggcwwetrgye4wu7wn26mawp`):**

| # | Contract | Address | Hex (32 bytes) |
|---|---|---|---|
| 1 | Mailbox | `terra1fwg35n5esjgny7d8pxnz8usjpwsvpguk0txsy6cnqxy58x9fdlksjpx3p9` | `0x4b911a4e9984913279a709a623f2120ba0c0a3967acd026b1301894398a96fed` |
| 2 | ISM Routing (default_ism) | `terra1uhzzvt9x3u8hjnkp695hklexx2uywjvfqv454d93ds92sgtpwk7qrpxdg0` | `0xe5c4262ca68f0f794ec1d1697b7f2632b8474989032b4ab4b16c0aa8216175bc` |
| 3 | ISM Multisig — ETH (domain 1) | `terra187rzjc3dznfxqtqqrwh796e5q4khmvp5av8mka6zhp98zjfk2z2qneldar` | `0x3f8629622d14d2602c001bafe2eb34056d7db034eb0fbb7742b84a7149365094` |
| 4 | ISM Multisig — BSC (domain 56) | `terra1nqj7qlnt2sty0dgnu3ss5z4u6wr7hjfea7cn6wpwjt2uymts8ucsmuj9xw` | `0x9825e07e6b541647b513e4610a0abcd387ebc939efb13d382e92d5c26d703f31` |
| 5 | ISM Multisig — Solana (domain 1399811149) | `terra10s3p36tjek8amhlc4krxpzln6g8n0qy9jq82wyda434l3rv89wfsucl50t` | `0x7c2218e972cd8fdddff8ad86608bf3d20f378085900ea711bdac6bf88d872b93` |
| 6 | Hook Aggregate — default (Merkle + IGP), used as `default_hook` | `terra1026v947k2jn58t09ppw003xujj92vp3lxv0fg3xk8ccz42r8d2sqvnmvel` | `0x7ab4c2d7d654a743ade5085cf7c4dc948aa6063f331e9444d63e302aa8676aa0` |
| 7 | IGP (fee-collection contract) | `terra1taunhg629rssf3g939nqr0h594q5mssrzdj5lkx2hygmxmh72ghqeqqnvz` | `0x5f793ba34a28e104c505896601bef42d414dc20313654fd8cab911b36efe522e` |
| 8 | Hook Aggregate — required (Pausable + Fee), used as `required_hook` | `terra1xmdd7yhu3qdlfhrcku8srfvtday6efymj54gqz0daxsmn8pvqygq0nxq04` | `0x36dadf12fc881bf4dc78b70f01a58b6f49aca49b952a8009ede9a1b99c2c0110` |
| 9 | Hook Pausable | `terra1x8s9qtw9355pfckywkns4e8f9zyfjaf8w5e5s8vh28ph5gzwwlks9tjcnf` | `0x31e0502dc58d2814e2c475a70ae4e928889975277533481d9751c37a204e77ed` |
| 10 | Hook Fee (0.283215 LUNC/msg) | `terra1sud5xyknr93wmxem6kxdfd0vxcju47wuh7zdm5uecavrm36w669sp7j8ag` | `0x871b4312d31962ed9b3bd58cd4b5ec3625caf9dcbf84ddd399c7583dc74ed68b` |
| 11 | Warp **LUNC** (native, real collateral) | `terra1m7jcqxfn4hd7q4sywhw508nxshaf078c4vh83y0ts43y9tlp9dcs50cggy` | `0xdfa5801933addbe0560475dd479e6685fa97f8f8ab2e7891eb856242afe12b71` |
| 12 | Warp **USTC** (native, real collateral) | `terra1qu3x6vhk4y6w6erhmedzfp2ug53qm5nwpyarxveqa7tvwg0telxqvd3ccf` | `0x07226d32f6a934ed6477de5a24855c45220dd26e093a333320ef96c721ebcfcc` |
| 13 | Warp IGORFAKE (cw20, discontinued test route) | `terra1wr7krp8lpfddpzxfkxvmhfnxd06vkz34e7f0tk2vyau36j3d4pvs6pjpel` | `0x70fd6184ff0a5ad088c9b199bba6666bf4cb0a35cf92f5d94c27791d4a2da859` |
| 14 | Warp FAKEFAKE (cw20, discontinued test route) | `terra1zkkk9km8f6gf5vgn4zf66ep0djztqqkvns8jws8c9f85v4tfxrvq9n2wlk` | `0x15ad62db674e909a3113a893ad642f6c84b002cc9c0f2740f82a4f46556930d8` |

New owner for all 14: **the governance account**
`terra10d07y265gmmuvt4z0w9aw880jnsr700juxf95n` — the real Terra Classic
**x/gov module account**, independently verified on-chain via
`/cosmos/auth/v1beta1/module_accounts` (name `gov`), same address on mainnet
(columbus-5) and testnet (rebel-2).

**Excluded — never touched by this script, under any mode:**

| Contract | Address | Why |
|---|---|---|
| IGP gas-oracle (`hpl_igp_oracle`) | `terra1j8xzgzk7vds5uzrplmnln4vcz6f205t9atdyflypzrr43cd5eh7scwqj0d` | Governed separately by its own dedicated **oracle-governor** contract (`terra1z7jmlky2cmsd9aslm4uxrsase2yjwz8k9rlk00ga8s7pxgljczjq9sv4hj`), confirmed on-chain as its current owner. Hard-excluded in the script by address, in addition to already failing the "owner == you" safety filter — belt and suspenders. |

**Not ownable — no `owner` field exists on these contracts, so there is
nothing to transfer (the script detects and skips them automatically):**

| Contract | Address |
|---|---|
| Validator Announce | `terra1gtnmdevekgxpvzej3wfy20e2n335gm3muwj6geduxxa86j3x70cq00asmy` |
| Hook Merkle (leaf of the default Aggregate hook) | `terra183lq6yqp8km3p34cxgk6k3u78uy4plqahey6rne7n9gy98delr9qyp0n2p` |

Inventory verified 2026-09-28 by querying `get_owner` on all 16 non-oracle
candidates directly against the chain (LCD `lcd.terra-classic.hexxagon.io`);
14 returned the deployer address, 2 returned a JSON-RPC error (no `ownable`
query variant → not ownable). Counts match what `./transfer-ownership.sh`
(dry-run) reports.

---

## 1. Why this handoff matters

The deployer account (`CURRENT_OWNER`) was used **only** for the
installation, deployment and testing phase. It should not remain the owner of
production infrastructure indefinitely. Once this runs, **every** future
configuration change (enrolling a router, swapping an ISM, adjusting a
hook/IGP) requires a governance action — that's the point: decentralizing
control.

```
  [deployer installs/deploys/tests] → tests OK → RUN THIS SCRIPT → governance in control
```

---

## 2. Two separate transfers, don't confuse them

| Transfer | Destination | Script |
|---|---|---|
| Infrastructure owner (this doc) — mailbox, ISMs, hooks, IGP, warp routes | Governance (`terra10d07y...f95n`) | `transfer-ownership.sh` |
| Synthetic warp owner on the **external** EVM/Solana chains (BSC, Ethereum, Solana) | Hyperlane-validator multisig (Safe on EVM, Squads on Solana) | `transfer-warp-evm.sh` / `transfer-warp-solana.sh` — already run, see `HYPERLANE_DEPLOYMENT-MAINNET_EN.md` |

They look similar but go to **different** destinations for a reason: TC-side
infra is governed by the chain's own governance; the synthetic warp side on
each external chain is governed by that chain's validator set. Don't reuse
one script's target address for the other.

---

## 3. Concepts you need before running this

### 3.1 `owner` ≠ `admin` — two separate powers

| Power | Controls | How it changes | Steps |
|---|---|---|---|
| **`owner`** (`hpl_ownable`) | Configuration: routers, ISM, hooks | `init_ownership_transfer` + `claim_ownership` | **2 steps** |
| **`admin`** (CosmWasm/x-wasm) | Code upgrades (`migrate`) | `set-contract-admin` (`MsgUpdateAdmin`) | **1 step, immediate** |

Transferring `owner` does **not** transfer `admin`, and vice versa. The
script only touches `owner` by default; `admin` is opt-in via
`--include-admin` and should happen only after governance has already
claimed ownership (see §5).

### 3.2 `owner` transfer is TWO STEPS

Confirmed in `packages/ownable/src/lib.rs`:

```
1) YOU (current owner):  init_ownership_transfer { next_owner: GOV }  → sets "pending_owner"
2) GOVERNANCE:           claim_ownership {}                           → accepts, becomes owner
```

Until governance claims, **you remain the owner**. You can cancel before the
claim with `revoke_ownership_transfer {}`.

### 3.3 The claim step needs a governance PROPOSAL, not a signature

`GOVERNANCE_ADDRESS` here is the real **x/gov module account** — verified
on-chain, not a placeholder. A module account has **no private key**; it can
only act through a passed governance proposal executing
`MsgExecuteContract` on its behalf (same mechanism already used in
`terraclassic/submit-proposal-mainnet.ts`). So `./transfer-ownership.sh
--claim --execute` does **not** try to sign anything — it writes
`claim-ownership-proposal.json` (one `MsgExecuteContract` per eligible
contract, `msg: {"ownable":{"claim_ownership":{}}}`), ready for:

```bash
terrad tx gov submit-proposal claim-ownership-proposal.json \
  --from <any_funding_key> --chain-id columbus-5 \
  --node https://terra-classic-rpc.publicnode.com:443 \
  --gas auto --gas-adjustment 1.5 --gas-prices 28.325uluna -y
```

The proposal must pass a normal on-chain vote before the owner actually
changes. Until then, `get_owner` still returns the deployer address and
`get_pending_owner` returns the governance address.

### 3.4 Safe auto-discovery

The script does not trust a fixed list (deploy records can go stale). For
every candidate address found in `context/terraclassic.json` (now walking
**everything**, including `deployments.warp` — nothing is skipped by
category anymore) it:

1. Skips it outright if it's in `HARD_EXCLUDE` (the oracle — see §0).
2. Queries `get_owner` on-chain, with a 3-attempt retry (the public RPC node
   occasionally answers a transient `503` under rapid sequential queries —
   without the retry this silently produces false "not ownable" skips; this
   was caught and fixed while validating this script on 2026-09-28).
3. Only considers it **eligible** if it's ownable **and** the current owner is
   exactly `CURRENT_OWNER`.

---

## 4. Configuration

Already filled in and verified on-chain (2026-09-28) — no editing needed to
run the dry-run:

| Variable | Value | Verified how |
|---|---|---|
| `GOVERNANCE_ADDRESS` | `terra10d07y265gmmuvt4z0w9aw880jnsr700juxf95n` | `/cosmos/auth/v1beta1/module_accounts`, name `gov` |
| `CURRENT_OWNER` | `terra1run9wz09uhh6pu7ggcwwetrgye4wu7wn26mawp` | `get_owner` on all 14 target contracts |
| `HARD_EXCLUDE` | `terra1j8xzgzk7...9sv4hj` (oracle) | `get_owner` = the oracle-governor, not the deployer |

Only `SIGNER_KEY` needs to be set before `--execute` — the name of your
keyring key (`terrad keys list`), i.e. the deployer's key.

---

## 5. Recommended flow

**1. Review the dry-run** (default — executes and writes nothing):
```bash
./transfer-ownership.sh                  # step 1 preview: the 14 init_ownership_transfer commands
./transfer-ownership.sh --claim          # step 2 preview: what the proposal will contain
./transfer-ownership.sh --include-admin  # preview: + set-contract-admin
```

**2. Run step 1 for real** (you, the current owner, propose the transfer):
```bash
./transfer-ownership.sh --execute
```

**3. Confirm each contract shows the governance address as `pending_owner`:**
```bash
terrad query wasm contract-state smart <CONTRACT> '{"ownable":{"get_pending_owner":{}}}' \
  --node https://terra-classic-rpc.publicnode.com:443
```

**4. Generate and submit the claim proposal:**
```bash
./transfer-ownership.sh --claim --execute   # writes claim-ownership-proposal.json
terrad tx gov submit-proposal claim-ownership-proposal.json --from <any_key> \
  --chain-id columbus-5 --node https://terra-classic-rpc.publicnode.com:443 \
  --gas auto --gas-adjustment 1.5 --gas-prices 28.325uluna -y
```

**5. Vote, wait for it to pass, then confirm:**
```bash
terrad query wasm contract-state smart <CONTRACT> '{"ownable":{"get_owner":{}}}' \
  --node https://terra-classic-rpc.publicnode.com:443
# should now be terra10d07y265gmmuvt4z0w9aw880jnsr700juxf95n for all 14
```

**6. (Optional, later) Transfer the migration admin** — only after governance
has confirmed the owner claim, so you're never left without any control
mid-way:
```bash
./transfer-ownership.sh --include-admin --execute
```

---

## 6. How to cancel / revert

- **Before the claim:** you're still the owner. Cancel the pending transfer:
  ```bash
  terrad tx wasm execute <CONTRACT> '{"ownable":{"revoke_ownership_transfer":{}}}' \
    --from <your_key> --chain-id columbus-5 \
    --node https://terra-classic-rpc.publicnode.com:443 \
    --gas auto --gas-adjustment 1.5 --gas-prices 28.325uluna -y
  ```
- **After the claim:** governance now owns it. Only a new governance
  proposal can transfer it back to you (`init_ownership_transfer` executed by
  governance, then you `claim_ownership`).

---

## 7. Warnings

1. **This is a real production migration for LUNC/USTC** — the native warp
   routes (#11–12 in the table) hold real collateral. Nothing is irreversible
   before governance claims (you can still `revoke`), but once the claim
   proposal passes, only another governance vote can undo it.
2. **The oracle is intentionally excluded, twice over** (filter + hard
   exclude) — do not remove it from `HARD_EXCLUDE` without an explicit
   decision to change how the oracle is governed.
3. **Order matters for `--include-admin`:** transfer `owner` and let
   governance claim it **before** touching `admin`. Changing `admin` too
   early can leave you without upgrade power while the owner transfer is
   still pending.
4. **Always dry-run first** and read the eligible/skipped list — if a
   contract you expect to see shows up as "skip (no get_owner)", re-run once
   before assuming it's really non-ownable (see §3.4 on RPC retries).
5. **Reserve LUNC for gas** — this is 14 separate transactions for step 1,
   plus the proposal deposit for step 2 (fetched live from
   `/cosmos/gov/v1/params/deposit` — 5,000,000,000,000 uluna = 5,000,000 LUNC
   as of 2026-09-28; this is a governance parameter and can change), plus
   whatever `--include-admin` adds later.

---

## 8. Troubleshooting

| Symptom | Likely cause | What to do |
|---|---|---|
| `no candidate addresses found` | wrong/empty `CONTEXT_FILE` | check the path to `context/terraclassic.json` |
| Your contract shows `skip (owner is already ...)` | owner already transferred, or `CURRENT_OWNER` wrong | check `CURRENT_OWNER` and the contract's `get_owner` |
| `skip (no get_owner)` | contract genuinely not ownable (validator_announce / merkle hook) | expected — no owner to transfer |
| `claim` proposal fails to pass / rejected | normal governance process — needs quorum + yes votes | resubmit or address voter concerns; nothing on-chain changes until it passes |
| `ownership is transferring` | a pending owner already exists | `claim` or `revoke` before a new `init_ownership_transfer` |
| A contract flakes between `ok`/`skip` across re-runs | public RPC 503 (rate limiting) | already retried 3x automatically; if it persists, try a different `--node` |

---

## 9. Related files

- `transfer-ownership.sh` — the script.
- `context/terraclassic.json` — source of the infrastructure + warp addresses.
- `terraclassic/submit-proposal-mainnet.ts` — same proposal-JSON convention,
  used for the original ISM-validator/IGP-oracle governance configuration.
- `packages/ownable/src/lib.rs` — `hpl_ownable` implementation (owner logic).
- `packages/interface/src/ownable.rs` — `OwnableMsg` definition.
