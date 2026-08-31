# Guia da Comunidade — Warp Routes Solana ↔ Terra Classic (Hyperlane)

Referência para desenvolvedores e membros da comunidade que vão **criar warp routes**
entre **Solana** e **Terra Classic** usando a infraestrutura Hyperlane **comunitária**
(IGP + ISM próprios, não os oficiais da Abacus Works).

> **Por que infra comunitária?** Os IGP/ISM oficiais da Hyperlane em Solana são
> controlados pela Abacus Works, não têm o domínio do Terra Classic configurado, e as
> taxas iriam para eles. A comunidade deploya o **seu próprio** IGP (taxas + oráculo)
> e ISM (validação), controlados pela governança da comunidade.

---

## 1. Arquitetura em 1 minuto

Uma warp route liga um token entre dois domínios. Cada mensagem cross-chain passa por:

- **Mailbox** — o "correio" Hyperlane em cada chain (usamos o **oficial** da Hyperlane).
- **ISM** (Interchain Security Module) — valida a assinatura do validator na mensagem
  recebida. Na Solana, o ISM **comunitário** valida mensagens vindas do Terra Classic.
- **IGP** (Interchain Gas Paymaster) — o remetente paga (em SOL) o gas que o relayer vai
  gastar na chain de destino. O IGP **comunitário** cobra por isso e as taxas vão para a
  comunidade.
- **Warp program (token)** — o programa que faz lock/mint do token (tipo `synthetic`
  para tokens que nascem na Solana representando um ativo do Terra Classic).
- **Relayer** (off-chain) — entrega as mensagens e paga o gas no destino.

---

## 2. Infraestrutura comunitária — endereços

### Solana Mainnet (`solanamainnet`, domain **1399811149**)

| Componente | Endereço | Origem |
|-----------|----------|--------|
| Mailbox | `E588QtVUvresuXq2KoNEwAmoifCzYGpRBdHByN9KQMbi` | oficial Hyperlane |
| Validator Announce | `pRgs5vN4Pj7WvFbxf6QDHizo2njq2uksqEUbaSghVA8` | oficial Hyperlane |
| **IGP program** (comunitário) | `FLZuKRsfdovLqd8n1AYhPCwLqBjfFyZY3A2edgnjdJoR` | ✅ deployado |
| **IGP account** (overhead-igp, usar no warp) | `FXacR73HiuNyvW7x34KYCDyv8XxM86pz31Ap8t2v3RCJ` | ✅ deployado |
| **IGP account** (inner) | `FPTvDsowMHXFKktoLgy2a2qfr5yL6846JHKwvk2mYKFk` | ✅ deployado |
| **ISM program** (comunitário) | `4MzF7HCfxuwj4EFHqZSEpvkcZZvv1mF37DP4pDHwR5VQ` | ✅ deployado |

Oráculo do IGP (domínio 132556): `token_exchange_rate=20000000000000` (2e13),
`gas_price=28325`, `token_decimals=6`, `destination_gas_overhead=3000000`.
ISM: validator `0x71b2b8c36a0c76b74be92eb7915e26a69b3b03eb`, threshold 1.

### Solana Testnet (`solanatestnet`, domain **1399811150**)

| Componente | Endereço |
|-----------|----------|
| Mailbox | `75HBBLae3ddeneJVrZeyrDfv6vb7SMC3aCpBucSXS5aR` |
| Validator Announce | `8qNYSi9EP1xSnRjtMpyof88A26GBbdcrsa61uSaHiwx3` |
| **IGP program** | `ESag6QsGmixv5HrtEgi5qxJxWQS1NeBa5TCVKfnCQ8c2` |
| **IGP account** (overhead-igp) | `FgsCd3gFPaUuzU7jH9rSp9YQ4mNrvxo9SxDs75FRgtny` |
| **ISM program** | `FQXMB763C9EMKGsGgjjkvtZvUakV9RieMpRwx11gRbja` |

### Terra Classic (destino)

