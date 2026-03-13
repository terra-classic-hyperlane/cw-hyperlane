#!/usr/bin/env bash
# =============================================================================
#  transfer-cw20-terra.sh
#  Transfers CW20 tokens on Terra Classic via CosmWasm
# =============================================================================
set -euo pipefail

# ─── Cores ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

# ─── Default settings (editable) ────────────────────────────────────────────
CW20_CONTRACT="${CW20_CONTRACT:-terra19ujvy60tjeyehjrwlrdpqlp0gxmtt4qv452nwjqc6w6m38pm8xmq22lux3}"
SENDER="${SENDER:-terra12awgqgwm2evj05ndtgs0xa35uunlpc76d85pze}"
RECIPIENT="${RECIPIENT:-terra18lr7ujd9nsgyr49930ppaajhadzrezam70j39k}"
AMOUNT="${AMOUNT:-100000000}"
TOKEN_SYMBOL="${TOKEN_SYMBOL:-XPTO}"

# RPC / LCD for Terra Classic (reads from warp-evm-config.json if it exists)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$SCRIPT_DIR/log"
mkdir -p "$LOG_DIR"
CONFIG_JSON="$SCRIPT_DIR/warp-evm-config.json"

if command -v jq &>/dev/null && [ -f "$CONFIG_JSON" ]; then
    RPC_URL=$(jq -r '.terra_classic.rpc // "https://rpc.terra-classic.hexxagon.dev"' "$CONFIG_JSON")
    LCD_URL=$(jq -r '.terra_classic.lcd // "https://lcd.terra-classic.hexxagon.dev"' "$CONFIG_JSON")
    CHAIN_ID=$(jq -r '.terra_classic.chain_id // "rebel-2"' "$CONFIG_JSON")
else
    RPC_URL="https://rpc.terra-classic.hexxagon.dev"
    LCD_URL="https://lcd.terra-classic.hexxagon.dev"
    CHAIN_ID="rebel-2"
fi

GAS_PRICE="${GAS_PRICE:-28.325}"
GAS_DENOM="${GAS_DENOM:-uluna}"
GAS_MULTIPLIER="${GAS_MULTIPLIER:-1.4}"

# ─── Banner ───────────────────────────────────────────────────────────────────
echo -e ""
echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${CYAN}║      CW20 TRANSFER — TERRA CLASSIC                   ║${RESET}"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════╝${RESET}"
echo -e ""

# ─── Check dependencies ──────────────────────────────────────────────────────
for dep in node jq curl; do
    if ! command -v "$dep" &>/dev/null; then
        echo -e "${RED}❌ Dependency not found: ${dep}${RESET}"
        echo -e "   Install with: sudo apt install ${dep}"
        exit 1
    fi
done

# Locate project node_modules
PROJECT_ROOT="$SCRIPT_DIR"
while [ "$PROJECT_ROOT" != "/" ] && [ ! -f "$PROJECT_ROOT/package.json" ]; do
    PROJECT_ROOT="$(dirname "$PROJECT_ROOT")"
done

if [ ! -d "$PROJECT_ROOT/node_modules/@cosmjs/cosmwasm-stargate" ]; then
    echo -e "${RED}❌ node_modules not found in $PROJECT_ROOT${RESET}"
    echo -e "   Execute: cd $PROJECT_ROOT && yarn install"
    exit 1
fi

echo -e "${GREEN}✅ node_modules found at: ${PROJECT_ROOT}${RESET}"

# ─── Private key ──────────────────────────────────────────────────────────────
if [ -z "${TERRA_PRIVATE_KEY:-}" ]; then
    echo -e ""
    echo -e "${YELLOW}⚠️  TERRA_PRIVATE_KEY not set.${RESET}"
    echo -e "   Option 1: export TERRA_PRIVATE_KEY=\"your_hex_key\""
    echo -e "   Option 2: enter now (will not be displayed):"
    echo -n "   > "
    read -rs TERRA_PRIVATE_KEY
    echo ""
    if [ -z "$TERRA_PRIVATE_KEY" ]; then
        echo -e "${RED}❌ Private key not provided. Aborting.${RESET}"
        exit 1
    fi
