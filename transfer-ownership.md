# transfer-ownership.sh — Transferência de propriedade dos contratos Hyperlane (Terra Classic)

Documento de referência do script `transfer-ownership.sh`, que transfere o
**owner** (e, opcionalmente, o **admin de migração**) dos contratos de
**infraestrutura** Hyperlane no Terra Classic para a conta da **governança**.

> ⚠️ **Seguro por padrão:** o script roda em modo **dry-run** (apenas imprime os
> comandos, **não executa nada**). Só executa de verdade com a flag `--execute`.

---

## 0. ⚠️ Por que este script PRECISA ser executado (handoff obrigatório)

A conta do desenvolvedor (`CURRENT_OWNER`) foi usada **apenas** para a fase de
**instalação, implantação e testes** dos contratos. Ela **não** deve permanecer
como dona da infraestrutura em produção.

**Assim que os testes forem concluídos e tudo estiver funcionando, este script
DEVE ser executado** para que todos os contratos de infraestrutura passem ao
**domínio da governança**. Enquanto isso não for feito, a rede continua sob
controle de uma única conta (a do desenvolvedor) — o que é aceitável só durante
o setup, mas **inaceitável em produção**.

Resumo do ciclo:

```
  [desenvolvedor instala/deploya/testa]  →  testes OK  →  RODAR ESTE SCRIPT  →  governança no controle
```

Depois do handoff, **toda** alteração de configuração passa a exigir aprovação da
governança — que é exatamente o objetivo: descentralizar o controle.

### E os warp routes sintéticos?
Os contratos de infraestrutura (este script) vão para a **governança**. Já os
**warp routes sintéticos** de LUNC/USTC nas redes externas (Solana, Ethereum,
BSC) vão para um **multisig dos validadores do Hyperlane** — veja
[`transfer-warp-synthetics.md`](./transfer-warp-synthetics.md) e os scripts
`transfer-warp-evm.sh` / `transfer-warp-solana.sh`.

---

## 1. Para que serve

Quando você instancia os contratos Hyperlane, sua conta pessoal fica como
`owner` de cada um. Para descentralizar o controle, esse `owner` deve passar para
a conta da governança. A partir daí, **qualquer mudança de configuração**
(enrolar router, trocar ISM, ajustar hook/IGP) passa a exigir uma ação da
governança.

O script automatiza esse processo para todos os contratos de infraestrutura de
uma vez, com segurança e sem deixar nenhum de fora.

### O que NÃO entra
- **Warp routes** — são responsabilidade de quem os criou. O script ignora
  automaticamente toda a subárvore `deployments.warp` do arquivo de contexto.
- **Contratos sem owner** — `validator_announce` e hooks do tipo merkle/aggregate
  não têm `owner`; o script os detecta e pula.

---

## 2. Conceitos que você precisa entender antes

### 2.1 `owner` ≠ `admin` (são duas posses diferentes)

| Posse | O que controla | Como muda | Passos |
|---|---|---|---|
| **`owner`** (`hpl_ownable`) | Configuração: routers, ISM, hooks | `init_ownership_transfer` + `claim_ownership` | **2 passos** |
| **`admin`** (CosmWasm/x-wasm) | Upgrade de código (`migrate`) | `set-contract-admin` (`MsgUpdateAdmin`) | **1 passo, imediato** |

Transferir o `owner` **não** transfere o `admin`, e vice-versa. Decida
conscientemente o que fazer com cada um.

### 2.2 Transferência de `owner` é em DOIS PASSOS

Confirmado no código `packages/ownable/src/lib.rs`:

```
1) VOCÊ (owner atual):   init_ownership_transfer { next_owner: GOV }   → define "pending_owner"
2) A GOVERNANÇA:         claim_ownership {}                            → aceita e vira owner
```

- Enquanto a governança **não** der o `claim`, **você continua sendo o owner**.
- Você pode cancelar antes do claim com `revoke_ownership_transfer {}`.
- O `claim_ownership` exige que o **remetente seja o `pending_owner`** — ou seja,
  a governança precisa **conseguir assinar/executar** uma transação por conta
  própria.

> 🔑 **Ponto de atenção:** se sua governança é o módulo `x/gov` da chain, o claim
> só ocorre via **proposta aprovada** que execute `MsgExecuteContract`. Se for um
> **multisig** ou conta normal, basta ela assinar. **Teste o claim em um contrato
> antes de depender disso.**

### 2.3 Auto-descoberta segura

O script não confia numa lista fixa (os registros de deploy estão incompletos).
Em vez disso, para cada endereço candidato ele:

1. Consulta `get_owner` on-chain.
2. Só considera **elegível** se o contrato é ownable **E** o owner atual é
   exatamente o seu `CURRENT_OWNER`.
3. Pula (com aviso) tudo que não for ownable ou que não pertença a você.

Isso garante que nada errado seja tocado e que nenhum contrato seu fique de fora.

---

## 3. Configuração

Edite as variáveis no topo do script:

| Variável | Obrigatória | Descrição |
|---|---|---|
| `GOVERNANCE_ADDRESS` | ✅ | Conta da governança que receberá owner/admin (`terra1...`) |
| `CURRENT_OWNER` | ✅ | Seu endereço atual de owner. Filtro de segurança: o script só mexe em contratos cujo owner == este endereço |
| `SIGNER_KEY` | só no `--execute` | Nome da key no keyring que assina as txs. No modo normal = sua key; no `--claim` = key da governança |
| `BINARY` | — | Binário da CLI (padrão `terrad`) |
| `CHAIN_ID` | — | Padrão `columbus-5` |
| `NODE` | — | Endpoint RPC |
| `GAS_PRICES` / `GAS_ADJUST` | — | Parâmetros de gás |
| `CONTEXT_FILE` | — | Caminho do `context/terraclassic.json` (padrão: ao lado do script) |
| `EXTRA_CONTRACTS` | — | Endereços de **infraestrutura** extra que não estejam no context. **Não** coloque warp routes aqui |

