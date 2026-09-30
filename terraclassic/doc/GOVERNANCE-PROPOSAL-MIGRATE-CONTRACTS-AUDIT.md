# Governance Proposal Audit — Migrate Hyperlane Infrastructure Contracts (Terra Classic)

**Status as of 2026-09-30:** new code uploaded and verified on-chain for all
20 contracts in the workspace (tx hashes in §2.1). The proposal JSON
(`migrate-contracts-proposal.json`) is built and verified against live
chain state but **not yet submitted**. This document lets any validator,
community member, or reviewer verify every claim before it is submitted and
before voting, without having to trust the proposer's word — same intent as
[`GOVERNANCE-PROPOSAL-CLAIM-OWNERSHIP-AUDIT.md`](./GOVERNANCE-PROPOSAL-CLAIM-OWNERSHIP-AUDIT.md),
which this proposal depends on for migration authority (§2).

---

## 1. Executive summary

Community researcher **Fragwuerdig** found that the deployed multisig ISM
(code_id 11374) predates upstream fix
[#142](https://github.com/many-things/cw-hyperlane/commit/d07e55e17c791a5f6557f114e3fb6cb433d9b800)
for duplicate validator-signature counting — a single compromised or
malicious validator key can satisfy an N-of-M threshold by repeating its own
signature, without collusion. Full writeup:
[Discourse](https://discourse.luncgoblins.com/t/claim-hyperlane-infrastructure-ownership-for-governance/555/2?u=fragwuerdig),
independently confirmed and documented in
[`GOVERNANCE-PROPOSAL-CLAIM-OWNERSHIP-AUDIT.md §10`](./GOVERNANCE-PROPOSAL-CLAIM-OWNERSHIP-AUDIT.md#10-known-pre-existing-issue--multisig-ism-duplicate-signature-counting-code_id-11374).

This proposal migrates **every contract that can be migrated** — not only
the 3 multisig ISMs — to code built from the fork's current `main`, which
carries #142 plus three unrelated commits already merged upstream
(§4). Scope was widened past "just the vulnerable ISM" on the reasoning
that since a migration round is happening anyway, bringing everything to the
same audited, current source reduces the number of future one-off
migrations — see §2 for exactly what is and isn't included, and why.

---

## 2. Scope — what migrates, what can't, what's left out on purpose

**Migration authority is the contract *admin*, separate from *owner*.**
Admin for the contracts below was transferred to governance
(`terra10d07y265gmmuvt4z0w9aw880jnsr700juxf95n`) on 2026-09-29, independent
of proposal #12229 (which transfers *owner*, still pending) — see
[`GOVERNANCE-PROPOSAL-CLAIM-OWNERSHIP-AUDIT.md §3`](./GOVERNANCE-PROPOSAL-CLAIM-OWNERSHIP-AUDIT.md#3-migration-admin--already-done-outside-this-governance-proposal).
That's what makes this proposal possible without waiting for #12229.

### 2.1 Migrating in this proposal — 13 instances, 10 code builds

All confirmed on-chain: `admin == terra10d07y265…` (governance), and the new
code_id's checksum differs from what's currently deployed. 12 of these 13 had
admin transferred to governance on 2026-09-29 as part of the ownership-claim
tooling (§3 of the ownership audit). The IGP Oracle (#13) is separate: its
admin was still the deployer wallet until 2026-09-30, when it was transferred
directly (`terrad tx wasm set-contract-admin`, tx
`2182AB478B5197245C50CA6657D55BAF7AEBE41529D938F88BE36B975F84F4B6`) —
unrelated to proposal #12229, which only ever covered the 12 contracts in
`GOVERNANCE-PROPOSAL-CLAIM-OWNERSHIP-AUDIT.md §2`. The IGP Oracle's *owner*
(who can call `SetRemoteGasData`, i.e. who actually sets prices) was already
the `oracle-governor` contract (`terra1z7jmlky2cmsd9aslm4uxrsase2yjwz8k9rlk00ga8s7pxgljczjq9sv4hj`,
tc-proof-of-delivery) before any of this — only migration authority changed.

| # | Contract | Address | Old code_id | Old sha256 | New code_id | New sha256 |
|---|---|---|---|---|---|---|
| 1 | Mailbox | `terra1fwg35n5esjgny7d8pxnz8usjpwsvpguk0txsy6cnqxy58x9fdlksjpx3p9` | 11371 | `b6d789c1a31e…49eb01` | **11687** | `82e8d06426908…18bff0` |
| 2 | Validator Announce | `terra1gtnmdevekgxpvzej3wfy20e2n335gm3muwj6geduxxa86j3x70cq00asmy` | 11372 | `c3c42fda7aab…e8167d` | **11688** | `f438c70f3a9fa…6f49c` |
| 3 | ISM Routing (`default_ism`) | `terra1uhzzvt9x3u8hjnkp695hklexx2uywjvfqv454d93ds92sgtpwk7qrpxdg0` | 11376 | `0881d65f4704…c8143c` | **11692** | `ea24599fe8744…f9acb` |
| 4 | ISM Multisig — Ethereum (domain 1) | `terra187rzjc3dznfxqtqqrwh796e5q4khmvp5av8mka6zhp98zjfk2z2qneldar` | 11374 | `32b07207c733…5e3a531` | **11690** | `1f7e78d2451d5…fab15923` |
| 5 | ISM Multisig — BSC (domain 56) | `terra1nqj7qlnt2sty0dgnu3ss5z4u6wr7hjfea7cn6wpwjt2uymts8ucsmuj9xw` | 11374 | (same as #4) | **11690** | (same as #4) |
| 6 | ISM Multisig — Solana (domain 1399811149) | `terra10s3p36tjek8amhlc4krxpzln6g8n0qy9jq82wyda434l3rv89wfsucl50t` | 11374 | (same as #4) | **11690** | (same as #4) |
| 7 | Hook Aggregate — default (Merkle + IGP) | `terra1026v947k2jn58t09ppw003xujj92vp3lxv0fg3xk8ccz42r8d2sqvnmvel` | 11378 | `9dfbe1ba3e0d…879a5004` | **11694** | `cfc9ba153c88…31239d` |
| 8 | Hook Aggregate — required (Pausable + Fee) | `terra1xmdd7yhu3qdlfhrcku8srfvtday6efymj54gqz0daxsmn8pvqygq0nxq04` | 11378 | (same as #7) | **11694** | (same as #7) |
| 9 | IGP (fee-collection contract) | `terra1taunhg629rssf3g939nqr0h594q5mssrzdj5lkx2hygmxmh72ghqeqqnvz` | 11377 | `34313c90c9e0…20590e6fad0b` | **11693** | `3711615ae051…03f49f` |
| 10 | Hook Pausable | `terra1x8s9qtw9355pfckywkns4e8f9zyfjaf8w5e5s8vh28ph5gzwwlks9tjcnf` | 11381 | `0f53c4193be4…699b6c2` | **11697** | `ca462e9554f0…3584b7` |
| 11 | Hook Fee (0.283215 LUNC/msg) | `terra1sud5xyknr93wmxem6kxdfd0vxcju47wuh7zdm5uecavrm36w669sp7j8ag` | 11379 | `c981467b9af2…4e7956e` | **11695** | `414f7d28f82af…264575` |
| 12 | Hook Merkle | `terra183lq6yqp8km3p34cxgk6k3u78uy4plqahey6rne7n9gy98delr9qyp0n2p` | 11380 | `f4258979caf1…e61e9f156` | **11696** | `cb2e04c9a51d0…6543c07` |
| 13 | IGP Oracle | `terra1j8xzgzk7vds5uzrplmnln4vcz6f205t9atdyflypzrr43cd5eh7scwqj0d` | 11388 | `3b0143755d32…8de1fc` | **11704** | `d288f3384707…2db4f1` |

Upload txs (2026-09-30, `yarn cw-hpl -n terraclassic upload local`, all 20
codes uploaded in one batch): mailbox `2ED95505…F66A0B7`, validator_announce
`806AA979…0A7375`, ism_multisig `9D0395B5…266E3A5`, ism_routing
`D0F02AA1…93F9ACB`, igp `2B8CB721…8273B735D`, hook_aggregate
`0CE1B665…D223D`, hook_fee `373FA7C0…B534AF2`, hook_merkle `E365AD75…5956E96`,
hook_pausable `37DA46FC…F839278`.

### 2.2 Cannot migrate, by any proposal, ever — 2 instances

| Contract | Address | Code_id | Why not |
|---|---|---|---|
| Warp **LUNC** (native) | `terra1m7jcqxfn4hd7q4sywhw508nxshaf078c4vh83y0ts43y9tlp9dcs50cggy` | 11390 | `contract_info.admin` is empty on-chain. CosmWasm has no mechanism to set an admin once it is empty — `MsgUpdateAdmin` requires the sender to already *be* the current admin. This is permanent by protocol design, not a policy choice. |
| Warp **USTC** (native) | `terra1qu3x6vhk4y6w6erhmedzfp2ug53qm5nwpyarxveqa7tvwg0telxqvd3ccf` | 11390 | Same as above (shares code_id 11390 with LUNC). |

A new build of `hpl_warp_native` was uploaded anyway as code_id **11706**
(sha256 `c2d2160766847…f99ccfd800`) for the record, but nothing can ever
point these two contracts at it.

### 2.3 Uploaded but nothing to migrate — 8 instances

`hpl_ism_aggregate` (11689), `hpl_ism_pausable` (11691 — not instantiated
anywhere on Terra Classic mainnet today, unlike `hpl_hook_pausable` which
is, §2.1 row 10), `hpl_hook_routing` / `_custom` / `_fallback` (11698–11700),
the 3 test-mock contracts (11701–11703), and `hpl_warp_cw20` (11705) were
rebuilt and uploaded as part of the same batch (the optimizer builds the
whole workspace at once) but have no live instance on Terra Classic mainnet
to migrate. Uploading them cost gas but changes nothing; they are listed
here so nobody has to wonder why their code_ids exist.

---

## 3. What changed in the code

4 commits separate the deployed `v0.0.7-rc0` tag from the build commit
(`cd972f84bbd5280d8731b3e02eaa9cf21f3dc670`, `terra-classic-hyperlane/cw-hyperlane`
`main`):

| Upstream PR | Commit | Change | Contract(s) affected | Severity |
|---|---|---|---|---|
| [#142](https://github.com/many-things/cw-hyperlane/commit/d07e55e17c791a5f6557f114e3fb6cb433d9b800) | `d07e55e` | Multisig ISM: stop counting a validator's repeated signature more than once | `hpl_ism_multisig` | **High** — see §10 of the ownership audit doc |
| #138 | — | Mailbox `Process` event emits the origin domain instead of the local domain | `hpl_mailbox` | Cosmetic |
| #139 | — | Fix event name in the pausable ISM | `hpl_ism_pausable` (not deployed standalone, §2.3) | Cosmetic |
| #143 | — | Allow disabling an ISM/hook | shared trait code — touches most contracts' compiled output even where the feature isn't used | Feature |

Only #142 is a security fix. The other 3 are why contracts beyond the 3 ISMs
show a bytecode difference at all — none of them change behavior that
matters for a contract that doesn't use the new "disable" feature.

---

## 4. Build reproducibility

Anyone can reproduce byte-identical wasm from the same commit. The
optimizer (`cosmwasm/optimizer:0.15.0`, same image the original release
used) ships Rust 1.73 (2023), while `main`'s loose `^x` dependency ranges
resolve to current crates.io versions that require newer Rust by default —
three local tweaks were needed, **none of which touch the compiled contract
code**, only which transitive dependency versions get pulled in and which
workspace members get built:

1. **Regenerate `Cargo.lock`** (not checked into the repo, consistent with
   how the original `v0.0.7-rc0` release was built — see
   `GOVERNANCE-PROPOSAL-CLAIM-OWNERSHIP-AUDIT.md §10.1`):
   ```bash
   cargo +1.73.0 generate-lockfile
   ```
2. **Pin two transitive dependencies** that resolve to `edition = "2024"`
   versions cargo 1.73 cannot parse, down to the latest `edition = "2021"`
   release of each:
   ```bash
   cargo +1.73.0 update -p base64ct --precise 1.6.0
   cargo +1.73.0 update -p zeroize --precise 1.7.0
   ```
3. **Remove `integration-test` from the workspace `members` list** in the
   root `Cargo.toml`, and **move two misplaced test-only dependencies**
   (`rstest`, `ibcx-test-utils`) from `[dependencies]` to nothing (they were
   only ever used in `packages/connection/src/lib.rs`'s `#[cfg(test)] mod
   tests`, confirmed by reading the source — removing them does not touch
   any non-test code path) in `packages/connection/Cargo.toml`. This alone
   is what pulls `osmosis-test-tube`, `test-tube`, and a long tail of heavy
   transitive crates (`home`, the `time` family, `hashbrown`, `icu_*`) that
   otherwise force an even newer Rust than any published `cosmwasm/optimizer`
   image bundles. Same category of fix as the `integration-test`
   removal the original `v0.0.7-rc0` verification already needed — this repo
   has simply drifted further from any fixed toolchain since.

None of these three tweaks were committed — they exist only in the local
tree used to produce the artifacts, exactly as the original reproduction
recipe in §10.1 of the ownership-claim audit did for the same reasons.
Anyone reproducing this build applies the same three steps to a checkout of
commit `cd972f84bbd5280d8731b3e02eaa9cf21f3dc670`, then:

```bash
make optimize   # cosmwasm/optimizer:0.15.0, full workspace
cosmwasm-check artifacts/hpl_ism_multisig.wasm   # and any other artifact — all 20 pass
sha256sum artifacts/*.wasm   # compare against §2's table
```

---

## 5. Migration mechanics verification

**Message shape.** `MsgMigrateContract{sender, contract, code_id, msg}`,
`msg` is the CosmWasm `MigrateMsg` — confirmed `Empty` (`{}`) for every one
of the 10 contract types migrated here, by reading each `migrate()` entry
point directly:

```
contracts/core/mailbox/src/contract.rs:99:    pub fn migrate(deps: DepsMut, _env: Env, _msg: Empty)
contracts/core/va/src/contract.rs:219:         pub fn migrate(deps: DepsMut, _env: Env, _msg: Empty)
contracts/isms/multisig/src/contract.rs:137:   pub fn migrate(deps: DepsMut, _env: Env, _msg: Empty)
contracts/isms/routing/src/contract.rs:155:    pub fn migrate(deps: DepsMut, _env: Env, _msg: Empty)
contracts/igps/core/src/contract.rs:138:       pub fn migrate(deps: DepsMut, _env: Env, _msg: Empty)
contracts/igps/oracle/src/contract.rs:103:     pub fn migrate(deps: DepsMut, _env: Env, _msg: Empty)
contracts/hooks/aggregate/src/lib.rs:198:      pub fn migrate(deps: DepsMut, _env: Env, _msg: Empty)
contracts/hooks/fee/src/lib.rs:157:            pub fn migrate(deps: DepsMut, _env: Env, _msg: Empty)
contracts/hooks/merkle/src/lib.rs:197:         pub fn migrate(deps: DepsMut, _env: Env, _msg: Empty)
contracts/hooks/pausable/src/lib.rs:106:       pub fn migrate(deps: DepsMut, _env: Env, _msg: Empty)
```

**cw2 version gate.** Every `migrate()` calls
`hpl_utils::migrate(storage, CONTRACT_NAME, CONTRACT_VERSION)`, which
requires the crate `name` to match what's stored on-chain exactly, and the
crate `version` to be strictly greater than what's stored — otherwise the
whole message (and therefore the whole proposal, §6) reverts.

- **Name:** unchanged for all 10 crates between the deployed tag
  (`eb791b56d`) and the build commit — `hpl-mailbox`,
  `hpl-validator-announce`, `hpl-ism-multisig`, `hpl-ism-routing`, `hpl-igp`,
  `hpl-igp-oracle`, `hpl-hook-aggregate`, `hpl-hook-fee`, `hpl-hook-merkle`,
  `hpl-hook-pausable` — verified by diffing each crate's `Cargo.toml`
  `name` field at both commits.
- **Version:** the workspace-wide `version` (root `Cargo.toml`,
  `[workspace.package]`) was `0.0.6` at the deployed tag and is `0.0.7` at
  the build commit — bumped in the very commit that lands #142. Every one
  of the 10 crates declares `version.workspace = true`, so the on-chain
  stored version (`0.0.6`, set at each contract's original instantiation)
  is strictly less than the new build's `0.0.7` for all of them. Checked
  individually, not assumed from one example.

---

## 6. Atomicity

Like the ownership-claim proposal (`GOVERNANCE-PROPOSAL-CLAIM-OWNERSHIP-AUDIT.md §7.2`),
the Cosmos SDK executes a governance proposal's messages as a single atomic
batch: if any one of the 13 `MsgMigrateContract` messages fails (wrong
admin, name/version mismatch, code_id doesn't exist), **none of them
apply**, even after the proposal passes a vote. §5 above exists specifically
to rule that out ahead of time, for every one of the 10 contract types, not
just a representative sample.

---

## 7. Reversibility

Migrating again to a different code_id later requires the same process:
a new governance proposal with `MsgMigrateContract` per contract. There is
no separate "revert" message — rolling back means proposing a migration
back to the old code_id (11371/11372/11374/11376/11377/11378/11379/11380/11381/11388),
which would also need a cw2 version bump above `0.0.7` to pass the same gate
described in §5 (or a contract-specific `MigrateMsg` change — none of these
10 contracts currently has one).

---

## 8. Related files

- [`migrate-contracts-proposal.json`](../../migrate-contracts-proposal.json)
  — the proposal ready for `terrad tx gov submit-proposal`.
- [`build-migrate-proposal.mjs`](../../build-migrate-proposal.mjs) — the
  script that generated it, verifying admin + code-diff on-chain per
  contract before including it (not hardcoded/assumed).
- [`GOVERNANCE-PROPOSAL-CLAIM-OWNERSHIP-AUDIT.md`](./GOVERNANCE-PROPOSAL-CLAIM-OWNERSHIP-AUDIT.md)
  — the ownership-claim proposal (#12229) this one's migration authority
  depends on (§2), and §10's original vulnerability writeup.
- `contracts/isms/multisig/src/query.rs` (fork `main`) — the fixed
  `verify_message`, for direct comparison against the deployed version's
  code (§4 of the ownership audit).
