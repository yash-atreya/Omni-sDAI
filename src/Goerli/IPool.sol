// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

/**
 * @title Mainnet DAI Bridge Pool
 */
interface IPool {
    function addLiquidity(uint256 amount) external;
    function removeLiquidity(uint256 amount) external;
}
