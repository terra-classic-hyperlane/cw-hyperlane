#!/usr/bin/env node
'use strict';
// ═══════════════════════════════════════════════════════════════════════════
//  jito-warp-init.js — MEV-safe Hyperlane Warp Route init
// ═══════════════════════════════════════════════════════════════════════════
//
//  APPROACH: Single atomic transaction (no Jito needed).
//
//  The Hyperlane comment at plugin.rs:122 says:
//    "the transaction calling this instruction must include a subsequent
//     instruction initializing the mint with the SPL token 2022 program"
//
//  So we put EVERYTHING in ONE transaction:
//    Instruction 1: ComputeBudget setLimit
//    Instruction 2: ComputeBudget setPrice
//    Instruction 3: warp_init   → creates token_storage + mint_PDA (234 bytes, uninitialized)
//    Instruction 4: InitializeMetadataPointer → marks mint for inline metadata
//    Instruction 5: InitializeMint2           → initializes the mint
//
//  Single tx = atomic by Solana design. Zero MEV window.
//  Tx size ≈ 640 bytes (well under 1232 limit).
//
//  USAGE:
//    node jito-warp-init.js solanamainnet igorfake
//    node jito-warp-init.js  (reads NET_KEY / TOKEN_KEY env vars)
//
// ═══════════════════════════════════════════════════════════════════════════

const path  = require('path');
const fs    = require('fs');
const https = require('https');
const { execSync, spawnSync } = require('child_process');

// ── Resolve node_modules ───────────────────────────────────────────────────
const SCRIPT_DIR = path.dirname(require.main ? require.main.filename : __filename);
const PROJECT_ROOT = (() => {
  let d = SCRIPT_DIR;
  while (d !== '/') {
    if (fs.existsSync(path.join(d, 'package.json'))) return d;
    d = path.dirname(d);
  }
  return SCRIPT_DIR;
})();
const NM = path.join(PROJECT_ROOT, 'node_modules');

const {
  Connection, Keypair, PublicKey, SystemProgram, Transaction,
  TransactionInstruction, ComputeBudgetProgram, LAMPORTS_PER_SOL,
} = require(path.join(NM, '@solana/web3.js'));

const splToken = require(path.join(NM, '@solana/spl-token'));
const bs58     = require(path.join(NM, 'bs58'));

// ── Colors ─────────────────────────────────────────────────────────────────
const R='\x1b[31m', G='\x1b[32m', Y='\x1b[33m', B='\x1b[34m', C='\x1b[36m', W='\x1b[1m', NC='\x1b[0m';
const OK=`${G}✅${NC}`, ERR=`${R}❌${NC}`, WARN=`${Y}⚠️ ${NC}`, INFO=`${B}ℹ️ ${NC}`;

const TOKEN_2022 = new PublicKey('TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb');

function log(m)     { console.log(m); }
function logOk(m)   { log(`${OK} ${m}`); }
function logErr(m)  { log(`${ERR} ${m}`); }
function logWarn(m) { log(`${WARN} ${m}`); }
function logInfo(m) { log(`${INFO} ${m}`); }
function logSep(m)  { log(`\n${C}${W}${m}${NC}\n${'─'.repeat(65)}`); }
function sleep(ms)  { return new Promise(r => setTimeout(r, ms)); }

// ── PDA derivations ────────────────────────────────────────────────────────
const pda = (seeds, prog) => PublicKey.findProgramAddressSync(seeds, prog)[0];

function tokenStoragePDA(programId) {
  return pda([
    Buffer.from('hyperlane_message_recipient'), Buffer.from('-'),
    Buffer.from('handle'), Buffer.from('-'), Buffer.from('account_metas'),
  ], programId);
}
function dispatchAuthPDA(programId) {
  return pda([
    Buffer.from('hyperlane_dispatcher'), Buffer.from('-'), Buffer.from('dispatch_authority'),
  ], programId);
}
function mintPDA(programId) {
  return pda([Buffer.from('hyperlane_token'), Buffer.from('-'), Buffer.from('mint')], programId);
}
function ataPayerPDA(programId) {
  return pda([Buffer.from('hyperlane_token'), Buffer.from('-'), Buffer.from('ata_payer')], programId);
}

