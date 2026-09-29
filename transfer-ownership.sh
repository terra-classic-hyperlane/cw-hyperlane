#!/usr/bin/env bash
#
# transfer-ownership.sh — Transfers owner (and, optionally, migration admin) of
# ALL Hyperlane contracts on Terra Classic to the GOVERNANCE account.
#
# Scope: every ownable contract discovered in context/terraclassic.json,
# INCLUDING the LUNC/USTC warp routes and the test cw20 warps (IGORFAKE/
# FAKEFAKE) — full inventory, see TRANSFER-OWNERSHIP-TO-GOVERNANCE.md.
#
# HARD EXCLUSION: the IGP gas-oracle contract is NEVER touched by this script,
# under any mode, regardless of its on-chain owner. It is governed separately
# by its own dedicated oracle-governor contract and must stay that way — see
# HARD_EXCLUDE below.
#
# >>> SAFE BY DEFAULT: runs in --dry-run (does NOT execute anything). <<<
# Pass --execute explicitly to actually run something.
#
# Mechanism (confirmed in the hpl_ownable code, packages/ownable/src/lib.rs):
#   - OWNER transfer is TWO STEPS:
#       1) YOU (current owner) call  init_ownership_transfer { next_owner: GOV }
#       2) GOVERNANCE claims          claim_ownership {}       (must accept!)
#     Until governance claims, YOU remain the owner.
#   - ADMIN transfer (migration authority) is ONE STEP: set-contract-admin
#     (immediate).
#
# GOVERNANCE_ADDRESS below is the real Terra Classic x/gov module account
# (verified on-chain via /cosmos/auth/v1beta1/module_accounts, name "gov").
# A module account has NO private key — it cannot sign a plain tx. So the
# claim_ownership step CANNOT be done with `--from <key>`; it can only happen
# through a passed on-chain governance proposal that executes
# MsgExecuteContract on its behalf. See --claim below: instead of trying to
# sign anything, it generates that proposal's JSON for you to submit with
# `terrad tx gov submit-proposal`.
#
# Usage:
#   ./transfer-ownership.sh                                 # dry-run: step 1 (init transfer)
#   ./transfer-ownership.sh --include-admin                 # dry-run: + set-contract-admin
#   ./transfer-ownership.sh --claim                         # dry-run: preview the claim proposal JSON
#   ./transfer-ownership.sh --key mykey --execute            # ACTUALLY runs step 1 (careful!)
#   ./transfer-ownership.sh --claim --execute                # writes claim-ownership-proposal.json to disk (no key needed — nothing is signed)
#   --key <name> sets SIGNER_KEY to a name from `terrad keys list` (only
#   needed for --execute without --claim; the actual step 1 signer).
#
set -euo pipefail

# ============================================================================
# CONFIGURATION (verified on-chain 2026-09-28 — see TRANSFER-OWNERSHIP-TO-GOVERNANCE.md)
# ============================================================================

# Governance account that will receive owner/admin (terra1...).
# = the real x/gov module account, same on mainnet (columbus-5) and testnet.
GOVERNANCE_ADDRESS="terra10d07y265gmmuvt4z0w9aw880jnsr700juxf95n"

# Current owner of all target contracts (terra1...). Used as a SAFETY FILTER:
# the script only touches contracts whose on-chain owner == this address.
CURRENT_OWNER="terra1run9wz09uhh6pu7ggcwwetrgye4wu7wn26mawp"

# Contract(s) that must NEVER be touched by this script, no matter what.
# hpl_igp_oracle — governed by its own dedicated oracle-governor contract
# (terra1z7jmlky2cmsd9aslm4uxrsase2yjwz8k9rlk00ga8s7pxgljczjq9sv4hj), not by
# this migration. Explicitly excluded per direct instruction, in addition to
# already failing the CURRENT_OWNER filter naturally.
HARD_EXCLUDE=(
  "terra1j8xzgzk7vds5uzrplmnln4vcz6f205t9atdyflypzrr43cd5eh7scwqj0d"  # hpl_igp_oracle — DO NOT TOUCH
)

