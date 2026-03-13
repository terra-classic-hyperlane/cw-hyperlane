# 📚 Guia de Documentação — Hyperlane Warp Routes Terra Classic

> **Documento índice** — Guia rápido para navegar pela documentação completa de criação e uso de Warp Routes entre Terra Classic ↔ EVM e Terra Classic ↔ Sealevel (Solana).

---

## 🚀 Início Rápido

### 1. Instalação e Setup

```bash
# 1. Clone o repositório
git clone <repository-url>
cd cw-hyperlane-tc

# 2. Instale as dependências Node.js
yarn install

# 3. Configure as chaves privadas (opcional, pode ser feito durante execução)
export TERRA_PRIVATE_KEY="sua_chave_hex_terra"
export ETH_PRIVATE_KEY="0x_sua_chave_hex_evm"
```

**Dependências necessárias:**
- `node` (≥ 16) — `node --version`
- `yarn` ou `npm` — `yarn --version`
- `jq` — `sudo apt install jq`
- `curl` — geralmente já instalado
- `python3` — geralmente já instalado

### 2. Primeiros Passos Recomendados

**Se você está começando do zero:**

1. **Leia este documento** (README.md) para entender a estrutura
2. **Escolha seu primeiro caso de uso:**
   - Terra Classic ↔ EVM (Sepolia/BSC)? → [`create-warp-evm-guide.md`](./create-warp-evm-guide.md)
   - Terra Classic ↔ Solana? → [`create-warp-sealevel-guide.md`](./create-warp-sealevel-guide.md)
3. **Siga o guia escolhido passo a passo**
4. **Teste com transferências** usando os guias de transferência

**Se você já tem Warp Routes criados:**

1. Use [`transfer-remote-guide.md`](./transfer-remote-guide.md) para enviar tokens
2. Use [`transfer-remote-to-terra-guide.md`](./transfer-remote-to-terra-guide.md) para receber tokens
3. Se encontrar erro "route not found", use [`enroll-terra-router-guide.md`](./enroll-terra-router-guide.md)

---

## 📖 Documentos Disponíveis

### 🎯 **Documentos Principais (Fluxo Completo)**

#### 1. [`create-warp-evm-guide.md`](./create-warp-evm-guide.md)
**O que faz:** Guia completo para criar Warp Routes em redes **EVM** (Sepolia, BSC Testnet, etc.) conectadas à Terra Classic.

**Quando usar:**
- Primeira vez criando um Warp Route EVM
- Adicionando um novo token em uma rede EVM
- Adicionando uma nova rede EVM ao projeto

**O que você vai fazer:**
1. Configurar `warp-evm-config.json` e `config.yaml`
2. Executar `./create-warp-evm.sh`
3. Deploy automático de contratos (Mailbox, ISM, IGP, Warp Route)
4. Configuração automática de hooks e rotas bidirecionais

**Tempo estimado:** 15-30 minutos por token/rede

---

#### 2. [`create-warp-sealevel-guide.md`](./create-warp-sealevel-guide.md)
**O que faz:** Guia completo para criar Warp Routes em **Solana (Sealevel)** conectadas à Terra Classic.

**Quando usar:**
- Primeira vez criando um Warp Route Solana
- Adicionando um novo token em Solana
- Migrando para Solana Mainnet

**O que você vai fazer:**
1. Configurar `warp-sealevel-config.json`
2. Preparar metadados do token (JSON)
3. Executar `./create-warp-sealevel.sh`
4. Deploy automático de programas Solana (Warp, ISM, IGP)
5. Configuração de rotas bidirecionais

**Tempo estimado:** 20-40 minutos por token

---

#### 3. [`transfer-remote-guide.md`](./transfer-remote-guide.md)
**O que faz:** Guia completo para enviar tokens de **Terra Classic → EVM/Sealevel**.

**Quando usar:**
- Enviar tokens de Terra Classic para Sepolia, BSC Testnet ou Solana
- Testar transferências após criar Warp Routes
- Verificar se tudo está configurado corretamente

**O que você vai fazer:**
1. Configurar `TERRA_PRIVATE_KEY`
2. Executar `./transfer-remote-terra.sh`
3. Escolher token e rede destino (interativo ou via variáveis)
4. Inserir endereço do destinatário e valor
5. Confirmar e enviar

**Tempo estimado:** 2-5 minutos por transferência

---

#### 4. [`transfer-remote-to-terra-guide.md`](./transfer-remote-to-terra-guide.md)
**O que faz:** Guia completo para enviar tokens de **EVM/Sealevel → Terra Classic**.

**Quando usar:**
- Enviar tokens de Sepolia/BSC/Solana de volta para Terra Classic
- Testar o fluxo reverso após criar Warp Routes
- Verificar recebimento de tokens em Terra Classic

