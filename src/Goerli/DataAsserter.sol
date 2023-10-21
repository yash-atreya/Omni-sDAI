// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@uma/core/contracts/optimistic-oracle-v3/implementation/ClaimData.sol";
import "@uma/core/contracts/optimistic-oracle-v3/interfaces/OptimisticOracleV3Interface.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
// This contract allows assertions on any form of data to be made using the UMA Optimistic Oracle V3 and stores the
// proposed value so that it may be retrieved on chain. The dataId is intended to be an arbitrary value that uniquely
// identifies a specific piece of information in the consuming contract and is replaceable. Similarly, any data
// structure can be used to replace the asserted data.

contract DataAsserter {
    using SafeERC20 for IERC20;

    IERC20 public immutable defaultCurrency; // Oracle's default currency for posting bonds.
    OptimisticOracleV3Interface public immutable oo;
    uint64 public constant assertionLiveness = 30; // 30 seconds.
    bytes32 public immutable defaultIdentifier; // The identifier used by the OptimisticOracleV3. - "ASSERT_TRUTH"
    address public immutable savingsDai; // SavingsDai contract address.
    address public immutable fillerPool; // FillerPool contract address.

    struct DepositAssertion {
        bytes32 depositId; // The txn hash of the deposit.
        address depositor;
        uint256 amount;
        address asserter; // The address that made the assertion.
        bool resolved; // Whether the assertion has been resolved.
    }

    struct WithdrawalAssertion {
        bytes32 withdrawalId; // The txn hash of the withdrawal.
        address withdrawer;
        uint256 amount; // Number of shares to withdraw.
        address asserter; // The address that made the assertion.
        bool resolved; // Whether the assertion has been resolved.
    }

    mapping(bytes32 => WithdrawalAssertion) public withdrawalAssertionsData;

    event WithdrawalAsserted(address indexed withdrawer, uint256 indexed amount, bytes32 indexed assertionId);
    event WithdrawalAssertionResolved(
        bytes32 indexed withdrawalId, address indexed asserter, bytes32 indexed assertionId
    );

    constructor(address _defaultCurrency, address _optimisticOracleV3, address _savingsDai, address _fillerPool) {
        defaultCurrency = IERC20(_defaultCurrency);
        oo = OptimisticOracleV3Interface(_optimisticOracleV3);
        defaultIdentifier = oo.defaultIdentifier();
        savingsDai = _savingsDai;
        fillerPool = _fillerPool;
    }

    // For a given assertionId, returns a boolean indicating whether the data is accessible and the data itself.
    // function getData(bytes32 assertionId) public view returns (bool, bytes32) {
    //     if (!assertionsData[assertionId].resolved) return (false, 0);
    //     return (true, assertionsData[assertionId].data);
    // }

    function assertWithdrawal(bytes32 _withdrawalId, address _withdrawer, uint256 _amount, address _asserter)
        public
        returns (bytes32 assertionId)
    {
        _asserter = _asserter == address(0) ? msg.sender : _asserter; // _asserter is the relayer.
        uint256 bond = oo.getMinimumBond(address(defaultCurrency));
        defaultCurrency.safeTransferFrom(msg.sender, address(this), bond);
        defaultCurrency.safeApprove(address(oo), bond);

        assertionId = oo.assertTruth(
            abi.encodePacked(
                "0x",
                ClaimData.toUtf8BytesAddress(_asserter),
                " asserting withdrawal by withdrawer: 0x",
                ClaimData.toUtf8BytesAddress(_withdrawer),
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

        withdrawalAssertionsData[assertionId] =
            WithdrawalAssertion(_withdrawalId, _withdrawer, _amount, _asserter, false);

        emit WithdrawalAsserted(_withdrawer, _amount, assertionId);
    }
    // Asserts data for a specific dataId on behalf of an asserter address.
    // Data can be asserted many times with the same combination of arguments, resulting in unique assertionIds. This is
    // because the block.timestamp is included in the claim. The consumer contract must store the returned assertionId
    // identifiers to able to get the information using getData.

    // function assertDepositAndFill(bytes32 _depositId, address _depositor, uint256 _amount, address _asserter)
    //     public
    //     returns (bytes32 assertionId)
    // {
    //     _asserter = _asserter == address(0) ? msg.sender : _asserter; // _asserter is the relayer.
    //     uint256 bond = oo.getMinimumBond(address(defaultCurrency));
    //     defaultCurrency.safeTransferFrom(msg.sender, address(this), bond);
    //     defaultCurrency.safeApprove(address(oo), bond);

    //     // The claim we want to assert is the first argument of assertTruth. It must contain all of the relevant
    //     // details so that anyone may verify the claim without having to read any further information on chain. As a
    //     // result, the claim must include both the data id and data, as well as a set of instructions that allow anyone
    //     // to verify the information in publicly available sources.
    //     // See the UMIP corresponding to the defaultIdentifier used in the OptimisticOracleV3 "ASSERT_TRUTH" for more
    //     // information on how to construct the claim.
    //     assertionId = oo.assertTruth(
    //         abi.encodePacked(
    //             "0x",
    //             ClaimData.toUtf8BytesAddress(_asserter),
    //             " asserting deposit on scroll: 0x", // in the example data is type bytes32 so we add the hex prefix 0x.
    //             ClaimData.toUtf8Bytes(_depositId),
    //             " for depositor: 0x",
    //             ClaimData.toUtf8BytesAddress(_depositor),
    //             " with amount: ",
    //             ClaimData.toUtf8BytesUint(_amount),
    //             " at timestamp: ",
    //             ClaimData.toUtf8BytesUint(block.timestamp),
    //             " in the DataAsserter contract at 0x",
    //             ClaimData.toUtf8BytesAddress(address(this)),
    //             " is valid."
    //         ),
    //         _asserter,
    //         address(this),
    //         address(0), // No sovereign security.
    //         assertionLiveness,
    //         defaultCurrency,
    //         bond,
    //         defaultIdentifier,
    //         bytes32(0) // No domain.
    //     );
    //     assertionsData[assertionId] = DepositAssertion(_depositId, _depositor, _amount, _asserter, false);
    //     emit DepositAsserted(_depositor, _amount, assertionId);

    //     // Fill the deposit `_amount` wDai by using Dai to mint sDAI and forwarding it to the user.
    //     // Assert the filled deposit request on Scroll's OOv3, which mints wsDai to the user.
    // }

    // OptimisticOracleV3 resolve callback.
    function assertionResolvedCallback(bytes32 assertionId, bool assertedTruthfully) public {
        require(msg.sender == address(oo));
        // If the assertion was true, then the data assertion is resolved.
        if (assertedTruthfully) {
            withdrawalAssertionsData[assertionId].resolved = true;
            WithdrawalAssertion memory dataAssertion = withdrawalAssertionsData[assertionId];
            emit WithdrawalAssertionResolved(dataAssertion.withdrawalId, dataAssertion.asserter, assertionId);
            // Deposit `amount` Dai from Pool in sDAI Vault with the receiver as the depositor on scroll.
            // daiPool.depositDaiToVault(dataAssertion.amount, dataAssertion.depositor);
            // Else delete the data assertion if it was false to save gas.
            (bool success,) = savingsDai.call(
                abi.encodeWithSignature(
                    "redeem(uint256,address,address)",
                    dataAssertion.amount,
                    address(fillerPool),
                    address(fillerPool) // `receiver` and `owner` are both the FillerPool contract.
                )
            );

            require(success, "Failed to withdraw Dai from sDai Vault to FillerPool.");
            // Emit event with how much Dai was received after withdrawing from the sDai Vault.
            // Lock that Dai in the filler pool.
            // Ask relayer to fill wDai to the user.
            // Let relayer withdraw the locked Dai from the filler pool.
        } else {
            delete withdrawalAssertionsData[assertionId];
        }
    }

    // If assertion is disputed, do nothing and wait for resolution.
    // This OptimisticOracleV3 callback function needs to be defined so the OOv3 doesn't revert when it tries to call it.
    // function assertionDisputedCallback(bytes32 assertionId) public {}
}
