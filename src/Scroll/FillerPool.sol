// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "./ScrollSavingsDai.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "v3-periphery/libraries/TransferHelper.sol";
import "@uma/core/contracts/optimistic-oracle-v3/implementation/ClaimData.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract FillerPool is Ownable {
    using SafeERC20 for IERC20;

    IERC20 public immutable wrappedDai; // Wrapped DAI contract address on Scroll
    IERC20 public immutable wrappedSavingsDai; // Wrapped SavingsDai contract address on Scroll

    mapping(bytes32 => Fill) public fills;

    constructor(address _wrappedDai, address _wrappedSavingsDai) {
        wrappedDai = IERC20(_wrappedDai);
        wrappedSavingsDai = IERC20(_wrappedSavingsDai);
    }

    struct Fill {
        bytes32 withdrawalHash; // Hash of the txn where user has requested a withdrawal
        uint256 amount; // Number of shares to withdraw
        address fillFor; // User for whom request is being filled. Any tokens should be transfered to this address
        address filler; // Relayer
        address token; // DAI/USDC/WETH/GHO
        uint256 fee; // In basis points
        uint256 timestamp;
        bool filled;
    }

    event FilledWithdrawal(address indexed filler, bytes32 indexed fillHash, uint256 indexed amount);

    /**
     * @dev Relayer needs to approve this contract to transfer wDai.
     * @dev Relayer calls this when it catches a successful withdrawal by oracle on mainnet for the user. i.e `WithdrawalAssertionResolved` event
     */
    function fillWithdrawal(bytes32 _withdrawalHash, uint256 _amount, address _fillFor, address _token, uint256 _fee)
        public
    {
        // Transfer the wDai to the user
        TransferHelper.safeTransferFrom(address(wrappedDai), msg.sender, _fillFor, _amount);
        bytes32 fillHash = keccak256(
            abi.encodePacked(
                "0x",
                ClaimData.toUtf8BytesAddress(msg.sender), // Filler,
                " filling withdrawal request at ",
                ClaimData.toUtf8Bytes(_withdrawalHash),
                " for ",
                ClaimData.toUtf8BytesAddress(_fillFor),
                " with amount",
                ClaimData.toUtf8BytesUint(_amount),
                " of token ",
                ClaimData.toUtf8BytesAddress(_token),
                " with fee ",
                ClaimData.toUtf8BytesUint(_fee)
            )
        );

        fills[fillHash] = Fill({
            withdrawalHash: _withdrawalHash,
            amount: _amount,
            fillFor: _fillFor,
            filler: msg.sender,
            token: _token,
            fee: _fee,
            timestamp: block.timestamp,
            filled: true
        });

        emit FilledWithdrawal(msg.sender, fillHash, _amount);
        // Next Relayer Asserts this Fill on the Mainnet oracle to get reimbursed with the withdrawn Dai.
    }

    function approve(address _token, address _spender, uint256 _amount) external onlyOwner {
        TransferHelper.safeApprove(_token, _spender, _amount);
    }
}
