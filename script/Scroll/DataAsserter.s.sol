// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "forge-std/Script.sol";
import "../../src/Goerli/DataAsserter.sol";
import "../../src/Scroll/ScrollSavingsDai.sol";
// Deploy Script for DataAsserter

contract ScrollDataAsserterScript is Script {
    function run() external {
        vm.startBroadcast();

        // Deploy DataAsserter
        DataAsserter dataAsserter = new DataAsserter(
            vm.envAddress("S_DEFAULT_CURRENCY"),
            vm.envAddress("S_OOV3"),
            vm.envAddress("S_SAVINGS_DAI"),
            vm.envAddress("S_FILLER_POOL")
        );
        console.log("Deployed Scroll DataAsserter at %s", address(dataAsserter));

        ScrollSavingsDai scrollSavingsDai = ScrollSavingsDai(vm.envAddress("S_SAVINGS_DAI"));
        scrollSavingsDai.setDataAsserter(address(dataAsserter));
        console.log("Set DataAsserter address in Scroll Savings Dai to %s", address(dataAsserter));
        vm.stopBroadcast();
    }
}