| Rede | Domain | Chain ID | Validator (assina as msgs) |
|------|--------|----------|----------------------------|
| Mainnet | **132556** | `columbus-5` | `0x71b2b8c36a0c76b74be92eb7915e26a69b3b03eb` |
| Testnet | **1325** | `rebel-2` | `0x133fd7f7094dbd17b576907d052a5acbd48db526` |

### Binários verificáveis (SHA-256)

Qualquer pessoa pode auditar o bytecode **deployado on-chain** e conferir que bate com o
hash publicado. **Importante:** o Solana Explorer **não** exibe um hash do bytecode — a
verificação é feita **baixando** o programa com `solana program dump` e calculando o
SHA-256 (o dump é byte-idêntico ao `.so`, sem padding).

| Programa (mainnet) | Program ID | SHA-256 |
|--------------------|------------|---------|
| IGP | `FLZuKRsfdovLqd8n1AYhPCwLqBjfFyZY3A2edgnjdJoR` | `4321c4263c37317baafdb99e133ddcded8fca470c86b16383e681e9cecc08c6d` |
| ISM | `4MzF7HCfxuwj4EFHqZSEpvkcZZvv1mF37DP4pDHwR5VQ` | `7c97cfedfbce7321229b811af0e36a9d6e888904964f239eb6058d769f33a53d` |

```bash
RPC="https://mainnet.helius-rpc.com/?api-key=<KEY>"   # ou outro RPC de mainnet

# IGP
solana program dump FLZuKRsfdovLqd8n1AYhPCwLqBjfFyZY3A2edgnjdJoR igp.so --url "$RPC"
sha256sum igp.so
# deve retornar: 4321c4263c37317baafdb99e133ddcded8fca470c86b16383e681e9cecc08c6d

# ISM
solana program dump 4MzF7HCfxuwj4EFHqZSEpvkcZZvv1mF37DP4pDHwR5VQ ism.so --url "$RPC"
sha256sum ism.so
# deve retornar: 7c97cfedfbce7321229b811af0e36a9d6e888904964f239eb6058d769f33a53d
```

> ✅ **Verificado:** ambos os hashes on-chain foram baixados e conferem exatamente com
> os valores publicados acima (IGP `4321c4…c08c6d`, ISM `7c97cf…f33a53d`).

**Ver no Explorer** (existência, upgrade authority, slot do deploy — não mostra hash):
- IGP: https://explorer.solana.com/address/FLZuKRsfdovLqd8n1AYhPCwLqBjfFyZY3A2edgnjdJoR
- ISM: https://explorer.solana.com/address/4MzF7HCfxuwj4EFHqZSEpvkcZZvv1mF37DP4pDHwR5VQ

### Binário do warp token — prebuilt (não precisa compilar)

Para criar uma warp route o programa é o `hyperlane_sealevel_token.so`. A comunidade
disponibiliza esse binário **já compilado e verificado**, então você **não precisa**
rodar `cargo build-sbf` (15-20 min) — use `BINARY_SOURCE=local`.

| Binário | SHA-256 | Deploy de referência (exemplo verificável) |
|---------|---------|--------------------------------------------|
| `hyperlane_sealevel_token.so` | `d6f2fc9fed82c5079ce2cb1728d5f833d61c70e6d5f2f2a40d5df6d1bdb33419` | `Dd3ajD8WbEyx7z3HqPnDyvUgFqEBzvF1VePjYd1NGnbr` (warp LUNC, 29/08/2026) — hex32 `0xbb8812381e07b070e8d37945ae659b8ad17ff2c5c36f019f351f332d45a3b261` |

```bash
# conferir o binário de referência on-chain
solana program dump Dd3ajD8WbEyx7z3HqPnDyvUgFqEBzvF1VePjYd1NGnbr token.so --url "$RPC"
sha256sum token.so   # deve retornar d6f2fc9fed82c5079ce2cb1728d5f833d61c70e6d5f2f2a40d5df6d1bdb33419
```

