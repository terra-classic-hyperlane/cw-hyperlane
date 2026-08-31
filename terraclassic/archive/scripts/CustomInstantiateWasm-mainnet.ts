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

  // ----------------------------------------------------------------
  // 14. SET ISM VALIDATORS — official Hyperlane mainnet validators for each chain
  //     CRITICAL: Without this, inbound messages (EVM → TC) CANNOT be validated.
  //     The ISM contracts were instantiated empty — validators MUST be set here.
  //     Source: https://docs.hyperlane.xyz/docs/reference/addresses/validators/mainnet-default-ism-validators
  // ----------------------------------------------------------------
  console.log("\n🔐 [14/17] SET ISM VALIDATORS — official Hyperlane mainnet validators");

  const validatorSets = [
    {
      addr: ADDRESSES["hpl_ism_multisig_eth"],
      label: "ETH mainnet (domain 1) — threshold 6/9",
      msg: {
        set_validators: {
          domain: 1,
          threshold: 6,
          validators: [
            "03c842db86a6a3e524d4a6615390c1ea8e2b9541", // Abacus Works
            "94438a7de38d4548ae54df5c6010c4ebc5239eae", // DSRV
            "5450447aee7b544c462c9352bef7cad049b0c2dc", // Zee Prime
            "b3ac35d3988bca8c2ffd195b1c6bee18536b317b", // Staked
            "b683b742b378632a5f73a2a5a45801b3489bba44", // Luganodes (AVS)
            "3786083ca59dc806d894104e65a13a70c2b39276", // Imperator
            "4f977a59fdc2d9e39f6d780a84d5b4add1495a36", // Mitosis
            "29d783efb698f9a2d3045ef4314af1f5674f52c5", // Substance Labs
            "36a669703ad0e11a0382b098574903d2084be22c", // Enigma
          ],
        },
      },
    },
    {
      addr: ADDRESSES["hpl_ism_multisig_bsc"],
      label: "BSC mainnet (domain 56) — threshold 4/6",
      msg: {
        set_validators: {
          domain: 56,
          threshold: 4,
          validators: [
            "570af9b7b36568c8877eebba6c6727aa9dab7268", // Abacus Works
            "5450447aee7b544c462c9352bef7cad049b0c2dc", // Zee Prime
            "0d4c1394a255568ec0ecd11795b28d1bda183ca4", // Tessellated
            "24c1506142b2c859aee36474e59ace09784f71e8", // Substance Labs
            "c67789546a7a983bf06453425231ab71c119153f", // Luganodes
            "2d74f6edfd08261c927ddb6cb37af57ab89f0eff", // Enigma
          ],
        },
      },
    },
    {
      addr: ADDRESSES["hpl_ism_multisig_sol"],
      label: "Solana mainnet (domain 1399811149) — threshold 3/5",
      msg: {
        set_validators: {
          domain: 1399811149,
          threshold: 3,
          validators: [
            "28464752829b3ea59a497fca0bdff575c534c3ff", // Abacus Works
            "2b7514a2f77bd86bbf093fe6bb67d8611f51c659", // Luganodes
            "cb6bcbd0de155072a7ff486d9d7286b0f71dcc2d", // Eclipse
            "4f977a59fdc2d9e39f6d780a84d5b4add1495a36", // Mitosis
            "5450447aee7b544c462c9352bef7cad049b0c2dc", // Zee Prime
          ],
        },
      },
    },
  ];

  for (const { addr, label, msg } of validatorSets) {
    console.log(`\n  → ${label}`);
    const r = await client.execute(sender, addr, msg, "auto",
      `set_validators — ${label}`);
    console.log("    TX:", r.transactionHash);
  }

  // ----------------------------------------------------------------
  // 15. CONFIGURE MAILBOX — set_default_ism, set_default_hook, set_required_hook
  //     Executed as owner (deployer). After governance transfer, update via proposal.
  //     Without this step, transfer_remote FAILS with "default_hook not set".
  // ----------------------------------------------------------------
  console.log("\n⚙️  [15/17] CONFIGURE MAILBOX (direct — as owner)");


  const configMsgs = [
    { msg: { set_default_ism:   { ism:  ADDRESSES["hpl_ism_routing"]              } }, label: "set_default_ism   → ISM Routing" },
    { msg: { set_default_hook:  { hook: ADDRESSES["hpl_hook_aggregate_default"]   } }, label: "set_default_hook  → Hook Agg [Merkle+IGP]" },
    { msg: { set_required_hook: { hook: ADDRESSES["hpl_hook_aggregate_required"]  } }, label: "set_required_hook → Hook Agg [Pausable+Fee]" },
  ];

  for (const { msg, label } of configMsgs) {
    console.log(`\n  → ${label}`);
    const r = await client.execute(sender, ADDRESSES["hpl_mailbox"], msg, "auto",
      `mailbox config — ${label}`);
    console.log("    TX:", r.transactionHash);
  }

  // ----------------------------------------------------------------
  // 15. CONFIGURE IGP ORACLE — set_remote_gas_data_configs + router.set_routes
  //     Sets exchange_rate and gas_price for domains 1 (ETH), 56 (BSC), 1399811149 (SOL).
  //     Update rates periodically via ./update-igp-oracle.sh or governance.
  //     Values below use: LUNC=$0.00006782, ETH=$1803, BNB=$617, SOL=$70 (2026-06-04)
  // ----------------------------------------------------------------
  console.log("\n⚙️  [16/17] CONFIGURE IGP ORACLE (direct — as owner)");

  const oracleConfigs = [
    { remote_domain: 1,          token_exchange_rate: "37611",          gas_price: "10000000000" }, // ETH 10 gwei
    { remote_domain: 56,         token_exchange_rate: "110531",         gas_price: "3000000000"  }, // BSC 3 gwei
    { remote_domain: 1399811149, token_exchange_rate: "38300155301425", gas_price: "1"           }, // SOL lamport
  ];

  const rOracle = await client.execute(sender, ADDRESSES["hpl_igp_oracle"],
    { set_remote_gas_data_configs: { configs: oracleConfigs } },
    "auto", "IGP oracle config — domains 1/56/1399811149");
  console.log("  Oracle config TX:", rOracle.transactionHash);

  const oracleRoutes = oracleConfigs.map(c => ({ domain: c.remote_domain, route: ADDRESSES["hpl_igp_oracle"] }));
  const rRoutes = await client.execute(sender, ADDRESSES["hpl_igp"],
    { router: { set_routes: { set: oracleRoutes } } },
    "auto", "IGP routes — domains 1/56/1399811149");
  console.log("  IGP routes TX:   ", rRoutes.transactionHash);

  // ==============================
  // SUMMARY
  // ==============================
  console.log("\n" + "=".repeat(80));
  console.log("✅ ALL 17 STEPS COMPLETE — MAINNET (columbus-5) FULLY CONFIGURED");
  console.log("=".repeat(80));
  console.log("\n📊 CONTRACT ADDRESSES:");
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

  console.log("\n📝 Full JSON (copy to context/terraclassic.json → deployments):");
  console.log(JSON.stringify(ADDRESSES, null, 2));

  console.log("\n✅ ISM VALIDATORS CONFIGURED (official Hyperlane mainnet):");
  console.log("  domain 1   (ETH):         6/9 validators (Abacus Works, DSRV, Zee Prime...)");
  console.log("  domain 56  (BSC):         4/6 validators (Abacus Works, Zee Prime...)");
  console.log("  domain 1399811149 (SOL):  3/5 validators (Abacus Works, Luganodes, Eclipse...)");

  console.log("\n✅ MAILBOX CONFIGURED:");
  console.log("  default_ism       → ISM Routing");
  console.log("  default_hook      → Hook Agg [Merkle + IGP]");
  console.log("  required_hook     → Hook Agg [Pausable + Fee (0.283215 LUNC)]");

  console.log("\n✅ IGP ORACLE CONFIGURED:");
  console.log("  domain 1   (ETH): exchange_rate=37611,          gas_price=10gwei");
  console.log("  domain 56  (BSC): exchange_rate=110531,         gas_price=3gwei");
  console.log("  domain 1399811149 (SOL): exchange_rate=38300155301425, gas_price=1");
  console.log("  ⚠️  Update rates via ./update-igp-oracle.sh when prices change >20%");

  console.log("\n⚠️  REMAINING NEXT STEPS:");
  console.log("  1. Update doc section 7:");
  console.log("     terraclassic/doc/HYPERLANE_DEPLOYMENT-MAINNET_EN.md");
  console.log("  2. Submit governance proposal (sets ISM validators — required for inbound msgs):");
  console.log("     PRIVATE_KEY='0x...' yarn tsx terraclassic/submit-proposal-mainnet.ts");
  console.log("  3. Deploy Warp Routes for each token:");
  console.log("     cd terraclassic && ./create-warp-evm.sh");
  console.log("  4. Update IGP oracle rates when prices change >20%:");
  console.log("     ./update-igp-oracle.sh");
  console.log("  5. Transfer ownership to governance (optional, after testing):");
  console.log("     ./transfer-ownership-to-governance.sh");
}

main().catch((error) => {
  console.error("Error:", error);
  process.exit(1);
});
