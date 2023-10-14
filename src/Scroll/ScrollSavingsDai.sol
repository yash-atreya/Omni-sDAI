// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract ScrollSavingsDai {
    using SafeERC20 for IERC20;

    IERC20 public immutable dai;
    mapping(address => uint256) public deposits;

    event Deposited(address indexed depositor, uint256 indexed amount);

    constructor(address _dai) {
        dai = IERC20(_dai);
    }

    function deposit(uint256 _amount) external {
        dai.safeTransferFrom(msg.sender, address(this), _amount);
        deposits[msg.sender] += _amount;
        emit Deposited(msg.sender, _amount);
    }
}
