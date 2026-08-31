# Warp Routes — Configuração de GAS (IGP/Oracle) que FUNCIONA

> Guia definitivo pós-incidente de 2026-07-09, quando a **VOLTA** (synthetic → Terra Classic) estava
> quebrada nas 3 chains por 3 defeitos de configuração distintos. Os scripts foram corrigidos para
> **falhar alto** em vez de imprimir "SUCCESS" com a volta quebrada.

## Os 3 defeitos históricos (não repetir)

| # | Chain | Defeito | Sintoma | Fix |
|---|---|---|---|---|
| 1 | BSC/ETH | IGP deployado (04/jun) com `TERRA_CLASSIC_DOMAIN = 1325` (**testnet**) como `constant` | `quoteGasPayment(132556)` → revert `destination not supported` | Re-deploy do IGP (constant não tem setter) + novo AggregationHook + `setHook` |
| 2 | ETH | `setGasOracle` falhou (RPC) e o script seguiu como sucesso → IGP no oracle **oficial** (sem o TC) | quote = **0** → despacharia **sem pagar o relayer** (mensagem PRESA) | `setGasOracle(oracleCustom, overhead)` — agora é FATAL no script |
| 3 | Solana | `token igp set … igp <conta>` com a conta **OVERHEAD** (tipo errado hardcoded no script) | `PayForGas` → `BorshIoError`; volta quebrava **até pelo client rust** | `token igp set <prog> overhead-igp <conta>` — o script agora lê `igp.account_type` do config |

Bônus: o rate do oracle Solana estava superdimensionado (2e13 → volta custava **US$13,60**; recalibrado
para 2,94e10 → **US$0,02**).

## Fórmulas de preço (validadas on-chain)

### Sealevel (Solana) — scale rust `1e19`
```
lamports = (gas_amount + GAS_OVERHEAD) × ORACLE_GAS_PRICE × ORACLE_EXCHANGE_RATE / 1e19 × 10^(9 − DECIMALS)
```
Calibração pelo preço-alvo (ex.: US$0,02):
```
alvo_lamports        = 0.02 / SOL_USD × 1e9
ORACLE_EXCHANGE_RATE = alvo_lamports × 1e19 / ((100000 + GAS_OVERHEAD) × ORACLE_GAS_PRICE × 10^(9 − DECIMALS))
```
Valores de referência (2026-07-09, SOL $77 / LUNC $0.00006): `rate=29400000000, gas_price=28325, decimals=6, overhead=3000000` → 0,000258 SOL.

### EVM (TerraClassicIGPStandalone) — scale `1e10`
```
wei = (gasLimit + gasOverhead) × gasPrice × tokenExchangeRate / 1e10
```
Referência: BSC `rate=9047190` → ~0,0000018 BNB · ETH `rate=26585078` → ~0,000008 ETH.

### cw-hyperlane (Terra Classic, a IDA) — scale `1e10`
```
uluna = gas_amount × gas_price_destino × exchange_rate / 1e10
```
Ver `update-igp-oracle.sh` (oracle terra1j8xz…).

## Checklist de deploy de um warp novo (qualquer chain)

1. **EVM** (`create-warp-evm.sh`):
   - O script agora **valida o domain do .sol** antes de compilar (guard automático).
   - `setGasOracle` falho = **exit 1** (não seguir).
   - STEP 8 inclui o **teste real da volta**: `quoteGasPayment(132556)` no warp — precisa retornar valor **> 0**.
   - Re-runs: limpar `igp_custom`/`hook_aggregation` no `warp-evm-config.json` + `rm .warp-evm-state.json`,
     senão o script "pula" com os endereços VELHOS.
2. **Solana IGP** (`create-warp-igp-solana.sh`):
   - Defaults corrigidos (rate 2,94e10); o script imprime a **estimativa da taxa da volta** e avisa se > 0,01 SOL.
   - Grava `igp.account_type` no config (usado pelo warp init).
3. **Solana warp** (`deploy-warp-solana-buffer.sh`):
   - O `token igp set` usa o **tipo do config** (`overhead-igp` default) — nunca mais hardcode.
   - Verificação pós-set: `token igp get synthetic` confere o tipo on-chain.
4. **Sempre, ao final**: testar a volta com **simulação** antes de anunciar (ver
   `.claude/skills/cosmiq-bridges-routing` no repo do AveraChain — técnica de simulação por RPC sem gastar).

## Endereços mainnet atuais (LUNC/USTC, 2026-08-29)

| Peça | BSC | ETH | Solana |
|---|---|---|---|
| Warp/router LUNC | `0x481095ec…e6e2` | `0xA4bc47a4…4Ac6` | `Dd3ajD8W…Gnbr` |
| Warp/router USTC | `0xfC067fd9…4339` | `0xf49408be…1e51` | `7CUdBt1Q…Eoyf` |
| IGP (novo, domain 132556) | `0xEdEd7a4f…4923` | `0x9650F1f8…64Aa` | `FLZuKR…dJoR` |
| Oracle | `0x7dE950f8…2306` | `0x3987cCE8…96cE` | (interno, via client) |
| AggregationHook | `0xD2c82583…8164` | `0x912c4d91…0aA8` | — |
| IGP account (sealevel) | — | — | igp `FPTvDso…YKFk` / overhead `FXacR73…3RCJ` |
| Owner | `0x8f085bAD…5291` (⚠️ rotação pendente) | `0xEF818120…00ae` | `BirXd4…Ef1j` |

Registro completo (endereços por extenso, hashes, txs): `doc/install/DEPLOY-HASHES.md` §5/§6.