fi

# Remove 0x prefix if present
TERRA_PRIVATE_KEY="${TERRA_PRIVATE_KEY#0x}"

# ─── Transaction summary ─────────────────────────────────────────────────────
echo -e ""
echo -e "${BOLD}📋 Transfer details:${RESET}"
echo -e "   ${CYAN}Rede      :${RESET} $CHAIN_ID"
echo -e "   ${CYAN}RPC       :${RESET} $RPC_URL"
echo -e "   ${CYAN}Contrato  :${RESET} $CW20_CONTRACT"
echo -e "   ${CYAN}Token     :${RESET} $TOKEN_SYMBOL"
echo -e "   ${CYAN}Sender    :${RESET} $SENDER"
echo -e "   ${CYAN}Recipient :${RESET} $RECIPIENT"
echo -e "   ${CYAN}Amount    :${RESET} $AMOUNT (base units)"
echo -e ""

# Confirmation
echo -ne "${YELLOW}▶ Confirm the transfer? [y/N]: ${RESET}"
read -r CONFIRM
if [[ ! "$CONFIRM" =~ ^[sStTyY]$ ]]; then
    echo -e "${RED}❌ Transfer cancelled.${RESET}"
    exit 0
fi

echo -e ""
echo -e "${BOLD}⏳ Processing...${RESET}"
echo -e ""

