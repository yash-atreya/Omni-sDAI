// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MintMainnetDai is Script {
    IERC20 dai = IERC20(address(0x6B175474E89094C44Da98b954EedeAC495271d0F)); // DAI on Mainnet
    address daiHolder = address(0x075e72a5eDf65F0A5f44699c7654C1a76941Ddc8); // Largest Dai holder on Mainnet
    address relayer = vm.envAddress("TEST_RELAYER"); // Relayer

    function run() external {
        vm.startBroadcast(daiHolder);

        // Mint Dai
        dai.transfer(relayer, 10000 * 10 ** 18); // Transfer 10000 Dai to relayer

        vm.stopBroadcast();
    }
}