> ⚠️ **Cada warp route é um programa PRÓPRIO** — no Sealevel o storage/mint são PDAs de
> seed fixo derivadas do `program_id`, ou seja **um programa = uma rota (singleton)**.
> Você deploya a **sua** instância, com **seu** Program ID. O que se compartilha é o
> **binário** (mesmo bytecode, hash `d6f2fc…`). O `Dd3ajD8W…` (warp LUNC) é só um
> exemplo de referência — **não** é um programa multi-token.

**⚡ Caminho mais rápido para criar sua warp:** use `deploy-warp-solana-buffer.sh` com
`BINARY_SOURCE=local`. Numa tacada ele reusa o `.so` prebuilt (sem compilar), deploya o
programa, faz o **init MEV-safe** (atômico) e já aponta o **ISM + IGP comunitários**.
É mais rápido que compilar do zero e fazer o deploy + init em passos separados.

---

## 3. Pré-requisitos

- **Solana CLI** (`solana`, `solana-keygen`) instalado.
- **Client Hyperlane Sealevel** compilado: `hyperlane-sealevel-client`
  (em `rust/sealevel/target/release/`). Os `.so` dos programas em `target/deploy/`.
- **Keypair** com SOL suficiente (deploys de programa custam ~1–2,3 SOL cada).
- **RPC decente** — **NÃO** use o público (`api.mainnet-beta.solana.com`): ele
  rate-limita (`429`) e trava deploys. Use **Helius** (plano Free $0 basta para
  deploys pontuais), QuickNode ou Triton. Aponte via `NET_RPC=...` ou no config.

---

## 4. Fluxo para criar uma warp route

A infra (IGP + ISM) já é da comunidade — normalmente você só precisa do **passo B**.

### A. (Uma vez, por rede) Deploy da infra comunitária
```bash
# ISM comunitário (valida msgs do Terra Classic)
BINARY_SOURCE=local ISM_VALIDATORS=<validator> ISM_THRESHOLD=1 ./create-warp-ism-solana.sh
# IGP comunitário (taxas + oráculo de gas)
ORACLE_EXCHANGE_RATE=<rate> BINARY_SOURCE=local ./create-warp-igp-solana.sh
```
Defaults já são mainnet (`solanamainnet`, domínio 132556, validator de columbus-5).
Para **testnet**, use os launchers `-testnet` (`create-warp-ism-solana-testnet.sh`,
`create-warp-igp-solana-testnet.sh`), que injetam os presets de rebel-2.

### B. Deploy do warp token
```bash
# 1) configure o token em warp-sealevel-config.json (ver seção 5)
# 2) rode o deploy MEV-safe:
BINARY_SOURCE=local TOKEN_KEY=<seu_token> ./deploy-warp-solana-buffer.sh          # mainnet
BINARY_SOURCE=local TOKEN_KEY=<seu_token> ./deploy-warp-solana-buffer-testnet.sh  # testnet
```
Isso faz: build/reuse do `.so` → deploy do programa → **init atômico MEV-safe** (warp
init + InitializeMint2 numa única tx) → configura **ISM**, **IGP**, **destination gas** →
transfere o owner do warp para o `owner` definido no config → grava tudo no config.

### C. Lado Terra Classic (rota de volta)
`enroll-remote-router` (Solana→TC) e `set_route` (TC→Solana) rodam automaticamente
**quando** o warp correspondente no Terra Classic estiver deployado com `deployed=true`
no bloco `.terra_classic[_testnet].tokens.<key>` do `warp-evm-config.json`. Enquanto não
estiver, esses passos são **pulados** (o lado Solana fica pronto e esperando).

---

## 5. Config do token (`warp-sealevel-config.json`)

Cada token vive em `.networks.<net>.warp_tokens.<key>`:

```json
{
  "deployed": false,
  "type": "synthetic",
  "program_id": "",
  "program_hex": "",
  "mint_address": "",
  "metadata_uri": "https://.../metadata-<token>.json",
  "decimals": 6,
  "owner": "<pubkey base58 do owner final do warp>"
}
```

