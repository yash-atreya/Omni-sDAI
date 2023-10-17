// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@uma/core/contracts/optimistic-oracle-v3/implementation/ClaimData.sol";
import "@uma/core/contracts/optimistic-oracle-v3/interfaces/OptimisticOracleV3Interface.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract DataAsserter {
    using SafeERC20 for IERC20;

    IERC20 public immutable defaultCurrency;
    OptimisticOracleV3Interface public immutable oo;
    uint64 public constant assertionLiveness = 30; // 30 seconds.
    bytes32 public immutable defaultIdentifier;

    struct DepositToVaultAssertion {
        bytes32 depositId; // The txn hash of the deposit.
        address depositor;
        uint256 amount;
        address asserter; // The address that made the assertion.
        bool resolved; // Whether the assertion has been resolved.
    }

    mapping(bytes32 => DepositToVaultAssertion) public assertionsData;

    event DepositToVaultAsserted(address indexed depositor, uint256 indexed amount, bytes32 indexed assertionId);

    event DepositToVaultAssertionResolved(
        bytes32 indexed depositId, address indexed asserter, bytes32 indexed assertionId
    );

    constructor(address _defaultCurrency, address _optimisticOracleV3) {
        defaultCurrency = IERC20(_defaultCurrency);
        oo = OptimisticOracleV3Interface(_optimisticOracleV3);
        defaultIdentifier = oo.defaultIdentifier();
    }

    function assertDepositToVault(bytes32 _depositId, address _depositor, uint256 _amount, address _asserter)
        public
        returns (bytes32 assertionId)
    {
        _asserter = _asserter == address(0) ? msg.sender : _asserter;
        uint256 bond = oo.getMinimumBond(address(defaultCurrency));
        defaultCurrency.safeTransferFrom(msg.sender, address(this), bond);
        defaultCurrency.safeApprove(address(oo), bond);

        assertionId = oo.assertTruth(
            abi.encodePacked(
                "0x",
                ClaimData.toUtf8BytesAddress(_asserter),
                " asserting Dai deposited to sDAI vault: 0x", // in the example data is type bytes32 so we add the hex prefix 0x.
                ClaimData.toUtf8Bytes(_depositId),
                " for depositor: 0x",
                ClaimData.toUtf8BytesAddress(_depositor),
                " with amount: ",
                ClaimData.toUtf8BytesUint(_amount),
                " at timestamp: ",
                ClaimData.toUtf8BytesUint(block.timestamp),
                " in the DataAsserter contract at 0x",
                ClaimData.toUtf8BytesAddress(address(this)),
                " is valid."
            ),
            _asserter,
            address(this),
            address(0), // No sovereign security.
            assertionLiveness,
            defaultCurrency,
            bond,
            defaultIdentifier,
            bytes32(0) // No domain.
        );

        assertionsData[assertionId] = DepositToVaultAssertion(_depositId, _depositor, _amount, _asserter, false);
        emit DepositToVaultAsserted(_depositor, _amount, assertionId);
    }

    // OptimisticOracleV3 resolve callback.
    function assertionResolvedCallback(bytes32 assertionId, bool assertedTruthfully) public {
        require(msg.sender == address(oo));
        // If the assertion was true, then the data assertion is resolved.
        if (assertedTruthfully) {
            assertionsData[assertionId].resolved = true;
            DepositToVaultAssertion memory dataAssertion = assertionsData[assertionId];
            emit DepositToVaultAssertionResolved(dataAssertion.depositId, dataAssertion.asserter, assertionId);
            // Mint `amount` of wrapped sDAI to the depositor on scroll.
        } else {
            delete assertionsData[assertionId];
        }
    }

    // TODO: Disputed Callback
    // This OptimisticOracleV3 callback function needs to be defined so the OOv3 doesn't revert when it tries to call it.
    // function assertionDisputedCallback(bytes32 assertionId) public {}
}
