# Proposta de Financiamento — Deploy Hyperlane Warp Routes no Solana Mainnet

> **Autor:** Igor Veras (`terra10d07y265gmmuvt4z0w9aw880jnsr700juxf95n`)  
> **Data:** 2026-06-07  
> **Categoria:** Infraestrutura / Interoperabilidade  
> **Tipo:** 🏛️ **Proposta de Saque do Community Pool (CP)** — requer aprovação via governança on-chain  
> **Status:** Aguardando aprovação da comunidade

---

> ⚠️ **ATENÇÃO — Tipo de Proposta**
>
> Esta é uma **proposta de saque do Community Pool (CP)** da Terra Classic.  
> **Não se trata de uma doação voluntária** e **não é uma coleta entre membros da comunidade**.  
> O valor de **≈ 9,072,794 LUNC** será sacado diretamente do fundo comunitário (Community Pool), mediante **aprovação pela governança on-chain** — ou seja, a proposta precisa ser submetida na blockchain da Terra Classic e aprovada por votação dos validadores e detentores de LUNC.

---

## Nota de Transparência

Gostaria de me desculpar com a comunidade por não ter informado estes custos na proposta original que solicitou autorização para realizar este trabalho de integração do Hyperlane com a Terra Classic.

Durante os testes na rede testnet do Solana, já havia percebido que o custo de deploy de programas era significativamente mais alto do que nas redes EVM. No entanto, acreditei que o valor seria diferente no mainnet — o que se revelou uma surpresa: o custo de rent-exempt no Solana Mainnet é equivalente ao testnet em termos de SOL, porém com o SOL valorizado (~$65 USD na época), o impacto financeiro real ficou muito acima do esperado.

Reconheço que esta informação deveria ter sido levantada e comunicada previamente. Esta proposta é a forma de corrigir essa lacuna de forma transparente, com todos os dados disponíveis para a comunidade avaliar.

---

## Resumo Executivo

Esta proposta solicita financiamento para custear o deploy de 5 programas Solana necessários para ativar as **Warp Routes Hyperlane** entre Terra Classic e Solana Mainnet — permitindo bridge de **LUNC** e **USTC** de forma descentralizada e sem custódia.

O custo principal é o **rent-exempt reserve** exigido pelo Solana para manter programas on-chain. Após o deploy inicial, qualquer reconfiguração futura via governança custa apenas uma taxa de transação mínima (~0.00025 SOL), sem necessidade de novos deploys.

---

## 1. O Que Já Foi Feito — Investimento Pessoal

Antes de solicitar qualquer recurso à comunidade, todo o trabalho de integração e configuração nas redes **Ethereum, BSC e Terra Classic** foi realizado e custeado integralmente com recursos próprios. **Não será solicitada nenhuma compensação por estes custos já incorridos.**

### 1.1 Terra Classic — ~20 Contratos Deployados (Custo Próprio)

O Hyperlane **não tinha nenhuma integração com a Terra Classic**. Foi necessário deployar toda a infraestrutura do zero:

| Grupo | Contratos | Descrição |
|-------|-----------|-----------|
| Core Hyperlane | Mailbox, ISM, IGP, Hook, Validator Announce | Base do protocolo cross-chain |
| Warp Routes | CwHypNative (LUNC), CwHypNative (USTC), CwHypCw20 (múltiplos tokens) | Rotas de bridge |
| Governança | Propostas on-chain para configuração e ownership transfer | Controle descentralizado |

Os 13 contratos do core Hyperlane foram deployados na Terra Classic Mainnet (columbus-5), cobrindo toda a infraestrutura necessária para comunicação cross-chain com Ethereum, BSC e Solana:

