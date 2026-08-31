# Solana Funding Proposal — On-chain submission

Arquivos prontos para submeter o **Community Pool Spend** referente à
[`funding-proposal.md`](./funding-proposal.md).

| Arquivo | Formato |
|---|---|
| `solana-funding-proposal.json` | cosmos-sdk **gov v1** (`MsgCommunityPoolSpend`) |
| `solana-funding-proposal-legacy.json` | formato **legacy** (`community-pool-spend`) |

## Valores (2026-06-15)

| Campo | Valor |
|---|---|
| Recipient | `terra1run9wz09uhh6pu7ggcwwetrgye4wu7wn26mawp` |
| Authority (gov) | `terra10d07y265gmmuvt4z0w9aw880jnsr700juxf95n` |
| Amount | **9,873,590 LUNC** = `9873590000000uluna` |
| Base | 9.08 SOL × $80 (buffer) ÷ $0.00007357/LUNC |

## ⚠️ Antes de submeter — verificar

1. **Formato aceito** (v1 vs legacy):
   ```bash
   terrad tx gov submit-proposal --help        # se aceita arquivo de messages -> use o v1
   terrad tx gov submit-legacy-proposal --help  # caso contrário -> use o legacy
   ```
2. **Depósito mínimo** (o `deposit` no JSON é inicial — confirme o mínimo vigente):
   ```bash
   terrad query gov params --node <RPC> -o json | jq '.deposit_params // .params'
   ```
3. **Cotação do LUNC** — o preço oscila intraday; se mudar muito desde 2026-06-15,
   recalcule o `amount` (`9.08 × 80 ÷ preco_LUNC × 1e6` uluna).

## Submeter

```bash
# gov v1
terrad tx gov submit-proposal solana-funding-proposal.json \
  --from <sua_conta> --chain-id columbus-5 --node <RPC> \
  --gas auto --gas-adjustment 1.5 --gas-prices 28.325uluna -y

# legacy (alternativa)
terrad tx gov submit-legacy-proposal community-pool-spend solana-funding-proposal-legacy.json \
  --from <sua_conta> --chain-id columbus-5 --node <RPC> \
  --gas auto --gas-adjustment 1.5 --gas-prices 28.325uluna -y
```

> Após submeter, deposite o restante até o mínimo (se o depósito inicial for menor)
> e divulgue o link da proposta para a comunidade votar.
