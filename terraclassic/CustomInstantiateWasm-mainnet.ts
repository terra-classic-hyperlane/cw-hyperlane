import { DirectSecp256k1Wallet } from "@cosmjs/proto-signing";
import { SigningCosmWasmClient } from "@cosmjs/cosmwasm-stargate";
import { GasPrice } from "@cosmjs/stargate";
import { fromBech32 } from "@cosmjs/encoding";

// ==============================
// UTILITY
// ==============================
function extractByte32AddrFromBech32(addr: string): string {
  const { data } = fromBech32(addr);
  const hexed = Buffer.from(data).toString("hex");
  return hexed.length === 64 ? hexed : hexed.padStart(64, "0");
}

// ==============================
// NETWORK — MAINNET (columbus-5)
// ==============================
const RPC      = "https://rpc.terra-classic.hexxagon.io";
const CHAIN_ID = "columbus-5";

// ==============================
// OWNERS — aligned with config-mainnet.yaml
//
//   All contracts use the same owner:
//   terra1run9wz09uhh6pu7ggcwwetrgye4wu7wn26mawp
// ==============================
const ISM_OWNER   = "terra1run9wz09uhh6pu7ggcwwetrgye4wu7wn26mawp";
const HOOKS_OWNER = "terra1run9wz09uhh6pu7ggcwwetrgye4wu7wn26mawp";

// ==============================
// MAINNET CODE IDs — uploaded 2026-06-03 (columbus-5)
// Source: context/terraclassic.json
// ==============================
const CODE_IDS = {
  hpl_mailbox:            11371,
  hpl_validator_announce: 11372,
  hpl_ism_multisig:       11374,
  hpl_ism_routing:        11376,
  hpl_hook_merkle:        11380,
  hpl_igp:                11377,
  hpl_igp_oracle:         11388,
  hpl_hook_aggregate:     11378,
  hpl_hook_pausable:      11381,
  hpl_hook_fee:           11379,
};

// GET FROM ENVIRONMENT — NEVER HARDCODE
const PRIVATE_KEY_HEX = process.env.PRIVATE_KEY || "";

// ==============================
// ADDRESS MAP
// ==============================
const ADDRESSES: Record<string, string> = {};

async function instantiateContract(
  client: SigningCosmWasmClient,
  sender: string,
  name: string,
  codeId: number,
  msg: object
) {
  console.log(`\nInstantiating ${name} (code_id ${codeId})...`);
  console.log("Params:", JSON.stringify(msg, null, 2));

  const result = await client.instantiate(
    sender,
    codeId,
    msg,
    `cw-hpl: ${name}`,
    "auto",
    { admin: sender } // migration admin = deployer (transferable later)
  );

  ADDRESSES[name] = result.contractAddress;

  console.log({
    type:    name,
    address: result.contractAddress,
    hexed:   "0x" + extractByte32AddrFromBech32(result.contractAddress),
  });
  console.log("-------------------------------------");
}

