import { SigningCosmWasmClient } from '@cosmjs/cosmwasm-stargate';
import { DirectSecp256k1Wallet } from '@cosmjs/proto-signing';
import { GasPrice } from '@cosmjs/stargate';
import * as fs from 'fs';

// ============================================================================
// HYPERLANE MAINNET GOVERNANCE PROPOSAL — columbus-5
//
// Usage:
//   PRIVATE_KEY="hex_no_0x" yarn tsx terraclassic/submit-proposal-mainnet.ts
//
// Modes (MODE env var):
//   proposal — generates proposal JSON files only (default, no key needed)
//   direct   — executes messages directly as owner (requires PRIVATE_KEY)
//
// What this proposal configures:
//   1. ISM Multisig validators (official Hyperlane mainnet validators)
//      - ETH (domain 1):  6-of-9
//      - BSC (domain 56): 4-of-6
//      - SOL (domain 1399811149): 3-of-5
//   2. IGP Oracle — exchange_rate + gas_price per domain
//   3. IGP routes — link domains to oracle
//   4. Mailbox — set_default_ism, set_default_hook, set_required_hook
//
// Note: Items 2–4 were already executed directly by the owner on 2026-06-04.
//       They are included in the proposal so they can be re-applied after
//       governance ownership transfer, or updated via future proposals.
// ============================================================================

const CHAIN_ID    = 'columbus-5';
const NODE        = 'https://rpc.terra-classic.hexxagon.io';
const GOV_MODULE  = 'terra10d07y265gmmuvt4z0w9aw880jnsr700juxf95n';

const PRIVATE_KEY_HEX = process.env.PRIVATE_KEY || process.env.TERRA_PRIVATE_KEY || '';

// ============================================================================
// MAINNET CONTRACT ADDRESSES — v2 re-deploy 2026-06-09, domain 132556
// ============================================================================
const MAILBOX       = 'terra1fwg35n5esjgny7d8pxnz8usjpwsvpguk0txsy6cnqxy58x9fdlksjpx3p9';
const ISM_MULTI_ETH = 'terra187rzjc3dznfxqtqqrwh796e5q4khmvp5av8mka6zhp98zjfk2z2qneldar';
const ISM_MULTI_BSC = 'terra1nqj7qlnt2sty0dgnu3ss5z4u6wr7hjfea7cn6wpwjt2uymts8ucsmuj9xw';
const ISM_MULTI_SOL = 'terra10s3p36tjek8amhlc4krxpzln6g8n0qy9jq82wyda434l3rv89wfsucl50t';
const ISM_ROUTING   = 'terra1uhzzvt9x3u8hjnkp695hklexx2uywjvfqv454d93ds92sgtpwk7qrpxdg0';
const IGP           = 'terra1taunhg629rssf3g939nqr0h594q5mssrzdj5lkx2hygmxmh72ghqeqqnvz';
const IGP_ORACLE    = 'terra1j8xzgzk7vds5uzrplmnln4vcz6f205t9atdyflypzrr43cd5eh7scwqj0d';
const HOOK_AGG_DEF  = 'terra1026v947k2jn58t09ppw003xujj92vp3lxv0fg3xk8ccz42r8d2sqvnmvel'; // Merkle + IGP
const HOOK_AGG_REQ  = 'terra1xmdd7yhu3qdlfhrcku8srfvtday6efymj54gqz0daxsmn8pvqygq0nxq04'; // Pausable + Fee

// ============================================================================
// EXECUTION MESSAGES
// ============================================================================
interface ExecMsg {
  contractAddress: string;
  msg: Record<string, unknown>;
  description: string;
}

