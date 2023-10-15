// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "./IPool.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./DataAsserterGoerli.sol";
import "../SavingsDai.sol";

contract TokenPool is IPool {
    using SafeERC20 for IERC20;

    IERC20 public token;
    SavingsDai public savingsDai;
    DataAsserter dataAsserter;
    mapping(address => uint256) public daiBalances;
    uint256 public totalDaiBalance;
    uint256 public totalSavingsDaiBalance; // This should be equal to the amount of ScrollSavingsDai minted on Scroll.

    event LiquidityAdded(address indexed provider, uint256 indexed amount);
    event LiquidityRemoved(address indexed provider, uint256 indexed amount);

    constructor(address _token, address _savingsDai, address _dataAsserter) {
        token = IERC20(_token);
        savingsDai = SavingsDai(_savingsDai);
        dataAsserter = DataAsserter(_dataAsserter);
    }

    /**
     * @notice Add liquidity to the pool
     * @dev Contract needs to be approved to transfer tokens
     * @param _amount Amount of tokens to add
     */
    function addLiquidity(uint256 _amount) external {
        token.safeTransferFrom(msg.sender, address(this), _amount);
        daiBalances[msg.sender] += _amount;
        totalDaiBalance += _amount;
        emit LiquidityAdded(msg.sender, _amount);
    }

    /**
     * @notice Remove liquidity from the pool
     * @param _amount Amount of tokens to remove
     */
    function removeLiquidity(uint256 _amount) external {
        require(daiBalances[msg.sender] >= _amount, "Insufficient balance");
        daiBalances[msg.sender] -= _amount;
        totalDaiBalance -= _amount;
        token.safeTransfer(msg.sender, _amount);
        emit LiquidityRemoved(msg.sender, _amount);
    }

    modifier onlyDataAsserter() {
        require(msg.sender == address(dataAsserter), "Only DataAsserter can call this function");
        _;
    }

    /**
     * @notice Deposit DAI to the SavingsDai contract and receive sDAI in exchange
     * @param _amount Amount of DAI to deposit
     * @dev This contract (TokenPool) needs to approve SavingsDai contract to transfer Dai
     * @dev Can only be called by the DataAsserterGoerli contract from the assertionResolvedCallback function, which is called by the oracle.
     */
    function depositDaiToVault(uint256 _amount) public onlyDataAsserter {
        // Transfer DAI from this Pool to SavingsDai
        savingsDai.deposit(_amount, address(this)); // Receive sDAI in exchange
        totalDaiBalance -= _amount; // Update totalDaiBalance
            // Lock SavingsDai and emit event to notify the oracle
            // The oracle then calls the mint function in the Scroll contract to mint ScrollSavingsDai.
    }

    /**
     * @notice Withdraw DAI from the SavingsDai contract and burn sDAI in exchange
     * @param _amount Amount of sDAI to burn
     * @dev This contract (TokenPool) needs to approve SavingsDai contract to transfer sDAI
     * @dev Can only be called by the DataAsserterGoerli contract from the assertionResolvedCallback function, which is called by the oracle.
     */
    function withdrawSavingsDaiFromVault(uint256 _amount) public onlyDataAsserter {
        // Transfer sDAI from this Pool to SavingsDai
        savingsDai.withdraw(_amount, address(this), msg.sender); // Receive DAI in exchange
        totalDaiBalance += _amount; // Update totalDaiBalance
    }
}
