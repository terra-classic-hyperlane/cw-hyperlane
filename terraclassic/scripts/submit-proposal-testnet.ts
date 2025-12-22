import { DirectSecp256k1Wallet } from "@cosmjs/proto-signing";
import { SigningCosmWasmClient } from "@cosmjs/cosmwasm-stargate";
import { SigningStargateClient, GasPrice } from "@cosmjs/stargate";
import { MsgSubmitProposal } from "cosmjs-types/cosmos/gov/v1beta1/tx";
import { toUtf8 } from "@cosmjs/encoding";

// ==============================
// CONFIGURATION - TESTNET
// ==============================
const WALLET_NAME = "hyperlane-testnet";
const CHAIN_ID = "rebel-2";
const NODE = "https://rpc.luncblaze.com:443";

// GET FROM ENVIRONMENT
const PRIVATE_KEY_HEX = process.env.PRIVATE_KEY || "deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef";

// ---------------------------
// CONTRACT ADDRESSES (TESTNET)
// ---------------------------
const MAILBOX = "terra1rqg3qfkfg5upad9xu6zj5jhl626qy053s7rn08829rgqzv2wu39s5la8yf";
const ISM_MULTISIG_BSC = "terra1rrt0kepmazvavmkusvz6589l5yg4mqjk49netqfqttnmf2y4exmqxhp0hv";
const ISM_MULTISIG_SOL = "terra1d7a52pxu309jcgv8grck7jpgwlfw7cy0zen9u42rqdr39tef9g7qc8gp4a";
const ISM_ROUTING = "terra1h4sd8fyxhde7dc9w9y9zhc2epphgs75q7zzfg3tfynm8qvpe3jlsd7sauh";
const IGP = "terra1n70g3vg7xge6q8m44rudm4y6fm6elpspwsgfmfphs3teezpak6cs6wxlk9";
const IGP_ORACLE = "terra18tyqe79yktac6p3alv3f49k06xqna2q52twyaflrz55qka9emhrs30k3hg";
const HOOK_MERKLE = "terra1x9ftmmyj0t9n0ql78r2vdfk9stxg5z6vnwnwjym9m7py6lvxz8ls7sa3df";
const HOOK_AGG_1 = "terra14qjm9075m8djus4tl86lc5n2xnsvuazesl52vqyuz6pmaj4k5s5qu5q6jh";
const HOOK_PAUSABLE = "terra1j04kamuwssgckj7592w5v3hlttmlqlu9cqkzvvxsjt8rqyt3stps0xan5l";
const HOOK_FEE = "terra13y6vseryqqj09uu9aagk8xks4dr9fr2p0xr3w6gngdzjd362h54sz5fr3j";
const HOOK_AGG_2 = "terra1xdpah0ven023jzd80qw0nkp4ndjxy4d7g5y99dhpfwetyal6q6jqpk42rj";

// AGGREGATE 1 = merkle + igp
const AGG_HOOK_DEFAULT = HOOK_AGG_1;

// AGGREGATE 2 = pausable + fee
const AGG_HOOK_REQUIRED = HOOK_AGG_2;

// Governance module address
const GOV_MODULE = "terra10d07y265gmmuvt4z0w9aw880jnsr700juxf95n";

// ---------------------------
// EXECUTION MESSAGES
// ---------------------------
interface ExecuteMsg {
  contractAddress: string;
  msg: any;
  description?: string;  // Message description
}

// ============================================================================
// EXECUTION MESSAGES DOCUMENTATION - TESTNET
// ============================================================================
// This governance proposal configures the instantiated Hyperlane contracts
// to allow cross-chain communication between Terra Classic Testnet, BSC Testnet,
// and Solana Testnet. Each message is explained in detail below.
// ============================================================================