const EXEC_MSGS: ExecMsg[] = [

  // --------------------------------------------------------------------------
  // MESSAGE 1 — ISM Multisig ETH (Domain 1) — threshold 6/9
  // Official Hyperlane mainnet validators for Ethereum.
  // Required for BSC → Terra Classic messages (validator signs ETH-sourced msgs).
  // --------------------------------------------------------------------------
  {
    contractAddress: ISM_MULTI_ETH,
    description: 'Set ISM Multisig validators for Ethereum (domain 1) — threshold 6/9',
    msg: {
      set_validators: {
        domain: 1,
        threshold: 6,
        validators: [
          '03c842db86a6a3e524d4a6615390c1ea8e2b9541', // Abacus Works
          '94438a7de38d4548ae54df5c6010c4ebc5239eae', // DSRV
          '5450447aee7b544c462c9352bef7cad049b0c2dc', // Zee Prime
          'b3ac35d3988bca8c2ffd195b1c6bee18536b317b', // Staked
          'b683b742b378632a5f73a2a5a45801b3489bba44', // Luganodes (AVS)
          '3786083ca59dc806d894104e65a13a70c2b39276', // Imperator
          '4f977a59fdc2d9e39f6d780a84d5b4add1495a36', // Mitosis
          '29d783efb698f9a2d3045ef4314af1f5674f52c5', // Substance Labs
          '36a669703ad0e11a0382b098574903d2084be22c', // Enigma
        ],
      },
    },
  },

  // --------------------------------------------------------------------------
  // MESSAGE 2 — ISM Multisig BSC (Domain 56) — threshold 4/6
  // Official Hyperlane mainnet validators for BSC.
  // Required to validate messages coming FROM BSC TO Terra Classic.
  // --------------------------------------------------------------------------
  {
    contractAddress: ISM_MULTI_BSC,
    description: 'Set ISM Multisig validators for BSC (domain 56) — threshold 4/6',
    msg: {
      set_validators: {
        domain: 56,
        threshold: 4,
        validators: [
          '570af9b7b36568c8877eebba6c6727aa9dab7268', // Abacus Works
          '5450447aee7b544c462c9352bef7cad049b0c2dc', // Zee Prime
          '0d4c1394a255568ec0ecd11795b28d1bda183ca4', // Tessellated
          '24c1506142b2c859aee36474e59ace09784f71e8', // Substance Labs
          'c67789546a7a983bf06453425231ab71c119153f', // Luganodes
          '2d74f6edfd08261c927ddb6cb37af57ab89f0eff', // Enigma
        ],
      },
    },
  },

  // --------------------------------------------------------------------------
  // MESSAGE 3 — ISM Multisig Solana (Domain 1399811149) — threshold 3/5
  // Official Hyperlane mainnet validators for Solana.
  // Required to validate messages coming FROM Solana TO Terra Classic.
  // --------------------------------------------------------------------------
  {
    contractAddress: ISM_MULTI_SOL,
    description: 'Set ISM Multisig validators for Solana (domain 1399811149) — threshold 3/5',
    msg: {
      set_validators: {
        domain: 1399811149,
        threshold: 3,
        validators: [
          '28464752829b3ea59a497fca0bdff575c534c3ff', // Abacus Works
          '2b7514a2f77bd86bbf093fe6bb67d8611f51c659', // Luganodes
          'cb6bcbd0de155072a7ff486d9d7286b0f71dcc2d', // Eclipse
          '4f977a59fdc2d9e39f6d780a84d5b4add1495a36', // Mitosis
          '5450447aee7b544c462c9352bef7cad049b0c2dc', // Zee Prime
        ],
      },
    },
  },

  // --------------------------------------------------------------------------
  // MESSAGE 4 — IGP Oracle: set_remote_gas_data_configs
  // Exchange rates and gas prices for each destination domain.
  // Formula: token_exchange_rate = (LUNC_USD / NATIVE_USD) * 1e12
  // Values below: LUNC=$0.00006782, ETH=$1803, BNB=$617, SOL=$70 (2026-06-04)
  // UPDATE BEFORE SUBMITTING if prices changed >20% since last update.
  // Run: LUNC_USD=X ETH_USD=X BNB_USD=X SOL_USD=X ./update-igp-oracle.sh MODE=governance
  // --------------------------------------------------------------------------
  {
    contractAddress: IGP_ORACLE,
    description: 'Configure IGP Oracle gas data for ETH/BSC/Solana (update rates if stale)',
    msg: {
      set_remote_gas_data_configs: {
        configs: [
          {
            remote_domain: 1,          // Ethereum mainnet
            token_exchange_rate: '37611',          // LUNC=$0.00006782, ETH=$1803
            gas_price: '10000000000',              // 10 gwei
          },
          {
            remote_domain: 56,         // BSC mainnet
            token_exchange_rate: '110531',         // LUNC=$0.00006782, BNB=$617
            gas_price: '3000000000',               // 3 gwei
          },
          {
            remote_domain: 1399811149, // Solana mainnet
            token_exchange_rate: '38300155301425', // LUNC=$0.00006782, SOL=$70
            gas_price: '1',                        // lamport model
          },
        ],
      },
    },
  },

  // --------------------------------------------------------------------------
  // MESSAGE 5 — IGP: router.set_routes
  // Links each destination domain to the IGP Oracle contract.
  // --------------------------------------------------------------------------
  {
    contractAddress: IGP,
    description: 'Set IGP routes — link domains 1/56/1399811149 to IGP Oracle',
    msg: {
      router: {
        set_routes: {
          set: [
            { domain: 1,          route: IGP_ORACLE },
            { domain: 56,         route: IGP_ORACLE },
            { domain: 1399811149, route: IGP_ORACLE },
          ],
        },
      },
    },
  },

  // --------------------------------------------------------------------------
  // MESSAGE 6 — Mailbox: set_default_ism
  // ISM Routing selects the correct multisig ISM based on origin domain.
  // Without this, inbound messages cannot be validated.
  // --------------------------------------------------------------------------
  {
    contractAddress: MAILBOX,
    description: 'Set Mailbox default ISM → ISM Routing (routes to ETH/BSC/SOL multisig)',
    msg: {
      set_default_ism: { ism: ISM_ROUTING },
    },
  },

  // --------------------------------------------------------------------------
  // MESSAGE 7 — Mailbox: set_default_hook
  // Default hook for outbound messages: Merkle Tree + IGP.
  // - Merkle Tree: records message in merkle tree (validator signs checkpoint)
  // - IGP: collects gas payment in LUNC for execution on destination chain
  // Without this, transfer_remote FAILS with "default_hook not set".
  // --------------------------------------------------------------------------
  {
    contractAddress: MAILBOX,
    description: 'Set Mailbox default hook → Hook Agg [Merkle Tree + IGP]',
    msg: {
      set_default_hook: { hook: HOOK_AGG_DEF },
    },
  },

  // --------------------------------------------------------------------------
  // MESSAGE 8 — Mailbox: set_required_hook
  // Mandatory hook always executed before default hook (cannot be bypassed):
  // - Hook Pausable: emergency circuit-breaker (owner can pause all messaging)
  // - Hook Fee: protocol fee of 0.283215 LUNC per outbound message
  // --------------------------------------------------------------------------
  {
    contractAddress: MAILBOX,
    description: 'Set Mailbox required hook → Hook Agg [Pausable + Fee (0.283215 LUNC)]',
    msg: {
      set_required_hook: { hook: HOOK_AGG_REQ },
    },
  },
];