// ==============================
// MAIN
// ==============================
async function main() {
  if (!PRIVATE_KEY_HEX) {
    console.error("ERROR: Set the PRIVATE_KEY environment variable.");
    console.error("Run from the project root:");
    console.error('  PRIVATE_KEY="0x..." yarn tsx terraclassic/CustomInstantiateWasm-mainnet.ts');
    process.exit(1);
  }

  // Build wallet from PRIVATE_KEY
  const keyHex = PRIVATE_KEY_HEX.startsWith("0x")
    ? PRIVATE_KEY_HEX.slice(2)
    : PRIVATE_KEY_HEX;

  const privateKeyBytes = Uint8Array.from(Buffer.from(keyHex, "hex"));
  const wallet          = await DirectSecp256k1Wallet.fromKey(privateKeyBytes, "terra");
  const [account]       = await wallet.getAccounts();
  const sender          = account.address;

  console.log("\n" + "=".repeat(80));
  console.log("HYPERLANE MAINNET INSTANTIATION — columbus-5");
  console.log("=".repeat(80));
  console.log("Deployer (sender)  :", sender);
  console.log("ISM owner          :", ISM_OWNER);
  console.log("Hooks owner        :", HOOKS_OWNER);
  console.log("RPC                :", RPC);

  const client = await SigningCosmWasmClient.connectWithSigner(RPC, wallet, {
    gasPrice: GasPrice.fromString("28.5uluna"),
  });
  console.log("Gas price          : 28.5uluna\n");

  // ----------------------------------------------------------------
  // 1. MAILBOX
  //    domain: 1325 (Terra Classic)
  //    owner:  ISM_OWNER (aligned with deploy.ism)
  // ----------------------------------------------------------------
  console.log("📮 [1/13] MAILBOX");
  await instantiateContract(client, sender, "hpl_mailbox", CODE_IDS.hpl_mailbox, {
    hrp:    "terra",
    domain: 1325,
    owner:  ISM_OWNER,
  });

  // ----------------------------------------------------------------
  // 2. VALIDATOR ANNOUNCE
  //    No owner — permissionless registry
  // ----------------------------------------------------------------
  console.log("\n📢 [2/13] VALIDATOR ANNOUNCE");
  await instantiateContract(client, sender, "hpl_validator_announce", CODE_IDS.hpl_validator_announce, {
    hrp:     "terra",
    mailbox: ADDRESSES["hpl_mailbox"],
  });

  // ----------------------------------------------------------------
  // 3. ISM MULTISIG — Ethereum (Domain 1)
  //    Validators configured later via governance:
  //    threshold 6/9 — source: config-mainnet.yaml ism.1
  // ----------------------------------------------------------------
  console.log("\n🔐 [3/13] ISM MULTISIG — Ethereum (Domain 1) — threshold 6/9");
  await instantiateContract(client, sender, "hpl_ism_multisig_eth", CODE_IDS.hpl_ism_multisig, {
    owner: ISM_OWNER,
  });

  // ----------------------------------------------------------------
  // 4. ISM MULTISIG — BSC (Domain 56)
  //    threshold 4/6 — source: config-mainnet.yaml ism.56
  // ----------------------------------------------------------------
  console.log("\n🔐 [4/13] ISM MULTISIG — BSC (Domain 56) — threshold 4/6");
  await instantiateContract(client, sender, "hpl_ism_multisig_bsc", CODE_IDS.hpl_ism_multisig, {
    owner: ISM_OWNER,
  });

  // ----------------------------------------------------------------
  // 5. ISM MULTISIG — Solana (Domain 1399811149)
  //    threshold 3/5 — source: config-mainnet.yaml ism.1399811149
  // ----------------------------------------------------------------
  console.log("\n🔐 [5/13] ISM MULTISIG — Solana (Domain 1399811149) — threshold 3/5");
  await instantiateContract(client, sender, "hpl_ism_multisig_sol", CODE_IDS.hpl_ism_multisig, {
    owner: ISM_OWNER,
  });

  // ----------------------------------------------------------------
  // 6. ISM ROUTING
  //    Routes: domain 1 → ETH, 56 → BSC, 1399811149 → Solana
  //    owner: ISM_OWNER — source: config-mainnet.yaml deploy.ism.owner
  // ----------------------------------------------------------------
  console.log("\n🗺️  [6/13] ISM ROUTING");
  await instantiateContract(client, sender, "hpl_ism_routing", CODE_IDS.hpl_ism_routing, {
    owner: ISM_OWNER,
    isms: [
      { domain: 1,          address: ADDRESSES["hpl_ism_multisig_eth"] },
      { domain: 56,         address: ADDRESSES["hpl_ism_multisig_bsc"] },
      { domain: 1399811149, address: ADDRESSES["hpl_ism_multisig_sol"] },
    ],
  });

  // ----------------------------------------------------------------
  // 7. HOOK MERKLE
  //    No owner — stateless
  //    source: config-mainnet.yaml hooks.default.hooks[merkle]
  // ----------------------------------------------------------------
  console.log("\n🌳 [7/13] HOOK MERKLE");
  await instantiateContract(client, sender, "hpl_hook_merkle", CODE_IDS.hpl_hook_merkle, {
    mailbox: ADDRESSES["hpl_mailbox"],
  });

  // ----------------------------------------------------------------
  // 8. IGP — Interchain Gas Paymaster
  //    owner/beneficiary: HOOKS_OWNER
  //    source: config-mainnet.yaml hooks.default.hooks[igp]
  // ----------------------------------------------------------------
  console.log("\n⛽ [8/13] IGP");
  await instantiateContract(client, sender, "hpl_igp", CODE_IDS.hpl_igp, {
    hrp:               "terra",
    owner:             HOOKS_OWNER,
    gas_token:         "uluna",
    beneficiary:       HOOKS_OWNER,
    default_gas_usage: "100000",
  });

  // ----------------------------------------------------------------
  // 9. IGP ORACLE
  //    owner: HOOKS_OWNER
  //    Gas configs for domains 1/56/1399811149 set via governance.
  //    source: config-mainnet.yaml hooks.default.hooks[igp]
  // ----------------------------------------------------------------
  console.log("\n🔮 [9/13] IGP ORACLE");
  console.log("ℹ️  exchange_rate / gas_price configured via governance after deployment");
  await instantiateContract(client, sender, "hpl_igp_oracle", CODE_IDS.hpl_igp_oracle, {
    owner: HOOKS_OWNER,
  });

  // ----------------------------------------------------------------
  // 10. HOOK AGGREGATE #1 — default hook (Merkle + IGP)
  //     owner: HOOKS_OWNER
  //     source: config-mainnet.yaml hooks.default (aggregate)
  // ----------------------------------------------------------------
  console.log("\n🔗 [10/13] HOOK AGGREGATE #1 — default hook (Merkle + IGP)");
  await instantiateContract(client, sender, "hpl_hook_aggregate_default", CODE_IDS.hpl_hook_aggregate, {
    owner: HOOKS_OWNER,
    hooks: [
      ADDRESSES["hpl_hook_merkle"],
      ADDRESSES["hpl_igp"],
    ],
  });

  // ----------------------------------------------------------------
  // 11. HOOK PAUSABLE
  //     owner: HOOKS_OWNER, paused: false
  //     source: config-mainnet.yaml hooks.required.hooks[pausable]
  // ----------------------------------------------------------------
  console.log("\n⏸️  [11/13] HOOK PAUSABLE");
  await instantiateContract(client, sender, "hpl_hook_pausable", CODE_IDS.hpl_hook_pausable, {
    owner:  HOOKS_OWNER,
    paused: false,
  });

  // ----------------------------------------------------------------
  // 12. HOOK FEE
  //     owner: HOOKS_OWNER, fee: 283215 uluna (0.283215 LUNC)
  //     source: config-mainnet.yaml hooks.required.hooks[fee]
  // ----------------------------------------------------------------
  console.log("\n💰 [12/13] HOOK FEE — 0.283215 LUNC per message");
  await instantiateContract(client, sender, "hpl_hook_fee", CODE_IDS.hpl_hook_fee, {
    owner: HOOKS_OWNER,
    fee: {
      denom:  "uluna",
      amount: "283215",
    },
  });

  // ----------------------------------------------------------------
  // 13. HOOK AGGREGATE #2 — required hook (Pausable + Fee)
  //     owner: HOOKS_OWNER
  //     source: config-mainnet.yaml hooks.required (aggregate)
  // ----------------------------------------------------------------
  console.log("\n🔗 [13/13] HOOK AGGREGATE #2 — required hook (Pausable + Fee)");
  await instantiateContract(client, sender, "hpl_hook_aggregate_required", CODE_IDS.hpl_hook_aggregate, {
    owner: HOOKS_OWNER,
    hooks: [
      ADDRESSES["hpl_hook_pausable"],
      ADDRESSES["hpl_hook_fee"],
    ],
  });

  // ==============================
  // SUMMARY
  // ==============================
  console.log("\n" + "=".repeat(80));
  console.log("✅ ALL 13 CONTRACTS INSTANTIATED — MAINNET (columbus-5)");
  console.log("=".repeat(80));
  console.log("\n📊 CONTRACTS:");
  console.log("  Mailbox           :", ADDRESSES["hpl_mailbox"]);
  console.log("  Validator Announce:", ADDRESSES["hpl_validator_announce"]);
  console.log("  ISM Multisig ETH  :", ADDRESSES["hpl_ism_multisig_eth"]);
  console.log("  ISM Multisig BSC  :", ADDRESSES["hpl_ism_multisig_bsc"]);
  console.log("  ISM Multisig SOL  :", ADDRESSES["hpl_ism_multisig_sol"]);
  console.log("  ISM Routing       :", ADDRESSES["hpl_ism_routing"]);
  console.log("  Hook Merkle       :", ADDRESSES["hpl_hook_merkle"]);
  console.log("  IGP               :", ADDRESSES["hpl_igp"]);
  console.log("  IGP Oracle        :", ADDRESSES["hpl_igp_oracle"]);
  console.log("  Hook Agg Default  :", ADDRESSES["hpl_hook_aggregate_default"]);
  console.log("  Hook Pausable     :", ADDRESSES["hpl_hook_pausable"]);
  console.log("  Hook Fee          :", ADDRESSES["hpl_hook_fee"]);
  console.log("  Hook Agg Required :", ADDRESSES["hpl_hook_aggregate_required"]);

  console.log("\n📝 Full JSON:");
  console.log(JSON.stringify(ADDRESSES, null, 2));

  console.log("\n⚠️  NEXT STEPS:");
  console.log("  1. Fill contract addresses in:");
  console.log("     terraclassic/doc/HYPERLANE_DEPLOYMENT-MAINNET_EN.md  (section 6)");
  console.log("  2. Submit governance proposal:");
  console.log("     set_validators for ETH/BSC/Solana ISMs");
  console.log("     set_remote_gas_data_configs in IGP Oracle");
  console.log("     set_default_ism  →", ADDRESSES["hpl_ism_routing"]);
  console.log("     set_default_hook →", ADDRESSES["hpl_hook_aggregate_default"]);
  console.log("     set_required_hook→", ADDRESSES["hpl_hook_aggregate_required"]);
  console.log("  3. Transfer ISM ownership to governance (optional):");
  console.log("     ./transfer-ownership-to-governance.sh");
}

main().catch((error) => {
  console.error("Error:", error);
  process.exit(1);
});
