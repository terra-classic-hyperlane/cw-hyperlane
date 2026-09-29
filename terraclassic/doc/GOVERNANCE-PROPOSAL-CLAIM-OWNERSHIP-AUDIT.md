# Governance Proposal Audit — Claim Ownership of Hyperlane Infrastructure (Terra Classic)

**Status as of 2026-09-28:** Step 1 (init_ownership_transfer) executed and verified
on-chain for all 14 contracts. Step 2 (the governance proposal itself) has been
generated but **not yet submitted** (currently under-funded — see §6).

This document exists so any validator, community member, or reviewer can
independently verify every claim behind the "Claim Hyperlane infrastructure
ownership for governance" proposal before voting, without having to trust the
proposer's word.

---

## 1. Executive summary

The Hyperlane infrastructure contracts on Terra Classic (mailbox, ISMs, hooks,
IGP, and the LUNC/USTC/ warp routes) were deployed and
administered by a single deployer wallet (`terra1run9wz09uhh6pu7ggcwwetrgye4wu7wn26mawp`)
during installation and testing. This proposal completes the handoff of that
administration to the chain's own governance module, so that future
configuration changes (validator set updates, hook/ISM changes, router
enrollment) require a community vote instead of one wallet's signature.

The IGP gas-oracle contract is **intentionally excluded** — it is governed
separately by its own dedicated oracle-governor contract and must stay that
way; it is not part of this proposal's scope.

The transfer is a standard two-step `hpl_ownable` handoff:
1. **`init_ownership_transfer`** — the deployer proposes governance as the next
   owner (**already done**, see §5).
2. **`claim_ownership`** — governance accepts (**this proposal**, see §6).

---

## 2. Scope — 14 contracts, one governance recipient

New owner for all 14: `terra10d07y265gmmuvt4z0w9aw880jnsr700juxf95n` — the
Terra Classic **x/gov module account** (provenance in §4).

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
| 13 | Warp IGORFAKE (cw20, discontinued test route) | `hpl_warp_cw20` | `terra1wr7krp8lpfddpzxfkxvmhfnxd06vkz34e7f0tk2vyau36j3d4pvs6pjpel` |
| 14 | Warp FAKEFAKE (cw20, discontinued test route) | `hpl_warp_cw20` | `terra1zkkk9km8f6gf5vgn4zf66ep0djztqqkvns8jws8c9f85v4tfxrvq9n2wlk` |

### 2.1 Excluded — never touched by this proposal

| Contract | Address | Why |
|---|---|---|
| IGP gas-oracle (`hpl_igp_oracle`) | `terra1j8xzgzk7vds5uzrplmnln4vcz6f205t9atdyflypzrr43cd5eh7scwqj0d` | Owned by its own dedicated oracle-governor contract (`terra1z7jmlky2cmsd9aslm4uxrsase2yjwz8k9rlk00ga8s7pxgljczjq9sv4hj`), confirmed on-chain. Out of scope by design, and hard-excluded in the tooling regardless of on-chain state. |

### 2.2 Not ownable — no `owner` field exists, nothing to transfer

| Contract | Address |
|---|---|
| Validator Announce | `terra1gtnmdevekgxpvzej3wfy20e2n335gm3muwj6geduxxa86j3x70cq00asmy` |
| Hook Merkle (leaf of the default Aggregate hook) | `terra183lq6yqp8km3p34cxgk6k3u78uy4plqahey6rne7n9gy98delr9qyp0n2p` |

Both confirmed by querying `{"ownable":{"get_owner":{}}}` on-chain: the query
returns a parse error (`unknown variant 'ownable'`) because these contract
types never implement the `hpl_ownable` interface at all — not a permissions
issue, the code genuinely has no such query/execute variant.

---

## 3. What does NOT change

- **Migration admin** (code-upgrade authority, separate from `owner`) is
  **not** part of this proposal. It stays with the deployer wallet for now,
  and is intentionally deferred to a later, separate proposal — only after
  governance has claimed `owner` here, so the deployer is never left without
  any control mid-transition. See `transfer-ownership.md` §8 for the
  `--include-admin` flow.
- The IGP gas-oracle's ownership (see §2.1).
- Nothing on BSC, Ethereum, or Solana — this proposal is Terra Classic-side
  only. The synthetic warp routes on those chains are governed separately, by
  each chain's own validator multisig (Safe on BSC, Squads on Solana),
  documented in `HYPERLANE_DEPLOYMENT-MAINNET_EN.md`.

---

## 4. Governance account provenance

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
is exactly what §6 is.

---

## 5. Step 1 — init_ownership_transfer (already executed, verified on-chain)

Executed 2026-09-28 by the deployer (`terra1run9wz09uhh6pu7ggcwwetrgye4wu7wn26mawp`),
one `MsgExecuteContract` per contract:
`{"ownable":{"init_ownership_transfer":{"next_owner":"terra10d07y265gmmuvt4z0w9aw880jnsr700juxf95n"}}}`.

All 14 transactions confirmed with `code: 0` (success):

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
| Warp IGORFAKE | `FAA1AFB63B14CCE41517AA9A977698F5031A748D28949099C0E1632ACA73FC7F` | 30609012 |
| Warp FAKEFAKE | `12F2661C77F0EBB4234E38E39F816E7C23CE04F7CA3B750430865536F6F49333` | 30609014 |

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
All 14 confirmed this way on 2026-09-28 (14/14 match, 0 mismatches).

