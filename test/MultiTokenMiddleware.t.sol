// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import "forge-std/Test.sol";
import "../src/MultiTokenMiddleware.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../src/SavingsDai.sol";

contract MultiTokenMiddlewareTest is Test {
    // Users
    address alice = address(0x1);
    address bob = address(0x2);

    // Tokens
    IERC20 immutable USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IERC20 immutable DAI = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    IERC20 immutable WETH = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    // Contracts
    MultiTokenMiddleware multiTokenMiddleware;
    ISwapRouter swapRouter = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564); // Uniswap v3 router
    SavingsDai sDAIVault = SavingsDai(0x83F20F44975D03b1b09e64809B757c47f942BEeA);

    function setUp() public {
        vm.createSelectFork("http://localhost:8545");
        // Give alice and bob some USDC and ETH
        vm.deal(alice, 10000 ether);
        vm.deal(bob, 100 ether);
        deal(address(USDC), alice, 1000, true); // 1000 USDC to alice
        vm.prank(alice);
        address(WETH).call{value: 1000 ether}(
            abi.encodeWithSignature("deposit()") // Deposit ETH into WETH
        ); // 1000 ETH to alice
        assertTrue(WETH.balanceOf(alice) >= 1000 ether);
        multiTokenMiddleware = new MultiTokenMiddleware();
    }

    function test_swapAndDepositUSDC() public {
        // Approve USDC for contract
        vm.prank(alice);
        TransferHelper.safeApprove(address(USDC), address(multiTokenMiddleware), 100);
        // Swap USDC for sDAI
        vm.prank(alice);
        multiTokenMiddleware.swapAndDeposit(100, 100, block.timestamp + 3, address(USDC));
        // Check that alice has 900 USDC and some sDAI
        assertEq(USDC.balanceOf(alice), 900);
        assertEq(sDAIVault.balanceOf(alice) > 0, true);
    }

    function test_swapAndDepositWETH() public {
        // Approve WETH for contract
        vm.prank(alice);
        TransferHelper.safeApprove(address(WETH), address(multiTokenMiddleware), 100);
        // Swap WETH for sDAI
        vm.prank(alice);
        multiTokenMiddleware.swapAndDeposit(100, 100, block.timestamp + 3, address(WETH));
        assertTrue(sDAIVault.balanceOf(alice) > 0);
    }
}