const EXEC_MSGS: ExecuteMsg[] = [
  // --------------------------------------------------------------------------
  // MESSAGE 1: Configure ISM Multisig Validators for BSC Testnet (Domain 97)
  // --------------------------------------------------------------------------
  // Defines the set of validators that will sign messages coming from
  // domain 97 (BSC Testnet). The threshold of 2 means at least 2 out of 3
  // validators must sign for a message to be considered valid.
  //
  // PARAMETERS:
  // - domain: 97 (BSC Testnet)
  // - threshold: 2 (minimum of 2 signatures required from 3 validators)
  // - validators: Array of 3 hexadecimal addresses (20 bytes each) of validators
  //
  // CONFIGURED VALIDATORS:
  // Each validator is an off-chain node that monitors messages and provides signatures.
  // Addresses are hexadecimal representations (without 0x) of Ethereum-style addresses.
  {
    contractAddress: ISM_MULTISIG_BSC,
    description: "Configure multisig validators for domain 97 (BSC Testnet) with threshold 2/3",
    msg: {
      set_validators: {
        domain: 97,             // BSC Testnet domain ID in Hyperlane protocol
        threshold: 2,           // Minimum number of required signatures (2 of 3)
        validators: [
          "242d8a855a8c932dec51f7999ae7d1e48b10c95e",  // Validator 1
          "f620f5e3d25a3ae848fec74bccae5de3edcd8796",  // Validator 2
          "1f030345963c54ff8229720dd3a711c15c554aeb",  // Validator 3
        ],
      },
    },
  },

  // --------------------------------------------------------------------------
  // MESSAGE 2: Configure ISM Multisig Validators for Solana Testnet (Domain 1399811150)
  // --------------------------------------------------------------------------
  // Defines the set of validators that will sign messages coming from
  // domain 1399811150 (Solana Testnet). The threshold of 1 means at least 1
  // validator must sign for a message to be considered valid.
  //
  // PARAMETERS:
  // - domain: 1399811150 (Solana Testnet)
  // - threshold: 1 (minimum of 1 signature required from 1 validator)
  // - validators: Array of 1 hexadecimal address (20 bytes) of validator
  {
    contractAddress: ISM_MULTISIG_SOL,
    description: "Configure multisig validators for domain 1399811150 (Solana Testnet) with threshold 1/1",
    msg: {
      set_validators: {
        domain: 1399811150,     // Solana Testnet domain ID in Hyperlane protocol
        threshold: 1,           // Minimum number of required signatures (1 of 1)
        validators: [
          "d4ce8fa138d4e083fc0e480cca0dbfa4f5f30bd5",  // Validator 1
        ],
      },
    },
  },

  // --------------------------------------------------------------------------
  // MESSAGE 3: Configure Remote Gas Data in IGP Oracle (Testnet Chains)
  // --------------------------------------------------------------------------
  // Defines the token exchange rate and gas price for supported testnet domains:
  // - Domain 97 (BSC Testnet)
  // - Domain 1399811150 (Solana Testnet)
  //
  // This allows IGP to calculate how much gas to charge on the source chain (Terra Testnet)
  // to cover execution costs on the destination chains.
  //
  // PARAMETERS:
  // - remote_domain: Chain domain ID
  // - token_exchange_rate: Exchange rate between LUNC and destination chain token
  // - gas_price: Gas price on destination chain
  //
  // COST CALCULATION:
  // Cost = (gas_used_on_destination * gas_price * token_exchange_rate)
  {
    contractAddress: IGP_ORACLE,
    description: "Configure remote gas data for testnet domains (BSC Testnet, Solana Testnet)",
    msg: {
      set_remote_gas_data_configs: {
        configs: [
          {
            remote_domain: 97,                      // BSC Testnet
            token_exchange_rate: "1805936462255558", // LUNC:BNB exchange rate
            gas_price: "50000000",                   // Gas price on BSC (0.05 Gwei)
          },
          {
            remote_domain: 1399811150,               // Solana Testnet
            token_exchange_rate: "57675000000000000", // LUNC:SOL exchange rate
            gas_price: "1",                          // Gas price on Solana
          },
        ],
      },
    },
  },

  // --------------------------------------------------------------------------
  // MESSAGE 4: Set IGP Routes to Oracle (Testnet Chains)
  // --------------------------------------------------------------------------
  // Configures IGP to use IGP Oracle when calculating gas costs for testnet domains:
  // - Domain 97 (BSC Testnet)
  // - Domain 1399811150 (Solana Testnet)
  //
  // These routes connect IGP to the Oracle that provides updated price and
  // exchange rate data for each destination chain.
  //
  // PARAMETERS:
  // - domain: Chain domain ID
  // - route: IGP Oracle address that provides gas data
  //
  // FLOW:
  // IGP receives payment -> queries Oracle via route -> calculates cost -> validates payment
  {
    contractAddress: IGP,
    description: "Set IGP routes to query Oracle about gas for testnet domains (BSC Testnet, Solana Testnet)",
    msg: {
      router: {
        set_routes: {
          set: [
            {
              domain: 97,          // BSC Testnet
              route: IGP_ORACLE,   // Oracle address that provides gas data
            },
            {
              domain: 1399811150,  // Solana Testnet
              route: IGP_ORACLE,   // Oracle address that provides gas data
            },
          ],
        },
      },
    },
  },

  // --------------------------------------------------------------------------
  // MESSAGE 5: Set Default ISM in Mailbox
  // --------------------------------------------------------------------------
  // Configures the default ISM (Interchain Security Module) that will be used by
  // Mailbox to validate received messages. ISM Routing allows using
  // different validation strategies per source domain.
  //
  // PARAMETERS:
  // - ism: ISM Routing address (routes to different ISM Multisig for each chain)
  //
  // VALIDATION FLOW:
  // Message received -> Mailbox queries default ISM -> ISM Routing directs to
  // appropriate ISM Multisig based on origin domain -> ISM Multisig validates signatures
  // - Domain 97 (BSC Testnet): 2/3 validators
  // - Domain 1399811150 (Solana Testnet): 1/1 validator
  {
    contractAddress: MAILBOX,
    description: "Set ISM Routing as Mailbox default security module (supports BSC Testnet, Solana Testnet)",
    msg: {
      set_default_ism: {
        ism: ISM_ROUTING,  // ISM Routing address
      },
    },
  },

  // --------------------------------------------------------------------------
  // MESSAGE 6: Set Default Hook in Mailbox
  // --------------------------------------------------------------------------
  // Configures the default Hook that will be executed when sending messages.
  // Hook Aggregate #1 combines Merkle Tree Hook (for proofs) and IGP (for payment).
  //
  // DEFAULT HOOK COMPONENTS:
  // 1. Merkle Hook: Adds message to Merkle tree for inclusion proofs
  // 2. IGP Hook: Processes gas payment for execution on destination chain
  //
  // SEND FLOW:
  // dispatch() called -> Default hook executed -> Merkle registers message ->
  // IGP processes payment -> Message emitted as event
  {
    contractAddress: MAILBOX,
    description: "Set Hook Aggregate #1 (Merkle + IGP) as default hook for message sending",
    msg: {
      set_default_hook: {
        hook: AGG_HOOK_DEFAULT,  // Hook Aggregate #1 (Merkle + IGP)
      },
    },
  },

  // --------------------------------------------------------------------------
  // MESSAGE 7: Set Required Hook in Mailbox
  // --------------------------------------------------------------------------
  // Configures the mandatory Hook that will ALWAYS be executed when sending messages,
  // regardless of custom hooks specified by the sender.
  // Hook Aggregate #2 combines Hook Pausable (emergency) and Hook Fee (monetization).
  //
  // REQUIRED HOOK COMPONENTS:
  // 1. Hook Pausable: Allows pausing message sending in case of emergency/maintenance
  // 2. Hook Fee: Charges fixed fee of 0.283215 LUNC per message (anti-spam/monetization)
  //
  // SEND FLOW (complete order):
  // dispatch() -> Required hook (Pausable checks if not paused, Fee charges fee) ->
  // Default hook (Merkle + IGP) -> Message sent
  //
  // IMPORTANT: Required hook is executed BEFORE default hook and cannot be bypassed.
  {
    contractAddress: MAILBOX,
    description: "Set Hook Aggregate #2 (Pausable + Fee) as required (mandatory) hook for sending",
    msg: {
      set_required_hook: {
        hook: AGG_HOOK_REQUIRED,  // Hook Aggregate #2 (Pausable + Fee)
      },
    },
  },
];