---

## 6. Step 2 — this proposal (claim_ownership)

### 6.1 Message shape verification

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

Every one of the 14 contract types wires this the same way, confirmed by
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
contracts/warp/cw20/src/contract.rs:94:               Ownable(msg) => hpl_ownable::handle(...)
```

And every `ExecuteMsg` enum wraps it as a `#[cw_serde]` newtype variant
`Ownable(OwnableMsg)` (`packages/interface/src/{core/mailbox,isms/*,hook/*,igp/core,warp/*}.rs`),
which serializes to `{"ownable": {"claim_ownership": {}}}` — exactly the
message shape used in `claim-ownership-proposal.json`.

This same governance-executed `MsgExecuteContract` mechanism (bundling
multiple messages into one proposal, signed by the gov module account) has
already been used successfully in this project's history — see proposals
[#12200 and #12222](https://validator.info/terra-classic/governance/12222),
referenced in `HYPERLANE_DEPLOYMENT-MAINNET_EN.md`.

### 6.2 Proposal contents

- **Title:** "Claim Hyperlane infrastructure ownership for governance"
- **Messages:** 14× `/cosmwasm.wasm.v1.MsgExecuteContract`, one per contract in
  §2, `sender` = governance, `msg` = `{"ownable":{"claim_ownership":{}}}`.
- **Chain minimum deposit:** live-queried from
  `https://lcd.terra-classic.hexxagon.io/cosmos/gov/v1/params/deposit` —
  `min_deposit` is **5,000,000,000,000 uluna (5,000,000 LUNC)** as of
  2026-09-28 (`voting_period` 604800s, `quorum` 40%, `threshold` 50%,
  `veto_threshold` 33.4%). This is a governance parameter and can change —
  always re-fetch before submitting rather than trusting a hardcoded figure.
- **Actual deposit in the current proposal file:** `2,417,579,670,000 uluna`
  (2,417,579.67 LUNC — a **partial initial deposit**, ~48.4% of the chain
  minimum, matching the deployer wallet's available balance at generation
  time). `min_initial_deposit_ratio` on this chain is `0`, so a proposal can
  be submitted with a partial deposit and enter the deposit period; it only
  moves to voting once the full 5,000,000 LUNC is reached (any wallet can top
  it up via `MsgDeposit` within the 14-day `max_deposit_period`, not
  necessarily the original submitter).
- File: `claim-ownership-proposal.json` (repo root), generated by
  `./transfer-ownership.sh --claim --execute` and hand-edited for the partial
  deposit amount above.

### 6.3 Behavior on partial failure

Cosmos SDK executes a proposal's messages atomically — if any one of the 14
`claim_ownership` calls were to fail (e.g. a contract's pending_owner had
since changed), the entire proposal execution reverts; there is no partial
application. Given §5 already confirms all 14 pending_owner values are
correct, this proposal is expected to succeed in full or not at all.

---

## 7. Reversibility

- **Before this proposal passes:** the deployer remains the actual `owner` on
  all 14 contracts and can cancel any individual pending transfer with
  `{"ownable":{"revoke_ownership_transfer":{}}}`.
- **After this proposal passes:** governance is the owner. Reverting requires
  a *new* governance proposal calling `init_ownership_transfer` back to a
  chosen address, then a wallet claiming it — i.e., undoing this requires the
  same democratic process that did it.

---

## 8. Git provenance

All source-code claims in §6.1 (the `hpl_ownable` logic and the per-contract
`ExecuteMsg::Ownable` wiring) were verified against:

- Repository: `git@github.com:terra-classic-hyperlane/cw-hyperlane.git`
- Contract source verified against commit: `47a6cfc538af4a9067a4e8d221e68697e39428e9` (2026-09-28)
- This document, the tooling, and the proposal snapshot: commit
  `b18cc218e782ac6743f14f30bbffa0a1cd1fe72f` (2026-09-28, not yet pushed to
  `origin` at the time of writing — check `git log` on the branch for the
  latest pushed state before relying on this hash being public).

This document, `transfer-ownership.sh`/`transfer-ownership.md`, and
`claim-ownership-proposal.json` are committed to the same repository so the
exact tooling and contract addresses used to build the proposal are
reproducible and auditable by anyone, not just quoted in a proposal summary.

---

## 9. Related files

- [`../../transfer-ownership.md`](../../transfer-ownership.md) — operator's
  guide (flags, flow, troubleshooting) for `transfer-ownership.sh`.
- [`../../transfer-ownership.sh`](../../transfer-ownership.sh) — the tooling
  that produced both steps.
- [`../HYPERLANE_DEPLOYMENT-MAINNET_EN.md`](../HYPERLANE_DEPLOYMENT-MAINNET_EN.md)
  — full mainnet deployment record, including the BSC/Ethereum/Solana side
  (out of scope for this proposal, documented for context).
- `packages/ownable/src/lib.rs`, `packages/interface/src/ownable.rs` —
  `hpl_ownable` implementation referenced in §6.1.
