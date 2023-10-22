import { createTestClient, createWalletClient, http, parseUnits } from "viem";
import {scroll, mainnet, foundry} from "viem/chains";
import { privateKeyToAccount } from "viem/accounts";

// ABIs
import ScrollSavingsDaiABI from "./abi/ScrollSavingsDai.json";
import ScrollDaiABI from "./abi/ScrollDai.json";
import FillerPoolABI from "./abi/FillerPool.json";

const daiHolder = "0x075e72a5eDf65F0A5f44699c7654C1a76941Ddc8"; // Largest Dai holder on mainnet
const depositorScroll = createWalletClient({
    key: 'Depositor',
    name: 'Deposit Wallet Client',
    account: privateKeyToAccount(process.env.TEST_DEPOSITOR_PK),
    chain: scroll,
    transport: http(process.env.SCROLL_RPC),
})

const relayerMainnet = createWalletClient({
    key: 'Relayer',
    name: 'Relayer Wallet Client',
    account: privateKeyToAccount(process.env.TEST_RELAYER_PK),
    chain: mainnet,
    transport: http(process.env.ETH_RPC),
})

const anvilMainnet = createTestClient({
    chain: foundry,
    mode: 'anvil',
    transport: http('http://localhost:8545'),
})

async function main() {
    let amount = 100 * 10 ** 18; // 100 wDai
    // _mintDai(amount);
    // await _approveContract(process.env.S_DAI, process.env.S_SAVINGS_DAI, amount, ScrollDaiABI, false);
    // _depositOnScroll(amount);
    // _mintDai(process.env.MAINNET_DAI, process.env.TEST_RELAYER, amount, ScrollDaiABI, true);
    
}

function _depositOnScroll(amount) {
    depositorScroll.writeContract({
        abi: ScrollSavingsDaiABI,
        address: process.env.S_SAVINGS_DAI,
        functionName: "deposit",
        args: [amount],
    }).then(tx => {
        console.log(`Deposited ${amount} wei of wDai to Scroll Savings Dai.`);
        console.log(`Transaction hash: ${tx}`);
    })
}

async function _fillDeposit(hash, amount, depositor, relayer, token, fee) {
    // Relayer needs to have Dai on mainnet
    // Relayer needs to approve Mainnet/FillerPool to spend Dai // 100 wDai
    relayerMainnet.writeContract({
        // abi: FillerPoolABI,
        address: process.env.G_FILLER_POOL,
        functionName: "fillDeposit",
        args: [hash, amount, depositor, token, fee],
    }).then(tx => {
        console.log(`Filled deposit ${hash} with ${amount} Dai.`);
        console.log(`Transaction hash: ${tx}`);
    });
}

async function _approveContract(token, spender, amount, abi, isEthClient) {
    if(isEthClient) {
        const txn = await relayerMainnet.writeContract({
            abi: abi,
            address: token,
            functionName: "approve",
            args:[spender, amount],
        })
        console.log(`Approved ${spender} to spend ${amount} Dai.`);
        console.log(`Transaction hash: ${txn}`);
        return;
    } else {
        const txn = await depositorScroll.writeContract({
            abi: abi,
            address: token,
            functionName: "approve",
            args:[spender, amount],
        })
        console.log(`Approved ${spender} to spend ${amount} wDai.`);
        console.log(`Transaction hash: ${txn}`);
        return;
    }
}

const _mintDai = async (token, receiver, amount, abi, isEthClient) => {
    if(isEthClient) {
        const txn = await relayerMainnet.writeContract({
            abi: abi,
            address: token,
            functionName: "mint",
            args: [receiver, amount],
        })
        console.log(`Minted ${amount} Dai.`)
        console.log(`Transaction hash: ${txn}`)
        return;
    } else {
        const txn = await depositorScroll.writeContract({
            abi: abi,
            address: token,
            functionName: "mint",
            args: [receiver, amount],
        })
        console.log(`Minted ${amount} Dai.`)
        console.log(`Transaction hash: ${txn}`)
        return;
    }
}

main()