// ── Borsh-encode the warp init instruction data ────────────────────────────
//
//  Layout (borsh 1.x — u8 enum variants):
//  [1,1,1,1,1,1,1,1]  — 8 byte discriminator (PROGRAM_INSTRUCTION_DISCRIMINATOR)
//  [0]                 — Instruction::Init variant (u8)
//  [32]                — mailbox pubkey
//  [0|1] + [32]?       — Option<Pubkey> ISM
//  [0|1] + [32] + [u8] + [32]  — Option<(Pubkey, IGPType)>
//  [1]                 — decimals
//  [1]                 — remote_decimals
//
function buildWarpInitData(mailbox, ismPubkey, igpProgram, igpAccount, decimals) {
  const parts = [
    Buffer.from([1, 1, 1, 1, 1, 1, 1, 1]),  // discriminator
    Buffer.from([0]),                          // Init variant
    mailbox.toBuffer(),                        // mailbox pubkey
    ismPubkey                                  // ISM: None or Some
      ? Buffer.concat([Buffer.from([1]), ismPubkey.toBuffer()])
      : Buffer.from([0]),
    igpProgram && igpAccount                   // IGP: None or Some(prog, OverheadIgp(acct))
      ? Buffer.concat([
          Buffer.from([1]),
          igpProgram.toBuffer(),
          Buffer.from([1]),   // OverheadIgp variant
          igpAccount.toBuffer(),
        ])
      : Buffer.from([0]),
    Buffer.from([decimals, decimals]),         // decimals + remote_decimals
  ];
  return Buffer.concat(parts); // 110 bytes total
}

function buildWarpInitInstruction(programId, payer, mailbox, ism, igpProg, igpAcct, decimals) {
  return new TransactionInstruction({
    programId,
    keys: [
      { pubkey: SystemProgram.programId,  isSigner: false, isWritable: false },
      { pubkey: tokenStoragePDA(programId), isSigner: false, isWritable: true  },
      { pubkey: dispatchAuthPDA(programId), isSigner: false, isWritable: true  },
      { pubkey: payer,                      isSigner: true,  isWritable: true  },
      { pubkey: mintPDA(programId),         isSigner: false, isWritable: true  },
      { pubkey: ataPayerPDA(programId),     isSigner: false, isWritable: true  },
    ],
    data: buildWarpInitData(mailbox, ism, igpProg, igpAcct, decimals),
  });
}

// ── Config loader ──────────────────────────────────────────────────────────
async function loadConfig() {
  const netKey   = process.argv[2] || process.env.NET_KEY   || 'solanamainnet';
  const tokenKey = process.argv[3] || process.env.TOKEN_KEY || 'igorfake';

  const SOL_CFG = path.join(SCRIPT_DIR, 'warp-sealevel-config.json');
  const EVM_CFG = path.join(SCRIPT_DIR, 'warp-evm-config.json');

  const sol = JSON.parse(fs.readFileSync(SOL_CFG, 'utf8'));
  const net = sol.networks?.[netKey];
  if (!net) throw new Error(`Network '${netKey}' not found in warp-sealevel-config.json`);
  const tok = net.warp_tokens?.[tokenKey] || {};

  const cfg = {
    rpcUrl:       process.env.NET_RPC        || net.rpc,
    keypairPath:  (process.env.KEYPAIR_PATH  || net.keypair || '').replace(/^~/, process.env.HOME),
    mailbox:      process.env.MAILBOX         || net.mailbox || '',
    ismProgram:   process.env.ISM_PROGRAM_ID || net.ism?.program_id || null,
    igpProgram:   process.env.IGP_PROGRAM_ID || net.igp?.program_id || '',
    igpAccount:   process.env.IGP_ACCOUNT    || net.igp?.account    || '',
    decimals:     parseInt(process.env.DECIMALS || tok.decimals || 6),
    programId:    process.env.WARP_PROGRAM_ID || tok.program_id || '',
    metadataUri:  process.env.TOKEN_URI       || tok.metadata_uri || '',
    ataFunding:   parseInt(process.env.ATA_PAYER_FUNDING || '50000000'),
    priorityFee:  parseInt(process.env.PRIORITY_FEE_MICRO_LAMPORTS || '500000'),
    netKey, tokenKey,
  };

  // Token name/symbol from EVM config
  if (fs.existsSync(EVM_CFG)) {
    const evm = JSON.parse(fs.readFileSync(EVM_CFG, 'utf8'));
    const evmTok = evm?.terra_classic?.tokens?.[tokenKey];
    cfg.tokenName   = process.env.TOKEN_NAME   || evmTok?.name   || tokenKey.toUpperCase();
    cfg.tokenSymbol = process.env.TOKEN_SYMBOL || evmTok?.symbol || tokenKey.toUpperCase();
  } else {
    cfg.tokenName = cfg.tokenSymbol = tokenKey.toUpperCase();
  }

  // Fetch metadata URI for name/symbol override
  if (cfg.metadataUri?.startsWith('http')) {
    try {
      const fetched = await new Promise((res, rej) => {
        const url = new URL(cfg.metadataUri);
        const mod = url.protocol === 'https:' ? https : require('http');
        mod.get(cfg.metadataUri, { timeout: 8000 }, (r) => {
          let d = ''; r.on('data', c => d += c);
          r.on('end', () => { try { res(JSON.parse(d)); } catch(e) { rej(e); } });
        }).on('error', rej);
      });
      if (fetched.name)   cfg.tokenName   = fetched.name;
      if (fetched.symbol) cfg.tokenSymbol = fetched.symbol;
      logInfo(`Metadata: name='${cfg.tokenName}' symbol='${cfg.tokenSymbol}'`);
    } catch(e) {
      logWarn(`Metadata fetch failed (${e.message}) — using fallback`);
    }
  }

  return cfg;
}

