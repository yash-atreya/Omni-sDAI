import { createPublicClient, http, parseAbiItem } from 'viem'
import { mainnet, scroll } from 'viem/chains'

const ETH_RPC="http://localhost:8545"
const SCROLL_RPC="http://localhost:9000"

const ethClient = createPublicClient({
  chain: mainnet,
  transport: http(ETH_RPC), 
});

const scrollClient = createPublicClient({
    chain: scroll,
    transport: http(SCROLL_RPC),
});

async function main() {
    console.log(`Relayer started.`)
    // EVENT LISTENERS

    // event Deposited(address indexed depositor, uint256 indexed amount)
    const depositUnsub = await _subscriptionEvent(process.env.S_SAVINGS_DAI, 'event Deposited(address indexed depositor, uint256 indexed amount)', (log) => {
        console.log(`Received event from address ${process.env.S_SAVINGS_DAI}`)
        console.log(log)
    }, false)

    // scrollClient.watchEvent({
    //     event: parseAbiItem('event Deposited(address indexed depositor, uint256 indexed amount)'),
    //     address: process.env.S_SAVINGS_DAI,
    //     onLogs: (log) => {
    //         console.log(`Received event from address ${process.env.S_SAVINGS_DAI}`)
    //         console.log(log)
    //     },
    // });

    // // event WithdrawalRequest(address indexed withdrawer, uint256 indexed amount);
    // const withdrawalRequestUnsub = await _subscriptionEvent('event WithdrawalRequest(address indexed withdrawer, uint256 indexed amount)', (log) => {
    //     console.log(log)
    // }, false)
    
}

const _subscriptionEvent = async (address, event, onLog, isEthClient) => {
    let unwatch;
    if(isEthClient) {
        unwatch = ethClient.watchEvent({
            event: parseAbiItem(event),
            onLogs: onLog,
        });
    } else {
        unwatch = scrollClient.watchEvent({
            event: parseAbiItem(event),
            onLogs: onLog,
        });
    }

    return unwatch;
}



main();

