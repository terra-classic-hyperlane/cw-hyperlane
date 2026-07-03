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

### 4. Operational — relayer signer funding (delivery gas)

The **relayer** needs SOL in its Solana signer to pay for message-delivery transactions
(≈ 0.0013 SOL per delivery: fee + recipient ATA + token mint). Funded on 2026-07-03:

| Item | Address | SOL |
|------|---------|-----|
| Relayer Solana signer | `PbEo7Fn2eJ6LYa4B8YU4MexB6s1BEQquWKCM1cwwrkS` | 0.06067 (≈ **$5.00** @ $82.41/SOL) |

TX: `4MNLr5HhC37jEYRKexyXFDpcoZArMwGjSMN3pWxmqinfoZ4qhEjvxWHDsLsnEkKysgNBxrbJsDaXQ3gfjwv6zLBy`

> This is an **operational / recurring** cost — **not** recoverable rent. It is consumed
> by delivery fees on Solana. Monitor the signer balance and top it up as needed
> (~0.06 SOL ≈ 40 deliveries). It unblocked the first TC→Solana deliveries (messages
> `0xef69b6f7…` and `0x269c455b…` delivered successfully).

## Totals

| | SOL |
|---|---|
| **Rent locked** (recoverable on teardown) | **5.02507064** |
| **Transaction fees** (burned, non-recoverable) | **≈ 0.01667** |
| **Operational** — relayer signer funding (delivery gas) | **0.06067** |
| **TOTAL** | **≈ 5.10241** |

> programdata rent scales with the `.so` size: warp `2.22` (312K) > IGP `1.61` (228K) >
> ISM `1.12` (160K).

## About `igorfake` (test token)

`igorfake` is a **FAKE token**, deployed **only to validate the end-to-end warp flow on
mainnet** (program → init → ISM/IGP → enroll → set_route on Terra Classic).

**Once testing is complete, the `igorfake` warp will be CLOSED and its rent returned to
the payer** — approximately **2.28 SOL recovered** (program `EPJNrr…` + accounts), via:

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