| # | Contrato | Função | Endereço |
|---|----------|--------|----------|
| 1 | Mailbox | Hub central de mensagens cross-chain | `terra1qeutmjcnwmhmumv4xlzrqmva0m4usdw6lt7mayk7wfw7gftsv6wq2xnxh5` |
| 2 | Validator Announce | Registro público dos validators | `terra1jg7904q2305f8qm6ph8jz95uez7undc57wd4dgaf9mvfxcw5j9wq3zdn8c` |
| 3 | ISM Multisig — Ethereum | Valida mensagens recebidas da rede ETH (domain 1) | `terra16axf5f8pqjz3kap0hmrwhatav2q8yrngn6f9vrzx0ralypzxw47s9tml5u` |
| 4 | ISM Multisig — BSC | Valida mensagens recebidas da rede BSC (domain 56) | `terra16hqg4napp3vypdvyymzd3sdsc3uewhyctxjng79j67lku27a5r7q4z8lnt` |
| 5 | ISM Multisig — Solana | Valida mensagens recebidas da rede Solana (domain 1399811149) | `terra180s622shslcldkrl93ksaddhnfvvclejvgt70xsz8flphwzc3fcqkn7m09` |
| 6 | ISM Routing | Roteia mensagens para o ISM correto por origem | `terra1gd3re2pmv34ruwlmmhq80qtp6xqt8htgjqdvsj6clzh0wef6s7mqt6p5ka` |
| 7 | Hook Merkle | Gera prova criptográfica de cada mensagem enviada | `terra1edwd2rhpzhl73uyqf24cc8zp0j5leuc72m7dxtmgfcgvpypj6afsryacf5` |
| 8 | IGP | Cobra e gerencia o gas para execução no destino | `terra1f6n8asv4ecqjjhvf57cprgcjwzd4y2mncpp6gcc95gd22mljnrcs3gcgkk` |
| 9 | IGP Oracle | Fornece cotação LUNC/ETH/BNB/SOL para cálculo de fees | `terra14yp4fvjx9llussdy7ghpu3gszrdfr0q3v53qcy4lkxzs2wc5dngq9zlux2` |
| 10 | Hook Aggregate #1 | Agrega Hook Merkle + IGP (fluxo padrão) | `terra1vtxef5jzax9uaktygay7nnl48akxekt94yg6ak4xa7unawp3du2qevkgde` |
| 11 | Hook Pausable | Permite pausar emergencialmente o envio de mensagens | `terra162q4qzmdy5rutkpkxwqw5xlw0vdjg8c7gw0njnk6ma2s8j52arhsgv3u29` |
| 12 | Hook Fee | Cobra taxa fixa por mensagem enviada | `terra1w8923j0nfvahxcsllqqslwqc0wj22673tf25exwx2vm8dag2a86sk2mdv0` |
| 13 | Hook Aggregate #2 | Agrega Hook Pausable + Fee (fluxo obrigatório) | `terra1n5wfxj38y5ejkh9kkz4ud7t6gqqshzhhhcu97j2j0kfa4359za8sdsqexu` |

### Binários Uploadados (Code IDs)

Antes de instanciar os contratos, foi necessário fazer o upload de **20 binários WASM** na rede Terra Classic. Cada upload é uma transação on-chain independente:

| # | Binário | Code ID | TX Hash |
|---|---------|---------|---------|
| 1 | hpl_mailbox | 11371 | `EE52306E16EB9A3D434219ECA0BDF838761B6ED7FDA4EBCA27E6072EAF7F3246` |
| 2 | hpl_validator_announce | 11372 | `EA29FACCCDFED7F54E5C7CC28E631C9DCD6EF3B6711BDED6611C6D6062E3C435` |
| 3 | hpl_ism_aggregate | 11373 | `7DD1BDB4EC4B57DBAC835087E1328EB6B201EF07BB5C4C5850A92A9FE3B615AA` |
| 4 | hpl_ism_multisig | 11374 | `B0F1C5CF22F5A55185E9CC79DFBF1DB97681BABAFC98ECC7F16F1EFF5AB3C1D1` |
| 5 | hpl_ism_pausable | 11375 | `6F5283B1D2FF2C2F8AB3E3F7209A3BDBA4E5916621B2C596A7A2946D07696A58` |
| 6 | hpl_ism_routing | 11376 | `523D8DD5AADDFD533F8C61AC651F6DAC76E88E8625FE9364D8035381912E1A9A` |
| 7 | hpl_igp | 11377 | `C81D18B9C7729209D379E929B85BFBC2FAF410748ADCF6F320541CFFBF19686E` |
| 8 | hpl_hook_aggregate | 11378 | `97814830E9459ABE12A99C82F8B6D65AF28282EDEB1B56B5C27BA83A0F51F681` |
| 9 | hpl_hook_fee | 11379 | `4E08DA612B3E89AC5CA71CF3B4099B3B1B5800190B814EF65F92A7327B839C51` |
| 10 | hpl_hook_merkle | 11380 | `F8004659796F3EED60623944C4A9C6938975FF72B0D626BE379BC994B7058D29` |
| 11 | hpl_hook_pausable | 11381 | `0694354D4312B965F45D4ED14372925D23AD6F0F1A217245E9EDFCFECE699F85` |
| 12 | hpl_hook_routing | 11382 | `6799A20AFD9C69F7D3BB41B078EE4FBDC5241CC0B41C192721F9325B2A66696A` |
| 13 | hpl_hook_routing_custom | 11383 | `56300AD82FB441094678272A34B1AF131AC69DF04277242FD17C1758F797E574` |
| 14 | hpl_hook_routing_fallback | 11384 | `8B18DB2D65A81F40A4AB896E9C58E3BB9C251B272928575EC787EA13B20838D0` |
| 15 | hpl_test_mock_hook | 11385 | `04F546649FC718DCBA701A9767395CEBD120C3DED9A266EE723F9751F60923D7` |
| 16 | hpl_test_mock_ism | 11386 | `EBEB7221C86FAD9C1449713357F78B14E10510AC87C0A46D0BC1EA717ABC4017` |
| 17 | hpl_test_mock_msg_receiver | 11387 | `E1F27D012F1575BC54A4E0A2714FC1A967789BAA5210FCCF6515868D3F56579B` |
| 18 | hpl_igp_oracle | 11388 | `C367D2C70F87D6B10F3CFCF7B3105BCA774C22890B67CE69BB4F36DA759B7E9D` |
| 19 | hpl_warp_cw20 | 11389 | `AD2C0B4E55BA7A3D4817DE9D95CA17A3E6D9B72A61F70B98485C39412D778926` |
| 20 | hpl_warp_native | 11390 | `F5BCFCDE48617B6B4A70E57B7F0B5376FC3B192B343D0A203F46F8627CF54D2D` |

