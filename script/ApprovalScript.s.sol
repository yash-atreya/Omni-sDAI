// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract ApprovalScript is Script {
    IERC20 dai = IERC20(address(0x6B175474E89094C44Da98b954EedeAC495271d0F)); // DAI on Mainnet

    function run() external {
        vm.startBroadcast(vm.envAddress("TEST_RELAYER"));

        // Relayer approves Mainnet/FillerPool to spend
        dai.approve(vm.envAddress("G_FILLER_POOL"), type(uint256).max);

        vm.stopBroadcast();
    }
}
