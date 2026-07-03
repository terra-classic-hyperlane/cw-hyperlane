# Warp routes sintéticos — Transferência de posse (Solana / Ethereum / BSC)

Documento dos scripts `transfer-warp-evm.sh` e `transfer-warp-solana.sh`, que
transferem a posse dos **warp routes sintéticos** de LUNC/USTC nas redes externas
para o controle **descentralizado** do projeto.

> ⚠️ **Seguros por padrão:** ambos rodam em **dry-run** (só imprimem os comandos,
> **não executam**). Só executam de verdade com `--execute`.

---

## 0. Modelo de governança e descentralização

Quando os tokens sintéticos de **LUNC** e **USTC** são instalados nas redes
externas (Solana, Ethereum, BSC), os contratos nascem com a conta do
**desenvolvedor** como dona — usada **apenas** para instalação, implantação e
testes. Em produção isso não pode continuar.

Diferentemente dos contratos de infraestrutura no Terra Classic (que vão para a
**governança** da chain — veja [`transfer-ownership.md`](./transfer-ownership.md)),
os warps sintéticos vivem em **outras blockchains**, onde a governança do Terra
Classic **não tem controle direto**. Por isso, a posse desses contratos vai para:

> **Uma conta de múltipla assinatura (multisig) dos validadores que validam o
> Hyperlane.** Esses validadores foram **selecionados pela governança via
> votação**, o que mantém o controle **descentralizado** e alinhado à governança,
> mesmo em redes onde ela não atua diretamente.

Ferramenta de multisig por rede:

| Rede | Multisig | Mecanismo de posse | Passos |
|---|---|---|---|
| **Ethereum** | **SAFE** (Gnosis Safe) | `transferOwnership(address)` (OZ Ownable) | 1 (imediato) |
| **BSC** | **SAFE** (Gnosis Safe) | `transferOwnership(address)` (OZ Ownable) | 1 (imediato) |
| **Solana** | **Squads** | `token transfer-ownership` (client) | 1 (imediato) |

### ⚠️ Diferença crítica em relação ao Terra Classic
No Terra Classic a transferência de owner é em **dois passos** (init + claim),
com rede de segurança. **Na EVM e na Solana é UM passo, imediato e sem claim.**
Assim que a transação confirma, o multisig vira owner e **você perde o controle**.
Não há como reverter sem o multisig. **Confira os endereços de destino com
atenção redobrada.**

### Ciclo de handoff
```
[dev instala/deploya/testa sintéticos]  →  testes OK  →  RODAR OS SCRIPTS  →  multisig dos validadores no controle
```

---

## 1. Pré-requisitos

| Rede | Ferramenta | Instalação |
|---|---|---|
| ETH / BSC | **foundry (`cast`)** | https://book.getfoundry.sh |
| Solana | **hyperlane-sealevel-client** | `cd ~/hyperlane-monorepo/rust/sealevel/client && cargo build --release` |

Você também precisa:
- Endereços dos warps sintéticos já implantados (LUNC, USTC) em cada rede.
- Endereço do **SAFE** (ETH e BSC) e da **vault do Squads** (Solana).
- Acesso de assinatura como **owner atual** (deployer): keystore/ledger (EVM) ou
  keypair (Solana).

---

## 2. EVM — `transfer-warp-evm.sh` (Ethereum e BSC → SAFE)

### 2.1 Configuração (no topo do script)

| Variável | Descrição |
|---|---|
| `DEPLOYER_ADDRESS` | Seu endereço atual de owner (filtro de segurança: só transfere o que é seu) |
| `CAST_AUTH` | Como o `cast` assina (`--account <keystore>`, `--ledger` ou `--private-key`) |
| `ETH_RPC_URL` / `BSC_RPC_URL` | RPC de cada rede |
| `ETH_SAFE_ADDRESS` / `BSC_SAFE_ADDRESS` | Endereço do SAFE multisig em cada rede |
| `ETH_TOKENS` / `BSC_TOKENS` | Lista de endereços `0x...` dos warps sintéticos |

### 2.2 Uso

```bash
# Revisar (dry-run) — não executa:
./transfer-warp-evm.sh --network ethereum
./transfer-warp-evm.sh --network bsc

# Incluir também a autoridade de upgrade (ProxyAdmin):
./transfer-warp-evm.sh --network ethereum --include-proxyadmin

# Executar de verdade:
./transfer-warp-evm.sh --network ethereum --execute
./transfer-warp-evm.sh --network bsc --execute
```

### 2.3 O que ele faz
1. Para cada token, lê `owner()` on-chain. Só age se o owner == `DEPLOYER_ADDRESS`
   (pula o resto com aviso).
2. Emite `transferOwnership(SAFE)`.
3. Com `--include-proxyadmin`: lê o slot EIP-1967 de cada proxy, descobre o
   contrato **ProxyAdmin** (autoridade de upgrade) e transfere o owner dele para o
   SAFE também. ⚠️ Um ProxyAdmin pode controlar vários proxies — faça isso **só
   depois** de confirmar que o SAFE já é owner dos tokens.

