// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "forge-std/Script.sol";
import "../../src/Goerli/DataAsserter.sol";

// Deploy Script for DataAsserter
contract DataAsserterScript is Script {
    function run() external {
        vm.startBroadcast();

        // Deploy DataAsserter
        DataAsserter dataAsserter = new DataAsserter(
            vm.envAddress("G_DEFAULT_CURRENCY"),
            vm.envAddress("G_OOV3"),
            vm.envAddress("G_SAVINGS_DAI"),
            vm.envAddress("G_FILLER_POOL")
        );
        console.log("Deployed DataAsserter at %s", address(dataAsserter));

        vm.stopBroadcast();
    }
}