# Name of the keyring key that signs transactions (terrad keys list).
#   - Normal mode: YOUR key (current deployer/owner).
#   - --claim never signs anything itself anymore (see header) — SIGNER_KEY is
#     unused in that mode.
SIGNER_KEY=""

# Network
BINARY="terrad"
CHAIN_ID="columbus-5"
NODE="https://terra-classic-rpc.publicnode.com:443"
LCD="https://lcd.terra-classic.hexxagon.io"
GAS_PRICES="28.325uluna"
GAS_ADJUST="2.0"

# Deploy context file (source of all contract addresses)
CONTEXT_FILE="$(cd "$(dirname "$0")" && pwd)/context/terraclassic.json"

# Extra infrastructure contracts that happen not to be in the context json —
# add here. The script validates each one via get_owner just like the rest.
EXTRA_CONTRACTS=(
  # "terra1..."
)

# ============================================================================
# NO NEED TO EDIT BELOW
# ============================================================================

DRY_RUN=1
INCLUDE_ADMIN=0
ADMIN_ONLY=0
CLAIM_MODE=0

while [ $# -gt 0 ]; do
  case "$1" in
    --execute)       DRY_RUN=0 ;;
    --dry-run)       DRY_RUN=1 ;;
    --include-admin) INCLUDE_ADMIN=1 ;;
    --admin-only)    INCLUDE_ADMIN=1; ADMIN_ONLY=1 ;;
    --claim)         CLAIM_MODE=1 ;;
    --key)
      shift
      [ $# -gt 0 ] || { echo "--key requires a keyring key name"; exit 1; }
      SIGNER_KEY="$1"
      ;;
    -h|--help)
      grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
  shift
done

c_red=$'\e[31m'; c_grn=$'\e[32m'; c_ylw=$'\e[33m'; c_cyn=$'\e[36m'; c_off=$'\e[0m'
die(){ echo "${c_red}ERROR:${c_off} $*" >&2; exit 1; }
note(){ echo "${c_cyn}»${c_off} $*"; }

# ---- validation --------------------------------------------------------
command -v "$BINARY" >/dev/null 2>&1 || die "binary '$BINARY' not found in PATH."
command -v python3   >/dev/null 2>&1 || die "python3 is required to read/write JSON."
[ -f "$CONTEXT_FILE" ] || die "context file not found: $CONTEXT_FILE"
[[ "$GOVERNANCE_ADDRESS" == terra1* ]] || die "configure GOVERNANCE_ADDRESS (terra1...)."
[[ "$CURRENT_OWNER"      == terra1* ]] || die "configure CURRENT_OWNER (terra1...)."

if [ "$DRY_RUN" -eq 0 ] && [ "$CLAIM_MODE" -eq 0 ]; then
  [[ -n "$SIGNER_KEY" ]] || die "--execute (step 1) requires SIGNER_KEY to be set."
fi

is_excluded(){
  local addr="$1"
  for ex in "${HARD_EXCLUDE[@]}"; do
    [ "$addr" = "$ex" ] && return 0
  done
  return 1
}

# ---- collect candidate addresses ---------------------------------------
# Every terra1... that looks like a CONTRACT (32-byte payload bech32) found
# anywhere in the context json (core, isms, hooks, AND warp — nothing is
# skipped by category) + EXTRA_CONTRACTS.
mapfile -t CTX_ADDRS < <(python3 - "$CONTEXT_FILE" <<'PY'
import json,sys,re
d=json.load(open(sys.argv[1]))
seen=[]
def walk(o):
    if isinstance(o,dict):
        for v in o.values(): walk(v)
    elif isinstance(o,list):
        for v in o: walk(v)
    elif isinstance(o,str):
        # Terra Classic contracts use 32-byte payloads -> long bech32 (~63 chars)
        if re.fullmatch(r"terra1[0-9a-z]{58}", o) and o not in seen:
            seen.append(o)
walk(d)
print("\n".join(seen))
PY
)