# ─── Inline Node.js script ───────────────────────────────────────────────────
RESULT=$(node --no-warnings - <<EOF
const path = require('path');
const PROJECT_ROOT = "${PROJECT_ROOT}";

// Load modules from project node_modules
const nmPath = path.join(PROJECT_ROOT, 'node_modules');
const { SigningCosmWasmClient } = require(path.join(nmPath, '@cosmjs/cosmwasm-stargate'));
const { DirectSecp256k1Wallet } = require(path.join(nmPath, '@cosmjs/proto-signing'));
const { GasPrice, calculateFee } = require(path.join(nmPath, '@cosmjs/stargate'));
const { fromHex } = require(path.join(nmPath, '@cosmjs/encoding'));

async function main() {
    const rpcUrl   = "${RPC_URL}";
    const contract = "${CW20_CONTRACT}";
    const sender   = "${SENDER}";
    const recipient= "${RECIPIENT}";
    const amount   = "${AMOUNT}";
    const privKeyHex = "${TERRA_PRIVATE_KEY}";
    const gasPrice = GasPrice.fromString("${GAS_PRICE}${GAS_DENOM}");

    // Create wallet from hex private key
    let privKeyBytes;
    try {
        privKeyBytes = fromHex(privKeyHex);
    } catch(e) {
        throw new Error("Invalid private key: " + e.message);
    }

    const wallet = await DirectSecp256k1Wallet.fromKey(privKeyBytes, 'terra');
    const [account] = await wallet.getAccounts();

    // Verify if derived address matches the expected sender
    if (account.address !== sender) {
        process.stderr.write("⚠️  WARNING: address derived from key: " + account.address + "\n");
        process.stderr.write("          configured address (SENDER): " + sender + "\n");
        process.stderr.write("          Using the address derived from the key.\n\n");
    }

    // Connect to client
    const client = await SigningCosmWasmClient.connectWithSigner(rpcUrl, wallet, {
        gasPrice: gasPrice,
    });

    // Check CW20 balance before transfer
    let balanceBefore = "0";
    let balanceRecipientBefore = "0";
    try {
        const res = await client.queryContractSmart(contract, {
            balance: { address: account.address }
        });
        balanceBefore = res.balance || "0";
        const resR = await client.queryContractSmart(contract, {
            balance: { address: recipient }
        });
        balanceRecipientBefore = resR.balance || "0";
    } catch(e) {
        // query may fail on testnets
        process.stderr.write("⚠️  Warning: Failed to query balance: " + e.message + "\n");
    }

    console.log("BALANCE_SENDER_BEFORE=" + balanceBefore);
    console.log("BALANCE_RECIPIENT_BEFORE=" + balanceRecipientBefore);

    // Check if sender has sufficient balance
    try {
        // Use BigInt for large numbers (available in Node.js 10.4+)
        const balanceBig = BigInt(balanceBefore);
        const amountBig = BigInt(amount);
        if (balanceBig < amountBig) {
            throw new Error("Insufficient balance: have " + balanceBefore + ", need " + amount);
        }
    } catch(e) {
        // Fallback: compare string lengths and values for older Node.js
        if (balanceBefore.length < amount.length || 
            (balanceBefore.length === amount.length && balanceBefore < amount)) {
            throw new Error("Insufficient balance: have " + balanceBefore + ", need " + amount);
        }
    }

    // CW20 transfer message
    const transferMsg = {
        transfer: {
            recipient: recipient,
            amount: amount
        }
    };

    // Estimate gas
    let gasEstimate;
    try {
        gasEstimate = await client.simulate(account.address, [
            {
                typeUrl: "/cosmwasm.wasm.v1.MsgExecuteContract",
                value: {
                    sender: account.address,
                    contract: contract,
                    msg: Buffer.from(JSON.stringify(transferMsg)),
                    funds: []
                }
            }
        ], "");
    } catch(e) {
        process.stderr.write("⚠️  Failed to estimate gas: " + e.message + "\n");
        process.stderr.write("   Using default gas: 200000\n");
        gasEstimate = null;
    }

    const gasLimit = gasEstimate ? Math.ceil(gasEstimate * ${GAS_MULTIPLIER}) : 200000;
    const fee = calculateFee(gasLimit, gasPrice);

    console.log("GAS_LIMIT=" + gasLimit);
    console.log("FEE_AMOUNT=" + fee.amount[0].amount + fee.amount[0].denom);

    // Execute transfer
    const result = await client.execute(
        account.address,
        contract,
        transferMsg,
        fee,
        "CW20 transfer via transfer-cw20-terra.sh"
    );

    console.log("TX_HASH=" + result.transactionHash);
    console.log("HEIGHT=" + result.height);
    console.log("GAS_USED=" + result.gasUsed);
    console.log("GAS_WANTED=" + result.gasWanted);
    console.log("SENDER_USED=" + account.address);

    // Check CW20 balance after transfer
    try {
        const resAfter = await client.queryContractSmart(contract, {
            balance: { address: account.address }
        });
        const resRAfter = await client.queryContractSmart(contract, {
            balance: { address: recipient }
        });
        console.log("BALANCE_SENDER_AFTER=" + resAfter.balance);
        console.log("BALANCE_RECIPIENT_AFTER=" + resRAfter.balance);
    } catch(e) {}
}

main().catch(e => {
    process.stderr.write("ERROR: " + e.message + "\n");
    process.exit(1);
});
EOF
)

EXIT_CODE=$?

# ─── Process result ──────────────────────────────────────────────────────────
if [ $EXIT_CODE -ne 0 ]; then
    echo -e "${RED}❌ Transfer failed!${RESET}"
    echo -e "${RED}   Check the logs above for more details.${RESET}"
    exit 1
fi