---

## 4. Flags

| Flag | Efeito |
|---|---|
| _(nenhuma)_ | **Dry-run** do passo 1 (init transfer). Não executa. |
| `--dry-run` | Força dry-run (é o padrão). |
| `--execute` | **Executa de verdade.** Exige `SIGNER_KEY`. |
| `--include-admin` | Inclui também `set-contract-admin` (transfere o admin de migração). |
| `--claim` | Gera os comandos de **claim** (para a governança rodar). |
| `-h`, `--help` | Mostra o cabeçalho de ajuda. |

---

## 5. Fluxo recomendado (passo a passo)

> Faça isso **por último**, depois que tudo estiver configurado e funcionando —
> porque, após a transferência, toda mudança exige aprovação da governança.

**1. Preencha as variáveis** `GOVERNANCE_ADDRESS`, `CURRENT_OWNER` e `SIGNER_KEY`.

**2. Revise no dry-run** (não executa, só mostra e lista quais contratos são elegíveis):
```bash
./transfer-ownership.sh
./transfer-ownership.sh --claim          # ver os comandos que a governança vai usar
./transfer-ownership.sh --include-admin  # ver também os set-contract-admin
```

**3. Execute o passo 1** (você, owner atual, propõe a transferência):
```bash
./transfer-ownership.sh --execute
```

**4. A governança aceita** (passo 2 — `claim`). Ajuste `SIGNER_KEY` para a key da
governança (ou abra a proposta `x/gov`, conforme o caso):
```bash
./transfer-ownership.sh --claim --execute
```

**5. Confira o resultado:**
```bash
terrad query wasm contract-state smart <CONTRATO> '{"ownable":{"get_owner":{}}}' --node "$NODE"
terrad query wasm contract-state smart <CONTRATO> '{"ownable":{"get_pending_owner":{}}}' --node "$NODE"
```

**6. (Opcional) Transfira o admin de migração** — recomendado **só depois** que a
governança já confirmou o claim do owner, para você não ficar sem nenhum controle
no meio do caminho:
```bash
./transfer-ownership.sh --include-admin --execute
```

---

## 6. Como cancelar / reverter

- **Antes do claim:** o owner ainda é você. Cancele a transferência pendente:
  ```bash
  terrad tx wasm execute <CONTRATO> '{"ownable":{"revoke_ownership_transfer":{}}}' \
    --from <sua_key> --chain-id columbus-5 --node "$NODE" \
    --gas auto --gas-adjustment 1.5 --gas-prices 28.325uluna -y
  ```
- **Depois do claim:** o owner já é a governança. Só ela pode transferir de volta
  (rodando um novo `init_ownership_transfer` para você, que então faz o `claim`).

---

## 7. Comandos que o script gera (referência)

**Passo 1 — init transfer (você):**
```bash
terrad tx wasm execute <CONTRATO> \
  '{"ownable":{"init_ownership_transfer":{"next_owner":"<GOV>"}}}' \
  --from <sua_key> ...
```

**Passo 2 — claim (governança):**
```bash
terrad tx wasm execute <CONTRATO> \
  '{"ownable":{"claim_ownership":{}}}' \
  --from <key_governanca> ...
```

**Admin de migração (`--include-admin`):**
```bash
terrad tx wasm set-contract-admin <CONTRATO> <GOV> --from <sua_key> ...
```

---

## 8. Avisos importantes

1. **Ordem importa:** transfira o `owner` e deixe a governança dar o `claim`
   **antes** de mexer no `admin`. Mudar o admin cedo demais pode te deixar sem
   poder de upgrade enquanto a transferência de owner ainda não foi concluída.
2. **Confirme que a governança consegue dar o claim** antes de transferir tudo —
   especialmente se for via `x/gov`. Teste com um contrato primeiro.
3. **Warp routes não são tocados** — por design.
4. **Sempre rode o dry-run primeiro** e leia a lista de elegíveis/pulados.
5. **Reserve LUNC para gás** — são várias transações (uma por contrato).

---

## 9. Solução de problemas

| Sintoma | Causa provável | O que fazer |
|---|---|---|
| `nenhum endereço candidato encontrado` | `CONTEXT_FILE` errado ou vazio | Verifique o caminho do `context/terraclassic.json` |
| Contrato seu aparece como `skip (owner já é ...)` | Owner já transferido, ou `CURRENT_OWNER` errado | Confira `CURRENT_OWNER` e `get_owner` do contrato |
| `skip (sem get_owner)` | Contrato não-ownable (validator_announce / merkle hook) | Esperado — não há owner para transferir |
| `claim` falha com `unauthorized` | Quem assinou ≠ `pending_owner` | Assine com a key da governança / use a proposta x/gov correta |
| `ownership is transferring` | Já existe um pending owner | Faça o `claim` ou `revoke` antes de novo init |

---

## 10. Arquivos relacionados

- `transfer-ownership.sh` — o script.
- `context/terraclassic.json` — fonte dos endereços de infraestrutura.
- `packages/ownable/src/lib.rs` — implementação do `hpl_ownable` (lógica de owner).
- `packages/interface/src/ownable.rs` — definição de `OwnableMsg`.
