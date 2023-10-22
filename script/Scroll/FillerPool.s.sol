// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "forge-std/Script.sol";
import "../../src/Goerli/FillerPool.sol";

contract ScrollFillerPoolScript is Script {
    function run() external {
        vm.startBroadcast();

        // Deploy FillerPool
        FillerPool fillerPool = new FillerPool(vm.envAddress("S_SAVINGS_DAI"));
        console.log("Deployed Scroll FillerPool at %s", address(fillerPool));

        vm.stopBroadcast();
    }
}
