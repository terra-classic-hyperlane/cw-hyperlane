# Complete Guide: `create-warp-evm.sh`

> Interactive script to create and configure Hyperlane Warp Routes on EVM networks connected to Terra Classic.  
> Fully portable — just copy the `terraclassic/` folder to any `cw-hyperlane` project.

---

## 📋 Table of Contents

1. [What the script does](#1-what-the-script-does)
2. [Prerequisites](#2-prerequisites)
3. [File structure](#3-file-structure)
4. [Configuring `warp-evm-config.json`](#4-configuring-warp-evm-configjson)
   - [Section `terra_classic.tokens`](#41-section-terra_classictokens)
   - [Section `networks`](#42-section-networks)
   - [Adding a new token](#43-adding-a-new-token)
   - [Enabling a new network](#44-enabling-a-new-network)
5. [Configuring `config.yaml`](#5-configuring-configyaml)
6. [Running the script](#6-running-the-script)
   - [Full execution (from scratch)](#61-full-execution-from-scratch)
   - [Automatic Terra Classic deploy](#62-automatic-terra-classic-deploy)
   - [Resuming after failure](#63-resuming-after-failure)
   - [Skipping already executed steps](#64-skipping-already-executed-steps)
7. [What the script configures — Detailed steps](#7-what-the-script-configures--detailed-steps)
8. [Manual IGP deploy via Remix](#8-manual-igp-deploy-via-remix)
9. [Warp deploy on Terra Classic (manual)](#9-warp-deploy-on-terra-classic-manual)
10. [Updating the JSON after deploy](#10-updating-the-json-after-deploy)
11. [Helper scripts](#11-helper-scripts)
12. [Using in another project (portability)](#12-using-in-another-project-portability)
13. [Troubleshooting](#13-troubleshooting)
14. [Manual AggregationHook fix (without the script)](#14-manual-aggregationhook-fix-without-the-script)
15. [Deployed address reference](#15-deployed-address-reference)
16. [How to find Hyperlane addresses for any network](#16-how-to-find-hyperlane-addresses-for-any-network)

---

## 1. What the script does

O `create-warp-evm.sh` automatiza o deploy e a configuração completa de um Warp Route Hyperlane no lado EVM, conectado à Terra Classic.

Para cada par **token + rede EVM** escolhido, o script executa de forma automatizada:

| Component | What it is | Why it is needed |
|---|---|---|
| **Terra Classic Warp** | `hpl_warp_cw20` or `hpl_warp_native` contract | Entry/exit point on Terra Classic |
| **Mailbox** | Hyperlane central hub of the EVM network | Receives and sends cross-chain messages |
| **ISM** | Interchain Security Module (`messageIdMultisigIsm`) | Validates that messages came from Terra Classic |
| **IGP** | Custom gas contract (`TerraClassicIGPStandalone`) | Calculates and charges gas for execution on Terra Classic |
| **AggregationHook** | `[MerkleTreeHook + IGP]` as Warp hook | Ensures messages enter the merkle tree (for the validator) **and** pay the IGP |
| **enrollRemoteRouter** | Bidirectional link Warp EVM ↔ Warp Terra | Authorizes the cross-chain route |

---

## 2. Prerequisites

### Required tools

| Tool | Min version | Installation |
|---|---|---|
| `bash` | 4+ | nativo no Linux/macOS |
| `jq` | 1.6+ | `sudo apt install jq` |
| `node` / `npm` | 18+ | [nodejs.org](https://nodejs.org/) |
| `yarn` | 1+ | `npm install -g yarn` |
| `python3` | 3.6+ | `sudo apt install python3` |
| `hyperlane CLI` | **26+** | `npm install -g @hyperlane-xyz/cli` |

> ⚠️ **A versão mínima do Hyperlane CLI é v26.** Versões anteriores falham com `invalid_enum_value` ao processar o protocolo `tron`. O script detecta isso e atualiza automaticamente.

### Recommended tools (automatic IGP deploy)

| Tool | Installation |
|---|---|
| `forge` (Foundry 1.x) | `curl -L https://foundry.paradigm.xyz \| bash && foundryup` |
| `cast` (Foundry 1.x) | Instalado junto com `forge` |

> **Sem o Foundry**, o script pausa na Etapa 3 e exibe instruções para deploy manual via **Remix IDE** (veja [Seção 8](#8-deploy-manual-do-igp-via-remix)).

### Minimum balance

| Network | Recommended balance | Faucet |
|---|---|---|
| Sepolia | 0.1 ETH | [sepoliafaucet.com](https://sepoliafaucet.com) |
| BSC Testnet | 0.1 BNB | [testnet.binance.org/faucet-smart](https://testnet.binance.org/faucet-smart) |

---

## 3. File structure

A pasta `terraclassic/` é autocontida. Copie-a inteira para qualquer projeto `cw-hyperlane`:

```
terraclassic/
│
├── create-warp-evm.sh                     ← script principal de deploy (executável)
├── enroll-terra-router.sh                 ← vincula rota EVM no Warp Terra Classic
├── transfer-cw20-terra.sh                 ← transfere tokens CW20 na Terra Classic
├── warp-evm-config.json                   ← configuração de redes e tokens (EDITE AQUI)
├── TerraClassicIGPStandalone-Sepolia.sol  ← contrato IGP (compilado/deployado automaticamente)
├── config.yaml                            ← configuração Terra Classic para o cw-hpl CLI
│
├── context/
│   └── terraclassic.json                  ← deployments existentes na Terra Classic
│
├── warp/
│   ├── terraclassic-cw20-xpto.json        ← config CW20 collateral (gerado/editável)
│   ├── terraclassic-cw20-juris.json       ← config CW20 collateral
│   ├── terraclassic-native-ustc.json      ← config native collateral
│   ├── terraclassic-native.json           ← config native collateral (genérico)
│   └── warp-<rede>-<token>.yaml           ← YAMLs do Hyperlane CLI (gerados automaticamente)
│
├── log/
│   ├── create-warp-evm.log                ← log completo de execução
│   └── WARP-<REDE>-<TOKEN>.txt            ← relatórios de deploy
│
└── docs/
    ├── create-warp-evm-guide.md           ← este documento
    └── enroll-terra-router-guide.md       ← guia do enroll-terra-router.sh
```

**Files automatically generated during execution:**

| File | Content |
|---|---|
| `log/create-warp-evm.log` | Log completo da execução |
| `warp/warp-<rede>-<token>.yaml` | YAML gerado para o CLI Hyperlane |
| `log/WARP-<REDE>-<TOKEN>.txt` | Relatório com todos os endereços |
| `.warp-evm-state.json` | Estado salvo (permite retomar após falha) |

---

## 4. Configuring `warp-evm-config.json`

This is the **central configuration file**. All script behavior comes from here.

### 4.1 Section `terra_classic.tokens`

Defines each token with its Terra Classic configuration.

```json
"terra_classic": {
  "chain_id": "rebel-2",
  "domain": 1325,
  "rpc": "https://rpc.terra-classic.hexxagon.dev",
  "lcd": "https://lcd.terra-classic.hexxagon.dev",

  "tokens": {
    "meutoken": {
      "id": "meutoken",
      "name": "Meu Token",
      "symbol": "MTK",
      "decimals": 6,
      "description": "Descrição",
      "image": "https://url-da-imagem.png",

      "terra_warp": {
        "type":               "cw20",       ← "cw20" or "native"
        "mode":               "collateral", ← "collateral" or "locked"
        "owner":              "terra1...",  ← admin address on Terra Classic
        "denom":              "",           ← fill if type = "native" (e.g.: "uluna")
        "collateral_address": "terra1...", ← fill if type = "cw20"
        "warp_address":       "",          ← filled AFTER Terra Classic deploy
        "warp_hexed":         "",          ← filled AFTER Terra Classic deploy
        "deployed":           false        ← changes to true after deploy
      }
    }
  }
}
```

#### Pre-configured tokens

| ID | Type | Terra Classic Warp | Status |
|---|---|---|---|
| `wlunc` | `native/collateral` (uluna) | `terra1zlm0h...` | ✅ Deployed |
| `ustc` | `native/collateral` (uusd) | `terra1rnpvp...` | ✅ Deployed |
| `juris` | `cw20/collateral` | `terra1stu3c...` | ✅ Deployed |
| `xpto` | `cw20/collateral` | `terra16ql6l...` | ✅ Deployed |

---

### 4.2 Section `networks`

Defines each EVM network with all Hyperlane addresses and IGP configurations.

```json
"networks": {
  "sepolia": {
    "enabled": true,                        ← true = appears in menu
    "display_name": "Ethereum Sepolia Testnet",
    "chain_id": 11155111,
    "domain":   11155111,
    "is_testnet": true,
    "native_token": { "symbol": "ETH", "decimals": 18 },
    "rpc_urls": [
      "https://ethereum-sepolia-rpc.publicnode.com",
      "https://rpc.sepolia.org"             ← alternate URL (automatic fallback)
    ],
    "explorer": "https://sepolia.etherscan.io",

    "mailbox": {
      "address": "0xfFAEF09B3cd11D9b20d1a19bECca54EEC2884766"
    },

    "ism": {
      "type":             "messageIdMultisigIsm",
      "factory":          "0xFEb9585b2f948c1eD74034205a7439261a9d27DD",
      "deployed_address": "",               ← optional: ISM already deployed
      "validators":       [ "0x8804770d6a346210c0fd011258fdf3ab0a5bb0d0" ],
      "threshold":        1
    },

    "hook": {
      "merkle_tree":      "0x4917a9746A7B6E0A57159cCb7F5a6744247f2d0d",
      "agg_hook_factory": "0x160C28C92cA453570aD7C031972b58d5Dd128F72"
    },

    "igp": {
      "gas_oracle":      "0x7113Df4d1D8B230e6339011d10277a6E5AC4eC9c",
      "overhead_default": 200000,
      "terra_classic_config": {
        "exchange_rate":   142244393,       ← see calculation below
        "gas_price_wei":   38325000000
      }
    },

    "warp_tokens": {
      "xpto": {
        "deployed":          true,
        "address":           "0xbF43aA4878f5Ad0fcAC12Cd3A835DD3506981048",
        "igp_custom":        "0xf285D5769db5AE6E79Bb3179d03082f6bc47055f",
        "hook_aggregation":  "0x1a13d7A50b76d4527a611e507B3f73058eCa5eAC",
        "owner":             "0x133fD7F7094DBd17b576907d052a5aCBd48dB526"
      }
    }
  }
}
```

#### Calculating `exchange_rate`

Configures the IGP to charge the correct ETH/BNB amount to pay gas on Terra Classic.

```
exchange_rate = (PRECO_ETH_USD / PRECO_LUNC_USD) × 0,01

Exemplo:
  ETH  = $3.500 USD
  LUNC = $0,00006069 USD
  exchange_rate = (3500 / 0,00006069) × 0,01 ≈ 142.244.393
```

> **Update this value periodically** to reflect real market prices.

---

### 4.3 Adding a new token

**Step 1** — Add the token in the `terra_classic.tokens` section:

```json
"novotoken": {
  "id":          "novotoken",
  "name":        "Novo Token",
  "symbol":      "NTK",
  "decimals":    6,
  "description": "Descrição do token",
  "image":       "",
  "terra_warp": {
    "type":               "cw20",
    "mode":               "collateral",
    "owner":              "terra12awgqg...",
    "denom":              "",
    "collateral_address": "terra1ENDERECO_DO_CW20...",
    "warp_address":       "",
    "warp_hexed":         "",
    "deployed":           false
  }
}
```

> For **native** tokens, fill `"denom": "uluna"` (or other denom) and leave `collateral_address` empty.

**Step 2** — Add the token in `warp_tokens` for **each network**:

```json
"warp_tokens": {
  "novotoken": {
    "deployed":         false,
    "address":          "",
    "igp_custom":       "",
    "hook_aggregation": "",
    "owner":            ""
  }
}
```

**Step 3** — Run the script, select the new token and the desired network.  
If `TERRA_PRIVATE_KEY` is defined, the Terra Classic deploy is **automatic**.

---

### 4.4 Enabling a new network

To enable a disabled network, edit the `enabled` field:

```json
"bsctestnet": {
  "enabled": true,   ← mude de false para true
  ...
}
```

> ⚠️ **For mainnet networks**, confirm all Hyperlane contract addresses and `exchange_rate` before running.

---

## 5. Configuring `config.yaml`

The `config.yaml` contains the **Terra Classic account** settings used by the `cw-hpl` CLI for deployments.

```yaml
networks:
  - id: 'terraclassic'
    chainId: 'rebel-2'
    hrp: 'terra'
    signer: YOUR_TERRA_PRIVATE_KEY_HEX   ← private key without 0x prefix
    endpoint:
       rpc: 'https://rpc.terra-classic.hexxagon.dev'   ← use hexxagon (synchronized)
       rest: 'https://lcd.terra-classic.hexxagon.dev'
       grpc: 'https://grpc.terra-classic.hexxagon.dev'
    gas:
      price: '28.325'
      denom: 'uluna'
    domain: 1325
```

> ⚠️ **Use sempre o RPC do `hexxagon`**. O `rpc.luncblaze.com` pode estar dias atrasado e causar falhas silenciosas de deploy (timeout + `account sequence mismatch`). Veja [Troubleshooting](#-timeouterror2--account-sequence-mismatch).

---

## 6. Running the script

### 6.1 Full execution (from scratch)

```bash
# 1. Enter the terraclassic folder (or project root)
cd ~/cw-hyperlane/terraclassic

# 2. Give execution permission (first time only)
chmod +x create-warp-evm.sh

# 3. Set EVM private key (Warp owner)
export ETH_PRIVATE_KEY="0xSUA_CHAVE_EVM"

# 4. (Optional) Set Terra Classic private key for automatic deploy
export TERRA_PRIVATE_KEY="SUA_CHAVE_TERRA_HEX"

# 5. Run
./create-warp-evm.sh
```

The script presents two interactive menus:

```
STEP 1 — SELECT TOKEN (Terra Classic)
   [1]  wlunc  — Wrapped Terra Classic LUNC  (native/collateral)  ✅ terra warp deployed
   [2]  ustc   — Wrapped TerraClassic USD    (native/collateral)  ✅ terra warp deployed
   [3]  juris  — Juris Token                 (cw20/collateral)    ✅ terra warp deployed
   [4]  xpto   — XPTO Token                  (cw20/collateral)    ✅ terra warp deployed

  Choose the token [1-4]: 4

STEP 2 — SELECT EVM NETWORK
   [1]  bsctestnet — BSC Testnet             [testnet] [new deploy]
   [2]  sepolia    — Ethereum Sepolia Testnet [testnet] [warp already deployed]

  Choose the network [1-2]: 2

▶ Proceed with XPTO deploy on Ethereum Sepolia Testnet? [s/N]: s
```

---

### 6.2 Automatic Terra Classic deploy

When a token does not yet have a Warp on Terra Classic (`deployed: false`), the script offers **two options**:

#### Option A — Automatic (recommended)

Set `TERRA_PRIVATE_KEY` and the script does everything automatically:

```bash
export ETH_PRIVATE_KEY="0xSUA_CHAVE_EVM"
export TERRA_PRIVATE_KEY="SUA_CHAVE_TERRA_HEX"  ← chave sem prefixo 0x
./create-warp-evm.sh
```

The script will automatically:
1. Generate the configuration file `warp/terraclassic-<type>-<token>.json`
2. Copy `config.yaml` to the project root (required for `yarn cw-hpl`)
3. Execute `yarn cw-hpl warp create ... -n terraclassic`
4. Extract the `terra1...` address from the output
5. Convert to hex `0x...` (via Python3 — `bech32_to_hex`)
6. Update `warp-evm-config.json` automatically
7. Continue to `enrollRemoteRouter` on the EVM side

#### Option B — Manual

Without `TERRA_PRIVATE_KEY`, the script displays instructions and waits:

```bash
cd ~/cw-hyperlane
export PRIVATE_KEY="SUA_CHAVE_TERRA_HEX"
yarn cw-hpl warp create \
  ./warp/terraclassic-cw20-novotoken.json \
  -n terraclassic
```

After deploy, **fill `warp-evm-config.json`** with the returned address (see [Section 10](#10-updating-the-json-after-deploy)) and re-run the script.

---

### 6.3 Resuming after failure

The script saves state in `.warp-evm-state.json`. To resume:

```bash
./create-warp-evm.sh
# The script detects previous state and reports saved addresses
```

To **start from scratch** (delete state):

```bash
rm -f .warp-evm-state.json
./create-warp-evm.sh
```

---

### 6.4 Skipping already executed steps

Use environment variables to inform already deployed contracts:

```bash
# Warp Route EVM already deployed → skips Step 2
export WARP_ADDRESS="0xENDERECO_WARP"

# IGP already deployed → skips Step 3
export IGP_ADDRESS="0xENDERECO_IGP"

# Skip enrollRemoteRouter
export SKIP_ENROLL="1"

export ETH_PRIVATE_KEY="0xSUA_CHAVE"
./create-warp-evm.sh
```

---

## 7. What the script configures — Detailed steps

### Step 1 — Generate Warp YAML

Generates the file `warp/warp-<network>-<token>.yaml` for the Hyperlane CLI:

```yaml
# Exemplo: warp/warp-sepolia-xpto.yaml
sepolia:
  isNft: false
  type: synthetic
  name: "XPTO Token"
  symbol: "XPTO"
  decimals: 6
  owner: "0xSEU_ENDERECO"
  mailbox: "0xfFAEF09B3cd11D9b20d1a19bECca54EEC2884766"
  interchainSecurityModule:
    type: messageIdMultisigIsm
    validators:
      - "0x8804770d6a346210c0fd011258fdf3ab0a5bb0d0"
    threshold: 1
```

---

### Step 2 — Deploy Warp Route

Executes the synthetic token deploy on the EVM network via Hyperlane CLI:

```bash
hyperlane warp deploy \
  --config warp/warp-sepolia-xpto.yaml \
  --key $ETH_PRIVATE_KEY \
  --yes
```

Creates the synthetic ERC20 contract (`wXPTO`) and registers it in the network Mailbox.

---

### Step 3 — Deploy custom IGP

Deploys `TerraClassicIGPStandalone` with `hookType = 4`.

The script uses `cast send --create` with bytecode compiled by Foundry (compatible with **Foundry v1.5+**, which defaulted to dry-run mode in `forge create`):

```bash
# Compilação
forge build

# Deploy via cast send --create (Foundry v1.5+)
cast send \
  --rpc-url $RPC \
  --private-key $ETH_PRIVATE_KEY \
  --legacy \
  --create $BYTECODE_COM_ARGS_CONSTRUCTOR
```

| Parameter | Value |
|---|---|
| `_GASORACLE` | Oracle oficial Hyperlane da rede |
| `_GASOVERHEAD` | `200000` |
| `_BENEFICIARY` | Endereço da sua carteira (owner) |

---

### Step 4 — Configure Gas Oracle

Calls `setRemoteGasData` on the **GAS ORACLE** (not the IGP) to configure the exchange rate and gas price:

```bash
cast send $GAS_ORACLE \
  "setRemoteGasData(uint32,uint128,uint128)" \
  1325 142244393 38325000000 \
  --rpc-url $RPC --private-key $ETH_PRIVATE_KEY --legacy
```

| Parameter | Meaning |
|---|---|
| `1325` | Domain ID da Terra Classic |
| `142244393` | Exchange rate ETH/LUNC (escala 1e8) |
| `38325000000` | Gas price na rede em wei |

> ⚠️ `setRemoteGasData` é função do **Gas Oracle** (`igp.gas_oracle` no JSON), **não** do contrato IGP.

---

### Step 5 — Configure Hook (AggregationHook = MerkleTree + IGP)

The Warp needs to use an **`AggregationHook`** that combines:

- **`MerkleTreeHook`** — inserts the message into the Mailbox merkle tree, allowing the validator to sign it
- **Custom `IGP`** — charges gas at the time of dispatch

> ⚠️ **Por que não usar o IGP diretamente como hook?**
> O `requiredHook` do Mailbox Sepolia é o `ProtocolFee` (não o MerkleTreeHook). O MerkleTreeHook faz parte
> do `defaultHook`. Ao setar um hook customizado no Warp sem incluir o MerkleTree, as mensagens **nunca
> entram na merkle tree** — o validator não as vê e não as assina, impedindo a entrega na Terra Classic.

The script deploys the `AggregationHook` via factory and sets it on the Warp:

```bash
# 1. Deploy AggregationHook (deterministic address via factory)
cast call $AGG_HOOK_FACTORY \
  "deploy(address[])(address)" \
  "[$MERKLE_TREE_HOOK,$IGP_ADDRESS]" \
  --rpc-url $RPC

# 2. On-chain deploy
cast send $AGG_HOOK_FACTORY \
  "deploy(address[])" \
  "[$MERKLE_TREE_HOOK,$IGP_ADDRESS]" \
  --rpc-url $RPC --private-key $ETH_PRIVATE_KEY --legacy

# 3. Set on Warp Route
cast send $WARP_ADDRESS "setHook(address)" $AGG_HOOK_ADDRESS \
  --rpc-url $RPC --private-key $ETH_PRIVATE_KEY --legacy
```

| Parameter | Address (Sepolia) |
|---|---|
| `MERKLE_TREE_HOOK` | `0x4917a9746A7B6E0A57159cCb7F5a6744247f2d0d` |
| `AGG_HOOK_FACTORY` | `0x160C28C92cA453570aD7C031972b58d5Dd128F72` |

O endereço do `AggregationHook` deployado é salvo em `hook_aggregation` no `warp-evm-config.json`.

---

### Step 6 — Configure ISM

If a `deployed_address` is defined in the JSON, the script applies it to the Warp Route:

```bash
cast send $WARP_ADDRESS \
  "setInterchainSecurityModule(address)" $ISM_ADDRESS \
  --rpc-url $RPC --private-key $ETH_PRIVATE_KEY --legacy
```

Otherwise, the Warp inherits the Mailbox default ISM (normal behavior).

---

### Step 7 — enrollRemoteRouter (EVM → Terra Classic)

Registers the Terra Classic Warp on the EVM contract, authorizing messages from domain 1325:

```bash
cast send $WARP_ADDRESS \
  "enrollRemoteRouter(uint32,bytes32)" \
  1325 0xd03fafd53ce350f49ba3c6ebcb1bee7cbbf453f261ec8d5ce9f36c55ab3e26a1 \
  --rpc-url $RPC --private-key $ETH_PRIVATE_KEY --legacy
```

The `bytes32` is the `terra1...` address of the Warp on Terra Classic converted from bech32 to 32-byte hex.

> ⚠️ **Atenção ao formato bytes32:** endereços CosmWasm têm 32 bytes (64 hex chars) — não devem ser
> tratados como endereços EVM (20 bytes). A função `to_bytes32` do script foi corrigida para distinguir
> automaticamente os dois tipos: usa padding esquerdo com zeros apenas para endereços EVM (40 chars),
> e mantém o hash CosmWasm inalterado quando já tem 64 chars.

> This step is **skipped** if `deployed: false` in the JSON and `TERRA_PRIVATE_KEY` is not set.

---

### Step 7B — set_route (Terra Classic → EVM)

Registers the EVM Warp on the Terra Classic Warp contract, creating the complete **bidirectional link**:

```javascript
// CosmWasm execute (executado via Node.js + @cosmjs)
{
  "router": {
    "set_route": {
      "set": {
        "domain": 11155111,
        "route": "000000000000000000000000bf43aa4878f5ad0fcac12cd3a835dd3506981048"
      }
    }
  }
}
```

> ⚠️ **Sem esta etapa, o `transfer_remote` da Terra Classic falha com `route not found`.**
> A rota EVM deve ser registrada no lado Terra Classic antes de qualquer transferência.

Esta etapa requer `TERRA_PRIVATE_KEY` e é executada automaticamente no `create-warp-evm.sh`.
Para executar manualmente depois, use o script auxiliar `enroll-terra-router.sh`
(ver [Scripts auxiliares](#11-scripts-auxiliares)).

---

### Step 8 — Final verification

The script verifies on-chain via `cast call`:

| Verification | Function | Expected |
|---|---|---|
| Mailbox existe | `eth_getCode` | bytecode != `0x` |
| Warp Route existe | `eth_getCode` | bytecode != `0x` |
| Hook = AggregationHook | `hook()(address)` | endereço do AggregationHook `[MerkleTree+IGP]` |
| hookType = 4 | `hookType()(uint8)` | `4` |
| ISM configurado | `interchainSecurityModule()(address)` | endereço != zero |
| Router Terra (EVM→Terra) | `routers(uint32)(bytes32)` | bytes32 do Warp Terra |
| Router EVM (Terra→EVM) | `router.list_routes` (CosmWasm) | domain EVM → bytes32 do Warp EVM |

> If the Terra Router verification shows `0x000...`, run `enroll-terra-router.sh` manually.

---

## 8. Manual IGP deploy via Remix

When Foundry is not installed, the script stops at Step 3 with instructions. Follow:

**1.** Abra [remix.ethereum.org](https://remix.ethereum.org)

**2.** Crie `TerraClassicIGP.sol` e cole o conteúdo de `TerraClassicIGPStandalone-Sepolia.sol`

**3.** Compile:
- Versão: `0.8.13` ou superior
- Optimization: `ON` — 200 runs

**4.** Na aba **Deploy & Run**:
- Environment: `Injected Provider - MetaMask`
- Rede: a rede desejada
- Contrato: `TerraClassicIGPStandalone`

**5.** Parâmetros do constructor (exemplo Sepolia):

| Campo | Valor |
|---|---|
| `_GASORACLE` | `0x7113Df4d1D8B230e6339011d10277a6E5AC4eC9c` |
| `_GASOVERHEAD` | `200000` |
| `_BENEFICIARY` | Seu endereço (owner) |

**6.** Clique em **Deploy** e confirme na MetaMask.

**7.** Copie o endereço e retome o script:

```bash
export IGP_ADDRESS="0xENDERECO_DO_REMIX"
export WARP_ADDRESS="0xENDERECO_WARP_ANTERIOR"  # se já deployado
export ETH_PRIVATE_KEY="0xSUA_CHAVE"
./create-warp-evm.sh
```

---

## 9. Warp deploy on Terra Classic (manual)

To deploy manually (without `TERRA_PRIVATE_KEY`):

### CW20 Token

```bash
# 1. Create the configuration file (already exists in warp/)
cat warp/terraclassic-cw20-novotoken.json

# 2. Set private key
export PRIVATE_KEY="SUA_CHAVE_TERRA_HEX"  ← sem prefixo 0x

# 3. Deploy (run from project root)
cd ~/cw-hyperlane
yarn cw-hpl warp create \
  ./warp/terraclassic-cw20-novotoken.json \
  -n terraclassic
```

### Native Token

```bash
cat warp/terraclassic-native-novotoken.json
export PRIVATE_KEY="SUA_CHAVE_TERRA_HEX"
yarn cw-hpl warp create \
  ./warp/terraclassic-native-novotoken.json \
  -n terraclassic
```

**Expected output:**
```
[DEBUG] [contract] deploying hpl_warp_cw20
[INFO]  [contract] deployed hpl_warp_cw20 at terra1ENDERECODEPLOY...
```

After deploy, the address is automatically saved in `context/terraclassic.json`.

---

## 10. Updating the JSON after deploy

### After Warp deploy on Terra Classic

Open `warp-evm-config.json` and fill in the token section:

```json
"novotoken": {
  "terra_warp": {
    "warp_address": "terra1ENDERECORETORNADO...",
    "warp_hexed":   "0xHEXCONVERTIDO...",
    "deployed":     true
  }
}
```

**Converting bech32 → hex manually:**

```bash
python3 - "terra1ENDERECO..." <<'EOF'
import sys
addr = sys.argv[1]
CHARSET = 'qpzry9x8gf2tvdw0s3jn54khce6mua7l'
sep = addr.rfind('1')
data_str = addr[sep+1:-6]
vals = [CHARSET.index(c) for c in data_str]
result, acc, bits = [], 0, 0
for v in vals:
    acc = (acc << 5) | v
    bits += 5
    while bits >= 8:
        bits -= 8
        result.append((acc >> bits) & 0xFF)
print('0x' + ''.join(f'{b:02x}' for b in result))
EOF
```

### After Warp and IGP deploy on the EVM network

```json
"warp_tokens": {
  "novotoken": {
    "deployed":         true,
    "address":          "0xENDERECO_WARP_EVM",
    "igp_custom":       "0xENDERECO_IGP_EVM",
    "hook_aggregation": "0xENDERECO_AGG_HOOK",
    "owner":            "0xSEU_ENDERECO"
  }
}
```

---

## 11. Helper scripts

The `terraclassic/` folder contains support scripts for specific operations — useful for manual corrections and post-deploy use.

---

### `enroll-terra-router.sh` — Link EVM route in Terra Classic Warp

Calls `router.set_route` on the **Terra Classic** Warp contract to register an EVM Warp as an authorized router.

**When to use:**
- Deploy was done without `TERRA_PRIVATE_KEY` (Step 7B skipped)
- `transfer_remote` fails with `route not found`
- Need to re-register the route after replacing the EVM contract

```bash
cd ~/cw-hyperlane/terraclassic
export TERRA_PRIVATE_KEY="sua_chave_terra_hex"
./enroll-terra-router.sh
```

The script presents interactive menus to select token and network, shows the operation summary, and asks for confirmation before sending.

> 📄 Documentação completa: [`docs/enroll-terra-router-guide.md`](./enroll-terra-router-guide.md)

---

### `transfer-cw20-terra.sh` — Transfer CW20 tokens on Terra Classic

Performs a simple CW20 token transfer between accounts on Terra Classic.

**Default settings** (overridable via env vars):

| Variável | Padrão |
|---|---|
| `CW20_CONTRACT_ADDRESS` | `terra1zle6pwm9...` (XPTO) |
| `SENDER_ADDRESS` | `terra12awgqgwm2...` |
| `RECIPIENT_ADDRESS` | `terra18lr7ujd9n...` |
| `AMOUNT` | `100000000000` |

```bash
cd ~/cw-hyperlane/terraclassic
export TERRA_PRIVATE_KEY="sua_chave_terra_hex"

# Default transfer (100 XPTO)
./transfer-cw20-terra.sh

# Or with custom values
export AMOUNT="50000000000"
export RECIPIENT_ADDRESS="terra1OUTRO..."
./transfer-cw20-terra.sh
```

The script displays balances before and after, saves report in `log/TRANSFER-CW20-<timestamp>.txt`.

---

## 12. Using in another project (portability)

The `terraclassic/` folder is designed to be **100% portable**. The script automatically detects the project root (where `package.json` is) by traversing parent directories.

### Copy to a new project

```bash
# Copy the entire folder
cp -r terraclassic/ /caminho/do/novo-projeto/terraclassic/

# Enter the folder
cd /caminho/do/novo-projeto/terraclassic/

# Run
export ETH_PRIVATE_KEY="0xSUA_CHAVE"
export TERRA_PRIVATE_KEY="SUA_CHAVE_TERRA"
./create-warp-evm.sh
```

### What the script handles automatically

| Situation | What happens |
|---|---|
| `package.json` is in the parent directory | `PROJECT_ROOT` is set as the parent |
| `config.yaml` is in `terraclassic/` but `yarn cw-hpl` needs it at root | The script automatically copies it before running |
| `context/terraclassic.json` is written by `cw-hpl` at root | The script reads from `PROJECT_ROOT/context/` |

### Single requirement

The target project must be a `cw-hyperlane` with `yarn build` already executed (i.e., `dist/index.js` must exist). Verify:

```bash
ls /caminho/do/novo-projeto/dist/index.js   # must exist
```

If it does not exist:
```bash
cd /caminho/do/novo-projeto
yarn install && yarn build
```

---

## 13. Troubleshooting

### ❌ `ZodError: "received": "tron", "code": "invalid_enum_value"`

**Cause:** Hyperlane CLI below version 26 does not recognize the `tron` protocol.  
**Fix:** The script updates automatically. To force manually:

```bash
npm install -g @hyperlane-xyz/cli@latest
hyperlane --version   # deve mostrar 26.x ou superior
```

---

### ❌ `"String must contain at least 1 character"` ao executar `hyperlane warp deploy`

**Cause:** `ETH_PRIVATE_KEY` is not set or is empty.  
**Fix:**

```bash
export ETH_PRIVATE_KEY="0xSUA_CHAVE_COMPLETA_COM_0x"
./create-warp-evm.sh
```

---

### ❌ `"Warning: Dry run enabled, not broadcasting transaction"` (Forge v1.5+)

**Cause:** Foundry v1.5 started using dry-run by default in `forge create`.  
**Fix:** The script already uses `cast send --create` with compiled bytecode. If this occurs with older script versions, update the script or use Remix (Section 8).

---

### ❌ `TimeoutError2` + `account sequence mismatch, expected N, got N-1`

**Cause:** The Terra Classic RPC is days behind. The TX was sent to an outdated node and the CLI timed out waiting for confirmation.

**Diagnosis:**
```bash
# Compare RPC block heights
curl -s "https://rpc.luncblaze.com/status" | jq '.result.sync_info.latest_block_height'
curl -s "https://rpc.terra-classic.hexxagon.dev/status" | jq '.result.sync_info.latest_block_height'
```

**Fix:** Always use `hexxagon` in `config.yaml`:

```yaml
endpoint:
   rpc:  'https://rpc.terra-classic.hexxagon.dev'
   rest: 'https://lcd.terra-classic.hexxagon.dev'
   grpc: 'https://grpc.terra-classic.hexxagon.dev'
```

---

### ❌ `"Failed to estimate gas: execution reverted"` ao chamar `setRemoteGasData`

**Cause:** `setRemoteGasData` is being called on the IGP contract instead of the **Gas Oracle**.  
**Fix:** Use the `igp.gas_oracle` address from the JSON, **not** `igp_custom`:

```bash
cast send $GAS_ORACLE \
  "setRemoteGasData(uint32,uint128,uint128)" \
  1325 142244393 38325000000 \
  --rpc-url $RPC --private-key $ETH_PRIVATE_KEY --legacy
```

---

### ❌ Mensagem enviada (Sepolia → Terra Classic) mas não chega — validator não assina

**Cause:** The EVM Warp hook does not include the `MerkleTreeHook`. Without it, the message **never enters the
merkle tree** of the Mailbox and the validator never sees it to sign the checkpoint.

This happens when the Warp uses the custom `IGP` directly as a hook, without the `AggregationHook`.

**Diagnosis:**
```bash
RPC="https://ethereum-sepolia-rpc.publicnode.com"
WARP="0xbF43aA4878f5Ad0fcAC12Cd3A835DD3506981048"
MERKLE="0x4917a9746A7B6E0A57159cCb7F5a6744247f2d0d"

# 1. Check the current Warp hook
cast call $WARP "hook()(address)" --rpc-url $RPC

# 2. Check merkle tree size — should grow with each dispatch
cast call $MERKLE "count()(uint32)" --rpc-url $RPC

# 3. Check the last checkpoint signed by the validator on S3
curl -s "https://BUCKET.s3.REGION.amazonaws.com/checkpoint_latest_index.json"
# If index is less than message nonce → validator has not signed yet
```

**Fix:** Update the hook to an `AggregationHook = [MerkleTreeHook + IGP]`:

```bash
AGG_FACTORY="0x160C28C92cA453570aD7C031972b58d5Dd128F72"
MERKLE="0x4917a9746A7B6E0A57159cCb7F5a6744247f2d0d"
IGP_CUSTOM="0xSEU_IGP_CUSTOM"

# Deploy AggregationHook
cast send $AGG_FACTORY \
  "deploy(address[])" "[$MERKLE,$IGP_CUSTOM]" \
  --rpc-url $RPC --private-key $ETH_PRIVATE_KEY --legacy

# Get the address
AGG_HOOK=$(cast call $AGG_FACTORY \
  "deploy(address[])(address)" "[$MERKLE,$IGP_CUSTOM]" \
  --rpc-url $RPC)

# Set on Warp
cast send $WARP "setHook(address)" $AGG_HOOK \
  --rpc-url $RPC --private-key $ETH_PRIVATE_KEY --legacy
```

> The `create-warp-evm.sh` already implements this logic automatically in Step 5.
> For already deployed Warps, just re-run the script with `WARP_ADDRESS` and `IGP_ADDRESS` set.

---

### ❌ `"destination not supported"` ao transferir

**Cause:** The Warp hook does not include an IGP with `hookType=4` (INTERCHAIN_GAS_PAYMASTER), or the
`AggregationHook` is incorrect.

**Diagnosis and fix:**

```bash
# Check current hook (should be the AggregationHook)
cast call $WARP_ADDRESS "hook()(address)" --rpc-url $RPC

# Check custom IGP hookType (must be 4)
cast call $IGP_CUSTOM "hookType()(uint8)" --rpc-url $RPC

# Check merkle tree count (should grow with each dispatch)
cast call $MERKLE_TREE "count()(uint32)" --rpc-url $RPC

# If hook is not the correct AggregationHook, reconfigure (see previous section)
```

---

### ❌ `"insufficient funds"` no enrollRemoteRouter

**Causa:** A carteira sendo usada não tem saldo **ou** não é o owner do Warp.  
**Diagnosis:**

```bash
# Check contract owner
cast call $WARP_ADDRESS "owner()(address)" --rpc-url $RPC

# Check balance
cast balance SEU_ENDERECO --rpc-url $RPC | xargs cast to-unit ether
```

The `enrollRemoteRouter` must be called by the **owner** of the Warp Route. Use `ETH_PRIVATE_KEY` from the owner wallet.

---

### ❌ `"jq: command not found"`

```bash
sudo apt-get install -y jq        # Ubuntu/Debian
brew install jq                   # macOS
```

---

### ❌ `"RPC indisponível"`

The script automatically tries the alternative RPC. To force a specific RPC, edit `rpc_urls` in `warp-evm-config.json`:

```json
"rpc_urls": [
  "https://seu-rpc-preferido.com",
  "https://rpc-alternativo.com"
]
```

---

### ⚠️ `exchange_rate` desatualizado (transferência muito cara ou muito barata)

Recalculate and update `warp-evm-config.json`:

```
exchange_rate = (PRECO_ETH_USD / PRECO_LUNC_USD) × 0,01

Exemplo com ETH = $2.000 e LUNC = $0,00005:
  (2000 / 0,00005) × 0,01 = 80.000.000
```

Update in `igp.terra_classic_config.exchange_rate` and re-run Step 4 (Gas Oracle).

---

### ❌ `"route not found"` ao chamar `transfer_remote` na Terra Classic

**Cause:** The Terra Classic Warp contract does not have a route for the destination EVM domain.
Step 7B (`set_route`) was skipped or failed during deploy.

**Diagnosis:**
```bash
# Check routes registered on the Terra Classic Warp
node -e "
const p=require('path'), nm=p.join('/home/lunc/cw-hyperlane','node_modules');
const {CosmWasmClient}=require(p.join(nm,'@cosmjs/cosmwasm-stargate'));
(async()=>{
  const c=await CosmWasmClient.connect('https://rpc.terra-classic.hexxagon.dev');
  const r=await c.queryContractSmart('SEU_WARP_TERRA', {router:{list_routes:{}}});
  console.log(JSON.stringify(r, null, 2));
})();"
```

**Fix:** Run the correction script:
```bash
export TERRA_PRIVATE_KEY="sua_chave_terra_hex"
./enroll-terra-router.sh
```

---

### ❌ Message ID não aparece nos eventos do Mailbox de destino

**Cause:** The message was dispatched at the origin but the **relayer** has not yet delivered it to the destination chain.  
The Hyperlane delivery process has 3 independent steps:

```
1. Origem:   Mailbox.dispatch() → gera message_id
2. Validador: assina o checkpoint e salva no S3/GCS
3. Relayer:  lê as assinaturas e chama Mailbox.process() no destino
```

**Full diagnosis:**
```bash
RPC="https://ethereum-sepolia-rpc.publicnode.com"
MAILBOX="0xfFAEF09B3cd11D9b20d1a19bECca54EEC2884766"
MSG_ID="0xSEU_MESSAGE_ID"

# 1. Was the message delivered?
cast call $MAILBOX "delivered(bytes32)(bool)" $MSG_ID --rpc-url $RPC

# 2. Is the EVM Router configured? (must be != 0x000...)
cast call $SEU_WARP_EVM "routers(uint32)(bytes32)" 1325 --rpc-url $RPC

# 3. Check in Hyperlane Explorer:
# https://explorer.hyperlane.xyz/message/$MSG_ID
```

**Common causes and fixes:**

| Cause | Diagnosis | Fix |
|---|---|---|
| `enrollRemoteRouter(1325)` missing on EVM Warp | `routers(1325)` returns `0x000...` | `cast send $WARP "enrollRemoteRouter(uint32,bytes32)" 1325 0xHEX_TERRA --private-key $ETH_KEY --legacy` |
| Validator not signing | Latest S3 checkpoint is old | Restart the Hyperlane validator |
| Relayer not running | No `process()` attempts | Start the relayer with `hyperlane relayer --chains sepolia` |
| Wrong bytes32 in `enrollRemoteRouter` | `routers(1325)` ≠ Warp Terra hex | Re-run `enrollRemoteRouter` with the correct 32-byte hex |

> 💡 **Check the validator:** The validator should have a recent `checkpoint_latest_index.json` in its storage (S3/GCS).
> If the index stopped advancing, the validator is not running.

---

### ❌ `enrollRemoteRouter` falha ou registra bytes32 errado (endereço EVM no lugar do Terra)

**Cause:** The `to_bytes32` function in the script had a bug: it added 24 zero padding bytes
(`000000000000000000000000`) before the hash, correct for EVM addresses (20 bytes / 40 hex chars)
but **wrong** for CosmWasm hashes (32 bytes / 64 hex chars).

**Example of the problem:**
```
# Terra Classic Warp hex (correct = 64 chars):
d03fafd53ce350f49ba3c6ebcb1bee7cbbf453f261ec8d5ce9f36c55ab3e26a1

# Wrong result (88 chars, cast rejects):
000000000000000000000000d03fafd53ce350f49ba3c6ebcb1bee7cbbf453f261ec8d5ce9f36c55ab3e26a1
```

**Verification:**
```bash
cast call $WARP_EVM "routers(uint32)(bytes32)" 1325 --rpc-url $RPC
# If it returns 0x000...000 or a value with 24 extra leading zeros: re-run
```

**Manual fix:**
```bash
# Get the correct hex from warp-evm-config.json:
HEX=$(jq -r '.terra_classic.tokens.xpto.terra_warp.warp_hexed' warp-evm-config.json)
HEX="${HEX#0x}"  # remove 0x

# Check length (must be 64):
echo ${#HEX}

# Run com o hex correto:
cast send $WARP_EVM \
  "enrollRemoteRouter(uint32,bytes32)" \
  1325 "0x${HEX}" \
  --rpc-url $RPC --private-key $ETH_PRIVATE_KEY --legacy
```

> The script `create-warp-evm.sh` is fixed in the current version (uses `printf '%064s' ... | tr ' ' '0'`).

---

## 🔗 Useful links

| Recurso | URL |
|---|---|
| Hyperlane Docs | [docs.hyperlane.xyz](https://docs.hyperlane.xyz/) |
| Hyperlane Explorer | [explorer.hyperlane.xyz](https://explorer.hyperlane.xyz) |
| Hyperlane Registry (GitHub) | [github.com/hyperlane-xyz/hyperlane-registry](https://github.com/hyperlane-xyz/hyperlane-registry) |
| Foundry (forge/cast) | [book.getfoundry.sh](https://book.getfoundry.sh/) |
| Remix IDE | [remix.ethereum.org](https://remix.ethereum.org) |
| Sepolia Etherscan | [sepolia.etherscan.io](https://sepolia.etherscan.io) |
| BSC Testnet Explorer | [testnet.bscscan.com](https://testnet.bscscan.com) |
| Terra Classic Finder (Hexxagon) | [finder.hexxagon.io/rebel-2](https://finder.hexxagon.io/rebel-2) |
| Terra Classic RPC (Hexxagon) | [rpc.terra-classic.hexxagon.dev](https://rpc.terra-classic.hexxagon.dev/status) |
| Faucet Sepolia | [sepoliafaucet.com](https://sepoliafaucet.com) |
| Faucet BSC Testnet | [www.bnbchain.org/en/testnet-faucet](https://www.bnbchain.org/en/testnet-faucet) |

---

## 14. Manual AggregationHook fix (without the script)

This section shows how to fix the hook of an already deployed Warp Route **manually via `cast`**, without needing to re-run the full script. Use when **EVM → Terra Classic** messages do not arrive and diagnosis shows the hook is configured directly with the `IGP` (without the `MerkleTreeHook`).

### Quick diagnosis

```bash
# Check the current Warp hook (should be AggregationHook, not IGP)
cast call $WARP_ADDRESS "hook()(address)" --rpc-url $RPC

# Check the owner (only the owner can call setHook)
cast call $WARP_ADDRESS "owner()(address)" --rpc-url $RPC
```

If the returned `hook` equals your custom `IGP` address → the problem is confirmed.

---

### Sepolia — Fix hook manually

```bash
export ETH_PRIVATE_KEY="0xSUA_CHAVE_PRIVADA"
RPC="https://ethereum-sepolia-rpc.publicnode.com"

# Endereços Sepolia
AGG_FACTORY="0x160C28C92cA453570aD7C031972b58d5Dd128F72"  # StaticAggregationHookFactory
MERKLE="0x4917a9746A7B6E0A57159cCb7F5a6744247f2d0d"        # MerkleTreeHook oficial
IGP_CUSTOM="0xSEU_IGP_CUSTOM"                              # seu IGP deployado
WARP_ADDRESS="0xSEU_WARP"

# Step 1 — Get deterministic AggHook address
AGG_HOOK=$(cast call $AGG_FACTORY \
  "deploy(address[])(address)" "[$MERKLE,$IGP_CUSTOM]" \
  --rpc-url $RPC)
echo "AggHook será: $AGG_HOOK"

# Step 2 — Deploy AggregationHook
cast send $AGG_FACTORY \
  "deploy(address[])" "[$MERKLE,$IGP_CUSTOM]" \
  --rpc-url $RPC --private-key $ETH_PRIVATE_KEY --legacy

# Step 3 — Set AggregationHook on Warp
cast send $WARP_ADDRESS "setHook(address)" $AGG_HOOK \
  --rpc-url $RPC --private-key $ETH_PRIVATE_KEY --legacy

# Final verification
cast call $WARP_ADDRESS "hook()(address)" --rpc-url $RPC
```

> **Endereços reais do XPTO Sepolia** (para referência):
> - `AGG_FACTORY` = `0x160C28C92cA453570aD7C031972b58d5Dd128F72`
> - `MERKLE` = `0x4917a9746A7B6E0A57159cCb7F5a6744247f2d0d`
> - `IGP_CUSTOM` = `0xf285D5769db5AE6E79Bb3179d03082f6bc47055f`
> - `AGG_HOOK` resultante = `0x1a13d7A50b76d4527a611e507B3f73058eCa5eAC`

---

### BSC Testnet — Fix hook manually

```bash
export ETH_PRIVATE_KEY="0xSUA_CHAVE_PRIVADA"
RPC="https://bsc-testnet.publicnode.com"

# Endereços BSC Testnet
AGG_FACTORY="0xa1145B39F1c7Ef9aA593BC1DB1634b00CC020942"  # StaticAggregationHookFactory ✅
MERKLE="0xc6cbF39A747f5E28d1bDc8D9dfDAb2960Abd5A8f"        # MerkleTreeHook oficial
IGP_CUSTOM="0xSEU_IGP_CUSTOM"                              # seu IGP deployado
WARP_ADDRESS="0xSEU_WARP"

# Step 1 — Get deterministic AggHook address
AGG_HOOK=$(cast call $AGG_FACTORY \
  "deploy(address[])(address)" "[$MERKLE,$IGP_CUSTOM]" \
  --rpc-url $RPC)
echo "AggHook será: $AGG_HOOK"

# Step 2 — Deploy AggregationHook
cast send $AGG_FACTORY \
  "deploy(address[])" "[$MERKLE,$IGP_CUSTOM]" \
  --rpc-url $RPC --private-key $ETH_PRIVATE_KEY --legacy

# Step 3 — Set AggregationHook on Warp
cast send $WARP_ADDRESS "setHook(address)" $AGG_HOOK \
  --rpc-url $RPC --private-key $ETH_PRIVATE_KEY --legacy

# Final verification
cast call $WARP_ADDRESS "hook()(address)" --rpc-url $RPC
```

> **Endereços reais do XPV BSC Testnet** (para referência):
> - `AGG_FACTORY` = `0xa1145B39F1c7Ef9aA593BC1DB1634b00CC020942`
> - `MERKLE` = `0xc6cbF39A747f5E28d1bDc8D9dfDAb2960Abd5A8f`
> - `IGP_CUSTOM` = `0x7d17d237c74Fa1bA3B5B56d94E414a4eAa41cE1e`
> - `AGG_HOOK` resultante = `0x3F11a590B50F959E52a660567865f1B65C913C5D`

> ⚠️ **Atenção:** A factory para BSC Testnet é `0xa1145B39F...`, **não** `0x0a71AcC99...` (esta última não tem código e resultará em erro silencioso). Sempre confirme o endereço da factory via registry antes de usar (veja [Seção 16](#16-como-encontrar-endereços-hyperlane-de-qualquer-rede)).

---

### Re-run the script for an already deployed Warp (simpler alternative)

If you prefer to use the script instead of manual commands, just set the already deployed addresses and re-run — the script skips completed steps and only executes what remains (like the AggHook deploy):

```bash
cd ~/cw-hyperlane/terraclassic
export ETH_PRIVATE_KEY="0xSUA_CHAVE"
export TERRA_PRIVATE_KEY="SUA_CHAVE_TERRA"

# Previous state is automatically read from .warp-evm-state.json
# If not present, set manually:
export WARP_ADDRESS="0xSEU_WARP"
export IGP_ADDRESS="0xSEU_IGP"

./create-warp-evm.sh
# Select the token and network — the script will skip Warp and IGP deploy
# and go directly to AggHook deploy (Step 5)
```

---

## 15. Deployed address reference

Addresses of all active contracts in this project, for quick reference and manual diagnosis.

### Sepolia (chain 11155111 / domain 11155111)

| Contract | Address | Explorer |
|---|---|---|
| **Mailbox** | `0xfFAEF09B3cd11D9b20d1a19bECca54EEC2884766` | [🔗](https://sepolia.etherscan.io/address/0xfFAEF09B3cd11D9b20d1a19bECca54EEC2884766) |
| **MerkleTreeHook** | `0x4917a9746A7B6E0A57159cCb7F5a6744247f2d0d` | [🔗](https://sepolia.etherscan.io/address/0x4917a9746A7B6E0A57159cCb7F5a6744247f2d0d) |
| **AggHook Factory** | `0x160C28C92cA453570aD7C031972b58d5Dd128F72` | [🔗](https://sepolia.etherscan.io/address/0x160C28C92cA453570aD7C031972b58d5Dd128F72) |
| **Gas Oracle** | `0x7113Df4d1D8B230e6339011d10277a6E5AC4eC9c` | [🔗](https://sepolia.etherscan.io/address/0x7113Df4d1D8B230e6339011d10277a6E5AC4eC9c) |
| **ISM Factory** | `0xFEb9585b2f948c1eD74034205a7439261a9d27DD` | [🔗](https://sepolia.etherscan.io/address/0xFEb9585b2f948c1eD74034205a7439261a9d27DD) |
| **Validator Announce** | `0xE6105C59480a1B8CF6db0D655571767f4b31Ef3C` | [🔗](https://sepolia.etherscan.io/address/0xE6105C59480a1B8CF6db0D655571767f4b31Ef3C) |

#### Sepolia Warps

| Token | EVM Warp | Custom IGP | AggHook | ISM |
|---|---|---|---|---|
| **XPTO** | [`0xbF43aA...`](https://sepolia.etherscan.io/address/0xbF43aA4878f5Ad0fcAC12Cd3A835DD3506981048) | [`0xf285D5...`](https://sepolia.etherscan.io/address/0xf285D5769db5AE6E79Bb3179d03082f6bc47055f) | [`0x1a13d7...`](https://sepolia.etherscan.io/address/0x1a13d7A50b76d4527a611e507B3f73058eCa5eAC) | — |
| **XPTV** | [`0x7d92c2...`](https://sepolia.etherscan.io/address/0x7d92c2E01933F1C651845152DBd4222d475Bd9f0) | `0xf285D5...` (mesmo XPTO) | `0x1a13d7...` (mesmo XPTO) | — |

#### Sepolia Validator (S3)

| Item | Value |
|---|---|
| Address | `0x133fD7F7094DBd17b576907d052a5aCBd48dB526` |
| Mailbox domain | `11155111` |
| S3 Bucket | [hyperlane-validator-signatures-igorveras-sepolia](https://hyperlane-validator-signatures-igorveras-sepolia.s3.us-east-1.amazonaws.com/) |
| Announcement | [announcement.json](https://hyperlane-validator-signatures-igorveras-sepolia.s3.us-east-1.amazonaws.com/announcement.json) |
| Latest checkpoint | [checkpoint_latest_index.json](https://hyperlane-validator-signatures-igorveras-sepolia.s3.us-east-1.amazonaws.com/checkpoint_latest_index.json) |

---

### BSC Testnet (chain 97 / domain 97)

| Contract | Address | Explorer |
|---|---|---|
| **Mailbox** | `0xF9F6F5646F478d5ab4e20B0F910C92F1CCC9Cc6D` | [🔗](https://testnet.bscscan.com/address/0xF9F6F5646F478d5ab4e20B0F910C92F1CCC9Cc6D) |
| **MerkleTreeHook** | `0xc6cbF39A747f5E28d1bDc8D9dfDAb2960Abd5A8f` | [🔗](https://testnet.bscscan.com/address/0xc6cbF39A747f5E28d1bDc8D9dfDAb2960Abd5A8f) |
| **AggHook Factory** ✅ | `0xa1145B39F1c7Ef9aA593BC1DB1634b00CC020942` | [🔗](https://testnet.bscscan.com/address/0xa1145B39F1c7Ef9aA593BC1DB1634b00CC020942) |
| **Gas Oracle** | `0x124EBCBC018A5D4Efe639f02ED86f95cdC3f6498` | [🔗](https://testnet.bscscan.com/address/0x124EBCBC018A5D4Efe639f02ED86f95cdC3f6498) |
| **ISM Factory** | `0x0D96aF0c01c4bbbadaaF989Eb489c8783F35B763` | [🔗](https://testnet.bscscan.com/address/0x0D96aF0c01c4bbbadaaF989Eb489c8783F35B763) |
| **Validator Announce** | `0xf09701B0a93210113D175461b6135a96773B5465` | [🔗](https://testnet.bscscan.com/address/0xf09701B0a93210113D175461b6135a96773B5465) |

#### BSC Testnet Warps

| Token | EVM Warp | Custom IGP | AggHook | ISM |
|---|---|---|---|---|
| **XPV** | [`0x11D6aa...`](https://testnet.bscscan.com/address/0x11D6aa52d60611a513ab783842Dc397C86E7fff0) | [`0x7d17d2...`](https://testnet.bscscan.com/address/0x7d17d237c74Fa1bA3B5B56d94E414a4eAa41cE1e) | [`0x3F11a5...`](https://testnet.bscscan.com/address/0x3F11a590B50F959E52a660567865f1B65C913C5D) | [`0x2b31a0...`](https://testnet.bscscan.com/address/0x2b31a08d397b7e508cbE0F5830E8a9182C88b6cA) |

#### BSC Testnet Validator (S3)

| Item | Value |
|---|---|
| Endereço | `0x8BD456605473ad4727ACfDCA0040a0dBD4be2DEA` |
| Mailbox domain | `97` |
| S3 Bucket | [hyperlane-validator-signatures-igorveras-bsctestnet](https://hyperlane-validator-signatures-igorveras-bsctestnet.s3.us-east-1.amazonaws.com/) |
| Announcement | [announcement.json](https://hyperlane-validator-signatures-igorveras-bsctestnet.s3.us-east-1.amazonaws.com/announcement.json) |
| Latest checkpoint | [checkpoint_latest_index.json](https://hyperlane-validator-signatures-igorveras-bsctestnet.s3.us-east-1.amazonaws.com/checkpoint_latest_index.json) |

---

### Terra Classic (chain rebel-2 / domain 1325)

| Item | Value |
|---|---|
| RPC | `https://rpc.terra-classic.hexxagon.dev` |
| LCD | `https://lcd.terra-classic.hexxagon.dev` |
| Explorer | [finder.hexxagon.io/rebel-2](https://finder.hexxagon.io/rebel-2) |

#### Terra Classic Warps

| Token | Terra Classic Warp | Hex bytes32 | CW20 Collateral |
|---|---|---|---|
| **XPTO** | [`terra16ql6l4...`](https://finder.hexxagon.io/rebel-2/address/terra16ql6l4fuudg0fxarcm4ukxlw0jalg5ljv8kg6h8f7dk9t2e7y6ssq2hqrm) | `0xd03fafd5...e26a1` | `terra1zle6pw...` |
| **XPTV** | [`terra1n8y4s...`](https://finder.hexxagon.io/rebel-2/address/terra1n8y4sj9lrqq66pf7je0nm7s6nhln5z4s3accw9g2aassdh8dzqts9y0928) | `0x99c95848...d1017` | `terra19ujvy...` |
| **XPV** | [`terra1dnflu...`](https://finder.hexxagon.io/rebel-2/address/terra1dnflusc7slapvals97em3fj4vrfyx90npr3znq6y45qjy7hhd6jqchqsgx) | `0x6cd3fe43...6ea4` | `terra1f2jw3...` |
| **wLUNC** | [`terra1zlm0h...`](https://finder.hexxagon.io/rebel-2/address/terra1zlm0h2xu6rhnjchn29hxnpvr74uxxqetar9y75zcehyx2mqezg9slj09ml) | `0x17f6fba8...120b` | `uluna` (native) |

---

### Quick verifications via cast

```bash
# Check hook of any Warp (should be AggHook, not IGP)
cast call $WARP "hook()(address)" --rpc-url $RPC

# Check owner of any contract
cast call $WARP "owner()(address)" --rpc-url $RPC

# Check Terra Classic router configured on EVM Warp
cast call $WARP "routers(uint32)(bytes32)" 1325 --rpc-url $RPC

# Check BSC Testnet router configured on EVM Warp
cast call $WARP "routers(uint32)(bytes32)" 97 --rpc-url $RPC

# Check Warp ISM
cast call $WARP "interchainSecurityModule()(address)" --rpc-url $RPC

# Check balance de uma carteira
cast balance $ENDERECO --rpc-url $RPC --ether

# Check latest validator checkpoint on S3
curl -s "https://SEU-BUCKET.s3.REGIAO.amazonaws.com/checkpoint_latest_index.json"
```

---

## 16. How to find Hyperlane addresses for any network

When configuring a new EVM network (mainnet or testnet), official Hyperlane contract addresses are available from two main sources.

### Source 1 — Hyperlane Registry (npm)

The `@hyperlane-xyz/registry` package contains all official addresses per network:

```bash
# Install (already in project as dependency)
npm install @hyperlane-xyz/registry

# Query addresses for a specific network
node -e "
const addresses = require('@hyperlane-xyz/registry/dist/chains/bsctestnet/addresses.json');
console.log(JSON.stringify(addresses, null, 2));
"

# Or via direct file in node_modules
cat node_modules/@hyperlane-xyz/registry/dist/chains/bsctestnet/addresses.json
cat node_modules/@hyperlane-xyz/registry/dist/chains/sepolia/addresses.json
```

**Important fields you need for `warp-evm-config.json`:**

| JSON field | Registry key |
|---|---|
| `mailbox.address` | `mailbox` |
| `hook.merkle_tree` | `merkleTreeHook` |
| `hook.agg_hook_factory` | `staticAggregationHookFactory` |
| `igp.official_address` | `interchainGasPaymaster` |
| `igp.gas_oracle` | `storageGasOracle` |
| `ism.factory` | `staticMessageIdMultisigIsmFactory` |

### Source 2 — GitHub Hyperlane Registry

Access directly via GitHub:

```
https://github.com/hyperlane-xyz/hyperlane-registry/tree/main/chains/<NOME_DA_REDE>
```

Example for BSC Testnet:
- Endereços: [chains/bsctestnet/addresses.yaml](https://github.com/hyperlane-xyz/hyperlane-registry/blob/main/chains/bsctestnet/addresses.yaml)
- Metadados: [chains/bsctestnet/metadata.yaml](https://github.com/hyperlane-xyz/hyperlane-registry/blob/main/chains/bsctestnet/metadata.yaml)

Example for Sepolia:
- Endereços: [chains/sepolia/addresses.yaml](https://github.com/hyperlane-xyz/hyperlane-registry/blob/main/chains/sepolia/addresses.yaml)

### Source 3 — Hyperlane CLI

```bash
# List all supported networks
hyperlane config show --chains

# View contracts of a specific network
hyperlane config show --chains sepolia
```

### Verify if an address has code (deployed contract)

Before using any factory address or Hyperlane contract, **always confirm** it has code:

```bash
# If it returns "0x" → no code, wrong address or wrong network
cast code $ENDERECO --rpc-url $RPC

# Verify multiple addresses at once
for ADDR in 0xADDR1 0xADDR2 0xADDR3; do
    CODE=$(cast code $ADDR --rpc-url $RPC 2>/dev/null | wc -c)
    [ $CODE -gt 5 ] && echo "✅ $ADDR" || echo "❌ $ADDR (sem código)"
done
```

### Finding the domain ID of a network

The Hyperlane domain ID is usually equal to the network `chainId`. Confirm via:

```bash
# Query in the registry
node -e "
const meta = require('@hyperlane-xyz/registry/dist/chains/bsctestnet/metadata.json');
console.log('chainId:', meta.chainId, '| domainId:', meta.domainId || meta.chainId);
"
```

| Network | chainId | Hyperlane domain |
|---|---|---|
| Ethereum | 1 | 1 |
| Sepolia | 11155111 | 11155111 |
| BSC | 56 | 56 |
| BSC Testnet | 97 | 97 |
| Polygon | 137 | 137 |
| Arbitrum | 42161 | 42161 |
| Optimism | 10 | 10 |
| **Terra Classic** | rebel-2 | **1325** |
