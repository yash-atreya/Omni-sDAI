// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract ScrollSavingsDai is ERC20, Ownable {
    using SafeERC20 for IERC20;

    IERC20 public immutable dai; // Scroll Dai
    address public dataAsserter;
    mapping(address => uint256) public deposits;

    event Deposited(address indexed depositor, uint256 indexed amount);

    constructor(address _dai) ERC20("Wrapped Savings Dai", "wsDAI") {
        dai = IERC20(_dai);
    }

    function setDataAsserter(address _dataAsserter) external onlyOwner {
        dataAsserter = _dataAsserter;
    }

    function deposit(uint256 _amount) external {
        dai.safeTransferFrom(msg.sender, address(this), _amount);
        deposits[msg.sender] += _amount;
        emit Deposited(msg.sender, _amount);
    }

    modifier onlyDataAsserter() {
        require(msg.sender == dataAsserter, "Caller is not data asserter");
        _;
    }
    // ERC20 functions

    function mint(address _receiver, uint256 shares) external onlyDataAsserter {
        _mint(_receiver, shares);
    }

    function burn(address _receiver, uint256 shares) external onlyDataAsserter {
        _burn(_receiver, shares);
    }
}
