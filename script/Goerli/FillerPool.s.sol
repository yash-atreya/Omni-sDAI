// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "forge-std/Script.sol";
import "../../src/Goerli/FillerPool.sol";

contract FillerPoolScript is Script {
    function run() external {
        vm.startBroadcast();

        // Deploy FillerPool
        FillerPool fillerPool =
            new FillerPool(vm.envOr("G_SAVINGS_DAI", address(0x83F20F44975D03b1b09e64809B757c47f942BEeA)));
        console.log("Deployed FillerPool at %s", address(fillerPool));

        vm.stopBroadcast();
    }
}
