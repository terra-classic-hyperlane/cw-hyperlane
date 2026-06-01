# Transfer Ownership to Governance — Hyperlane Terra Classic

## Overview

Yes — it is fully possible to deploy all Hyperlane contracts with your own wallet as administrator and then transfer ownership to the governance module at any time.

The Hyperlane contracts implement a **2-step ownership transfer** pattern (based on `hpl_ownable`):

```
Step 1 (admin wallet)   → InitOwnershipTransfer { next_owner: governance_address }
Step 2 (governance)     → ClaimOwnership {}  (via governance proposal)
```

This prevents accidental transfers: the new owner must actively accept the ownership.

---

## Governance Module Address

On both **Terra Classic Mainnet (columbus-5)** and **Testnet (rebel-2)**:

```
terra10d07y265gmmuvt4z0w9aw880jnsr700juxf95n
```

This is a deterministic module account address derived from the module name `gov` in the Cosmos SDK. It is the same on all Terra Classic networks.

---

## Contracts Covered

All 10 contracts with the `ownable` interface:

| Contract | Address | Execute Key |
|----------|---------|-------------|
| Mailbox | `terra1s4jwfe0tcaztpfsct5wzj02esxyjy7e7lhkcwn5dp04yvly82rwsvzyqmm` | `ownable` |
| ISM Routing | `terra1na6ljyf4m5x2u7llfvvxxe2nyq0t8628qyk0vnwu4ttpq86tt0cse47t68` | `ownable` |
| ISM Multisig (Solana) | `terra18gh7nl0tk047ykrvy0a8z2lhv0rvl65wu95texyawrj879qenysq02p98f` | `ownable` |
| ISM Multisig (BSC) | `terra1ksq6cekt0as2f9vv5txld90s854y4pkr2k0jn5p83vqpa5zzzfysuavxr0` | `ownable` |
| Hook Aggregate (default) | `terra18shx4zhfehscggs9upspl489qd7yg29vdasvrerytppt3am92mnsj5365s` | `ownable` |
| IGP | `terra1mcaqgr7kqs9xr3q6w0e9f2ekrj6sehwcep9shtss6u8pdz2rsw5qzrew7r` | `ownable` |
| **IGP Oracle** | `terra1yew4y2ekzhkwuuz07yt7qufqxxejxhmnr7apehkqk7e8jdw8ffqqs8zhds` | **`ownership`** ⚠️ |
| Hook Aggregate (required) | `terra16veqgkz2yzvgmhyw8rn5k8fue4wysey077zmexevv7hm6ud4my0q8g3krq` | `ownable` |
| Hook Pausable | `terra12qw82wwutq6hpswfgqfkcjdr0z4fqg4wus9np0uhxdngfwy6lf7s2xsq7d` | `ownable` |
| Hook Fee | `terra1g8yzt275smsneyp8qrejc2v99dutt6yhfa8x4yylprh4x9vep7gsxuq2q8` | `ownable` |

> **Important:** The IGP Oracle contract uses the execute key `ownership` (not `ownable`) for execute messages, but uses `ownable` for query messages. This is a difference in the Rust `ExecuteMsg` enum variant name.

**Contracts WITHOUT ownable interface (no transfer needed):**
- `hpl_validator_announce` — no owner, permissionless
- `hpl_hook_merkle` — no owner, stateless

---

## Step-by-Step Process

### Step 1 — Init Transfer (admin wallet)

Call `InitOwnershipTransfer` on every ownable contract. This registers the governance module as the **pending owner** without transferring control yet.

**For most contracts:**
```bash
terrad tx wasm execute <CONTRACT_ADDRESS> \
  '{"ownable":{"init_ownership_transfer":{"next_owner":"terra10d07y265gmmuvt4z0w9aw880jnsr700juxf95n"}}}' \
  --from YOUR_KEY --chain-id rebel-2 --node https://rpc.luncblaze.com \
  --gas auto --gas-adjustment 1.5 --gas-prices 28.325uluna \
  --keyring-backend file -y
```

**For IGP Oracle only (uses `ownership` key):**
```bash
terrad tx wasm execute terra1yew4y2ekzhkwuuz07yt7qufqxxejxhmnr7apehkqk7e8jdw8ffqqs8zhds \
  '{"ownership":{"init_ownership_transfer":{"next_owner":"terra10d07y265gmmuvt4z0w9aw880jnsr700juxf95n"}}}' \
  --from YOUR_KEY --chain-id rebel-2 --node https://rpc.luncblaze.com \
  --gas auto --gas-adjustment 1.5 --gas-prices 28.325uluna \
  --keyring-backend file -y
```

**Or use the automated script:**
```bash
export TERRA_KEY_NAME="your-key-name"
./transfer-ownership-to-governance.sh
```

### Step 2 — Claim Ownership (governance proposal)

After Step 1, each contract has the governance module as `pending_owner`. To complete the transfer, a governance proposal must execute `ClaimOwnership` on all contracts.

The script generates the proposal JSON automatically in `log/governance-claim-ownership-*.json`.

**Submit the proposal:**
```bash
terrad tx gov submit-proposal log/governance-claim-ownership-TIMESTAMP.json \
  --from YOUR_KEY --chain-id rebel-2 --node https://rpc.luncblaze.com \
  --gas auto --gas-adjustment 1.5 --gas-prices 28.325uluna \
  --keyring-backend file -y
```

**Vote YES:**
```bash
terrad tx gov vote <PROPOSAL_ID> yes \
  --from YOUR_KEY --chain-id rebel-2 --node https://rpc.luncblaze.com \
  --gas auto --gas-adjustment 1.5 --gas-prices 28.325uluna \
  --keyring-backend file -y
```

### Step 3 — Verify Ownership