CANDIDATES=("${CTX_ADDRS[@]}")
for a in "${EXTRA_CONTRACTS[@]}"; do
  [[ "$a" == terra1* ]] && CANDIDATES+=("$a")
done

# dedup
mapfile -t CANDIDATES < <(printf '%s\n' "${CANDIDATES[@]}" | awk 'NF && !seen[$0]++')

[ "${#CANDIDATES[@]}" -gt 0 ] || die "no candidate addresses found."

echo
echo "============================================================"
echo " Ownership transfer — Hyperlane Terra Classic"
echo "============================================================"
echo " Mode             : $( [ "$CLAIM_MODE" -eq 1 ] && echo 'CLAIM (generates governance proposal JSON)' || echo 'INIT TRANSFER (run by you, the current owner)' )"
echo " Execution        : $( [ "$DRY_RUN" -eq 1 ] && echo "${c_ylw}DRY-RUN (nothing executed/written)${c_off}" || echo "${c_red}REAL EXECUTION${c_off}" )"
echo " Governance (GOV) : $GOVERNANCE_ADDRESS"
echo " Current owner    : $CURRENT_OWNER"
echo " Hard-excluded    : ${HARD_EXCLUDE[*]}"
echo " Include admin    : $( [ "$INCLUDE_ADMIN" -eq 1 ] && echo 'YES' || echo 'no' )"
echo " Candidates       : ${#CANDIDATES[@]} address(es)"
echo "============================================================"
echo

TXFLAGS=(--chain-id "$CHAIN_ID" --node "$NODE" --gas auto \
         --gas-adjustment "$GAS_ADJUST" --gas-prices "$GAS_PRICES" \
         --from "$SIGNER_KEY" -y -b sync -o json)

# The public RPC node occasionally answers with a transient 503 under rapid
# sequential queries — retry a few times before concluding a contract has no
# owner. A false negative here would silently drop a real contract from the
# eligible list, so this is not just cosmetic.
retry_query(){
  local attempt out
  for attempt in 1 2 3; do
    out="$("$@" 2>/dev/null || true)"
    [ -n "$out" ] && { echo "$out"; return 0; }
    sleep 2
  done
  echo "$out"
}
q_owner(){ # echo owner address, or nothing if not ownable
  local out
  out="$(retry_query "$BINARY" query wasm contract-state smart "$1" '{"ownable":{"get_owner":{}}}' \
     --node "$NODE" -o json)"
  echo "$out" | python3 -c 'import sys,json;
try:
 print(json.load(sys.stdin)["data"]["owner"])
except Exception: pass' 2>/dev/null || true
}
q_pending_owner(){ # echo pending_owner address, or nothing if none/not ownable
  local out
  out="$(retry_query "$BINARY" query wasm contract-state smart "$1" '{"ownable":{"get_pending_owner":{}}}' \
     --node "$NODE" -o json)"
  echo "$out" | python3 -c 'import sys,json;
try:
 v = json.load(sys.stdin)["data"]["pending_owner"]
 print(v if v else "")
except Exception: pass' 2>/dev/null || true
}
q_admin(){ # echo current migration-admin of the contract
  local out
  out="$(retry_query "$BINARY" query wasm contract "$1" --node "$NODE" -o json)"
  echo "$out" | python3 -c 'import sys,json;
try:
 print(json.load(sys.stdin)["contract_info"]["admin"])
except Exception: pass' 2>/dev/null || true
}