- `type: synthetic` → token nasce na Solana representando o ativo do Terra Classic.
- `decimals` → precisa bater com o ativo de origem.
- `owner` → para quem o script transfere a posse do warp **ao final** do deploy.
  Em produção, use o **multisig dos validadores da Hyperlane** (não uma EOA de deploy).
- `program_id`/`mint_address`/`deployed` são preenchidos pelo script automaticamente.

---

## 6. Economia de gas (IGP)

O remetente na Solana paga, em SOL, o gas que o relayer gasta no Terra Classic. A conta
(programa IGP Sealevel):

```
cost_lamports = gas_amount × gas_price × token_exchange_rate ÷ 1e19 × 10^(9 − token_decimals)
```

Parâmetros do oráculo comunitário (domínio TC):

| Parâmetro | Valor | Significado |
|-----------|-------|-------------|
| `gas_price` | `28325` | preço do gas no TC (uluna/unidade) |
| `token_exchange_rate` | `20000000000000` (2e13) | taxa SOL↔LUNC **com buffer** |
| `token_decimals` | `6` | decimais do uluna |
| `destination_gas_overhead` | `3000000` | gas somado por mensagem |

**Como o `token_exchange_rate` é calculado:**
```
rate_justo = (preço_LUNC ÷ preço_SOL) × 1e19
```
Ex.: SOL=$81,43 e LUNC=$0,00006367 → ~7,82e12. Usamos **2e13** (buffer ~2,5×) para
proteger o relayer de subpagamento se o LUNC valorizar / SOL cair. Como o fee em SOL é
minúsculo, superpagar um pouco é irrelevante.

**Atualização:** o rate é estático on-chain. Só o `owner` do IGP pode alterá-lo. A
estratégia recomendada é **buffer folgado + atualização rara via governança** (não
automação com chave quente — quem é owner do IGP também pode trocar o beneficiário).

---

## 7. Segurança e ownership

### Papéis do IGP (todos no `owner` — indivisíveis no programa Sealevel)
- **owner** — configura oráculo, troca beneficiário, transfere posse.
- **beneficiary** — recebe as taxas acumuladas (via `claim`, permissionless).
- **upgrade authority** (BPF loader) — pode trocar o bytecode do programa.

### Modelo de handoff (deployer → governança)
1. Deploy com a **chave de deploy** (quente) — vira owner temporário.
2. Configura tudo (oráculo, validators, beneficiary) **enquanto** ainda é owner.
3. Transfere **owner + upgrade authority** para o **multisig dos validadores da Hyperlane** (Squads).
   - Use `transfer-solana-ownership.sh` (ver `TRANSFER-SOLANA-OWNERSHIP.md`).
   - Ordem importa: setar beneficiary **antes** de transferir o owner.
   - São **3 autoridades** por programa (owner de access-control, upgrade authority) +
     o **route owner** do warp — todas precisam ir para o multisig.

### ISM (validação)
O ISM comunitário na Solana valida mensagens do Terra Classic checando a assinatura do
**validator** daquela rede (mainnet `0x71b2b8c3…`, testnet `0x133fd7f7…`) com o
`threshold` configurado (1). Validator errado = mensagens não validam.

---

## 8. Verificação on-chain

```bash
RPC="https://mainnet.helius-rpc.com/?api-key=<KEY>"   # use um RPC real

# programa deployado + upgrade authority
solana program show <PROGRAM_ID> --url $RPC | grep -E 'Authority|Executable'

# estado do warp (owner/ISM/IGP configurados)
hyperlane-sealevel-client -u $RPC token query --program-id <WARP_PID> synthetic \
  | grep -A2 'owner: Some'
```

> Os `query` de **IGP** e **ISM** do client têm um bug (`unwrap` em None) e podem
> **panicar** — não afeta os deploys. Para conferir owner/oráculo do IGP, decodifique a
> conta on-chain (layout `[1][8 disc][bump][salt32][owner Option][beneficiary 32][gas_oracles map]`).

---

## 9. Gotchas (aprendidos na prática)

