# Transferência de posse (ownership) — deployment Solana comunitário

Guia do script [`transfer-solana-ownership.sh`](../transfer-solana-ownership.sh), que transfere
os papéis de owner/admin do deployment Hyperlane na Solana da autoridade atual
(o **deployer**) para um **novo owner**.

**Escopo de cada execução:** a **infra compartilhada** (IGP + overhead IGP + ISM,
com seus owners e upgrade authorities) **mais um warp token que você informa**
(ex.: `igorfake`). Os demais tokens **não** são tocados. Assim você entrega a
infra junto com o warp específico em que está trabalhando, sem afetar os outros.

## Objetivo e as duas fases

O deployment é feito com uma chave de deploy ("quente") que paga o SOL e nasce
como dona de tudo. Depois, a posse é entregue a quem deve governar de fato.

| Fase | `NEW_OWNER` | Quando |
|------|-------------|--------|
| **1 — Ensaio** | `EMAYGfEyhywUyEX6kfG5FZZMfznmKXM8PbWpkJhJ9Jjd` (chave de owner que você controla) | Agora, em testnet, para validar o fluxo |
| **2 — Produção** | Vault do **multisig Squads dos validadores da Hyperlane** | Depois de todo o deploy de mainnet estar pronto e conferido |

A Fase 1 é um teste seguro: como você controla **as duas** chaves (deployer e
`EMAYGf`), dá para reverter. Na Fase 2, entregar ao multisig é **porta de mão única**.

## Papéis transferidos

Todos referentes à rede `NET_KEY` (default `solanatestnet`). Endereços resolvidos
automaticamente do `warp-sealevel-config.json` + artifacts do env.

| # | Papel | Objeto | Comando | Autoridade exigida |
|---|-------|--------|---------|--------------------|
| 1 | **IGP beneficiary** | inner IGP | `igp set-igp-beneficiary` | owner do IGP |
| 2 | **IGP owner** | inner IGP | `igp transfer-igp-ownership` | owner do IGP |
| 3 | **Overhead IGP owner** | overhead IGP | `igp transfer-overhead-igp-ownership` | owner do overhead IGP |
| 4 | **ISM owner** | ISM program | `multisig-ism-message-id transfer-ownership` | owner do ISM |
| 5 | **IGP upgrade authority** | IGP program | `solana program set-upgrade-authority` | upgrade authority atual |
| 6 | **ISM upgrade authority** | ISM program | `solana program set-upgrade-authority` | upgrade authority atual |
| 7 | **Warp route owner** (por token) | token program | `token transfer-ownership` | owner do warp |
| 8 | **Warp upgrade authority** (por token) | token program | `solana program set-upgrade-authority` | upgrade authority atual |

> **Beneficiary (nº 1)** não é bem "owner/admin" — é para onde vão as taxas. É
> incluído porque, no handoff completo, as taxas também devem ir para a comunidade.
> Para não mexer nele: `SKIP_BENEFICIARY=1`.

### Dois níveis de autoridade por programa

Cada programa tem **duas** autoridades independentes — as duas precisam migrar:

- **Access-control owner** (dentro do estado do programa) → quem configura
  (setar ISM/IGP, validators, oráculo, beneficiary…). Comandos do `hyperlane-sealevel-client`.
- **Upgrade authority** (do BPF Loader) → quem pode **substituir o bytecode** do
  programa. Comando `solana program set-upgrade-authority`.

Transferir só uma das duas deixa a porta aberta pela outra.

## Ordem importa

O script respeita a ordem segura: **o `beneficiary` é setado ANTES de transferir o
`owner` do IGP** — porque mudar o beneficiary exige ser owner. Depois que o owner
sai, não dá mais para ajustar nada sem a nova autoridade.

## Uso

O **token é obrigatório** (o warp que você quer transferir junto com a infra).
Se você não passar, o script lista os tokens deployados e sai.

```bash
# DRY-RUN (não executa nada) — testnet, infra + warp 'igorfake', destino EMAYGf
./transfer-solana-ownership.sh igorfake

# Executar de verdade (pede confirmação 'TRANSFERIR')
./transfer-solana-ownership.sh igorfake --execute

# Mainnet (dry-run)
NET_KEY=solanamainnet ./transfer-solana-ownership.sh igorfake

# Fase 2 — entregar ao multisig dos validadores da Hyperlane
NEW_OWNER=<SQUADS_VAULT> NET_KEY=solanamainnet ./transfer-solana-ownership.sh igorfake --execute
```