ELIGIBLE=(); SKIP=()
note "Querying on-chain owner of each candidate..."
echo
for addr in "${CANDIDATES[@]}"; do
  if is_excluded "$addr"; then
    SKIP+=("$addr  (HARD-EXCLUDED — igp_oracle, governed separately) — skipped")
    printf "  %s  %s\n" "${c_red}EXCL${c_off}" "$addr  (hard-excluded: igp_oracle)"
    continue
  fi
  owner="$(q_owner "$addr")"
  if [ -z "$owner" ]; then
    SKIP+=("$addr  (not ownable, e.g. validator_announce/merkle hook) — skipped")
    printf "  %s  %s\n" "${c_ylw}skip${c_off}" "$addr  (no get_owner)"
    continue
  fi
  if [ "$owner" != "$CURRENT_OWNER" ]; then
    SKIP+=("$addr  (owner = $owner ≠ you) — skipped")
    printf "  %s  %s\n" "${c_ylw}skip${c_off}" "$addr  (owner is already $owner)"
    continue
  fi
  ELIGIBLE+=("$addr")
  printf "  %s  %s\n" "${c_grn}ok  ${c_off}" "$addr"
done

echo
echo "------------------------------------------------------------"
echo " Eligible (owner == you): ${#ELIGIBLE[@]}    |    Skipped: ${#SKIP[@]}"
echo "------------------------------------------------------------"
echo

[ "${#ELIGIBLE[@]}" -gt 0 ] || { note "Nothing to do."; exit 0; }

FAILED_TXS=()  # collected for a final summary — see the end of the script

