// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract WrappedDaiScript is Script {
    function run() external {
        vm.startBroadcast();

        // Deploy Wrapped Dai
        WrappedDai wrappedDai = new WrappedDai("Wrapped Dai", "wDAI");
        console.log("Wrapped Dai deployed at address: %s", address(wrappedDai));

        // Mint 1000 Wrapped Dai to depositor and relayer for testing
        wrappedDai.mint(vm.envAddress("TEST_DEPOSITOR"), 1000 * 10 ** 18);
        wrappedDai.mint(vm.envAddress("TEST_RELAYER"), 1000 * 10 ** 18);
        console.log("Minted 1000 Wrapped Dai to depositor and relayer");
        console.log("Depositor Wrapped Dai balance: %s", wrappedDai.balanceOf(vm.envAddress("TEST_DEPOSITOR")));
        console.log("Relayer Wrapped Dai balance: %s", wrappedDai.balanceOf(vm.envAddress("TEST_RELAYER")));

        vm.stopBroadcast();
    }
}

contract WrappedDai is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address _receiver, uint256 _amount) external {
        _mint(_receiver, _amount);
    }

    function burn(address _receiver, uint256 _amount) external {
        _burn(_receiver, _amount);
    }
}