// ============================================================================
// SAVE FILES
// ============================================================================
function saveFiles() {
  // Individual execution messages
  fs.writeFileSync(
    'exec_msgs_mainnet.json',
    JSON.stringify(EXEC_MSGS, null, 2),
  );
  console.log('✓ exec_msgs_mainnet.json');

  // Full governance proposal
  const proposal = {
    title: 'Hyperlane Mainnet Configuration — columbus-5',
    summary: `Configure Hyperlane contracts for cross-chain messaging on Terra Classic Mainnet.
Sets ISM validators (ETH 6/9, BSC 4/6, Solana 3/5), IGP oracle gas prices,
Mailbox default ISM/hook/required-hook. Domains: ETH(1), BSC(56), Solana(1399811149).`,
    messages: EXEC_MSGS.map(m => ({
      '@type': '/cosmwasm.wasm.v1.MsgExecuteContract',
      sender:   GOV_MODULE,
      contract: m.contractAddress,
      msg:      m.msg,
      funds:    [],
    })),
    deposit:  '512000000uluna',
    expedited: false,
  };

  fs.writeFileSync('proposal_mainnet.json', JSON.stringify(proposal, null, 2));
  console.log('✓ proposal_mainnet.json');
}

// ============================================================================
// DIRECT EXECUTION (as owner, no governance)
// ============================================================================
async function executeDirectly(client: SigningCosmWasmClient, sender: string) {
  console.log('\n' + '='.repeat(80));
  console.log('DIRECT EXECUTION — as owner, without governance');
  console.log('='.repeat(80) + '\n');

  for (let i = 0; i < EXEC_MSGS.length; i++) {
    const { contractAddress, msg, description } = EXEC_MSGS[i];
    console.log(`\n[${i + 1}/${EXEC_MSGS.length}] ${description}`);
    console.log('Contract:', contractAddress);

    try {
      const result = await client.execute(sender, contractAddress, msg, 'auto',
        `mainnet-config: ${description}`);
      console.log('✅ TX:', result.transactionHash);
    } catch (err: unknown) {
      const e = err as { message?: string };
      console.error('❌ FAILED:', e.message);
      throw err;
    }
  }

  console.log('\n' + '='.repeat(80));
  console.log('✅ ALL MESSAGES EXECUTED');
  console.log('='.repeat(80));
}