**O que você vai fazer:**
1. Configurar `ETH_PRIVATE_KEY` (EVM) ou keypair Solana
2. Executar `./transfer-remote-to-terra.sh`
3. Escolher token e rede origem
4. Inserir endereço Terra Classic do destinatário
5. Confirmar e enviar

**Tempo estimado:** 2-5 minutos por transferência

---

#### 5. [`enroll-terra-router-guide.md`](./enroll-terra-router-guide.md)
**O que faz:** Guia para registrar rotas EVM no contrato Warp da Terra Classic (resolve erro "route not found").

**Quando usar:**
- Erro `route not found` ao executar `transfer_remote`
- Deploy foi feito sem `TERRA_PRIVATE_KEY` configurado
- Adicionando uma nova rede EVM a um token existente
- Verificação preventiva antes de transferir

**O que você vai fazer:**
1. Executar `./enroll-terra-router.sh`
2. Escolher token e rede EVM
3. Confirmar e executar `set_route` no contrato Terra Classic

**Tempo estimado:** 1-2 minutos

---

### 🔧 **Documentos de Suporte**

#### 6. [`HYPERLANE_DEPLOYMENT-TESTNET.md`](./HYPERLANE_DEPLOYMENT-TESTNET.md)
**O que faz:** Documentação técnica sobre deploy de contratos Hyperlane em testnets.

**Quando usar:**
- Entender a arquitetura dos contratos Hyperlane
- Deploy manual de contratos (sem scripts)
- Troubleshooting avançado

---

#### 7. [`submit-proposal-guide.md`](./submit-proposal-guide.md)
**O que faz:** Guia para criar e submeter propostas de governança na Terra Classic.

**Quando usar:**
- Atualizar configurações via governança
- Modificar parâmetros de contratos deployados
- Operações administrativas avançadas

---

#### 8. [`UPDATE-IGP-ORACLE-GOVERNANCE.md`](./UPDATE-IGP-ORACLE-GOVERNANCE.md)
**O que faz:** Guia específico para atualizar o Oracle do IGP via governança.

**Quando usar:**
- Atualizar taxas de gas do IGP
- Modificar exchange rates
- Manutenção do sistema de gas paymaster

---

### 🛡️ **Documentos de Segurança**

#### 9. [`SAFE-SCRIPTS-GUIDE.md`](./SAFE-SCRIPTS-GUIDE.md)
**O que faz:** Guia para usar scripts com Safe (multisig) para operações seguras.

**Quando usar:**
- Operações em produção
- Requerendo múltiplas assinaturas
- Operações críticas de infraestrutura

---

#### 10. [`QUICK-START-SAFE.md`](./QUICK-START-SAFE.md)
**O que faz:** Início rápido para configurar Safe multisig.

**Quando usar:**
- Primeira configuração de Safe
- Setup rápido de multisig para testes

---

#### 11. [`README-SAFE-EXECUTE.md`](./README-SAFE-EXECUTE.md)
**O que faz:** Documentação sobre execução de transações via Safe.

**Quando usar:**
- Executar transações multisig
- Entender o fluxo de aprovação Safe

---

## 🔄 Fluxo de Trabalho Completo

### Cenário 1: Criar Warp Route EVM (Terra Classic ↔ Sepolia)

```
1. Instalação
   └─ yarn install

2. Configuração
   ├─ Editar warp-evm-config.json (adicionar token/rede)
   └─ Editar config.yaml (gas prices, owner, etc.)

3. Deploy
   └─ ./create-warp-evm.sh
      ├─ Deploy Warp Route EVM
      ├─ Deploy IGP Custom
      ├─ Configurar AggregationHook
      └─ Registrar rota no Terra Classic (set_route)

4. Teste
   ├─ Terra → EVM: ./transfer-remote-terra.sh
   └─ EVM → Terra: ./transfer-remote-to-terra.sh
```

**Documentos necessários:**
- [`create-warp-evm-guide.md`](./create-warp-evm-guide.md) — Passos 1-3
- [`transfer-remote-guide.md`](./transfer-remote-guide.md) — Passo 4 (Terra → EVM)
- [`transfer-remote-to-terra-guide.md`](./transfer-remote-to-terra-guide.md) — Passo 4 (EVM → Terra)

---

### Cenário 2: Criar Warp Route Sealevel (Terra Classic ↔ Solana)

```
1. Instalação
   └─ yarn install

2. Configuração
   ├─ Editar warp-sealevel-config.json
   ├─ Criar metadata JSON do token
   └─ Configurar keypair Solana

3. Deploy
   └─ ./create-warp-sealevel.sh
      ├─ Deploy Warp Program Solana
      ├─ Deploy ISM e IGP
      └─ Registrar rotas bidirecionais

4. Teste
   ├─ Terra → Solana: ./transfer-remote-terra.sh
   └─ Solana → Terra: ./transfer-remote-to-terra.sh
```