### 2.4 owner ≠ ProxyAdmin (na EVM)
- **`owner` do token** → controla configuração (ISM, routers, gas).
- **`ProxyAdmin`** → controla o **upgrade do código** (equivalente ao admin de
  migração no CosmWasm). Para descentralizar de verdade, transfira **os dois** ao
  SAFE (use `--include-proxyadmin`).

### 2.5 Conferir
```bash
cast call <token> "owner()(address)" --rpc-url <RPC>
```

---

## 3. Solana — `transfer-warp-solana.sh` (→ Squads)

### 3.1 Configuração (no topo do script)

| Variável | Descrição |
|---|---|
| `SQUADS_VAULT` | Endereço (base58) da **vault** do Squads que receberá a posse |
| `CLIENT` | Caminho do binário `hyperlane-sealevel-client` |
| `OWNER_KEYPAIR` | Keypair do owner atual (deployer) que assina |
| `RPC_URL` | RPC da Solana mainnet |
| `TOKEN_TYPE` | `synthetic` (padrão para sintéticos) |
| `TOKEN_PROGRAM_IDS` | Program IDs dos warps sintéticos (LUNC, USTC, ...) |

> 🔑 `SQUADS_VAULT` deve ser o endereço da **vault** do Squads (a PDA que age como
> autoridade do multisig), **não** a conta de configuração do multisig.

### 3.2 Uso
```bash
./transfer-warp-solana.sh            # dry-run (mostra query do owner + comando)
./transfer-warp-solana.sh --execute  # executa de verdade
```

### 3.3 O que ele faz
1. Para cada program id: roda `token query` (leitura) para você ver o owner atual.
2. Emite `token transfer-ownership --program-id <PID> <SQUADS_VAULT>`.

### 3.4 Conferir
```bash
hyperlane-sealevel-client --url <RPC> token query --program-id <PID> synthetic
```

---

## 4. Ordem recomendada de execução

> Faça **por último**, com os sintéticos já instalados, configurados e testados.

1. **Confirme os endereços de destino** (SAFE de ETH, SAFE de BSC, vault do
   Squads). Não há claim/reversão — erro aqui é irreversível.
2. **Teste o multisig** antes: faça o SAFE/Squads executar uma transação simples
   para garantir que os validadores conseguem assinar e executar.
3. Rode em **dry-run** e revise a lista de elegíveis em cada rede.
4. Execute a transferência do **owner** dos tokens (`--execute`).
5. Confirme `owner()` / `token query` em cada token.
6. (EVM) Só então transfira o **ProxyAdmin** (`--include-proxyadmin --execute`).

---

## 5. Avisos importantes

1. **Sem claim na EVM/Solana** — a transferência é imediata e irreversível sem o
   multisig. Confira os endereços três vezes.
2. **Teste o multisig antes** — se os validadores não conseguirem assinar/executar
   no SAFE/Squads, o contrato fica sob controle de um multisig inoperante.
3. **owner ≠ upgrade** — transfira também ProxyAdmin (EVM); na Solana, a
   autoridade de upgrade do programa (BPF loader) é separada e deve ser tratada à
   parte se aplicável.
4. **Sempre dry-run primeiro.**
5. **Reserve saldo nativo** para gás (ETH/BNB/SOL) — uma tx por contrato.

---

## 6. Solução de problemas

| Sintoma | Causa provável | O que fazer |
|---|---|---|
| EVM `skip (owner já é ...)` | Já transferido ou `DEPLOYER_ADDRESS` errado | Confira `owner()` e o `DEPLOYER_ADDRESS` |
| EVM `skip (não respondeu owner())` | Endereço errado / não é Ownable | Verifique o endereço do token |
| EVM `Nenhum ProxyAdmin detectado` | Token não está atrás de proxy | Esperado em alguns deploys |
| Solana `client não encontrado` | Binário não compilado | `cargo build --release` em `rust/sealevel/client` |
| Solana erro de assinatura | `OWNER_KEYPAIR` não é o owner atual | Use o keypair do deployer/owner |

---

## 7. Arquivos relacionados

- `transfer-warp-evm.sh` — transfere warps sintéticos EVM (ETH/BSC) ao SAFE.
- `transfer-warp-solana.sh` — transfere warps sintéticos Solana ao Squads.
- [`transfer-ownership.md`](./transfer-ownership.md) — infraestrutura Terra Classic → governança.
- Solidity: `solidity/contracts/client/MailboxClient.sol` (OwnableUpgradeable).
- Solana: `rust/sealevel/libraries/hyperlane-sealevel-token/src/processor.rs` (`transfer_ownership`).
- Client: `rust/sealevel/client/src/main.rs` (`token transfer-ownership`), `client/src/squads.rs`.