> ⚠️ A **infra compartilhada (IGP/ISM)** é transferida em qualquer execução. Se
> você rodar para vários tokens em sequência, a infra só migra na **primeira**
> (nas seguintes o script detecta que já está no `NEW_OWNER` e pula).

### Variáveis

| Variável | Default | Descrição |
|----------|---------|-----------|
| `TOKEN_KEY` (ou 1º arg) | — (**obrigatório**) | warp token a transferir junto com a infra |
| `NET_KEY` | `solanatestnet` | rede alvo |
| `NEW_OWNER` | `EMAYGf…` | destino da posse |
| `OWNER_KEYPAIR` | keypair do deployer `BirXd4Q…` | autoridade **atual** que assina |
| `SKIP_BENEFICIARY` | (vazio) | `=1` para não alterar o beneficiary |
| `CLIENT` | `~/hyperlane-monorepo/.../hyperlane-sealevel-client` | binário do client |

## Segurança

- **DRY-RUN por padrão.** Nada é executado sem `--execute`.
- **Idempotente.** Antes de cada transferência de upgrade authority e de warp
  route owner, o script lê o estado on-chain e **pula** o que já está no `NEW_OWNER`.
- **Confirmação.** No `--execute` é preciso digitar `TRANSFERIR`.
- **Irreversível na chain.** Solana não tem "claim" — a tx confirma e a posse muda.
- **Vault do Squads (Fase 2):** `NEW_OWNER` deve ser o endereço da **vault** (a PDA
  que atua como autoridade do multisig), **não** a conta de configuração do multisig.

## Verificação (depois de transferir)

```bash
# upgrade authorities
solana program show <IGP_PROGRAM> --url <RPC> | grep Authority
solana program show <ISM_PROGRAM> --url <RPC> | grep Authority
solana program show <TOKEN_PID>   --url <RPC> | grep Authority

# access-control owners
hyperlane-sealevel-client -u <RPC> token query --program-id <TOKEN_PID> synthetic | grep -A2 'owner: Some'
```

> Nota: `igp query` e `multisig-ism-message-id query` do client têm um bug
> (`unwrap` em None) neste cenário e podem panicar — não afeta as transferências.
> Para conferir o owner do IGP/ISM, decodifique a conta on-chain se necessário.

## Reverter o ensaio (só na Fase 1)

Como você controla as duas chaves, dá para voltar tudo para o deployer:

```bash
NEW_OWNER=BirXd4QDxfq2vx9LGqgXXSgZrjT81rhoFGUbQRWDEf1j \
OWNER_KEYPAIR=$HOME/keys/solana-keypair-EMAYGfEyhywUyEX6kfG5FZZMfznmKXM8PbWpkJhJ9Jjd.json \
./transfer-solana-ownership.sh --execute
```

(Na Fase 2, com multisig, reverter exige aprovação M-de-N do próprio multisig.)

## Endereços do deployment comunitário (testnet — `solanatestnet`)

| Papel | Endereço |
|-------|----------|
| IGP program | `ESag6QsGmixv5HrtEgi5qxJxWQS1NeBa5TCVKfnCQ8c2` |
| IGP account (inner) | `2dtsRyohVAgB2U6UxaK4EgQLPcGQK1d1K8CNCpzPRPkD` |
| Overhead IGP account | `FgsCd3gFPaUuzU7jH9rSp9YQ4mNrvxo9SxDs75FRgtny` |
| ISM program | `FQXMB763C9EMKGsGgjjkvtZvUakV9RieMpRwx11gRbja` |
| Warp `igorfake` program | `GfwnLrBJtG161xgN7fnoVnDFFzgwE9p1YGzE4CBNgz9N` |
| **Deployer** (autoridade inicial) | `BirXd4QDxfq2vx9LGqgXXSgZrjT81rhoFGUbQRWDEf1j` |
| **Owner de teste** (Fase 1) | `EMAYGfEyhywUyEX6kfG5FZZMfznmKXM8PbWpkJhJ9Jjd` |