- **RPC público = `429`.** Deploys travam no `api.mainnet-beta.solana.com`. Use Helius/etc.
- **Buffer preso ≠ SOL perdido.** Se um `solana program deploy` for cancelado, o buffer
  fica financiado (~1,6 SOL). Recupere com:
  ```bash
  solana program close <BUFFER> --recipient <PAYER> -k <KEYPAIR> --url $RPC
  ```
  Ou simplesmente **re-rode o deploy** — ele reusa o buffer e o consome no programa.
- **Salt do IGP** usa `--context` (keccak do nome `tc-community`), não `--account-salt`.
- **`validator_announce`** é obrigatório no `core/program-ids.json` (schema `CoreProgramIds`).
- **Não commite a API key** do RPC no `warp-sealevel-config.json` — passe via `NET_RPC=`.
- **Custo aproximado:** IGP ~1,6 SOL · ISM ~1,1 SOL · warp synthetic ~2,2 SOL (+ rent de contas).

---

## 10. Scripts de referência

| Script | Função |
|--------|--------|
| `create-warp-ism-solana.sh` / `-testnet` | deploy do ISM comunitário |
| `create-warp-igp-solana.sh` / `-testnet` | deploy do IGP comunitário + oráculo |
| `deploy-warp-solana-buffer.sh` / `-testnet` | deploy MEV-safe de um warp token |
| `transfer-solana-ownership.sh` | handoff de posse (infra + warp) → owner/multisig |

Docs relacionados: `TRANSFER-SOLANA-OWNERSHIP.md`, `WARP-SOLANA-GUIDE.md`,
`create-warp-sealevel-guide.md`.

---

## 11. Exemplo completo — `lunc` (mainnet)

> Warp route **viva** do LUNC nativo (Terra Classic ↔ Solana Mainnet), deployada em
> 29/08/2026 com transferências bidirecionais testadas no mesmo dia. Use este exemplo
> como **template** para a warp de qualquer projeto — troque o token, os metadados e o
> owner. Todos os endereços abaixo são reais (Solana Mainnet). O fluxo foi validado
> originalmente com um token de teste, hoje descontinuado.

### Endereços finais

| Item | Endereço |
|------|----------|
| Warp program | `Dd3ajD8WbEyx7z3HqPnDyvUgFqEBzvF1VePjYd1NGnbr` |
| Program hex32 (p/ `set_route` no TC) | `0xbb8812381e07b070e8d37945ae659b8ad17ff2c5c36f019f351f332d45a3b261` |
| Mint (Token-2022) | `8dxTo5reLtvRDx3Q8WEP33Uj2C5u6372EygJdNbsLFKG` |
| ISM (comunitário) | `4MzF7HCfxuwj4EFHqZSEpvkcZZvv1mF37DP4pDHwR5VQ` |
| IGP account (comunitário) | `FXacR73HiuNyvW7x34KYCDyv8XxM86pz31Ap8t2v3RCJ` |
| Owner (bootstrap) | `BirXd4QDxfq2vx9LGqgXXSgZrjT81rhoFGUbQRWDEf1j` (deployer → multisig no handoff) |
| Terra Classic warp (native `uluna`) | `terra1m7jcqxfn4hd7q4sywhw508nxshaf078c4vh83y0ts43y9tlp9dcs50cggy` |
| TC warp owner (assina o `set_route`) | `terra1run9wz09uhh6pu7ggcwwetrgye4wu7wn26mawp` |
| SHA-256 do binário | `d6f2fc9fed82c5079ce2cb1728d5f833d61c70e6d5f2f2a40d5df6d1bdb33419` |

**Status: rota BIDIRECIONAL ✅ (29/08/2026)** — Solana→TC (enroll-remote-router) e
TC→Solana (`set_route`) configurados, com transferências reais testadas nas duas
direções. Registro completo: `doc/install/DEPLOY-HASHES.md` §5.

### Processo (3 passos)

**1. Deploy do programa (`.so`)** — sobe o binário verificado sob um Program ID novo:
```bash
NET_RPC="https://mainnet.helius-rpc.com/?api-key=<KEY>" \
NET_KEY=solanamainnet BINARY_SOURCE=local \
./create-warp-program-solana.sh
# → reporta Program ID (ex.: Dd3ajD8W…) + hex32 + SHA-256 (~2,2 SOL)
```

