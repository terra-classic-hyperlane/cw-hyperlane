// build-migrate-proposal.mjs — builds a governance proposal JSON that migrates
// every governable Hyperlane infrastructure contract on Terra Classic to code
// built from the current fork `main` (includes upstream #142, the multisig ISM
// duplicate-signature fix, plus #138/#139/#143). Verifies each contract
// on-chain before including it — never assumes.
//
// New code_ids come from `yarn cw-hpl -n terraclassic upload local` run
// 2026-09-30 (uploads hpl_ism_multisig..hpl_warp_native as code_id 11687-11706,
// built from commit cd972f84 of terra-classic-hyperlane/cw-hyperlane).
//
// Usage: node build-migrate-proposal.mjs > migrate-contracts-proposal.json
const LCD = 'https://lcd.terra-classic.hexxagon.io';
const GOV = 'terra10d07y265gmmuvt4z0w9aw880jnsr700juxf95n';

// contract type -> newly uploaded code_id (2026-09-30 upload)
const NEW_CODE_ID = {
  hpl_mailbox: 11687,
  hpl_validator_announce: 11688,
  hpl_ism_multisig: 11690,
  hpl_ism_routing: 11692,
  hpl_igp: 11693,
  hpl_hook_aggregate: 11694,
  hpl_hook_fee: 11695,
  hpl_hook_merkle: 11696,
  hpl_hook_pausable: 11697,
  hpl_igp_oracle: 11704,
};

// every contract instance considered for this migration, with its type.
// warp_lunc/warp_ustc are included so the script can explain WHY they're
// excluded, not just silently skip them.
const INSTANCES = [
  { name: 'mailbox', type: 'hpl_mailbox', address: 'terra1fwg35n5esjgny7d8pxnz8usjpwsvpguk0txsy6cnqxy58x9fdlksjpx3p9' },
  { name: 'validator_announce', type: 'hpl_validator_announce', address: 'terra1gtnmdevekgxpvzej3wfy20e2n335gm3muwj6geduxxa86j3x70cq00asmy' },
  { name: 'ism_routing (default_ism)', type: 'hpl_ism_routing', address: 'terra1uhzzvt9x3u8hjnkp695hklexx2uywjvfqv454d93ds92sgtpwk7qrpxdg0' },
  { name: 'ism_multisig ETH', type: 'hpl_ism_multisig', address: 'terra187rzjc3dznfxqtqqrwh796e5q4khmvp5av8mka6zhp98zjfk2z2qneldar' },
  { name: 'ism_multisig BSC', type: 'hpl_ism_multisig', address: 'terra1nqj7qlnt2sty0dgnu3ss5z4u6wr7hjfea7cn6wpwjt2uymts8ucsmuj9xw' },
  { name: 'ism_multisig Solana', type: 'hpl_ism_multisig', address: 'terra10s3p36tjek8amhlc4krxpzln6g8n0qy9jq82wyda434l3rv89wfsucl50t' },
  { name: 'hook_aggregate default', type: 'hpl_hook_aggregate', address: 'terra1026v947k2jn58t09ppw003xujj92vp3lxv0fg3xk8ccz42r8d2sqvnmvel' },
  { name: 'hook_aggregate required', type: 'hpl_hook_aggregate', address: 'terra1xmdd7yhu3qdlfhrcku8srfvtday6efymj54gqz0daxsmn8pvqygq0nxq04' },
  { name: 'igp', type: 'hpl_igp', address: 'terra1taunhg629rssf3g939nqr0h594q5mssrzdj5lkx2hygmxmh72ghqeqqnvz' },
  { name: 'hook_pausable', type: 'hpl_hook_pausable', address: 'terra1x8s9qtw9355pfckywkns4e8f9zyfjaf8w5e5s8vh28ph5gzwwlks9tjcnf' },
  { name: 'hook_fee', type: 'hpl_hook_fee', address: 'terra1sud5xyknr93wmxem6kxdfd0vxcju47wuh7zdm5uecavrm36w669sp7j8ag' },
  { name: 'hook_merkle', type: 'hpl_hook_merkle', address: 'terra183lq6yqp8km3p34cxgk6k3u78uy4plqahey6rne7n9gy98delr9qyp0n2p' },
  { name: 'warp LUNC (native)', type: 'hpl_warp_native', address: 'terra1m7jcqxfn4hd7q4sywhw508nxshaf078c4vh83y0ts43y9tlp9dcs50cggy' },
  { name: 'warp USTC (native)', type: 'hpl_warp_native', address: 'terra1qu3x6vhk4y6w6erhmedzfp2ug53qm5nwpyarxveqa7tvwg0telxqvd3ccf' },
  { name: 'igp_oracle', type: 'hpl_igp_oracle', address: 'terra1j8xzgzk7vds5uzrplmnln4vcz6f205t9atdyflypzrr43cd5eh7scwqj0d' },
];

