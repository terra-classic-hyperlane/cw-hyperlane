# Update IGP Oracle via Governance

Since the IGP Oracle has the governance module (`terra10d07y265gmmuvt4z0w9aw880jnsr700juxf95n`) as owner, you need to create a governance proposal to update the `token_exchange_rate`.

## Important Addresses

- **IGP Oracle**: `terra18tyqe79yktac6p3alv3f49k06xqna2q52twyaflrz55qka9emhrs30k3hg`
- **Governance Module**: `terra10d07y265gmmuvt4z0w9aw880jnsr700juxf95n`

## Creating a Governance Proposal

### Method 1: Using the Script (Recommended)

```bash
# Run the script to generate the proposal file
bash script/create-igp-oracle-proposal.sh

# The script will create the file: proposal-igp-oracle-update.json
```

### Method 2: Create Manually

Create a file `proposal-igp-oracle-update.json`:

```json
{
  "messages": [
    {
      "@type": "/cosmwasm.wasm.v1.MsgExecuteContract",
      "sender": "terra10d07y265gmmuvt4z0w9aw880jnsr700juxf95n",
      "contract": "terra18tyqe79yktac6p3alv3f49k06xqna2q52twyaflrz55qka9emhrs30k3hg",
      "msg": {
        "set_remote_gas_data_configs": {
          "configs": [
            {
              "remote_domain": 97,
              "token_exchange_rate": "14794529576536",
              "gas_price": "50000000"
            }
          ]
        }
      },
      "funds": []
    }
  ],
  "metadata": "Update IGP Oracle exchange rate for BSC Testnet (domain 97) to reflect current BNB price ($897.88). This fixes the gas cost calculation from ~$1512 to ~$0.0045 per cross-chain transfer.",
  "deposit": "500000uluna",
  "title": "Update IGP Oracle Exchange Rate for BSC Testnet",
  "summary": "Update token_exchange_rate from 1805936462255558 to 14794529576536 for BSC Testnet (domain 97) to correctly calculate gas costs. Current rate results in ~$1512 per transfer (incorrect). New rate will result in ~74 LUNC (~$0.0045) per transfer, accurately covering 0.000005 BNB gas cost on BSC.",
  "expedited": false
}
```

## Submit the Proposal

```bash
terrad tx gov submit-proposal proposal-igp-oracle-update.json \
  --from hypelane-val-testnet \
  --keyring-backend file \
  --chain-id rebel-2 \
  --node https://rpc.luncblaze.com:443 \
  --gas auto \
  --gas-adjustment 1.5 \
  --gas-prices 28.5uluna \
  --yes
```

**Note:** The initial deposit is 0.5 LUNC (500000uluna), which is less than the minimum deposit of 1 LUNC (1000000uluna). The proposal will enter the **deposit period** and will need to reach the minimum deposit of 1 LUNC before entering the voting period. Other users can contribute additional deposits.

## Deposit Period

After submitting, the proposal will enter the **deposit period**. The initial deposit is 1 LUNC (1,000,000 uluna), which is the minimum deposit. If you want other users to be able to contribute, you can use a smaller initial deposit.

### Check Proposal Status

```bash
terrad query gov proposal <PROPOSAL_ID> \
  --chain-id rebel-2 \
  --node https://rpc.luncblaze.com:443
```

**Expected status:** `DepositPeriod` (deposit period)

### Add Deposit (if necessary)

Since the initial deposit is 0.5 LUNC (500,000 uluna) and the minimum is 1 LUNC (1,000,000 uluna), you or other users need to add another 0.5 LUNC:

```bash
terrad tx gov deposit <PROPOSAL_ID> 500000uluna \
  --from hypelane-val-testnet \
  --keyring-backend file \
  --chain-id rebel-2 \
  --node https://rpc.luncblaze.com:443 \
  --gas-prices 28.5uluna \
  --yes
```

**Note:** The minimum deposit is 1,000,000 uluna (1 LUNC). When the total deposits reach this value, the proposal will automatically enter the voting period. You can check the total deposits with:
```bash
terrad query gov deposits <PROPOSAL_ID> \
  --chain-id rebel-2 \
  --node https://rpc.luncblaze.com:443
```

## Vote on the Proposal

After the deposit period and when the proposal enters the **voting period** (status `VotingPeriod`), note the `PROPOSAL_ID` and vote:

```bash
terrad tx gov vote <PROPOSAL_ID> yes \
  --from hypelane-val-testnet \
  --keyring-backend file \
  --chain-id rebel-2 \
  --node https://rpc.luncblaze.com:443 \
  --gas-prices 28.5uluna \
  --yes
```

## Check Proposal Status

```bash
# View proposal details
terrad query gov proposal <PROPOSAL_ID> \
  --chain-id rebel-2 \
  --node https://rpc.luncblaze.com:443

# View all proposals
terrad query gov proposals \
  --chain-id rebel-2 \
  --node https://rpc.luncblaze.com:443

# View proposal deposits
terrad query gov deposits <PROPOSAL_ID> \
  --chain-id rebel-2 \
  --node https://rpc.luncblaze.com:443
```

**Possible statuses:**
- `DepositPeriod`: Proposal is in the deposit period (waiting to reach the minimum)
- `VotingPeriod`: Proposal is in the voting period
- `Passed`: Proposal was approved
- `Rejected`: Proposal was rejected

## Verify Execution

After the proposal is approved and executed, verify that the exchange_rate was updated:

```bash
IGP_ORACLE="terra18tyqe79yktac6p3alv3f49k06xqna2q52twyaflrz55qka9emhrs30k3hg"

# Check configuration for domain 97
terrad query wasm contract-state smart ${IGP_ORACLE} \
  '{"remote_gas_data":{"remote_domain":97}}' \
  --chain-id rebel-2 \
  --node https://rpc.luncblaze.com:443
```

**Expected output:**
```json
{
  "token_exchange_rate": "14794529576536",
  "gas_price": "50000000"
}
```

## Exchange Rate Calculation

**With BNB @ $897.88:**
- Cost in BNB: 0.000005 BNB
- Cost in USD: 0.000005 × $897.88 = $0.004489
- Cost in LUNC: $0.004489 / $0.00006069 = 73.97 LUNC
- Cost in uluna: 73,972,647 uluna
- Exchange rate: `(73,972,647 × 10^18) / (100000 × 50000000) = 14794529576536`

**Note:** If the BNB price changes significantly, you will need to update the exchange_rate again via governance.