**2. Warp init + wiring** — liga o programa à rota (init MEV-safe + ISM/IGP/gas/enroll):
```bash
NET_RPC="https://mainnet.helius-rpc.com/?api-key=<KEY>" \
WARP_PROGRAM_ID=Dd3ajD8WbEyx7z3HqPnDyvUgFqEBzvF1VePjYd1NGnbr \
TOKEN_KEY=lunc NET_KEY=solanamainnet BINARY_SOURCE=local \
./deploy-warp-solana-buffer.sh
```
Faz: init atômico (mint + metadata) → set **ISM** (`4MzF7HCf`) → set **IGP**
(`FLZuKR`/`FXacR73`) → **destination gas** (domínio 132556) → **enroll-remote-router**
(Solana→TC) → transfere o owner do warp.

**3. Rota de volta (Terra Classic → Solana)** — `set_route` no contrato do TC. ✅ Feito.
Precisa da chave do **owner do warp no TC** (`terra1run9wz…`), pois `set_route` é
owner-gated. Rode só este passo com os `SKIP_*` (pula o que já está pronto):
```bash
export TERRA_PRIVATE_KEY='<hex_do_owner_TC>'    # não commite / não exponha
NET_RPC="https://mainnet.helius-rpc.com/?api-key=<KEY>" \
WARP_PROGRAM_ID=Dd3ajD8WbEyx7z3HqPnDyvUgFqEBzvF1VePjYd1NGnbr \
SKIP_INIT=1 SKIP_ISM=1 SKIP_IGP=1 SKIP_GAS=1 SKIP_ENROLL=1 \
TOKEN_KEY=lunc NET_KEY=solanamainnet BINARY_SOURCE=local \
./deploy-warp-solana-buffer.sh
```
Registra no TC: `domain 1399811149 → route bb881238…`. É idempotente.
Exemplo executado: TX `14C2BF10…D65D9DA`
(`finder.hexxagon.io/columbus-5/tx/14C2BF10D2288940F2D65F3BD3017967B9563CF4CC98E8C314799C72ED65D9DA`).

> Alternativa manual: `terrad tx wasm execute <TC_WARP> '{"router":{"set_route":{"set":{"domain":1399811149,"route":"bb881238…"}}}}' --from <KEY> --chain-id columbus-5 --node <TC_RPC> --gas auto --gas-adjustment 1.5 --fees 12000000uluna --yes` (route **sem** `0x`).

### Lições aprendidas (valem para qualquer deploy)

- **Sempre passe `NET_RPC=<Helius real>`.** O `jito-warp-init.js` usa o RPC do config;
  o placeholder `YOUR_HELIUS_API_KEY` dá **`401 invalid api key`**, e o RPC público dá **`429`**.
- **Programa fechado ≠ redeploy no mesmo ID.** `solana program close` é definitivo — um
  deploy novo gera Program ID novo (aqui: `Hs4FrEg` fechado → `EPJNrr` novo).
- **hex32 vem do Program ID, não do config.** Um `program_hex` velho no config poderia
  vazar para o `set_route` e apontar para o programa errado — corrigido para sempre
  derivar do `WARP_PROGRAM_ID`.
- **Não precisa compilar.** O mesmo `.so` verificado (`d6f2fc…`) serve para todos — use
  `BINARY_SOURCE=local` e pule os 15-20 min de build.
- **Custo real** do deploy do programa ≈ **2,2 SOL** (a estimativa antiga mostrava a
  metade; corrigida).

---

## 12. Agentes off-chain (Validator + Relayer) — operação e troubleshooting

A infra on-chain **não entrega mensagens sozinha**. É preciso rodar dois agentes
(binários Hyperlane, ex.: via systemd):

- **Validator** (valida columbus-5): assina os checkpoints da merkle tree da mailbox de
  origem, publica as assinaturas num **bucket S3**, e **anuncia** o local no
  `validator_announce` de columbus-5.