// ── RPC helper ─────────────────────────────────────────────────────────────
async function rpcPost(rpcUrl, method, params) {
  return new Promise((resolve, reject) => {
    const body = JSON.stringify({ jsonrpc: '2.0', id: 1, method, params });
    const urlObj = new URL(rpcUrl);
    const mod = urlObj.protocol === 'https:' ? https : require('http');
    const req = mod.request({
      hostname: urlObj.hostname, port: urlObj.port || 443,
      path: urlObj.pathname + urlObj.search, method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(body) },
    }, (res) => {
      let d = ''; res.on('data', c => d += c);
      res.on('end', () => { try { resolve(JSON.parse(d)); } catch(e) { reject(new Error(d.slice(0,300))); } });
    });
    req.on('error', reject); req.write(body); req.end();
  });
}

// ── Main ────────────────────────────────────────────────────────────────────
async function main() {
  log(`\n${C}${W}╔═══════════════════════════════════════════════════════════════════╗${NC}`);
  log(`${C}${W}║    🛡️  WARP INIT — MEV-SAFE (single atomic transaction)            ║${NC}`);
  log(`${C}${W}╚═══════════════════════════════════════════════════════════════════╝${NC}\n`);

  // ── 1. Config ──────────────────────────────────────────────────────────────
  logSep('STEP 1 — LOAD CONFIG');
  const cfg = await loadConfig();

  for (const [k, v] of Object.entries({
    programId: cfg.programId, keypairPath: cfg.keypairPath,
    mailbox: cfg.mailbox, igpProgram: cfg.igpProgram, igpAccount: cfg.igpAccount,
  })) {
    if (!v) throw new Error(`Missing required config: ${k}`);
  }
  if (!fs.existsSync(cfg.keypairPath)) throw new Error(`Keypair not found: ${cfg.keypairPath}`);

  const payer      = Keypair.fromSecretKey(Uint8Array.from(JSON.parse(fs.readFileSync(cfg.keypairPath, 'utf8'))));
  const programId  = new PublicKey(cfg.programId);
  const mailbox    = new PublicKey(cfg.mailbox);
  const ism        = cfg.ismProgram ? new PublicKey(cfg.ismProgram) : null;
  const igpProg    = new PublicKey(cfg.igpProgram);
  const igpAcct    = new PublicKey(cfg.igpAccount);
  const mint       = mintPDA(programId);
  const ataP       = ataPayerPDA(programId);
  const tokStore   = tokenStoragePDA(programId);
  const connection = new Connection(cfg.rpcUrl, 'confirmed');

  logOk(`Network:    ${cfg.netKey} / ${cfg.tokenKey}`);
  logOk(`Program ID: ${programId.toBase58()}`);
  logOk(`Payer:      ${payer.publicKey.toBase58()}`);
  logOk(`Mint PDA:   ${mint.toBase58()}`);
  logOk(`ATA payer:  ${ataP.toBase58()}`);
  logOk(`Token store:${tokStore.toBase58()}`);

  // ── 2. Pre-flight ──────────────────────────────────────────────────────────
  logSep('STEP 2 — PRE-FLIGHT CHECKS');

  // Verify program exists
  const progInfo = await connection.getAccountInfo(programId);
  if (!progInfo) throw new Error(`Program ${programId.toBase58()} does NOT exist on-chain! Deploy it first.`);
  if (!progInfo.executable) throw new Error(`Account ${programId.toBase58()} is not executable!`);
  logOk(`Program verified on-chain (executable)`);

  const balance = await connection.getBalance(payer.publicKey);
  logOk(`Balance: ${(balance / LAMPORTS_PER_SOL).toFixed(6)} SOL`);
  if (balance < 0.05 * LAMPORTS_PER_SOL) throw new Error('Insufficient balance (need ≥ 0.05 SOL)');

  // Check existing state
  const tokStoreInfo = await connection.getAccountInfo(tokStore);
  if (tokStoreInfo) {
    logWarn(`Token storage exists (init already done). Checking mint...`);
    const mintInfo = await connection.getAccountInfo(mint);
    if (mintInfo) {
      logOk(`Mint also exists — going straight to metadata steps.`);
      await metadataAndAuthority(connection, payer, programId, mint, ataP, cfg);
      return;
    } else {
      logWarn(`Mint PDA missing but token storage exists!`);
      logWarn(`This state requires closing and redeploying. Run ./close-warp-program.sh first.`);
      process.exit(1);
    }
  }

  // ── 3. Build single atomic transaction ────────────────────────────────────
  logSep('STEP 3 — BUILD ATOMIC TRANSACTION (init + InitializeMint)');

  const { blockhash } = await connection.getLatestBlockhash('confirmed');
  logInfo(`Blockhash: ${blockhash}`);

  const tx = new Transaction({ recentBlockhash: blockhash, feePayer: payer.publicKey });

  // Compute budget
  tx.add(ComputeBudgetProgram.setComputeUnitLimit({ units: 1_400_000 }));
  tx.add(ComputeBudgetProgram.setComputeUnitPrice({ microLamports: cfg.priorityFee }));

  // Warp init (creates token_storage + dispatch_auth + mint_pda + ata_payer)
  tx.add(buildWarpInitInstruction(programId, payer.publicKey, mailbox, ism, igpProg, igpAcct, cfg.decimals));

  // MetadataPointer init (MUST be before InitializeMint2)
  tx.add(splToken.createInitializeMetadataPointerInstruction(
    mint, payer.publicKey, mint, TOKEN_2022,
  ));

  // InitializeMint2 (mint_authority = payer for now, transferred later)
  tx.add(splToken.createInitializeMint2Instruction(
    mint, cfg.decimals, payer.publicKey, null, TOKEN_2022,
  ));

  tx.sign(payer);

  const serialized = tx.serialize();
  logOk(`Transaction built: ${serialized.length} bytes (limit: 1232)`);
  if (serialized.length > 1232) throw new Error(`Transaction too large: ${serialized.length} bytes!`);

  const sig = bs58.encode(tx.signature);
  logInfo(`Signature: ${sig}`);
  logInfo(`Explorer:  https://explorer.solana.com/tx/${sig}`);

  // ── 4. Simulate ────────────────────────────────────────────────────────────
  logSep('STEP 4 — SIMULATE');

  const simResult = await rpcPost(cfg.rpcUrl, 'simulateTransaction', [
    serialized.toString('base64'),
    { encoding: 'base64', commitment: 'confirmed', sigVerify: false },
  ]);

  const simVal = simResult.result?.value;
  if (!simVal) throw new Error(`RPC error: ${JSON.stringify(simResult.error || simResult)}`);

  if (simVal.err) {
    logErr(`Simulation FAILED: ${JSON.stringify(simVal.err)}`);
    logErr(`Logs:`);
    (simVal.logs || []).forEach(l => log(`  ${l}`));
    throw new Error('Transaction simulation failed — will NOT submit.');
  }

  logOk(`Simulation passed! CUs used: ${simVal.unitsConsumed}`);
  (simVal.logs || []).forEach(l => logInfo(l));

  // ── 5. Submit ──────────────────────────────────────────────────────────────
  logSep('STEP 5 — SUBMIT TRANSACTION');
  logInfo('Sending transaction...');

  let txSig;
  for (let attempt = 1; attempt <= 5; attempt++) {
    try {
      txSig = await connection.sendRawTransaction(serialized, {
        skipPreflight: true, // already simulated above
        maxRetries: 5,
        preflightCommitment: 'confirmed',
      });
      logOk(`Tx sent (attempt ${attempt}): ${txSig}`);
      break;
    } catch(e) {
      logWarn(`Send attempt ${attempt} failed: ${e.message}`);
      if (attempt >= 5) throw e;
      await sleep(2000);
    }
  }

  // ── 6. Confirm ─────────────────────────────────────────────────────────────
  logSep('STEP 6 — WAIT FOR CONFIRMATION');
  logInfo(`Waiting for: ${txSig}`);

  const deadline = Date.now() + 90_000; // 90s
  let confirmed = false;
  let dotCount = 0;

  while (Date.now() < deadline && !confirmed) {
    await sleep(2500);
    dotCount++;

    const status = await connection.getSignatureStatus(txSig, { searchTransactionHistory: true });
    if (status?.value) {
      if (status.value.err) {
        log('');
        logErr(`Transaction FAILED: ${JSON.stringify(status.value.err)}`);

        // Get full transaction details for debugging
        try {
          const parsed = await connection.getParsedTransaction(txSig, { maxSupportedTransactionVersion: 0 });
          if (parsed?.meta?.logMessages) {
            logErr('Program logs:');
            parsed.meta.logMessages.forEach(l => log(`  ${l}`));
          }
        } catch(e2) {}

        process.exit(1);
      }

      const conf = status.value.confirmationStatus;
      if (conf === 'confirmed' || conf === 'finalized') {
        log('');
        logOk(`Transaction confirmed! (${conf})`);
        confirmed = true;
        break;
      }
    }

    // Re-submit periodically to keep it in the mempool (in case of slot skip)
    if (dotCount % 12 === 0) {
      logInfo('Re-broadcasting to prevent mempool drop...');
      const freshBh = await connection.getLatestBlockhash('confirmed');
      tx.recentBlockhash = freshBh.blockhash;
      tx.sign(payer);
      const newSig = bs58.encode(tx.signature);
      try {
        await connection.sendRawTransaction(tx.serialize(), { skipPreflight: true, maxRetries: 3 });
        logInfo(`Re-broadcast: ${newSig}`);
      } catch(e3) { /* ignore */ }
    }

    process.stdout.write('.');
  }
  log('');

  if (!confirmed) {
    // Last resort: check if mint was created anyway
    const mintCheck = await connection.getAccountInfo(mint);
    if (mintCheck) {
      logWarn('Timeout, but mint PDA exists — transaction likely landed.');
      confirmed = true;
    } else {
      throw new Error(`Transaction not confirmed after 90s. Check: https://explorer.solana.com/tx/${txSig}`);
    }
  }

  // ── 7. Verify ──────────────────────────────────────────────────────────────
  logSep('STEP 7 — VERIFY MINT');

  const mintInfo = await connection.getAccountInfo(mint);
  if (!mintInfo) {
    logErr('Mint PDA not found! Something went wrong.');
    process.exit(1);
  }
  logOk(`Mint PDA on-chain: ${mint.toBase58()} (${mintInfo.data.length} bytes)`);

  // ── 8. Metadata + Authority ────────────────────────────────────────────────
  await metadataAndAuthority(connection, payer, programId, mint, ataP, cfg);
}