After the proposal passes, verify all contracts now belong to governance:

```bash
LCD="https://lcd.luncblaze.com"
GOVERNANCE="terra10d07y265gmmuvt4z0w9aw880jnsr700juxf95n"

for contract in \
  terra1s4jwfe0tcaztpfsct5wzj02esxyjy7e7lhkcwn5dp04yvly82rwsvzyqmm \
  terra1na6ljyf4m5x2u7llfvvxxe2nyq0t8628qyk0vnwu4ttpq86tt0cse47t68 \
  terra18gh7nl0tk047ykrvy0a8z2lhv0rvl65wu95texyawrj879qenysq02p98f \
  terra1ksq6cekt0as2f9vv5txld90s854y4pkr2k0jn5p83vqpa5zzzfysuavxr0 \
  terra18shx4zhfehscggs9upspl489qd7yg29vdasvrerytppt3am92mnsj5365s \
  terra1mcaqgr7kqs9xr3q6w0e9f2ekrj6sehwcep9shtss6u8pdz2rsw5qzrew7r \
  terra1yew4y2ekzhkwuuz07yt7qufqxxejxhmnr7apehkqk7e8jdw8ffqqs8zhds \
  terra16veqgkz2yzvgmhyw8rn5k8fue4wysey077zmexevv7hm6ud4my0q8g3krq \
  terra12qw82wwutq6hpswfgqfkcjdr0z4fqg4wus9np0uhxdngfwy6lf7s2xsq7d \
  terra1g8yzt275smsneyp8qrejc2v99dutt6yhfa8x4yylprh4x9vep7gsxuq2q8; do
  Q=$(echo -n '{"ownable":{"get_owner":{}}}' | base64 -w0)
  owner=$(curl -s "$LCD/cosmwasm/wasm/v1/contract/$contract/smart/$Q" | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['owner'])" 2>/dev/null)
  if [ "$owner" = "$GOVERNANCE" ]; then
    echo "✅ $contract → governance"
  else
    echo "⚠️  $contract → $owner"
  fi
done
```

---

## What Changes After the Transfer

| Action | Before transfer (admin wallet) | After transfer (governance) |
|--------|-------------------------------|----------------------------|
| Change IGP gas prices | `terrad tx wasm execute` from your wallet | Governance proposal required |
| Change ISM validators | `terrad tx wasm execute` from your wallet | Governance proposal required |
| Update Hook Fee amount | `terrad tx wasm execute` from your wallet | Governance proposal required |
| Pause the system (Hook Pausable) | `terrad tx wasm execute` from your wallet | Governance proposal required |
| Set default ISM in Mailbox | `terrad tx wasm execute` from your wallet | Governance proposal required |

---

## What Does NOT Change

- Contract addresses remain the same
- Existing ISM validator sets and thresholds remain unchanged
- Existing IGP oracle gas configurations remain unchanged
- Messages in transit are not affected
- The `hpl_validator_announce` and `hpl_hook_merkle` contracts are unaffected (no owner)

---

## Important: Can the Transfer Be Revoked?

**Yes — but only before Step 2 (ClaimOwnership) is executed.**

If you called `InitOwnershipTransfer` but the governance proposal has not yet passed, you can cancel the pending transfer:

```bash
# Cancel pending transfer (admin wallet only, before governance claims ownership)
terrad tx wasm execute <CONTRACT_ADDRESS> \
  '{"ownable":{"revoke_ownership_transfer":{}}}' \
  --from YOUR_KEY --chain-id rebel-2 --node https://rpc.luncblaze.com \
  --gas auto --gas-adjustment 1.5 --gas-prices 28.325uluna \
  --keyring-backend file -y
```

**Once the governance proposal passes and `ClaimOwnership` is executed, the transfer is permanent.** Your admin wallet will no longer be able to make direct changes — all future changes require a governance proposal.

---

## Governance Proposal Structure (ClaimOwnership)

The proposal generated by the script has this structure:

```json
{
  "messages": [
    {
      "@type": "/cosmwasm.wasm.v1.MsgExecuteContract",
      "sender": "terra10d07y265gmmuvt4z0w9aw880jnsr700juxf95n",
      "contract": "<CONTRACT_ADDRESS>",
      "msg": {"ownable": {"claim_ownership": {}}},
      "funds": []
    }
    // ... repeated for each contract
    // IGP Oracle uses "ownership" instead of "ownable"
  ],
  "title": "Hyperlane: Transfer Protocol Ownership to Governance",
  "summary": "..."
}
```

---

## Ownable Interface Reference

**Query current owner:**
```json
{"ownable": {"get_owner": {}}}
```

**Query pending owner (after InitOwnershipTransfer, before ClaimOwnership):**
```json
{"ownable": {"get_pending_owner": {}}}
```

**Execute — Init transfer (admin wallet):**
```json
{"ownable": {"init_ownership_transfer": {"next_owner": "NEW_OWNER_ADDRESS"}}}
```

**Execute — Revoke pending transfer (admin wallet, before claim):**
```json
{"ownable": {"revoke_ownership_transfer": {}}}
```

**Execute — Claim ownership (new owner only):**
```json
{"ownable": {"claim_ownership": {}}}
```

> Replace `ownable` with `ownership` for the IGP Oracle contract only.

---

## Quick Reference

```
Admin wallet address  : terra12awgqgwm2evj05ndtgs0xa35uunlpc76d85pze
Governance address    : terra10d07y265gmmuvt4z0w9aw880jnsr700juxf95n
Network               : rebel-2 (Terra Classic Testnet)
LCD                   : https://lcd.luncblaze.com
Script                : ../transfer-ownership-to-governance.sh
```

---

**Last updated**: 2026-06-01  
**Source**: Contracts verified on-chain via `check-contract-config.sh`