- **Relayer**: lê a mensagem despachada no TC, pega a assinatura do validator, monta a
  prova para o ISM comunitário e **submete a tx de entrega** no destino (pagando o gas).

### Config crítico do VALIDATOR (mainnet)
| Campo | Valor correto (mainnet) |
|-------|-------------------------|
| `originChainName` | `terraclassic` |
| `domainId` (terraclassic) | **132556** (NÃO 1325 = rebel-2/testnet) |
| `merkleTreeHook` (terraclassic) | `0x3c7e0d10013db710c6b8322dab479e3f0950fc1dbe49a1cf3e9950429db9f8ca` (NÃO `0xcb5cd50e…` = testnet) |
| `checkpointSyncer.bucket` | um bucket S3 **exclusivo de mainnet** |

> ⚠️ **NUNCA compartilhe o mesmo bucket S3 entre validator de testnet e de mainnet.**
> Um validator testnet gravando no bucket de mainnet escreve checkpoints com
> `mailbox_domain: 1325`, que o relayer **descarta** (mismatch de domínio) → as
> entregas de mainnet travam. Use buckets separados (ex.: `…-terraclassic` para mainnet,
> `…-terraclassic-testnet` para testnet).

### Config crítico do RELAYER (mainnet)
- `relayChains` inclui **`solanamainnet`** (ex.: `terraclassic,bsc,ethereum,solanamainnet`).
- `chains.solanamainnet.rpcUrls` → use **Helius** (o público `api.mainnet-beta.solana.com`
  dá 429 e falha em "landar" tx sob congestionamento).
- **Signer Solana COM SOL.** O relayer paga cada entrega no Solana (~**0,0013 SOL** cada:
  taxa + ATA + mint). Sem SOL, **nada entrega** (a mensagem fica pendente sem erro claro).
  ~$5 (≈0,06 SOL) cobre ~40 entregas — **monitore e recarregue** o signer.
- RPCs de **BSC/ETH** com API key (os públicos dão `limit exceeded`/`unauthorized`).

### Troubleshooting: "fiz a transferência mas o token não chegou"

Cheque nesta ordem:

```bash
RPC="https://mainnet.helius-rpc.com/?api-key=<KEY>"
CLIENT=~/hyperlane-monorepo/rust/sealevel/target/release/hyperlane-sealevel-client
MAILBOX=E588QtVUvresuXq2KoNEwAmoifCzYGpRBdHByN9KQMbi

# 1) A mensagem foi entregue no destino?
$CLIENT -u "$RPC" mailbox delivered --message-id <0xMSGID> --program-id $MAILBOX

# 2) O validator está assinando o domínio CERTO (132556, não 1325)?
B="<bucket-do-validator>"; U="https://$B.s3.<region>.amazonaws.com"
curl -s "$U/checkpoint_latest_index.json"                    # ex.: 8
curl -s "$U/checkpoint_8_with_id.json" | grep mailbox_domain # deve ser 132556

# 3) Validator está em dia? (métrica)
curl -s localhost:9090/metrics | grep hyperlane_latest_checkpoint

# 4) O SIGNER do relayer tem SOL?
solana balance <SIGNER_SOLANA_DO_RELAYER> --url "$RPC"       # se 0 -> financie!

# 5) O relayer está tentando entregar? (logs)
journalctl -u hyperlane-relayer | grep <MSGID>              # InclusionStage / Finalized
```

**Causas reais já encontradas (validação do fluxo em mainnet, 2026):**
1. **Bucket S3 compartilhado testnet+mainnet** → checkpoints `domain 1325` poluíram o
   bucket de mainnet → relayer travou. *Fix:* apagar os checkpoints 1325 do bucket +
   corrigir `checkpoint_latest_index` + bucket separado para testnet.
2. **Signer Solana do relayer com 0 SOL** → o relayer montava a tx mas não conseguia
   submeter. *Fix:* enviar SOL para o signer.

Depois de corrigir, o relayer **reprocessa as pendentes automaticamente** (não precisa
reenviar a transferência).