// ============================================================================
// CONFIGURATION SUMMARY - TESTNET
// ============================================================================
// After execution of this proposal, the Hyperlane system will be configured to:
//
// 1. SECURITY: Validate messages using multisig validators:
//    - BSC Testnet (domain 97): 2/3 validators
//    - Solana Testnet (domain 1399811150): 1/1 validator
// 2. PAYMENT: Calculate and process gas payments using IGP + Oracle for testnet chains
// 3. PROOFS: Maintain Merkle tree of sent messages
// 4. CONTROL: Allow emergency pause via Hook Pausable
// 5. MONETIZATION: Charge fee of 0.283215 LUNC per message via Hook Fee
//
// The system will be ready to send and receive cross-chain messages between:
// - Terra Classic Testnet (domain 1325)
// - BSC Testnet (domain 97)
// - Solana Testnet (domain 1399811150)
// ============================================================================

// ---------------------------
// FUNCTIONS
// ---------------------------
function saveExecutionMessages() {
  const fs = require("fs");
  fs.writeFileSync("exec_msgs_testnet.json", JSON.stringify(EXEC_MSGS, null, 2));
  console.log("✓ exec_msgs_testnet.json file created successfully!");
}

function saveProposalJson() {
  const fs = require("fs");
  
  // Format for Terra Classic v2.x (Cosmos SDK v0.47+)
  const proposal = {
    messages: EXEC_MSGS.map((execMsg) => ({
      "@type": "/cosmwasm.wasm.v1.MsgExecuteContract",
      sender: GOV_MODULE, // governance module
      contract: execMsg.contractAddress,
      msg: execMsg.msg,
      funds: [],
    })),
    metadata: "Initial configuration of Hyperlane contracts for testnet multi-chain support",
    deposit: "10000000uluna",
    title: "Hyperlane Contracts Configuration - Testnet Multi-Chain",
    summary: "Proposal to configure Hyperlane contracts for BSC Testnet and Solana Testnet: set ISM validators (BSC 2/3, Solana 1/1), configure IGP Oracle for testnet chains, set IGP routes, configure default ISM and hooks (default and required) in Mailbox",
    expedited: false,
  };

  fs.writeFileSync("proposal_testnet.json", JSON.stringify(proposal, null, 2));
  console.log("✓ proposal_testnet.json file created successfully!");
}