// ── Post-init: fund ATA payer, initialize metadata, transfer authority ─────
async function metadataAndAuthority(connection, payer, programId, mint, ataP, cfg) {
  const { keypairPath, rpcUrl, tokenName, tokenSymbol, metadataUri,
          ataFunding, netKey, tokenKey } = cfg;
  const SPL = path.join(process.env.HOME, '.cargo/bin/spl-token');

  // ── Fund ATA payer ─────────────────────────────────────────────────────────
  logSep('STEP 8 — FUND ATA PAYER');
  const ataBalance = await connection.getBalance(ataP);
  logInfo(`ATA payer balance: ${(ataBalance / 1e9).toFixed(6)} SOL`);

  if (ataBalance < ataFunding) {
    const needed = ataFunding - ataBalance;
    logInfo(`Funding ATA payer: +${(needed / 1e9).toFixed(6)} SOL`);
    const { blockhash: bh } = await connection.getLatestBlockhash('confirmed');
    const fundTx = new Transaction({ recentBlockhash: bh, feePayer: payer.publicKey });
    fundTx.add(SystemProgram.transfer({ fromPubkey: payer.publicKey, toPubkey: ataP, lamports: needed }));
    fundTx.sign(payer);
    const fundSig = await connection.sendRawTransaction(fundTx.serialize(), { skipPreflight: false });
    await connection.confirmTransaction(fundSig, 'confirmed');
    logOk(`ATA payer funded: ${fundSig}`);
  } else {
    logOk('ATA payer already funded.');
  }

  // ── Initialize metadata ────────────────────────────────────────────────────
  logSep('STEP 9 — INITIALIZE METADATA');
  logInfo(`name='${tokenName}' symbol='${tokenSymbol}' uri='${metadataUri || ""}'`);

  const metaRes = spawnSync(SPL, [
    'initialize-metadata', mint.toBase58(),
    tokenName, tokenSymbol, metadataUri || '',
    '-p', TOKEN_2022.toBase58(),
    '--mint-authority', keypairPath,
    '--update-authority', payer.publicKey.toBase58(),
    '--with-compute-unit-limit', '500000',
    '--url', rpcUrl, '--fee-payer', keypairPath,
  ], { encoding: 'utf8', timeout: 120000, env: process.env });

  const metaOut = (metaRes.stdout || '') + (metaRes.stderr || '');
  if (metaRes.status === 0) {
    logOk('Metadata initialized!');
    logInfo(metaOut.trim().split('\n').slice(-3).join('\n'));
  } else if (/already.*init|already.*exist/i.test(metaOut)) {
    logOk('Metadata already initialized.');
  } else {
    logWarn(`spl-token initialize-metadata: exit ${metaRes.status}`);
    logWarn('Manual:');
    log(`  spl-token initialize-metadata ${mint.toBase58()} "${tokenName}" "${tokenSymbol}" "${metadataUri||''}" -p ${TOKEN_2022.toBase58()} --mint-authority ${keypairPath} --url ${rpcUrl}`);
  }

  // ── Transfer mint authority → mint PDA itself ───────────────────────────
  logSep('STEP 10 — TRANSFER MINT AUTHORITY → Mint PDA (self)');

  const authRes = spawnSync(SPL, [
    'authorize', mint.toBase58(), 'mint', mint.toBase58(),
    '-p', TOKEN_2022.toBase58(),
    '--authority', keypairPath,
    '--with-compute-unit-limit', '500000',
    '--url', rpcUrl, '--fee-payer', keypairPath,
  ], { encoding: 'utf8', timeout: 120000, env: process.env });

  const authOut = (authRes.stdout || '') + (authRes.stderr || '');
  if (authRes.status === 0) {
    logOk(`Mint authority transferred to: ${mint.toBase58()}`);
  } else if (/already|same/i.test(authOut)) {
    logOk('Mint authority already correct.');
  } else {
    logWarn(`spl-token authorize: exit ${authRes.status}`);
    logWarn(`Manual: spl-token authorize ${mint.toBase58()} mint ${mint.toBase58()} -p ${TOKEN_2022.toBase58()} --authority ${keypairPath} --url ${rpcUrl}`);
  }

  // ── Update config ──────────────────────────────────────────────────────────
  logSep('DONE');
  const mintAddr = mint.toBase58();
  logOk(`Mint address: ${G}${mintAddr}${NC}`);

  const SOL_CFG = path.join(SCRIPT_DIR, 'warp-sealevel-config.json');
  if (fs.existsSync(SOL_CFG)) {
    try {
      const sol = JSON.parse(fs.readFileSync(SOL_CFG, 'utf8'));
      if (sol.networks?.[netKey]?.warp_tokens?.[tokenKey]) {
        sol.networks[netKey].warp_tokens[tokenKey].mint_address = mintAddr;
        sol.networks[netKey].warp_tokens[tokenKey].deployed     = true;
        fs.writeFileSync(SOL_CFG, JSON.stringify(sol, null, 2));
        logOk('warp-sealevel-config.json updated (deployed=true, mint_address)');
      }
    } catch(e) { logWarn(`Config update error: ${e.message}`); }
  }

  console.log(`MINT_ADDRESS=${mintAddr}`);
  console.log(`JITO_INIT_OK=1`);
}

main().catch(err => {
  console.error(`\n${R}${W}FATAL: ${err.message}${NC}`);
  if (process.env.DEBUG) console.error(err.stack);
  process.exit(1);
});
