// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "forge-std/Script.sol";
import "../../src/Goerli/DataAsserter.sol";
import "../../src/Goerli/FillerPool.sol";
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
        console.log("Deployed Goerli DataAsserter at %s", address(dataAsserter));

        FillerPool fillerPool = FillerPool(vm.envAddress("G_FILLER_POOL"));
        // Set DataAsserter in FillerPool
        fillerPool.setDataAsserter(vm.envOr("G_DATA_ASSERTER", address(0x0)));
        console.log("Set DataAsserter in FillerPool to %s", address(dataAsserter));
        console.log("FillerPool DataAsserter is %s", fillerPool.dataAsserter());

        vm.stopBroadcast();
    }
}