run_or_show(){ # $1 = description, rest = command
  local desc="$1"; shift
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "  # $desc"
    echo "  $*"
    echo
  else
    echo "  ▶ $desc"
    local tmpfile hash code raw_log
    tmpfile=$(mktemp)
    # Pipe through tee (not `$(...)` capture) so an interactive keyring
    # passphrase prompt still reaches the terminal live — capturing stdout
    # into a variable silently swallowed that prompt, leaving the script
    # looking hung while it was actually just waiting for input on stdin.
    "$@" 2>&1 | tee "$tmpfile" || true
    # The file also contains the passphrase prompt text (mixed via 2>&1), so
    # the JSON result is only ONE line among others — try each line, keep the
    # first one that parses and has a txhash, instead of parsing the whole file.
    hash=$(python3 -c 'import sys,json
for line in open(sys.argv[1]):
    line = line.strip()
    if not line.startswith("{"):
        continue
    try:
        h = json.loads(line).get("txhash", "")
        if h:
            print(h)
            break
    except Exception:
        continue' "$tmpfile" 2>/dev/null)
    rm -f "$tmpfile"
    if [ -z "$hash" ]; then
      echo "  ${c_red}⚠ could not extract a txhash from the response — verify manually.${c_off}"
      FAILED_TXS+=("$desc -> no txhash returned")
      echo
      return
    fi
    # A 'sync' broadcast only confirms CheckTx (mempool acceptance), NOT that
    # the transaction actually succeeded on-chain (DeliverTx). Wait for block
    # inclusion, then check the REAL result — otherwise a failed tx (e.g. out
    # of gas) looks identical to a successful one in the immediate response.
    sleep 6
    out="$(curl -s --max-time 10 "$LCD/cosmos/tx/v1beta1/txs/$hash")"
    code=$(echo "$out" | python3 -c 'import sys,json
try: print(json.load(sys.stdin)["tx_response"]["code"])
except Exception: print("?")' 2>/dev/null)
    if [ "$code" = "0" ]; then
      echo "  ${c_grn}✓ confirmed on-chain (code 0)${c_off}"
    else
      raw_log=$(echo "$out" | python3 -c 'import sys,json
try: print(json.load(sys.stdin)["tx_response"]["raw_log"][:250])
except Exception: print("(could not fetch raw_log)")' 2>/dev/null)
      echo "  ${c_red}✗ FAILED on-chain (code $code): $raw_log${c_off}"
      FAILED_TXS+=("$desc -> tx $hash failed, code $code: $raw_log")
    fi
    echo
  fi
}

if [ "$CLAIM_MODE" -eq 1 ]; then
  # ---- CLAIM mode: build the governance proposal JSON ---------------------
  # GOVERNANCE_ADDRESS is the real x/gov module account: it has no private key,
  # so claim_ownership can only happen via a passed governance proposal that
  # executes MsgExecuteContract on the module's behalf — same pattern as
  # terraclassic/submit-proposal-mainnet.ts.
  OUT_FILE="claim-ownership-proposal.json"
  note "Building the governance proposal that claims ownership on all ${#ELIGIBLE[@]} contract(s)..."
  echo

  if [ "$DRY_RUN" -eq 1 ]; then
    echo "  # Would write $OUT_FILE with one MsgExecuteContract per contract:"
    for addr in "${ELIGIBLE[@]}"; do
      echo "  #   $addr  ->  {\"ownable\":{\"claim_ownership\":{}}}"
    done
    echo
    note "DRY-RUN: nothing written. Re-run with --claim --execute to write $OUT_FILE."
  else
    # Query the REAL on-chain minimum deposit — never hardcode this, it's a
    # governance parameter that can change (and has, historically).
    MIN_DEPOSIT_JSON=$(curl -s "$LCD/cosmos/gov/v1/params/deposit")
    MIN_DEPOSIT_AMOUNT=$(echo "$MIN_DEPOSIT_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['params']['min_deposit'][0]['amount'])" 2>/dev/null || echo "")
    MIN_DEPOSIT_DENOM=$(echo "$MIN_DEPOSIT_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['params']['min_deposit'][0]['denom'])" 2>/dev/null || echo "")
    [ -n "$MIN_DEPOSIT_AMOUNT" ] && [ -n "$MIN_DEPOSIT_DENOM" ] || die "could not fetch live min_deposit from $LCD/cosmos/gov/v1/params/deposit — check manually before submitting."
    DEPOSIT="${MIN_DEPOSIT_AMOUNT}${MIN_DEPOSIT_DENOM}"
    note "Live on-chain min_deposit: $DEPOSIT ($(python3 -c "print(int('$MIN_DEPOSIT_AMOUNT')/1e6)") LUNC)"

    python3 - "$OUT_FILE" "$GOVERNANCE_ADDRESS" "$DEPOSIT" "${ELIGIBLE[@]}" <<'PY'
import json, sys
out_file, gov, deposit = sys.argv[1], sys.argv[2], sys.argv[3]
contracts = sys.argv[4:]
proposal = {
    "title": "Claim Hyperlane infrastructure ownership for governance",
    "summary": (
        "Governance claims ownership (claim_ownership) of the Hyperlane "
        f"contracts on Terra Classic whose owner was already proposed to "
        f"governance ({gov}) via init_ownership_transfer. "
        "The IGP gas-oracle contract is intentionally NOT included: it is "
        "governed separately by its own dedicated oracle-governor contract."
    ),
    "messages": [
        {
            "@type": "/cosmwasm.wasm.v1.MsgExecuteContract",
            "sender": gov,
            "contract": c,
            "msg": {"ownable": {"claim_ownership": {}}},
            "funds": [],
        }
        for c in contracts
    ],
    "deposit": deposit,
    "expedited": False,
}
with open(out_file, "w") as f:
    json.dump(proposal, f, indent=2)
print(f"Wrote {out_file} with {len(contracts)} claim_ownership message(s).")
PY
    echo
    note "Submit it with:"
    echo "  $BINARY tx gov submit-proposal $OUT_FILE \\"
    echo "    --from <any_funding_key> --chain-id $CHAIN_ID --node $NODE \\"
    echo "    --gas auto --gas-adjustment $GAS_ADJUST --gas-prices $GAS_PRICES -y"
    echo
    note "After it passes, vote/verify, then check:"
    echo "  $BINARY query wasm contract-state smart <CONTRACT> '{\"ownable\":{\"get_owner\":{}}}' --node $NODE"
  fi
else
  # ---- INIT TRANSFER mode: you propose the transfer ------------------------
  if [ "$ADMIN_ONLY" -eq 1 ]; then
    note "Skipping step 1 (--admin-only) — going straight to migration admin."
  else
    note "Step 1 — init_ownership_transfer (run with YOUR key = $CURRENT_OWNER):"
    echo
    for addr in "${ELIGIBLE[@]}"; do
      pending="$(q_pending_owner "$addr")"
      if [ -n "$pending" ]; then
        echo "  ${c_ylw}skip${c_off} $addr  (already has a pending_owner: $pending)"
        continue
      fi
      run_or_show "init_ownership_transfer -> $GOVERNANCE_ADDRESS @ $addr" \
        "$BINARY" tx wasm execute "$addr" \
        "{\"ownable\":{\"init_ownership_transfer\":{\"next_owner\":\"$GOVERNANCE_ADDRESS\"}}}" \
        "${TXFLAGS[@]}"
    done
  fi

  if [ "$INCLUDE_ADMIN" -eq 1 ]; then
    echo "------------------------------------------------------------"
    note "Migration admin — set-contract-admin (ONE step, immediate, no proposal needed):"
    echo "${c_ylw}  This hands code-upgrade authority to governance right away — unlike owner,${c_off}"
    echo "${c_ylw}  admin transfer has no accept step, so there is no reason to sequence it${c_off}"
    echo "${c_ylw}  after the owner claim unless you specifically want that safety margin.${c_off}"
    echo
    for addr in "${ELIGIBLE[@]}"; do
      cur_admin="$(q_admin "$addr")"
      if [ "$cur_admin" != "$CURRENT_OWNER" ]; then
        echo "  ${c_ylw}skip admin${c_off} $addr  (current admin = ${cur_admin:-<none/immutable>})"
        continue
      fi
      run_or_show "set-contract-admin -> $GOVERNANCE_ADDRESS @ $addr" \
        "$BINARY" tx wasm set-contract-admin "$addr" "$GOVERNANCE_ADDRESS" "${TXFLAGS[@]}"
    done
  fi

  echo "------------------------------------------------------------"
  note "REMEMBER: the owner only changes for real once GOVERNANCE claims it —"
  note "governance has no private key, so this needs a passed proposal:"
  echo "        ./transfer-ownership.sh --claim            (preview)"
  echo "        ./transfer-ownership.sh --claim --execute  (writes claim-ownership-proposal.json)"
  echo "        $BINARY tx gov submit-proposal claim-ownership-proposal.json --from <any_key> ..."
  echo "  To CANCEL before the claim:"
  echo "        $BINARY tx wasm execute <CONTRACT> '{\"ownable\":{\"revoke_ownership_transfer\":{}}}' --from <your_key> ..."
fi

echo
note "Check the result of any contract:"
echo "  $BINARY query wasm contract-state smart <CONTRACT> '{\"ownable\":{\"get_owner\":{}}}' --node $NODE"
echo "  $BINARY query wasm contract-state smart <CONTRACT> '{\"ownable\":{\"get_pending_owner\":{}}}' --node $NODE"
echo
if [ "$DRY_RUN" -eq 0 ] && [ "${#FAILED_TXS[@]}" -gt 0 ]; then
  echo "${c_red}✗ ${#FAILED_TXS[@]} transaction(s) FAILED on-chain${c_off} (confirmed via tx query, not just the broadcast response):"
  for f in "${FAILED_TXS[@]}"; do
    echo "  - $f"
  done
  echo "${c_ylw}These did NOT take effect. Common cause: gas underestimated — consider raising GAS_ADJUST and re-running.${c_off}"
elif [ "$DRY_RUN" -eq 0 ]; then
  echo "${c_grn}✓ All broadcast transactions confirmed successful on-chain (code 0).${c_off}"
fi
[ "$DRY_RUN" -eq 1 ] && note "${c_grn}DRY-RUN: nothing was executed.${c_off} Review the output above and re-run with --execute when ready."
