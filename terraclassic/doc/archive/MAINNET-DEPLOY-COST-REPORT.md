# Mainnet Deployment — SOL Cost Report

Community accountability report for all SOL spent deploying the Hyperlane **community
infrastructure** (IGP + ISM) and the **warp route** on Solana Mainnet.

All values were read on-chain. Report generated for the community; amounts in **SOL**.

## Funding source

The payer wallet held two clearly separated sources of funds. Accountability to the
community is measured **only against the community contribution**.

| Source | SOL | Note |
|--------|-----|------|
| **Community contribution** | **7.449271196** | converted from **585.702903 USDC** (~78.62 USDC/SOL) |
| Personal test funds (deployer) | 2.102794599 | pre-existing, belongs to the deployer — **not** community money |
| **Total in payer wallet (pre-deploy)** | **9.552065795** | |

### Funding trail — how the community SOL was sourced

The community contribution (**+7.449182 SOL**) was sourced from community **LUNC**,
converted on-chain through the steps below — all on **2026-07-02**, within ~8 minutes:

| # | Chain(s) | Conversion / transfer | Amount | Time (UTC) | Tx |
|---|----------|-----------------------|--------|------------|-----|
| 1 | Terra Classic | **LUNC → USDC** (swap) | ≈ 4,936,795 LUNC → ≈ 585.90 USDC | 03:16:39 | [`FE10F019…D8236`](https://finder.terra.money/classic/tx/FE10F019AABE5E4F67EB5E09AD29386E6F7B85E2D78AAA5B22B4E229951D8236) |
| 2 | Terra Classic → Noble | **USDC → Noble** (IBC, channel-113) | 585.902200 USDC | 03:19:15 | [`11AD2400…563ED`](https://finder.terra.money/classic/tx/11AD2400D72C5960D51A0F92948996B64C5DE9095161FFE342ABD5A90E8563ED) |
| 3 | Noble → Solana | **USDC → Solana** (CCTP / Range) | ≈ 585.702903 USDC (após taxa de bridge) | ~03:2x | [range.org](https://usdc.range.org/transactions?sc=INTERCHAIN&s=noble1act45umsc0nwj570qfe8zumarwws5jz9ml2tdl) |
| 4 | Solana | **USDC → SOL** (swap → wSOL → SOL) | 585.702903 USDC → **+7.449182 SOL** | 03:24:02 | [`44jqir…oooYQwR`](https://solscan.io/tx/44jqirx58q6t7Ey81b5h1WQQPNgvqrVw4Amnp8QkhRopD3DL4tbn7cvC84t9kdA7MVrGqJAAMecyojHQvoooYQwR) |

Taxa implícita SOL: 585.702903 USDC ÷ 7.449182 SOL ≈ **$78,63/SOL**.

**Endereços da trilha** (todas as carteiras são do **desenvolvedor de deploy** — usadas
para executar a conversão e o deploy; **não** são carteiras da comunidade):
| Papel | Endereço |
|-------|----------|
| Carteira Terra Classic — **do desenvolvedor de deploy** | `terra1run9wz09uhh6pu7ggcwwetrgye4wu7wn26mawp` |
| Conta Noble (intermediária) — do desenvolvedor de deploy | `noble1act45umsc0nwj570qfe8zumarwws5jz9ml2tdl` |
| Carteira Solana (payer dos deploys) — do desenvolvedor de deploy | `BirXd4QDxfq2vx9LGqgXXSgZrjT81rhoFGUbQRWDEf1j` |

> **Importante:** as carteiras acima são do **desenvolvedor de deploy**, não da
> comunidade. O que é da comunidade é o **valor** — os **7,449 SOL** (≈ 585,70 USDC,
> convertidos de LUNC) — que foi roteado *através* das carteiras do desenvolvedor de
> deploy para realizar os deploys. On-chain confirma o baseline: a carteira Solana
> `BirXd4Q…` foi de **2.102884 → 9.552066 SOL** ao receber os 7.449182 SOL (step 4);
> os **2,1028 SOL pré-existentes** são fundos pessoais do desenvolvedor de deploy.

## Summary

| | |
|---|---|
| Payer wallet | `BirXd4QDxfq2vx9LGqgXXSgZrjT81rhoFGUbQRWDEf1j` |
| Balance before deploys | `9.552065795` |
| Balance now (after relayer funding) | `≈ 4.449647` |
| **Total spent (from the combined wallet)** | **≈ 5.102414** |

Most of the total is **rent** (rent-exempt reserve locked inside on-chain accounts) —
**recoverable** by closing the accounts/programs; it is invested in on-chain storage,
not burned. Only the transaction fees (~0.017 SOL) are non-recoverable.

> **Community-fund impact:** of the ≈5.04 SOL spent, ≈5.02 is recoverable rent and only
> ≈0.017 is burned fees. After the `igorfake` test is closed (−2.28 recovered), the
> permanent community-funded rent is just the shared infra — **IGP 1.621 + ISM 1.125 =
> ≈2.746 SOL, all recoverable** if the infra is ever torn down. So the true
> non-recoverable community cost to date is ≈**0.017 SOL** (fees).

## Cost breakdown

### 1. IGP — Interchain Gas Paymaster
| Account | Address | Rent (SOL) |
|---------|---------|------------|
| program | `FLZuKRsfdovLqd8n1AYhPCwLqBjfFyZY3A2edgnjdJoR` | 0.00114144 |
| programdata | `FGQB8BYQz4Nj9uMusuM9VLSQKgPSpQrV1nV1A2Sp4JBu` | 1.61469912 |
| IGP account (inner) | `FPTvDsowMHXFKktoLgy2a2qfr5yL6846JHKwvk2mYKFk` | 0.00345912 |
| overhead IGP account | `FXacR73HiuNyvW7x34KYCDyv8XxM86pz31Ap8t2v3RCJ` | 0.00174696 |
| **Subtotal** | | **1.62104664** |

### 2. ISM — Multisig Security Module
| Account | Address | Rent (SOL) |
|---------|---------|------------|
| program | `4MzF7HCfxuwj4EFHqZSEpvkcZZvv1mF37DP4pDHwR5VQ` | 0.00114144 |
| programdata | `4CFMLbJKNg2jn9SVecmgiSohbqM7jA8QdxJ2rc96o8GJ` | 1.12371288 |
| **Subtotal** | | **1.12485432** |

### 3. Warp route — `igorfake` (test token) — includes program + mint
| Account | Address | Rent (SOL) |
|---------|---------|------------|
| **program** | `EPJNrrpCeZGqDPoFtdV9u9uDWBNW3Xqh84LfM7345zcL` | 0.00114144 |
| programdata | `8w9xxSM2ot8wK29D1mJEHQ1UpmQPGJaSsdJegJaFjDky` | 2.22105432 |
| **mint** (Token-2022) | `CeLHx5Wm9AzuWRnP4URMfNqNa9kDDrnsNGoATCS96QwD` | 0.00405768 |
| token store | `4cS7w9zyS1CV5m92RDhyaevjY3vdfED66zqGb1Vh3FR6` | 0.00291624 |
| ATA payer (funding) | `CuT1SZWTEHCBtKcFUptf53U7npm9fn41xDucp699nr7D` | 0.05000000 |
| **Subtotal** | | **2.27916968** |

### 4. Operational — relayer signer funding (delivery gas) — **borne by the relayer operator, NOT the community**

The **relayer** needs SOL in its Solana signer to pay for message-delivery transactions
(≈ 0.0013 SOL per delivery: fee + recipient ATA + token mint). Funded on 2026-07-03:

| Item | Address | SOL |
|------|---------|-----|
| Relayer Solana signer | `PbEo7Fn2eJ6LYa4B8YU4MexB6s1BEQquWKCM1cwwrkS` | 0.06067 (≈ **$5.00** @ $82.41/SOL) |

TX: `4MNLr5HhC37jEYRKexyXFDpcoZArMwGjSMN3pWxmqinfoZ4qhEjvxWHDsLsnEkKysgNBxrbJsDaXQ3gfjwv6zLBy`

> ⚠️ **This is a cost of whoever OPERATES the relayer — NOT a community cost.** The
> relayer is an off-chain service; its Solana signer gas is paid by the relayer operator.
> Currently the **deploy developer operates the relayer and volunteers to keep operating
> it**, funding this signer from their own funds. It is therefore **not charged against
> the community donation**. It is an operational/recurring cost (not recoverable rent),
> consumed by delivery fees; the operator monitors and tops up the signer as needed
> (~0.06 SOL ≈ 40 deliveries). It unblocked the first TC→Solana deliveries (messages
> `0xef69b6f7…` and `0x269c455b…`, delivered successfully).

## Totals

| | SOL |
|---|---|
| **Rent locked** (recoverable on teardown) | **5.02507064** |
| **Transaction fees** (deploy — burned, non-recoverable) | **≈ 0.01667** |
| **Deploy subtotal** (against the community-funded pool) | **≈ 5.04174** |
| **Relayer signer funding** — *operator-borne, **NOT** community* | **0.06067** |
| **Total moved from the wallet** | **≈ 5.10241** |

> The **deploy subtotal (≈ 5.04174 SOL)** is what is charged against the community
> donation (of which ≈ 5.025 is recoverable rent, ≈ 0.017 burned fees). The **relayer
> signer funding (0.06067 SOL)** is **not** community cost — it belongs to the relayer
> operator (see §4).

> programdata rent scales with the `.so` size: warp `2.22` (312K) > IGP `1.61` (228K) >
> ISM `1.12` (160K).

## About `igorfake` (test token)

`igorfake` is a **FAKE token**, deployed **only to validate the end-to-end warp flow on
mainnet** (program → init → ISM/IGP → enroll → set_route on Terra Classic).

**✅ DONE 2026-08-29: the `igorfake` warp was CLOSED** — **2.221 SOL reclaimed** from
the program (`EPJNrr…`), funding the LUNC Solana deploy (live program
`Dd3ajD8WbEyx7z3HqPnDyvUgFqEBzvF1VePjYd1NGnbr`, see doc/install/DEPLOY-HASHES.md §5).
The mint / token-store / ATA-payer PDAs stay orphaned (rent not recoverable once the
program is closed). Command used:

```bash
# closes the warp program and reclaims the rent
solana program close EPJNrrpCeZGqDPoFtdV9u9uDWBNW3Xqh84LfM7345zcL \
  --recipient BirXd4QDxfq2vx9LGqgXXSgZrjT81rhoFGUbQRWDEf1j \
  --keypair <UPGRADE_AUTHORITY_KEYPAIR> --url <RPC>
# (the mint / token-store / ATA-payer accounts are closed separately)
```

The **community infrastructure (IGP + ISM) stays deployed** — it is shared by all real
warp routes. Only the test token is torn down.

## Net cost after test teardown (projected)

| | SOL |
|---|---|
| Community IGP (permanent) | 1.62104664 |
| Community ISM (permanent) | 1.12485432 |
| `igorfake` test (to be recovered) | −2.27916968 |
| Fees (burned) | ≈ 0.01667 |
| **Projected net cost of the infra** | **≈ 2.75 (rent, recoverable) + 0.017 (fees)** |

## Next steps — production warp routes

After the `igorfake` test is closed, deploy the **real** warp routes reusing the same
verified binary (`BINARY_SOURCE=local`, SHA `d6f2fc9…33419`) and the community ISM/IGP:

1. **LUNC** (Wrapped Terra Classic LUNC)
2. **USTC** (Wrapped TerraClassic USD)

Each follows the same 3-step process documented in `WARP-COMMUNITY-GUIDE.md` §11
(create program → buffer init/wiring → set_route on Terra Classic). Each real route
costs ~2.2 SOL in program rent (recoverable) + minimal fees.

## Community fund — return of any leftover

**Commitment:** once **all LUNC and USTC production warp routes are deployed** and the
**`igorfake` test token is closed** (recovering ~2.28 SOL of its rent), **any SOL
remaining from the community donation of `7.449182` SOL will be returned to the
community.**

The community's `7.449182` SOL (≈ 585.70 USDC, converted from LUNC — see *Funding source*
and *Funding trail*) is tracked **separately** from the deploy developer's personal funds
(the pre-existing `2.1028` SOL). Only what is genuinely consumed by the **on-chain
production deployment** (LUNC + USTC warp routes + shared IGP/ISM infra) is charged
against the community donation. **Relayer operating costs (signer gas) are borne by the
relayer operator, not the community** (see §4). The **remaining balance is returned to
the community**.

> Portuguese / Português: **assim que todos os deploys de LUNC e USTC forem concluídos e
> o token de teste `igorfake` for fechado (recuperando ~2,28 SOL), o valor que sobrar dos
> `7.449182` SOL doados pela comunidade será devolvido à comunidade.**

## Governance — ownership handoff to a validators multisig

During deployment the community infrastructure (community **IGP** and **ISM**) and the
warp routes are owned by the **deploy developer's key** (bootstrap owner). This is
temporary.

> ⭐ **Once all deployments are complete, ownership will be transferred to a
> multi-signature (multisig) account controlled by the Hyperlane validators** — so that
> **no single party controls the community infrastructure**; changes (oracle updates,
> ISM validators, upgrades, beneficiary) require M-of-N approval by the validators.

This covers **all authorities**: IGP owner + beneficiary, Overhead IGP owner, ISM owner,
program upgrade authorities, and each warp route owner. The bootstrap-then-handoff
sequence and the exact transfer procedure are documented in `TRANSFER-SOLANA-OWNERSHIP.md`.

> Português: **assim que tudo for implantado, o `owner` passará a ser uma conta
> multi-assinatura (multisig) dos validadores da Hyperlane** — governança compartilhada,
> sem controle por uma única parte.