async function submitGovernanceProposal(
  client: SigningCosmWasmClient,
  proposer: string
) {
  console.log("\n" + "=".repeat(80));
  console.log("PREPARING HYPERLANE GOVERNANCE PROPOSAL - TESTNET MULTI-CHAIN");
  console.log("=".repeat(80) + "\n");

  const proposalTitle = "Hyperlane Contracts Configuration - Testnet Multi-Chain";
  const proposalDescription = `
Proposal to configure Hyperlane contracts for testnet multi-chain support:
- Set validators for ISM Multisig:
  * BSC Testnet (domain 97): 2/3 validators
  * Solana Testnet (domain 1399811150): 1/1 validator
- Configure remote gas data in IGP Oracle for testnet chains
- Set IGP routes for testnet chains
- Set default ISM in Mailbox (ISM Routing)
- Set default and required hooks in Mailbox
  `.trim();

  const initialDeposit = [{ denom: "uluna", amount: "10000000" }]; // 10 LUNC

  console.log("📋 PROPOSAL INFORMATION:");
  console.log("─".repeat(80));
  console.log("Title:", proposalTitle);
  console.log("Initial deposit:", JSON.stringify(initialDeposit));
  console.log("\n🌐 SUPPORTED CHAINS (TESTNET):");
  console.log("  • BSC Testnet (Domain 97) - 2/3 validators");
  console.log("  • Solana Testnet (Domain 1399811150) - 1/1 validator");
  console.log("\n📝 EXECUTION MESSAGES (" + EXEC_MSGS.length + " messages):");
  console.log("─".repeat(80));
  
  EXEC_MSGS.forEach((execMsg, idx) => {
    console.log(`\n[${idx + 1}/${EXEC_MSGS.length}] ${execMsg.description || Object.keys(execMsg.msg)[0]}`);
    console.log("─".repeat(80));
    console.log("Contract:", execMsg.contractAddress);
    console.log("Message:", JSON.stringify(execMsg.msg, null, 2));
  });

  // Save files
  console.log("\n" + "=".repeat(80));
  console.log("💾 SAVING FILES...");
  console.log("=".repeat(80));
  saveExecutionMessages();
  saveProposalJson();

  // To submit proposal via CLI, use:
  console.log("\n" + "=".repeat(80));
  console.log("🚀 COMMAND TO SUBMIT VIA CLI:");
  console.log("=".repeat(80));
  console.log("\nExecute the command below to submit the proposal:");
  console.log("\n" + "─".repeat(80));
  console.log(`terrad tx gov submit-proposal proposal_testnet.json \\
  --from ${WALLET_NAME} \\
  --chain-id ${CHAIN_ID} \\
  --gas auto \\
  --gas-adjustment 1.5 \\
  --gas-prices 28.5uluna \\
  --node ${NODE} \\
  -y`);
  console.log("─".repeat(80));

  console.log("\n" + "=".repeat(80));
  console.log("📁 CREATED FILES:");
  console.log("=".repeat(80));
  console.log("  ✓ exec_msgs_testnet.json      - Individual execution messages");
  console.log("  ✓ proposal_testnet.json       - Complete proposal formatted for terrad");
  console.log("\n💡 NEXT STEPS:");
  console.log("─".repeat(80));
  console.log("  1. Review the created JSON files");
  console.log("  2. Execute the terrad command above to submit the proposal");
  console.log("  3. Vote on the proposal: terrad tx gov vote <PROPOSAL_ID> yes ...");
  console.log("  4. Wait for the voting period to end");
  console.log("  5. Verify execution by querying the contracts");
  console.log("=".repeat(80) + "\n");
}

