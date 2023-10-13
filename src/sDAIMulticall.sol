// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import "forge-std/console.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ISavingsDai {
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);
}

/// @title OmniSavingsDAI
/// @notice This contract swaps USDC for DAI and deposits the DAI into the SavingsDAI vault and sends sDAI to  msg.sender
/// @dev This contract needs to be approved to spend USDC by the msg.sender
contract OmniSavingsDai {
    ISavingsDai immutable SDAI_VAULT = ISavingsDai(0x83F20F44975D03b1b09e64809B757c47f942BEeA);
    IERC20 immutable USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    // address immutable USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    IERC20 immutable DAI = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    // address immutable DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    ISwapRouter immutable swapRouter = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);

    /// @notice Swaps USDC for DAI and deposits the DAI into the SavingsDAI vault and sends sDAI to  msg.sender
    /// @param _amountIn The amount of USDC to swap for DAI
    /// @param _amountOutMinimum The minimum amount of DAI to receive from the swap, determined using uni-v3 sdk
    /// @param _deadline The deadline for the swap
    /// @param _tokenIn The address of the token to swap for DAI
    function swapAndDepositUSDC(uint256 _amountIn, uint256 _amountOutMinimum, uint256 _deadline, address _tokenIn)
        public
    {
        // Transfer USDC from msg.sender to this contract
        TransferHelper.safeTransferFrom(_tokenIn, msg.sender, address(this), 100);

        // Approve USDC for swapRouter
        TransferHelper.safeApprove(_tokenIn, address(swapRouter), 100);

        // Swap USDC for DAI
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: _tokenIn,
            tokenOut: address(DAI),
            fee: 100,
            recipient: address(this),
            deadline: _deadline,
            amountIn: _amountIn,
            amountOutMinimum: _amountOutMinimum,
            sqrtPriceLimitX96: 0
        });

        uint256 amountOut = swapRouter.exactInputSingle(params);

        // Approve DAI for SDAI_VAULT
        TransferHelper.safeApprove(address(DAI), address(SDAI_VAULT), amountOut);

        // Deposit DAI into SDAI_VAULT
        SDAI_VAULT.deposit(amountOut, msg.sender);
    }
}