## Ensaio realizado e verificado (testnet)

Comando: `./transfer-solana-ownership.sh igorfake --execute` (defaults: `BirXd4Q → EMAYGf`).
Todas as 8 transferências passaram, na ordem segura, e foram **confirmadas on-chain**:

| # | Papel | Objeto | Depois |
|---|-------|--------|--------|
| 1 | IGP beneficiary | inner `2dtsRy` | ✅ `EMAYGf` |
| 2 | IGP owner | inner `2dtsRy` | ✅ `EMAYGf` |
| 3 | Overhead IGP owner | `FgsCd3` | ✅ `EMAYGf` |
| 4 | ISM owner | `FQXMB763` | ✅ `EMAYGf` |
| 5 | Upgrade authority IGP | `ESag6` | ✅ `EMAYGf` |
| 6 | Upgrade authority ISM | `FQXMB763` | ✅ `EMAYGf` |
| 7 | Warp route owner | igorfake | ✅ `EMAYGf` |
| 8 | Upgrade authority WARP | `GfwnLr` | ✅ `EMAYGf` |

Conclusão: o fluxo de handoff está **validado ponta a ponta**. Para produção, basta
repetir com `NEW_OWNER=<vault do multisig>` e `NET_KEY=solanamainnet`.

## Forward × Revert — entendendo os erros

O script só consegue transferir o que a `OWNER_KEYPAIR` **realmente controla naquele
momento**. Há dois sentidos:

| Sentido | `NEW_OWNER` | `OWNER_KEYPAIR` (assina) | Funciona quando |
|---------|-------------|--------------------------|-----------------|
| **Forward** | `EMAYGf` (default) | `BirXd4Q` (deployer, default) | sempre — o deployer é a autoridade inicial |
| **Revert** | `BirXd4Q` | keypair do `EMAYGf` | **só depois** do forward (aí o `EMAYGf` vira autoridade) |

Se você rodar o **revert antes do forward**, os papéis de infra vão falhar com:

- `Transaction::sign failed with error NotEnoughSigners` — o client precisa da
  assinatura do **owner atual**, que a keypair fornecida não tem.
- `InstructionError(1, InvalidArgument)` / `failed: invalid program argument` — o
  programa on-chain **rejeita** porque quem assinou não é o owner atual.

**Esses erros são a proteção funcionando** — significam "você não é a autoridade
atual". Nada é alterado, exceto os papéis que a keypair de fato controlava (ex.: no
nosso caso, o revert prematuro só conseguiu puxar o *route owner* do igorfake de
volta, porque era a única coisa que o `EMAYGf` já possuía).

> 💡 Regra de ouro: **assine sempre com a chave que é a autoridade ATUAL** do que
> você quer transferir. Forward → deployer; revert → o owner novo.

## Verificação rápida (comandos usados no ensaio)

```bash
# upgrade authorities
solana program show ESag6QsGmixv5HrtEgi5qxJxWQS1NeBa5TCVKfnCQ8c2 --url <RPC> | grep Authority
solana program show FQXMB763C9EMKGsGgjjkvtZvUakV9RieMpRwx11gRbja --url <RPC> | grep Authority
solana program show GfwnLrBJtG161xgN7fnoVnDFFzgwE9p1YGzE4CBNgz9N --url <RPC> | grep Authority

# warp route owner
hyperlane-sealevel-client -u <RPC> token query \
  --program-id GfwnLrBJtG161xgN7fnoVnDFFzgwE9p1YGzE4CBNgz9N synthetic | grep -A2 'owner: Some'
```

> Para o **owner do IGP/ISM** (access control), os `query` do client panicam neste
> cenário — decodifique a conta on-chain (byte layout `[1][8 disc][bump][salt32][owner Option][…]`)
> se precisar confirmar o valor exato.

## Observações

- `validator_announce` **não é ownable** (não tem owner para transferir) — é ignorado.
- O `mailbox` de testnet/mainnet é o **oficial da Hyperlane** — não é seu para transferir.
- Warp routes não deployados (`deployed:false`) são pulados automaticamente.
- No mainnet, confirme antes que o IGP/ISM/warp em uso são os **comunitários** (não
  os oficiais da Hyperlane) — só faz sentido transferir o que é seu.
