// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "v3-periphery/libraries/TransferHelper.sol";
import "@uma/core/contracts/optimistic-oracle-v3/implementation/ClaimData.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface ISavingsDai {
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);
    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares);
}

contract FillerPool is Ownable {
    ISavingsDai public immutable savingsDai;
    IERC20 public immutable dai = IERC20(address(0x6B175474E89094C44Da98b954EedeAC495271d0F)); // DAI on Mainnet

    constructor(address _savingsDai) {
        savingsDai = ISavingsDai(_savingsDai);
        // Give approvals to tokens
        TransferHelper.safeApprove(address(dai), address(savingsDai), type(uint256).max);
    }

    mapping(bytes32 => Fill) public depositFills;

    event DepositFilled(address indexed filler, address indexed fillFor, bytes32 indexed fillHash); // Deposit Request on Scroll to mint sDAI.address

    struct Fill {
        bytes32 depositHash; // Txn hash of deposit
        uint256 amount;
        address fillFor; // User for whom request is being filled. Any tokens should be transfered to this address
        address filler; // Relayer
        address token; // DAI/USDC/WETH/GHO
        uint256 fee; // In basis points
        uint256 timestamp;
        bool filled;
    }
    /**
     * @dev Relayer/Filler needs to approve address(this) to transfer _token
     * @param _amount Amount of tokens to fill
     * @param _fillFor User for whom request is being filled. Any tokens should be transfered to this address.
     * @param _filler Relayer address
     * @param _token  Address of token using which the request is being filled.
     * @param _fee Optional fee in basis points taken by the relayer.
     * @param _depositHash Txn hash of deposit by user.
     */

    function fillDeposit(
        bytes32 _depositHash,
        uint256 _amount,
        address _fillFor,
        address _filler,
        address _token, // L1 Token Address
        uint256 _fee
    ) public returns (bytes32, uint256) {
        // If token is Dai
        // Transfer Dai from filler to sDAI vault with receiver as address(this). This locks the sDAI token.
        // Emit DepositFilled event
        // Off-chain - Relayer asserts the DepositFilled event on Scroll and mints wsSAI to _fillFor
        // else use the multitoken-sDAI contract to mint sDAI.
        require(dai.balanceOf(_filler) >= _amount, "Filler has insufficient balance to fill deposit");
        TransferHelper.safeTransferFrom(_token, _filler, address(this), _amount);
        uint256 receivedShares;

        // TODO: Add fee component
        // Check if Dai
        if (_token == address(dai)) {
            // Need _token to be approved by address(this)
            receivedShares = savingsDai.deposit(_amount, address(this));
        } else {
            // Use multitoken-sDAI contract to mint sDAI
            // receivedShares = multitoken-sDAI.deposit(_amount, address(this));
        }
        bytes32 fillHash = keccak256(
            abi.encodePacked(
                "0x",
                ClaimData.toUtf8BytesAddress(_filler),
                " filling deposit 0x",
                ClaimData.toUtf8Bytes(_depositHash),
                " for 0x",
                ClaimData.toUtf8BytesAddress(_fillFor),
                " with amount ",
                ClaimData.toUtf8BytesUint(_amount),
                " at timestamp: ",
                ClaimData.toUtf8BytesUint(block.timestamp),
                " using token: 0x",
                ClaimData.toUtf8BytesAddress(_token), // _token: L1 Token Address
                " receiving ",
                ClaimData.toUtf8BytesUint(receivedShares),
                " shares in the FillerPool contract at 0x",
                ClaimData.toUtf8BytesAddress(address(this))
            )
        );
        depositFills[fillHash] = Fill(_depositHash, _amount, _fillFor, _filler, _token, _fee, block.timestamp, true);
        emit DepositFilled(_filler, _fillFor, fillHash);
        return (fillHash, receivedShares);
    }

    function approve(address _token, address _spender, uint256 _amount) external onlyOwner {
        TransferHelper.safeApprove(_token, _spender, _amount);
    }
}