async function executeContractsDirectly(
  client: SigningCosmWasmClient,
  sender: string
) {
  console.log("\n" + "=".repeat(80));
  console.log("EXECUTING CONTRACTS DIRECTLY (DIRECT MODE - WITHOUT GOVERNANCE)");
  console.log("=".repeat(80));
  console.log("⚠️  WARNING: This mode executes messages directly without going through governance.");
  console.log("    Use only for testing in development environment!");
  console.log("=".repeat(80) + "\n");

  for (let i = 0; i < EXEC_MSGS.length; i++) {
    const { contractAddress, msg, description } = EXEC_MSGS[i];
    const msgKey = Object.keys(msg)[0];

    console.log(`\n[${i + 1}/${EXEC_MSGS.length}] ${description || msgKey}`);
    console.log("─".repeat(80));
    console.log("Contract:", contractAddress);
    console.log("Message:", JSON.stringify(msg, null, 2));
    console.log("Executing...");

    try {
      const result = await client.execute(
        sender,
        contractAddress,
        msg,
        "auto",
        undefined,
        []
      );

      console.log("✅ SUCCESS!");
      console.log("  • TX Hash:", result.transactionHash);
      console.log("  • Gas used:", result.gasUsed);
      console.log("  • Height:", result.height);
    } catch (error: any) {
      console.error("❌ ERROR!");
      console.error("  • Message:", error.message);
      if (error.log) {
        console.error("  • Log:", error.log);
      }
      throw error;
    }
  }

  console.log("\n" + "=".repeat(80));
  console.log("✅ ALL MESSAGES HAVE BEEN EXECUTED SUCCESSFULLY!");
  console.log("=".repeat(80));
  console.log("\n💡 NEXT STEPS:");
  console.log("─".repeat(80));
  console.log("  1. Verify configurations using terrad query commands");
  console.log("  2. Test cross-chain message sending");
  console.log("  3. Monitor contract events and logs");
  console.log("=".repeat(80) + "\n");
}

async function main() {
  if (!PRIVATE_KEY_HEX) {
    console.error("ERROR: Set the PRIVATE_KEY environment variable.");
    console.error('Example: PRIVATE_KEY="abcdef..." npx tsx script/submit-proposal-testnet.ts');
    return;
  }

  // Create wallet
  const privateKeyBytes = Uint8Array.from(Buffer.from(PRIVATE_KEY_HEX, "hex"));
  const wallet = await DirectSecp256k1Wallet.fromKey(privateKeyBytes, "terra");
  const [account] = await wallet.getAccounts();
  const sender = account.address;

  console.log("Wallet loaded:", sender);
  console.log("Chain ID:", CHAIN_ID);
  console.log("Node:", NODE);

  // Connect client
  const client = await SigningCosmWasmClient.connectWithSigner(NODE, wallet, {
    gasPrice: GasPrice.fromString("28.5uluna"),
  });

  console.log("✓ Connected to node\n");

  // Check execution mode
  const mode = process.env.MODE || "proposal";

  if (mode === "direct") {
    // Execute directly (without governance)
    console.log("Mode: DIRECT EXECUTION");
    await executeContractsDirectly(client, sender);
  } else {
    // Prepare governance proposal
    console.log("Mode: GOVERNANCE PROPOSAL");
    await submitGovernanceProposal(client, sender);
  }
}

main().catch((error) => {
  console.error("\nError executing:", error);
  process.exit(1);
});

