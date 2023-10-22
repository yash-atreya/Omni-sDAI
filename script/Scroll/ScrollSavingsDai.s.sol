// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "forge-std/Script.sol";
import "../../src/Scroll/ScrollSavingsDai.sol";

/**
 * @title Scroll Savings Dai Script
 * @author Yash Atreya
 * @notice Used deploy the Scroll Savings Dai contract
 * @dev Requires the `Dai` address on Scroll
 */
contract ScrollSavingsDaiScript is Script {
    function run() external {
        vm.startBroadcast();

        // Deploy Scroll Savings Dai
        ScrollSavingsDai scrollSavingsDai = new ScrollSavingsDai(
            vm.envAddress("S_DAI")
        );
        console.log("Deployed Scroll Savings Dai at %s", address(scrollSavingsDai));

        vm.stopBroadcast();
    }
}