**Documentos necessários:**
- [`create-warp-sealevel-guide.md`](./create-warp-sealevel-guide.md) — Passos 1-3
- [`transfer-remote-guide.md`](./transfer-remote-guide.md) — Passo 4 (Terra → Solana)
- [`transfer-remote-to-terra-guide.md`](./transfer-remote-to-terra-guide.md) — Passo 4 (Solana → Terra)

---

### Cenário 3: Resolver Erro "route not found"

```
1. Identificar problema
   └─ transfer_remote falha com "route not found"

2. Verificar configuração
   └─ Checar se rota existe no Terra Classic

3. Registrar rota
   └─ ./enroll-terra-router.sh
      └─ Executa set_route no contrato Terra Classic

4. Testar novamente
   └─ ./transfer-remote-terra.sh
```

**Documentos necessários:**
- [`enroll-terra-router-guide.md`](./enroll-terra-router-guide.md)

---

## 📁 Estrutura de Arquivos Importantes

```
terraclassic/
├── doc/                          ← Você está aqui
│   ├── README.md                 ← Este documento (índice)
│   ├── create-warp-evm-guide.md
│   ├── create-warp-sealevel-guide.md
│   ├── transfer-remote-guide.md
│   ├── transfer-remote-to-terra-guide.md
│   └── enroll-terra-router-guide.md
│
├── create-warp-evm.sh            ← Script principal EVM
├── create-warp-sealevel.sh       ← Script principal Solana
├── transfer-remote-terra.sh      ← Enviar Terra → Outros
├── transfer-remote-to-terra.sh   ← Enviar Outros → Terra
├── enroll-terra-router.sh        ← Registrar rotas
│
├── warp-evm-config.json          ← Config EVM + tokens Terra
├── warp-sealevel-config.json     ← Config Solana
└── config.yaml                   ← Config Terra Classic (gas, owner, etc.)
```

---

## 🎯 Decisão Rápida: Qual Documento Usar?

| Situação | Documento |
|----------|-----------|
| Primeira vez criando Warp Route EVM | [`create-warp-evm-guide.md`](./create-warp-evm-guide.md) |
| Primeira vez criando Warp Route Solana | [`create-warp-sealevel-guide.md`](./create-warp-sealevel-guide.md) |
| Enviar tokens Terra → EVM/Solana | [`transfer-remote-guide.md`](./transfer-remote-guide.md) |
| Enviar tokens EVM/Solana → Terra | [`transfer-remote-to-terra-guide.md`](./transfer-remote-to-terra-guide.md) |
| Erro "route not found" | [`enroll-terra-router-guide.md`](./enroll-terra-router-guide.md) |
| Entender arquitetura Hyperlane | [`HYPERLANE_DEPLOYMENT-TESTNET.md`](./HYPERLANE_DEPLOYMENT-TESTNET.md) |
| Operações via governança | [`submit-proposal-guide.md`](./submit-proposal-guide.md) |
| Usar Safe multisig | [`SAFE-SCRIPTS-GUIDE.md`](./SAFE-SCRIPTS-GUIDE.md) |

---

## ⚠️ Troubleshooting Rápido

### Erro: "route not found"
→ Use [`enroll-terra-router-guide.md`](./enroll-terra-router-guide.md)

### Erro: "insufficient fees"
→ Verifique `gasPrice` em `config.yaml` (deve ser `28.325uluna`)

### Erro: "insufficient balance"
→ Verifique se você tem tokens na carteira antes de transferir

### Erro: "node_modules not found"
→ Execute `yarn install` na raiz do projeto

### Script não encontra configuração
→ Verifique se `warp-evm-config.json` ou `warp-sealevel-config.json` existem e estão corretos

---

## 📞 Próximos Passos

1. **Se é sua primeira vez:** Comece com [`create-warp-evm-guide.md`](./create-warp-evm-guide.md) ou [`create-warp-sealevel-guide.md`](./create-warp-sealevel-guide.md)

2. **Se já tem Warp Routes criados:** Use [`transfer-remote-guide.md`](./transfer-remote-guide.md) para testar transferências

3. **Se está com problemas:** Consulte a seção de Troubleshooting de cada guia específico

---

## 📝 Notas Importantes

- **Todos os scripts são interativos** — você pode executar sem parâmetros e escolher opções
- **Modo não-interativo disponível** — use variáveis de ambiente para automação
- **Logs salvos automaticamente** — em `terraclassic/log/`
- **Configurações centralizadas** — tudo em arquivos JSON/YAML fáceis de editar

---

**Última atualização:** 2026-03-13  
**Versão:** 1.0