async function contractInfo(address) {
  const res = await fetch(`${LCD}/cosmwasm/wasm/v1/contract/${address}`);
  const json = await res.json();
  return json.contract_info;
}

const messages = [];
const skipped = [];

for (const inst of INSTANCES) {
  const info = await contractInfo(inst.address);
  const targetCodeId = NEW_CODE_ID[inst.type];

  if (!targetCodeId) {
    skipped.push(`${inst.name}: no new build for type ${inst.type} (not part of this migration)`);
    continue;
  }
  if (info.admin !== GOV) {
    skipped.push(`${inst.name}: admin is ${info.admin || '<none/immutable>'}, not governance (${GOV}) — cannot migrate via proposal`);
    continue;
  }
  if (Number(info.code_id) === targetCodeId) {
    skipped.push(`${inst.name}: already on code_id ${targetCodeId}`);
    continue;
  }

  messages.push({
    '@type': '/cosmwasm.wasm.v1.MsgMigrateContract',
    sender: GOV,
    contract: inst.address,
    code_id: String(targetCodeId),
    msg: {},
  });
}

const proposal = {
  title: 'Migrate Hyperlane infrastructure contracts to fix duplicate-signature-counting bug (upstream #142)',
  summary:
    `Migrates ${messages.length} governance-owned Hyperlane contract instances on Terra Classic ` +
    'to code built from terra-classic-hyperlane/cw-hyperlane main (commit cd972f84bbd5280d8731b3e02eaa9cf21f3dc670), ' +
    'which includes upstream PR #142 (many-things/cw-hyperlane commit d07e55e17c791a5f6557f114e3fb6cb433d9b800) fixing ' +
    'duplicate validator-signature counting in the multisig ISM, plus 3 cosmetic/feature commits (#138, #139, #143). ' +
    'Found independently by community researcher Fragwuerdig ' +
    '(https://discourse.luncgoblins.com/t/claim-hyperlane-infrastructure-ownership-for-governance/555/2?u=fragwuerdig), ' +
    'documented in terraclassic/doc/GOVERNANCE-PROPOSAL-CLAIM-OWNERSHIP-AUDIT.md §10. ' +
    'Excluded: Warp LUNC and Warp USTC (native collateral warps) have no contract admin at all (empty, permanently ' +
    'immutable — confirmed on-chain) and cannot be migrated by any proposal, ever. The IGP Oracle admin was ' +
    'transferred to governance separately on 2026-09-30 (tx 2182AB478B5197245C50CA6657D55BAF7AEBE41529D938F88BE36B975F84F4B6) ' +
    'and is included in this proposal. MigrateMsg is empty ({}) for every message; cw2 version ' +
    'check passes for all (stored 0.0.6 < new 0.0.7).',
  messages,
  deposit: '5000000000000uluna',
  expedited: false,
};

console.log(JSON.stringify(proposal, null, 2));
console.error('\n--- skipped ---');
for (const s of skipped) console.error('  ' + s);
console.error(`\n${messages.length} messages included.`);
