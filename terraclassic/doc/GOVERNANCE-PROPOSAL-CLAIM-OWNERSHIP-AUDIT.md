# Governance Proposal Audit — Claim Ownership of Hyperlane Infrastructure (Terra Classic)

**Status as of 2026-09-29:** Step 1 (init_ownership_transfer) executed and
verified on-chain for all 12 contracts in scope. Migration admin already
transferred to governance for the 12 contracts that have one (§3). Step 2
(the governance proposal itself, for `owner`) is **submitted on-chain as
[proposal #12229](https://lcd.terra-classic.hexxagon.io/cosmos/gov/v1/proposals/12229)**,
tx `2FC146CC730B2E2C1FC421B3E31A2A8980AFB743689E740837AC53E736AB8BC6`,
currently in `PROPOSAL_STATUS_DEPOSIT_PERIOD` (deposit period ends
2026-10-13) — see `claim-ownership-proposal.json` for the exact deposit
amount, which can still be topped up by any wallet via `MsgDeposit` before it
moves to voting.

This document exists so any validator, community member, or reviewer can
independently verify every claim behind the "Claim Hyperlane infrastructure
ownership for governance" proposal before voting, without having to trust the
proposer's word.

---

## 1. Executive summary

The Hyperlane infrastructure contracts on Terra Classic (mailbox, ISMs, hooks,
IGP, and the LUNC/USTC warp routes) were deployed and administered by a
single deployer wallet (`terra1run9wz09uhh6pu7ggcwwetrgye4wu7wn26mawp`)
during installation and testing. This proposal completes the handoff of that
administration to the chain's own governance module, so that future
configuration changes (validator set updates, hook/ISM changes, router
enrollment) require a community vote instead of one wallet's signature.

The transfer is a standard two-step `hpl_ownable` handoff:
1. **`init_ownership_transfer`** — the deployer proposes governance as the next
   owner (**already done**, see §6).
2. **`claim_ownership`** — governance accepts (**this proposal**, see §7).

**Note:** the 3 ISM Multisig contracts in scope (§2, items #3–#5) carry a
pre-existing bug in their deployed code (duplicate validator-signature
counting, predates upstream fix #142) — unrelated to `claim_ownership`
itself, but relevant to anyone evaluating this infrastructure. See §10 for
the finding and the remediation path, which does not block or depend on this
proposal.

---

## 2. Scope — 12 contracts claimed in this proposal, one governance recipient

New owner: `terra10d07y265gmmuvt4z0w9aw880jnsr700juxf95n` — the Terra Classic
**x/gov module account** (provenance in §5).

| # | Contract | Code (`hpl_*`) | Address |
|---|---|---|---|
| 1 | Mailbox | `hpl_mailbox` | `terra1fwg35n5esjgny7d8pxnz8usjpwsvpguk0txsy6cnqxy58x9fdlksjpx3p9` |
| 2 | ISM Routing (`default_ism`) | `hpl_ism_routing` | `terra1uhzzvt9x3u8hjnkp695hklexx2uywjvfqv454d93ds92sgtpwk7qrpxdg0` |
| 3 | ISM Multisig — Ethereum (domain 1) | `hpl_ism_multisig` | `terra187rzjc3dznfxqtqqrwh796e5q4khmvp5av8mka6zhp98zjfk2z2qneldar` |
| 4 | ISM Multisig — BSC (domain 56) | `hpl_ism_multisig` | `terra1nqj7qlnt2sty0dgnu3ss5z4u6wr7hjfea7cn6wpwjt2uymts8ucsmuj9xw` |
| 5 | ISM Multisig — Solana (domain 1399811149) | `hpl_ism_multisig` | `terra10s3p36tjek8amhlc4krxpzln6g8n0qy9jq82wyda434l3rv89wfsucl50t` |
| 6 | Hook Aggregate — default (Merkle + IGP) | `hpl_hook_aggregate` | `terra1026v947k2jn58t09ppw003xujj92vp3lxv0fg3xk8ccz42r8d2sqvnmvel` |
| 7 | IGP (fee-collection contract) | `hpl_igp` | `terra1taunhg629rssf3g939nqr0h594q5mssrzdj5lkx2hygmxmh72ghqeqqnvz` |
| 8 | Hook Aggregate — required (Pausable + Fee) | `hpl_hook_aggregate` | `terra1xmdd7yhu3qdlfhrcku8srfvtday6efymj54gqz0daxsmn8pvqygq0nxq04` |
| 9 | Hook Pausable | `hpl_hook_pausable` | `terra1x8s9qtw9355pfckywkns4e8f9zyfjaf8w5e5s8vh28ph5gzwwlks9tjcnf` |
| 10 | Hook Fee (0.283215 LUNC/msg) | `hpl_hook_fee` | `terra1sud5xyknr93wmxem6kxdfd0vxcju47wuh7zdm5uecavrm36w669sp7j8ag` |
| 11 | Warp **LUNC** (native, real collateral) | `hpl_warp_native` | `terra1m7jcqxfn4hd7q4sywhw508nxshaf078c4vh83y0ts43y9tlp9dcs50cggy` |
| 12 | Warp **USTC** (native, real collateral) | `hpl_warp_native` | `terra1qu3x6vhk4y6w6erhmedzfp2ug53qm5nwpyarxveqa7tvwg0telxqvd3ccf` |

### 2.1 Not ownable — no `owner` field exists, nothing to transfer

| Contract | Address |
|---|---|
| Validator Announce | `terra1gtnmdevekgxpvzej3wfy20e2n335gm3muwj6geduxxa86j3x70cq00asmy` |
| Hook Merkle (leaf of the default Aggregate hook) | `terra183lq6yqp8km3p34cxgk6k3u78uy4plqahey6rne7n9gy98delr9qyp0n2p` |

Both confirmed by querying `{"ownable":{"get_owner":{}}}` on-chain: the query
returns a parse error (`unknown variant 'ownable'`) because these contract
types never implement the `hpl_ownable` interface at all — not a permissions
issue, the code genuinely has no such query/execute variant.

---

## 3. Migration admin — already done, outside this governance proposal

**Migration admin** (code-upgrade authority, separate from `owner`) was
**never** part of this governance proposal — it doesn't need to be. Unlike
`owner`, `admin` transfer (`MsgUpdateAdmin`/`set-contract-admin`) has no
accept step: it is a single signed transaction from the current admin,
effective immediately, with no vote or proposal involved.

Executed 2026-09-29 by the deployer via `transfer-ownership.sh --admin-only
--execute`, for **12 contracts** with a mutable admin: the 10 from §2, plus
Validator Announce and the Merkle Tree hook (§2.1) — these two have no
`owner()` at all, but a CosmWasm admin is a separate, always-present property
independent of whether a contract implements `hpl_ownable`, so they were
still eligible. (First pass at this script only checked admin for the
owner-eligible subset and silently missed these two — fixed by building a
separate admin-candidate list covering every non-excluded address.) The
LUNC and USTC warps have no admin at all — see the "not ownable"-style note
in `DEPLOY-HASHES.md`, admin is `<none/immutable>` for those, permanently
(confirmed on-chain: `contract_info.admin` is an empty string, and an empty
admin can never be set later — `MsgUpdateAdmin` requires the sender to
already be the current admin). All 12 confirmed
`admin == terra10d07y265gmmuvt4z0w9aw880jnsr700juxf95n` directly via
`GET /cosmwasm/wasm/v1/contract/<address>` (`contract_info.admin`), not just
the broadcast response:

| Contract | Tx hash |
|---|---|
| Mailbox | `210A97D10B55D4161CC67AF159F841E24E822DEADBF07D7A5D412F023E3C487E` |
| ISM Routing | `D7E72AB2397FF89732783729D155FAD6334389CFA0E31990A519A2C2496FF3D6` |
| ISM Multisig ETH | `4458068C1892F17B8FC0A6CF30E790CC277B4738B037484ED394DE82122C4DC9` |
| ISM Multisig BSC | `17A957A9F6F8CE1E7F456632ADC1EEACBC730A2ABB8C37AB79E66A667FA675F4` |
| ISM Multisig Solana | `BB49C0B3256251BD5C1FB34F38FB1481E71B2FC9A38AEDEF78D835EB26DBB700` |
| Hook Aggregate (default) | `02E96F6FFC2CC0DE05E110491BA9B1E35B6D30BDF81EE6B71BFFB1508E78FD00` |
| IGP | `ECFB49FA2B820D19E3E7B9CCF1732E61646447494201F8549CCC3A8BEB350A95` |
| Hook Aggregate (required) | `A5CE1CEC5E92857BD6FBE3392E95F8163B6425A12EC802D35AF652FA58D31070` |
| Hook Pausable | `12A7087A71969E31976E6C8FA887B5A4716B4117359BA12FC4B618457A1EEBEA` |
| Hook Fee | `707C56E07861082C87C5BA9463B83DDBF17991C17679FE206385066F143178B1` |
| Validator Announce | `06639CD923F00B2868A2200E4438438E21DCBEB3E6078A528F8DB77D6492EF77` |
| Hook Merkle | `3566BD5A461BEAA93DD0C39B44DFDB4DEB7B11451784C33168EACF32042BBA6E` |

(A first attempt at the initial 10 failed silently — `code 11`, out of gas,
visible only via a real tx query, not the broadcast response. Fixed in
`transfer-ownership.sh` by raising `GAS_ADJUST`, and re-run successfully; see
`transfer-ownership.md` for the tooling fix.)

## 4. Also out of scope for this proposal

- Nothing on BSC, Ethereum, or Solana — this proposal is Terra Classic-side
  only. The synthetic warp routes on those chains are governed separately, by
  each chain's own validator multisig (Safe on BSC, Squads on Solana),
  documented in `HYPERLANE_DEPLOYMENT-MAINNET_EN.md`.

---

## 5. Governance account provenance

`terra10d07y265gmmuvt4z0w9aw880jnsr700juxf95n` is not a hand-picked address —
it is the chain's actual `x/gov` module account, deterministically derived by
the Cosmos SDK from the module name. Verified independently via:

```bash
curl -s "https://lcd.terra-classic.hexxagon.io/cosmos/auth/v1beta1/module_accounts" \
  | jq -r '.accounts[] | select(.name=="gov") | .base_account.address'
# -> terra10d07y265gmmuvt4z0w9aw880jnsr700juxf95n
```

This matches the value already documented in
[`HYPERLANE_DEPLOYMENT-MAINNET_EN.md`](../HYPERLANE_DEPLOYMENT-MAINNET_EN.md)
and used unchanged since the original core deployment.

A module account has **no private key** — the only way to make it act is
through a passed governance proposal executing a message on its behalf, which
is exactly what §7 is.

---

## 6. Step 1 — init_ownership_transfer (already executed, verified on-chain)

Executed 2026-09-28 by the deployer (`terra1run9wz09uhh6pu7ggcwwetrgye4wu7wn26mawp`),
one `MsgExecuteContract` per contract:
`{"ownable":{"init_ownership_transfer":{"next_owner":"terra10d07y265gmmuvt4z0w9aw880jnsr700juxf95n"}}}`.

All 12 transactions confirmed with `code: 0` (success):

| Contract | Tx hash | Height |
|---|---|---|
| Mailbox | `0A82F4061242F3925F483F523A7050294A11F18B71039A90D447A3E5468E853B` | 30608995 |
| ISM Routing | `E0F753E6AB3397489E79104CDF3A19B9EEEB5910CFEE1BA163E719C92F75972A` | 30608996 |
| ISM Multisig ETH | `3012F2CC663C9F575921575542F95655E6E23C41F15D67C22ECEA500859961B5` | 30608998 |
| ISM Multisig BSC | `D59793F08616D2F6EED21A77CE327AE540F59E991ED0C317EAB4D4AB34D2D46F` | 30608999 |
| ISM Multisig Solana | `DAD5C59D1749A86508B3B4323578887694CC7450E7C7729C690CF663B70F8054` | 30609001 |
| Hook Aggregate (default) | `325F0E51F8F9348738FDEA953700B5F91F257108C9B70E4AF23AAD18795AEF33` | 30609002 |
| IGP | `7375F5737E3E5FDB8FAEB432C08E3AB30DCC565838D2ABC513F164A2A837AF2F` | 30609003 |
| Hook Aggregate (required) | `E4C7E26CC7C97BAFA83EB4083F3786B192821F3A59644865F4DF1D9E22A64EC3` | 30609004 |
| Hook Pausable | `00319F3CE044923A7B503E2DE85BFCFDD5934D2F4BEF0485394F65A2B6CA5E80` | 30609006 |
| Hook Fee | `86A08F96AA8C9F49ED7A541086C0FE310F335CB1808AD8BA133CE77433773553` | 30609007 |
| Warp LUNC | `5CFC5AB62513063186A968C0F82FEDFF1A92795AF9FC0A1B6A432150517E6708` | 30609009 |
| Warp USTC | `AAD0BA1DF959F49CF0383D4B6BBC008B294140E4ED52DDB6444A9C4A547E10E4` | 30609011 |

Independently re-verifiable by anyone:
```bash
curl -s "https://lcd.terra-classic.hexxagon.io/cosmos/tx/v1beta1/txs/<TX_HASH>" \
  | jq '.tx_response.code, .tx_response.height'   # code must be 0
```

And the resulting state, queried directly (not from these tx receipts):
```bash
curl -s "https://lcd.terra-classic.hexxagon.io/cosmwasm/wasm/v1/contract/<CONTRACT>/smart/$(echo -n '{"ownable":{"get_pending_owner":{}}}' | base64 -w0)"
# -> data.pending_owner must be terra10d07y265gmmuvt4z0w9aw880jnsr700juxf95n
```
All 12 confirmed this way on 2026-09-28 (12/12 match, 0 mismatches).

---

## 7. Step 2 — this proposal (claim_ownership)

### 7.1 Message shape verification

`claim_ownership` requires `info.sender == pending_owner` exactly — no other
precondition:

```rust
// packages/ownable/src/lib.rs
pub fn claim_ownership(storage: &mut dyn Storage, sender: &Addr) -> StdResult<Event> {
    ensure!(PENDING_OWNER.exists(storage), "ownership is not transferring");
    ensure_eq!(sender, PENDING_OWNER.load(storage)?, "unauthorized");
    OWNER.save(storage, sender)?;
    PENDING_OWNER.remove(storage);
}
```

Every one of the 12 contracts wires `hpl_ownable` the same way, confirmed by
reading each contract's source directly (not assumed from convention):

```
contracts/core/mailbox/src/contract.rs:61:          Ownable(msg) => hpl_ownable::handle(...)
contracts/isms/routing/src/contract.rs:54:           Ownable(msg) => hpl_ownable::handle(...)
contracts/isms/multisig/src/contract.rs:51:          Ownable(msg) => hpl_ownable::handle(...)
contracts/hooks/aggregate/src/lib.rs:84:              ExecuteMsg::Ownable(msg) => hpl_ownable::handle(...)
contracts/hooks/pausable/src/lib.rs:69:               ExecuteMsg::Ownable(msg) => hpl_ownable::handle(...)
contracts/hooks/fee/src/lib.rs:82:                    ExecuteMsg::Ownable(msg) => hpl_ownable::handle(...)
contracts/igps/core/src/contract.rs:70:               ExecuteMsg::Ownable(msg) => hpl_ownable::handle(...)
contracts/warp/native/src/contract.rs:98:             Ownable(msg) => hpl_ownable::handle(...)
```

And every `ExecuteMsg` enum wraps it as a `#[cw_serde]` newtype variant
`Ownable(OwnableMsg)` (`packages/interface/src/{core/mailbox,isms/*,hook/*,igp/core,warp/*}.rs`),
which serializes to `{"ownable": {"claim_ownership": {}}}` — exactly the
message shape used in `claim-ownership-proposal.json`.

### 7.2 Behavior on partial failure

Cosmos SDK executes a proposal's messages atomically — if any one of the 12
`claim_ownership` calls in this proposal were to fail (e.g. a contract's
pending_owner had since changed), the entire proposal execution reverts;
there is no partial application. Given §6 already confirms all 12
pending_owner values are correct, this proposal is expected to succeed in
full or not at all.

---

## 8. Reversibility

- **Before this proposal passes:** the deployer remains the actual `owner` on
  all 12 contracts and can cancel any individual pending transfer with
  `{"ownable":{"revoke_ownership_transfer":{}}}`.
- **After this proposal passes:** governance is the owner of all 12
  contracts. Reverting requires a *new* governance proposal calling
  `init_ownership_transfer` back to a chosen address, then a wallet claiming
  it — i.e., undoing this requires the same democratic process that did it.

---

## 9. Git provenance

All source-code claims in §7.1 (the `hpl_ownable` logic and the per-contract
`ExecuteMsg::Ownable` wiring) were verified against:

- Repository: `git@github.com:terra-classic-hyperlane/cw-hyperlane.git`, `main` branch.
- Contract source verified against commit: `47a6cfc538af4a9067a4e8d221e68697e39428e9` (2026-09-28).
- This document and the tooling were first published in commit
  `b18cc218e782ac6743f14f30bbffa0a1cd1fe72f` (2026-09-28) and have been
  amended since — check `git log -- terraclassic/doc/GOVERNANCE-PROPOSAL-CLAIM-OWNERSHIP-AUDIT.md`
  for the current state rather than assuming any single hash is final.

This document, `transfer-ownership.sh`/`transfer-ownership.md`, and
`claim-ownership-proposal.json` are committed to the same repository so the
exact tooling and contract addresses used to build the proposal are
reproducible and auditable by anyone, not just quoted in a proposal summary.

---

## 10. Known pre-existing issue — multisig ISM duplicate-signature counting (code_id 11374)

**Found independently by community researcher Fragwuerdig**, posted
[on Discourse](https://discourse.luncgoblins.com/t/claim-hyperlane-infrastructure-ownership-for-governance/555/2?u=fragwuerdig)
2026-09-30, and confirmed by us the same day. This is a property of the code
already live on-chain — it is **not introduced or changed by this proposal**,
and does not affect the correctness of `claim_ownership` verified in §7.1.
Documented here so it isn't discovered twice and so the remediation path is
on record before the vote.

### 10.1 What's wrong

The three ISM Multisig contracts (§2, items #3–#5: ETH, BSC, Solana) all run
code_id `11374`, uploaded 2026-06-03 as the **unmodified official release**
`many-things/cw-hyperlane` tag `v0.0.7-rc0`
(`yarn cw-hpl upload remote v0.0.7-rc0 -n terraclassic` — see
`HYPERLANE_DEPLOYMENT-MAINNET_EN.md`). That release predates upstream
[PR #142](https://github.com/many-things/cw-hyperlane/commit/d07e55e17c791a5f6557f114e3fb6cb433d9b800)
("fix: correct multisig ism signature verification logic", merged
2024-11-11), which fixed `verify_message` in
`contracts/isms/multisig/src/query.rs`. Pre-fix, the loop decrements the
threshold counter for every signature that recovers to an address in the
validator set, **without checking whether that validator has already been
counted in this same verification**:

```rust
for signature in metadata.signatures {
    let pubkey = deps.api.secp256k1_recover_pubkey(&hashed_message, &signature[..64], signature[64] - 27)?;
    if validators.contains(&eth_addr(pubkey.into())?) {
        threshold -= 1;
        if threshold == 0 { break; }
    }
}
```

Impact: the relayer supplies the signature metadata for an inbound message.
Repeating one validator's own valid signature N times satisfies an N-of-M
threshold **by itself** — no collusion between validators needed. A single
compromised or malicious key in the validator set could forge acceptance of
an arbitrary inbound message on that ISM, including a warp transfer that
releases native LUNC/USTC from the Warp LUNC/USTC contracts (§2, items
#11–#12), since their default security path routes through this same ISM
(via ISM Routing, item #2).

**Bytecode verification (independently reproduced, not just claimed):**
on-chain `data_hash` for code_id 11374
(`32b07207c733ba7469f49d321c30cf00bacb8c9560dc92accd35df61e5e3a531`) matches
the upstream `v0.0.7-rc0` GitHub release sha256 exactly, and matches an
independent local rebuild from source tag `v0.0.7-rc0` (commit `eb791b56d`)
via `cosmwasm/optimizer:0.15.0`. Confirmed locally: `d07e55e` (the #142 fix)
**is** present in our fork's `main` branch (`terra-classic-hyperlane/cw-hyperlane`)
today — the fix exists in our source tree, it was simply never rebuilt and
re-uploaded as a new on-chain code after the original 2026-06-03 upload. Three
other upstream fixes merged into fork `main` after the deployed tag are
likewise absent on-chain: #138 (mailbox `Process` event emits local instead
of origin domain — cosmetic), #139 (pausable-ISM event name — cosmetic), #143
(allow disabling ISM/hook — feature).

### 10.2 Scope of exposure

The validator sets behind the affected ISMs (§2 items #3–#5) are the
**official Hyperlane mainnet validator sets** for each origin chain, not
TC-chosen keys:

| ISM | Domain | Validators | Threshold |
|---|---|---|---|
| ISM Multisig ETH | 1 | 9 | 6 |
| ISM Multisig BSC | 56 | 6 | 4 |
| ISM Multisig Solana | 1399811149 | 5 | 3 |

So exploitation requires one of those specific official validator keys to be
malicious or compromised — bounded, but real, and not something this
repository controls.

### 10.3 Remediation does not have to wait for this proposal

Migration (code upgrade) authority is the contract **admin**, which is
separate from **owner** (§3) and was already transferred to governance on
2026-09-29 for all three ISM Multisig contracts — independently of whether
proposal #12229 (this `owner` claim) passes. Governance can therefore fix
this with its own, separate `MsgMigrateContract` proposal at any time: build
code from current fork `main` (which already contains #142), upload it, and
migrate the three `terra187rzjc3…neldar` / `terra1nqj7qln…muj9xw` /
`terra10s3p36t…ucl50t` addresses to it. This does not depend on, and can run
in parallel with, the ownership handoff covered by this document. Once
`owner` also moves to governance (this proposal), migrating the `default`
Mailbox ISM and the Pausable hook to a current build is optional
cleanup — recommended, not required, since neither carries the
signature-verification bug (that's specific to `hpl_ism_multisig`).

---

## 11. Related files

- [`../../transfer-ownership.md`](../../transfer-ownership.md) — operator's
  guide (flags, flow, troubleshooting) for `transfer-ownership.sh`.
- [`../../transfer-ownership.sh`](../../transfer-ownership.sh) — the tooling
  that produced both steps.
- [`../HYPERLANE_DEPLOYMENT-MAINNET_EN.md`](../HYPERLANE_DEPLOYMENT-MAINNET_EN.md)
  — full mainnet deployment record, including the BSC/Ethereum/Solana side
  (out of scope for this proposal, documented for context).
- `packages/ownable/src/lib.rs`, `packages/interface/src/ownable.rs` —
  `hpl_ownable` implementation referenced in §7.1.