# Extract variables from Node.js output
TX_HASH=$(echo "$RESULT"             | grep "^TX_HASH="                  | cut -d= -f2)
HEIGHT=$(echo "$RESULT"              | grep "^HEIGHT="                   | cut -d= -f2)
GAS_USED=$(echo "$RESULT"            | grep "^GAS_USED="                 | cut -d= -f2)
GAS_LIMIT=$(echo "$RESULT"           | grep "^GAS_LIMIT="                | cut -d= -f2)
FEE_AMOUNT=$(echo "$RESULT"          | grep "^FEE_AMOUNT="               | cut -d= -f2)
SENDER_USED=$(echo "$RESULT"         | grep "^SENDER_USED="              | cut -d= -f2)
BAL_S_BEFORE=$(echo "$RESULT"        | grep "^BALANCE_SENDER_BEFORE="    | cut -d= -f2)
BAL_S_AFTER=$(echo "$RESULT"         | grep "^BALANCE_SENDER_AFTER="     | cut -d= -f2)
BAL_R_BEFORE=$(echo "$RESULT"        | grep "^BALANCE_RECIPIENT_BEFORE=" | cut -d= -f2)
BAL_R_AFTER=$(echo "$RESULT"         | grep "^BALANCE_RECIPIENT_AFTER="  | cut -d= -f2)

# ─── Final report ────────────────────────────────────────────────────────────
echo -e ""
echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${GREEN}║       ✅ TRANSFER COMPLETED SUCCESSFULLY!            ║${RESET}"
echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════╝${RESET}"
echo -e ""
echo -e "${BOLD}📦 Transaction:${RESET}"
echo -e "   ${CYAN}TX Hash   :${RESET} ${BOLD}${TX_HASH}${RESET}"
echo -e "   ${CYAN}Block     :${RESET} $HEIGHT"
echo -e "   ${CYAN}Gas used  :${RESET} ${GAS_USED} / ${GAS_LIMIT}"
echo -e "   ${CYAN}Fee paid  :${RESET} $FEE_AMOUNT"
echo -e ""
echo -e "${BOLD}💰 Balances:${RESET}"
echo -e "   ${CYAN}Sender   (before) :${RESET} $BAL_S_BEFORE $TOKEN_SYMBOL"
echo -e "   ${CYAN}Sender   (after)  :${RESET} $BAL_S_AFTER $TOKEN_SYMBOL"
echo -e "   ${CYAN}Recipient (before):${RESET} $BAL_R_BEFORE $TOKEN_SYMBOL"
echo -e "   ${CYAN}Recipient (after) :${RESET} $BAL_R_AFTER $TOKEN_SYMBOL"
echo -e ""
echo -e "${BOLD}🔗 Verify on Explorer:${RESET}"
echo -e "   ${CYAN}https://finder.terra-classic.hexxagon.dev/testnet/tx/${TX_HASH}${RESET}"
echo -e ""

# ─── Save report ─────────────────────────────────────────────────────────────
REPORT_FILE="$LOG_DIR/TRANSFER-CW20-$(date +%Y%m%d-%H%M%S).txt"
cat > "$REPORT_FILE" <<REPORT
CW20 TRANSFER — TERRA CLASSIC
==============================
Date/Time  : $(date "+%Y-%m-%d %H:%M:%S")
Chain      : $CHAIN_ID
RPC        : $RPC_URL

PARAMETERS
----------
Token      : $TOKEN_SYMBOL
Contract   : $CW20_CONTRACT
Sender     : $SENDER_USED
Recipient  : $RECIPIENT
Amount     : $AMOUNT

RESULT
------
TX Hash    : $TX_HASH
Block      : $HEIGHT
Gas Used   : $GAS_USED / $GAS_LIMIT
Fee        : $FEE_AMOUNT

BALANCES
--------
Sender before   : $BAL_S_BEFORE $TOKEN_SYMBOL
Sender after    : $BAL_S_AFTER $TOKEN_SYMBOL
Recipient before: $BAL_R_BEFORE $TOKEN_SYMBOL
Recipient after : $BAL_R_AFTER $TOKEN_SYMBOL

Explorer: https://finder.terra-classic.hexxagon.dev/testnet/tx/$TX_HASH
REPORT

echo -e "${GREEN}📄 Report saved: ${REPORT_FILE}${RESET}"
echo -e ""