// ============================================================================
// MAIN
// ============================================================================
async function main() {
  const mode = process.env.MODE || 'proposal';

  console.log('\n' + '='.repeat(80));
  console.log('HYPERLANE MAINNET GOVERNANCE PROPOSAL — columbus-5');
  console.log('='.repeat(80));
  console.log(`Mode     : ${mode}`);
  console.log(`Chain    : ${CHAIN_ID}`);
  console.log(`Messages : ${EXEC_MSGS.length}`);
  console.log('');
  console.log('Contracts:');
  console.log('  Mailbox      :', MAILBOX);
  console.log('  ISM ETH      :', ISM_MULTI_ETH);
  console.log('  ISM BSC      :', ISM_MULTI_BSC);
  console.log('  ISM Solana   :', ISM_MULTI_SOL);
  console.log('  IGP Oracle   :', IGP_ORACLE);
  console.log('  IGP          :', IGP);
  console.log('');

  EXEC_MSGS.forEach((m, i) => {
    console.log(`[${i + 1}] ${m.description}`);
  });

  if (mode === 'direct') {
    if (!PRIVATE_KEY_HEX) {
      console.error('\nERROR: Set PRIVATE_KEY or TERRA_PRIVATE_KEY for direct mode.');
      process.exit(1);
    }
    const keyHex = PRIVATE_KEY_HEX.replace(/^0x/, '');
    const wallet = await DirectSecp256k1Wallet.fromKey(
      Uint8Array.from(Buffer.from(keyHex, 'hex')), 'terra');
    const [account] = await wallet.getAccounts();
    console.log('\nSender:', account.address);

    const client = await SigningCosmWasmClient.connectWithSigner(NODE, wallet, {
      gasPrice: GasPrice.fromString('28.325uluna'),
    });
    await executeDirectly(client, account.address);
  }

  console.log('\n' + '='.repeat(80));
  console.log('SAVING FILES...');
  console.log('='.repeat(80));
  saveFiles();

  console.log('\n' + '='.repeat(80));
  console.log('SUBMIT VIA TERRAD:');
  console.log('='.repeat(80));
  console.log(`
terrad tx gov submit-proposal proposal_mainnet.json \\
  --from YOUR_KEY --chain-id ${CHAIN_ID} \\
  --node ${NODE}:443 \\
  --gas auto --gas-adjustment 1.5 --gas-prices 28.5uluna -y

# After passing, vote:
terrad tx gov vote PROPOSAL_ID yes \\
  --from YOUR_KEY --chain-id ${CHAIN_ID} \\
  --node ${NODE}:443 \\
  --gas auto --gas-adjustment 1.5 --gas-prices 28.5uluna -y
`);
}

main().catch(e => { console.error('ERROR:', e); process.exit(1); });