**Total: 20 binários uploadados + 13 contratos instanciados = 33 transações on-chain na Terra Classic**, todas custeadas com recursos próprios.

Para o detalhamento completo de cada contrato, hashes de auditoria e transações de deploy, consulte a documentação completa:  
📄 [HYPERLANE_DEPLOYMENT-MAINNET_EN.md](https://github.com/terra-classic-hyperlane/cw-hyperlane/blob/main/terraclassic/doc/HYPERLANE_DEPLOYMENT-MAINNET_EN.md)

> Todos estes contratos foram deployados diretamente com recursos próprios. Cada hash de transação foi documentado e disponibilizado publicamente para fins de auditoria — qualquer técnico pode verificar que o código original não foi modificado. Ao final de toda a configuração, a conta **owner** será transferida para a conta de governança da Terra Classic (`terra10d07y265gmmuvt4z0w9aw880jnsr700juxf95n`), garantindo controle descentralizado da infraestrutura.

### 1.2 Ethereum e BSC — Configuração Completa (Custo Próprio)

As redes Ethereum e BSC já estão **totalmente configuradas e funcionando**, com todos os contratos de infraestrutura deployados e testados:

| Rede | Contratos Deployados | Custo Aproximado |
|------|---------------------|------------------|
| Ethereum Mainnet | ISM, IGP, Oracle, Hook Aggregation, Warp IGORFAKE | ~$12 USD |
| BSC Mainnet | ISM, IGP, Oracle, Hook Aggregation, Warp IGORFAKE, Warp ZTT | incluído nos ~$12 USD |

> O custo total em ETH e BSC ficou em torno de **$12 USD** na época — valor acessível que pude arcar sem onerar a comunidade.

### 1.3 Por Que Solana É Diferente

No caso das redes EVM (Ethereum/BSC), os contratos de configuração (ISM, IGP, Oracle) custam poucos dólares em gas. No Solana, cada **programa** exige um depósito de rent-exempt proporcional ao tamanho do binário compilado — o que eleva o custo para dezenas de dólares por programa.

| Rede | Custo médio por contrato de configuração | Custo warp por token |
|------|------------------------------------------|----------------------|
| Ethereum / BSC | $1–3 USD | responsabilidade do dono do projeto |
| Terra Classic | ~$0.10 USD (em LUNC) | ~$0.10 USD |
| **Solana** | **$45–200 USD** | **$70–200 USD** |

> **Nota importante:** Nas redes EVM e Terra Classic, o **warp route** (contrato do token em si) é de responsabilidade do dono de cada projeto — a comunidade Terra Classic só arca com os contratos de infraestrutura compartilhada. No caso do Solana, como **LUNC e USTC são tokens nativos da Terra Classic**, cabe à comunidade financiar também os programas warp destes dois tokens.

---

## 2. Contexto e Prova de Conceito

### 2.1 Teste Realizado com IGORFAKE

Para validar a viabilidade técnica antes de solicitar recursos da comunidade, realizei um **teste completo** utilizando o token IGORFAKE (token de teste pessoal):

| Item | Endereço | Valor |
|------|----------|-------|
| Warp Program (fechado) | `Hs4FrEgigJaabS5HtdkzceFdCPNmPhntWbbdWBJcXyCn` | 2.22105432 SOL |
| ProgramData (fechado) | `4emPmRNLtcdZmtJyfSqGteoDJSApVTGaUL37cFrb3auY` | — |
| Mint IGORFAKE | `5s6DL6pYGxLNXNf1U915BLzLxNkRjnWCzqyzEfXuYDQT` | 0.00405768 SOL |
| Buffer ISM (falhou) | `8keKF8ouqxsmQKZ2Yo3RfzGJQxFjk1MDsECCATUd37CV` | 0 SOL |

> **Importante:** Ao acessar o endereço do warp program no explorer, o saldo aparece como zero. Isso ocorre porque após o teste **fechei o programa** com `solana program close`, o que retornou os 2.22 SOL para minha carteira. **O programa não pode mais ser utilizado em nenhuma hipótese** — mesmo o endereço existindo no explorer, o código foi destruído e o programa está inativo. Para qualquer uso futuro é obrigatório subir o binário novamente.

### 2.2 Resultado do Teste

- ✅ Deploy do warp program bem-sucedido
- ✅ Mint do token sintético criado no Solana
- ✅ Rota Terra Classic ↔ Solana configurada e funcional
- ❌ Deploy do ISM falhou por **saldo insuficiente** (necessário ~1.35 SOL, tinha 0.93 SOL)
- ✅ **2.22105432 SOL recuperados** após encerramento do teste
- ⚠️ **0.00114144 SOL permanentemente bloqueados** no program account (limitação do Solana — não recuperável)

---

## 2. Programas a Deployar

### 2.1 Arquitetura dos Programas

O Solana exige que cada programa binário ocupe uma conta com saldo mínimo de rent proporcional ao tamanho do código. Os valores abaixo são calculados com base em dados reais medidos durante o teste:

| # | Programa | Função | Tamanho | Custo Estimado |
|---|----------|---------|---------|----------------|
| 1 | **ISM** (MultisigIsmMessageId) | Valida mensagens recebidas da Terra Classic | 194.344 bytes | ~1.35 SOL |
| 2 | **Warp LUNC** (HypSynthetic) | Bridge de LUNC entre Terra Classic ↔ Solana | 318.944 bytes | ~2.22 SOL |
| 3 | **Warp USTC** (HypSynthetic) | Bridge de USTC entre Terra Classic ↔ Solana | 318.944 bytes | ~2.22 SOL |
| 4 | **IGP** (InterchainGasPaymaster) | Pagamento de gas cross-chain | 248.080 bytes | ~1.73 SOL |
| 5 | **Oracle** (Gas Oracle) | Cotação de preços para cálculo de fees | — | ~0.01 SOL |

> **Nota sobre ISM:** Uma vez deployado, o mesmo ISM é **compartilhado por todos os tokens** (LUNC, USTC e futuros). Não é necessário deployar um ISM por token.

### 2.2 Custo Total

```
Deploy próprio de todos os programas (soberania total da governança):
  ISM:          ~1.35 SOL
  Warp LUNC:    ~2.22 SOL
  Warp USTC:    ~2.22 SOL
  IGP:          ~1.73 SOL
  Oracle:       ~0.01 SOL
  Fees/txs:     ~0.05 SOL
  ──────────────────────────
  Total:        ~7.58 SOL
```

Não utilizaremos os programas nativos do Hyperlane Labs — a comunidade Terra Classic terá **controle total** sobre validators, taxas de gas e configurações de oracle, sem dependência de terceiros.

### 2.3 Custo de Manutenção Futura

Após o deploy inicial, qualquer alteração via governança (mudar validators, ajustar taxas de gas, atualizar oracle) custa apenas:
- **~0.00025 SOL por transação** (fee de rede)
- **Sem novos deploys de programas**

---

## 3. Referências Técnicas

### 3.1 Programas de Referência no Solana Mainnet

| Programa | Endereço | Status |
|----------|----------|--------|
| Mailbox Hyperlane | `E588QtVUvresuXq2KoNEwAmoifCzYGpRBdHByN9KQMbi` | ativo |
| IGP Hyperlane | `BhNcatUDC2D5JTyeaqrdSukiVFsEHK7e3hVmKMztwefv` | ativo |
| IGP Account | `AkeHBbE5JkwVppujCQQ6WuxsVsJtruBAjUo6fDCFp6fF` | ativo |
| ISM Referência | `LwNfVYMDzAe5dCJgA5CipTZcT34Eyf74zLr81K91jxk` | ativo (owner externo) |

### 3.2 Warp Routes já Deployadas (Terra Classic Testnet)

As redes testnet estão operacionais, validando o stack completo:

| Token | Terra Classic Testnet | Solana Testnet |
|-------|----------------------|----------------|
| LUNC | `terra1zlm0h2xu6rhnjchn29hxnpvr74uxxqetar9y75zcehyx2mqezg9slj09ml` | `HNxN3ZSBtD5J2nNF4AATMhuvTWVeHQf18nTtzKtsnkyw` |
| USTC | `terra1rnpvpwvqcf94keldtm2udt4tqhwthpw5cu94m443rz5ue7rvvkjq9nklml` | `7PtxvK2AB8TmhygeWDyVjkCKvBST16QFb8j6tdSLtoha` |

### 3.3 Configuração dos Validators

O protocolo opera com **múltiplos validators independentes** para garantir descentralização e segurança. O validator utilizado durante os testes foi o próprio deployer, com threshold 1/1. À medida que os validators externos concluem sua infraestrutura, o ISM será atualizado para incluí-los — operação que custa apenas uma taxa de transação, sem necessidade de novo deploy.

| Validator | Status | Endereço |
|-----------|--------|----------|
| Deployer (teste) | ✅ Ativo desde o início | `0x71b2b8c36a0c76b74be92eb7915e26a69b3b03eb` |
| @Thomas_HighStakes | ✅ Infraestrutura concluída | aguardando inclusão no ISM |
| Validator 3 | 🔄 Configurando infraestrutura | — |
| Validator 4 | 🔄 Configurando infraestrutura | — |

> O ISM será atualizado para o conjunto completo de validators assim que todos concluírem a configuração de infraestrutura. O threshold final será definido em conjunto com os validators. Esta atualização não requer nenhum novo deploy de programa — apenas uma transação de configuração.

| Campo | Valor atual (teste) |
|-------|---------------------|
| Domain Terra Classic Mainnet | `1325` (columbus-5) |
| Threshold atual | 1/1 (somente deployer) |
| Threshold alvo | a definir com os 4 validators |

---

## 4. O que Acontece Após o Deploy

```
Terra Classic (LUNC/USTC)          Solana Mainnet
        │                                │
        │  1. lock/burn no warp TC       │
        │ ─────────────────────────────► │
        │                                │  2. ISM verifica assinatura
        │                                │     do validator
        │                                │  3. mint/release no warp Solana
        │                                │
        │  4. burn no warp Solana        │
        │ ◄───────────────────────────── │
        │  5. release no warp TC         │
        │                                │
```

- **Warp LUNC/USTC:** contratos que travam tokens na origem e mintam tokens sintéticos no destino
- **ISM:** verifica criptograficamente que a mensagem veio da Terra Classic (assinatura do validator)
- **IGP:** cobra a taxa de gas para executar a transação no destino
- **Oracle:** fornece a cotação SOL/LUNC para cálculo correto das fees

---

## 5. Solicitude de Recursos

### 5.1 Valor Solicitado

| Item | Valor (SOL) | Observação |
|------|-------------|------------|
| ISM program | 1.35 | Deploy único, compartilhado por todos os tokens |
| Warp LUNC | 2.22 | Necessário por token |
| Warp USTC | 2.22 | Necessário por token |
| IGP program | 1.73 | Controle de governança total |
| Oracle + contas PDAs | 0.06 | Init + configurações |
| Buffer de segurança | 0.50 | Fees, retentativas e imprevistos |
| Reserva para eventualidades | 1.00 | Imprevistos, flutuação de preço do SOL |
| **Total em SOL** | **9.08 SOL** | |

### 5.2 Conversão para LUNC

> ✏️ *Editado em 2026-06-08 — valor original em SOL mantido acima para referência técnica; valor de envio corrigido para LUNC conforme solicitação da comunidade.*

~~A proposta original solicitava o envio direto de **9.08 SOL**.~~

A comunidade enviará **LUNC** diretamente para minha carteira. O valor foi calculado utilizando **$70/SOL** como referência conservadora, dado que o SOL apresenta alta volatilidade e a proposta pode levar dias para ser aprovada.

| Referência | Valor |
|-----------|-------|
| Preço SOL utilizado (conservador) | $70.00 USD |
| ~~Preço LUNC original (publicação)~~ | — |
| Preço LUNC em 2026-06-08 | $0.00007006 USD |
| Total em USD (9.08 SOL × $70) | $635.60 USD |
| ~~Total original~~ | ~~9.08 SOL~~ |
| **Total solicitado em LUNC** | **≈ 9,072,794 LUNC** |

> **Sobre a volatilidade:** O preço do SOL em 2026-06-08 era de $66.87 USD. Foi utilizado $70/SOL para cobrir eventual alta antes da aprovação. No dia da compra do SOL publicarei o TX da transação. **Caso sobre LUNC**, o valor será enviado diretamente de volta à comunidade — **não será convertido, será devolvido como LUNC**.

### 5.3 Destino dos Recursos

Os recursos deverão ser enviados em **LUNC** para a carteira Terra Classic:

```
terra1run9wz09uhh6pu7ggcwwetrgye4wu7wn26mawp
```

O LUNC recebido será convertido para SOL no dia da compra e utilizado exclusivamente no deploy dos programas. A conversão será documentada com o hash da transação para prestação de contas completa. Qualquer LUNC não utilizado será devolvido diretamente à comunidade.

---

## 6. Transparência e Prestação de Contas

- Todo o código está disponível publicamente: [github.com/terra-classic-hyperlane/cw-hyperlane](https://github.com/terra-classic-hyperlane/cw-hyperlane)
- Os endereços dos programas deployados serão publicados imediatamente após o deploy
- Os scripts de deploy são auditáveis na pasta `terraclassic/` do repositório
- Os programas deployados serão transferidos para controle da governança (`terra10d07y265gmmuvt4z0w9aw880jnsr700juxf95n`)

### 6.1 Prestação de Contas da Compra de SOL

Será publicado um relatório completo contendo:

1. **TX da compra LUNC → SOL** — hash da transação de conversão dos LUNC recebidos da comunidade para SOL, comprovando o câmbio utilizado e o valor recebido
2. **TX de cada deploy** — hash de cada transação de deploy no Solana Mainnet, com o endereço do programa resultante e o custo exato em SOL
3. **Saldo final da carteira** — extrato público da carteira `BirXd4QDxfq2vx9LGqgXXSgZrjT81rhoFGUbQRWDEf1j` após a conclusão de todos os deploys

**Caso sobre SOL:** qualquer valor remanescente na carteira após o deploy completo será enviado diretamente para a conta de governança da Terra Classic (`terra10d07y265gmmuvt4z0w9aw880jnsr700juxf95n`). Nenhum valor ficará retido.

---

## 7. Cronograma

| Etapa | Prazo estimado |
|-------|----------------|
| Aprovação da proposta | — |
| Recebimento dos recursos | Imediato após aprovação |
| Deploy ISM | Dia 1 |
| Deploy Warp LUNC | Dia 1 |
| Deploy Warp USTC | Dia 2 |
| Deploy IGP + Oracle | Dia 2 |
| Testes finais mainnet | Dia 3 |
| Entrega à governança | Dia 3-5 |

---

## 8. Perguntas Frequentes

**Por que não reutilizar os programas do teste IGORFAKE?**  
O programa `Hs4FrEgigJaabS5HtdkzceFdCPNmPhntWbbdWBJcXyCn` foi fechado com `solana program close` para recuperar os SOL investidos. Após o fechamento, o programa é **permanentemente inativo** — o endereço pode ser visualizado no explorer mas não possui código executável. É necessário subir o binário novamente com um novo endereço.

**O rent é perdido?**  
Não. O rent fica bloqueado enquanto o programa existe e é **totalmente recuperável** via `solana program close`. Exceção: 0.00114144 SOL do program account pointer (irrecuperável por limitação do Solana — valor residual insignificante).

**Por que o Solana cobra tanto?**  
O rent-exempt é uma garantia de disponibilidade permanente dos dados na rede. É um custo único de infraestrutura, não uma taxa recorrente.

**E se precisar atualizar os validators?**  
Basta uma transação de ~0.00025 SOL na mesma ISM já deployada. Não é necessário deploy de nenhum programa novo.

---

*Proposta elaborada por Igor Veras — desenvolvedor Hyperlane Terra Classic*  
